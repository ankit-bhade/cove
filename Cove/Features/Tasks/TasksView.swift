import SwiftUI

/// All due tasks collected by the in-memory index: incomplete tasks sorted
/// by due date, completed ones below, with a quick-entry field on top that
/// understands sentences like "get bread 3p tmr". Toggling a checkbox
/// rewrites the line in the task's original Markdown file (a recurring task
/// rolls forward to its next occurrence); tapping the row opens the note.
struct TasksView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var errorMessage: String?
    @State private var quickEntry = ""
    @State private var pendingDraft: PendingDraft?
    @State private var isClearingCompleted = false
    @State private var showsClearCompletedConfirmation = false

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
                .confirmationDialog(
                    "Clear All Completed Tasks?",
                    isPresented: $showsClearCompletedConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear All", role: .destructive) {
                        clearCompletedTasks()
                    }
                } message: {
                    Text("This permanently removes every completed task line from its Markdown note.")
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
                quickCaptureCard(openCount: incomplete.count, completedCount: completed.count)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 14, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if !incomplete.isEmpty {
                Section {
                    ForEach(incomplete) { task in
                        row(for: task)
                    }
                } header: {
                    Text("Open · \(incomplete.count)")
                        .font(.caption.weight(.semibold))
                }
            }
            if !completed.isEmpty {
                Section {
                    ForEach(completed) { task in
                        row(for: task)
                    }
                } header: {
                    HStack {
                        Text("Completed · \(completed.count)")
                        Spacer()
                        Button("Clear All", role: .destructive) {
                            showsClearCompletedConfirmation = true
                        }
                        .buttonStyle(.borderless)
                        .disabled(isClearingCompleted)
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            if incomplete.isEmpty, completed.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("A Clear Horizon", systemImage: "checkmark.circle")
                    } description: {
                        Text("Capture a task above, or add a due-task line to any note.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .listRowBackground(Color.clear)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .background(CoveTheme.canvas(for: colorScheme))
    }

    private func quickCaptureCard(openCount: Int, completedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Capture")
                        .font(.headline)
                    Text("Write naturally. Cove will find the date and time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "circle")
                    Text("\(openCount) open")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(CoveTheme.teal)
            }

            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(CoveTheme.brandGradient, in: Circle())
                TextField("e.g. Get bread tomorrow at 3pm", text: $quickEntry)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .onSubmit(presentDraft)
                    .submitLabel(.done)
            }
            .padding(11)
            .background(CoveTheme.canvas(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(CoveTheme.border(for: colorScheme), lineWidth: 1)
            }

            if completedCount > 0 {
                Label("\(completedCount) completed across your vault",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background { CoveCardBackground() }
    }

    /// Interprets the quick-entry sentence and opens the confirmation sheet.
    private func presentDraft() {
        let sentence = quickEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        pendingDraft = PendingDraft(sentence: sentence,
                                    draft: QuickTaskParser.parse(sentence, now: .now))
    }

    private func row(for task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Button {
                toggle(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(task.isCompleted ? Color.secondary : CoveTheme.teal)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete"
                                : task.recurrence == nil ? "Mark complete"
                                : "Complete and reschedule")

            NavigationLink(value: task.fileURL) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(task.text)
                        .font(.body.weight(.medium))
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    HStack(spacing: 7) {
                        dueLabel(for: task)
                        if let rule = task.recurrence {
                            Label(rule.displayName, systemImage: "repeat")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Label(task.fileTitle, systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
    }

    private func dueLabel(for task: TaskItem) -> some View {
        let overdue = isOverdue(task)
        return HStack(spacing: 5) {
            Image(systemName: overdue ? "exclamationmark.circle.fill" : "calendar")
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
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(overdue ? Color.red : CoveTheme.teal)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background((overdue ? Color.red : CoveTheme.teal).opacity(0.10), in: Capsule())
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

    private func clearCompletedTasks() {
        isClearingCompleted = true
        Task {
            defer { isClearingCompleted = false }
            do {
                try await vaultManager.clearCompletedTasks()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
