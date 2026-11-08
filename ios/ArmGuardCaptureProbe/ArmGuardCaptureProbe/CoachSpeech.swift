import AVFoundation
import Combine
import Speech
import UIKit

/// Dynamic Cartesia TTS via a trusted gateway; urgent cues always use local speech.
final class CoachSpeech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var gatewayURL = ""
    @Published var gatewayToken = "" // Session memory only. Never the Cartesia API key.
    @Published var useCartesia = false
    @Published var handsFree = false
    @Published private(set) var status = "Built-in voice ready"
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
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
        if !urgent, useCartesia, let base = Self.allowedGateway(gatewayURL), !gatewayToken.isEmpty {
            status = "Generating Cartesia speech…"
            var urlRequest = URLRequest(url: base.appendingPathComponent("speak"))
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = 8
            urlRequest.setValue("Bearer \(gatewayToken)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
            networkTask = Task { [weak self] in
                do {
                    let (data, response) = try await URLSession.shared.data(for: urlRequest)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          http.mimeType?.hasPrefix("audio/") == true, data.count <= 5_000_000 else {
                        throw URLError(.badServerResponse)
                    }
                    await MainActor.run {
                        guard let self, self.token == current else { return }
                        do {
                            try self.configureAudio()
                            self.player = try AVAudioPlayer(data: data)
                            self.player?.delegate = self
                            self.player?.prepareToPlay()
                            guard self.player?.play() == true else { throw URLError(.cannotDecodeContentData) }
                            self.status = "Cartesia voice"
                        } catch { self.localSpeech(text, status: "Cartesia unavailable; built-in voice") }
                    }
                } catch {
                    await MainActor.run {
                        guard let self, self.token == current else { return }
                        self.localSpeech(text, status: "Cartesia unavailable; built-in voice")
                    }
                }
            }
        } else { localSpeech(text, status: urgent ? "Immediate local warning" : "Built-in voice") }
    }

    private func configureAudio() throws {
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try AVAudioSession.sharedInstance().setActive(true)
    }

    private func localSpeech(_ text: String, status: String) {
        try? configureAudio()
        self.status = status
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }

    func stop() {
        token = UUID()
        networkTask?.cancel()
        networkTask = nil
        speaking = false
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        stopListening()
    }

    func listen() {
        guard !speaking, canListen?() != false else { return }
        stopListening()
        token = UUID()
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            SFSpeechRecognizer.requestAuthorization { [weak self] permission in
                DispatchQueue.main.async {
                    if permission == .authorized { self?.listen() }
                    else { self?.status = "Speech permission unavailable; type a response instead." }
                }
            }
            return
        }
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    if allowed { self?.listen() }
                    else { self?.status = "Microphone unavailable; type a response instead." }
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
                        self.status = "Listening stopped; tap Listen or type your response."
                    }
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stopListening()
            status = "Audio input could not start; type a response instead."
        }
    }

    private func finishResponse() {
        guard isListening else { return }
        let answer = transcript
        stopListening()
        if !answer.isEmpty { onResponse?(answer) }
    }

    func stopListening() {
        silenceTimer?.invalidate(); silenceTimer = nil
        audioEngine.stop()
        if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        request?.endAudio(); request = nil
        recognition?.cancel(); recognition = nil
        isListening = false
    }

    private func finishedSpeaking() {
        speaking = false
        guard handsFree, canListen?() != false else { return }
        let finishedToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.token == finishedToken else { return }
            self.listen()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finishedSpeaking() }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finishedSpeaking() }
}
