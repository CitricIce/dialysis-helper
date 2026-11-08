import Combine
import Foundation
import UIKit

final class CoachViewModel: ObservableObject {
    let capture = CaptureController()
    let speech = CoachSpeech()
    let band = BandClient()
    let conversation = CartesiaConversation()
    private let vision = CoachVisionPipeline()
    @Published private(set) var session: RoutineSession?
    @Published private(set) var observation = CoachVisionSnapshot()
    @Published var selectedSlot = "Exchange 1"
    @Published var response = ""
    @Published var allowCloudQuestions = false
    @Published private(set) var message = "Start a practice routine to try the checks."
    @Published private(set) var scannedLabel = ""
    @Published private(set) var logURL: URL?
    private var subscriptions: Set<AnyCancellable> = []
    private var health: Timer?
    private var warningTime = -Double.infinity
    private var lastHazardTime = -Double.infinity
    private var clearSince: Double?
    private let logQueue = DispatchQueue(label: "org.armguard.coach.events", qos: .utility)
    private var runID = UUID()

    init() {
        do {
            guard let url = Bundle.main.url(forResource: "RoutineTemplate", withExtension: "json", subdirectory: "Resources")
                ?? Bundle.main.url(forResource: "RoutineTemplate", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            session = try RoutineSession(template: JSONDecoder().decode(RoutineTemplate.self, from: Data(contentsOf: url)))
        } catch { message = "Practice template could not load. \(error.localizedDescription)" }
        capture.frameObserver = { [weak vision = self.vision] frame in vision?.submit(frame) }
        vision.onResult = { [weak self] output in self?.received(output) }
        speech.onResponse = { [weak self] text in self?.handle(text) }
        speech.canListen = { [weak self] in
            guard let self else { return false }
            return self.session?.phase == .checking && !self.conversation.active
        }
        for publisher in [capture.objectWillChange.eraseToAnyPublisher(), speech.objectWillChange.eraseToAnyPublisher(),
                          band.objectWillChange.eraseToAnyPublisher(), conversation.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        }
        health = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.checkHealth() }
    }

    var fresh: Bool {
        let age = ProcessInfo.processInfo.systemUptime - observation.receipt
        return capture.isRunning && observation.receipt > 0 && age >= 0 && age <= 0.25
    }
    var canArm: Bool {
        guard fresh, observation.modelInstalled, observation.handCoverageComplete,
              session?.phase == .checking, session?.currentCheck?.responseKind == .monitoring else { return false }
        if case .clear = observation.decision { return true }
        return false // Start with a clear view and a gap outside the experimental warning band.
    }
    var riskText: String {
        guard fresh else { return "Observation unavailable or older than 250 ms" }
        switch observation.decision {
        case .unavailable(let reason): return reason
        case .clear: return observation.handCoverageComplete ? "No proximity flag in current observations · experimental" : "Incomplete fingertip coverage; show both hands"
        case .warning(_, let meters): return String(format: "Estimated proximity %.0f mm · experimental", meters * 1000)
        case .projectedOverlap: return "Image overlap · possible contact cannot be determined from this view"
        }
    }
    var diagnostics: String {
        """
        ArmGuard practice coach · slot \(selectedSlot)
        Phase: \(session?.phase.rawValue ?? "unavailable")
        Check: \(session?.currentCheck?.id ?? "none")
        Model: \(observation.modelStatus)
        Hands: \(observation.provider); complete two-hand coverage: \(observation.handCoverageComplete)
        Last pipeline processing: \(String(format: "%.1f", observation.processingMilliseconds)) ms
        Observation: \(riskText)
        Band: \(band.status)
        No prescription configured. No sterility or contact verification.
        """
    }

    func start() {
        guard session?.phase == .idle else { return }
        session?.start(); persist(); prompt()
    }
    func reset() {
        pauseHardware()
        guard let template = session?.template else { return }
        session = try? RoutineSession(template: template)
        runID = UUID(); logURL = nil; response = ""; scannedLabel = ""
        message = "New practice only. Reset does not resolve a real contamination concern."
    }
    func startCamera() {
        vision.setActive(true)
        capture.start()
    }
    func scanLabel() {
        guard capture.isRunning, session?.phase == .checking else { return }
        vision.requestLabelRead()
        message = "Reading visible text only. Inspect it yourself; no prescription comparison is configured."
    }
    func submit() { let text = response; response = ""; handle(text) }
    func handle(_ text: String) {
        guard !conversation.active else { return }
        switch VoiceIntent.parse(text) {
        case .pause: pause()
        case .help: explain()
        case .askQuestion: askQuestion()
        case .repeatPrompt: prompt()
        case .confirm: confirm()
        case .arm: arm()
        case .finishPreparation: finishPreparation()
        case .finishMonitoring: finishMonitoring()
        case .answer(let answer):
            guard session?.phase == .checking else { return }
            message = session?.submit(answer) ?? "Routine unavailable"
            persist(); speech.speak(message)
        }
    }
    func confirm() {
        if session?.confirmReadBack() == true { persist(); prompt() }
        else { message = "First provide a read-back for this check." }
    }
    func prompt() {
        conversation.stop()
        message = session?.currentCheck?.prompt ?? "Practice finished. This record does not verify sterility."
        speech.speak(message)
    }
    func explain() {
        conversation.stop()
        message = session?.currentCheck?.help ?? "Use your PD team's instructions. No protocol is configured here."
        speech.speak(message)
    }
    func askQuestion() {
        guard allowCloudQuestions else {
            message = "Cloud questions are off. Enable them before preparation, or say help for an offline explanation."
            speech.speak(message, urgent: true)
            return
        }
        guard let check = session?.currentCheck,
              session?.phase == .checking || session?.phase == .paused,
              let base = CoachSpeech.allowedGateway(speech.gatewayURL), !speech.gatewayToken.isEmpty else {
            message = "Configure the voice gateway first. Offline Explain is always available."
            speech.speak(message, urgent: true)
            return
        }
        speech.stop()
        conversation.start(base: base, gatewayToken: speech.gatewayToken, checkID: check.id)
    }
    func arm() {
        conversation.stop(); speech.stop()
        guard session?.armMonitoring(visionReady: canArm) == true else {
            message = "Cannot arm: need a fresh clear observation, trained model, usable depth and both hands fully tracked."
            return
        }
        warningTime = -Double.infinity; lastHazardTime = -Double.infinity; clearSince = nil
        message = "Experimental monitoring active. Follow your own clinic instructions."
        persist()
    }
    func finishMonitoring() {
        guard session?.finishMonitoring() == true else { return }
        band.stop(); persist(); prompt()
    }
    func finishPreparation() {
        guard session?.phase == .checking, session?.currentCheck?.responseKind == .monitoring else { return }
        session?.finishPreparationOnly(); band.stop(); persist()
        message = "Preparation practice ended. Connection and disconnection were not monitored."
        speech.stop(); conversation.stop()
    }
    func pause() {
        session?.pause(); band.stop(); speech.stop(); conversation.stop(); persist()
        message = "Paused. Resume explicitly; previous monitoring must be rearmed."
    }
    func resume() {
        session?.resume(); persist()
        if session?.reviewRequired == true {
            message = "Possible overlap still needs review. Follow your PD team's instructions; resume cannot clear this flag."
            speech.speak(message, urgent: true)
        } else { prompt() }
    }
    func backgrounded() {
        pause(); pauseHardware()
    }
    private func pauseHardware() {
        vision.setActive(false); capture.stop(reason: "Capture paused. Press Start camera to resume.")
        band.stop(); speech.stop(); conversation.stop()
    }
    private func checkHealth() {
        guard session?.phase == .monitoring else { return }
        if !fresh { loseObservation("Observation lost or delayed. Pause and restore a clear view before rearming.") }
    }
    private func loseObservation(_ reason: String) {
        session?.observationLost(); band.stop(); conversation.stop(); persist()
        message = reason
        speech.speak(reason, urgent: true)
    }
    private func received(_ output: CoachVisionSnapshot) {
        observation = output
        if !output.labelText.isEmpty { scannedLabel = output.labelText }
        guard session?.phase == .monitoring else { return }
        guard fresh else { loseObservation("Vision is delayed. Monitoring paused; restore the view before rearming."); return }
        let now = ProcessInfo.processInfo.systemUptime
        if !output.handCoverageComplete, output.decision != .projectedOverlap {
            loseObservation("Fingertip coverage lost. Pause and show both hands before rearming.")
            return
        }
        switch output.decision {
        case .projectedOverlap:
            session?.flagPossibleContact(); band.set(intensity: 255, suspected: true)
            conversation.stop(); persist()
            message = "The hand overlaps a protected opening in the image. Pause and check using your PD team's instructions. This view cannot confirm contact."
            speech.speak(message, urgent: true)
        case .unavailable(let reason): loseObservation("Monitoring paused: " + reason)
        case .warning(let intensity, _):
            lastHazardTime = now; clearSince = nil
            band.set(intensity: intensity)
            if now - warningTime >= 5 {
                warningTime = now; conversation.stop()
                message = "Your fingers are close to a protected opening. Pause and move your hand away from the opening."
                speech.speak(message, urgent: true)
            }
        case .clear:
            guard output.handCoverageComplete else { loseObservation("Fingertip coverage lost. Pause and show both hands before rearming."); return }
            if clearSince == nil { clearSince = now }
            if now - (clearSince ?? now) >= 0.3 { band.stop() }
            else if now - lastHazardTime < 0.3 { band.set(intensity: 80) }
        }
    }
    private func persist() {
        guard let session, let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let currentRun = runID
        let url = directory.appendingPathComponent("practice-\(currentRun.uuidString).json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(session.events) else { return }
        // Only event types/timestamps/evidence categories. No voice, read-back text or images.
        logQueue.async {
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.runID == currentRun else { return }
                    self.logURL = url
                }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.message = "Practice event log could not be saved." }
            }
        }
    }
}
