import SwiftUI
import UserNotifications

@MainActor final class PracticePlanner: ObservableObject {
    @Published private(set) var routines: [PracticeRoutine] = []
    @Published private(set) var reminderMessage = ""
    private let storageKey = "sterling.practiceRoutines.v1"
    private let notificationPrefix = "sterling.routine."

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([PracticeRoutine].self, from: data) {
            routines = PracticeRoutine.ordered(saved.filter(\.isValid))
        }
    }
    func seed(names: [String]) {
        // An intentionally emptied plan stays empty on the next launch.
        guard UserDefaults.standard.data(forKey: storageKey) == nil else { return }
        routines = names.map { PracticeRoutine(name: $0) }; persist()
    }
    func save(_ routine: PracticeRoutine) {
        guard routine.isValid else { return }
        if let index = routines.firstIndex(where: { $0.id == routine.id }) { routines[index] = routine }
        else { routines.append(routine) }
        routines = PracticeRoutine.ordered(routines); persist(); syncReminders()
    }
    func delete(_ id: UUID) {
        routines.removeAll { $0.id == id }; persist(); syncReminders()
    }
    func complete(_ id: UUID, at date: Date = Date()) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].completedAt = date; persist()
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(routines) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    private var reminderTask: Task<Void, Never>?
    func syncReminders() {
        let previous = reminderTask
        previous?.cancel()
        reminderTask = Task {
            // Serialize rapid edits so an older in-flight add cannot restore a deleted reminder.
            await previous?.value
            guard !Task.isCancelled else { return }
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(notificationPrefix) })
            let enabled = routines.filter { $0.reminder && $0.isValid }
            guard !enabled.isEmpty else { reminderMessage = ""; return }
            do {
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                guard !Task.isCancelled else { return }
                guard allowed else { reminderMessage = "Reminders are off in iPhone Settings. Your routines are still saved."; return }
                for routine in routines.filter({ $0.reminder && $0.isValid }) {
                    guard let minute = routine.minuteOfDay, !Task.isCancelled else { return }
                    let content = UNMutableNotificationContent()
                    content.title = "Sterling"
                    content.body = "Time for \(routine.name). Open Sterling when you're ready."
                    content.sound = .default
                    var components = DateComponents(); components.hour = minute / 60; components.minute = minute % 60
                    try await center.add(UNNotificationRequest(identifier: notificationPrefix + routine.id.uuidString,
                        content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
                }
                reminderMessage = ""
            } catch {
                if !Task.isCancelled { reminderMessage = "Couldn't schedule reminders. Open Settings to check notification access." }
            }
        }
    }
}

struct RoutineEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var routine: PracticeRoutine
    var isNew: Bool
    var checks: [RoutineCheck]
    var save: (PracticeRoutine) -> Void
    var delete: (UUID) -> Void
    private var time: Binding<Date> {
        Binding(get: {
            let minutes = routine.minuteOfDay ?? 9 * 60
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: {
            routine.minuteOfDay = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0)
        })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Name, such as Morning exchange", text: $routine.name)
                    Toggle("Set a time", isOn: Binding(get: { routine.minuteOfDay != nil }, set: {
                        routine.minuteOfDay = $0 ? 9 * 60 : nil
                        if !$0 { routine.reminder = false }
                    }))
                    if routine.minuteOfDay != nil {
                        DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                        Toggle("Remind me each day", isOn: $routine.reminder)
                    }
                }
                Section {
                    TextField("Optional reminder to yourself", text: $routine.note, axis: .vertical)
                } header: { Text("Your notes") } footer: {
                    Text("Use the schedule and supplies in your care team's instructions. These notes aren't checked by the voice assistant. Every routine currently uses the same practice steps.")
                }
                Section {
                    Text("These are examples, not a script. Use your own words and the details on your actual supplies. You can ask questions, say ‘pause’ or ‘resume’, or ask to move to the next practice step.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                        DisclosureGroup("\(index + 1). \(check.title)") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(check.prompt).font(.subheadline).foregroundStyle(.secondary)
                                Text("You could say").font(.caption.bold())
                                ForEach(check.exampleResponses ?? [], id: \.self) { example in
                                    Text("“\(example)”").font(.body).textSelection(.enabled)
                                }
                                if check.id == "supplies" {
                                    Text("Read the real label, then confirm the read-back. If Sterling asks for one missing detail, say just that detail; you don't need to start again. Bracketed words above are spaces for your own label details.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                } else if check.responseKind == .monitoring {
                                    Text("Say ‘ready’ to begin, then ‘done’ to finish. The current model is experimental; it cannot confirm safe contact or sterility.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 8)
                        }
                    }
                } header: { Text("What to say at each check") } footer: {
                    Text("Practice progression can be unverified. A possible-contact review still needs your care team's instructions.")
                }
                if !isNew {
                    Section { Button("Delete routine", role: .destructive) { delete(routine.id); dismiss() } }
                }
            }.navigationTitle(isNew ? "Add a routine" : "Edit routine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            routine.name = routine.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            save(routine); dismiss()
                        }.disabled(!routine.isValid)
                    }
                }
        }.tint(SterlingStyle.accent)
    }
}
