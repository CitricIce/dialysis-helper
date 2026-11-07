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

let checks: [(String, () throws -> Void)] = [
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
