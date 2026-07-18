import SwiftUI

/// Confirmation sheet for a quick-added task: shows how the sentence was
/// interpreted and lets the user adjust the title, date, time, and
/// recurrence before the Markdown line is written. Editing the sentence
/// re-interprets everything; editing the fields below tweaks the current
/// draft directly.
struct TaskDraftSheet: View {
    @State var sentence: String
    @State var draft: TaskDraft
    let onConfirm: (TaskDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    private var canAdd: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Try “get bread 3p tmr”", text: $sentence)
                        .autocorrectionDisabled()
                        .onChange(of: sentence) { _, newValue in
                            draft = QuickTaskParser.parse(newValue, now: .now)
                        }
                } header: {
                    Text("Task")
                } footer: {
                    Text("Dates, times, and repeats at the end of the sentence are understood — e.g. “tmr”, “next fri”, “6pm”, “every sun”.")
                }

                Section("Details") {
                    TextField("Title", text: $draft.title)
                    DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                    Toggle("Time", isOn: timeEnabledBinding)
                    if draft.dueTimeString != nil {
                        DatePicker("At", selection: timeBinding,
                                   displayedComponents: .hourAndMinute)
                    }
                    Picker("Repeat", selection: $draft.recurrence) {
                        ForEach(recurrenceOptions, id: \.self) { rule in
                            Text(rule?.displayName ?? "Never")
                                .tag(rule)
                        }
                    }
                }

                Section {
                    Label {
                        if draft.dueTimeString != nil {
                            Text(draft.recurrence == nil
                                 ? "Notification at the time above."
                                 : "Notification at the time above, every occurrence.")
                        } else {
                            Text("No time set, so no notification.")
                        }
                    } icon: {
                        Image(systemName: draft.dueTimeString != nil
                              ? "bell" : "bell.slash")
                    }
                    .foregroundStyle(.secondary)
                    .font(.callout)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onConfirm(draft)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 440)
        #endif
    }

    /// Common presets, plus the parsed rule when the sentence produced one
    /// the presets can't express (e.g. "every mon wed", "every 2 weeks").
    private var recurrenceOptions: [RecurrenceRule?] {
        var options: [RecurrenceRule?] = [
            nil,
            RecurrenceRule(frequency: .daily),
            RecurrenceRule(frequency: .weekly),
            RecurrenceRule(frequency: .monthly),
            RecurrenceRule(frequency: .yearly),
            .everyWeekday,
        ]
        if let current = draft.recurrence, !options.contains(current) {
            options.append(current)
        }
        return options
    }

    // MARK: - Field bindings

    /// `dueDateString` as a `Date` for the picker (noon-anchored so the
    /// round-trip through the picker never shifts a day).
    private var dateBinding: Binding<Date> {
        Binding {
            let parts = draft.dueDateString.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = Calendar.current.date(from: DateComponents(
                      year: parts[0], month: parts[1], day: parts[2], hour: 12))
            else { return .now }
            return date
        } set: { newValue in
            draft.dueDateString = QuickTaskParser.ymdString(from: newValue)
        }
    }

    private var timeEnabledBinding: Binding<Bool> {
        Binding {
            draft.dueTimeString != nil
        } set: { enabled in
            draft.dueTimeString = enabled ? (draft.dueTimeString ?? "09:00") : nil
        }
    }

    private var timeBinding: Binding<Date> {
        Binding {
            let parts = (draft.dueTimeString ?? "09:00")
                .split(separator: ":").compactMap { Int($0) }
            let components = DateComponents(hour: parts.first ?? 9,
                                            minute: parts.count > 1 ? parts[1] : 0)
            return Calendar.current.date(from: components) ?? .now
        } set: { newValue in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            draft.dueTimeString = String(format: "%02d:%02d", parts.hour!, parts.minute!)
        }
    }
}
