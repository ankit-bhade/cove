import AppIntents
import Foundation
import WidgetKit

/// Checking a task off from the Home Screen.
///
/// The intent carries only the row's identity; everything else is looked up in
/// the shared snapshot, which is by definition exactly what the widget was
/// drawing when the tap landed.
struct ToggleTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description = IntentDescription("Checks a Cove task off from the Today widget.")

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
        try await TaskToggleWriter().setCompletion(taskID: taskID)
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
    private let repository = VaultRepository()

    func setCompletion(taskID: String, now: Date = Date()) async throws {
        var snapshot = store.readSnapshot()
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = snapshot.tasks[index]
        let desiredCompletion = !task.isCompleted
        let operation = PendingTaskOperation(
            task: task,
            desiredCompletion: desiredCompletion)

        // Queue first. If the note write succeeds but acknowledgment fails,
        // the retained desired-state operation is safe to apply again.
        try store.append(operation)
        if await apply(operation, now: now) {
            // A failure here deliberately leaves the operation queued.
            do {
                try store.acknowledge(operationID: operation.id)
            } catch {
                widgetChannelLogger.error(
                    "Operation acknowledgment failed: \(error.localizedDescription, privacy: .private)")
            }
        }

        // Completing a recurring task rolls its line to the next occurrence
        // rather than checking it off, so the row leaves today's list instead
        // of sitting there struck through.
        if task.recurrence != nil, desiredCompletion {
            snapshot.tasks.remove(at: index)
        } else {
            snapshot.tasks[index] = task.settingCompleted(desiredCompletion)
        }
        store.writeSnapshot(snapshot)
    }

    /// Rewrites the task's line in its note, through the same parser and the
    /// same coordinated write the app uses. Returns false if the vault can't
    /// be reached or the line no longer matches.
    private func apply(_ operation: PendingTaskOperation, now: Date) async -> Bool {
        guard let vaultURL = resolveVaultURL() else { return false }
        let didStart = vaultURL.startAccessingSecurityScopedResource()
        defer { if didStart { vaultURL.stopAccessingSecurityScopedResource() } }

        // A snapshot path that doesn't resolve inside the vault this process
        // just opened is not a target to retry — it's one to drop.
        guard let noteURL = operation.taskIdentity.fileURL(within: vaultURL) else {
            return true
        }

        do {
            _ = try await repository.updateNote(at: noteURL) { text in
                TaskParser.settingTaskCompleted(
                    operation.taskIdentity,
                    to: operation.desiredCompletion,
                    todayDateString: QuickTaskParser.ymdString(from: now),
                    in: text)
            }
            return true
        } catch VaultFileOperations.OperationError.fileMissing(_) {
            // The note (and therefore the task) is definitively gone.
            return true
        } catch {
            return false
        }
    }

    private func resolveVaultURL() -> URL? {
        guard let data = store.readBookmark() else { return nil }
        var isStale = false
        do {
            return try URL(
                resolvingBookmarkData: data,
                options: VaultBookmarkStore.platformResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale)
        } catch {
            return nil
        }
    }
}
