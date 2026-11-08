import ARKit
import CoreML
import Vision

struct CoachVisionSnapshot {
    var fingertips: [SensorPoint] = []
    var regions: [ProtectedRegion] = []
    var provider = "Apple Vision"
    var modelStatus = "Protected-part model not installed"
    var labelText = ""
    var decision: ProximityDecision = .unavailable("Waiting for observations")
    var receipt = 0.0
    var processingMilliseconds = 0.0
    var modelInstalled = false
    var handCoverageComplete = false
}

final class CoachVisionPipeline {
    var onResult: ((CoachVisionSnapshot) -> Void)?
    private let worker = DispatchQueue(label: "org.armguard.coach.vision", qos: .userInitiated)
    private let lock = NSLock()
    private var active = false
    private var busy = false
    private var generation = UUID()
    private var lastSubmission = -Double.infinity
    private var wantsOCR = false
    private var model: VNCoreMLModel?
    private var attemptedModelLoad = false
    private var modelError = "Protected-part model not installed"
    private let protectedLabels: Set<String> = ["sterile_tip", "cap_interior", "connector_opening"]
    private let fingertipLabels: Set<String> = ["fingertip", "thumb_tip", "index_tip", "middle_tip", "ring_tip", "little_tip"]

    func setActive(_ enabled: Bool) {
        lock.lock()
        active = enabled
        generation = UUID()
        wantsOCR = false
        lock.unlock()
    }

    func requestLabelRead() {
        lock.lock(); wantsOCR = true; lock.unlock()
    }

    func submit(_ frame: ARFrame) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard active, !busy, now - lastSubmission >= 1.0 / 15.0 else { lock.unlock(); return }
        busy = true
        lastSubmission = now
        let token = generation
        let scan = wantsOCR
        wantsOCR = false
        lock.unlock()
        worker.async { [weak self] in
            guard let self else { return }
            let output = autoreleasepool { self.process(frame, receipt: now, scanLabel: scan) }
            DispatchQueue.main.async {
                self.lock.lock()
                let publish = self.active && self.generation == token
                self.busy = false
                self.lock.unlock()
                if publish { self.onResult?(output) }
            }
        }
    }

    private func loadModelIfNeeded() {
        guard !attemptedModelLoad else { return }
        attemptedModelLoad = true
        guard let url = Bundle.main.url(forResource: "SterileParts", withExtension: "mlmodelc") else { return }
        do {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            model = try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: configuration))
            modelError = "Core ML model loaded; export and classes still require validation"
        } catch { modelError = "Model failed to load: \(error.localizedDescription)" }
    }

    private func process(_ frame: ARFrame, receipt: Double, scanLabel: Bool) -> CoachVisionSnapshot {
        let started = ProcessInfo.processInfo.systemUptime
        loadModelIfNeeded()
        var result = CoachVisionSnapshot()
        result.receipt = frame.timestamp // ARKit capture time, seconds since boot; includes camera delivery lag.
        result.modelInstalled = model != nil
        result.modelStatus = modelError
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)
        do {
            if let model {
                let request = VNCoreMLRequest(model: model)
                request.imageCropAndScaleOption = .scaleFit
                try handler.perform([request])
                guard let objects = request.results as? [VNRecognizedObjectObservation] else {
                    result.decision = .unavailable("Model must export Vision object observations with NMS")
                    return result
                }
                for object in objects {
                    guard let label = object.labels.first, label.confidence >= 0.6 else { continue }
                    let name = label.identifier.lowercased()
                    let b = object.boundingBox
                    if protectedLabels.contains(name) {
                        // Vision uses oriented portrait/bottom-left; risk uses native sensor/top-left.
                        let left = max(0, min(1, Double(1 - b.maxY)))
                        let top = max(0, min(1, Double(1 - b.maxX)))
                        let right = max(0, min(1, Double(1 - b.minY)))
                        let bottom = max(0, min(1, Double(1 - b.minX)))
                        result.regions.append(ProtectedRegion(x: left, y: top, width: right - left, height: bottom - top))
                    } else if fingertipLabels.contains(name) {
                        result.fingertips.append(SensorPoint(x: Double(1 - b.midY), y: Double(1 - b.midX)))
                    }
                    // Whole-hand centroids are intentionally not substituted for fingertip positions.
                }
            }
            let hasCustomTips = !result.fingertips.isEmpty
            let hands = VNDetectHumanHandPoseRequest()
            hands.maximumHandCount = 2
            try handler.perform([hands])
            let tips: [VNHumanHandPoseObservation.JointName] = [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
            var completeHands = 0
            for hand in hands.results ?? [] {
                let points = try hand.recognizedPoints(.all)
                var visible = 0
                for name in tips {
                    if let point = points[name], point.confidence >= 0.5 {
                        visible += 1
                        let candidate = SensorPoint(x: Double(1 - point.location.y), y: Double(1 - point.location.x))
                        // Fill missing custom tips, rather than abandoning all fallback coverage
                        // as soon as the custom model finds a single finger.
                        if !result.fingertips.contains(where: { hypot($0.x - candidate.x, $0.y - candidate.y) < 0.01 }) {
                            result.fingertips.append(candidate)
                        }
                    }
                }
                if visible == tips.count { completeHands += 1 }
            }
            result.handCoverageComplete = completeHands == 2
            result.provider = hasCustomTips ? "Custom fingertips + Apple coverage/fallback" : "Apple Vision pretrained fingertips"
            if scanLabel {
                let text = VNRecognizeTextRequest()
                text.recognitionLevel = .accurate
                text.usesLanguageCorrection = false
                try handler.perform([text])
                result.labelText = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n").prefix(1500).description
            }
            if model == nil {
                result.decision = .unavailable("Protected-part model not installed; hand tracking alone cannot protect a connector")
            } else if let depth = frame.sceneDepth, let grid = try? FrameRenderer.copyGrid(depth) {
                let tooSmall = result.regions.contains {
                    $0.width * Double(grid.width) < 2 || $0.height * Double(grid.height) < 2
                }
                if tooSmall {
                    result.decision = .unavailable("Protected surface is smaller than usable depth resolution")
                } else {
                    let k = frame.camera.intrinsics
                    let width = Double(CVPixelBufferGetWidth(frame.capturedImage))
                    let height = Double(CVPixelBufferGetHeight(frame.capturedImage))
                    result.decision = ProximityEngine.evaluate(fingertips: result.fingertips, regions: result.regions) {
                        DepthProjection.cameraPoint($0, grid: grid, imageWidth: width, imageHeight: height,
                                                    fx: Double(k[0][0]), fy: Double(k[1][1]),
                                                    cx: Double(k[2][0]), cy: Double(k[2][1]))
                    }
                }
            } else { result.decision = .unavailable("LiDAR depth is missing or unreadable") }
        } catch { result.decision = .unavailable("Vision failed: \(error.localizedDescription)") }
        result.processingMilliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
        return result
    }
}
