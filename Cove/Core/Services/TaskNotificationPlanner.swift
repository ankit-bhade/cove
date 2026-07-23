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
                      calendar: Calendar = TaskCalendar.gregorian()) -> [TaskNotificationPlan] {
        let calendar = TaskCalendar.gregorian(timeZone: calendar.timeZone)
        // The cap is applied before the bodies are worded: the tasks past it
        // are never scheduled, so formatting a date for each of them is work
        // thrown away.
        return tasks
            .filter { !$0.isCompleted && $0.dueTimeString != nil }
            .sorted(by: VaultIndex.byDueDate)
            .compactMap { task -> (task: TaskItem, fireDate: Date, components: DateComponents)? in
                // A time can only exist alongside a date, so the undated
                // list items never reach here — but the model allows nil.
                guard let time = task.timeComponents,
                      let dueDateString = task.dueDateString else { return nil }
                let parts = dueDateString.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3 else { return nil }
                let components = DateComponents(
                    year: parts[0], month: parts[1], day: parts[2],
                    hour: time.hour, minute: time.minute)
                guard let fireDate = calendar.date(from: components),
                      fireDate > now else { return nil }
                return (task, fireDate, components)
            }
            .prefix(maximumPlans)
            .map { scheduled in
                TaskNotificationPlan(
                    identifier: identifierPrefix + scheduled.task.id,
                    title: scheduled.task.text,
                    body: "\(formattedDueMoment(scheduled.fireDate, calendar: calendar)).",
                    fireDateComponents: scheduled.components)
            }
    }

    /// A compact, human-readable reminder date, for example
    /// `Jul 18, 8:00pm` or `Jul 18, 8:30pm`.
    private static func formattedDueMoment(_ date: Date, calendar: Calendar) -> String {
        TemplateDateFormatters.shared.string(from: date,
                                             template: "MMM d, h:mm a",
                                             calendar: calendar)
    }
}
