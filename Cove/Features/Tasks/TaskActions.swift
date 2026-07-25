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

    func isProcessing(_ task: TaskItem) -> Bool {
        pendingTaskIDs.contains(task.id)
    }

    /// Toggling a recurring task rolls its due date forward instead of
    /// checking it off, which is `VaultManager`'s business; undo puts the line
    /// back in the completion state the index last saw.
    func toggle(
        _ task: TaskItem,
        in vaultManager: VaultManager,
        undoManager: UndoManager?
    ) {
        perform(task) {
            let record = try await vaultManager.toggleTask(task)
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
            undoManager?.registerUndo(withTarget: vaultManager) { [weak self] manager in
                Task {
                    do {
                        try await manager.restoreDeletedTask(record)
                    } catch {
                        self?.errorMessage = error.localizedDescription
                        CoveLog.vault.error(
                            "Task undo failed: \(error.localizedDescription, privacy: .private)")
                    }
                }
            }
            undoManager?.setActionName("Delete Task")
        }
    }

    /// Each screen clears exactly what it shows, so the sweep itself is the
    /// caller's — this owns only the in-flight flag the header's button reads.
    func clearCompleted(_ operation: @escaping () async throws -> Void) {
        isClearingCompleted = true
        Task {
            defer { isClearingCompleted = false }
            do {
                try await operation()
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

    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ForEach(tasks) { task in
            TaskRow(
                task: task, now: now,
                onToggle: { actions.toggle(task, in: vaultManager, undoManager: undoManager) },
                onDelete: { actions.delete(task, in: vaultManager, undoManager: undoManager) },
                isProcessing: actions.isProcessing(task))
        }
    }
}

/// The header over a screen's completed tasks: its name, its count, and the
/// sweep that empties it. Shared so "Completed" and "Done" differ in wording
/// alone and not in the weight or the state of the button beside them.
struct CompletedTasksHeader: View {
    let title: String
    let count: Int
    let isClearing: Bool
    let clear: () -> Void

    var body: some View {
        CoveSectionHeader(title: title, count: count) {
            Button("Clear All", role: .destructive, action: clear)
                .buttonStyle(.borderless)
                .font(.caption2.weight(.semibold))
                .disabled(isClearing)
        }
    }
}

extension View {
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
