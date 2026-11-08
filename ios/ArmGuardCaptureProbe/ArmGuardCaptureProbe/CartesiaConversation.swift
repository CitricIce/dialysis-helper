import AVFoundation
import Combine
import Foundation
import UIKit

/// One opt-in conversation; native tools enforce routine transitions.
final class CartesiaConversation: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var status = "Voice is ready to connect"
    @Published private(set) var transcript = ""
    @Published private(set) var lastReply = ""
    @Published private(set) var audioNotice = ""
    var onNeedsResume: ((String) -> Void)?
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onUserUtterance: ((String, Int) -> Void)?
    var onTool: ((String, [String: Any]) -> (String, Bool))?
    private var toolResults: [String: (String, Bool)] = [:]
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private let wire = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private let playback = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var socket: URLSessionWebSocketTask?
    private var bootstrap: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var tapInstalled = false
    private var generation = UUID()
    private var ready = false
    private var sending = false
    private var pending: [Data] = []
    private var microphoneRemainder = Data()
    private var playbackState = VoicePlaybackTracker()
    private var recoveryBudget = VoiceRecoveryBudget()
    private var audioGeneration = UUID()
    private var interrupted = false
    private var rebuilding = false
    private var healthTimer: Timer?
    private var recoveryTask: Task<Void, Never>?
    private var observers: Set<AnyCancellable> = []
    private var lastMicrophoneAt = 0.0
    private var inputChunks = 0
    private var outputChunks = 0
    private var playedChunks = 0
    private var clearedChunks = 0
    private var recoveryCount = 0
    private var lastAudioProblem = "none"
    private let audioGate = AudioDeliveryGate()

    init() {
        engine.attach(player)
        observeAudioChanges()
    }

    deinit { healthTimer?.invalidate(); recoveryTask?.cancel() }

    var audioDiagnostics: String {
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ", ")
        return """
        Call active: \(active); ready: \(ready); interrupted: \(interrupted)
        Engine running: \(engine.isRunning); player running: \(player.isPlaying)
        Output route: \(route.isEmpty ? "none" : route); volume: \(Int(session.outputVolume * 100))%
        Mic chunks sent: \(inputChunks); audio packets received: \(outputChunks); buffers completed: \(playedChunks)
        Queued audio: \(playbackState.queuedSamples / 16) ms; barge-in clears: \(clearedChunks); recoveries: \(recoveryCount)
        Last audio problem: \(lastAudioProblem)
        """
    }

    func start(request: URLRequest) {
        stop()
        guard UIApplication.shared.applicationState == .active else { return }
        active = true // Own the microphone while its permission prompt is pending.
        let permissionGeneration = generation
        guard AVAudioApplication.shared.recordPermission == .granted else {
            AVAudioApplication.requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.generation == permissionGeneration else { return }
                    if allowed { self.start(request: request) }
                    else { self.fail("Allow microphone access to use voice.") }
                }
            }
            return
        }
        active = true
        status = "Connecting to Cartesia…"
        transcript = ""; lastReply = ""; toolResults.removeAll(); audioNotice = ""
        inputChunks = 0; outputChunks = 0; playedChunks = 0; clearedChunks = 0; recoveryCount = 0
        lastAudioProblem = "none"; recoveryBudget = VoiceRecoveryBudget(); playbackState = VoicePlaybackTracker()
        let token = generation
        bootstrap = Task { @MainActor [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let value = json["url"] as? String, var parts = URLComponents(string: value),
                      parts.scheme == "wss", ["api.cartesia.ai", "api-us.cartesia.ai"].contains(parts.host ?? ""),
                      parts.port == nil || parts.port == 443,
                      parts.user == nil, parts.password == nil, let access = json["token"] as? String else {
                    throw URLError(.badServerResponse)
                }
                parts.queryItems = [URLQueryItem(name: "cartesia_version", value: "2026-08-14"),
                                    URLQueryItem(name: "access_token", value: access)]
                guard let url = parts.url else { throw URLError(.badURL) }
                guard let self, self.generation == token, self.active else { return }
                let socket = URLSession.shared.webSocketTask(with: url)
                socket.maximumMessageSize = 2_000_000
                self.socket = socket
                socket.resume()
                self.send(["type": "session_create", "audio": ["input_format": "pcm_16000", "output_delivery": "speaking_pace", "continuous_input": true]])
                self.receive(token: token)
                self.timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: 12_000_000_000) }
                    catch { return }
                    guard let self, self.generation == token, !self.ready else { return }
                    self.fail("Voice connection timed out.")
                }
            } catch {
                guard let self, self.generation == token else { return }
                self.fail("Cartesia could not connect. Check voice setup.")
            }
        }
    }

    func stop() {
        generation = UUID()
        active = false; ready = false; sending = false; interrupted = false
        pending.removeAll(); microphoneRemainder.removeAll()
        healthTimer?.invalidate(); healthTimer = nil
        recoveryTask?.cancel(); recoveryTask = nil
        timeout?.cancel(); timeout = nil
        bootstrap?.cancel(); bootstrap = nil
        receiveTask?.cancel(); receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        stopAudioGraph()
        status = "Voice stopped"
    }

    private func fail(_ message: String) {
        lastAudioProblem = message
        stop(); status = message; onFailure?(message)
    }

    private func receive(token: UUID) {
        guard let socket else { return }
        receiveTask = Task { @MainActor [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    let data: Data
                    switch message {
                    case .data(let value): data = value
                    case .string(let value): data = Data(value.utf8)
                    @unknown default: continue
                    }
                    let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                    guard let self, self.generation == token, self.active else { return }
                    self.handle(event)
                }
            } catch {
                guard let self, self.generation == token else { return }
                self.fail("Voice connection ended.")
            }
        }
    }

    private func send(_ event: [String: Any], completion: (() -> Void)? = nil) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: event),
              let text = String(data: data, encoding: .utf8) else { return }
        let token = generation
        Task { @MainActor [weak self] in
            do {
                try await socket.send(.string(text))
                guard let self, self.generation == token else { return }
                completion?()
            } catch {
                guard let self, self.generation == token else { return }
                self.fail("Voice network is unavailable.")
            }
        }
    }

    private func handle(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "session_ready":
            timeout?.cancel(); timeout = nil
            guard !ready else { return }
            if let audio = event["audio"] as? [String: Any],
               let format = audio["input_format"] as? String, format != "pcm_16000" {
                fail("Cartesia returned an unsupported audio format."); return
            }
            do {
                try startAudio(); ready = true; status = "Listening"
                healthTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkAudioHealth() }
                onReady?()
            }
            catch { fail("Microphone or speaker could not start.") }
        case "audio_output":
            guard let string = event["audio"] as? String, let data = Data(base64Encoded: string),
                  !data.isEmpty, data.count % 2 == 0, data.count <= 192_000 else {
                fail("Cartesia sent invalid voice audio."); return
            }
            outputChunks += 1
            guard !interrupted else { return }
            if !engine.isRunning {
                guard recoverAudio(reason: "Audio engine stopped before playback") else { return }
            }
            playbackState.receivedAudio()
            status = "Speaking"
            play(data)
        case "audio_output_clear":
            clearedChunks += 1
            playbackState.clear()
            player.stop() // Restart only when the next audio buffer has actually been scheduled.
            if !interrupted { status = "Listening" }
        case "turn_started":
            if event["role"] as? String == "assistant" { playbackState.beginReply() }
            else if event["role"] as? String == "user" {
                audioNotice = ""; playbackState.cancelReplyExpectation()
            }
        case "turn_ended":
            if let text = event["text"] as? String {
                transcript = String((transcript + "\n" + text).suffix(4000))
                if event["role"] as? String == "user", let turn = event["turn"] as? Int {
                    onUserUtterance?(text, turn)
                } else if event["role"] as? String == "assistant" {
                    lastReply = text
                    playbackState.endedReply(at: ProcessInfo.processInfo.systemUptime,
                        hasText: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        interrupted: event["interrupted"] as? Bool == true)
                }
            }
        case "client_tool_call":
            if event["expects_response"] as? Bool == true, let id = event["tool_call_id"] as? String {
                let result: (String, Bool)
                if let saved = toolResults[id] { result = saved }
                else if let name = event["tool_name"] as? String, let parameters = event["parameters"] as? [String: Any] {
                    result = onTool?(name, parameters) ?? ("Routine unavailable", true)
                    // A bounded cache makes replayed tool IDs idempotent.
                    if toolResults.count >= 128 { toolResults.removeAll() }
                    toolResults[id] = result
                } else { result = ("Invalid tool request", true) }
                send(["type": "client_tool_result", "tool_call_id": id,
                      "result": result.0, "is_error": result.1])
            }
        case "error":
            if event["fatal"] as? Bool == false {
                audioNotice = "Voice service reported a temporary error."
            } else { fail("Cartesia reported an error.") }
        default: break
        }
    }

    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        // Keep deliberate headphones, but do not let a voice-chat route fall back to the quiet earpiece.
        if session.currentRoute.outputs.contains(where: { $0.portType == .builtInReceiver }) {
            try session.overrideOutputAudioPort(.speaker)
        }
        let input = engine.inputNode
        if !input.isVoiceProcessingEnabled { try input.setVoiceProcessingEnabled(true) }
        // Voice processing and route changes can rebuild the I/O nodes. Connect after that change.
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: playback)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = AVAudioConverter(from: format, to: wire) else {
            throw URLError(.cannotDecodeRawData)
        }
        audioGeneration = UUID()
        let token = generation
        let audioToken = audioGeneration
        let gate = audioGate
        // Conversion is bounded DSP; network and UI work never run on the audio callback.
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(format.sampleRate * 0.04), format: format) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / format.sampleRate) + 32)
            guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            let result = converter.convert(to: output, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return buffer
            }
            guard result != .error, error == nil, output.frameLength > 0,
                  let bytes = output.int16ChannelData?[0] else { return }
            let data = Data(bytes: bytes, count: Int(output.frameLength) * 2)
            guard gate.acquire() else { return }
            DispatchQueue.main.async {
                defer { gate.release() }
                guard let self, self.generation == token, self.audioGeneration == audioToken,
                      self.ready, !self.interrupted else { return }
                self.lastMicrophoneAt = ProcessInfo.processInfo.systemUptime
                if gate.overflowed { self.fail("Voice audio fell behind."); return }
                // Fixed 40 ms chunks; converter callbacks may be any length.
                self.microphoneRemainder.append(data)
                while self.microphoneRemainder.count >= 1280, self.active {
                    let chunk = Data(self.microphoneRemainder.prefix(1280))
                    self.microphoneRemainder.removeFirst(1280)
                    self.enqueue(chunk)
                }
            }
        }
        tapInstalled = true
        gate.reset()
        lastMicrophoneAt = ProcessInfo.processInfo.systemUptime
        engine.prepare(); try engine.start()
    }

    private func enqueue(_ data: Data) {
        guard pending.count < 5 else { fail("Voice connection fell behind."); return }
        pending.append(data)
        flush()
    }
    private func flush() {
        guard ready, !interrupted, !sending, !pending.isEmpty else { return }
        sending = true
        let data = pending.removeFirst()
        send(["type": "audio_input", "audio": data.base64EncodedString()]) { [weak self] in
            self?.inputChunks += 1
            self?.sending = false; self?.flush()
        }
    }
    private func play(_ data: Data) {
        guard ready, !interrupted else { return }
        let count = data.count / 2
        guard playbackState.schedule(samples: count, at: ProcessInfo.processInfo.systemUptime),
              let buffer = AVAudioPCMBuffer(pcmFormat: playback, frameCapacity: AVAudioFrameCount(count)),
              let channel = buffer.floatChannelData?[0] else {
            fail("Voice playback fell behind."); return
        }
        buffer.frameLength = AVAudioFrameCount(count)
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for i in 0..<count {
                let value = UInt16(bytes[i * 2]) | UInt16(bytes[i * 2 + 1]) << 8
                channel[i] = Float(Int16(bitPattern: value)) / 32768
            }
        }
        let token = playbackState.epoch
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self,
                      self.playbackState.completed(samples: count, epoch: token, at: ProcessInfo.processInfo.systemUptime) else { return }
                self.playedChunks += 1
                if self.playbackState.queuedSamples == 0 { self.status = "Listening" }
            }
        }
        if !player.isPlaying { player.play() }
    }

    private func stopAudioGraph() {
        audioGeneration = UUID()
        playbackState.clear(cancelReply: false) // Invalidate callbacks BEFORE stopping the player.
        player.stop(); engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        microphoneRemainder.removeAll(); pending.removeAll()
    }

    private func observeAudioChanges() {
        NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange)
            .receive(on: DispatchQueue.main).sink { [weak self] note in
                guard let self, let changed = note.object as? AVAudioEngine, changed === self.engine,
                      self.active, self.ready, !self.interrupted, !self.rebuilding,
                      !self.engine.isRunning else { return }
                self.scheduleRecovery(reason: "Audio engine configuration changed")
            }.store(in: &observers)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] note in
                guard let self, self.active, self.ready, !self.interrupted, !self.rebuilding else { return }
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
                // Our own category/override changes must not recursively restart the engine.
                if reason == AVAudioSession.RouteChangeReason.categoryChange.rawValue ||
                   reason == AVAudioSession.RouteChangeReason.override.rawValue { return }
                self.scheduleRecovery(reason: "Audio output route changed")
            }.store(in: &observers)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] note in
                guard let self, self.active, self.ready,
                      let raw = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                if type == .began {
                    self.interrupted = true
                    self.recoveryTask?.cancel(); self.recoveryTask = nil
                    self.stopAudioGraph(); self.playbackState.clear()
                    self.status = "Voice interrupted by another app"
                    self.audioNotice = "Voice is paused while another app uses audio."
                } else {
                    let rawOptions = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
                    guard AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) else {
                        self.stop()
                        self.onNeedsResume?("Voice was interrupted. Resume voice when you're ready.")
                        return
                    }
                    self.interrupted = false
                    self.scheduleRecovery(reason: "Audio interruption ended")
                }
            }.store(in: &observers)
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self, self.active, self.ready else { return }
                self.stopAudioGraph()
                self.engine = AVAudioEngine(); self.player = AVAudioPlayerNode()
                self.engine.attach(self.player)
                self.scheduleRecovery(reason: "iPhone audio service restarted")
            }.store(in: &observers)
    }

    private func scheduleRecovery(reason: String) {
        guard active, ready, !interrupted, recoveryTask == nil else { return }
        let token = generation
        recoveryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            guard let self, self.generation == token else { return }
            self.recoveryTask = nil
            _ = self.recoverAudio(reason: reason)
        }
    }

    @discardableResult private func recoverAudio(reason: String) -> Bool {
        guard active, ready, !interrupted, !rebuilding else { return false }
        guard recoveryBudget.take(at: ProcessInfo.processInfo.systemUptime) else {
            fail("The phone speaker could not keep playing voice audio."); return false
        }
        rebuilding = true
        defer { rebuilding = false }
        lastAudioProblem = reason
        stopAudioGraph()
        do {
            try startAudio()
            recoveryCount += 1
            audioNotice = "Audio reconnected. Say ‘repeat’ if you missed the last reply."
            status = "Listening"
            return true
        } catch { fail("The phone microphone or speaker could not reconnect."); return false }
    }

    private func checkAudioHealth() {
        guard active, ready, !interrupted, !rebuilding, recoveryTask == nil else { return }
        if !engine.isRunning { _ = recoverAudio(reason: "Audio engine stopped while the call was connected"); return }
        if ProcessInfo.processInfo.systemUptime - lastMicrophoneAt > 3 {
            _ = recoverAudio(reason: "Microphone stopped delivering audio while the engine was running"); return
        }
        switch playbackState.issue(at: ProcessInfo.processInfo.systemUptime) {
        case .playbackStalled:
            _ = recoverAudio(reason: "Audio arrived but playback stopped progressing")
        case .replyAudioMissing:
            fail("Cartesia sent reply text without voice audio.")
        case nil: break
        }
    }
}

private final class AudioDeliveryGate {
    private let lock = NSLock()
    private var outstanding = 0
    private var overflow = false
    var overflowed: Bool { lock.lock(); defer { lock.unlock() }; return overflow }
    func reset() { lock.lock(); overflow = false; lock.unlock() }
    func acquire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard outstanding < 4 else { overflow = true; return false }
        outstanding += 1; return true
    }
    func release() { lock.lock(); outstanding = max(0, outstanding - 1); lock.unlock() }
}
