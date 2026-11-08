// Compile with RFDETRDetector.swift and Core/Sources/CaptureProbeCore/*.swift.
// Run from the repository root. Optional --direct-voice uses environment credentials.
import Foundation
import CoreML
import CoreVideo

@main enum ModelSmokeCheck {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "ArmGuardModelCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func main() async throws {
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let app = root.appendingPathComponent("ios/ArmGuardCaptureProbe/ArmGuardCaptureProbe")
        let compiled = try await MLModel.compileModel(at: app.appendingPathComponent("SterileParts.mlpackage"))
        defer { try? FileManager.default.removeItem(at: compiled) }
        let configuration = MLModelConfiguration(); configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: compiled, configuration: configuration)
        let detector = try RFDETRDetector(model: model)
        print("PASS: bundled model compiled and adapter loaded: \(detector.summary)")
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 64, 48, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else { throw URLError(.cannotDecodeRawData) }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let pixels = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<48 {
            for x in 0..<64 {
                let color: [UInt8] = y < 24 ? (x < 32 ? [0, 0, 255] : [0, 255, 0]) : (x < 32 ? [255, 0, 0] : [255, 255, 255])
                let offset = y * stride + x * 4
                for channel in 0..<3 { pixels[offset + channel] = color[channel] }
                pixels[offset + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        let input = try detector.prepareInput(pixelBuffer)
        let resolution = input.shape[2].intValue
        let mean: [Float] = [0.485, 0.456, 0.406], std: [Float] = [0.229, 0.224, 0.225]
        // Native top-left red / top-right green / bottom-left blue / bottom-right white.
        // Clockwise portrait must be blue-red / white-green, in tensor top-left coordinates.
        let corners: [(Int, Int, [Float])] = [(1, 1, [0, 0, 1]), (3, 1, [1, 0, 0]), (1, 3, [1, 1, 1]), (3, 3, [0, 1, 0])]
        for (x, y, expected) in corners {
            for channel in 0..<3 {
                let indices: [NSNumber] = [0, NSNumber(value: channel), NSNumber(value: y * resolution / 4), NSNumber(value: x * resolution / 4)]
                let value = input[indices].floatValue * std[channel] + mean[channel]
                try require(abs(value - expected[channel]) < 0.03, "RGB/portrait orientation mismatch at quadrant \(x),\(y), channel \(channel): \(value)")
            }
        }
        let again = try detector.prepareInput(pixelBuffer)
        try require(input.dataPointer == again.dataPointer, "Tensor is not reused")
        print("PASS: RGB channels, portrait orientation, normalization and input reuse")
        let features = try MLDictionaryFeatureProvider(dictionary: ["tensors": MLFeatureValue(multiArray: input)])
        let raw = try await model.prediction(from: features)
        if let boxes = raw.featureValue(for: "concat_2")?.multiArrayValue {
            let values = (0..<boxes.count).map { boxes[$0].floatValue }
            print("Model box range: \(values.min() ?? 0)...\(values.max() ?? 0); outside unit interval: \(values.filter { $0 < 0 || $0 > 1 }.prefix(8))")
        }
        _ = try detector.detect(pixelBuffer) // warm up, without claiming a meaningful image detection
        let start = ProcessInfo.processInfo.systemUptime
        let detections = try detector.detect(pixelBuffer)
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        try require(detections.allSatisfy { $0.box.width > 0 && $0.box.height > 0 && $0.confidence.isFinite }, "Invalid decoded output")
        print(String(format: "PASS: real model prediction and output decoding; warm Mac CPU processing %.1f ms (not iPhone latency)", elapsed))
        if CommandLine.arguments.contains("--direct-voice") {
            do { try await directVoice(app: app) }
            catch { fputs("FAIL: direct Cartesia request or WebSocket check\n", stderr); exit(1) }
        }
    }
    static func directVoice(app: URL) async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let key = environment["CARTESIA_API_KEY"], let voice = environment["CARTESIA_VOICE_ID"],
              let agent = environment["CARTESIA_AGENT_ID"] else { throw CartesiaRequests.RequestError.invalidConfiguration }
        let speech = try CartesiaRequests.speech(apiKey: key, voiceID: voice, text: "Ready when you are.")
        let (audio, response) = try await URLSession.shared.data(for: speech)
        try require((response as? HTTPURLResponse)?.statusCode == 200, "Direct speech request failed")
        _ = try WaveClip.finalized(audio)
        print("PASS: direct native Cartesia speech and streaming-WAV finalization; no gateway")
        let template = try JSONDecoder().decode(RoutineTemplate.self, from: Data(contentsOf: app.appendingPathComponent("Resources/RoutineTemplate.json")))
        let instructions = try String(contentsOf: app.appendingPathComponent("Resources/VoiceInstructions.txt"), encoding: .utf8)
        let request = try CartesiaRequests.agentSession(apiKey: key, voiceID: voice, agentID: agent,
            instructions: instructions, initialPrompt: template.checks[0].prompt, checks: template.checks,
            checkID: "room", phase: .checking)
        let (data, result) = try await URLSession.shared.data(for: request)
        try require((result as? HTTPURLResponse)?.statusCode == 200, "Direct session creation failed")
        let session = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        guard let value = session["url"] as? String, var parts = URLComponents(string: value),
              parts.scheme == "wss", ["api.cartesia.ai", "api-us.cartesia.ai"].contains(parts.host ?? ""),
              let token = session["token"] as? String else { throw URLError(.badServerResponse) }
        parts.queryItems = [URLQueryItem(name: "cartesia_version", value: "2026-08-14"), URLQueryItem(name: "access_token", value: token)]
        let socket = URLSession.shared.webSocketTask(with: parts.url!); socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        let deadline = Task { try await Task.sleep(nanoseconds: 20_000_000_000); socket.cancel(with: .goingAway, reason: nil) }
        defer { deadline.cancel() }
        try await socket.send(.string("{\"type\":\"session_create\",\"audio\":{\"input_format\":\"pcm_16000\",\"output_delivery\":\"speaking_pace\",\"continuous_input\":true}}"))
        var ready = false
        while true {
            let message = try await socket.receive()
            let bytes: Data
            switch message { case .data(let data): bytes = data; case .string(let text): bytes = Data(text.utf8); @unknown default: continue }
            let event = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            if event["type"] as? String == "session_ready" { ready = true }
            if event["type"] as? String == "error" { throw URLError(.badServerResponse) }
            if event["type"] as? String == "audio_output", let audio = event["audio"] as? String, !audio.isEmpty {
                try require(ready, "Agent emitted audio before readiness")
                print("PASS: direct native session creation, WebSocket readiness and agent audio; no gateway")
                return
            }
        }
    }
}
