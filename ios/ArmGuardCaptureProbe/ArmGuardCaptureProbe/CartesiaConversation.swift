import AVFoundation
import Combine
import Foundation
import UIKit

/// Explicit opt-in cloud conversation. No workflow mutation callback exists.
final class CartesiaConversation: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var status = "Voice questions are optional"
    @Published private(set) var transcript = ""
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let wire = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private let playback = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var socket: URLSessionWebSocketTask?
    private var bootstrap: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var timeout: Timer?
    private var tapInstalled = false
    private var generation = UUID()
    private var ready = false
    private var sending = false
    private var pending: [Data] = []
    private var microphoneRemainder = Data()
    private var queuedSamples = 0
    private var playbackGeneration = UUID()
    private let audioGate = AudioDeliveryGate()

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playback)
    }

    func start(base: URL, gatewayToken: String, checkID: String) {
        stop()
        guard UIApplication.shared.applicationState == .active else { return }
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    if allowed { self?.start(base: base, gatewayToken: gatewayToken, checkID: checkID) }
                    else { self?.status = "Microphone permission is required for voice questions." }
                }
            }
            return
        }
        active = true
        status = "Connecting to Cartesia…"
        transcript = ""
        let token = generation
        var request = URLRequest(url: base.appendingPathComponent("agent-session"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(gatewayToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["check_id": checkID])
        bootstrap = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: String],
                      let value = json["url"], var parts = URLComponents(string: value),
                      parts.scheme == "wss", parts.host == "api.cartesia.ai",
                      parts.user == nil, parts.password == nil, let access = json["token"] else {
                    throw URLError(.badServerResponse)
                }
                parts.queryItems = [URLQueryItem(name: "cartesia_version", value: "2026-08-14"),
                                    URLQueryItem(name: "access_token", value: access)]
                guard let url = parts.url else { throw URLError(.badURL) }
                await MainActor.run {
                    guard let self, self.generation == token, self.active else { return }
                    let socket = URLSession.shared.webSocketTask(with: url)
                    socket.maximumMessageSize = 2_000_000
                    self.socket = socket
                    socket.resume()
                    self.send(["type": "session_create", "audio": ["input_format": "pcm_16000", "output_delivery": "speaking_pace", "continuous_input": true]])
                    self.receive(token: token)
                    self.timeout = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
                        guard self?.ready == false else { return }
                        self?.fail("Voice connection timed out. Use the check's offline explanation.")
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self, self.generation == token else { return }
                    self.fail("Voice questions unavailable. Check gateway and published Cartesia agent configuration.")
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        playbackGeneration = UUID()
        active = false; ready = false; sending = false
        pending.removeAll(); microphoneRemainder.removeAll(); queuedSamples = 0
        timeout?.invalidate(); timeout = nil
        bootstrap?.cancel(); bootstrap = nil
        receiveTask?.cancel(); receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        engine.stop(); player.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        status = "Voice questions stopped; routine state unchanged"
    }

    private func fail(_ message: String) { stop(); status = message }

    private func receive(token: UUID) {
        guard let socket else { return }
        receiveTask = Task { [weak self] in
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
                    await MainActor.run {
                        guard let self, self.generation == token, self.active else { return }
                        self.handle(event)
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self, self.generation == token else { return }
                    self.fail("Voice connection ended. Routine state unchanged; offline help is available.")
                }
            }
        }
    }

    private func send(_ event: [String: Any], completion: (() -> Void)? = nil) {
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: event),
              let text = String(data: data, encoding: .utf8) else { return }
        let token = generation
        Task { [weak self] in
            do {
                try await socket.send(.string(text))
                await MainActor.run {
                    guard let self, self.generation == token else { return }
                    completion?()
                }
            } catch {
                await MainActor.run {
                    guard let self, self.generation == token else { return }
                    self.fail("Voice network is unavailable. Return to the check controls.")
                }
            }
        }
    }

    private func handle(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "session_ready":
            timeout?.invalidate(); timeout = nil
            do { try startAudio(); ready = true; status = "Voice Q&A live · microphone sent to Cartesia" }
            catch { fail("Audio could not start. End voice Q&A and use offline help.") }
        case "audio_output":
            guard let string = event["audio"] as? String, let data = Data(base64Encoded: string) else { return }
            play(data)
        case "audio_output_clear":
            playbackGeneration = UUID(); queuedSamples = 0
            player.stop(); player.play()
        case "turn_ended":
            // Transcript display only. This text never reaches RoutineSession or VoiceIntent.
            let turn = event["turn"] as? [String: Any] ?? event
            if let text = turn["text"] as? String {
                transcript = String((transcript + "\n" + text).suffix(4000))
            }
        case "client_tool_call":
            if event["expects_response"] as? Bool == true, let id = event["tool_call_id"] as? String {
                send(["type": "client_tool_result", "tool_call_id": id,
                      "result": "This practice assistant has no app-control tools. Ask the user to return to the check controls.", "is_error": true])
            }
        case "error": fail("Cartesia reported an error. Offline help remains available.")
        default: break
        }
    }

    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let converter = AVAudioConverter(from: format, to: wire) else {
            throw URLError(.cannotDecodeRawData)
        }
        let token = generation
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
                guard let self, self.generation == token, self.ready else { return }
                if gate.overflowed { self.fail("Voice audio fell behind. Reconnect Q&A; monitoring remains local."); return }
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
        engine.prepare(); try engine.start(); player.play()
    }

    private func enqueue(_ data: Data) {
        guard pending.count < 5 else { fail("Voice upload fell behind. Reconnect Q&A."); return }
        pending.append(data)
        flush()
    }
    private func flush() {
        guard ready, !sending, !pending.isEmpty else { return }
        sending = true
        let data = pending.removeFirst()
        send(["type": "audio_input", "audio": data.base64EncodedString()]) { [weak self] in
            self?.sending = false; self?.flush()
        }
    }
    private func play(_ data: Data) {
        guard ready, data.count > 0, data.count % 2 == 0, data.count <= 320_000 else { return }
        let count = data.count / 2
        guard queuedSamples + count <= 16_000 * 6,
              let buffer = AVAudioPCMBuffer(pcmFormat: playback, frameCapacity: AVAudioFrameCount(count)),
              let channel = buffer.floatChannelData?[0] else {
            fail("Voice playback fell behind. Reconnect Q&A."); return
        }
        buffer.frameLength = AVAudioFrameCount(count)
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for i in 0..<count {
                let value = UInt16(bytes[i * 2]) | UInt16(bytes[i * 2 + 1]) << 8
                channel[i] = Float(Int16(bitPattern: value)) / 32768
            }
        }
        queuedSamples += count
        let token = playbackGeneration
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == token else { return }
                self.queuedSamples = max(0, self.queuedSamples - count)
            }
        }
        if !player.isPlaying { player.play() }
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
