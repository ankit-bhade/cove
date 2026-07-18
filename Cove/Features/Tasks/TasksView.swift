import SwiftUI

/// All due tasks collected by the in-memory index: incomplete tasks sorted
/// by due date, completed ones below, with a quick-entry field on top that
/// understands sentences like "get bread 3p tmr". Toggling a checkbox
/// rewrites the line in the task's original Markdown file (a recurring task
/// rolls forward to its next occurrence); tapping the row opens the note.
struct TasksView: View {
    @Environment(VaultManager.self) private var vaultManager
    @State private var errorMessage: String?
    @State private var quickEntry = ""
    @State private var pendingDraft: PendingDraft?

    /// The sentence and its interpretation, handed to the confirmation
    /// sheet together so reopening the sheet always matches the field.
    private struct PendingDraft: Identifiable {
        let sentence: String
        let draft: TaskDraft
        var id: String { sentence }
    }

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Tasks")
                .navigationDestination(for: URL.self) { url in
                    EditorView(fileURL: url)
                }
                .toolbar {
                    ToolbarItem {
                        Button {
                            Task { await vaultManager.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
                .sheet(item: $pendingDraft) { pending in
                    TaskDraftSheet(sentence: pending.sentence, draft: pending.draft) { draft in
                        quickEntry = ""
                        Task {
                            do {
                                try await vaultManager.captureTask(draft)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
                .alert(
                    "Something Went Wrong",
                    isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { if !$0 { errorMessage = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "")
                }
                // Editor autosaves don't rescan the vault, so returning to
                // this tab rebuilds the index to pick up freshly typed tasks.
                .task {
                    await vaultManager.refresh()
                }
        }
    }

    private var list: some View {
        let incomplete = vaultManager.index.incompleteTasks
        let completed = vaultManager.index.completedTasks
        return List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    TextField("Add a task — try “get bread 3p tmr”", text: $quickEntry)
                        .autocorrectionDisabled()
                        .onSubmit(presentDraft)
                        .submitLabel(.done)
                }
            }
            if !incomplete.isEmpty {
                Section("Due") {
                    ForEach(incomplete) { task in
                        row(for: task)
                    }
                }
            }
            if !completed.isEmpty {
                Section("Completed") {
                    ForEach(completed) { task in
                        row(for: task)
                    }
                }
            }
            if incomplete.isEmpty, completed.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Tasks",
                        systemImage: "checklist",
                        description: Text("Type a task above — “get bread 3p tmr” — or add a line like “- [ ] Task text @due(2026-01-31)” to any note.")
                    )
                }
            }
        }
    }

    /// Interprets the quick-entry sentence and opens the confirmation sheet.
    private func presentDraft() {
        let sentence = quickEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        pendingDraft = PendingDraft(sentence: sentence,
                                    draft: QuickTaskParser.parse(sentence, now: .now))
    }

    private func row(for task: TaskItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                toggle(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.square" : "square")
                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete"
                                : task.recurrence == nil ? "Mark complete"
                                : "Complete and reschedule")

            NavigationLink(value: task.fileURL) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.text)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    HStack(spacing: 4) {
                        dueLabel(for: task)
                        if let rule = task.recurrence {
                            Text("·")
                            Label(rule.displayName, systemImage: "repeat")
                        }
                        Text("·")
                        Text(task.fileTitle)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func dueLabel(for task: TaskItem) -> some View {
        Group {
            if let moment = task.dueDateTime {
                Text(moment,
                     format: .dateTime.day().month(.abbreviated).year().hour().minute())
            } else if let date = task.dueDate {
                Text(date, format: .dateTime.day().month(.abbreviated).year())
            } else {
                Text(task.dueDateString)
            }
        }
        .foregroundStyle(isOverdue(task) ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
    }

    /// Overdue when the due day is past, or the due moment today is past.
    private func isOverdue(_ task: TaskItem) -> Bool {
        guard !task.isCompleted else { return false }
        if let moment = task.dueDateTime {
            return moment < .now
        }
        return task.dueDateString < QuickTaskParser.ymdString(from: .now)
    }

    private func toggle(_ task: TaskItem) {
        Task {
            do {
                try await vaultManager.toggleTask(task)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
