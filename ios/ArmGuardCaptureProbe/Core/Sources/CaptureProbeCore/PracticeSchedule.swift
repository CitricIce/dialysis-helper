import Foundation

/// A personal practice plan, not a prescription or a treatment record.
public struct PracticeRoutine: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var minuteOfDay: Int?
    public var reminder: Bool
    public var note: String
    public var completedAt: Date?

    public init(id: UUID = UUID(), name: String, minuteOfDay: Int? = nil,
                reminder: Bool = false, note: String = "", completedAt: Date? = nil) {
        self.id = id; self.name = name; self.minuteOfDay = minuteOfDay
        self.reminder = reminder; self.note = note; self.completedAt = completedAt
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (minuteOfDay.map { (0..<1440).contains($0) } ?? true) && (!reminder || minuteOfDay != nil)
    }
    public func completed(on date: Date, calendar: Calendar = .current) -> Bool {
        completedAt.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    }
    public static func ordered(_ routines: [PracticeRoutine]) -> [PracticeRoutine] {
        // Stable order for untimed routines or matching times.
        routines.enumerated().sorted {
            let left = $0.element.minuteOfDay ?? 1440, right = $1.element.minuteOfDay ?? 1440
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }
}
