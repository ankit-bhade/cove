import SwiftUI

/// The fields a task is written down with: its title, its date, its time, and
/// how often it comes back.
///
/// One copy, because two sheets edit them. The capture sheet checks what a
/// sentence was understood as before the line is written; the details sheet
/// edits a line that already exists. What a date picker or a repeat rule
/// *means* is the same in both, and a repeat option offered on one screen and
/// not the other is precisely the drift `TaskActions` and `TaskRow` exist to
/// prevent on the rows below.
struct TaskScheduleFields: View {
    @Binding var draft: TaskDraft
    /// Whether the task may go without a date at all. True only inside a
    /// list, where `@due` is optional; a task bound for the Tasks screen has
    /// to carry one.
    let allowsUndated: Bool
    /// Called on every field edit. The capture sheet uses it to stop treating
    /// the sentence as the source of truth once the fields have been touched.
    var onEdit: () -> Void = {}

    var body: some View {
        // The label above and the field below used to be stacked, which left
        // the title starting at the section's edge while every value under
        // it — date, time, repeat — sat in the trailing column. One row, one
        // grid.
        LabeledContent {
            TextField("Task title", text: titleBinding, axis: .vertical)
                .lineLimit(1...3)
                .multilineTextAlignment(.trailing)
        } label: {
            Label("Title", systemImage: "textformat")
        }
        if allowsUndated {
            Toggle(isOn: dateEnabledBinding) {
                Label("Due Date", systemImage: "calendar")
            }
        }
        if draft.dueDateString != nil {
            DatePicker(selection: dateBinding, displayedComponents: .date) {
                Label("Date", systemImage: "calendar")
            }
            Toggle(isOn: timeEnabledBinding) {
                Label("Time", systemImage: "clock")
            }
            if draft.dueTimeString != nil {
                DatePicker(
                    selection: timeBinding,
                    displayedComponents: .hourAndMinute
                ) {
                    // A clock, not a bell: this row sets a time, and the
                    // section below is the one that speaks for what does and
                    // doesn't get a reminder. The repeat is deliberate — the
                    // toggle above it and its value share a glyph exactly as
                    // Due Date and Date do.
                    Label("At", systemImage: "clock")
                }
            }
            // A repeat rule hangs off the `@due` tag, so it only exists for a
            // dated task.
            Picker(selection: recurrenceBinding) {
                ForEach(recurrenceOptions, id: \.self) { rule in
                    Text(rule?.displayName ?? "Never")
                        .tag(rule)
                }
            } label: {
                Label("Repeat", systemImage: "repeat")
            }
        }
    }

    /// Common presets, plus the draft's own rule when it is one the presets
    /// can't express (e.g. "every mon wed", "every 2 weeks").
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

    private var titleBinding: Binding<String> {
        Binding {
            draft.title
        } set: { value in
            onEdit()
            draft.title = value
        }
    }

    private var dateEnabledBinding: Binding<Bool> {
        Binding {
            draft.dueDateString != nil
        } set: { enabled in
            onEdit()
            if enabled {
                draft.dueDateString =
                    draft.dueDateString ?? QuickTaskParser.ymdString(from: .now)
            } else {
                // Both tags live inside or after `@due`, so they go with it.
                draft.dueDateString = nil
                draft.dueTimeString = nil
                draft.recurrence = nil
            }
        }
    }

    /// `dueDateString` as a `Date` for the picker (noon-anchored so the
    /// round-trip through the picker never shifts a day).
    private var dateBinding: Binding<Date> {
        Binding {
            let parts = (draft.dueDateString ?? "").split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                let date = TaskCalendar.gregorian().date(
                    from: DateComponents(
                        year: parts[0], month: parts[1], day: parts[2], hour: 12))
            else { return .now }
            return date
        } set: { newValue in
            onEdit()
            draft.dueDateString = QuickTaskParser.ymdString(from: newValue)
        }
    }

    private var timeEnabledBinding: Binding<Bool> {
        Binding {
            draft.dueTimeString != nil
        } set: { enabled in
            onEdit()
            draft.dueTimeString = enabled ? (draft.dueTimeString ?? "09:00") : nil
        }
    }

    private var timeBinding: Binding<Date> {
        Binding {
            let parts = (draft.dueTimeString ?? "09:00")
                .split(separator: ":").compactMap { Int($0) }
            let components = DateComponents(
                hour: parts.first ?? 9,
                minute: parts.count > 1 ? parts[1] : 0)
            return TaskCalendar.gregorian().date(from: components) ?? .now
        } set: { newValue in
            onEdit()
            let parts = TaskCalendar.gregorian().dateComponents(
                [.hour, .minute],
                from: newValue)
            draft.dueTimeString = String(format: "%02d:%02d", parts.hour!, parts.minute!)
        }
    }

    private var recurrenceBinding: Binding<RecurrenceRule?> {
        Binding {
            draft.recurrence
        } set: { value in
            onEdit()
            draft.recurrence = value
        }
    }
}

/// What the schedule above will and won't remind you about. Only a task with
/// both a date and a time gets a notification, which is the one rule about
/// reminders a sheet full of pickers cannot show by itself.
struct TaskNotificationNote: View {
    let draft: TaskDraft

    var body: some View {
        Label {
            if draft.dueTimeString != nil {
                Text(
                    draft.recurrence == nil
                        ? "Notification at the time above."
                        : "Notification at the time above, every occurrence.")
            } else if draft.dueDateString == nil {
                Text("No due date, so no notification.")
            } else {
                Text("No time set, so no notification.")
            }
        } icon: {
            Image(systemName: draft.dueTimeString != nil ? "bell" : "bell.slash")
        }
        .foregroundStyle(.secondary)
        .font(.callout)
        .padding(.vertical, 3)
    }
}
