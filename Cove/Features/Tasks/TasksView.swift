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
    /// Ticks each minute so "Overdue" and "Today" stay accurate while the
    /// tab sits open across a due moment or across midnight.
    @State private var now = Date()

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
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        now = Date()
                    }
                }
        }
    }

    private var list: some View {
        let incomplete = vaultManager.index.incompleteTasks
        let completed = vaultManager.index.completedTasks
        return List {
            Section {
                quickCaptureCard(openCount: incomplete.count)
                    .listRowInsets(CoveTheme.dashboardRowInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(TaskGroup.grouping(incomplete, now: now)) { group in
                Section {
                    ForEach(group.tasks) { task in
                        row(for: task, now: now)
                    }
                } header: {
                    Label(group.title, systemImage: group.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(group.isOverdue ? Color.red : .secondary)
                }
            }
            if !completed.isEmpty {
                Section {
                    ForEach(completed) { task in
                        row(for: task, now: now)
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
        .coveListStyle()
    }

    private func quickCaptureCard(openCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Quick Capture")
                    .font(.headline)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "circle")
                    Text("\(openCount) open")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(CoveTheme.teal)
            }

            HStack(spacing: 10) {
                TextField("e.g. Get bread tomorrow at 3pm", text: $quickEntry)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .onSubmit(presentDraft)
                    .submitLabel(.done)
                // Previously a decorative glyph that looked tappable and did
                // nothing. It is now the actual submit action, and it leads
                // the trailing edge so the field reads left-to-right.
                Button(action: presentDraft) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(canCapture ? AnyShapeStyle(CoveTheme.brandGradient)
                                    : AnyShapeStyle(Color.secondary.opacity(0.4)),
                                    in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canCapture)
                .animation(.easeInOut(duration: 0.15), value: canCapture)
                .accessibilityLabel("Interpret and add task")
            }
            .padding(11)
            .background(CoveTheme.canvas(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(CoveTheme.border(for: colorScheme), lineWidth: 1)
            }

        }
        .padding(18)
        .background { CoveCardBackground() }
    }

    private var canCapture: Bool {
        !quickEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Interprets the quick-entry sentence and opens the confirmation sheet.
    private func presentDraft() {
        let sentence = quickEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        pendingDraft = PendingDraft(sentence: sentence,
                                    draft: QuickTaskParser.parse(sentence, now: .now))
    }

    private func row(for task: TaskItem, now: Date) -> some View {
        let overdue = task.isOverdue(at: now)
        return HStack(alignment: .top, spacing: 11) {
            Button {
                toggle(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(task.isCompleted ? Color.secondary : CoveTheme.teal)
                    // The glyph alone is a small target; padding brings the
                    // hit area up to the 44pt minimum without moving it.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: -10)
            .padding(.trailing, -10)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete"
                                : task.recurrence == nil ? "Mark complete"
                                : "Complete and reschedule")

            NavigationLink(value: task.fileURL) {
                // The source note is deliberately not shown: tasks nearly
                // always live in the capture note, so the row read as a
                // repeated "Tasks" caption under every task.
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.text)
                        .font(.body.weight(.medium))
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    HStack(spacing: 7) {
                        dueLabel(for: task, overdue: overdue, now: now)
                        if let rule = task.recurrence {
                            Label(rule.displayName, systemImage: "repeat")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                delete(task)
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        }
    }

    private func dueLabel(for task: TaskItem, overdue: Bool, now: Date) -> some View {
        let tint: Color = overdue ? .red
            : task.isDue(onSameDayAs: now) ? CoveTheme.teal
            : .secondary
        return HStack(spacing: 5) {
            Image(systemName: overdue ? "exclamationmark.circle.fill"
                  : task.dueTimeString != nil ? "clock" : "calendar")
            Text(task.relativeDueDescription(at: now))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10), in: Capsule())
    }

    /// Removes the task's line from its note. Deliberately not confirmed —
    /// a swipe (or a context-menu pick) is already a deliberate gesture, and
    /// the bulk Clear All is the destructive action worth a dialog.
    private func delete(_ task: TaskItem) {
        Task {
            do {
                try await vaultManager.deleteTask(task)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
