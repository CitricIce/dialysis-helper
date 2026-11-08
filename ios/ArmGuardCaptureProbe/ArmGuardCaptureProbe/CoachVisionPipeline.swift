import ARKit
import CoreImage
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
    private let protectedLabels: Set<String> = ["sterile_tip", "cap_interior", "connector_opening"]
    private let fingertipLabels: Set<String> = ["fingertip", "thumb_tip", "index_tip", "middle_tip", "ring_tip", "little_tip"]
    private let handLabels: Set<String> = ["hand", "hands", "glove", "gloved_hand"]
    private var scaleTracker = ScaleRiskTracker()   // touched only on the worker queue
    private var resetTracker = false

    /// Roboflow class names vary ("Sterile Tip", "catheter-tip"...). Normalize, then match loosely.
    private enum Kind { case protected, fingertip, hand, other }
    private func classify(_ raw: String) -> Kind {
        let name = raw.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
        if fingertipLabels.contains(name) || name.contains("finger") || name.contains("thumb") { return .fingertip }
        if protectedLabels.contains(name) || name.contains("sterile") || name.contains("catheter")
            || name.contains("connector") || name.contains("tip") { return .protected }
        if handLabels.contains(name) || name.contains("hand") { return .hand }
        return .other
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
        lock.unlock()
        worker.async { [weak self] in
            guard let self else { return }
            if freshTracker { self.scaleTracker.reset() }
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
            let loaded = try MLModel(contentsOf: url, configuration: configuration)
            if let detector = RFDETRDetector(model: loaded) {
                rfdetr = detector
                modelError = "RF-DETR model loaded · \(detector.summary)"
            } else {
                model = try VNCoreMLModel(for: loaded)
                modelError = "Core ML model loaded; export and classes still require validation"
            }
        } catch { modelError = "Model failed to load: \(error.localizedDescription)" }
    }

    private func process(_ frame: ARFrame, receipt: Double, scanLabel: Bool) -> CoachVisionSnapshot {
        let started = ProcessInfo.processInfo.systemUptime
        loadModelIfNeeded()
        var result = CoachVisionSnapshot()
        result.receipt = frame.timestamp // ARKit capture time, seconds since boot; includes camera delivery lag.
        result.modelInstalled = model != nil || rfdetr != nil
        result.modelStatus = modelError
        let handler = VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right)
        do {
            // Every detector is normalized to Vision coordinates: portrait, bottom-left origin.
            var detections: [(name: String, confidence: Float, box: CGRect)] = []
            if let rfdetr {
                detections = try rfdetr.detect(frame.capturedImage).map { found in
                    (name: found.className, confidence: found.confidence,
                     box: CGRect(x: found.box.minX, y: 1 - found.box.maxY, width: found.box.width, height: found.box.height))
                }
            } else if let model {
                let request = VNCoreMLRequest(model: model)
                request.imageCropAndScaleOption = .scaleFit
                try handler.perform([request])
                guard let objects = request.results as? [VNRecognizedObjectObservation] else {
                    result.decision = .unavailable("Model must export Vision object observations with NMS")
                    return result
                }
                detections = objects.compactMap { object in
                    object.labels.first.map { (name: $0.identifier, confidence: $0.confidence, box: object.boundingBox) }
                }
            }
            do {
                for object in detections {
                    guard object.confidence >= 0.45 else { continue } // CONFIDENCE_THRESH
                    let kind = classify(object.name)
                    let b = object.box
                    if kind == .hand {
                        let left = max(0, min(1, Double(1 - b.maxY)))
                        let top = max(0, min(1, Double(1 - b.maxX)))
                        let right = max(0, min(1, Double(1 - b.minY)))
                        let bottom = max(0, min(1, Double(1 - b.minX)))
                        result.hands.append(ProtectedRegion(x: left, y: top, width: right - left, height: bottom - top))
                    } else if kind == .protected {
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
            // SPINOSAURUS method: known-size sterile tip -> mm/px, closest-edge distance -> MEDIUM/HIGH.
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
            if model == nil && rfdetr == nil {
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

/// Runs a Roboflow RF-DETR Core ML export (`rfdetr` package, `model.export(format="coreml")`).
/// Input: one float MultiArray (1, 3, R, R), RGB, squashed to R x R, ImageNet-normalized.
/// Outputs: dets (1, Q, 4) as normalized cx, cy, w, h and labels (1, Q, C) as class logits.
/// DETR models predict a fixed set of queries, so no NMS is needed.
/// scripts/export_rfdetr_coreml.py stores class names and output names in the model metadata.
final class RFDETRDetector {
    struct Detection {
        let className: String
        let confidence: Float
        let box: CGRect   // portrait, top-left origin, normalized 0...1
    }

    private let model: MLModel
    private let inputName: String
    private let inputType: MLMultiArrayDataType
    private let resolution: Int
    private let classNames: [Int: String]
    private let detsName: String?
    private let labelsName: String?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var rgba: [UInt8]
    private let mean: [Float] = [0.485, 0.456, 0.406]
    private let std: [Float] = [0.229, 0.224, 0.225]
    var threshold: Float = 0.45

    var summary: String {
        let names = classNames.sorted { $0.key < $1.key }.map(\.value).joined(separator: ", ")
        return "\(resolution)px · classes: \(names.isEmpty ? "metadata missing" : names)"
    }

    init?(model: MLModel) {
        let description = model.modelDescription
        guard let entry = description.inputDescriptionsByName.first(where: { $0.value.type == .multiArray }),
              let constraint = entry.value.multiArrayConstraint else { return nil }
        let shape = constraint.shape.map(\.intValue)
        guard shape.count == 4, shape[1] == 3, shape[2] == shape[3], shape[2] > 0,
              description.outputDescriptionsByName.count >= 2 else { return nil }
        self.model = model
        inputName = entry.key
        inputType = constraint.dataType
        resolution = shape[2]
        rgba = [UInt8](repeating: 0, count: shape[2] * shape[2] * 4)
        let metadata = description.metadata[.creatorDefinedKey] as? [String: String] ?? [:]
        detsName = metadata["dets_output"]
        labelsName = metadata["labels_output"]
        if let json = metadata["classes"]?.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: String].self, from: json) {
            classNames = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in Int(key).map { ($0, value) } })
        } else { classNames = [:] }
    }

    func detect(_ buffer: CVPixelBuffer) throws -> [Detection] {
        let r = resolution
        // Same upright orientation the Vision requests use (.right), then stretch to R x R.
        let upright = CIImage(cvPixelBuffer: buffer).oriented(.right)
        let extent = upright.extent
        let squared = upright
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(r) / extent.width, y: CGFloat(r) / extent.height))
        guard let image = ciContext.createCGImage(squared, from: CGRect(x: 0, y: 0, width: r, height: r)) else {
            throw CocoaError(.featureUnsupported)
        }
        rgba.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: r, height: r, bitsPerComponent: 8, bytesPerRow: r * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: r, height: r))
        }
        let input = try MLMultiArray(shape: [1, 3, NSNumber(value: r), NSNumber(value: r)], dataType: inputType)
        let strides = input.strides.map(\.intValue)
        switch inputType {
        case .float16: fill(input.dataPointer.assumingMemoryBound(to: Float16.self), strides) { Float16($0) }
        case .double: fill(input.dataPointer.assumingMemoryBound(to: Double.self), strides) { Double($0) }
        default: fill(input.dataPointer.assumingMemoryBound(to: Float.self), strides) { $0 }
        }
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: input)]))
        guard let pair = outputs(output) else { throw CocoaError(.coderInvalidValue) }
        let dets = pair.dets, labels = pair.labels

        let logits = labels.values.contains { $0 < 0 || $0 > 1 }
        let pixelBoxes = dets.values.contains { $0 > 1.5 }
        var found: [Detection] = []
        for query in 0..<min(dets.rows, labels.rows) {
            var bestClass = 0
            var bestScore = -Float.infinity
            for k in 0..<labels.cols where labels.values[query * labels.cols + k] > bestScore {
                bestScore = labels.values[query * labels.cols + k]; bestClass = k
            }
            let score = logits ? 1 / (1 + exp(-bestScore)) : bestScore
            guard score >= threshold else { continue }
            var v = Array(dets.values[(query * 4)..<(query * 4 + 4)])
            if pixelBoxes { v = v.map { $0 / Float(r) } }
            let left = max(0, min(1, v[0] - v[2] / 2)), top = max(0, min(1, v[1] - v[3] / 2))
            let right = max(0, min(1, v[0] + v[2] / 2)), bottom = max(0, min(1, v[1] + v[3] / 2))
            guard right > left, bottom > top else { continue }
            found.append(Detection(className: classNames[bestClass] ?? "class_\(bestClass)", confidence: score,
                                   box: CGRect(x: CGFloat(left), y: CGFloat(top),
                                               width: CGFloat(right - left), height: CGFloat(bottom - top))))
        }
        return found
    }

    private func fill<T>(_ pointer: UnsafeMutablePointer<T>, _ strides: [Int], _ convert: (Float) -> T) {
        let r = resolution
        rgba.withUnsafeBufferPointer { pixels in
            for y in 0..<r {
                for x in 0..<r {
                    let p = (y * r + x) * 4
                    for c in 0..<3 {
                        let value = (Float(pixels[p + c]) / 255 - mean[c]) / std[c]
                        pointer[c * strides[1] + y * strides[2] + x * strides[3]] = convert(value)
                    }
                }
            }
        }
    }

    private typealias Matrix = (rows: Int, cols: Int, values: [Float])

    private func outputs(_ provider: MLFeatureProvider) -> (dets: Matrix, labels: Matrix)? {
        var arrays: [String: Matrix] = [:]
        for name in provider.featureNames {
            if let array = provider.featureValue(for: name)?.multiArrayValue, let matrix = Self.matrix(array) {
                arrays[name] = matrix
            }
        }
        if let d = detsName, let l = labelsName, let dets = arrays[d], let labels = arrays[l] { return (dets, labels) }
        // Without metadata: boxes are the output whose last dimension is 4.
        guard let dets = arrays.first(where: { $0.value.cols == 4 }),
              let labels = arrays.first(where: { $0.key != dets.key }) else { return nil }
        return (dets.value, labels.value)
    }

    /// Copies the last two dimensions of a (1, Q, K) array into a dense Float matrix.
    private static func matrix(_ array: MLMultiArray) -> Matrix? {
        let shape = array.shape.map(\.intValue), strides = array.strides.map(\.intValue)
        guard shape.count >= 2 else { return nil }
        let rows = shape[shape.count - 2], cols = shape[shape.count - 1]
        let rs = strides[shape.count - 2], cs = strides[shape.count - 1]
        var values = [Float](repeating: 0, count: rows * cols)
        func copy<T>(_ type: T.Type, _ toFloat: (T) -> Float) {
            let p = array.dataPointer.assumingMemoryBound(to: T.self)
            for r in 0..<rows { for c in 0..<cols { values[r * cols + c] = toFloat(p[r * rs + c * cs]) } }
        }
        switch array.dataType {
        case .float32: copy(Float.self) { $0 }
        case .float16: copy(Float16.self) { Float($0) }
        case .double: copy(Double.self) { Float($0) }
        default: return nil
        }
        return (rows, cols, values)
    }
}
