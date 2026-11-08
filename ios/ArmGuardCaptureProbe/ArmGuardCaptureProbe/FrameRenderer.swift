import ARKit
import CoreImage
import ImageIO
import UIKit

struct ProbeSnapshot {
    var colorImage: CGImage?
    var depthImage: CGImage?
    var colorResolution = "—"
    var depthResolution = "—"
    var summary: DepthSummary?
    var hasConfidence = false
    var processingMilliseconds = 0.0
    var frameTimestamp = 0.0
    var note = "Waiting for capture."
}

/// Runs only on the render worker. Preview conversion is capped at 10 Hz, independent of capture.
final class FrameRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func colorPreview(_ frame: ARFrame) -> CGImage? {
        portraitImage(CIImage(cvPixelBuffer: frame.capturedImage), maximumDimension: 960)
    }

    func render(_ frame: ARFrame) -> ProbeSnapshot {
        let started = ProcessInfo.processInfo.systemUptime
        let color = frame.capturedImage
        var result = ProbeSnapshot()
        result.frameTimestamp = frame.timestamp
        result.colorResolution = "\(CVPixelBufferGetWidth(color)) × \(CVPixelBufferGetHeight(color))"
        // The app is portrait-only. Both full sensor images are rotated, never independently cropped.
        result.colorImage = colorPreview(frame)
        if let depth = frame.sceneDepth {
            do {
                let grid = try Self.copyGrid(depth)
                result.depthResolution = "\(grid.width) × \(grid.height)"
                result.hasConfidence = grid.confidence != nil
                result.summary = DepthAnalyzer.summarize(grid)
                result.depthImage = heatmap(grid)
                result.note = result.summary?.centerMeters == nil
                    ? "Depth arrived; center has no usable medium/high-confidence samples."
                    : "Scene depth received without temporal smoothing. Center value is distance from camera, not a contact gap."
            } catch {
                result.note = "Depth buffer could not be read: \(error.localizedDescription)"
            }
        } else {
            result.note = "RGB arrived; waiting for LiDAR depth."
        }
        result.processingMilliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        return result
    }

    private func portraitImage(_ source: CIImage, maximumDimension: CGFloat? = nil) -> CGImage? {
        var image = source.oriented(.right)
        if let maximumDimension {
            let largest = max(image.extent.width, image.extent.height)
            if largest > maximumDimension {
                let scale = maximumDimension / largest
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }
        return context.createCGImage(image, from: image.extent)
    }

    static func copyGrid(_ depth: ARDepthData) throws -> DepthGrid {
        let map = depth.depthMap
        guard CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32 else {
            throw ReadError.unexpectedPixelFormat
        }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let address = CVPixelBufferGetBaseAddress(map) else { throw ReadError.missingBuffer }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let stride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float>.stride
        let values = Array(UnsafeBufferPointer(start: address.assumingMemoryBound(to: Float.self),
                                              count: stride * height))
        var confidenceValues: [UInt8]?
        var confidenceStride = 0
        if let confidence = depth.confidenceMap {
            guard CVPixelBufferGetWidth(confidence) == width,
                  CVPixelBufferGetHeight(confidence) == height,
                  CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8 else {
                throw ReadError.unexpectedConfidenceLayout
            }
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
            guard let confidenceAddress = CVPixelBufferGetBaseAddress(confidence) else {
                throw ReadError.missingBuffer
            }
            confidenceStride = CVPixelBufferGetBytesPerRow(confidence)
            confidenceValues = Array(UnsafeBufferPointer(
                start: confidenceAddress.assumingMemoryBound(to: UInt8.self),
                count: confidenceStride * height))
        }
        return try DepthGrid(width: width, height: height, rowStride: stride, values: values,
                             confidenceRowStride: confidenceStride, confidence: confidenceValues)
    }

    private func heatmap(_ grid: DepthGrid) -> CGImage? {
        var pixels = [UInt8]()
        pixels.reserveCapacity(grid.width * grid.height * 4)
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let color = DepthColorMap.rgba(depth: grid.depth(x: x, y: y),
                                              confidence: grid.confidence(x: x, y: y))
                pixels.append(contentsOf: [color.0, color.1, color.2, color.3])
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: grid.width, height: grid.height,
                                  bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: grid.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        return portraitImage(CIImage(cgImage: image))
    }

    private enum ReadError: LocalizedError {
        case unexpectedPixelFormat, unexpectedConfidenceLayout, missingBuffer
        var errorDescription: String? {
            switch self {
            case .unexpectedPixelFormat: return "Expected floating-point depth in meters."
            case .unexpectedConfidenceLayout: return "Confidence dimensions or pixel format do not match depth."
            case .missingBuffer: return "Pixel buffer has no readable base address."
            }
        }
    }
}
