import Foundation
import OSLog
import UserNotifications

enum TaskNotificationPermission: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
    case unknown

    var permitsScheduling: Bool {
        self == .authorized
    }
}

struct TaskNotificationSchedulingFailure: Equatable, Sendable {
    enum Operation: String, Equatable, Sendable {
        case add
        case inspect
    }

    let operation: Operation
    /// Deliberately generic. The underlying system error is logged privately;
    /// health/UI never retain a vault path or task title.
    let description: String
}

/// The observable result of one requested reconciliation.
struct TaskNotificationHealth: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case reconciled
        case permissionNotDetermined
        case permissionDenied
        case permissionUnknown
        case superseded
        case failed
        case cancelledAll
    }

    let state: State
    let checkedAt: Date
    let desiredCount: Int
    let pendingCount: Int
    let omittedBySystemLimit: Int
    let invalidDateCount: Int
    let addedCount: Int
    let removedCount: Int
    let unchangedCount: Int
    let failures: [TaskNotificationSchedulingFailure]

    var isHealthy: Bool {
        state == .reconciled && failures.isEmpty
    }

    static func superseded(at date: Date = Date()) -> Self {
        Self(
            state: .superseded,
            checkedAt: date,
            desiredCount: 0,
            pendingCount: 0,
            omittedBySystemLimit: 0,
            invalidDateCount: 0,
            addedCount: 0,
            removedCount: 0,
            unchangedCount: 0,
            failures: [])
    }
}

/// Small seam around `UNUserNotificationCenter`, both to keep the actor
/// deterministic and to exercise the actual diff/latest-wins behavior in
/// unit tests without prompting for notification permission.
struct TaskNotificationPendingRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let dateComponents: DateComponents?
    let repeats: Bool

    func matches(_ plan: TaskNotificationPlan) -> Bool {
        title == plan.title
            && body == plan.body
            && dateComponents == plan.fireDateComponents
            && !repeats
    }
}

protocol TaskNotificationCenter: Sendable {
    func permission() async -> TaskNotificationPermission
    func pendingRequests() async -> [TaskNotificationPendingRequest]
    func add(_ plan: TaskNotificationPlan) async throws
    func removePendingRequests(withIdentifiers identifiers: [String]) async
}

struct SystemTaskNotificationCenter: TaskNotificationCenter {
    /// Avoid retaining the framework's non-Sendable singleton in this
    /// Sendable adapter; each method obtains the same documented singleton.
    private var center: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }

    func permission() async -> TaskNotificationPermission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .unknown
        }
    }

    func pendingRequests() async -> [TaskNotificationPendingRequest] {
        await center.pendingNotificationRequests().map { request in
            let trigger = request.trigger as? UNCalendarNotificationTrigger
            return TaskNotificationPendingRequest(
                identifier: request.identifier,
                title: request.content.title,
                body: request.content.body,
                dateComponents: trigger?.dateComponents,
                repeats: trigger?.repeats ?? false)
        }
    }

    func add(_ plan: TaskNotificationPlan) async throws {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: plan.fireDateComponents,
            repeats: false)
        try await center.add(
            UNNotificationRequest(
                identifier: plan.identifier,
                content: content,
                trigger: trigger))
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Schedules local notifications for incomplete due tasks.
///
/// A call is now awaitable all the way through the notification-center diff.
/// When a newer rebuild arrives, the older work is cancelled and allowed to
/// unwind before the newer diff runs. Even if cancellation lands between a
/// remove and an add, awaiting the newest call guarantees that its full
/// desired state is the last reconciliation applied.
actor TaskNotificationScheduler {
    private let center: any TaskNotificationCenter
    private var activeReconciliation: Task<TaskNotificationHealth, Never>?

    init(center: any TaskNotificationCenter = SystemTaskNotificationCenter()) {
        self.center = center
    }

    /// Reconciles Cove-owned requests to the latest task list. Older queued or
    /// in-flight calls return `.superseded`; the newest caller returns only
    /// after its notification-center work has completed.
    @discardableResult
    func rebuildNotifications(
        for tasks: [TaskItem],
        now: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) async -> TaskNotificationHealth {
        let previous = activeReconciliation
        previous?.cancel()
        let center = self.center
        let task = Task {
            _ = await previous?.value
            guard !Task.isCancelled else {
                return TaskNotificationHealth.superseded()
            }
            return await Self.performRebuild(
                for: tasks,
                now: now,
                timeZone: timeZone,
                center: center)
        }
        activeReconciliation = task
        return await task.value
    }

    /// Cancels every Cove-owned task reminder without touching notifications
    /// created by another feature or app. Like rebuild, this supersedes and
    /// waits for older work before returning.
    @discardableResult
    func cancelAllNotifications() async -> TaskNotificationHealth {
        let previous = activeReconciliation
        previous?.cancel()
        let center = self.center
        let task = Task {
            _ = await previous?.value
            guard !Task.isCancelled else {
                return TaskNotificationHealth.superseded()
            }
            let existing = await center.pendingRequests().filter {
                $0.identifier.hasPrefix(TaskNotificationPlanner.identifierPrefix)
            }
            guard !Task.isCancelled else {
                return TaskNotificationHealth.superseded()
            }
            await center.removePendingRequests(
                withIdentifiers: existing.map(\.identifier))
            return TaskNotificationHealth(
                state: .cancelledAll,
                checkedAt: Date(),
                desiredCount: 0,
                pendingCount: 0,
                omittedBySystemLimit: 0,
                invalidDateCount: 0,
                addedCount: 0,
                removedCount: existing.count,
                unchangedCount: 0,
                failures: [])
        }
        activeReconciliation = task
        return await task.value
    }

    private static func performRebuild(
        for tasks: [TaskItem],
        now: Date,
        timeZone: TimeZone,
        center: any TaskNotificationCenter
    ) async -> TaskNotificationHealth {
        let inventory = TaskNotificationPlanner.inventory(
            for: tasks,
            now: now,
            timeZone: timeZone)
        let permission = await center.permission()
        guard !Task.isCancelled else { return .superseded() }
        let existing = await center.pendingRequests().filter {
            $0.identifier.hasPrefix(TaskNotificationPlanner.identifierPrefix)
        }
        guard !Task.isCancelled else { return .superseded() }
        guard permission.permitsScheduling else {
            // Permission checks never prompt. Removing stale Cove-owned
            // requests is safe even while permission is denied or undecided,
            // and prevents an old completed/edited task from surviving a
            // later system-settings authorization change.
            if !existing.isEmpty {
                await center.removePendingRequests(
                    withIdentifiers: existing.map(\.identifier))
            }
            let state: TaskNotificationHealth.State
            switch permission {
            case .notDetermined:
                state = .permissionNotDetermined
            case .denied:
                state = .permissionDenied
            case .unknown:
                state = .permissionUnknown
            case .authorized:
                state = .reconciled
            }
            return TaskNotificationHealth(
                state: state,
                checkedAt: Date(),
                desiredCount: inventory.plans.count,
                pendingCount: 0,
                omittedBySystemLimit: inventory.omittedBySystemLimit,
                invalidDateCount: inventory.invalidDateCount,
                addedCount: 0,
                removedCount: existing.count,
                unchangedCount: 0,
                failures: [])
        }
        let existingByID = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.identifier, $0) })
        let desiredIDs = Set(inventory.plans.map(\.identifier))
        var removals = existing.map(\.identifier).filter {
            !desiredIDs.contains($0)
        }
        var additions: [TaskNotificationPlan] = []
        var unchangedCount = 0
        for plan in inventory.plans {
            if let request = existingByID[plan.identifier], request.matches(plan) {
                unchangedCount += 1
                continue
            }
            if existingByID[plan.identifier] != nil {
                removals.append(plan.identifier)
            }
            additions.append(plan)
        }

        let uniqueRemovals = Array(Set(removals))
        if !uniqueRemovals.isEmpty {
            await center.removePendingRequests(withIdentifiers: uniqueRemovals)
        }
        guard !Task.isCancelled else { return .superseded() }

        var addedCount = 0
        var failures: [TaskNotificationSchedulingFailure] = []
        for plan in additions {
            guard !Task.isCancelled else { return .superseded() }
            do {
                try await center.add(plan)
                addedCount += 1
            } catch is CancellationError {
                return .superseded()
            } catch {
                failures.append(
                    TaskNotificationSchedulingFailure(
                        operation: .add,
                        description: "A reminder could not be scheduled."))
                CoveLog.notifications.error(
                    "Scheduling failed: \(error.localizedDescription, privacy: .private)")
            }
        }

        let pendingCount = unchangedCount + addedCount
        let health = TaskNotificationHealth(
            state: failures.isEmpty ? .reconciled : .failed,
            checkedAt: Date(),
            desiredCount: inventory.plans.count,
            pendingCount: pendingCount,
            omittedBySystemLimit: inventory.omittedBySystemLimit,
            invalidDateCount: inventory.invalidDateCount,
            addedCount: addedCount,
            removedCount: uniqueRemovals.count,
            unchangedCount: unchangedCount,
            failures: failures)
        CoveLog.notifications.info(
            "Notification reconciliation removed \(health.removedCount), added \(health.addedCount), retained \(health.unchangedCount), omitted \(health.omittedBySystemLimit)"
        )
        return health
    }
}
