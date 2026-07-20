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

    private var allowsUndated: Bool { listName != nil }

    private var canAdd: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 13) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(CoveTheme.brandGradient,
                                        in: RoundedRectangle(cornerRadius: 12,
                                                             style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Review Cove’s Interpretation")
                                .font(.headline)
                            Text(listName.map { "Fine-tune anything before it’s added to \($0)." }
                                 ?? "Fine-tune anything before it’s added to Tasks.md.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background { CoveCardBackground() }
                    .listRowInsets(CoveTheme.dashboardRowInsets(bottom: 12))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    HStack(spacing: 10) {
                        CoveIconTile(systemName: "quote.bubble.fill")
                        TextField("Try “get bread 3p tmr”", text: $sentence)
                            .autocorrectionDisabled()
                            .onChange(of: sentence) { _, newValue in
                                draft = QuickTaskParser.parse(
                                    newValue, now: .now,
                                    defaultingToToday: !allowsUndated)
                            }
                    }
                } header: {
                    Text("Task")
                } footer: {
                    Text("Dates, times, and repeats at the end of the sentence are understood — e.g. “tmr”, “next fri”, “6pm”, “every sun”.")
                }

                Section("Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Title", systemImage: "textformat")
                            .font(.subheadline.weight(.medium))
                        TextField("Task title", text: $draft.title, axis: .vertical)
                            .lineLimit(1...3)
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
                            DatePicker(selection: timeBinding,
                                       displayedComponents: .hourAndMinute) {
                                Label("At", systemImage: "bell")
                            }
                        }
                        // A repeat rule hangs off the `@due` tag, so it only
                        // exists for a dated task.
                        Picker(selection: $draft.recurrence) {
                            ForEach(recurrenceOptions, id: \.self) { rule in
                                Text(rule?.displayName ?? "Never")
                                    .tag(rule)
                            }
                        } label: {
                            Label("Repeat", systemImage: "repeat")
                        }
                    }
                }

                Section {
                    Label {
                        if draft.dueTimeString != nil {
                            Text(draft.recurrence == nil
                                 ? "Notification at the time above."
                                 : "Notification at the time above, every occurrence.")
                        } else if draft.dueDateString == nil {
                            Text("No due date, so no notification.")
                        } else {
                            Text("No time set, so no notification.")
                        }
                    } icon: {
                        Image(systemName: draft.dueTimeString != nil
                              ? "bell" : "bell.slash")
                    }
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .padding(.vertical, 3)
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
