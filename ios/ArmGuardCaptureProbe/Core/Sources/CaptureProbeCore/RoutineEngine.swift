import Foundation

public enum DetectorStatus: String, Codable { case placeholder, experimental }

public struct RoutineCheck: Codable, Identifiable, Equatable {
    public enum ResponseKind: String, Codable { case actionReport, readBack, monitoring }
    public let id: String
    public let title: String
    public let prompt: String
    public let help: String
    public let responseKind: ResponseKind
    public let exampleResponses: [String]?
}

public struct RoutineTemplate: Codable, Equatable {
    public let schemaVersion: Int
    public let id: String
    public let title: String
    public let practiceOnly: Bool
    public let protocolNote: String
    public let slots: [String]
    public let checks: [RoutineCheck]
    public let voice: [String: String]?
    public let detectorStatus: DetectorStatus?

    public func validate() throws {
        guard schemaVersion == 1, practiceOnly, !slots.isEmpty, !checks.isEmpty,
              Set(checks.map(\.id)).count == checks.count,
              checks.allSatisfy({ !$0.id.isEmpty && !$0.prompt.isEmpty }),
              checks.contains(where: { $0.responseKind == .monitoring }) else { throw RoutineError.invalidTemplate }
    }
    public enum RoutineError: Error { case invalidTemplate }
}

public enum RoutinePhase: String, Codable {
    case idle, checking, paused, monitoring, unmonitoredPractice, reviewRequired, preparationOnly, completed
}

public struct RoutineEvent: Codable {
    public let kind: String
    public let checkID: String?
    public let timestamp: Date
    public let evidence: String
}

public struct RoutineSession {
    public let template: RoutineTemplate
    public private(set) var phase: RoutinePhase = .idle
    public private(set) var checkIndex = 0
    public private(set) var pendingReadBack: String?
    public private(set) var readBackParts: [String] = []
    public private(set) var events: [RoutineEvent] = []
    public private(set) var reviewRequired = false
    public private(set) var debugNavigationUsed = false
    private var pausedPhase: RoutinePhase = .checking

    public init(template: RoutineTemplate) throws {
        try template.validate()
        self.template = template
    }

    public var currentCheck: RoutineCheck? {
        guard template.checks.indices.contains(checkIndex) else { return nil }
        return template.checks[checkIndex]
    }

    public var expectedResponse: String {
        if reviewRequired { return "contact_review" }
        if phase == .paused { return "resume_or_question" }
        if phase == .monitoring { return "finished_or_pause" }
        if phase == .unmonitoredPractice { return "unmonitored_active" }
        guard phase == .checking, let check = currentCheck else { return "none" }
        switch check.responseKind {
        case .actionReport: return "action_report"
        case .readBack: return pendingReadBack == nil ? "read_back_details" : "read_back_confirmation"
        case .monitoring: return template.detectorStatus == .experimental ? "ready_to_monitor" : "unmonitored_ready"
        }
    }

    /// Shared by spoken prompts and tool state so the agent sees the same answer format.
    public var responseInstruction: String {
        let key: String
        if expectedResponse == "read_back_details" {
            key = currentCheck?.id == "supplies" ? "bag_details" : "openings_details"
        } else if expectedResponse == "read_back_confirmation" {
            key = currentCheck?.id == "supplies" ? "bag_confirmation" : "openings_confirmation"
        } else { key = expectedResponse }
        return voiceLine(key, fallback: defaultResponseInstruction)
    }

    private var defaultResponseInstruction: String {
        switch expectedResponse {
        case "action_report": return "Say 'done' when you've finished, or ask a question."
        case "read_back_details":
            return currentCheck?.id == "supplies"
                ? "Read the bag's name, strength, amount and expiry date. You can give them together or a little at a time. I'll keep the details, read them back, then ask you to say 'yes' or 'no'."
                : "Name the openings in a short sentence. I'll read your answer back, then ask you to say 'ready' or 'no'."
        case "read_back_confirmation":
            return currentCheck?.id == "supplies"
                ? "Compare those details with your written instructions. Say 'yes' if they match, or 'no' to stay here and check them again."
                : "Say 'ready' to continue, or 'no' to go over the openings again."
        case "ready_to_monitor": return "Say 'ready' when both hands and the opening are in view, or say 'pause'."
        case "unmonitored_ready": return "Camera distance cues are experimental. Say 'ready' to practise this step, then 'done' when you've finished."
        case "unmonitored_active": return "Say 'done' when you've finished, or 'pause'."
        case "finished_or_pause": return "Say 'done' when you've finished, or say 'pause'."
        case "resume_or_question": return "Say 'resume' when you're ready, or ask a question."
        case "contact_review": return "Pause and follow your care team's instructions about possible contact."
        default: return "Ask a question if there's anything you'd like to go over."
        }
    }

    public var responsePrompt: String {
        if expectedResponse == "unmonitored_ready" || expectedResponse == "unmonitored_active" { return responseInstruction }
        if phase == .checking, let pendingReadBack {
            return voiceLine("read_back", fallback: "You said: {details}. {instruction}")
                .replacingOccurrences(of: "{instruction}", with: responseInstruction)
                .replacingOccurrences(of: "{details}", with: pendingReadBack)
        }
        if phase == .checking, currentCheck?.id == "supplies", !readBackParts.isEmpty {
            return voiceLine("bag_correction", fallback: "I've kept the earlier details. Tell me what needs correcting; you don't need to start over.")
        }
        return currentCheck?.prompt ?? "We're finished. Is there anything else you'd like to ask?"
    }

    private func voiceLine(_ key: String, fallback: String) -> String {
        guard let text = template.voice?[key], !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fallback }
        return text
    }

    private func instructionReply(_ key: String, fallback: String) -> String {
        voiceLine(key, fallback: fallback).replacingOccurrences(of: "{instruction}", with: responseInstruction)
    }

    public mutating func start() {
        guard phase == .idle else { return }
        phase = .checking
        record("started", evidence: "practice")
    }

    /// Responses are recorded as self-reports, never as verified clinical observations.
    public mutating func submit(_ text: String) -> String {
        guard phase == .checking, let check = currentCheck, check.responseKind != .monitoring else {
            return "Tell me when you’re ready to begin, or say pause."
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = VoiceIntent.normalize(cleaned)
        guard !normalized.isEmpty else { return "I didn't catch that. Could you say it again?" }
        if VoiceIntent.isQuestion(cleaned) { return check.help }
        let isBag = check.id == "supplies" && check.responseKind == .readBack
        if isBag, ["start over", "start the bag over", "start bag over", "clear bag details"].contains(normalized) {
            pendingReadBack = nil; readBackParts = []
            return responseInstruction
        }
        let uncertaintyText = isBag
            ? normalized.replacingOccurrences(of: "\\bnot expired\\b", with: "", options: .regularExpression)
            : normalized
        let uncertainty = ["not ", "unsure", "haven t", "didn t", "isn t", "aren t", "wasn t", "weren t", "don t", "can t", "cannot", "wrong bag", "need more time", "need to ", "going to ", "i will ", "i should "]
        let uncertain = uncertainty.contains(where: uncertaintyText.contains) || normalized == "no" || normalized == "not"
        if check.responseKind == .readBack, pendingReadBack != nil {
            if VoiceIntent.isReadBackConfirmation(cleaned) {
                _ = confirmReadBack()
                return responsePrompt
            }
            if VoiceIntent.isReadBackRejection(cleaned) {
                pendingReadBack = nil
                // Keep the bag history available for corrections. A bare yes
                // cannot confirm rejected details until a new detail is supplied.
                if isBag { return responsePrompt }
                readBackParts = []
                return instructionReply("read_back_rejected", fallback: "Let's stay on this step. {instruction}")
            }
            if isBag, !uncertain, !["hmm", "um", "uh", "maybe"].contains(normalized) {
                appendReadBack(cleaned)
                return responsePrompt
            }
            // Never replace the original details with an unclear reply.
            return instructionReply("confirmation_retry", fallback: "We're still confirming what I read back. {instruction}")
        }
        // A bag description may correctly include 'not expired'. It is still only
        // a self-report; other uncertainty/mismatch wording must continue to hold.
        guard !uncertain else {
            return instructionReply("uncertain_reply", fallback: "Take your time. {instruction}")
        }
        if check.responseKind == .readBack {
            guard (isBag || normalized.split(separator: " ").count >= 3), !VoiceIntent.isReadBackConfirmation(cleaned),
                  !["hmm", "um", "uh", "maybe"].contains(normalized) else {
                return responseInstruction
            }
            appendReadBack(cleaned)
            return responsePrompt
        }
        let reports = ["prepared", "checked", "removed", "turned off", "washed", "cleaned", "dried", "inspected", "reviewed", "put on", "mask is on", "it s on", "finished", "completed", "set up", "i read", "got the"]
        guard VoiceIntent.isAffirmative(cleaned) || reports.contains(where: normalized.contains) else {
            return responseInstruction
        }
        advance(evidence: "self_report")
        return responsePrompt
    }

    public mutating func confirmReadBack() -> Bool {
        guard phase == .checking, currentCheck?.responseKind == .readBack,
              pendingReadBack != nil else { return false }
        advance(evidence: "self_reported_read_back")
        return true
    }

    /// Conversational progression is separate from verified completion evidence.
    public mutating func assistantAdvance(checkID: String) -> Bool {
        if phase == .unmonitoredPractice, currentCheck?.id == checkID { return finishUnmonitoredPractice() }
        guard template.practiceOnly, phase == .checking, !reviewRequired,
              currentCheck?.id == checkID, currentCheck?.responseKind != .monitoring else { return false }
        record("assistant_step_advanced", evidence: "assistant_judgment_unverified")
        pendingReadBack = nil; readBackParts = []
        checkIndex += 1
        if checkIndex >= template.checks.count {
            phase = .completed
            record("assistant_practice_finished", evidence: "assistant_judgment_unverified")
        }
        return true
    }

    private mutating func appendReadBack(_ text: String) {
        if !readBackParts.contains(where: { VoiceIntent.normalize($0) == VoiceIntent.normalize(text) }) {
            readBackParts.append(text)
        }
        pendingReadBack = readBackParts.joined(separator: "; ")
    }

    public mutating func armMonitoring(visionReady: Bool) -> Bool {
        guard phase == .checking, currentCheck?.responseKind == .monitoring,
              template.detectorStatus == .experimental, visionReady, !reviewRequired else { return false }
        phase = .monitoring
        record("monitoring_armed", evidence: "experimental_detector")
        return true
    }

    public mutating func beginUnmonitoredPractice() -> Bool {
        guard template.practiceOnly, phase == .checking,
              currentCheck?.responseKind == .monitoring, !reviewRequired else { return false }
        phase = .unmonitoredPractice
        record("unmonitored_practice_started", evidence: "no_camera_protection")
        return true
    }

    public mutating func finishUnmonitoredPractice() -> Bool {
        guard template.practiceOnly, phase == .unmonitoredPractice, !reviewRequired else { return false }
        record("unmonitored_practice_finished", evidence: "not_monitored")
        phase = .checking
        advance(evidence: "not_monitored")
        return true
    }

    public mutating func finishPreparationOnly() {
        guard phase == .checking, currentCheck?.responseKind == .monitoring,
              !reviewRequired else { return }
        phase = .preparationOnly
        record("preparation_only", evidence: "connection_not_monitored")
    }

    /// Explicit practice-only continuation; no observation is represented as a pass.
    public mutating func continueWithoutCamera() -> Bool {
        guard template.practiceOnly, phase == .checking,
              currentCheck?.responseKind == .monitoring, !reviewRequired else { return false }
        record("camera_step_skipped", evidence: "explicit_unobserved_practice")
        advance(evidence: "not_monitored")
        return true
    }

    public mutating func finishMonitoring() -> Bool {
        guard phase == .monitoring, !reviewRequired else { return false }
        record("monitoring_finished", evidence: "not_a_clean_exchange_claim")
        phase = .checking
        advance(evidence: "self_reported_practice_step")
        return true
    }

    public mutating func flagPossibleContact() {
        guard phase == .monitoring else { return }
        reviewRequired = true
        phase = .reviewRequired
        record("suspected_overlap", evidence: "projected_geometry_not_confirmed_contact")
    }

    public mutating func observationLost() {
        guard phase == .monitoring else { return }
        pause()
        record("observation_lost", evidence: "protection_unavailable")
    }

    public mutating func pause() {
        guard phase == .checking || phase == .monitoring || phase == .unmonitoredPractice || phase == .reviewRequired else { return }
        pausedPhase = phase
        phase = .paused
        record("paused", evidence: "user_or_lifecycle")
    }

    public mutating func resume() {
        guard phase == .paused else { return }
        // A former monitoring session must be explicitly rearmed with fresh observations.
        phase = reviewRequired ? .reviewRequired : (pausedPhase == .monitoring ? .checking : pausedPhase)
    }

    /// Developer navigation never records a completed check or arms monitoring.
    public mutating func debugJump(to checkID: String) -> Bool {
        guard template.practiceOnly, !reviewRequired,
              let index = template.checks.firstIndex(where: { $0.id == checkID }) else { return false }
        checkIndex = index
        pendingReadBack = nil
        readBackParts = []
        phase = .checking
        debugNavigationUsed = true
        record("debug_step_jump", evidence: "unverified_debug_navigation")
        return true
    }

    public mutating func debugSkipCurrentCheck() -> Bool {
        guard template.practiceOnly, !reviewRequired, currentCheck != nil,
              phase == .checking || phase == .paused || phase == .monitoring else { return false }
        record("debug_step_skipped", evidence: "unverified_debug_navigation")
        debugNavigationUsed = true
        pendingReadBack = nil
        readBackParts = []
        checkIndex += 1
        phase = checkIndex < template.checks.count ? .checking : .completed
        if phase == .completed { record("debug_finished", evidence: "unverified_debug_navigation") }
        return true
    }

    private mutating func advance(evidence: String) {
        record("check_recorded", evidence: evidence)
        pendingReadBack = nil
        readBackParts = []
        checkIndex += 1
        if checkIndex >= template.checks.count {
            phase = .completed
            record("practice_finished", evidence: "not_a_clean_exchange_claim")
        }
    }

    private mutating func record(_ kind: String, evidence: String) {
        events.append(RoutineEvent(kind: kind, checkID: currentCheck?.id,
                                   timestamp: Date(), evidence: evidence))
    }
}

public enum VoiceIntent: Equatable {
    case pause, resume, endSession, repeatPrompt, help, askQuestion, confirm, arm, skipCamera, skipStep, readLabel, finishPreparation, finishMonitoring, answer(String)
    public static func normalize(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
    public static func isQuestion(_ text: String) -> Bool {
        let normalized = normalize(text)
        return text.contains("?") || ["why ", "how ", "what ", "when ", "where ", "should ", "can ", "could ", "do i ", "is it ", "is this "].contains(where: normalized.hasPrefix)
    }
    public static func isAffirmative(_ text: String) -> Bool {
        ["yes", "yeah", "yep", "yes they do", "yes it does", "that s right", "that matches", "they match", "correct", "i confirm", "confirm", "ready", "i m ready", "done", "all done", "finished", "okay", "ok", "yes done", "okay done", "all set", "i ve finished", "let s go"].contains(normalize(text))
    }
    public static func isReadBackConfirmation(_ text: String) -> Bool {
        isAffirmative(text) || ["yes it matches", "yes they match", "yes that matches", "yes that s right",
            "yes that s correct", "that s correct", "it matches", "everything matches",
            "i checked and everything matches", "the details match", "i m ready to continue"].contains(normalize(text))
    }
    public static func isReadBackRejection(_ text: String) -> Bool {
        ["no", "no it doesn t", "no they don t", "no it doesn t match", "no they don t match",
         "they don t match", "it doesn t match", "that s wrong", "that s not right", "that s not correct"].contains(normalize(text))
    }
    public static func parse(_ text: String) -> VoiceIntent {
        switch normalize(text) {
        case "pause", "stop", "pause routine", "stop routine", "wait", "hold on", "give me a minute",
             "please pause", "pause please", "can you pause", "can we pause", "let s pause", "pause the routine": return .pause
        case "resume", "continue", "let s continue", "i m back", "let s keep going": return .resume
        case "end session", "end the session", "stop listening", "goodbye": return .endSession
        case "repeat", "repeat that", "say that again", "what did you say": return .repeatPrompt
        case "help", "i need help", "not ready": return .help
        case "ask a question", "i have a question", "voice questions": return .askQuestion
        case "confirm", "i confirm": return .confirm
        case "start monitoring", "arm monitoring", "start watching", "let s connect", "ready to connect": return .arm
        case "continue without camera", "continue without the camera", "skip the camera step": return .skipCamera
        case "skip", "skip ahead", "skip step", "skip this step", "skip this", "next step", "go to the next step", "please skip this step": return .skipStep
        case "read the label", "read my bag", "scan the label": return .readLabel
        case "finish preparation practice", "finish setup": return .finishPreparation
        case "finish monitoring", "finish connection practice", "i m connected", "i ve connected it", "i m disconnected", "i ve disconnected it": return .finishMonitoring
        default: return .answer(text)
        }
    }
}

/// A cloud tool can submit only the latest actual user transcript, once, for the current step.
/// Generated assistant speech never enters this gate.
public struct SpokenReplyGate {
    private var turn = -1
    private var consumed = -1
    private var words = ""
    public init() {}
    public mutating func receive(_ text: String, turn: Int) {
        guard turn > self.turn else { return }
        self.turn = turn; words = text
    }
    public mutating func consume(_ reported: String, expectedCheckID: String, currentCheckID: String) -> String? {
        guard turn >= 0, consumed != turn, expectedCheckID == currentCheckID,
              !VoiceIntent.normalize(words).isEmpty,
              VoiceIntent.normalize(reported) == VoiceIntent.normalize(words) else { return nil }
        consumed = turn
        return words
    }
}
