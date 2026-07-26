import AppIntents
import Foundation
import UserNotifications
import WidgetKit

/// Checking a task off from the Home Screen.
///
/// The intent originates from a rendered timeline entry. Shared state may
/// already have advanced, so it carries both the displayed task fingerprint
/// and the displayed control's explicit desired state.
struct ToggleTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description = IntentDescription("Checks a Cove task off from the Today widget.")

    /// The widget's own button, not a Shortcuts action: without a vault path
    /// and a live snapshot it has nothing to act on.
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Task")
    var taskID: String

    /// Optional only so controls persisted by an older Cove build fail safe.
    /// Every control emitted by this build supplies an explicit desired state.
    @Parameter(title: "Completed")
    var desiredCompletion: Bool?

    init() {}

    init(taskID: String, desiredCompletion: Bool) {
        self.taskID = taskID
        self.desiredCompletion = desiredCompletion
    }

    func perform() async throws -> some IntentResult {
        _ = try await TaskToggleWriter().setCompletion(
            taskID: taskID,
            desiredCompletion: desiredCompletion)
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
    private let store: WidgetSnapshotStore
    private let repository: VaultRepository

    init(
        store: WidgetSnapshotStore = WidgetSnapshotStore(),
        repository: VaultRepository = VaultRepository()
    ) {
        self.store = store
        self.repository = repository
    }

    @discardableResult
    func setCompletion(
        taskID: String,
        desiredCompletion: Bool?,
        now: Date = Date()
    ) async throws -> TaskCompletionMutationOutcome {
        // A control saved before explicit desired state existed must never
        // fall back to "toggle whatever is current."
        guard let desiredCompletion else { return .stale }
        let snapshot = try store.readSnapshotResult().get()
        // The semantic ID includes the rendered title/date/repeat identity.
        // If the line was edited or reused since this timeline was rendered,
        // the stale tap is an idempotent no-op.
        guard let task = snapshot.task(matchingWidgetID: taskID) else {
            return .stale
        }
        let proposedOperation = PendingTaskOperation(
            task: task, desiredCompletion: desiredCompletion)

        // Queue first. If the note write succeeds but acknowledgment fails,
        // the retained desired-state operation is safe to apply again.
        let operation = try store.append(proposedOperation)
        let outcome = await apply(operation, now: now)
        if outcome != .deferred {
            // A failure here deliberately leaves the operation queued.
            do {
                try store.acknowledge(operationID: operation.id)
            } catch {
                widgetChannelLogger.error(
                    "Operation acknowledgment failed: \(error.localizedDescription, privacy: .private)")
            }
        }

        // Remove the reminder only after direct or terminal application. A
        // durably deferred operation keeps it until completion is confirmed.
        if desiredCompletion, outcome != .deferred {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [task.notificationIdentifier])
        }

        do {
            _ = try store.applyOptimisticCompletion(
                taskID: taskID,
                desiredCompletion: desiredCompletion,
                operationID: operation.id,
                outcome: outcome,
                at: now)
        } catch WidgetStoreError.taskNotFound {
            // Another tap or an app publication already retired the row.
        }
        return outcome
    }

    /// Rewrites the task's line in its note, through the same parser and the
    /// same coordinated write the app uses. The repository's `changed` result
    /// is paired with a parse of its resulting text so "already in the desired
    /// state" is not confused with "identity no longer exists."
    private func apply(
        _ operation: PendingTaskOperation,
        now: Date
    ) async -> TaskCompletionMutationOutcome {
        guard let vaultURL = resolveVaultURL() else { return .deferred }
        let didStart = vaultURL.startAccessingSecurityScopedResource()
        defer { if didStart { vaultURL.stopAccessingSecurityScopedResource() } }

        guard let noteURL = operation.taskIdentity.fileURL(within: vaultURL) else {
            return .stale
        }

        do {
            let result = try await repository.updateNote(at: noteURL) { text in
                try TaskParser.settingTaskCompletedResult(
                    operation.taskIdentity,
                    to: operation.desiredCompletion,
                    todayDateString: QuickTaskParser.ymdString(from: now),
                    in: text
                ).get()
            }
            if result.changed { return .changed }
            switch TaskParser.matchResult(
                operation.taskIdentity,
                in: result.resultingText)
            {
            case .matched(let matching):
                return matching.isCompleted == operation.desiredCompletion
                    ? .alreadyDesired : .deferred
            case .missing:
                return .stale
            case .ambiguous:
                return .deferred
            }
        } catch VaultFileOperations.OperationError.fileMissing(_) {
            return .stale
        } catch TaskParser.MutationError.taskMissing {
            return .stale
        } catch {
            widgetChannelLogger.error(
                "Direct widget mutation deferred: \(error.localizedDescription, privacy: .private)")
            return .deferred
        }
    }

    private func resolveVaultURL() -> URL? {
        guard let data = store.readBookmark() else { return nil }
        var isStale = false
        do {
            return try URL(
                resolvingBookmarkData: data,
                options: Self.bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale)
        } catch {
            return nil
        }
    }

    /// The extension reads its bookmark from the App Group container, not
    /// from `UserDefaults`, so it needs the resolution flags and nothing else
    /// `VaultBookmarkStore` does. Keeping them local lets the widget target
    /// omit that source entirely.
    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
            [.withSecurityScope]
        #else
            []
        #endif
    }
}
