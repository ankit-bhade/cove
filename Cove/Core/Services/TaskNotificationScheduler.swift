import Foundation
import OSLog
import UserNotifications

/// Schedules local notifications for incomplete due tasks via
/// `UNUserNotificationCenter`. Each rebuild compares existing Cove-owned
/// requests against the desired plans and changes only the requests that
/// differ. Rebuilds are chained so two
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
        guard await isAuthorized(center) else { return }

        let existing = await center.pendingNotificationRequests().filter {
            $0.identifier.hasPrefix(TaskNotificationPlanner.identifierPrefix)
        }
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.identifier, $0) })
        let desiredIDs = Set(plans.map(\.identifier))
        var removals = existing.map(\.identifier).filter { !desiredIDs.contains($0) }
        var additions: [TaskNotificationPlan] = []
        for plan in plans {
            if let request = existingByID[plan.identifier], request.matches(plan) {
                continue
            }
            if existingByID[plan.identifier] != nil { removals.append(plan.identifier) }
            additions.append(plan)
        }
        if !removals.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(Set(removals)))
        }

        for plan in additions {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: plan.fireDateComponents, repeats: false)
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: plan.identifier, content: content, trigger: trigger))
            } catch {
                CoveLog.notifications.error("Scheduling failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        CoveLog.notifications.info(
            "Notification diff removed \(removals.count, privacy: .public) and added \(additions.count, privacy: .public)"
        )
    }

    /// Scheduling never owns the permission prompt. Settings is the only
    /// place allowed to ask.
    private static func isAuthorized(_ center: UNUserNotificationCenter) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }
}

private extension UNNotificationRequest {
    func matches(_ plan: TaskNotificationPlan) -> Bool {
        guard content.title == plan.title,
            content.body == plan.body,
            let trigger = trigger as? UNCalendarNotificationTrigger
        else { return false }
        return trigger.dateComponents == plan.fireDateComponents && !trigger.repeats
    }
}
