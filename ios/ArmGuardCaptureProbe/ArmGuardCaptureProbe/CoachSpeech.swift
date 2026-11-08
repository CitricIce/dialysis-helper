import AVFoundation
import Combine
import Speech
import Security
import UIKit

enum VoiceConnectionMode: String, CaseIterable { case direct, server }

/// Prototype direct access uses a user-entered Keychain key; hosted access remains optional.
final class CoachSpeech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var gatewayURL = UserDefaults.standard.string(forKey: "voiceGatewayURL") ?? "" {
        didSet { UserDefaults.standard.set(gatewayURL, forKey: "voiceGatewayURL"); invalidateClips() }
    }
    @Published var gatewayToken = VoiceAccessCode.read() {
        didSet { VoiceAccessCode.save(gatewayToken); invalidateClips() }
    } // A separate gateway access code, never the Cartesia API key.
    @Published var connectionMode = VoiceConnectionMode(rawValue: UserDefaults.standard.string(forKey: "voiceConnectionMode") ?? "direct") ?? .direct {
        didSet { UserDefaults.standard.set(connectionMode.rawValue, forKey: "voiceConnectionMode"); invalidateClips() }
    }
    @Published var cartesiaAPIKey = VoiceAccessCode.read(account: "cartesia") {
        didSet { VoiceAccessCode.save(cartesiaAPIKey, account: "cartesia"); invalidateClips() }
    }
    @Published var voiceID = UserDefaults.standard.string(forKey: "cartesiaVoiceID") ?? "62ae83ad-4f6a-430b-af41-a9bede9286ca" {
        didSet { UserDefaults.standard.set(voiceID, forKey: "cartesiaVoiceID"); invalidateClips() }
    }
    @Published var agentID = UserDefaults.standard.string(forKey: "cartesiaAgentID") ?? "agent_B7mQ8N5KGeaTvriBekCNKe" {
        didSet { UserDefaults.standard.set(agentID, forKey: "cartesiaAgentID") }
    }
    @Published var useCartesia = false
    @Published var handsFree = true
    @Published private(set) var status = "Built-in voice ready"
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    var onFailure: ((String) -> Void)?
    var onFinished: (() -> Void)?
    var onResponse: ((String) -> Void)?
    var canListen: (() -> Bool)?
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var networkTask: Task<Void, Never>?
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var silenceTimer: Timer?
    private var token = UUID()
    private var tapInstalled = false
    private var speaking = false
    private var currentUtterance: AVSpeechUtterance?
    private var currentText = ""
    private var clipTask: Task<Void, Never>?
    private var alertClips: [String: Data] = [:]
    private var retryTimer: Timer?
    private var listeningLimit: Timer?
    private var recognitionFailures = 0
    // Kept to about a second each so cues never pile up; the band and screen alert continuously.
    static let nearCue = "Medium risk. Move back."
    static let highCue = "High risk. Hands back."
    static let reviewCue = "Your hand overlaps the opening in the image. Pause and follow your dialysis team's instructions about possible contact."
    static let viewLostCue = "I've lost a clear view. We're paused. Restore the view, then say resume."

    private func invalidateClips() {
        clipTask?.cancel(); clipTask = nil; alertClips.removeAll()
    }
    var connectionReady: Bool {
        if connectionMode == .direct { return !cartesiaAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !voiceID.isEmpty && !agentID.isEmpty }
        return Self.allowedGateway(gatewayURL) != nil && !gatewayToken.isEmpty
    }
    func agentSessionRequest(checkID: String, phase: RoutinePhase, prompt: String, checks: [RoutineCheck], detectorStatus: DetectorStatus = .placeholder) -> URLRequest? {
        if connectionMode == .direct {
            guard let url = Bundle.main.url(forResource: "VoiceInstructions", withExtension: "txt"),
                  let instructions = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return try? CartesiaRequests.agentSession(apiKey: cartesiaAPIKey, voiceID: voiceID, agentID: agentID,
                instructions: instructions, initialPrompt: prompt, checks: checks, checkID: checkID, phase: phase, detectorStatus: detectorStatus)
        }
        return gatewayRequest(path: "agent-session", body: ["check_id": checkID, "phase": phase.rawValue])
    }
    private func gatewayRequest(path: String, body: [String: Any]) -> URLRequest? {
        guard let base = Self.allowedGateway(gatewayURL), !gatewayToken.isEmpty else { return nil }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("Bearer \(gatewayToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
    private func speechRequest(_ text: String) -> URLRequest? {
        if connectionMode == .direct { return try? CartesiaRequests.speech(apiKey: cartesiaAPIKey, voiceID: voiceID, text: text) }
        return gatewayRequest(path: "speak", body: ["text": text])
    }
    func prepareAlertClips() {
        guard clipTask == nil, connectionReady else { return }
        let requests = [Self.nearCue, Self.highCue, Self.reviewCue, Self.viewLostCue].compactMap { text -> (String, URLRequest)? in
            guard alertClips[text] == nil, let request = speechRequest(text) else { return nil }
            return (text, request)
        }
        clipTask = Task { @MainActor [weak self] in
            for (text, request) in requests {
                guard !Task.isCancelled else { return }
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200,
                          (response as? HTTPURLResponse)?.mimeType?.hasPrefix("audio/") == true else { continue }
                    self?.alertClips[text] = try WaveClip.finalized(data)
                } catch { if Task.isCancelled { return } }
            }
            self?.clipTask = nil
        }
    }

    override init() { super.init(); synthesizer.delegate = self }

    static func allowedGateway(_ value: String) -> URL? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return nil }
        if url.scheme == "https" || (url.scheme == "http" && host.hasSuffix(".local")) { return url }
        return nil
    }

    func speak(_ text: String, urgent: Bool = false) {
        stop()
        let current = token
        speaking = true
        currentText = text
        if urgent, let data = alertClips[text] {
            do {
                try configureAudio()
                player = try AVAudioPlayer(data: data); player?.delegate = self
                guard player?.play() == true else { throw URLError(.cannotDecodeContentData) }
                status = "Cartesia voice"
                return
            } catch { localSpeech(text, status: "Phone voice fallback"); return }
        }
        if !urgent, useCartesia, var urlRequest = speechRequest(text) {
            status = "Generating Cartesia speech…"
            urlRequest.timeoutInterval = 8
            networkTask = Task { @MainActor [weak self] in
                do {
                    let (data, response) = try await URLSession.shared.data(for: urlRequest)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          http.mimeType?.hasPrefix("audio/") == true, data.count <= 5_000_000 else {
                        throw URLError(.badServerResponse)
                    }
                    guard let self, self.token == current else { return }
                    do {
                        try self.configureAudio()
                        self.player = try AVAudioPlayer(data: WaveClip.finalized(data))
                        self.player?.delegate = self
                        self.player?.prepareToPlay()
                        guard self.player?.play() == true else { throw URLError(.cannotDecodeContentData) }
                        self.status = "Cartesia voice"
                    } catch { self.localSpeech(text, status: "Cartesia unavailable; built-in voice") }
                } catch {
                    guard let self, self.token == current else { return }
                    self.localSpeech(text, status: "Cartesia unavailable; built-in voice")
                }
            }
        } else { localSpeech(text, status: urgent ? "Immediate local warning" : "Built-in voice") }
    }

    private func configureAudio() throws {
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        let session = AVAudioSession.sharedInstance()
        try session.setActive(true)
        if session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
            try session.overrideOutputAudioPort(.speaker)
        }
    }

    private func localSpeech(_ text: String, status: String) {
        do { try configureAudio() }
        catch {
            speaking = false
            self.status = "Phone audio could not start."
            onFailure?("The phone microphone or speaker is unavailable. Resume voice after the interruption ends.")
            return
        }
        self.status = status
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    func suspend() {
        stop()
        clipTask?.cancel(); clipTask = nil
    }

    func stop() {
        token = UUID()
        networkTask?.cancel()
        networkTask = nil
        speaking = false; currentUtterance = nil; currentText = ""
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        stopListening()
    }

    func listen() {
        guard handsFree, !speaking, canListen?() != false else { return }
        stopListening()
        token = UUID()
        let permissionToken = token
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            SFSpeechRecognizer.requestAuthorization { [weak self] permission in
                DispatchQueue.main.async {
                    guard let self, self.token == permissionToken else { return }
                    if permission == .authorized { self.listen() }
                    else { self.status = "Speech permission unavailable; type a response instead." }
                }
            }
            return
        }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            AVAudioApplication.requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.token == permissionToken else { return }
                    if allowed { self.listen() }
                    else { self.status = "Microphone unavailable; type a response instead." }
                }
            }
            return
        }
        guard UIApplication.shared.applicationState == .active,
              let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            status = "On-device English recognition unavailable; type a response. No audio is sent to Apple."
            return
        }
        do {
            try configureAudio()
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw URLError(.cannotDecodeRawData) }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            let listeningToken = token
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapInstalled = true
            transcript = ""
            isListening = true
            status = "Listening on device…"
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self, self.token == listeningToken, self.isListening else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                        self.silenceTimer?.invalidate()
                        self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in self?.finishResponse() }
                        if result.isFinal { self.finishResponse() }
                    } else if error != nil {
                        self.stopListening()
                        self.status = "Reconnecting microphone…"
                        self.retryListening()
                    }
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
            listeningLimit = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.stopListening(); self.retryListening()
            }
        } catch {
            stopListening()
            status = "Audio input could not start; type a response instead."
        }
    }

    private func finishResponse() {
        guard isListening else { return }
        let answer = transcript
        stopListening()
        recognitionFailures = 0
        if !answer.isEmpty { onResponse?(answer) }
        if !speaking { retryListening() }
    }

    private func retryListening() {
        guard handsFree, canListen?() != false, !speaking else { return }
        recognitionFailures = min(recognitionFailures + 1, 5)
        let retryToken = token
        retryTimer = Timer.scheduledTimer(withTimeInterval: min(Double(recognitionFailures), 5), repeats: false) { [weak self] _ in
            guard let self, self.token == retryToken, self.canListen?() != false else { return }
            self.listen()
        }
    }
    func stopListening() {
        retryTimer?.invalidate(); retryTimer = nil
        listeningLimit?.invalidate(); listeningLimit = nil
        silenceTimer?.invalidate(); silenceTimer = nil
        audioEngine.stop()
        if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); request = nil
        recognition?.cancel(); recognition = nil
        isListening = false
    }

    private func finishedSpeaking() {
        speaking = false
        onFinished?()
        guard handsFree, canListen?() != false else { return }
        let finishedToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.token == finishedToken else { return }
            self.listen()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard currentUtterance === utterance else { return }
        currentUtterance = nil; finishedSpeaking()
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard currentUtterance === utterance else { return }
        currentUtterance = nil; speaking = false
        onFailure?("Phone speech was interrupted. Resume voice when the phone's audio is available.")
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard self.player === player else { return }
        if flag { finishedSpeaking() }
        else { localSpeech(currentText, status: "Phone voice fallback") }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard self.player === player else { return }
        self.player = nil
        localSpeech(currentText, status: "Phone voice fallback")
    }
}

// The access code persists in the device keychain, restricted to this installation.
private enum VoiceAccessCode {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "org.armguard.voice", kSecAttrAccount as String: account]
    }
    static func read(account: String = "gateway") -> String {
        var lookup = query(account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String, account: String = "gateway") {
        let query = query(account)
        if value.isEmpty { SecItemDelete(query as CFDictionary); return }
        let fields: [String: Any] = [kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, fields as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(fields) { _, new in new } as CFDictionary, nil)
        }
    }
}
