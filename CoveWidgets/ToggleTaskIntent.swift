import AppIntents
import Foundation
import WidgetKit

/// Checking a task off from the Home Screen.
///
/// The intent carries only the row's identity; everything else is looked up in
/// the shared snapshot, which is by definition exactly what the widget was
/// drawing when the tap landed.
struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Checks a Cove task off from the Today widget.")

    /// The widget's own button, not a Shortcuts action: without a vault path
    /// and a live snapshot it has nothing to act on.
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Task")
    var taskID: String

    init() {}

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        TaskToggleWriter().toggle(taskID: taskID)
        WidgetCenter.shared.reloadTimelines(ofKind: CoveSharedContainer.todayWidgetKind)
        return .result()
    }
}

/// Applies a widget-initiated toggle: to the note if it can reach the vault,
/// to the pending queue if it can't, and to the snapshot either way.
///
/// The snapshot update is what makes the tap feel instant — the widget redraws
/// from it before the app has re-indexed anything. It is optimistic, but never
/// a lie about the file: when the direct write fails the toggle is queued, and
/// the app applies it on its next refresh.
struct TaskToggleWriter {
    private let store = WidgetSnapshotStore()

    func toggle(taskID: String, now: Date = Date()) {
        var snapshot = store.readSnapshot()
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = snapshot.tasks[index]

        if !writeToVault(task, now: now) {
            store.appendPendingToggle(PendingToggle(task))
        }

        // Completing a recurring task rolls its line to the next occurrence
        // rather than checking it off, so the row leaves today's list instead
        // of sitting there struck through.
        if task.recurrence != nil, !task.isCompleted {
            snapshot.tasks.remove(at: index)
        } else {
            snapshot.tasks[index] = task.toggled()
        }
        store.writeSnapshot(snapshot)
    }

    /// Rewrites the task's line in its note, through the same parser and the
    /// same coordinated write the app uses. Returns false if the vault can't
    /// be reached or the line no longer matches.
    private func writeToVault(_ task: SnapshotTask, now: Date) -> Bool {
        guard let vaultURL = resolveVaultURL() else { return false }
        let didStart = vaultURL.startAccessingSecurityScopedResource()
        defer { if didStart { vaultURL.stopAccessingSecurityScopedResource() } }

        let operations = VaultFileOperations()
        guard let text = try? operations.readNote(at: task.fileURL),
              let updated = TaskParser.togglingTask(
                withText: task.text,
                dueDateString: task.dueDateString,
                dueTimeString: task.dueTimeString,
                recurrence: task.recurrence,
                isCompleted: task.isCompleted,
                listName: nil,
                preferredLineNumber: task.lineNumber,
                todayDateString: QuickTaskParser.ymdString(from: now),
                in: text)
        else { return false }

        do {
            try operations.saveNote(updated, to: task.fileURL)
            return true
        } catch {
            return false
        }
    }

    private func resolveVaultURL() -> URL? {
        guard let data = store.readBookmark() else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data,
                        options: VaultBookmarkStore.platformResolutionOptions,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale)
    }
}
