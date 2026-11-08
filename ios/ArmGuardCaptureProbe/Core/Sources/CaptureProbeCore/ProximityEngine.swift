import Foundation

public struct SensorPoint: Equatable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

public struct ProtectedRegion {
    public let x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0
            && x + width <= 1.0001 && y + height <= 1.0001
    }
    public func nearest(to point: SensorPoint) -> SensorPoint {
        SensorPoint(x: max(x, min(x + width, point.x)), y: max(y, min(y + height, point.y)))
    }
}

public struct CameraPoint {
    public let x: Double, y: Double, z: Double
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
    public var isValid: Bool { x.isFinite && y.isFinite && z.isFinite && z > 0 }
    public func distance(to other: CameraPoint) -> Double {
        sqrt(pow(x - other.x, 2) + pow(y - other.y, 2) + pow(z - other.z, 2))
    }
}

public enum ProximityDecision: Equatable {
    case unavailable(String), clear, warning(UInt8, meters: Double), projectedOverlap
    public var intensity: UInt8 {
        switch self { case .warning(let value, _): return value; case .projectedOverlap: return 255; default: return 0 }
    }
}

public enum ProximityEngine {
    /// Experimental surface-boundary clearance. All input coordinates use unrotated sensor space.
    public static func evaluate(fingertips: [SensorPoint], regions: [ProtectedRegion],
                                warningMeters: Double = 0.05,
                                cameraPoint: (SensorPoint) -> CameraPoint?) -> ProximityDecision {
        guard warningMeters.isFinite, warningMeters > 0 else { return .unavailable("Invalid threshold") }
        guard !fingertips.isEmpty, fingertips.allSatisfy(\.isValid) else { return .unavailable("Hands unavailable") }
        guard !regions.isEmpty, regions.allSatisfy(\.isValid) else { return .unavailable("Protected surfaces unavailable") }
        var minimum = Double.infinity
        var missingDepth = false
        for fingertip in fingertips {
            for region in regions {
                let boundary = region.nearest(to: fingertip)
                // Sampling depth twice at the same overlapped pixel would falsely manufacture zero gap.
                if boundary == fingertip { return .projectedOverlap }
                guard let hand = cameraPoint(fingertip), let surface = cameraPoint(boundary),
                      hand.isValid, surface.isValid else { missingDepth = true; continue }
                minimum = min(minimum, hand.distance(to: surface))
            }
        }
        // A known close hazard still warns, even if another pair has invalid depth.
        if minimum < warningMeters {
            let strength = 80 + 175 * max(0, min(1, 1 - minimum / warningMeters))
            return .warning(UInt8(strength.rounded()), meters: minimum)
        }
        if missingDepth || !minimum.isFinite { return .unavailable("Depth insufficient for one or more hazard pairs") }
        return .clear
    }
}

public enum BandProtocolMode: String, CaseIterable { case legacy, intensityV2 }

public enum DepthProjection {
    /// Reject mixed foreground/background patches instead of manufacturing precise boundary depth.
    public static func cameraPoint(_ point: SensorPoint, grid: DepthGrid, imageWidth: Double,
                                    imageHeight: Double, fx: Double, fy: Double, cx: Double, cy: Double) -> CameraPoint? {
        guard point.isValid, [imageWidth, imageHeight, fx, fy, cx, cy].allSatisfy(\.isFinite),
              imageWidth > 0, imageHeight > 0, fx > 0, fy > 0 else { return nil }
        let x = min(grid.width - 1, Int(point.x * Double(grid.width)))
        let y = min(grid.height - 1, Int(point.y * Double(grid.height)))
        var values: [Double] = []
        for row in max(0, y - 1)...min(grid.height - 1, y + 1) {
            for column in max(0, x - 1)...min(grid.width - 1, x + 1) {
                let depth = grid.depth(x: column, y: row)
                if depth.isFinite, depth > 0, let confidence = grid.confidence(x: column, y: row), confidence == 1 || confidence == 2 {
                    values.append(Double(depth))
                }
            }
        }
        guard values.count >= 3, let low = values.min(), let high = values.max(), high - low <= 0.02 else { return nil }
        values.sort()
        let z = values[values.count / 2]
        return CameraPoint(x: (point.x * imageWidth - cx) * z / fx,
                           y: (point.y * imageHeight - cy) * z / fy, z: z)
    }
}

public enum BandEncoding {
    public static func payload(intensity: UInt8, suspected: Bool, mode: BandProtocolMode) -> [UInt8] {
        if mode == .legacy {
            return [suspected ? 69 : (intensity > 0 ? 87 : 83)] // E / W / S
        }
        return [suspected ? 2 : (intensity > 0 ? 1 : 0), intensity]
    }
}

// MARK: - Scale-reference proximity (ported from SPINOSAURUS.py)
//
// Same method as the tumor/nerve script:
//   1. mm-per-pixel comes from an object of known physical size (there: the 3 mm
//      tumor; here: the sterile catheter tip), smoothed with an EMA.
//   2. Distance = pixels from the hand to the CLOSEST EDGE of the protected
//      region (cv2.pointPolygonTest), converted to mm and EMA-smoothed.
//   3. Two thresholds give MEDIUM and HIGH risk.
// Difference from the script: a hand point inside the sterile region counts as
// 0 mm (the script's abs() would report the distance to the edge instead).

public enum RiskLevel: Int, Comparable {
    case none = 0, medium, high
    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ScaleProximityMeasurement: Equatable {
    /// Closest hand-to-surface gap in image pixels (0 = overlapping in the image).
    public let distancePixels: Double
    /// Size in pixels of the reference sterile tip (largest detected tip).
    public let referencePixels: Double
    /// Normalized sensor-space endpoints of the closest gap, for drawing.
    public let handPoint: SensorPoint
    public let surfacePoint: SensorPoint
}

public enum ScaleProximity {
    /// - Parameters: all points/boxes in normalized sensor space; image size in pixels.
    /// Fingertips are preferred. Whole-hand boxes are used only when no fingertip is visible.
    public static func measure(fingertips: [SensorPoint], hands: [ProtectedRegion], regions: [ProtectedRegion],
                               imageWidth: Double, imageHeight: Double) -> ScaleProximityMeasurement? {
        let regions = regions.filter(\.isValid)
        guard imageWidth > 0, imageHeight > 0, !regions.isEmpty else { return nil }
        // Reference: the largest sterile tip (the script picked the largest tumor polygon).
        guard let reference = regions.max(by: { $0.width * $0.height * imageWidth * imageHeight
                                                 < $1.width * $1.height * imageWidth * imageHeight }) else { return nil }
        let referencePixels = max(1, max(reference.width * imageWidth, reference.height * imageHeight))

        func pixels(_ a: SensorPoint, _ b: SensorPoint) -> Double {
            hypot((a.x - b.x) * imageWidth, (a.y - b.y) * imageHeight)
        }
        var best: ScaleProximityMeasurement?
        func consider(_ distance: Double, _ hand: SensorPoint, _ surface: SensorPoint) {
            if best == nil || distance < best!.distancePixels {
                best = ScaleProximityMeasurement(distancePixels: distance, referencePixels: referencePixels,
                                                 handPoint: hand, surfacePoint: surface)
            }
        }
        let tips = fingertips.filter(\.isValid)
        if !tips.isEmpty {
            for tip in tips {
                for region in regions {
                    let edge = region.nearest(to: tip)   // == tip when the tip is inside the box
                    consider(pixels(tip, edge), tip, edge)
                }
            }
        } else {
            for hand in hands where hand.isValid {
                for region in regions {
                    // Closest points between two boxes (0 when they overlap).
                    let hx = max(hand.x, min(hand.x + hand.width, region.x + region.width / 2))
                    let hy = max(hand.y, min(hand.y + hand.height, region.y + region.height / 2))
                    let handPoint = SensorPoint(x: hx, y: hy)
                    let edge = region.nearest(to: handPoint)
                    let refined = hand.nearest(to: edge)
                    consider(pixels(refined, edge), refined, edge)
                }
            }
        }
        return best
    }
}

/// Stateful smoothing + thresholds. Mirrors the constants block of SPINOSAURUS.py.
public struct ScaleRiskTracker {
    /// Real size of the sterile catheter tip as seen by the camera (longest side). MEASURE YOURS.
    public var sterileTipSizeMM = 10.0
    public var highThresholdMM = 30.0     // <= this: HIGH RISK
    public var mediumThresholdMM = 80.0   // <= this: MEDIUM RISK
    public var scaleSmoothAlpha = 0.20    // SCALE_SMOOTH_ALPHA
    public var distanceSmoothAlpha = 0.25 // DISTANCE_SMOOTH_ALPHA
    public private(set) var mmPerPixel: Double?
    public private(set) var distanceMM: Double?

    public init() {}

    public mutating func reset() { mmPerPixel = nil; distanceMM = nil }

    private static func ema(_ previous: Double?, _ new: Double, _ alpha: Double) -> Double {
        guard let previous else { return new }
        return alpha * new + (1 - alpha) * previous
    }

    public mutating func update(_ measurement: ScaleProximityMeasurement?) -> RiskLevel {
        guard let measurement else { distanceMM = nil; return .none }
        let scale = Self.ema(mmPerPixel, sterileTipSizeMM / measurement.referencePixels, scaleSmoothAlpha)
        mmPerPixel = scale
        let raw = measurement.distancePixels * scale
        // Overlap reports immediately; smoothing must not delay the most serious case.
        distanceMM = raw == 0 ? 0 : Self.ema(distanceMM, raw, distanceSmoothAlpha)
        return level(for: distanceMM!)
    }

    public func level(for millimetres: Double) -> RiskLevel {
        if millimetres <= highThresholdMM { return .high }
        if millimetres <= mediumThresholdMM { return .medium }
        return .none
    }
}
