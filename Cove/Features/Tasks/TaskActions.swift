import Foundation
import Observation
import OSLog
import SwiftUI

/// The gestures both task screens offer: check a task off, swipe it away, and
/// sweep the completed ones. The Tasks tab and a list's detail view show
/// different sections of different tasks, but a checkbox means the same thing
/// in both — so the behaviour behind it, the in-flight bookkeeping, and the
/// names those actions take in the Edit menu live here rather than being
/// written out twice.
///
/// They were written out twice, and they had already drifted: the same
/// checkbox registered its undo as "Toggle Task" on one screen and "Toggle
/// Checkbox" on the other. One copy is what keeps that from happening again.
@MainActor
@Observable
final class TaskActions {
    /// Rows with a write in flight. A second tap on the same row is dropped
    /// rather than queued — the first one is already rewriting that line.
    private(set) var pendingTaskIDs: Set<String> = []
    private(set) var isClearingCompleted = false
    var errorMessage: String?
    /// The task whose edit sheet is open. Tapping a row opens it; the note
    /// itself is one menu item away.
    var editingTask: TaskItem?
    /// A note push a row has asked for. The screen owning the navigation
    /// stack consumes it, since a sheet and a swipe action cannot push.
    var pendingNoteDestination: NoteDestination?
    /// What the last destructive action was, while an Undo of it is still one
    /// tap away.
    private(set) var undoNotice: UndoNotice?
    private var undoNoticeDismissal: Task<Void, Never>?

    /// One line of "this happened, and it doesn't have to have".
    ///
    /// Every destructive task action registers a real Undo, and on a Mac the
    /// Edit menu and ⌘Z say so. On a phone the only route to it is a shake,
    /// which nothing on screen advertises and few people use — so a swipe that
    /// removed the wrong line read as final when it never was.
    ///
    /// The notice carries the reversal itself rather than calling
    /// `UndoManager.undo()`, because outside a `DocumentGroup` SwiftUI's
    /// `\.undoManager` is **nil on iOS** — so a bar that only drove the
    /// manager would have been a button that does nothing on the one platform
    /// it exists for. It still prefers the manager when there is one, so a Mac
    /// keeps a single undo stack and the Edit menu stays in step.
    struct UndoNotice: Identifiable {
        let id = UUID()
        let message: String
        let undo: () -> Void
    }

    /// How long a notice stays up. Long enough to read a short sentence and
    /// reach for it, short enough that it is gone before it becomes furniture.
    static let undoNoticeDuration: Duration = .seconds(6)

    func isProcessing(_ task: TaskItem) -> Bool {
        pendingTaskIDs.contains(task.id)
    }

    private func announceUndo(_ message: String, undo: @escaping () -> Void) {
        undoNoticeDismissal?.cancel()
        undoNotice = UndoNotice(message: message, undo: undo)
        undoNoticeDismissal = Task { [weak self] in
            try? await Task.sleep(for: Self.undoNoticeDuration)
            guard !Task.isCancelled else { return }
            self?.undoNotice = nil
        }
    }

    /// Registers one reversal everywhere it can be reached from: the platform
    /// undo stack, and the bar that says it is there.
    private func registerUndo(
        named name: String,
        announcing message: String,
        in vaultManager: VaultManager,
        undoManager: UndoManager?,
        _ operation: @escaping (VaultManager) async throws -> Void
    ) {
        let reverse: () -> Void = { [weak self] in
            Task {
                do {
                    try await operation(vaultManager)
                } catch {
                    self?.errorMessage = error.localizedDescription
                    CoveLog.vault.error(
                        "\(name, privacy: .public) undo failed: \(error.localizedDescription, privacy: .private)"
                    )
                }
            }
        }
        undoManager?.registerUndo(withTarget: vaultManager) { _ in reverse() }
        undoManager?.setActionName(name)
        announceUndo(message) { [weak undoManager] in
            // The manager owns the stack when there is one, so going through
            // it keeps the Edit menu and this bar from undoing twice.
            if let undoManager, undoManager.canUndo {
                undoManager.undo()
            } else {
                reverse()
            }
        }
    }

    func dismissUndoNotice() {
        undoNoticeDismissal?.cancel()
        undoNoticeDismissal = nil
        undoNotice = nil
    }

    /// Toggling a recurring task rolls its due date forward instead of
    /// checking it off, which is `VaultManager`'s business; undo puts the line
    /// back in the completion state the index last saw.
    ///
    /// A tap on a row whose line is already in that state writes nothing, and
    /// registers nothing: the state it would put back is another device's
    /// change rather than this tap's.
    func toggle(
        _ task: TaskItem,
        in vaultManager: VaultManager,
        undoManager: UndoManager?
    ) {
        perform(task) {
            guard let record = try await vaultManager.toggleTask(task) else {
                return
            }
            undoManager?.registerUndo(withTarget: vaultManager) { [weak self] manager in
                Task {
                    do {
                        try await manager.undoTaskToggle(record)
                    } catch {
                        self?.errorMessage = error.localizedDescription
                        CoveLog.vault.error(
                            "Task toggle undo failed: \(error.localizedDescription, privacy: .private)"
                        )
                    }
                }
            }
            undoManager?.setActionName("Toggle Task")
        }
    }

    /// Removes the task's line from its note. Deliberately not confirmed — a
    /// swipe (or a context-menu pick) is already a deliberate gesture, and the
    /// bulk Clear All is the destructive action worth a dialog.
    func delete(
        _ task: TaskItem,
        in vaultManager: VaultManager,
        undoManager: UndoManager?
    ) {
        perform(task) {
            let record = try await vaultManager.deleteTask(task)
            self.registerUndo(
                named: "Delete Task",
                announcing: "Task deleted.",
                in: vaultManager,
                undoManager: undoManager
            ) { manager in
                try await manager.restoreDeletedTask(record)
            }
        }
    }

    /// Rewrites one task's title and schedule from the edit sheet.
    ///
    /// Throwing rather than reporting: the sheet stays open on a failure with
    /// the edit still in its fields, which is the only place the typed values
    /// exist. A refused write — an ambiguous line, or one that changed
    /// meanwhile — is exactly the case where losing them would hurt most.
    func update(
        _ task: TaskItem,
        to draft: TaskDraft,
        in vaultManager: VaultManager,
        undoManager: UndoManager?
    ) async throws {
        guard let record = try await vaultManager.updateTask(task, to: draft) else {
            return
        }
        undoManager?.registerUndo(withTarget: vaultManager) { [weak self] manager in
            Task {
                do {
                    try await manager.undoTaskEdit(record)
                } catch {
                    self?.errorMessage = error.localizedDescription
                    CoveLog.vault.error(
                        "Task edit undo failed: \(error.localizedDescription, privacy: .private)"
                    )
                }
            }
        }
        undoManager?.setActionName("Edit Task")
    }

    /// Asks the screen that owns the navigation stack to push a task's note,
    /// at the task's own line.
    func openNote(for task: TaskItem) {
        pendingNoteDestination = NoteDestination(task.fileURL, line: task.lineNumber)
    }

    /// Writes one captured task and registers taking it back.
    ///
    /// Capture was the one mutating task action with no Undo: return in the
    /// quick-entry field put a line in the note with nothing but the live
    /// preview between a mis-parsed sentence and the file. Every other action
    /// on these screens is undoable, so this one is too — and it goes through
    /// `TaskActions` for the same reason the rest do, so the Tasks screen and
    /// a list cannot word or handle it differently.
    ///
    /// The capture itself is the caller's closure, because *where* a task
    /// lands is the one thing the two screens genuinely disagree about.
    func capture(
        in vaultManager: VaultManager,
        undoManager: UndoManager?,
        _ operation: @escaping () async throws -> VaultManager.CapturedTaskRecord?
    ) async throws {
        guard let record = try await operation() else { return }
        undoManager?.registerUndo(withTarget: vaultManager) { [weak self] manager in
            Task {
                do {
                    try await manager.undoCapturedTask(record)
                } catch {
                    self?.errorMessage = error.localizedDescription
                    CoveLog.vault.error(
                        "Capture undo failed: \(error.localizedDescription, privacy: .private)"
                    )
                }
            }
        }
        undoManager?.setActionName("Add Task")
    }

    /// Each screen clears exactly what it shows. The manager returns the
    /// semantic deletion records as one Undo group; restoring them later
    /// inserts only those lines into the newest note contents.
    func clearCompleted(
        in vaultManager: VaultManager,
        undoManager: UndoManager?,
        _ operation: @escaping () async throws -> [DeletedTaskRecord]
    ) {
        isClearingCompleted = true
        Task {
            defer { isClearingCompleted = false }
            do {
                let records = try await operation()
                guard !records.isEmpty else { return }
                registerUndo(
                    named: "Clear Completed Tasks",
                    announcing:
                        "\(records.count) completed task\(records.count == 1 ? "" : "s") cleared.",
                    in: vaultManager,
                    undoManager: undoManager
                ) { manager in
                    try await manager.restoreDeletedTasks(records)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func perform(_ task: TaskItem, _ operation: @escaping () async throws -> Void) {
        guard pendingTaskIDs.insert(task.id).inserted else { return }
        Task {
            defer { pendingTaskIDs.remove(task.id) }
            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// One run of task rows, wired to the shared actions. Both task screens build
/// their sections from this, so a row in a list and a row on the Tasks tab
/// cannot drift apart in what a tap does — only in which tasks are handed in.
struct TaskRows: View {
    let tasks: [TaskItem]
    let now: Date
    let actions: TaskActions
    /// Passed through to every row: the Tasks screen names a task's list,
    /// a list's own detail view does not.
    var showsListNames = false

    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ForEach(tasks) { task in
            TaskRow(
                task: task, now: now,
                onToggle: { actions.toggle(task, in: vaultManager, undoManager: undoManager) },
                onDelete: { actions.delete(task, in: vaultManager, undoManager: undoManager) },
                onSelect: { actions.editingTask = task },
                onOpenInNote: { actions.openNote(for: task) },
                isProcessing: actions.isProcessing(task),
                showsListName: showsListNames)
        }
    }
}

/// The header over a screen's completed tasks: its name, its count, and the
/// chevron that folds it away. Shared so "Completed" and "Done" differ in
/// wording alone and not in whether they fold or how.
///
/// Completed work is the one section on either screen that is finished by
/// definition, so like Upcoming it arrives closed.
struct CompletedTasksHeader: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        CoveSectionHeader(title, count: count, isExpanded: $isExpanded)
    }
}

/// The sweep that empties a completed section, as that section's last row.
///
/// It was a caption-sized text button in the header, which put a destructive
/// action a few points from the chevron that folds the section — two controls
/// of different consequence sharing one corner, the smaller of them red. As a
/// row it takes the same grid every other row uses, gets a full-height target
/// instead of a caption's, and is only reachable with the section open, so the
/// tasks it would remove are on screen when it is pressed.
struct ClearCompletedTasksRow: View {
    let isClearing: Bool
    let clear: () -> Void

    var body: some View {
        Button(role: .destructive, action: clear) {
            // The tile takes the role's own red rather than the palette's
            // rust. Destructive controls keeping the system red is a decision
            // this app already made — but a rust tile beside role-red text
            // puts the near-miss inside a single row, where it reads as a
            // mistake rather than as two components a screen apart.
            CoveRow(systemName: "trash.fill", tint: .red) {
                Text("Clear All Completed")
                    .font(.body.weight(.medium))
                Spacer(minLength: 0)
                if isClearing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
        }
        .disabled(isClearing)
    }
}

/// Everything a screen of task rows owes those rows: the details sheet a tap
/// opens, the note push a menu item asks for, and the Undo bar a destructive
/// action leaves behind.
///
/// One modifier for the same reason `TaskRows` is one view — the Tasks tab and
/// a list's detail view differ in which tasks they hand over and in nothing
/// else, and three separate pieces of plumbing written twice is three chances
/// for them to disagree.
private struct TaskScreenModifier: ViewModifier {
    @Bindable var actions: TaskActions
    /// How this screen pushes a note. The sheet and the swipe action can't:
    /// only the view owning the navigation stack knows its path.
    let openNote: (NoteDestination) -> Void

    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.editingTask) { task in
                TaskEditSheet(task: task) { draft in
                    try await actions.update(
                        task, to: draft,
                        in: vaultManager, undoManager: undoManager)
                } onOpenInNote: {
                    actions.openNote(for: task)
                }
            }
            .onChange(of: actions.pendingNoteDestination) { _, destination in
                guard let destination else { return }
                actions.pendingNoteDestination = nil
                actions.editingTask = nil
                openNote(destination)
            }
            // Under the navigation bar, not over the tab bar. The bottom is
            // where a toast is conventionally put and it is the one edge this
            // app cannot use: iOS 26's tab bar floats *over* scrolling
            // content and contributes no safe-area inset, so a bar placed
            // against the bottom edge came out underneath it — legible only
            // as a sliver of card behind the tab labels. Above the content it
            // is unobstructed, it stacks predictably under the storage banner
            // that already reports from the top, and it needs no guess at how
            // tall the platform's chrome happens to be this year.
            .safeAreaInset(edge: .top, spacing: 0) {
                if let notice = actions.undoNotice {
                    CoveUndoBar(message: notice.message) {
                        notice.undo()
                        actions.dismissUndoNotice()
                    } dismiss: {
                        actions.dismissUndoNotice()
                    }
                    .padding(.horizontal, CoveTheme.Space.regular)
                    .padding(.bottom, CoveTheme.Space.tight)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: actions.undoNotice?.id)
    }
}

extension View {
    func coveTaskScreen(
        _ actions: TaskActions,
        openNote: @escaping (NoteDestination) -> Void
    ) -> some View {
        modifier(TaskScreenModifier(actions: actions, openNote: openNote))
    }

    /// Re-evaluates once a minute, so a view showing relative time — "Today",
    /// "Overdue" — stays true while it sits open across a due moment or across
    /// midnight.
    func coveMinuteTick(_ now: Binding<Date>) -> some View {
        task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now.wrappedValue = Date()
            }
        }
    }
}
