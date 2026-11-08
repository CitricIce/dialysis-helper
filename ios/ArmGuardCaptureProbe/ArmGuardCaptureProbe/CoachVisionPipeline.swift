import ARKit
import CoreImage
import CoreML
import Vision

struct CoachDetectedObject {
    let label: String
    let confidence: Float
    let role: DetectionRole
    let region: ProtectedRegion // native sensor coordinates
}

struct CoachVisionSnapshot {
    var detections: [CoachDetectedObject] = []
    var debugImage: CGImage?
    var fingertips: [SensorPoint] = []
    var regions: [ProtectedRegion] = []
    var provider = "Apple Vision"
    var modelStatus = "Protected-part model not installed"
    var labelText = ""
    var decision: ProximityDecision = .unavailable("Waiting for observations")
    var receipt = 0.0
    var processingMilliseconds = 0.0
    var modelInstalled = false
    var modelUsable = false
    var detectorStatus: DetectorStatus = .placeholder
    var handCoverageComplete = false
    // Scale-reference proximity (SPINOSAURUS method)
    var hands: [ProtectedRegion] = []
    var scaleRisk: RiskLevel = .none
    var distanceMM: Double?
    var mmPerPixel: Double?
    var closestHand: SensorPoint?
    var closestSurface: SensorPoint?
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
    private var rfdetr: RFDETRDetector?   // Roboflow RF-DETR export (raw tensors, no Vision wrapper)
    private var attemptedModelLoad = false
    private var modelError = "Protected-part model not installed"
    private var scaleTracker = ScaleRiskTracker() // worker queue only; alerts only once a tip size is entered
    private var sterileTipSizeMM: Double? // protected by lock; nil = uncalibrated (no warnings)
    private var resetTracker = false
    private var labelRoles: [String: DetectionRole] = [:]
    private var minimumConfidence: Float = 0.45 // protected by lock
    private let includeDebugPreview: Bool
    private let detectorStatus: DetectorStatus
    private lazy var debugRenderer = FrameRenderer() // worker queue only

    init(includeDebugPreview: Bool = false) {
        self.includeDebugPreview = includeDebugPreview
        if let url = Bundle.main.url(forResource: "RoutineTemplate", withExtension: "json"),
           let data = try? Data(contentsOf: url), let template = try? JSONDecoder().decode(RoutineTemplate.self, from: data) {
            detectorStatus = template.detectorStatus ?? .placeholder
        } else { detectorStatus = .placeholder }
    }

    /// Measured sterile-tip size in mm (longest side). nil turns distance warnings off.
    func setSterileTipSize(_ millimetres: Double?) {
        let valid = millimetres.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        lock.lock(); sterileTipSizeMM = valid; resetTracker = true; lock.unlock()
    }

    func setConfidenceThreshold(_ value: Float) {
        guard value.isFinite else { return }
        lock.lock(); minimumConfidence = max(0.05, min(0.95, value)); lock.unlock()
    }

    private func classify(_ raw: String) -> DetectionRole {
        labelRoles[raw] ?? DetectionLabels.role(for: raw)
    }

    func setActive(_ enabled: Bool) {
        lock.lock()
        active = enabled
        generation = UUID()
        resetTracker = true
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
        let freshTracker = resetTracker
        resetTracker = false
        let confidence = minimumConfidence
        let tipSize = sterileTipSizeMM
        lock.unlock()
        worker.async { [weak self] in
            guard let self else { return }
            if freshTracker { self.scaleTracker.reset() }
            self.scaleTracker.sterileTipSizeMM = tipSize
            let output = autoreleasepool { () -> CoachVisionSnapshot in
                var output = self.process(frame, receipt: now, scanLabel: scan, confidence: confidence)
                if self.includeDebugPreview { output.debugImage = self.debugRenderer.colorPreview(frame) }
                return output
            }
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
            let loaded = try MLModel(contentsOf: url, configuration: configuration)
            let metadata = loaded.modelDescription.metadata[.creatorDefinedKey] as? [String: String] ?? [:]
            if let json = metadata["armguard_roles"]?.data(using: .utf8) {
                labelRoles = try JSONDecoder().decode([String: DetectionRole].self, from: json)
            }
            if loaded.modelDescription.inputDescriptionsByName.values.contains(where: { $0.type == .multiArray }) {
                let detector = try RFDETRDetector(model: loaded)
                rfdetr = detector
                modelError = "RF-DETR model loaded · \(detector.summary)"
            } else {
                model = try VNCoreMLModel(for: loaded)
                modelError = "Core ML model loaded; export and classes still require validation"
            }
        } catch { modelError = "Model failed to load: \(error.localizedDescription)" }
        if detectorStatus == .placeholder { modelError = "PLACEHOLDER · debug predictions only · " + modelError }
    }

    private func process(_ frame: ARFrame, receipt: Double, scanLabel: Bool, confidence: Float) -> CoachVisionSnapshot {
        let started = ProcessInfo.processInfo.systemUptime
        loadModelIfNeeded()
        var result = CoachVisionSnapshot()
        result.receipt = frame.timestamp // ARKit capture time, seconds since boot; includes camera delivery lag.
        result.modelInstalled = model != nil || rfdetr != nil
        result.detectorStatus = detectorStatus
        result.modelUsable = result.modelInstalled && detectorStatus == .experimental
        result.modelStatus = modelError
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)
        do {
            // Every detector is normalized to Vision coordinates: portrait, bottom-left origin.
            var detections: [(name: String, confidence: Float, box: CGRect)] = []
            do {
            if let rfdetr {
                detections = try rfdetr.detect(frame.capturedImage, threshold: confidence).map { found in
                    (name: found.className, confidence: found.confidence,
                     box: CGRect(x: found.box.minX, y: 1 - found.box.maxY, width: found.box.width, height: found.box.height))
                }
            } else if let model {
                let request = VNCoreMLRequest(model: model)
                request.imageCropAndScaleOption = .scaleFit
                try handler.perform([request])
                guard let objects = request.results as? [VNRecognizedObjectObservation] else {
                    throw CocoaError(.coderInvalidValue)
                }
                detections = objects.compactMap { object in
                    object.labels.first.map { (name: $0.identifier, confidence: $0.confidence, box: object.boundingBox) }
                }
            }
            } catch {
                result.modelUsable = false
                result.modelStatus += " · Prediction failed: \(error.localizedDescription)"
            }
            do {
                for object in detections {
                    guard object.confidence >= confidence else { continue }
                    let kind = classify(object.name)
                    let b = object.box
                    let region = ProtectedRegion(x: Double(1 - b.maxY), y: Double(1 - b.maxX),
                                                 width: Double(b.height), height: Double(b.width))
                    if region.isValid {
                        result.detections.append(CoachDetectedObject(label: object.name, confidence: object.confidence,
                                                                    role: kind, region: region))
                    }
                    if kind == .hand {
                        let left = max(0, min(1, Double(1 - b.maxY)))
                        let top = max(0, min(1, Double(1 - b.maxX)))
                        let right = max(0, min(1, Double(1 - b.minY)))
                        let bottom = max(0, min(1, Double(1 - b.minX)))
                        result.hands.append(ProtectedRegion(x: left, y: top, width: right - left, height: bottom - top))
                    } else if kind == .protectedOpening {
                        // Vision uses oriented portrait/bottom-left; risk uses native sensor/top-left.
                        let left = max(0, min(1, Double(1 - b.maxY)))
                        let top = max(0, min(1, Double(1 - b.maxX)))
                        let right = max(0, min(1, Double(1 - b.minY)))
                        let bottom = max(0, min(1, Double(1 - b.minX)))
                        result.regions.append(ProtectedRegion(x: left, y: top, width: right - left, height: bottom - top))
                    } else if kind == .fingertip {
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
            // SPINOSAURUS method: tip size -> mm/px -> fingertip-to-tip-edge distance -> MEDIUM/HIGH.
            // Uncalibrated (no tip size entered) it stays image-space only and returns .none.
            let measurement = ScaleProximity.measure(
                fingertips: result.fingertips, hands: result.hands, regions: result.regions,
                imageWidth: Double(CVPixelBufferGetWidth(frame.capturedImage)),
                imageHeight: Double(CVPixelBufferGetHeight(frame.capturedImage)))
            result.scaleRisk = scaleTracker.update(measurement)
            result.distanceMM = scaleTracker.distanceMM
            result.mmPerPixel = scaleTracker.mmPerPixel
            result.closestHand = measurement?.handPoint
            result.closestSurface = measurement?.surfacePoint
            if scanLabel {
                let text = VNRecognizeTextRequest()
                text.recognitionLevel = .accurate
                text.usesLanguageCorrection = false
                try handler.perform([text])
                result.labelText = (text.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n").prefix(1500).description
            }
            if detectorStatus == .placeholder {
                result.decision = .unavailable("Placeholder detector; distance monitoring is off. Camera images are a separate hardware test.")
            } else if result.modelInstalled && !result.modelUsable {
                result.decision = .unavailable("Object prediction failed; hand tracking alone cannot protect the opening")
            } else if model == nil && rfdetr == nil {
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
