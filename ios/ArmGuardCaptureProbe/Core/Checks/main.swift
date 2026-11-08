// Portable logic checks: no XCTest or iOS SDK required.
import Foundation
import CaptureProbeCore

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure(description: message) }
}

func expectThrow(_ body: () throws -> Void) throws {
    var didThrow = false
    do { try body() } catch { didThrow = true }
    try expect(didThrow, "Malformed layout was accepted")
}

var checks: [(String, () throws -> Void)] = [
    ("Padded rows preserve usable center median", {
        let grid = try DepthGrid(width: 3, height: 2, rowStride: 4,
                                 values: [1, 2, 3, 999, 4, 5, 6, 999],
                                 confidenceRowStride: 5, confidence: [2, 2, 2, 0, 0, 2, 2, 2, 0, 0])
        let summary = DepthAnalyzer.summarize(grid)
        try expect(summary.centerMeters == 3.5, "Padding affected median")
        try expect(summary.centerSampleCount == 6 && summary.usableFraction == 1, "Incorrect sample counts")
    }),
    ("Invalid and low-confidence values do not become zero distance", {
        let grid = try DepthGrid(width: 3, height: 2, rowStride: 3,
                                 values: [.nan, .infinity, 0, -1, 0.01, 2],
                                 confidenceRowStride: 3, confidence: [2, 2, 2, 2, 0, 1])
        let summary = DepthAnalyzer.summarize(grid)
        try expect(summary.centerMeters == 2 && summary.centerSampleCount == 1, "Unusable sample entered median")
        try expect(abs(summary.finiteFraction - 2.0 / 6.0) < 0.0001, "Incorrect finite fraction")
        try expect(abs(summary.usableFraction - 1.0 / 6.0) < 0.0001, "Incorrect usable fraction")
    }),
    ("Missing confidence and wholly invalid depth remain unknown", {
        let unknown = try DepthGrid(width: 1, height: 1, rowStride: 1, values: [0.5])
        let unknownSummary = DepthAnalyzer.summarize(unknown)
        try expect(unknownSummary.centerMeters == nil && unknownSummary.highConfidenceFraction == nil,
                   "Missing confidence presented as a reliable reading")
        try expect(unknownSummary.finiteFraction == 1 && unknownSummary.usableFraction == 0, "Unknown sample counted usable")
        let invalid = try DepthGrid(width: 1, height: 1, rowStride: 1, values: [.nan],
                                    confidenceRowStride: 1, confidence: [2])
        try expect(DepthAnalyzer.summarize(invalid).centerMeters == nil, "Invalid sample became a reading")
    }),
    ("Center patch excludes distant foreground and handles a one-pixel map", {
        var values = [Float](repeating: 1, count: 49)
        values[0] = 0.01
        values[24] = 0.6
        let grid = try DepthGrid(width: 7, height: 7, rowStride: 7, values: values,
                                 confidenceRowStride: 7, confidence: [UInt8](repeating: 2, count: 49))
        let summary = DepthAnalyzer.summarize(grid, centerRadius: 0)
        try expect(abs((summary.centerMeters ?? 0) - 0.6) < 0.00001 && summary.centerSampleCount == 1,
                   "Center patch included another point")
        let tiny = try DepthGrid(width: 1, height: 1, rowStride: 1, values: [0.5],
                                 confidenceRowStride: 1, confidence: [2])
        try expect(DepthAnalyzer.summarize(tiny).centerMeters == 0.5, "One-pixel center is incorrect")
    }),
    ("Malformed or truncated buffer layouts are rejected", {
        try expectThrow { _ = try DepthGrid(width: 2, height: 2, rowStride: 2, values: [1]) }
        try expectThrow { _ = try DepthGrid(width: 2, height: 1, rowStride: 1, values: [1, 1]) }
        try expectThrow { _ = try DepthGrid(width: 1, height: 1, rowStride: 1, values: [1],
                                            confidenceRowStride: 0, confidence: []) }
        try expectThrow { _ = try DepthGrid(width: 1, height: 0, rowStride: 1, values: []) }
    }),
    ("Fixed color scale distinguishes invalid, low confidence, near and far", {
        let invalid = DepthColorMap.rgba(depth: .nan, confidence: 2)
        let low = DepthColorMap.rgba(depth: 0.5, confidence: 0)
        let near = DepthColorMap.rgba(depth: 0.15, confidence: 2)
        let far = DepthColorMap.rgba(depth: 2, confidence: 2)
        try expect(invalid.0 == 0 && invalid.1 == 0 && invalid.2 == 0, "Invalid color is not black")
        try expect(low.0 == 48 && low.1 == 48 && low.2 == 48, "Unknown color is not gray")
        try expect(near.0 > near.2 && far.2 > far.0, "Near/far scale reversed")
    }),
    ("Stale, missing, invalid and future receipt times are rejected", {
        try expect(FrameFreshness.isFresh(lastReceipt: 10, now: 10.5), "Recent frame marked stale")
        try expect(!FrameFreshness.isFresh(lastReceipt: 10, now: 10.8), "Expired frame marked fresh")
        try expect(!FrameFreshness.isFresh(lastReceipt: nil, now: 10), "Missing frame marked fresh")
        try expect(!FrameFreshness.isFresh(lastReceipt: 11, now: 10), "Future timestamp accepted")
        try expect(!FrameFreshness.isFresh(lastReceipt: .nan, now: 10), "NaN timestamp accepted")
    })
]

func practiceTemplate() throws -> RoutineTemplate {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try JSONDecoder().decode(RoutineTemplate.self, from: Data(contentsOf: root.appendingPathComponent("ArmGuardCaptureProbe/Resources/RoutineTemplate.json")))
}
func readyForMonitoring() throws -> RoutineSession {
    var session = try RoutineSession(template: practiceTemplate())
    session.start()
    while let check = session.currentCheck, check.responseKind != .monitoring {
        _ = session.submit("I inspected the practice supplies")
        if check.responseKind == .readBack { _ = session.confirmReadBack() }
    }
    return session
}
checks += [
    ("Questions, uncertainty and rote yes do not advance a check", {
        var session = try RoutineSession(template: practiceTemplate())
        session.start()
        for response in ["yes", "yes yes done", "I have not checked", "I didn't check", "Why is this needed?", "How do I check the room"] {
            _ = session.submit(response)
            try expect(session.checkIndex == 0, "Unfinished action advanced: \(response)")
        }
        _ = session.submit("I removed direct airflow")
        try expect(session.checkIndex == 1, "Action report not recorded")
        try expect(session.events.last?.evidence == "self_report", "Report misrepresented as verified")
    }),
    ("Read-back needs a separate exact confirmation", {
        var session = try RoutineSession(template: practiceTemplate())
        session.start(); _ = session.submit("I prepared the room")
        try expect(!session.confirmReadBack(), "Empty read-back confirmed")
        _ = session.submit("Practice bag product strength volume expiry")
        try expect(session.checkIndex == 1 && session.pendingReadBack != nil, "Read-back advanced without confirmation")
        try expect(session.confirmReadBack() && session.checkIndex == 2, "Explicit confirmation did not advance")
        try expect(VoiceIntent.parse("I cannot confirm this") == .answer("I cannot confirm this"), "Substring auto-confirmed")
        try expect(VoiceIntent.parse("I have a question") == .askQuestion, "Hands-free Q&A entry unavailable")
        try expect(VoiceIntent.parse("do not stop") == .answer("do not stop"), "Substring triggered stop")
    }),
    ("Missing model blocks arming; lost observation needs explicit rearm", {
        var session = try readyForMonitoring()
        try expect(!session.armMonitoring(visionReady: false), "Unavailable vision armed")
        try expect(session.armMonitoring(visionReady: true), "Ready practice did not arm")
        session.observationLost()
        try expect(session.phase == .paused, "Missing observation did not pause")
        session.resume()
        try expect(session.phase == .checking, "Resume automatically restored monitoring")
        try expect(!session.finishMonitoring(), "Unarmed monitoring completed")
    }),
    ("Possible overlap remains latched across pause and resume", {
        var session = try readyForMonitoring()
        _ = session.armMonitoring(visionReady: true)
        session.flagPossibleContact(); session.pause(); session.resume()
        try expect(session.reviewRequired && session.phase == .reviewRequired, "Review latch cleared")
        try expect(!session.finishMonitoring() && !session.armMonitoring(visionReady: true), "Review bypassed")
        session.finishPreparationOnly()
        try expect(session.phase == .reviewRequired, "Preparation exit cleared review")
    }),
    ("Preparation-only exit never records exchange completion", {
        var session = try readyForMonitoring()
        session.finishPreparationOnly()
        try expect(session.phase == .preparationOnly, "Wrong terminal phase")
        try expect(!session.events.contains { $0.kind == "practice_finished" }, "Unmonitored exchange marked finished")
        let encoded = String(data: try JSONEncoder().encode(session.events), encoding: .utf8) ?? ""
        try expect(!encoded.contains("I inspected the practice supplies"), "Read-back text persisted")
    }),
    ("Connection and disconnection are distinct monitored practice windows", {
        var session = try readyForMonitoring()
        var windows = 0
        while session.phase != .completed {
            guard let check = session.currentCheck else { throw CheckFailure(description: "Missing next step") }
            if check.responseKind == .monitoring {
                try expect(session.armMonitoring(visionReady: true), "Could not arm next window")
                try expect(session.finishMonitoring(), "Could not finish practice window")
                windows += 1
            } else {
                _ = session.submit("I reviewed the practice steps")
                if check.responseKind == .readBack { _ = session.confirmReadBack() }
            }
        }
        try expect(windows == 2, "Connection/disconnection windows merged or skipped")
        try expect(session.events.last?.evidence == "not_a_clean_exchange_claim", "Completion implies verified cleanliness")
    }),
    ("Projected overlap is not a manufactured zero-depth gap", {
        let region = ProtectedRegion(x: 0.2, y: 0.2, width: 0.2, height: 0.2)
        let result = ProximityEngine.evaluate(fingertips: [SensorPoint(x: 0.3, y: 0.3)], regions: [region]) { _ in
            throwAwayDepthCall = true
            return CameraPoint(x: 0, y: 0, z: 1)
        }
        try expect(result == .projectedOverlap && !throwAwayDepthCall, "Overlap sampled the same pixel twice")
    }),
    ("Unknown pairs cannot clear a hazard; known close pairs still warn", {
        let region = ProtectedRegion(x: 0.7, y: 0.7, width: 0.1, height: 0.1)
        let tip = SensorPoint(x: 0.1, y: 0.1)
        let unknown = ProximityEngine.evaluate(fingertips: [tip], regions: [region]) { _ in nil }
        if case .unavailable = unknown {} else { throw CheckFailure(description: "Missing depth became clear") }
        let near = ProximityEngine.evaluate(fingertips: [tip, SensorPoint(x: 0.05, y: 0.05)], regions: [region]) { p in
            if p.x == 0.05 { return nil }
            return CameraPoint(x: p.x * 0.02, y: p.y * 0.02, z: 0.5)
        }
        if case .warning(let intensity, let meters) = near {
            try expect(intensity > 80 && meters < 0.05, "Incorrect warning strength")
        } else { throw CheckFailure(description: "Known proximity hidden by another unknown pair") }
    }),
    ("Mixed foreground/background depth patches are rejected", {
        let values: [Float] = [0.5, 0.5, 0.5, 0.5, 0.6, 0.5, 0.5, 0.5, 0.5]
        let grid = try DepthGrid(width: 3, height: 3, rowStride: 3, values: values,
                                 confidenceRowStride: 3, confidence: Array(repeating: 2, count: 9))
        let point = DepthProjection.cameraPoint(SensorPoint(x: 0.5, y: 0.5), grid: grid,
                                               imageWidth: 100, imageHeight: 100, fx: 50, fy: 50, cx: 50, cy: 50)
        try expect(point == nil, "Mixed depth boundary presented as precise")
    }),
    ("BLE modes preserve legacy commands and v2 intensity bytes", {
        try expect(BandEncoding.payload(intensity: 123, suspected: false, mode: .legacy) == [87], "Legacy warning changed")
        try expect(BandEncoding.payload(intensity: 123, suspected: false, mode: .intensityV2) == [1, 123], "Intensity lost")
        try expect(BandEncoding.payload(intensity: 255, suspected: true, mode: .intensityV2) == [2, 255], "Review cue lost")
        try expect(BandEncoding.payload(intensity: 0, suspected: false, mode: .intensityV2) == [0, 0], "Off packet invalid")
    })
]
var throwAwayDepthCall = false

var failures = 0
for (name, check) in checks {
    do {
        try check()
        print("PASS: \(name)")
    } catch {
        failures += 1
        print("FAIL: \(name): \(error)")
    }
}
print("\(checks.count - failures)/\(checks.count) checks passed")
if failures > 0 { exit(1) }
