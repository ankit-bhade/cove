import SwiftUI
import OSLog

/// All due tasks collected by the in-memory index: incomplete tasks sorted
/// by due date, completed ones below, with a quick-entry field on top that
/// understands sentences like "get bread 3p tmr". Toggling a checkbox
/// rewrites the line in the task's original Markdown file (a recurring task
/// rolls forward to its next occurrence); tapping the row opens the note.
struct TasksView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.undoManager) private var undoManager
    @State private var errorMessage: String?
    @State private var isClearingCompleted = false
    @State private var showsClearCompletedConfirmation = false
    @State private var pendingTaskIDs: Set<String> = []
    /// Ticks each minute so "Overdue" and "Today" stay accurate while the
    /// tab sits open across a due moment or across midnight.
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Tasks")
                .navigationDestination(for: URL.self) { url in
                    EditorView(fileURL: url)
                }
                .toolbar {
                    ToolbarItem {
                        CoveRefreshButton {
                            await vaultManager.refresh()
                        }
                    }
                }
                .coveErrorAlert($errorMessage)
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
                captureMasthead(openCount: incomplete.count)
                    .listRowInsets(CoveTheme.mastheadRowInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(TaskGroup.grouping(incomplete, now: now)) { group in
                Section {
                    ForEach(group.tasks) { task in
                        TaskRow(task: task, now: now,
                                onToggle: { toggle(task) },
                                onDelete: { delete(task) },
                                isProcessing: pendingTaskIDs.contains(task.id))
                    }
                } header: {
                    // Tracked capitals with the count set apart, like every
                    // other section header in the app. The glyphs these
                    // headers used to carry — a sunrise, a calendar — turned
                    // to mush at caption size and said nothing the title
                    // didn't already say.
                    CoveSectionHeader(group.name,
                                      count: group.tasks.count,
                                      tint: group.isOverdue ? CoveTheme.alert : nil)
                }
            }
            if !completed.isEmpty {
                Section {
                    ForEach(completed) { task in
                        TaskRow(task: task, now: now,
                                onToggle: { toggle(task) },
                                onDelete: { delete(task) },
                                isProcessing: pendingTaskIDs.contains(task.id))
                    }
                } header: {
                    CoveSectionHeader(title: "Completed", count: completed.count) {
                        Button("Clear All", role: .destructive) {
                            showsClearCompletedConfirmation = true
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2.weight(.semibold))
                        .disabled(isClearingCompleted)
                    }
                }
            }
            if incomplete.isEmpty, completed.isEmpty {
                Section {
                    CoveEmptyState(
                        "Nothing Due",
                        systemName: "checkmark",
                        description: "Capture a task above, or add a due-task line to any note."
                    )
                    .listRowBackground(Color.clear)
                }
            }
        }
        .coveListStyle()
        #if os(iOS)
        .listSectionSpacing(.compact)
        #endif
        .coveReadableWidth()
    }

    private func captureMasthead(openCount: Int) -> some View {
        CoveMasthead(
            eyebrow: "Quick Capture",
            title: "Write it, naturally",
            subtitle: "“Get bread tmr 3pm” becomes a dated task in Tasks.md."
        ) {
            CoveCountBadge("\(openCount) open")
                .accessibilityLabel("\(openCount) open tasks")
        } content: {
            QuickCaptureField(
                placeholder: "e.g. Get bread tomorrow at 3pm",
                accessibilityHint: "Enter a task with an optional date, time, or repeat rule"
            ) { draft in
                try await vaultManager.captureTask(draft)
            }
        }
    }

    /// Removes the task's line from its note. Deliberately not confirmed —
    /// a swipe (or a context-menu pick) is already a deliberate gesture, and
    /// the bulk Clear All is the destructive action worth a dialog.
    private func delete(_ task: TaskItem) {
        guard pendingTaskIDs.insert(task.id).inserted else { return }
        Task {
            defer { pendingTaskIDs.remove(task.id) }
            do {
                let record = try await vaultManager.deleteTask(task)
                undoManager?.registerUndo(withTarget: vaultManager) { manager in
                    Task {
                        do { try await manager.restoreDeletedTask(record) }
                        catch {
                            CoveLog.vault.error("Task undo failed: \(error.localizedDescription, privacy: .private)")
                        }
                    }
                }
                undoManager?.setActionName("Delete Task")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func toggle(_ task: TaskItem) {
        guard pendingTaskIDs.insert(task.id).inserted else { return }
        Task {
            defer { pendingTaskIDs.remove(task.id) }
            do {
                try await vaultManager.toggleTask(task)
                let previousCompletion = task.isCompleted
                undoManager?.registerUndo(withTarget: vaultManager) { manager in
                    Task {
                        do { try await manager.setTaskCompleted(task, to: previousCompletion) }
                        catch {
                            CoveLog.vault.error("Task toggle undo failed: \(error.localizedDescription, privacy: .private)")
                        }
                    }
                }
                undoManager?.setActionName("Toggle Task")
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
