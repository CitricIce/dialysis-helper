import Foundation

/// A copied sensor buffer, including row padding. Distances are camera-space Z in meters.
public struct DepthGrid {
    public let width: Int
    public let height: Int
    public let rowStride: Int
    public let values: [Float]
    public let confidenceRowStride: Int
    public let confidence: [UInt8]?

    public init(width: Int, height: Int, rowStride: Int, values: [Float],
                confidenceRowStride: Int = 0, confidence: [UInt8]? = nil) throws {
        guard width > 0, height > 0, rowStride >= width,
              rowStride <= Int.max / height, values.count >= rowStride * height else {
            throw BufferError.invalidDepthLayout
        }
        if let confidence {
            guard confidenceRowStride >= width, confidenceRowStride <= Int.max / height,
                  confidence.count >= confidenceRowStride * height else {
                throw BufferError.invalidConfidenceLayout
            }
        }
        self.width = width
        self.height = height
        self.rowStride = rowStride
        self.values = values
        self.confidenceRowStride = confidenceRowStride
        self.confidence = confidence
    }

    public enum BufferError: Error {
        case invalidDepthLayout
        case invalidConfidenceLayout
    }

    public func depth(x: Int, y: Int) -> Float { values[y * rowStride + x] }
    public func confidence(x: Int, y: Int) -> UInt8? {
        confidence.map { $0[y * confidenceRowStride + x] }
    }
}

public struct DepthSummary {
    public let centerMeters: Double?
    public let centerSampleCount: Int
    public let finiteFraction: Double
    public let usableFraction: Double
    public let highConfidenceFraction: Double?
}

public enum DepthAnalyzer {
    /// Center uses a small patch of medium/high confidence samples; not a finger-to-tip gap.
    public static func summarize(_ grid: DepthGrid, centerRadius: Int = 2) -> DepthSummary {
        var finiteCount = 0
        var usableCount = 0
        var highCount = 0
        var center: [Float] = []
        let radius = max(0, min(centerRadius, max(grid.width, grid.height)))
        let centerX = grid.width / 2
        let centerY = grid.height / 2
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                let depth = grid.depth(x: x, y: y)
                guard depth.isFinite, depth > 0 else { continue }
                finiteCount += 1
                // Missing confidence is unknown, not evidence of usable depth.
                guard let confidence = grid.confidence(x: x, y: y),
                      confidence == 1 || confidence == 2 else { continue }
                usableCount += 1
                if confidence == 2 { highCount += 1 }
                if abs(x - centerX) <= radius && abs(y - centerY) <= radius {
                    center.append(depth)
                }
            }
        }
        center.sort()
        let median: Double?
        if center.isEmpty {
            median = nil
        } else if center.count.isMultiple(of: 2) {
            median = (Double(center[center.count / 2 - 1]) + Double(center[center.count / 2])) / 2
        } else {
            median = Double(center[center.count / 2])
        }
        let total = Double(grid.width * grid.height)
        return DepthSummary(centerMeters: median, centerSampleCount: center.count,
                            finiteFraction: Double(finiteCount) / total,
                            usableFraction: Double(usableCount) / total,
                            highConfidenceFraction: grid.confidence == nil ? nil : Double(highCount) / total)
    }
}

public enum DepthColorMap {
    /// Fixed 0.15–2 m scale. Black = invalid, gray = unknown/low confidence.
    public static func rgba(depth: Float, confidence: UInt8?) -> (UInt8, UInt8, UInt8, UInt8) {
        guard depth.isFinite, depth > 0 else { return (0, 0, 0, 255) }
        guard let confidence, confidence == 1 || confidence == 2 else { return (48, 48, 48, 255) }
        let t = max(0, min(1, (depth - 0.15) / 1.85))
        let red = UInt8(255 * (1 - t))
        let green = UInt8(180 * (1 - abs(2 * t - 1)))
        let blue = UInt8(255 * t)
        return (red, green, blue, 255)
    }
}

public enum FrameFreshness {
    public static func isFresh(lastReceipt: Double?, now: Double, timeout: Double = 0.75) -> Bool {
        guard let lastReceipt, lastReceipt.isFinite, now.isFinite, timeout.isFinite,
              timeout > 0, now >= lastReceipt else { return false }
        return now - lastReceipt <= timeout
    }
}
