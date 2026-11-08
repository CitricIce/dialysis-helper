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
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onUserUtterance: ((String, Int) -> Void)?
    var onTool: ((String, [String: Any]) -> (String, Bool))?
    private var toolResults: [String: (String, Bool)] = [:]
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
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
    private var queuedSamples = 0
    private var playbackGeneration = UUID()
    private let audioGate = AudioDeliveryGate()

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playback)
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
        transcript = ""; lastReply = ""; toolResults.removeAll()
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
        playbackGeneration = UUID()
        active = false; ready = false; sending = false
        pending.removeAll(); microphoneRemainder.removeAll(); queuedSamples = 0
        timeout?.cancel(); timeout = nil
        bootstrap?.cancel(); bootstrap = nil
        receiveTask?.cancel(); receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        engine.stop(); player.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        status = "Voice stopped"
    }

    private func fail(_ message: String) { stop(); status = message; onFailure?(message) }

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
            do { try startAudio(); ready = true; status = "Listening"; onReady?() }
            catch { fail("Microphone or speaker could not start.") }
        case "audio_output":
            guard let string = event["audio"] as? String, let data = Data(base64Encoded: string) else { return }
            status = "Speaking"
            play(data)
        case "audio_output_clear":
            playbackGeneration = UUID(); queuedSamples = 0
            player.stop(); player.play()
        case "turn_ended":
            if let text = event["text"] as? String {
                transcript = String((transcript + "\n" + text).suffix(4000))
                if event["role"] as? String == "user", let turn = event["turn"] as? Int {
                    onUserUtterance?(text, turn)
                } else if event["role"] as? String == "assistant" { lastReply = text }
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
        case "error": fail("Cartesia reported an error.")
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
        engine.prepare(); try engine.start(); player.play()
    }

    private func enqueue(_ data: Data) {
        guard pending.count < 5 else { fail("Voice connection fell behind."); return }
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
            fail("Voice playback fell behind."); return
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
                if self.queuedSamples == 0 { self.status = "Listening" }
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
