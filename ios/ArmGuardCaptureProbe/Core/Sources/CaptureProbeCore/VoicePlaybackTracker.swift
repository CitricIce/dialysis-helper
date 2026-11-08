import Foundation

/// Playback callbacks can arrive after stop/clear. Only the current epoch owns its queue.
public struct VoicePlaybackTracker {
    public enum Issue: Equatable { case playbackStalled, replyAudioMissing }
    public private(set) var epoch = UUID()
    public private(set) var queuedSamples = 0
    private var progressAt: Double?
    private var replyHadAudio = false
    private var replyCancelled = false
    private var missingAudioDeadline: Double?
    public init() {}

    public mutating func beginReply() {
        replyHadAudio = false; replyCancelled = false; missingAudioDeadline = nil
    }
    public mutating func cancelReplyExpectation() { replyCancelled = true; missingAudioDeadline = nil }
    public mutating func receivedAudio() { replyHadAudio = true; missingAudioDeadline = nil }
    public mutating func endedReply(at now: Double, hasText: Bool, interrupted: Bool) {
        if hasText && !interrupted && !replyCancelled && !replyHadAudio {
            missingAudioDeadline = now + 8
        }
    }
    public mutating func clear(cancelReply: Bool = true) {
        epoch = UUID(); queuedSamples = 0; progressAt = nil
        if cancelReply { replyCancelled = true; missingAudioDeadline = nil }
    }
    public mutating func schedule(samples: Int, at now: Double) -> Bool {
        guard samples > 0, samples <= 96_000, queuedSamples + samples <= 96_000 else { return false }
        if queuedSamples == 0 { progressAt = now }
        queuedSamples += samples
        return true
    }
    @discardableResult public mutating func completed(samples: Int, epoch: UUID, at now: Double) -> Bool {
        guard epoch == self.epoch else { return false }
        queuedSamples = max(0, queuedSamples - samples)
        progressAt = queuedSamples == 0 ? nil : now
        return true
    }
    public func issue(at now: Double) -> Issue? {
        if let deadline = missingAudioDeadline, now >= deadline { return .replyAudioMissing }
        if queuedSamples > 0, let progressAt,
           now - progressAt > max(3, Double(queuedSamples) / 16_000 + 1) { return .playbackStalled }
        return nil
    }
}

/// Notification bursts and persistent hardware failures must not create an endless restart loop.
public struct VoiceRecoveryBudget {
    private var attempts: [Double] = []
    public init() {}
    public mutating func take(at now: Double) -> Bool {
        attempts.removeAll { now - $0 > 15 }
        guard attempts.count < 2 else { return false }
        attempts.append(now); return true
    }
}
