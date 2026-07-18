import Foundation

/// One local notification the app intends to schedule for a due task.
struct TaskNotificationPlan: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    /// Local year/month/day/hour/minute of the one-shot fire moment.
    let fireDateComponents: DateComponents
}

/// Pure planning half of task notifications: decides which tasks get a
/// notification and when it fires, without touching
/// `UNUserNotificationCenter`. Fully unit-tested; the scheduling half
/// (`TaskNotificationScheduler`) stays a thin wrapper.
///
/// Only incomplete tasks with a due *time* are scheduled — a task with a
/// bare date gets no notification. Every plan is a one-shot at the task's
/// due moment, skipped once it has passed. Recurring tasks are not
/// scheduled ahead (mirroring grove-app): completing an occurrence rolls
/// the task's line to the next date, and the rebuild that follows
/// schedules that occurrence's notification.
enum TaskNotificationPlanner {
    /// Every app-generated identifier carries this prefix, so a rebuild can
    /// remove exactly the requests the app created and nothing else.
    static let identifierPrefix = "cove-task:"

    /// The system keeps at most 64 pending local notifications per app;
    /// stay under it and let the soonest-due tasks win.
    static let maximumPlans = 60

    static func plans(for tasks: [TaskItem],
                      now: Date,
                      calendar: Calendar = .current) -> [TaskNotificationPlan] {
        tasks
            .filter { !$0.isCompleted && $0.dueTimeString != nil }
            .sorted(by: VaultIndex.byDueDate)
            .compactMap { task -> TaskNotificationPlan? in
                guard let time = task.timeComponents else { return nil }
                let parts = task.dueDateString.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3 else { return nil }
                let components = DateComponents(
                    year: parts[0], month: parts[1], day: parts[2],
                    hour: time.hour, minute: time.minute)
                guard let fireDate = calendar.date(from: components),
                      fireDate > now else { return nil }
                var body = "Due \(task.dueDateString) \(task.dueTimeString!)"
                if let rule = task.recurrence { body += " · \(rule.displayName)" }
                body += " · \(task.fileTitle)"
                return TaskNotificationPlan(
                    identifier: identifierPrefix + task.id,
                    title: task.text,
                    body: body,
                    fireDateComponents: components)
            }
            .prefix(maximumPlans)
            .map { $0 }
    }
}
