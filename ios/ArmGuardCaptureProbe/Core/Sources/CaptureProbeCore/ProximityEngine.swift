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

/// One source for display/haptic severity. Detection outside an armed routine cannot alert.
public enum ProximityFeedback {
    /// Image-scale cues are independent of strict depth-monitoring/rehearsal phases.
    public static func distanceLevel(fresh: Bool, distanceMM: Double?, risk: RiskLevel) -> RiskLevel {
        guard fresh, let distanceMM, distanceMM.isFinite, distanceMM >= 0 else { return .none }
        return risk
    }
    public static func combinedLevel(phase: RoutinePhase?, fresh: Bool, decision: ProximityDecision,
                                     distanceMM: Double?, scaleRisk: RiskLevel) -> RiskLevel {
        max(level(phase: phase, fresh: fresh, decision: decision),
            distanceLevel(fresh: fresh, distanceMM: distanceMM, risk: scaleRisk))
    }
    public static func level(phase: RoutinePhase?, fresh: Bool, decision: ProximityDecision) -> RiskLevel {
        guard phase == .monitoring, fresh else { return .none }
        switch decision {
        case .projectedOverlap: return .high
        case .warning(let intensity, _): return intensity >= 200 ? .high : .medium
        default: return .none
        }
    }
}

public struct ScaleProximityMeasurement: Equatable {
    /// Closest hand-to-surface gap in image pixels (0 = overlapping in the image).
    public let distancePixels: Double
    /// Size in pixels of the reference sterile tip (largest detected tip).
    public let referencePixels: Double
    /// Normalized sensor-space endpoints of the closest gap, for drawing.
    public let handPoint: SensorPoint
    public let surfacePoint: SensorPoint
    /// Index (into the `regions` passed to `measure`) of the tip used as the size reference.
    public var referenceIndex = 0
}

/// The two connector tips the team uses. Sizes are fixed measurements and are not
/// user-editable: blue tip 8 mm at its tip; clear tip with red tubing 13 mm at the very top.
public enum ConnectorTip: String, CaseIterable {
    case blue, clear
    public var sizeMM: Double { self == .blue ? 8 : 13 }
    public var name: String { self == .blue ? "Blue tip" : "Clear tip" }
    public var detail: String { self == .blue ? "Blue connector · 8 mm" : "Clear connector, red tubing · 13 mm" }
    /// Identify a detected tip from its mean chroma (full-range YCbCr, 128 = neutral).
    /// Blue plastic has strongly raised Cb; a clear tip shows red tubing or background (neutral/raised Cr).
    public static func identify(meanCb: Double, meanCr: Double) -> ConnectorTip {
        let blueness = meanCb - 128, warmth = meanCr - 128
        return blueness > 10 && blueness - warmth > 15 ? .blue : .clear
    }
}

public enum ScaleProximity {
    /// - Parameters: all points/boxes in normalized sensor space; image size in pixels.
    /// Fingertips are preferred. Whole-hand boxes are used only when no fingertip is visible.
    public static func measure(fingertips: [SensorPoint], hands: [ProtectedRegion], regions: [ProtectedRegion],
                               imageWidth: Double, imageHeight: Double) -> ScaleProximityMeasurement? {
        let indexed = regions.enumerated().filter { $0.element.isValid }
        let regions = indexed.map(\.element)
        guard imageWidth > 0, imageHeight > 0, !regions.isEmpty else { return nil }
        // Reference: the largest sterile tip (the script picked the largest tumor polygon).
        guard let referenceEntry = indexed.max(by: { $0.element.width * $0.element.height
                                                     < $1.element.width * $1.element.height }) else { return nil }
        let reference = referenceEntry.element
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
        best?.referenceIndex = referenceEntry.offset
        return best
    }
}

/// Warning distances, fingertip to the tip's nearest edge. Defaults: HIGH within 10 mm,
/// MEDIUM within 30 mm. Editable in the app's Connectors sheet, saved on the phone and
/// applied to the tracker on every frame. HIGH always stays at least `minimumGapMM`
/// inside MEDIUM, so the two zones never overlap.
public enum WarningDistances {
    public static let defaultHighMM = 10.0
    public static let defaultMediumMM = 30.0
    public static let stepMM = 5.0
    public static let minimumGapMM = 5.0
    public static let lowestMM = 5.0
    public static let highestMM = 150.0
    public static let highKey = "warningDistanceMM.high"
    public static let mediumKey = "warningDistanceMM.medium"

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(max(value, low), high) }
    private static func stored(_ key: String) -> Double? {
        let value = UserDefaults.standard.double(forKey: key) // 0 when never set
        return value > 0 && value.isFinite ? value : nil
    }
    public static var highRangeMM: ClosedRange<Double> { lowestMM...(highestMM - minimumGapMM) }
    public static var mediumRangeMM: ClosedRange<Double> { (highMM + minimumGapMM)...highestMM }

    public static var highMM: Double {
        get { clamp(stored(highKey) ?? defaultHighMM, highRangeMM.lowerBound, highRangeMM.upperBound) }
        set {
            UserDefaults.standard.set(clamp(newValue, highRangeMM.lowerBound, highRangeMM.upperBound), forKey: highKey)
            if mediumMM < highMM + minimumGapMM { mediumMM = highMM + minimumGapMM } // push MEDIUM out
        }
    }
    public static var mediumMM: Double {
        get { clamp(stored(mediumKey) ?? defaultMediumMM, highMM + minimumGapMM, highestMM) }
        set { UserDefaults.standard.set(clamp(newValue, highMM + minimumGapMM, highestMM), forKey: mediumKey) }
    }
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: highKey)
        UserDefaults.standard.removeObject(forKey: mediumKey)
    }
    public static var isDefault: Bool { highMM == defaultHighMM && mediumMM == defaultMediumMM }
}

/// Decides when to speak a distance warning, so short cues don't pile up into noise.
/// The band and screen alert continuously; the voice only marks the danger getting worse:
/// - speak once when the level rises and has held for `dwellSeconds` (ignores flickers),
/// - stay quiet when the level drops (HIGH back to MEDIUM),
/// - repeat HIGH only every `repeatHighSeconds` while it lasts,
/// - start a new episode only after the hand has been clear for `clearResetSeconds`.
public struct WarningCuePolicy {
    public var dwellSeconds = 0.3
    public var repeatHighSeconds = 8.0
    public var clearResetSeconds = 1.0
    private var level: RiskLevel = .none
    private var levelSince = 0.0
    private var spoken: RiskLevel = .none
    private var lastSpoken = -Double.infinity

    public init() {}

    public mutating func reset() { level = .none; levelSince = 0; spoken = .none; lastSpoken = -.infinity }

    /// Feed the current level (any rate). Returns the level to announce now, or nil to stay quiet.
    public mutating func update(_ newLevel: RiskLevel, at now: Double) -> RiskLevel? {
        if newLevel != level { level = newLevel; levelSince = now }
        let held = now - levelSince
        if level == .none {
            if held >= clearResetSeconds { spoken = .none }
            return nil
        }
        guard held >= dwellSeconds else { return nil }
        let rising = level > spoken
        let repeatHigh = level == .high && now - lastSpoken >= repeatHighSeconds
        guard rising || repeatHigh else { return nil }
        spoken = max(spoken, level); lastSpoken = now
        return level
    }
}

/// Stateful smoothing + thresholds. Mirrors the constants block of SPINOSAURUS.py.
public struct ScaleRiskTracker {
    /// Real size of the sterile catheter tip as seen by the camera (longest side). MEASURE YOURS.
    // No assumed prop size: scale estimates are diagnostics until explicitly calibrated.
    public var sterileTipSizeMM: Double?
    public var highThresholdMM = WarningDistances.defaultHighMM     // <= this: HIGH RISK
    public var mediumThresholdMM = WarningDistances.defaultMediumMM // <= this: MEDIUM RISK
    public var scaleSmoothAlpha = 0.20    // SCALE_SMOOTH_ALPHA
    public var distanceSmoothAlpha = 0.25 // DISTANCE_SMOOTH_ALPHA
    /// Hysteresis: a level is only released once the distance is this far past its threshold,
    /// so a hand hovering at a boundary does not make the banner and band flicker.
    public var releaseMarginMM = 5.0
    public private(set) var mmPerPixel: Double?
    public private(set) var distanceMM: Double?
    public private(set) var current: RiskLevel = .none

    public init() {}

    public mutating func reset() { mmPerPixel = nil; distanceMM = nil; current = .none }

    private static func ema(_ previous: Double?, _ new: Double, _ alpha: Double) -> Double {
        guard let previous else { return new }
        return alpha * new + (1 - alpha) * previous
    }

    public mutating func update(_ measurement: ScaleProximityMeasurement?) -> RiskLevel {
        guard let size = sterileTipSizeMM, size.isFinite, size > 0,
              let measurement, measurement.referencePixels.isFinite, measurement.referencePixels > 0,
              measurement.distancePixels.isFinite, measurement.distancePixels >= 0 else {
            reset(); return .none
        }
        let scale = Self.ema(mmPerPixel, size / measurement.referencePixels, scaleSmoothAlpha)
        mmPerPixel = scale
        let raw = measurement.distancePixels * scale
        // Overlap reports immediately; smoothing must not delay the most serious case.
        let distance = raw == 0 ? 0 : Self.ema(distanceMM, raw, distanceSmoothAlpha)
        distanceMM = distance
        // Escalate immediately; de-escalate only past threshold + margin.
        var next = level(for: distance)
        if next < current {
            let held = current == .high ? highThresholdMM : mediumThresholdMM
            if distance <= held + releaseMarginMM { next = current }
        }
        current = next
        return next
    }

    public func level(for millimetres: Double) -> RiskLevel {
        if millimetres <= highThresholdMM { return .high }
        if millimetres <= mediumThresholdMM { return .medium }
        return .none
    }
}

/// Exact class roles. Whole connector bodies and ambiguous names are not protected openings.
public enum DetectionRole: String, Codable { case protectedOpening, fingertip, hand, ignored }

public enum DetectionLabels {
    public static func normalize(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
    }
    public static func role(for label: String) -> DetectionRole {
        switch normalize(label) {
        case "sterile_tip", "sterile_connector_tip", "cap_interior", "connector_opening", "catheter_tip": return .protectedOpening
        case "fingertip", "thumb_tip", "index_tip", "middle_tip", "ring_tip", "little_tip": return .fingertip
        case "hand", "hands", "glove", "gloved_hand": return .hand
        default: return .ignored
        }
    }
}

public struct DecodedDetection {
    public let label: String
    public let confidence: Float
    /// Portrait image, top-left origin. Conversion to sensor coordinates happens once downstream.
    public let box: ProtectedRegion
}

/// RF-DETR's exported contract: normalized cxcywh boxes, raw independent class logits.
/// Background index comes from training metadata, never from tensor width or label sorting.
public enum RFDETRDecoding {
    public enum DecodeError: Error { case invalidShape, invalidMetadata, nonFiniteOutput }
    public static func decode(boxes: [Float], logits: [Float], queries: Int, classCount: Int,
                              classes: [Int: String], backgroundClassID: Int?,
                              threshold: Float = 0.45) throws -> [DecodedDetection] {
        guard queries > 0, classCount > 0, boxes.count == queries * 4,
              logits.count == queries * classCount else { throw DecodeError.invalidShape }
        guard threshold.isFinite, threshold >= 0, threshold <= 1, !classes.isEmpty,
              classes.keys.allSatisfy({ $0 >= 0 && $0 < classCount }),
              backgroundClassID.map({ $0 >= 0 && $0 < classCount }) ?? true else { throw DecodeError.invalidMetadata }
        guard boxes.allSatisfy(\.isFinite), logits.allSatisfy(\.isFinite) else { throw DecodeError.nonFiniteOutput }
        var detections: [DecodedDetection] = []
        for query in 0..<queries {
            let values = Array(boxes[(query * 4)..<(query * 4 + 4)])
            var best: Int?
            for column in 0..<classCount where column != backgroundClassID {
                if best == nil || logits[query * classCount + column] > logits[query * classCount + best!] { best = column }
            }
            guard let best, let label = classes[best] else { continue }
            let raw = logits[query * classCount + best]
            let score: Float
            if raw >= 0 { score = 1 / (1 + exp(-raw)) }
            else { let exponential = exp(raw); score = exponential / (1 + exponential) }
            guard score >= threshold else { continue }
            // Normalized means image-relative units; boxes may extend beyond
            // the frame. Clip corners, never infer a different unit system.
            guard values[2] > 0, values[3] > 0 else { continue }
            let left = max(0, Double(values[0] - values[2] / 2))
            let top = max(0, Double(values[1] - values[3] / 2))
            let right = min(1, Double(values[0] + values[2] / 2))
            let bottom = min(1, Double(values[1] + values[3] / 2))
            guard right > left, bottom > top else { continue }
            detections.append(DecodedDetection(label: label, confidence: score,
                box: ProtectedRegion(x: left, y: top, width: right - left, height: bottom - top)))
        }
        return detections
    }
}

/// Per-session safety statistics for the summary screen and care-team share.
/// Practice feedback only: counts and times, not a sterility or cleanliness score.
public struct SafetyStats: Equatable {
    public private(set) var mediumAlerts = 0
    public private(set) var highAlerts = 0
    public private(set) var closestMM: Double?
    /// Seconds with a live distance measurement (calibrated, fresh, hand and tip in view).
    public private(set) var measuredSeconds = 0.0
    public private(set) var warningSeconds = 0.0
    public private(set) var longestSafeStreak = 0.0
    private var level: RiskLevel = .none
    private var lastTime: Double?
    private var safeStreak = 0.0

    public init() {}

    /// Seconds measured outside any warning zone, as a fraction of measured time (nil before any).
    public var safeFraction: Double? {
        measuredSeconds > 0 ? max(0, measuredSeconds - warningSeconds) / measuredSeconds : nil
    }
    public var alertCount: Int { mediumAlerts + highAlerts }

    /// Call often (every result / 100 ms). Gaps over 1 s are not counted as measured time.
    public mutating func record(level newLevel: RiskLevel, distanceMM: Double?, at time: Double, measuring: Bool) {
        defer { lastTime = measuring ? time : nil }
        guard measuring, let distanceMM, distanceMM.isFinite, distanceMM >= 0 else {
            level = .none; safeStreak = 0; return
        }
        closestMM = min(closestMM ?? distanceMM, distanceMM)
        if newLevel > level {
            if newLevel == .high { highAlerts += 1 } else { mediumAlerts += 1 }
        }
        if let lastTime, time > lastTime, time - lastTime <= 1 {
            let dt = time - lastTime
            measuredSeconds += dt
            if newLevel == .none {
                safeStreak += dt
                longestSafeStreak = max(longestSafeStreak, safeStreak)
            } else {
                warningSeconds += dt
                safeStreak = 0
            }
        }
        level = newLevel
    }
}


public enum DetectionConfidence {
    public static let defaultValue = 0.45
    private static let key = "sterling.previewConfidence"
    public static var preview: Double {
        get {
            let value = UserDefaults.standard.double(forKey: key)
            return value.isFinite && (0.1...0.9).contains(value) ? value : defaultValue
        }
        set {
            guard newValue.isFinite else { return }
            UserDefaults.standard.set(min(0.9, max(0.1, newValue)), forKey: key)
        }
    }
}
