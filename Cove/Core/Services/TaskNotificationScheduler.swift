import Foundation
import UserNotifications

/// Schedules local notifications for incomplete due tasks via
/// `UNUserNotificationCenter`. Each rebuild removes every previously
/// app-generated request (recognized by `TaskNotificationPlanner`'s
/// identifier prefix) before scheduling the current plans, so the pending
/// set always mirrors the latest index. Rebuilds are chained so two
/// overlapping calls never interleave their remove/add steps.
actor TaskNotificationScheduler {
    private var pendingRebuild: Task<Void, Never>?

    /// Enqueues a rebuild for the given tasks (the full task list is fine;
    /// completed tasks are planned away). Returns as soon as the rebuild is
    /// queued; the notification-center work runs behind the previous one.
    func rebuildNotifications(for tasks: [TaskItem]) {
        let previous = pendingRebuild
        pendingRebuild = Task {
            await previous?.value
            await Self.performRebuild(for: tasks)
        }
    }

    private static func performRebuild(for tasks: [TaskItem]) async {
        let center = UNUserNotificationCenter.current()
        let plans = TaskNotificationPlanner.plans(for: tasks, now: Date())

        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(TaskNotificationPlanner.identifierPrefix) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        guard !plans.isEmpty, await ensureAuthorization(center) else { return }

        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: plan.fireDateComponents, repeats: false)
            try? await center.add(UNNotificationRequest(
                identifier: plan.identifier, content: content, trigger: trigger))
        }
    }

    /// Prompts the user the first time there is something to schedule; a
    /// denial silently disables scheduling until permission is granted in
    /// the system settings.
    private static func ensureAuthorization(_ center: UNUserNotificationCenter) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
