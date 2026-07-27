import SwiftUI

/// All due tasks collected by the in-memory index: incomplete tasks sorted
/// by due date, completed ones below, with a quick-entry field on top that
/// understands sentences like "get bread 3p tmr". Toggling a checkbox
/// rewrites the line in the task's original Markdown file (a recurring task
/// rolls forward to its next occurrence); tapping the row opens the note.
struct TasksView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.undoManager) private var undoManager
    @State private var actions = TaskActions()
    @State private var showsClearCompletedConfirmation = false
    /// Upcoming folds but arrives open — what's further out is still work
    /// that's coming. Completed is the one section that starts closed: it is
    /// finished by definition. See `TaskGroup.isCollapsible`.
    @State private var isUpcomingExpanded = true
    @State private var isCompletedExpanded = false
    /// Ticks each minute so "Overdue" and "Today" stay accurate while the
    /// tab sits open across a due moment or across midnight.
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Tasks")
                .navigationDestination(for: NoteDestination.self) { destination in
                    EditorView(destination)
                }
                .toolbar {
                    ToolbarItem {
                        CoveRefreshButton {
                            await vaultManager.refresh()
                        }
                    }
                }
                .coveErrorAlert($actions.errorMessage)
                .confirmationDialog(
                    "Clear All Completed Tasks?",
                    isPresented: $showsClearCompletedConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear All", role: .destructive) {
                        actions.clearCompleted(
                            in: vaultManager,
                            undoManager: undoManager
                        ) {
                            try await vaultManager.clearCompletedTasks()
                        }
                    }
                } message: {
                    Text("This removes every completed task line shown here from its Markdown note, including dated items from your lists. You can undo the clear.")
                }
                // No refresh on appearance. It was here because editor
                // autosaves did not reach the index — they do now, through
                // `noteDidPersist`, which re-reads the one note that changed
                // instead of re-enumerating the vault. Between that, the
                // iCloud observer, and the rescan when the scene activates,
                // a full scan on every visit to this tab was the same answer
                // arrived at the expensive way. The toolbar's refresh is the
                // manual path for a vault the observer cannot see.
                .coveMinuteTick($now)
        }
    }

    private var list: some View {
        let incomplete = vaultManager.index.incompleteTasks
        let completed = vaultManager.index.completedTasks
        let groups = TaskGroup.grouping(incomplete, now: now)
        return List {
            Section {
                captureMasthead(openCount: incomplete.count)
                    .listRowInsets(CoveTheme.headerRowInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            // Overdue, Today, Tomorrow, Upcoming, and Completed are one list
            // partitioned five ways, not five lists — so they take one surface
            // with the headings set inside it. As five inset-grouped sections
            // they were five rounded cards stacked inside iOS's own rounded
            // chrome, and the gap between each pair cost roughly a task of what
            // fit above the fold on the screen the app opens on. The capture
            // panel keeps its own elevation: it is a different kind of thing.
            if !groups.isEmpty || !completed.isEmpty {
                Section {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { position, group in
                        header(for: group)
                            .coveGroupHeaderRow(
                                isFirst: position == 0,
                                // Upcoming is the last group and the only one
                                // that folds, so folded away with nothing
                                // completed below it, its heading is the last
                                // row on the surface.
                                isLast: !isShowing(group)
                                    && position == groups.count - 1
                                    && completed.isEmpty)
                        if isShowing(group) {
                            TaskRows(
                                tasks: group.tasks, now: now, actions: actions,
                                showsListNames: true)
                        }
                    }
                    if !completed.isEmpty {
                        CompletedTasksHeader(
                            title: "Completed",
                            count: completed.count,
                            isExpanded: $isCompletedExpanded
                        )
                        .coveGroupHeaderRow(
                            isFirst: groups.isEmpty, isLast: !isCompletedExpanded)
                        if isCompletedExpanded {
                            TaskRows(
                                tasks: completed, now: now, actions: actions,
                                showsListNames: true)
                            ClearCompletedTasksRow(
                                isClearing: actions.isClearingCompleted
                            ) {
                                showsClearCompletedConfirmation = true
                            }
                        }
                    }
                }
            } else {
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
        .coveReadableWidth()
    }

    /// Tracked capitals with the count set apart, like every other section
    /// header in the app. The glyphs these headers used to carry — a sunrise,
    /// a calendar — turned to mush at caption size and said nothing the title
    /// didn't already say.
    ///
    /// A collapsible group hands its expansion state to the header, which
    /// becomes the control that folds the section away.
    private func header(for group: TaskGroup) -> some View {
        CoveSectionHeader(
            group.name,
            count: group.tasks.count,
            tint: group.isOverdue ? CoveTheme.alert : nil,
            isExpanded: group.isCollapsible ? $isUpcomingExpanded : nil)
    }

    private func isShowing(_ group: TaskGroup) -> Bool {
        !group.isCollapsible || isUpcomingExpanded
    }

    /// Compact on purpose: this is the screen the app opens on, and a hero
    /// card with a slogan and a syntax hint spent the top third of it on copy
    /// that is read once. The field, the open count, and the first overdue
    /// task now all land above the fold.
    private func captureMasthead(openCount: Int) -> some View {
        CovePanel(eyebrow: "Quick Capture") {
            CoveCountBadge("\(openCount) open")
                .accessibilityLabel("\(openCount) open tasks")
        } content: {
            QuickCaptureField(
                placeholder: "e.g. Get bread tomorrow at 3pm",
                accessibilityHint: "Enter a task with an optional date, time, or repeat rule",
                bindsFocusShortcut: true
            ) { draft in
                try await actions.capture(
                    in: vaultManager, undoManager: undoManager
                ) {
                    try await vaultManager.captureTask(draft)
                }
            }
        }
    }

}
