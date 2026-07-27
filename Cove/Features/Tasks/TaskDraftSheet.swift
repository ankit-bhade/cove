import SwiftUI

/// Confirmation sheet for a quick-added task: shows how the sentence was
/// interpreted and lets the user adjust the title, date, time, and
/// recurrence before the Markdown line is written. Editing the sentence
/// re-interprets everything; editing the fields below tweaks the current
/// draft directly.
struct TaskDraftSheet: View {
    @State var sentence: String
    @State var draft: TaskDraft
    /// The list this task is bound for, when it came from the Lists screen.
    /// Its items may be undated, so the date becomes a toggle and the sheet
    /// says where the task is going.
    var listName: String?
    let onConfirm: (TaskDraft) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var didEditDetails = false

    private var allowsUndated: Bool { listName != nil }

    /// The sheet is the place a blocking diagnostic gets resolved, so once
    /// the details have been touched even an unwritable sentence can be
    /// added — the fields, not the sentence, are what gets saved by then.
    /// Advisory diagnostics never gate the button here either.
    private var canAdd: Bool {
        draft.validationIssues.isEmpty
            && (didEditDetails || !parseDiagnostics.contains(where: \.blocksCapture))
    }

    private var parseDiagnostics: [QuickTaskParser.Diagnostic] {
        QuickTaskParser.parseWithDiagnostics(
            sentence,
            now: .now,
            defaultingToToday: !allowsUndated
        ).diagnostics
    }

    var body: some View {
        NavigationStack {
            Form {
                // No masthead: a sheet already announces itself in its own
                // title bar, and "Check the details" under "New Task" was a
                // second heading that pushed the fields being checked below
                // the fold on a phone.
                Section {
                    CoveRow(systemName: "quote.bubble.fill") {
                        TextField("Try “get bread 3p tmr”", text: $sentence)
                            .autocorrectionDisabled()
                            .onChange(of: sentence) { _, newValue in
                                draft =
                                    QuickTaskParser.parseWithDiagnostics(
                                        newValue, now: .now,
                                        defaultingToToday: !allowsUndated
                                    ).draft
                                didEditDetails = false
                            }
                    }
                    if let diagnostic = parseDiagnostics.first {
                        Label(
                            diagnostic.message,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(CoveTheme.alert)
                    }
                    if let issue = draft.validationIssues.first {
                        Label(
                            issue.message,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(CoveTheme.alert)
                    }
                } header: {
                    CoveSectionHeader("Task")
                } footer: {
                    Text(
                        "Dates, times, and repeats at the end of the sentence are understood — e.g. “tmr”, “next fri”, “6pm”, “every sun”."
                    )
                }

                Section {
                    // The label above and the field below used to be stacked,
                    // which left the title starting at the section's edge
                    // while every value under it — date, time, repeat — sat in
                    // the trailing column. One row, one grid.
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
                                // A clock, not a bell: this row sets a time,
                                // and the section below is the one that speaks
                                // for what does and doesn't get a reminder.
                                // The repeat is deliberate — the toggle above
                                // it and its value share a glyph exactly as
                                // Due Date and Date do.
                                Label("At", systemImage: "clock")
                            }
                        }
                        // A repeat rule hangs off the `@due` tag, so it only
                        // exists for a dated task.
                        Picker(selection: recurrenceBinding) {
                            ForEach(recurrenceOptions, id: \.self) { rule in
                                Text(rule?.displayName ?? "Never")
                                    .tag(rule)
                            }
                        } label: {
                            Label("Repeat", systemImage: "repeat")
                        }
                    }
                } header: {
                    CoveSectionHeader("Details")
                }

                Section {
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
                        Image(
                            systemName: draft.dueTimeString != nil
                                ? "bell" : "bell.slash")
                    }
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(.vertical, 3)
                } footer: {
                    // Where the line lands: the removed header used to carry
                    // this, and it is the one thing about the sheet a person
                    // can't see from the fields.
                    Text(
                        listName.map { "Added to the “\($0)” list in Tasks.md." }
                            ?? "Added to Tasks.md at the top of your vault.")
                }
            }
            .disabled(isAdding)
            .coveFormStyle()
            .coveReadableWidth(680)
            .navigationTitle("New Task")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isAdding)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        addTask()
                    } label: {
                        if isAdding {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Add")
                        }
                    }
                    .disabled(!canAdd || isAdding)
                    .accessibilityLabel(isAdding ? "Adding task" : "Add task")
                }
            }
            .coveErrorAlert($errorMessage)
        }
        .interactiveDismissDisabled(isAdding)
        #if os(macOS)
            .frame(minWidth: 380, minHeight: 440)
        #endif
    }

    private func addTask() {
        guard canAdd, !isAdding else { return }
        do {
            _ = try draft.validatedMarkdownLine()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        isAdding = true
        Task {
            do {
                try await onConfirm(draft)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isAdding = false
            }
        }
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
    private var dateEnabledBinding: Binding<Bool> {
        Binding {
            draft.dueDateString != nil
        } set: { enabled in
            didEditDetails = true
            if enabled {
                draft.dueDateString = draft.dueDateString ?? QuickTaskParser.ymdString(from: .now)
            } else {
                // Both tags live inside or after `@due`, so they go with it.
                draft.dueDateString = nil
                draft.dueTimeString = nil
                draft.recurrence = nil
            }
        }
    }

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
            didEditDetails = true
            draft.dueDateString = QuickTaskParser.ymdString(from: newValue)
        }
    }

    private var timeEnabledBinding: Binding<Bool> {
        Binding {
            draft.dueTimeString != nil
        } set: { enabled in
            didEditDetails = true
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
            didEditDetails = true
            let parts = TaskCalendar.gregorian().dateComponents(
                [.hour, .minute],
                from: newValue)
            draft.dueTimeString = String(format: "%02d:%02d", parts.hour!, parts.minute!)
        }
    }

    private var titleBinding: Binding<String> {
        Binding {
            draft.title
        } set: { value in
            didEditDetails = true
            draft.title = value
        }
    }

    private var recurrenceBinding: Binding<RecurrenceRule?> {
        Binding {
            draft.recurrence
        } set: { value in
            didEditDetails = true
            draft.recurrence = value
        }
    }
}
