import SwiftUI

/// All due tasks collected by the in-memory index: incomplete tasks sorted
/// by due date, completed ones below, with a quick-entry field on top that
/// understands sentences like "get bread 3p tmr". Toggling a checkbox
/// rewrites the line in the task's original Markdown file (a recurring task
/// rolls forward to its next occurrence); tapping the row opens the note.
struct TasksView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var errorMessage: String?
    @State private var isClearingCompleted = false
    @State private var showsClearCompletedConfirmation = false
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
                quickCaptureCard(openCount: incomplete.count)
                    .listRowInsets(CoveTheme.dashboardRowInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(TaskGroup.grouping(incomplete, now: now)) { group in
                Section {
                    ForEach(group.tasks) { task in
                        TaskRow(task: task, now: now,
                                onToggle: { toggle(task) },
                                onDelete: { delete(task) })
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
                        TaskRow(task: task, now: now,
                                onToggle: { toggle(task) },
                                onDelete: { delete(task) })
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
        #if os(iOS)
        .listSectionSpacing(.compact)
        #endif
        .coveReadableWidth()
    }

    private func quickCaptureCard(openCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quick Capture")
                        .font(.headline)
                    openTaskCount(openCount)
                }
            } else {
                HStack {
                    Text("Quick Capture")
                        .font(.headline)
                    Spacer()
                    openTaskCount(openCount)
                }
            }

            QuickCaptureField(
                placeholder: "e.g. Get bread tomorrow at 3pm",
                accessibilityHint: "Enter a task with an optional date, time, or repeat rule"
            ) { draft in
                capture(draft)
            }
        }
        .padding(14)
        .background { CoveCardBackground() }
    }

    private func openTaskCount(_ count: Int) -> some View {
        Label("\(count) open", systemImage: "circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CoveTheme.teal)
    }

    /// Writes the interpreted task straight to the capture note. There is no
    /// confirmation step: the field showed the interpretation while it was
    /// being typed, and the new row appearing is the receipt.
    private func capture(_ draft: TaskDraft) {
        Task {
            do {
                try await vaultManager.captureTask(draft)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
