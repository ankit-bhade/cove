import Foundation

/// One local notification the app intends to schedule for a due task.
struct TaskNotificationPlan: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    /// For one-shot plans: local year/month/day/hour/minute. For repeating
    /// plans: the recurring components (hour/minute, plus weekday for
    /// weekly rules).
    let fireDateComponents: DateComponents
    /// True for recurring tasks, whose trigger repeats.
    let repeats: Bool
}

/// Pure planning half of task notifications: decides which tasks get a
/// notification and when it fires, without touching
/// `UNUserNotificationCenter`. Fully unit-tested; the scheduling half
/// (`TaskNotificationScheduler`) stays a thin wrapper.
///
/// Only incomplete tasks with a due *time* are scheduled — a task with a
/// bare date gets no notification. Non-recurring tasks get one notification
/// at their due moment (skipped once it has passed); recurring tasks get
/// repeating notifications at their time on every occurrence.
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
            .flatMap { plans(for: $0, now: now, calendar: calendar) }
            .prefix(maximumPlans)
            .map { $0 }
    }

    private static func plans(for task: TaskItem,
                              now: Date,
                              calendar: Calendar) -> [TaskNotificationPlan] {
        guard let time = task.timeComponents else { return [] }
        let identifier = identifierPrefix + task.id

        switch task.recurrence {
        case nil:
            let parts = task.dueDateString.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return [] }
            let components = DateComponents(
                year: parts[0], month: parts[1], day: parts[2],
                hour: time.hour, minute: time.minute)
            guard let fireDate = calendar.date(from: components), fireDate > now else {
                return []
            }
            return [TaskNotificationPlan(
                identifier: identifier,
                title: task.text,
                body: "Due \(task.dueDateString) \(task.dueTimeString!) · \(task.fileTitle)",
                fireDateComponents: components,
                repeats: false)]

        case .daily:
            return [repeatingPlan(for: task, identifier: identifier,
                                  weekday: nil, time: time)]
        case .weekly(let weekday):
            return [repeatingPlan(for: task, identifier: identifier,
                                  weekday: weekday, time: time)]
        case .everyWeekday:
            // One repeating trigger per weekday, Monday through Friday.
            return (2...6).map { (weekday: Int) in
                repeatingPlan(for: task, identifier: identifier + "#w\(weekday)",
                              weekday: weekday, time: time)
            }
        }
    }

    private static func repeatingPlan(for task: TaskItem,
                                      identifier: String,
                                      weekday: Int?,
                                      time: (hour: Int, minute: Int)) -> TaskNotificationPlan {
        var components = DateComponents(hour: time.hour, minute: time.minute)
        components.weekday = weekday
        return TaskNotificationPlan(
            identifier: identifier,
            title: task.text,
            body: "\(task.recurrence!.displayName) at \(task.dueTimeString!) · \(task.fileTitle)",
            fireDateComponents: components,
            repeats: true)
    }
}
