import Combine
import Foundation
import UIKit

final class CoachViewModel: ObservableObject {
    let capture = CaptureController()
    let speech = CoachSpeech()
    let band = BandClient()
    let conversation = CartesiaConversation()
    private let vision = CoachVisionPipeline(includeDebugPreview: true)
    @Published var detectionConfidence = DetectionConfidence.preview {
        didSet {
            if session?.template.detectorStatus != .experimental {
                DetectionConfidence.preview = detectionConfidence
                vision.setConfidenceThreshold(Float(detectionConfidence))
            }
        }
    }
    @Published private(set) var session: RoutineSession?
    @Published private(set) var stats = SafetyStats()
    @Published private(set) var statsStarted = Date()
    @Published private(set) var observation = CoachVisionSnapshot()
    @Published var selectedSlot = "Exchange 1"
    @Published var response = ""
    @Published var allowCloudQuestions = UserDefaults.standard.bool(forKey: "cloudVoiceConsent") {
        didSet {
            UserDefaults.standard.set(allowCloudQuestions, forKey: "cloudVoiceConsent")
            if !allowCloudQuestions {
                conversation.stop(); resumeCloudAfterCue = false
                if voiceEnabled { speech.stop(); speech.listen() }
            }
        }
    }
    @Published private(set) var voiceEnabled = false
    @Published private(set) var ended = false
    @Published var debugControlsEnabled = false
    private var replyGate = SpokenReplyGate()
    private var progressionGate = SpokenReplyGate()
    private var lastUserCheckID = ""
    private var lastUserWords = ""
    private var lastUserTurn = -1
    private var nativeCommand: (checkID: String, words: String)?
    private var resumeCloudAfterCue = false
    @Published private(set) var message = "Set up your voice, then start when you're ready."
    @Published private(set) var scannedLabel = ""
    @Published private(set) var logURL: URL?
    private var subscriptions: Set<AnyCancellable> = []
    private var health: Timer?
    private var warningTime = -Double.infinity
    private var lastHazardTime = -Double.infinity
    private var clearSince: Double?
    private let logQueue = DispatchQueue(label: "org.armguard.coach.events", qos: .utility)
    private var runID = UUID()
    private var lastRiskLevel: RiskLevel = .none
    private var lastDistanceRisk: RiskLevel = .none
    private var cuePolicy = WarningCuePolicy()
    private let haptics = UINotificationFeedbackGenerator()

    init() {
        do {
            guard let url = Bundle.main.url(forResource: "RoutineTemplate", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            session = try RoutineSession(template: JSONDecoder().decode(RoutineTemplate.self, from: Data(contentsOf: url)))
        } catch { message = "Practice template could not load. \(error.localizedDescription)" }
        UserDefaults.standard.removeObject(forKey: "sterileTipSizeMM") // old editable size; tips are now fixed
        capture.frameObserver = { [weak vision = self.vision] frame in vision?.submit(frame) }
        vision.onResult = { [weak self] output in self?.received(output) }
        speech.onResponse = { [weak self] text in self?.handle(text) }
        speech.canListen = { [weak self] in
            guard let self else { return false }
            return self.voiceEnabled && self.session?.phase != .idle && !self.conversation.active
        }
        speech.onFinished = { [weak self] in
            guard let self, self.resumeCloudAfterCue, self.voiceEnabled else { return }
            self.resumeCloudAfterCue = false
            self.connectVoice()
        }
        conversation.onNeedsResume = { [weak self] notice in self?.audioNeedsResume(notice) }
        speech.onFailure = { [weak self] notice in self?.audioNeedsResume(notice) }
        conversation.onReady = { [weak self] in
            self?.startCamera()
            self?.speech.prepareAlertClips()
        }
        conversation.onFailure = { [weak self] reason in
            guard let self, self.voiceEnabled else { return }
            self.resumeCloudAfterCue = false
            self.message = reason + " I'm using the phone voice for now. " + self.currentPrompt
            self.speech.speak(self.message, urgent: true)
        }
        conversation.onUserUtterance = { [weak self] text, turn in
            guard let self, self.voiceEnabled, !self.ended, turn > self.lastUserTurn else { return }
            self.lastUserTurn = turn
            self.lastUserCheckID = self.session?.currentCheck?.id ?? "finished"
            self.lastUserWords = text
            self.replyGate.receive(text, turn: turn)
            self.progressionGate.receive(text, turn: turn)
            // These commands belong to the app, and do not wait for an agent tool call.
            let intent = VoiceIntent.parse(text)
            let readBackReply: Bool
            switch intent {
            case .answer, .confirm:
                readBackReply = self.session?.phase == .checking && self.session?.currentCheck?.responseKind == .readBack
            default: readBackReply = false
            }
            let rehearsalReply = self.session?.phase == .unmonitoredPractice ||
                (self.session?.phase == .checking && self.session?.currentCheck?.responseKind == .monitoring && self.session?.template.detectorStatus != .experimental)
            if readBackReply || rehearsalReply || [.pause, .resume, .endSession, .skipStep, .skipCamera].contains(intent) {
                let checkID = self.session?.currentCheck?.id ?? "finished"
                guard self.replyGate.consume(text, expectedCheckID: checkID, currentCheckID: checkID) != nil else { return }
                self.nativeCommand = (checkID, VoiceIntent.normalize(text))
                self.handle(text)
            } else { self.nativeCommand = nil }
        }
        conversation.onTool = { [weak self] name, parameters in
            self?.runTool(name, parameters: parameters) ?? ("Routine unavailable", true)
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
    var observationAge: Double? {
        guard observation.receipt > 0 else { return nil }
        return max(0, ProcessInfo.processInfo.systemUptime - observation.receipt)
    }
    var displayFresh: Bool { capture.isRunning && (observationAge.map { $0 <= 1 } ?? false) }
    var canArm: Bool {
        guard fresh, observation.modelUsable, observation.handCoverageComplete,
              session?.phase == .checking, session?.currentCheck?.responseKind == .monitoring else { return false }
        if case .clear = observation.decision { return true }
        return false // Start with a clear view and a gap outside the experimental warning band.
    }
    /// Camera-distance (SPINOSAURUS) level from the fixed tip sizes; needs a fresh observation.
    /// Unlike the LiDAR path it runs in every phase, so it warns during rehearsal too.
    var distanceRisk: RiskLevel {
        ProximityFeedback.distanceLevel(fresh: fresh, distanceMM: observation.distanceMM, risk: observation.scaleRisk)
    }
    var riskLevel: RiskLevel {
        ProximityFeedback.combinedLevel(phase: session?.phase, fresh: fresh, decision: observation.decision,
            distanceMM: observation.distanceMM, scaleRisk: observation.scaleRisk)
    }
    var distanceText: String {
        guard fresh, let mm = observation.distanceMM else { return "Camera distance: waiting for a hand and a connector tip in view" }
        let label = distanceRisk == .high ? "HIGH" : distanceRisk == .medium ? "MEDIUM" : "clear"
        let tip = observation.referenceTip?.detail ?? "connector tip"
        return String(format: "Camera distance %.0f mm · %@ · scale from %@ · experimental", mm, label, tip)
    }

    /// What the Live Guard screen should tell the user right now, in priority order.
    enum GuardState: Equatable {
        case cameraStarting, lookingForTip, lookingForHand
        case measuring(RiskLevel, Double)
    }
    var guardState: GuardState {
        guard capture.isRunning, displayFresh else { return .cameraStarting }
        guard !observation.regions.isEmpty else { return .lookingForTip }
        guard fresh, let mm = observation.distanceMM else { return .lookingForHand }
        return .measuring(distanceRisk, mm)
    }
    func resetStats() { stats = SafetyStats(); statsStarted = Date() }
    /// Opening Live Guard starts the camera; distance warnings, band and voice work without a routine.
    func openLiveGuard() { if !capture.isRunning && !capture.isStarting { startCamera() } }
    func closeLiveGuard() {
        // An active routine keeps its camera; otherwise stop it so nothing keeps watching.
        guard session?.phase == .idle || ended else { return }
        vision.setActive(false); capture.stop(reason: "Camera stopped"); band.stop()
    }
    var summaryText: String {
        let date = statsStarted.formatted(date: .abbreviated, time: .shortened)
        let measured = Int(stats.measuredSeconds.rounded())
        var lines = ["Sterling practice summary · \(date)"]
        if measured == 0 {
            lines.append("No distance was measured (keep a connector tip and a hand in view).")
        } else {
            lines.append("Distance measured for \(measured / 60) min \(measured % 60) s")
            if let closest = stats.closestMM { lines.append(String(format: "Closest approach to the sterile tip: %.0f mm", closest)) }
            lines.append("Warnings: \(stats.highAlerts) high risk (≤ \(Int(WarningDistances.highMM)) mm), \(stats.mediumAlerts) medium risk (≤ \(Int(WarningDistances.mediumMM)) mm)")
            if let safe = stats.safeFraction { lines.append(String(format: "Time outside warning zones: %.0f%%", safe * 100)) }
            lines.append(String(format: "Longest stretch without a warning: %.0f s", stats.longestSafeStreak))
        }
        if session?.reviewRequired == true { lines.append("A possible-contact review was flagged during practice.") }
        lines.append("Practice feedback from a 2D camera estimate. It does not confirm contact or sterility.")
        return lines.joined(separator: "\n")
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
        Sterling practice coach · slot \(selectedSlot)
        Phase: \(session?.phase.rawValue ?? "unavailable")
        Check: \(session?.currentCheck?.id ?? "none")
        Model: \(observation.modelStatus)
        Hands: \(observation.provider); complete two-hand coverage: \(observation.handCoverageComplete)
        Detections: \(observation.regions.count) openings; \(observation.hands.count) hand boxes; \(observation.fingertips.count) fingertips
        Last pipeline processing: \(String(format: "%.1f", observation.processingMilliseconds)) ms
        Observation: \(riskText)
        \(distanceText)
        Band: \(band.status)
        \(band.diagnostics)
        Detector confidence: \(Int(detectionConfidence * 100))%; frame age: \(observationAge.map { String(format: "%.0f ms", $0 * 1000) } ?? "none")
        Voice audio:
        \(conversation.audioDiagnostics)
        Native voice: \(speech.status); listening: \(speech.isListening)
        No prescription configured. No sterility or contact verification.
        """
    }

    var voiceConfigured: Bool {
        allowCloudQuestions && speech.connectionReady
    }
    var currentPrompt: String {
        if session?.reviewRequired == true { return "Pause and follow your dialysis team's instructions about possible contact. I can't confirm contact from this view." }
        if session?.phase == .paused { return "We're paused. Say resume when you're ready." }
        if session?.phase == .monitoring { return "I'm watching. Say 'done' when you've finished, or say 'pause'." }
        if session?.phase == .unmonitoredPractice { return session?.responseInstruction ?? "Say done when you've finished this unmonitored practice step." }
        if session?.phase == .preparationOnly { return "Preparation practice is finished. The connection wasn't monitored. Is there anything you'd like to ask?" }
        return session?.responsePrompt ?? "We're finished. Is there anything else you'd like to ask?"
    }
    var cameraMessage: String {
        if session?.reviewRequired == true { return "Possible contact needs review" }
        guard capture.isRunning else { return capture.isStarting ? "Starting camera" : "Camera is not running" }
        guard fresh else { return "Camera analysis is delayed. Distance warnings are unavailable until it catches up." }
        guard !observation.regions.isEmpty else { return "Looking for a connector tip. No distance warning is available yet." }
        guard observation.distanceMM != nil else { return "Show your hand and the connector tip together so I can estimate the gap." }
        if distanceRisk == .high { return "High risk. Move your hand back." }
        if distanceRisk == .medium { return "Medium risk. Keep a gap." }
        return "Experimental distance estimate available. No close approach detected in this frame."
    }
    func start(usePhoneVoice: Bool = false) {
        guard session?.phase == .idle else { return }
        guard usePhoneVoice || voiceConfigured else {
            message = "Open Voice setup to connect Cartesia, or choose Try phone voice."
            return
        }
        ended = false; voiceEnabled = true
        band.beginRoutineConnection()
        resetStats()
        session?.start(); persist()
        message = currentPrompt
        startCamera()
        if usePhoneVoice { speech.speak(message, urgent: true) }
        else { connectVoice() }
    }
    func connectVoice() {
        guard voiceEnabled, voiceConfigured, let session,
              let request = speech.agentSessionRequest(checkID: session.currentCheck?.id ?? "finished",
                  phase: session.phase, prompt: currentPrompt, checks: session.template.checks,
                  detectorStatus: session.template.detectorStatus ?? .placeholder) else { return }
        speech.stop(); replyGate = SpokenReplyGate(); progressionGate = SpokenReplyGate()
        lastUserCheckID = ""; lastUserWords = ""; lastUserTurn = -1; nativeCommand = nil
        conversation.start(request: request)
    }
    func reset() {
        endSession()
        guard let template = session?.template else { return }
        session = try? RoutineSession(template: template)
        runID = UUID(); logURL = nil; response = ""; scannedLabel = ""; ended = false
        resetStats()
        message = "Start when you're ready for another practice."
    }
    func startCamera() {
        if session?.template.detectorStatus != .experimental { detectionConfidence = DetectionConfidence.preview }
        else { vision.setConfidenceThreshold(Float(DetectionConfidence.defaultValue)) }
        guard !capture.isRunning, !capture.isStarting else { return }
        vision.setActive(true); capture.start()
    }
    func scanLabel() {
        guard capture.isRunning, session?.phase == .checking else {
            say("The camera needs to be running before I can read a label."); return
        }
        vision.requestLabelRead()
        say("Hold the label in view. I'll read the visible text; compare it with your written instructions.")
    }
    func submit() { let text = response; response = ""; conversation.stop(); handle(text) }
    func handle(_ text: String) {
        guard voiceEnabled, !ended else { return }
        switch VoiceIntent.parse(text) {
        case .pause: pause()
        case .resume:
            if session?.phase == .paused { resume() }
            else if session?.currentCheck?.responseKind == .monitoring { arm() }
            else { say(currentPrompt) }
        case .endSession: endSession()
        case .help: explain()
        case .askQuestion: askQuestion()
        case .repeatPrompt: prompt()
        case .confirm: confirm()
        case .arm: arm()
        case .skipCamera:
            if session?.continueWithoutCamera() == true {
                band.stop(); persist(); say("We'll continue this practice without camera monitoring. " + currentPrompt)
            } else { say(currentPrompt) }
        case .skipStep:
            if debugControlsEnabled { debugSkipStep() }
            else if let checkID = session?.currentCheck?.id, session?.assistantAdvance(checkID: checkID) == true {
                persist(); prompt() // Explicit spoken progression is unverified, like the assistant's advance tool.
            } else { say("Let's stay here. " + currentPrompt) }
        case .readLabel: scanLabel()
        case .finishPreparation: finishPreparation()
        case .finishMonitoring: finishMonitoring()
        case .answer(let answer):
            if session?.phase == .paused {
                if VoiceIntent.isAffirmative(answer) { resume() }
                else { say(currentPrompt) }
            } else if session?.phase == .monitoring || session?.phase == .unmonitoredPractice {
                if VoiceIntent.isAffirmative(answer) { finishMonitoring() }
                else { say(currentPrompt) }
            } else if session?.phase == .checking, session?.currentCheck?.responseKind == .monitoring {
                if VoiceIntent.isAffirmative(answer) { arm() }
                else { say(currentPrompt) }
            } else if session?.phase == .checking {
                let reply = session?.submit(answer) ?? "Routine unavailable"
                persist(); say(reply)
            } else { say(currentPrompt) }
        }
    }
    private func stateResult(error: String? = nil) -> (String, Bool) {
        var state: [String: Any] = [
            "phase": session?.phase.rawValue ?? "unavailable",
            "check_id": session?.currentCheck?.id ?? "finished",
            "reply": message, "prompt": currentPrompt,
            "help": session?.currentCheck?.help ?? "Follow your dialysis team's written instructions.",
            "camera_ready": canArm, "review_required": session?.reviewRequired ?? false,
            "pending_read_back": session?.pendingReadBack ?? "",
            "read_back_parts": session?.readBackParts ?? [],
            "latest_reply_handled_natively": nativeCommand != nil,
            "assistant_can_advance": session?.phase == .unmonitoredPractice || (session?.phase == .checking && session?.reviewRequired == false && session?.currentCheck?.responseKind != .monitoring),
            "detector_status": (session?.template.detectorStatus ?? .placeholder).rawValue,
            "visual_mode": session?.phase == .monitoring ? "experimental_monitoring" : "experimental_preview",
            "distance_warnings_enabled": true,
            "distance_warning_level": distanceRisk == .high ? "high" : distanceRisk == .medium ? "medium" : "none",
            "distance_estimate_fresh": fresh && observation.distanceMM != nil,
            "camera_running": capture.isRunning,
            "camera_status": cameraMessage,
            "wristband_connected": band.connected,
            "wristband_status": band.status,
            "wristband_last_write": band.lastCommandDescription,
            "rear_lidar_supported": capture.supportsLiDAR,
            "vision_fresh": displayFresh,
            "vision_protection_fresh": fresh,
            "model_loaded": observation.modelInstalled,
            "vision_pipeline_ms": observation.processingMilliseconds,
            "confidence_threshold": detectionConfidence,
            "vision_frame_age_ms": observation.receipt > 0 ? max(0, ProcessInfo.processInfo.systemUptime - observation.receipt) * 1000 : -1,
            "vision_status": observation.modelStatus,
            "proximity_status": riskText,
            "camera_distance_status": distanceText,
            "opening_count": observation.regions.count,
            "hand_box_count": observation.hands.count,
            "fingertip_count": observation.fingertips.count,
            "detected_objects": observation.detections.prefix(12).map { ["label": $0.label, "confidence": $0.confidence] as [String: Any] },
            "expected_response": session?.expectedResponse ?? "none",
            "response_instruction": session?.responseInstruction ?? "",
            "debug_controls_enabled": debugControlsEnabled,
            "debug_navigation_used": session?.debugNavigationUsed ?? false,
            "visible_label_text": String(scannedLabel.prefix(800)),
            "self_report_only": true]
        if let error { state["error"] = error }
        let data = (try? JSONSerialization.data(withJSONObject: state)) ?? Data()
        return (String(data: data, encoding: .utf8) ?? "{}", error != nil)
    }
    private func runTool(_ name: String, parameters: [String: Any]) -> (String, Bool) {
        if name == "get_routine_state" { return stateResult() }
        if name == "advance_practice_step" {
            guard let checkID = parameters["check_id"] as? String, checkID == lastUserCheckID,
                  progressionGate.consume(lastUserWords, expectedCheckID: checkID,
                      currentCheckID: session?.currentCheck?.id ?? "finished") != nil,
                  session?.assistantAdvance(checkID: checkID) == true else {
                return stateResult(error: "Cannot advance this step. Read current state; camera readiness, pauses and contact review cannot be overridden. Use only the latest real user reply for this check.")
            }
            persist(); message = currentPrompt
            return stateResult()
        }
        // A late tool call acknowledges the native command, without applying it twice.
        if name == "respond_to_check", let nativeCommand,
           parameters["check_id"] as? String == nativeCommand.checkID,
           let words = parameters["user_words"] as? String,
           VoiceIntent.normalize(words) == nativeCommand.words { return stateResult() }
        guard name == "respond_to_check", let checkID = parameters["check_id"] as? String,
              let words = parameters["user_words"] as? String,
              let actual = replyGate.consume(words, expectedCheckID: checkID,
                                             currentCheckID: session?.currentCheck?.id ?? "finished") else {
            return stateResult(error: "No matching unused user reply for this step. Read state and ask the user to repeat; do not invent words.")
        }
        handle(actual)
        return stateResult()
    }
    private func say(_ text: String, urgent: Bool = false) {
        message = text
        if urgent {
            resumeCloudAfterCue = resumeCloudAfterCue || (conversation.active && voiceConfigured && voiceEnabled)
            conversation.stop()
            speech.speak(text, urgent: true)
        } else if !conversation.active { speech.speak(text, urgent: true) }
        // During a call, the tool result carries this reply; avoid a second speaker.
    }
    func confirm() {
        if session?.confirmReadBack() == true { persist(); prompt() }
        else { say("Tell me the details first, then I'll ask you to confirm them.") }
    }
    func prompt() { say(currentPrompt) }
    func explain() { say(session?.currentCheck?.help ?? currentPrompt) }
    func askQuestion() {
        if conversation.active { return }
        if voiceConfigured { connectVoice() }
        else { say("Cartesia isn't connected. " + (session?.currentCheck?.help ?? currentPrompt)) }
    }
    func arm() {
        guard session?.reviewRequired != true else { say(currentPrompt); return }
        if session?.template.detectorStatus != .experimental {
            if session?.beginUnmonitoredPractice() == true { band.stop(); persist(); prompt() }
            else { say(currentPrompt) }
            return
        }
        let visionReady = canArm
        guard session?.armMonitoring(visionReady: visionReady) == true else {
            say(observation.modelInstalled
                ? "I need a clear view of both hands and the opening, with usable depth. Say ready when they're in view."
                : "The opening detector hasn't been added yet. For this practice, you can say continue without camera, or end session.")
            return
        }
        warningTime = -Double.infinity; lastHazardTime = -Double.infinity; clearSince = nil; cuePolicy.reset()
        persist(); say("I'm watching. Tell me when you've finished.")
    }
    func finishMonitoring() {
        if session?.finishUnmonitoredPractice() == true { band.stop(); persist(); prompt(); return }
        guard session?.finishMonitoring() == true else { say(currentPrompt); return }
        band.stop(); persist(); prompt()
    }
    func finishPreparation() {
        guard session?.phase == .checking, session?.currentCheck?.responseKind == .monitoring else { return }
        session?.finishPreparationOnly(); band.stop(); persist()
        say("That's the end of preparation practice. The connection wasn't monitored.")
    }
    func pause() {
        session?.pause(); band.stop(); persist()
        // Pausing the routine must keep the live microphone and conversation for spoken resume.
        say("We're paused. Take your time. Say resume when you're ready.")
    }
    func resume() {
        session?.resume(); startCamera(); persist(); prompt()
    }
    func debugJump(to checkID: String) {
        guard debugControlsEnabled, session?.debugJump(to: checkID) == true else { return }
        didNavigateForDebug()
    }
    func debugSkipStep() {
        guard debugControlsEnabled, session?.debugSkipCurrentCheck() == true else { return }
        didNavigateForDebug()
    }
    private func didNavigateForDebug() {
        band.stop(); conversation.stop(); speech.stop(); resumeCloudAfterCue = false
        replyGate = SpokenReplyGate(); progressionGate = SpokenReplyGate()
        lastUserCheckID = ""; lastUserWords = ""; lastUserTurn = -1; nativeCommand = nil
        ended = false; scannedLabel = ""; persist()
        message = "Debug step selected. " + currentPrompt
        if voiceEnabled {
            if voiceConfigured { connectVoice() } else { prompt() }
        }
    }
    func endSession() {
        voiceEnabled = false; ended = true; resumeCloudAfterCue = false
        session?.pause(); persist(); pauseHardware()
        message = "Session ended."
    }
    func backgrounded() {
        session?.pause(); persist(); voiceEnabled = false; resumeCloudAfterCue = false
        pauseHardware(); message = "Paused. Resume when you're ready."
    }
    private func audioNeedsResume(_ notice: String) {
        session?.pause(); band.stop(); persist()
        voiceEnabled = false; resumeCloudAfterCue = false
        conversation.stop(); speech.stop(); message = notice
    }
    func foregrounded() {
        // Permission sheets briefly make the app inactive without ending practice.
        guard voiceEnabled, !conversation.active, !speech.isListening else { return }
        speech.listen()
    }
    func resumeVoice() {
        guard session?.phase != .idle, !ended else { return }
        voiceEnabled = true; band.beginRoutineConnection()
        if voiceConfigured { connectVoice() } else { prompt() }
    }
    func usePhoneVoice() {
        guard !ended else { return }
        voiceEnabled = true; resumeCloudAfterCue = false
        conversation.stop(); prompt()
    }
    private func pauseHardware() {
        vision.setActive(false); capture.stop(reason: "Camera paused")
        band.endRoutineConnection(); speech.suspend(); conversation.stop()
    }
    private func checkHealth() {
        objectWillChange.send() // Keep displayed frame age/staleness honest between results.
        driveDistanceAlerts()
        if voiceEnabled, !ended, session?.phase != .idle, session?.phase != .completed { band.maintainRoutineConnection() }
        guard session?.phase == .monitoring else { return }
        if !fresh { loseObservation("Observation lost or delayed. Pause and restore a clear view before rearming.") }
    }
    private func loseObservation(_ reason: String) {
        session?.observationLost(); band.stop(); persist()
        say(CoachSpeech.viewLostCue, urgent: true)
    }
    private func received(_ output: CoachVisionSnapshot) {
        observation = output
        defer { driveDistanceAlerts() }
        let level = riskLevel
        if level > lastRiskLevel { haptics.notificationOccurred(level == .high ? .error : .warning) }
        lastRiskLevel = level
        if !output.labelText.isEmpty, output.labelText != scannedLabel {
            scannedLabel = output.labelText
            let labelReply = "The visible label says: " + String(output.labelText.prefix(800)) + ". Compare that with your written instructions."
            message = labelReply
            resumeCloudAfterCue = resumeCloudAfterCue || (conversation.active && voiceConfigured && voiceEnabled)
            speech.useCartesia = conversation.active
            conversation.stop()
            if voiceEnabled { speech.speak(labelReply) }
        }
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
            persist()
            say(CoachSpeech.reviewCue, urgent: true)
        case .unavailable(let reason): loseObservation("Monitoring paused: " + reason)
        case .warning(let intensity, _):
            lastHazardTime = now; clearSince = nil
            band.set(intensity: intensity)
            if now - warningTime >= 5 {
                warningTime = now
                say(CoachSpeech.nearCue, urgent: true)
            }
        case .clear:
            guard output.handCoverageComplete else { loseObservation("Fingertip coverage lost. Pause and show both hands before rearming."); return }
            if clearSince == nil { clearSince = now }
            if distanceRisk != .none { /* camera-distance warning owns the band */ }
            else if now - (clearSince ?? now) >= 0.3 { band.stop() }
            else if now - lastHazardTime < 0.3 { band.set(intensity: 80) }
        }
    }
    /// MEDIUM -> pulsing band + "Careful, too close."; HIGH -> continuous band + "Stop. Hands back."
    /// Called per result and every 100 ms; BandClient expires each set() after 250 ms, so the
    /// band stops by itself if observations stop arriving.
    private func driveDistanceAlerts() {
        let level = distanceRisk
        defer { lastDistanceRisk = level }
        let now = ProcessInfo.processInfo.systemUptime
        stats.record(level: level, distanceMM: observation.distanceMM, at: now,
                     measuring: fresh && observation.distanceMM != nil)
        switch level {
        case .high:
            band.set(intensity: 255, suspected: true)
        case .medium:
            if case .warning = observation.decision, session?.phase == .monitoring { break } // LiDAR already driving
            if case .projectedOverlap = observation.decision, session?.phase == .monitoring { break }
            band.set(intensity: 200)
        case .none:
            if lastDistanceRisk != .none, session?.phase != .monitoring { band.stop() }
        }
        // Phone haptics come from received(), since riskLevel includes this level.
        // Voice: one short cue when the danger rises (held 0.3 s), quiet when it drops,
        // HIGH repeated only every 8 s. See WarningCuePolicy. Shares warningTime with the LiDAR cue.
        guard let cue = cuePolicy.update(level, at: now) else { return }
        warningTime = now
        say(cue == .high ? CoachSpeech.highCue : CoachSpeech.nearCue, urgent: true)
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
