import ARKit
import AVFoundation
import Combine
import UIKit

final class CaptureController: NSObject, ObservableObject, ARSessionDelegate {
    @Published private(set) var snapshot = ProbeSnapshot()
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var needsSettings = false
    @Published private(set) var status = "Ready to test camera and rear LiDAR."
    @Published private(set) var tracking = "Not started"
    @Published private(set) var cameraFPS = 0.0
    @Published private(set) var depthFPS = 0.0
    @Published private(set) var frameCount = 0
    @Published private(set) var depthFrameCount = 0
    @Published private(set) var cameraFresh = false
    @Published private(set) var depthFresh = false
    @Published private(set) var previewFresh = false

    let supportsLiDAR = ARWorldTrackingConfiguration.isSupported
        && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)

    private let session = ARSession()
    private let delegateQueue = DispatchQueue(label: "org.armguard.probe.frames", qos: .userInitiated)
    private let renderQueue = DispatchQueue(label: "org.armguard.probe.preview", qos: .userInitiated)
    private let renderer = FrameRenderer()
    // Configure before starting capture; the observer must enqueue work and return immediately.
    var frameObserver: ((ARFrame) -> Void)?
    private let stateLock = NSLock()
    private var pipeline = PipelineState()
    private var healthTimer: Timer?
    private var rateBaseline = (time: 0.0, frames: 0, depth: 0)
    private var previewReceipt: Double?
    private var permissionRequest: UUID?

    private struct PipelineState {
        var runID: UUID?
        var busy = false
        var frames = 0
        var depth = 0
        var lastCamera: Double?
        var lastDepth: Double?
        var lastPreviewDispatch = -Double.infinity
    }

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = delegateQueue
    }

    private func withState<T>(_ body: (inout PipelineState) -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body(&pipeline)
    }

    /// UI entry point. Camera frames/rendering never execute on the main queue.
    func start() {
        guard !isRunning, !isStarting else { return }
        needsSettings = false
        guard supportsLiDAR else {
            status = "Rear LiDAR unavailable. Use an iPhone Pro with LiDAR, such as the 15 Pro. A standard iPhone 16 cannot pass this test."
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginSession()
        case .notDetermined:
            let request = UUID()
            permissionRequest = request
            isStarting = true
            status = "Allow camera access to start the hardware test."
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.permissionRequest == request else { return }
                    self.permissionRequest = nil
                    self.isStarting = false
                    if granted {
                        self.beginSession()
                    } else {
                        self.showPermissionError()
                    }
                }
            }
        case .denied, .restricted:
            showPermissionError()
        @unknown default:
            status = "Unknown camera permission state."
        }
    }

    private func showPermissionError() {
        needsSettings = true
        status = "Camera permission is unavailable. Enable Camera for this app in Settings, then press Start."
    }

    private func beginSession() {
        guard UIApplication.shared.applicationState == .active else {
            status = "Return to the app and press Start."
            return
        }
        withState { $0 = PipelineState(runID: UUID()) }
        snapshot = ProbeSnapshot()
        frameCount = 0
        depthFrameCount = 0
        cameraFPS = 0
        depthFPS = 0
        cameraFresh = false
        depthFresh = false
        previewFresh = false
        previewReceipt = nil
        tracking = "Initializing"
        status = "Starting camera; waiting for RGB and LiDAR frames…"
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.sceneDepth]
        // Lower capture rate when a native 30 fps format is available; never invent the delivered rate.
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats.filter { $0.framesPerSecond == 30 }
        if let format = formats.min(by: {
            abs($0.imageResolution.width - 1920) < abs($1.imageResolution.width - 1920)
        }) {
            configuration.videoFormat = format
        }
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        rateBaseline = (ProcessInfo.processInfo.systemUptime, 0, 0)
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        healthTimer?.invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateHealth()
        }
    }

    func stop(reason: String = "Stopped. Press Start for a new test.") {
        permissionRequest = nil
        isStarting = false
        withState { $0.runID = nil }
        session.pause()
        healthTimer?.invalidate()
        healthTimer = nil
        isRunning = false
        cameraFresh = false
        depthFresh = false
        previewFresh = false
        cameraFPS = 0
        depthFPS = 0
        tracking = "Paused"
        status = reason
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func updateHealth() {
        guard isRunning else { return }
        let state = withState { $0 }
        let now = ProcessInfo.processInfo.systemUptime
        cameraFresh = FrameFreshness.isFresh(lastReceipt: state.lastCamera, now: now)
        depthFresh = FrameFreshness.isFresh(lastReceipt: state.lastDepth, now: now)
        previewFresh = FrameFreshness.isFresh(lastReceipt: previewReceipt, now: now)
        frameCount = state.frames
        depthFrameCount = state.depth
        let elapsed = now - rateBaseline.time
        if elapsed >= 1 {
            cameraFPS = Double(state.frames - rateBaseline.frames) / elapsed
            depthFPS = Double(state.depth - rateBaseline.depth) / elapsed
            rateBaseline = (now, state.frames, state.depth)
        }
        if !cameraFresh {
            status = state.frames == 0 ? "Waiting for the first camera frame…" : "Camera feed stalled. Press Stop, then Start."
        } else if !depthFresh {
            status = "Camera is live, but LiDAR depth is missing or stale."
        } else if !previewFresh {
            status = "Frames are arriving, but the displayed measurement is stale."
        } else {
            status = "Camera and LiDAR are delivering frames."
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard withState({ $0.runID }) != nil else { return }
        frameObserver?(frame)
        let receipt = ProcessInfo.processInfo.systemUptime
        let token: UUID? = withState { state in
            guard let runID = state.runID else { return nil }
            state.frames += 1
            state.lastCamera = receipt
            if frame.sceneDepth != nil {
                state.depth += 1
                state.lastDepth = receipt
            }
            // One in-flight render, no queue of old frames, at most 10 preview updates/sec.
            guard !state.busy, receipt - state.lastPreviewDispatch >= 0.1 else { return nil }
            state.busy = true
            state.lastPreviewDispatch = receipt
            return runID
        }
        guard let token else { return }
        renderQueue.async { [weak self] in
            guard let self, self.withState({ $0.runID }) == token else { return }
            let rendered = autoreleasepool { self.renderer.render(frame) }
            DispatchQueue.main.async {
                guard self.isRunning, self.withState({ $0.runID }) == token else { return }
                // Hold the gate until UI delivery too: a blocked main queue must not accumulate images.
                self.withState { $0.busy = false }
                self.snapshot = rendered
                // Use the source frame's receipt, not render completion, for stale-result detection.
                self.previewReceipt = receipt
                self.updateHealth()
            }
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let message: String
        switch camera.trackingState {
        case .normal: message = "Normal"
        case .notAvailable: message = "Unavailable"
        case .limited(let reason):
            switch reason {
            case .initializing: message = "Initializing"
            case .excessiveMotion: message = "Limited: movement"
            case .insufficientFeatures: message = "Limited: few visual features"
            case .relocalizing: message = "Relocalizing"
            @unknown default: message = "Limited"
            }
        }
        let token = withState { $0.runID }
        DispatchQueue.main.async { [weak self] in
            guard let self, let token, self.isRunning, self.withState({ $0.runID }) == token else { return }
            self.tracking = message
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.stop(reason: "Capture failed: \(error.localizedDescription)")
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.stop(reason: "Camera interrupted. Return here and press Start to resume.")
        }
    }

    var diagnostics: String {
        let summary = snapshot.summary
        let center = previewFresh && depthFresh ? summary?.centerMeters.map { String(format: "%.3f m", $0) } : nil
        return """
        ArmGuard Capture Probe 0.2 (build 2)
        Exported: \(ISO8601DateFormatter().string(from: Date()))
        Device: \(UIDevice.current.model), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        Rear scene-depth supported: \(supportsLiDAR)
        Running: \(isRunning)
        Status: \(status)
        AR tracking: \(tracking)
        Frames: \(frameCount); depth-bearing frames: \(depthFrameCount)
        Camera: \(snapshot.colorResolution), \(String(format: "%.1f", cameraFPS)) fps
        Depth: \(snapshot.depthResolution), \(String(format: "%.1f", depthFPS)) fps
        Camera/depth/preview fresh: \(cameraFresh)/\(depthFresh)/\(previewFresh)
        Center depth: \(center ?? "unavailable or stale")
        Finite depth: \(String(format: "%.1f", (summary?.finiteFraction ?? 0) * 100))%
        Medium/high-confidence depth: \(String(format: "%.1f", (summary?.usableFraction ?? 0) * 100))%
        Confidence map present: \(snapshot.hasConfidence)
        Last preview conversion: \(String(format: "%.1f", snapshot.processingMilliseconds)) ms
        AR frame timestamp: \(snapshot.frameTimestamp) s
        Note: \(snapshot.note)
        Depth mode: sceneDepth (not smoothedSceneDepth)
        Center depth is camera Z, not a finger-to-connector gap.
        Preview timing is NOT sensor-to-screen or motor latency.
        """
    }
}
