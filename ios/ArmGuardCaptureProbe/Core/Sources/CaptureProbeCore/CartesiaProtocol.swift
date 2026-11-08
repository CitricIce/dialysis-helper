import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CartesiaRequests {
    public enum RequestError: Error { case invalidConfiguration }
    private static func request(path: String, apiKey: String, payload: [String: Any]) throws -> URLRequest {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RequestError.invalidConfiguration }
        var request = URLRequest(url: URL(string: "https://api.cartesia.ai/" + path)!)
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("2026-08-14", forHTTPHeaderField: "Cartesia-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }
    public static func agentSession(apiKey: String, voiceID: String, agentID: String,
                                    instructions: String, initialPrompt: String, checks: [RoutineCheck],
                                    checkID: String, phase: RoutinePhase, detectorStatus: DetectorStatus = .placeholder) throws -> URLRequest {
        guard !voiceID.isEmpty, !instructions.isEmpty, !checks.isEmpty,
              agentID.range(of: "^[A-Za-z0-9_-]{1,150}$", options: .regularExpression) != nil else { throw RequestError.invalidConfiguration }
        let context: [String: Any] = ["starting_check_id": checkID, "starting_phase": phase.rawValue,
            "detector_status": detectorStatus.rawValue, "camera_access": "on_device_derived_observations",
            "checks": try JSONSerialization.jsonObject(with: JSONEncoder().encode(checks))]
        let data = try JSONSerialization.data(withJSONObject: context)
        let trustedContext = String(decoding: data, as: UTF8.self)
        return try request(path: "v1/agents/websocket/" + agentID + "/sessions", apiKey: apiKey, payload: [
            "config_overrides": ["instructions": instructions + trustedContext, "initial_message": initialPrompt,
                "language": ["primary": "en"], "audio": ["output": ["voice_id": voiceID, "speed": 1.0]]]])
    }
    public static func speech(apiKey: String, voiceID: String, text: String) throws -> URLRequest {
        guard !voiceID.isEmpty, !text.isEmpty, text.count <= 2000 else { throw RequestError.invalidConfiguration }
        return try request(path: "tts/bytes", apiKey: apiKey, payload: ["model_id": "sonic-3.6", "voice": voiceID,
            "transcript": text, "language": "en", "output_format": ["container": "wav", "encoding": "pcm_s16le", "sample_rate": 44100]])
    }
}

public enum WaveClip {
    public enum FormatError: Error { case invalidWAV }
    /// Replace open-ended streaming lengths with actual complete-clip lengths.
    public static func finalized(_ bytes: Data) throws -> Data {
        var data = Array(bytes)
        guard data.count >= 44, data.count <= 5_000_000,
              String(bytes: data[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: data[8..<12], encoding: .ascii) == "WAVE" else { throw FormatError.invalidWAV }
        func read(_ position: Int) -> UInt32 {
            UInt32(data[position]) | UInt32(data[position + 1]) << 8 | UInt32(data[position + 2]) << 16 | UInt32(data[position + 3]) << 24
        }
        func write(_ position: Int, _ value: UInt32) {
            for index in 0..<4 { data[position + index] = UInt8(truncatingIfNeeded: value >> (8 * index)) }
        }
        var offset = 12
        var pcm = false
        while offset + 8 <= data.count {
            let name = String(bytes: data[offset..<(offset + 4)], encoding: .ascii)
            let length = Int(read(offset + 4))
            let start = offset + 8
            if name == "fmt " {
                guard length >= 16, length <= data.count - start,
                      data[start] == 1, data[start + 1] == 0, // PCM
                      data[start + 2] == 1, data[start + 3] == 0, // mono
                      read(start + 4) == 44100, data[start + 14] == 16, data[start + 15] == 0 else { throw FormatError.invalidWAV }
                pcm = true
            }
            if name == "data" {
                let actual = length == Int(UInt32.max) || length > data.count - start ? data.count - start : length
                guard pcm, actual > 0, actual % 2 == 0 else { throw FormatError.invalidWAV }
                write(offset + 4, UInt32(actual))
                write(4, UInt32(data.count - 8))
                return Data(data)
            }
            guard length <= data.count - start else { throw FormatError.invalidWAV }
            offset = start + length + length % 2
        }
        throw FormatError.invalidWAV
    }
}
