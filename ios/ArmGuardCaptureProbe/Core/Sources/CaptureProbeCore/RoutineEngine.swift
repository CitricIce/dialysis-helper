import Foundation

public struct RoutineCheck: Codable, Identifiable, Equatable {
    public enum ResponseKind: String, Codable { case actionReport, readBack, monitoring }
    public let id: String
    public let title: String
    public let prompt: String
    public let help: String
    public let responseKind: ResponseKind
}

public struct RoutineTemplate: Codable, Equatable {
    public let schemaVersion: Int
    public let id: String
    public let title: String
    public let practiceOnly: Bool
    public let protocolNote: String
    public let slots: [String]
    public let checks: [RoutineCheck]

    public func validate() throws {
        guard schemaVersion == 1, practiceOnly, !slots.isEmpty, !checks.isEmpty,
              Set(checks.map(\.id)).count == checks.count,
              checks.allSatisfy({ !$0.id.isEmpty && !$0.prompt.isEmpty }),
              checks.contains(where: { $0.responseKind == .monitoring }) else { throw RoutineError.invalidTemplate }
    }
    public enum RoutineError: Error { case invalidTemplate }
}

public enum RoutinePhase: String, Codable {
    case idle, checking, paused, monitoring, reviewRequired, preparationOnly, completed
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
    public private(set) var events: [RoutineEvent] = []
    public private(set) var reviewRequired = false
    private var pausedPhase: RoutinePhase = .checking

    public init(template: RoutineTemplate) throws {
        try template.validate()
        self.template = template
    }

    public var currentCheck: RoutineCheck? {
        guard template.checks.indices.contains(checkIndex) else { return nil }
        return template.checks[checkIndex]
    }

    public mutating func start() {
        guard phase == .idle else { return }
        phase = .checking
        record("started", evidence: "practice")
    }

    /// Responses are recorded as self-reports, never as verified clinical observations.
    public mutating func submit(_ text: String) -> String {
        guard phase == .checking, let check = currentCheck, check.responseKind != .monitoring else {
            return "Use the monitoring controls for this step."
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = VoiceIntent.normalize(cleaned)
        let words = normalized.split(separator: " ")
        let uncertainty = ["not ready", "not sure", "unsure", "have not", "haven t", "did not", "didn t", "wrong bag"]
        let questionStarts = ["why ", "how ", "what ", "when ", "where ", "should ", "can ", "could ", "do i ", "is it "]
        if cleaned.contains("?") || questionStarts.contains(where: normalized.hasPrefix) {
            pendingReadBack = nil
            return "That sounds like a question. Say ask a question for a conversation, or help for offline explanation. This check is still open."
        }
        let emptyConfirmations: Set<String> = ["yes", "done", "ready", "okay", "ok", "confirm"]
        guard words.count >= 3, !words.allSatisfy({ emptyConfirmations.contains(String($0)) }),
              !uncertainty.contains(where: normalized.contains) else {
            pendingReadBack = nil
            return "Take your time. Describe what you checked, or say help. A yes or done alone will not finish this check."
        }
        if check.responseKind == .readBack {
            pendingReadBack = cleaned
            return "Read-back captured, not clinically verified. If it matches your instructions, say confirm. Otherwise say help."
        }
        advance(evidence: "self_report")
        return currentCheck?.prompt ?? "Preparation practice recorded."
    }

    public mutating func confirmReadBack() -> Bool {
        guard phase == .checking, currentCheck?.responseKind == .readBack,
              pendingReadBack != nil else { return false }
        advance(evidence: "self_reported_read_back")
        return true
    }

    public mutating func armMonitoring(visionReady: Bool) -> Bool {
        guard phase == .checking, currentCheck?.responseKind == .monitoring,
              visionReady, !reviewRequired else { return false }
        phase = .monitoring
        record("monitoring_armed", evidence: "experimental_detector")
        return true
    }

    public mutating func finishPreparationOnly() {
        guard phase == .checking, currentCheck?.responseKind == .monitoring,
              !reviewRequired else { return }
        phase = .preparationOnly
        record("preparation_only", evidence: "connection_not_monitored")
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
        guard phase == .checking || phase == .monitoring || phase == .reviewRequired else { return }
        pausedPhase = phase
        phase = .paused
        record("paused", evidence: "user_or_lifecycle")
    }

    public mutating func resume() {
        guard phase == .paused else { return }
        // A former monitoring session must be explicitly rearmed with fresh observations.
        phase = reviewRequired ? .reviewRequired : (pausedPhase == .monitoring ? .checking : pausedPhase)
    }

    private mutating func advance(evidence: String) {
        record("check_recorded", evidence: evidence)
        pendingReadBack = nil
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
    case pause, repeatPrompt, help, askQuestion, confirm, arm, finishPreparation, finishMonitoring, answer(String)
    public static func normalize(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
    public static func parse(_ text: String) -> VoiceIntent {
        switch normalize(text) {
        case "pause", "stop", "pause routine", "stop routine": return .pause
        case "repeat", "repeat that": return .repeatPrompt
        case "help", "i need help", "not ready": return .help
        case "ask a question", "i have a question", "voice questions": return .askQuestion
        case "confirm", "i confirm": return .confirm
        case "start monitoring", "arm monitoring": return .arm
        case "finish preparation practice": return .finishPreparation
        case "finish monitoring", "finish connection practice": return .finishMonitoring
        default: return .answer(text)
        }
    }
}
