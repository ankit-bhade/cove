import Foundation

/// One local notification the app intends to schedule for a due task.
struct TaskNotificationPlan: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    /// Local year/month/day/hour/minute the notification fires at.
    let fireDateComponents: DateComponents
}

/// Pure planning half of task notifications: decides which incomplete tasks
/// get a notification and when it fires, without touching
/// `UNUserNotificationCenter`. Fully unit-tested; the scheduling half
/// (`TaskNotificationScheduler`) stays a thin wrapper.
enum TaskNotificationPlanner {
    /// Every app-generated identifier carries this prefix, so a rebuild can
    /// remove exactly the requests the app created and nothing else.
    static let identifierPrefix = "cove-task:"

    /// Local hour of the due day at which a task notification fires.
    static let fireHour = 9

    /// The system keeps at most 64 pending local notifications per app;
    /// stay under it and let the soonest-due tasks win.
    static let maximumPlans = 60

    /// Plans notifications for the incomplete tasks whose fire time
    /// (`fireHour` on the due day) is still in the future, soonest first,
    /// capped at `maximumPlans`. Completed and already-past tasks get none.
    static func plans(for tasks: [TaskItem],
                      now: Date,
                      calendar: Calendar = .current) -> [TaskNotificationPlan] {
        tasks
            .filter { !$0.isCompleted }
            .sorted {
                ($0.dueDateString, $0.fileTitle, $0.lineNumber)
                    < ($1.dueDateString, $1.fileTitle, $1.lineNumber)
            }
            .compactMap { task -> TaskNotificationPlan? in
                let parts = task.dueDateString.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3 else { return nil }
                let components = DateComponents(
                    year: parts[0], month: parts[1], day: parts[2],
                    hour: fireHour, minute: 0)
                guard let fireDate = calendar.date(from: components),
                      fireDate > now else { return nil }
                return TaskNotificationPlan(
                    identifier: identifierPrefix + task.id,
                    title: task.text,
                    body: "Due \(task.dueDateString) · \(task.fileTitle)",
                    fireDateComponents: components)
            }
            .prefix(maximumPlans)
            .map { $0 }
    }
}
