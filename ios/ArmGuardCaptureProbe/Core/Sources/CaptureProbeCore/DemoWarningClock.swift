import Foundation

/// Deterministic trigger for demo voice/BLE outputs. It never creates a detector observation.
public struct DemoWarningClock {
    public let delaySeconds: Double
    private var checkID: String?
    private var elapsed = 0.0
    private var lastTick: Double?
    private var wasRunning = false
    private var fired = false

    public init(delaySeconds: Double = 8) { self.delaySeconds = max(0, delaySeconds) }
    public mutating func reset() {
        checkID = nil; elapsed = 0; lastTick = nil; wasRunning = false; fired = false
    }
    /// Feed foreground routine state; a pause freezes elapsed time, and a new step starts afresh.
    public mutating func update(enabled: Bool, checkID next: String?, phase: RoutinePhase?, at now: Double) -> Bool {
        guard enabled, now.isFinite, let next, next == "connect" || next == "disconnect" else { reset(); return false }
        if phase == .paused, checkID == next {
            wasRunning = false; lastTick = now; return false
        }
        guard phase == .monitoring || phase == .unmonitoredPractice else { reset(); return false }
        if checkID != next { reset(); checkID = next }
        if wasRunning, let lastTick, now >= lastTick { elapsed += now - lastTick }
        lastTick = now; wasRunning = true
        guard !fired, elapsed >= delaySeconds else { return false }
        fired = true; return true
    }
}
