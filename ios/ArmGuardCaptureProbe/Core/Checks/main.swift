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
    // Synthetic geometry/risk tests explicitly opt into experimental mode.
    var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(practiceTemplate())) as! [String: Any]
    object["detectorStatus"] = "experimental"
    let template = try JSONDecoder().decode(RoutineTemplate.self, from: JSONSerialization.data(withJSONObject: object))
    var session = try RoutineSession(template: template)
    session.start()
    while let check = session.currentCheck, check.responseKind != .monitoring {
        let previous = session.checkIndex
        _ = session.submit("I inspected the practice supplies")
        if check.responseKind == .readBack { _ = session.confirmReadBack() }
        try expect(session.checkIndex > previous, "Preparation stalled at \(check.id)")
    }
    return session
}
checks += [
    ("Low-accuracy detector permits rehearsal without arming or blocking on detections", {
        var session = try RoutineSession(template: practiceTemplate())
        let check = session.template.checks.first { $0.responseKind == .monitoring }!
        try expect(session.debugJump(to: check.id), "Could not reach rehearsal")
        try expect(session.expectedResponse == "unmonitored_ready" && !session.armMonitoring(visionReady: true), "Placeholder armed real monitoring")
        try expect(session.beginUnmonitoredPractice() && session.phase == .unmonitoredPractice, "Rehearsal required detections")
        try expect(ProximityFeedback.level(phase: session.phase, fresh: true, decision: .warning(255, meters: 0.001)) == .none, "Rehearsal emitted a proximity warning")
        session.pause(); session.resume()
        try expect(session.phase == .unmonitoredPractice, "Resume lost rehearsal mode")
        try expect(session.assistantAdvance(checkID: check.id) && session.currentCheck?.id != check.id, "Assistant could not finish rehearsal")
        try expect(session.events.contains { $0.kind == "unmonitored_practice_finished" && $0.evidence == "not_monitored" }, "Rehearsal claimed monitoring")
    }),
    ("Unmonitored practice cannot clear a genuine contact review", {
        var session = try readyForMonitoring()
        _ = session.armMonitoring(visionReady: true); session.flagPossibleContact()
        try expect(!session.beginUnmonitoredPractice() && !session.finishUnmonitoredPractice() && session.reviewRequired, "Rehearsal bypassed contact review")
    }),
    ("Bag details accumulate across short replies and pause without restarting", {
        var session = try RoutineSession(template: practiceTemplate())
        session.start(); _ = session.submit("done")
        for fragment in ["PracticeBrand", "one point five percent", "two litres", "2027"] { _ = session.submit(fragment) }
        try expect(session.readBackParts.count == 4 && session.pendingReadBack?.contains("PracticeBrand") == true && session.pendingReadBack?.contains("2027") == true, "Short final detail replaced or lost prior details")
        _ = session.submit("2027")
        try expect(session.readBackParts.count == 4, "Repeated detail duplicated")
        session.pause(); session.resume()
        try expect(session.readBackParts.count == 4 && session.responsePrompt.contains("two litres"), "Pause lost draft")
        _ = session.submit("yes it matches")
        try expect(session.currentCheck?.id == "mask" && session.readBackParts.isEmpty, "Confirmed draft did not advance/clear")
    }),
    ("Bag corrections retain history until explicit restart", {
        var session = try RoutineSession(template: practiceTemplate())
        session.start(); _ = session.submit("done")
        _ = session.submit("PracticeBrand two litres")
        _ = session.submit("Expiry 2027")
        _ = session.submit("Actually expiry 2028")
        try expect(session.readBackParts.count == 3 && session.pendingReadBack?.contains("Actually expiry 2028") == true, "Correction lost original context")
        _ = session.submit("no")
        try expect(session.pendingReadBack == nil && session.readBackParts.count == 3, "Rejected summary erased context")
        _ = session.submit("yes")
        try expect(session.currentCheck?.id == "supplies", "Rejected summary confirmed without correction")
        _ = session.submit("Corrected strength one point five percent")
        try expect(session.readBackParts.count == 4, "Correction restarted bag")
        _ = session.submit("start the bag over")
        try expect(session.readBackParts.isEmpty && session.pendingReadBack == nil, "Explicit restart ignored")
    }),
    ("Assistant can advance ordinary practice checks but not camera, pause or review gates", {
        var session = try RoutineSession(template: practiceTemplate())
        session.start(); _ = session.submit("done"); _ = session.submit("PracticeBrand")
        try expect(!session.assistantAdvance(checkID: "room"), "Stale override advanced")
        try expect(session.assistantAdvance(checkID: "supplies") && session.currentCheck?.id == "mask", "Conversational override unavailable")
        try expect(session.events.last?.kind == "assistant_step_advanced" && session.events.last?.evidence == "assistant_judgment_unverified", "Assistant advance claimed verification")
        try expect(!session.assistantAdvance(checkID: "supplies"), "Old step override advanced twice")
        session.pause()
        try expect(!session.assistantAdvance(checkID: "mask"), "Pause bypassed")
        var monitored = try readyForMonitoring()
        let id = monitored.currentCheck!.id
        try expect(!monitored.assistantAdvance(checkID: id), "Unarmed camera check bypassed")
        _ = monitored.armMonitoring(visionReady: true); monitored.flagPossibleContact()
        try expect(!monitored.assistantAdvance(checkID: id) && monitored.reviewRequired, "Contact review bypassed")
    }),
    ("Read-back fragments stay out of event logs and clear on debug navigation", {
        var session = try RoutineSession(template: practiceTemplate())
        session.start(); _ = session.submit("done"); _ = session.submit("PrivatePracticeBrand"); _ = session.submit("2027")
        let log = String(decoding: try JSONEncoder().encode(session.events), as: UTF8.self)
        try expect(!log.contains("PrivatePracticeBrand") && !log.contains("2027"), "Read-back text persisted")
        try expect(session.debugJump(to: "mask") && session.readBackParts.isEmpty && session.pendingReadBack == nil, "Debug jump kept old draft")
    }),
    ("Editable JSON voice lines drive read-back prompts and follow-ups", {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(practiceTemplate())) as! [String: Any]
        object["voice"] = ["bag_confirmation": "Edited confirmation: say yes or no.",
                           "read_back": "Edited read-back: {details}. {instruction}",
                           "confirmation_retry": "Edited retry. {instruction}"]
        let template = try JSONDecoder().decode(RoutineTemplate.self, from: JSONSerialization.data(withJSONObject: object))
        var session = try RoutineSession(template: template)
        session.start(); _ = session.submit("done")
        _ = session.submit("Practice bag strength volume expiry")
        try expect(session.responsePrompt.contains("Edited read-back:") && session.responsePrompt.contains("Edited confirmation:"), "JSON edits ignored")
        let reply = session.submit("hmm")
        try expect(reply.contains("Edited retry.") && session.checkIndex == 1, "Edited retry bypassed gate or ignored wording")
    }),
    ("Prompts announce the answer format and preserve confirmation after resume", {
        var session = try RoutineSession(template: practiceTemplate())
        session.start()
        try expect(session.responsePrompt.contains("'done'") && session.expectedResponse == "action_report", "Action format hidden")
        _ = session.submit("done")
        try expect(session.responsePrompt.contains("a little at a time") && session.expectedResponse == "read_back_details", "Partial answers not announced upfront")
        _ = session.submit("Practice bag strength volume expiry")
        let confirmation = session.responsePrompt
        try expect(session.expectedResponse == "read_back_confirmation" && confirmation.contains("You said:"), "Pending details not reflected in prompt")
        session.pause(); session.resume()
        try expect(session.responsePrompt == confirmation && session.expectedResponse == "read_back_confirmation", "Resume returned to initial bag prompt")
    }),
    ("Natural read-back confirmations advance once without replacing bag details", {
        for words in ["yes", "they match", "yes, it matches", "yes, that's correct", "I checked and everything matches"] {
            var session = try RoutineSession(template: practiceTemplate())
            session.start(); _ = session.submit("done")
            _ = session.submit("Practice bag strength volume expiry")
            _ = session.submit(words)
            try expect(session.currentCheck?.id == "mask" && session.pendingReadBack == nil, "Confirmation loop: \(words)")
        }
        var empty = try RoutineSession(template: practiceTemplate())
        empty.start(); _ = empty.submit("done"); _ = empty.submit("yes it matches")
        try expect(empty.currentCheck?.id == "supplies" && empty.pendingReadBack == nil, "Confirmation invented missing details")
    }),
    ("Unrecognized and negative confirmations cannot overwrite or pass a read-back", {
        var session = try RoutineSession(template: practiceTemplate())
        session.start(); _ = session.submit("done")
        let details = "Practice bag strength volume expiry"
        _ = session.submit(details)
        for words in ["hmm", "yes but they do not match", "I am unsure", "Why is this needed?"] {
            _ = session.submit(words)
            try expect(session.currentCheck?.id == "supplies" && session.pendingReadBack == details, "Unclear reply overwrote details or passed")
        }
        _ = session.submit("no they don't match")
        try expect(session.pendingReadBack == nil && session.expectedResponse == "read_back_details", "Mismatch retained confirmable details")
        _ = session.submit("yes")
        try expect(session.currentCheck?.id == "supplies" && session.pendingReadBack == nil, "Yes passed after rejected read-back")
    }),
    ("Not-expired descriptions are self-reports while other uncertainty still holds", {
        var session = try RoutineSession(template: practiceTemplate())
        session.start(); _ = session.submit("done")
        for words in ["I have not checked the bag", "I'm unsure it is not expired", "This is the wrong bag and it is not expired"] {
            _ = session.submit(words)
            try expect(session.pendingReadBack == nil && session.currentCheck?.id == "supplies", "Uncertainty became bag details: \(words)")
        }
        let words = "Practice bag strength volume expiry and it is not expired"
        _ = session.submit(words)
        try expect(session.pendingReadBack == words && session.checkIndex == 1, "Valid negative description rejected or automatically confirmed")
        _ = session.submit("yes it matches")
        try expect(session.currentCheck?.id == "mask", "Explicit confirmation did not complete self-report")
    }),
    ("Debug jumps discard read-backs and never complete or arm a check", {
        var session = try RoutineSession(template: practiceTemplate())
        session.start(); _ = session.submit("done")
        _ = session.submit("Practice bag product strength volume expiry")
        try expect(session.pendingReadBack != nil, "Missing read-back fixture")
        let monitor = session.template.checks.first { $0.responseKind == .monitoring }!
        let previousRecords = session.events.filter { $0.kind == "check_recorded" }.count
        try expect(session.debugJump(to: monitor.id), "Debug jump rejected")
        try expect(session.phase == .checking && session.pendingReadBack == nil && session.debugNavigationUsed,
                   "Jump retained evidence or armed monitoring")
        try expect(!session.armMonitoring(visionReady: false), "Debug bypassed camera readiness")
        try expect(session.events.filter { $0.kind == "check_recorded" }.count == previousRecords,
                   "Jump recorded a completed check")
        let previousIndex = session.checkIndex
        try expect(!session.debugJump(to: "unknown") && session.checkIndex == previousIndex, "Unknown jump mutated state")
        try expect(session.events.last?.kind == "debug_step_jump", "Debug navigation not logged separately")
    }),
    ("Debug skips and completion stay unverified and cannot bypass contact review", {
        var session = try readyForMonitoring()
        _ = session.armMonitoring(visionReady: true)
        try expect(session.debugSkipCurrentCheck() && session.phase == .checking, "Monitoring skip stayed armed")
        let last = session.template.checks.last!
        try expect(session.debugJump(to: last.id) && session.debugSkipCurrentCheck(), "Final debug skip failed")
        try expect(session.phase == .completed && session.events.last?.kind == "debug_finished", "Debug finish represented as normal completion")
        var flagged = try readyForMonitoring()
        _ = flagged.armMonitoring(visionReady: true); flagged.flagPossibleContact(); flagged.pause()
        try expect(!flagged.debugSkipCurrentCheck() && !flagged.debugJump(to: last.id) && flagged.reviewRequired,
                   "Debug navigation cleared review")
        var idle = try RoutineSession(template: practiceTemplate())
        try expect(!idle.debugSkipCurrentCheck(), "Idle routine skipped before starting")
    }),
    ("Natural pause and debug skip commands require explicit phrases", {
        for words in ["please pause", "Can you pause?", "let's pause", "pause the routine"] {
            try expect(VoiceIntent.parse(words) == .pause, "Pause phrase missed: \(words)")
        }
        for words in ["skip this step", "next step", "skip ahead"] {
            try expect(VoiceIntent.parse(words) == .skipStep, "Debug command missed: \(words)")
        }
        for words in ["don't pause", "don't skip this step", "why would I skip this step?"] {
            try expect(VoiceIntent.parse(words) == .answer(words), "Substring triggered command: \(words)")
        }
    }),
    ("Questions and uncertainty hold the step; natural completion is self-report", {
        var session = try RoutineSession(template: practiceTemplate())
        session.start()
        for response in ["hello", "I have not checked", "I didn't check", "It isn't prepared", "I will put on my mask", "I need to get cleaned up", "Why is this needed?", "How do I check the room"] {
            _ = session.submit(response)
            try expect(session.checkIndex == 0, "Unfinished action advanced: \(response)")
        }
        _ = session.submit("I removed direct airflow")
        try expect(session.checkIndex == 1, "Action report not recorded")
        try expect(session.events.last?.evidence == "self_report", "Report misrepresented as verified")
        _ = session.submit("yes")
        try expect(session.checkIndex == 1 && session.pendingReadBack == nil, "A bare yes supplied missing bag details")
    }),
    ("Spoken read-back confirmation and one-turn cloud guard", {
        var session = try RoutineSession(template: practiceTemplate())
        session.start(); _ = session.submit("done")
        _ = session.submit("Practice bag product strength volume expiry")
        _ = session.submit("Why do I check this?")
        try expect(session.checkIndex == 1 && session.pendingReadBack != nil, "Question altered read-back")
        _ = session.submit("they match")
        try expect(session.checkIndex == 2, "Spoken confirmation did not advance")
        var gate = SpokenReplyGate()
        gate.receive("I've put on my mask", turn: 1)
        try expect(gate.consume("done", expectedCheckID: "mask", currentCheckID: "mask") == nil, "Invented consent accepted")
        try expect(gate.consume("I've put on my mask", expectedCheckID: "hands", currentCheckID: "mask") == nil, "Stale step accepted")
        try expect(gate.consume("I've put on my mask", expectedCheckID: "mask", currentCheckID: "mask") != nil, "Actual words rejected")
        try expect(gate.consume("I've put on my mask", expectedCheckID: "hands", currentCheckID: "hands") == nil, "Same user turn advanced twice")
        gate.receive("done", turn: 0)
        try expect(gate.consume("done", expectedCheckID: "hands", currentCheckID: "hands") == nil, "Replayed turn accepted")
    }),
    ("Skipping camera is explicit unobserved practice and cannot clear review", {
        var session = try readyForMonitoring()
        try expect(session.continueWithoutCamera(), "Practice skip unavailable")
        try expect(session.events.contains(where: { $0.kind == "camera_step_skipped" && $0.evidence == "explicit_unobserved_practice" }), "Skip represented as monitored")
        var flagged = try readyForMonitoring()
        _ = flagged.armMonitoring(visionReady: true); flagged.flagPossibleContact()
        try expect(!flagged.continueWithoutCamera() && flagged.reviewRequired, "Skip cleared review")
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
            let previous = session.checkIndex
            guard let check = session.currentCheck else { throw CheckFailure(description: "Missing next step") }
            if check.responseKind == .monitoring {
                try expect(session.armMonitoring(visionReady: true), "Could not arm next window")
                try expect(session.finishMonitoring(), "Could not finish practice window")
                windows += 1
            } else {
                _ = session.submit("I reviewed the practice steps")
                if check.responseKind == .readBack { _ = session.confirmReadBack() }
            }
            try expect(session.checkIndex > previous, "Practice stalled at \(check.id)")
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

checks += [
    ("RF-DETR raw logits in zero-to-one range still require sigmoid", {
        let found = try RFDETRDecoding.decode(boxes: [0.5, 0.5, 0.2, 0.4],
            logits: [0.9, 0.1, 0.2], queries: 1, classCount: 3,
            classes: [0: "_roboflow_placeholder", 1: "Hand", 2: "Sterile_connector_tip"], backgroundClassID: 0)
        try expect(found.count == 1 && found[0].label == "Sterile_connector_tip", "Background or class ID decoded incorrectly")
        try expect(abs(found[0].confidence - 0.549834) < 0.00001, "Positive logits treated as probabilities")
        try expect(abs(found[0].box.x - 0.4) < 0.00001 && abs(found[0].box.height - 0.4) < 0.00001, "Box coordinates decoded incorrectly")
    }),
    ("RF-DETR rejects malformed outputs and never rescales arbitrary boxes", {
        try expectThrow { _ = try RFDETRDecoding.decode(boxes: [0.5, 0.5, 0.2, 0.2], logits: [0.2], queries: 1, classCount: 3, classes: [1: "Hand"], backgroundClassID: 0) }
        let outside = try RFDETRDecoding.decode(boxes: [300, 300, 50, 50], logits: [0.2], queries: 1, classCount: 1, classes: [0: "Hand"], backgroundClassID: nil)
        try expect(outside.isEmpty, "Box units silently inferred/rescaled")
        let crossing = try RFDETRDecoding.decode(boxes: [-0.1, 0.5, 0.4, 0.4], logits: [2], queries: 1, classCount: 1, classes: [0: "Hand"], backgroundClassID: nil)
        try expect(crossing.count == 1 && crossing[0].box.x == 0 && abs(crossing[0].box.width - 0.1) < 0.00001, "Valid off-frame box not clipped")
        try expectThrow { _ = try RFDETRDecoding.decode(boxes: [.nan, 0.5, 0.2, 0.2], logits: [0.2], queries: 1, classCount: 1, classes: [0: "Hand"], backgroundClassID: nil) }
        let unknown = try RFDETRDecoding.decode(boxes: [0.5, 0.5, 0.2, 0.2], logits: [5, -5], queries: 1, classCount: 2, classes: [1: "Hand"], backgroundClassID: nil)
        try expect(unknown.isEmpty, "Unknown class invented a known label")
    }),
    ("Class roles do not turn arbitrary catheter bodies into protected openings", {
        try expect(DetectionLabels.role(for: "Sterile_connector_tip") == .protectedOpening, "Bundled protected class ignored")
        try expect(DetectionLabels.role(for: "Hand") == .hand, "Whole hand became a fingertip")
        for name in ["catheter", "non_sterile_connector", "tip", "finger", "fingertip_sleeve"] {
            try expect(DetectionLabels.role(for: name) == .ignored, "Loose substring classified \(name)")
        }
    }),
    ("Paused and stale observations cannot drive new alerts", {
        let close = ProximityDecision.warning(240, meters: 0.005)
        for phase: RoutinePhase in [.idle, .checking, .paused, .reviewRequired, .preparationOnly, .completed] {
            try expect(ProximityFeedback.level(phase: phase, fresh: true, decision: close) == .none, "Alert outside monitoring")
        }
        try expect(ProximityFeedback.level(phase: .monitoring, fresh: false, decision: close) == .none, "Stale alert accepted")
        try expect(ProximityFeedback.level(phase: .monitoring, fresh: true, decision: close) == .high, "Current armed warning lost")
    }),
    ("Image scale has no assumed millimetres and clears when the reference is lost", {
        var tracker = ScaleRiskTracker()
        let measurement = ScaleProximity.measure(fingertips: [SensorPoint(x: 0.1, y: 0.5)], hands: [],
            regions: [ProtectedRegion(x: 0.2, y: 0.4, width: 0.1, height: 0.2)], imageWidth: 1000, imageHeight: 500)
        try expect(measurement != nil, "Image geometry failed")
        try expect(tracker.update(measurement) == .none && tracker.mmPerPixel == nil, "Assumed physical prop size")
        tracker.sterileTipSizeMM = 10
        _ = tracker.update(measurement)
        try expect(tracker.mmPerPixel != nil, "Explicit calibration unavailable")
        _ = tracker.update(nil)
        try expect(tracker.mmPerPixel == nil && tracker.distanceMM == nil, "Lost reference reused stale scale")
    }),
    ("Calibrated distance gives MEDIUM/HIGH warnings with hysteresis", {
        // Tip box 20 px wide in a 1000 px image; 10 mm tip -> 0.5 mm per pixel.
        let tip = ProtectedRegion(x: 0.4, y: 0.4, width: 0.02, height: 0.01)
        func at(_ mm: Double) -> ScaleProximityMeasurement? {
            ScaleProximity.measure(fingertips: [SensorPoint(x: 0.42 + mm / 0.5 / 1000, y: 0.405)], hands: [],
                                   regions: [tip], imageWidth: 1000, imageHeight: 1000)
        }
        var tracker = ScaleRiskTracker()
        tracker.sterileTipSizeMM = 10
        tracker.distanceSmoothAlpha = 1   // no smoothing, so each step is exact
        try expect(tracker.update(at(100)) == .none, "Far hand warned")
        try expect(tracker.update(at(60)) == .medium, "MEDIUM band missed")
        try expect(tracker.update(at(20)) == .high, "HIGH band missed")
        try expect(tracker.update(at(33)) == .high, "HIGH released inside hysteresis margin")
        try expect(tracker.update(at(40)) == .medium, "HIGH not released past margin")
        try expect(tracker.update(at(83)) == .medium, "MEDIUM released inside hysteresis margin")
        try expect(tracker.update(at(90)) == .none, "MEDIUM not released past margin")
        try expect(tracker.update(at(0)) == .high && tracker.distanceMM == 0, "Fingertip on the tip not HIGH at 0 mm")
        try expect(tracker.update(nil) == .none && tracker.current == .none, "Lost reference kept the warning")
    }),
    ("Direct phone requests carry credentials only in HTTPS headers", {
        let template = try practiceTemplate()
        let request = try CartesiaRequests.agentSession(apiKey: "test-key", voiceID: "test-voice", agentID: "agent_test",
            instructions: "Trusted practice guidance. ", initialPrompt: template.checks[0].prompt,
            checks: template.checks, checkID: "room", phase: .checking)
        try expect(request.url?.host == "api.cartesia.ai" && request.url?.scheme == "https", "Direct request uses a local server")
        try expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key", "Missing authenticated header")
        try expect(request.url?.query == nil, "Secret passed in URL")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        let config = body["config_overrides"] as! [String: Any]
        try expect((config["instructions"] as? String)?.contains("starting_check_id") == true, "Native state context missing")
        try expect(!String(decoding: request.httpBody!, as: UTF8.self).contains("test-key"), "Provider key leaked into instructions")
        try expectThrow { _ = try CartesiaRequests.agentSession(apiKey: "key", voiceID: "voice", agentID: "../outside", instructions: "rules", initialPrompt: "hello", checks: template.checks, checkID: "room", phase: .checking) }
    }),
    ("Phone WAV finalizer bounds streaming lengths and preserves audio samples", {
        var wav = Data("RIFF".utf8)
        func little(_ value: UInt32, bytes: Int = 4) -> Data { Data((0..<bytes).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }) }
        wav.append(little(.max)); wav.append(Data("WAVEfmt ".utf8)); wav.append(little(16))
        wav.append(little(1, bytes: 2)); wav.append(little(1, bytes: 2)); wav.append(little(44100)); wav.append(little(88200))
        wav.append(little(2, bytes: 2)); wav.append(little(16, bytes: 2)); wav.append(Data("data".utf8)); wav.append(little(.max))
        wav.append(Data([0, 0, 1, 0, 255, 127, 0, 128]))
        let finalized = try WaveClip.finalized(wav)
        try expect(Array(finalized[4..<8]) == Array(little(44)), "RIFF size not finalized")
        try expect(Array(finalized[40..<44]) == Array(little(8)), "Audio length remains open-ended")
        try expect(finalized.suffix(8) == wav.suffix(8), "Samples changed")
        try expectThrow { _ = try WaveClip.finalized(Data("invalid".utf8)) }
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
