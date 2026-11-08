import Foundation
import CoreML
import CoreImage
import CoreGraphics
import CoreVideo

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
    private let detsName: String
    private let labelsName: String
    private let backgroundClassID: Int?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var rgba: [UInt8]
    private let inputTensor: MLMultiArray
    private let features: MLDictionaryFeatureProvider
    private let mean: [Float] = [0.485, 0.456, 0.406]
    private let std: [Float] = [0.229, 0.224, 0.225]

    var summary: String {
        let names = classNames.sorted { $0.key < $1.key }.map(\.value).joined(separator: ", ")
        return "\(resolution)px · classes: \(names.isEmpty ? "metadata missing" : names)"
    }

    enum ModelError: LocalizedError {
        case contract(String)
        var errorDescription: String? {
            if case .contract(let detail) = self { return detail }
            return nil
        }
    }
    init(model: MLModel) throws {
        let description = model.modelDescription
        guard description.inputDescriptionsByName.count == 1,
              let entry = description.inputDescriptionsByName.first,
              entry.value.type == .multiArray, let constraint = entry.value.multiArrayConstraint else {
            throw ModelError.contract("RF-DETR needs one NCHW input")
        }
        let shape = constraint.shape.map(\.intValue)
        guard shape.count == 4, shape[0] == 1, shape[1] == 3,
              shape[2] == shape[3], (32...2048).contains(shape[2]),
              [.float16, .float32, .double].contains(constraint.dataType) else {
            throw ModelError.contract("Unsupported RF-DETR input shape or type")
        }
        let metadata = description.metadata[.creatorDefinedKey] as? [String: String] ?? [:]
        guard let d = metadata["dets_output"], let l = metadata["labels_output"], d != l,
              description.outputDescriptionsByName[d]?.type == .multiArray,
              description.outputDescriptionsByName[l]?.type == .multiArray,
              metadata["armguard_box_format"] == "normalized_cxcywh",
              metadata["armguard_score_encoding"] == "logits",
              let background = metadata["armguard_background_class_id"],
              background == "none" || Int(background) != nil,
              let json = metadata["classes"]?.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: json), !decoded.isEmpty else {
            throw ModelError.contract("RF-DETR metadata is incomplete. Re-export with the verified class IDs and background slot.")
        }
        var names: [Int: String] = [:]
        for (key, value) in decoded {
            guard let index = Int(key), index >= 0, names[index] == nil, !value.isEmpty else {
                throw ModelError.contract("Invalid RF-DETR class IDs")
            }
            names[index] = value
        }
        let tensor = try MLMultiArray(shape: [1, 3, NSNumber(value: shape[2]), NSNumber(value: shape[2])], dataType: constraint.dataType)
        inputTensor = tensor
        features = try MLDictionaryFeatureProvider(dictionary: [entry.key: MLFeatureValue(multiArray: tensor)])
        self.model = model
        inputName = entry.key; inputType = constraint.dataType; resolution = shape[2]
        rgba = [UInt8](repeating: 0, count: shape[2] * shape[2] * 4)
        classNames = names; detsName = d; labelsName = l
        backgroundClassID = background == "none" ? nil : Int(background)
    }

    func prepareInput(_ buffer: CVPixelBuffer) throws -> MLMultiArray {
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
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: r, height: r, bitsPerComponent: 8, bytesPerRow: r * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .low // bilinear, matching resize without antialiasing
            context.draw(image, in: CGRect(x: 0, y: 0, width: r, height: r))
            return true
        }
        guard rendered else { throw ModelError.contract("Could not prepare model input") }
        let input = inputTensor
        let strides = input.strides.map(\.intValue)
        switch inputType {
        case .float16: fill(input.dataPointer.assumingMemoryBound(to: Float16.self), strides) { Float16($0) }
        case .double: fill(input.dataPointer.assumingMemoryBound(to: Double.self), strides) { Double($0) }
        case .float32: fill(input.dataPointer.assumingMemoryBound(to: Float.self), strides) { $0 }
        default: throw ModelError.contract("Unsupported input tensor type")
        }
        return input
    }

    func detect(_ buffer: CVPixelBuffer, threshold: Float = 0.45) throws -> [Detection] {
        _ = try prepareInput(buffer)
        let output = try model.prediction(from: features)
        guard let pair = outputs(output) else { throw CocoaError(.coderInvalidValue) }
        let dets = pair.dets, labels = pair.labels

        guard dets.cols == 4, dets.rows == labels.rows else { throw ModelError.contract("RF-DETR output shapes differ") }
        return try RFDETRDecoding.decode(boxes: dets.values, logits: labels.values,
            queries: dets.rows, classCount: labels.cols, classes: classNames,
            backgroundClassID: backgroundClassID, threshold: threshold).map {
                Detection(className: $0.label, confidence: $0.confidence,
                          box: CGRect(x: $0.box.x, y: $0.box.y, width: $0.box.width, height: $0.box.height))
            }
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
        guard let dets = provider.featureValue(for: detsName)?.multiArrayValue,
              let labels = provider.featureValue(for: labelsName)?.multiArrayValue,
              let boxes = Self.matrix(dets), let scores = Self.matrix(labels) else { return nil }
        return (boxes, scores)
    }

    /// Copies the last two dimensions of a (1, Q, K) array into a dense Float matrix.
    private static func matrix(_ array: MLMultiArray) -> Matrix? {
        let shape = array.shape.map(\.intValue), strides = array.strides.map(\.intValue)
        guard shape.count == 3, shape[0] == 1, shape[1] > 0, shape[2] > 0 else { return nil }
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
