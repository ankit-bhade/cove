import Foundation

/// One local notification the app intends to schedule for a due task.
struct TaskNotificationPlan: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    /// Year/month/day/hour/minute of the one-shot fire moment, including the
    /// Gregorian calendar and the time zone in which Cove interpreted the
    /// task's otherwise zone-less Markdown due time.
    let fireDateComponents: DateComponents
}

/// The complete result of planning, including work that could not be handed
/// to the notification center. Keeping the cap visible avoids presenting
/// "successfully scheduled 60" as "every reminder is covered."
struct TaskNotificationPlanInventory: Equatable, Sendable {
    let plans: [TaskNotificationPlan]
    let eligibleCount: Int
    let omittedBySystemLimit: Int
    let invalidDateCount: Int
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
    static let identifierPrefix = CoveTaskNotificationIdentifier.prefix

    /// The system keeps at most 64 pending local notifications per app;
    /// stay under it and let the soonest-due tasks win.
    static let maximumPlans = 60

    static func plans(
        for tasks: [TaskItem],
        now: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [TaskNotificationPlan] {
        inventory(for: tasks, now: now, timeZone: timeZone).plans
    }

    /// Plans reminders and reports both invalid local wall-clock values (for
    /// example 02:30 during a spring-forward gap) and otherwise valid tasks
    /// omitted because iOS/macOS cap pending local notifications.
    static func inventory(
        for tasks: [TaskItem],
        now: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> TaskNotificationPlanInventory {
        let calendar = TaskCalendar.gregorian(timeZone: timeZone)
        var invalidDateCount = 0
        let eligible =
            tasks
            .filter { !$0.isCompleted && $0.dueTimeString != nil }
            .sorted(by: VaultIndex.byDueDate)
            .compactMap { task -> (task: TaskItem, fireDate: Date, components: DateComponents)? in
                guard let dueDateString = task.dueDateString,
                    let dueTimeString = task.dueTimeString
                else { return nil }
                guard
                    case .success(let resolution) = TaskCalendar.resolve(
                        date: dueDateString,
                        time: dueTimeString,
                        timeZone: timeZone,
                        nonexistentTime: .reject,
                        repeatedTime: .first),
                    let date = TaskCalendar.dateComponents(from: dueDateString),
                    let time = TaskCalendar.timeComponents(from: dueTimeString)
                else {
                    invalidDateCount += 1
                    return nil
                }
                var components = DateComponents(
                    year: date.year, month: date.month, day: date.day,
                    hour: time.hour, minute: time.minute)
                components.calendar = calendar
                components.timeZone = timeZone
                guard resolution.date > now else { return nil }
                return (task, resolution.date, components)
            }

        let plans =
            eligible
            .prefix(maximumPlans)
            .map { scheduled in
                TaskNotificationPlan(
                    identifier: CoveTaskNotificationIdentifier.identifier(
                        forTaskID: scheduled.task.id),
                    title: scheduled.task.text,
                    body: "\(formattedDueMoment(scheduled.fireDate, calendar: calendar)).",
                    fireDateComponents: scheduled.components)
            }
        return TaskNotificationPlanInventory(
            plans: Array(plans),
            eligibleCount: eligible.count,
            omittedBySystemLimit: max(0, eligible.count - maximumPlans),
            invalidDateCount: invalidDateCount)
    }

    /// A compact, human-readable reminder date, for example
    /// `Jul 18, 8:00pm` or `Jul 18, 8:30pm`.
    private static func formattedDueMoment(_ date: Date, calendar: Calendar) -> String {
        TemplateDateFormatters.shared.string(
            from: date,
            template: "MMM d, h:mm a",
            calendar: calendar)
    }
}
