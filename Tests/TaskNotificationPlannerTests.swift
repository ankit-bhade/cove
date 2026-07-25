import XCTest
@testable import Cove

final class TaskNotificationPlannerTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// A `now` well before any 2026 fire time.
    private var earlyNow: Date {
        date(2026, 1, 1, hour: 0)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour))!
    }

    private func task(
        text: String = "Task",
        due: String,
        time: String? = nil,
        recurrence: RecurrenceRule? = nil,
        file: String = "Note",
        line: Int = 0,
        completed: Bool = false
    ) -> TaskItem {
        TaskItem(
            fileURL: URL(fileURLWithPath: "/vault/\(file).md"),
            fileTitle: file,
            lineNumber: line,
            text: text,
            dueDateString: due,
            dueTimeString: time,
            recurrence: recurrence,
            isCompleted: completed,
            listName: nil)
    }

    // MARK: - Which tasks get a plan

    func testPlansTimedIncompleteFutureTask() {
        let plans = TaskNotificationPlanner.plans(
            for: [task(text: "Do Laundry", due: "2026-07-18", time: "20:00", file: "Tasks")],
            now: earlyNow, timeZone: calendar.timeZone)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.title, "Do Laundry")
        XCTAssertEqual(
            plans.first?.body,
            notificationBody(2026, 7, 18, hour: 20, minute: 0))
        XCTAssertEqual(
            plans.first?.fireDateComponents,
            triggerComponents(2026, 7, 18, hour: 20, minute: 0))
    }

    func testDateOnlyTasksGetNoNotification() {
        let plans = TaskNotificationPlanner.plans(
            for: [
                task(due: "2026-07-20"),
                task(due: "2026-07-21", recurrence: RecurrenceRule(frequency: .daily)),
            ],
            now: earlyNow, timeZone: calendar.timeZone)
        XCTAssertTrue(plans.isEmpty)
    }

    func testSkipsCompletedTasks() {
        let plans = TaskNotificationPlanner.plans(
            for: [task(due: "2026-07-20", time: "15:00", completed: true)],
            now: earlyNow, timeZone: calendar.timeZone)
        XCTAssertTrue(plans.isEmpty)
    }

    func testSkipsTasksWhoseDueMomentHasPassed() {
        let now = date(2026, 7, 20, hour: 16)
        let plans = TaskNotificationPlanner.plans(
            for: [
                task(due: "2026-07-19", time: "15:00"),
                task(due: "2026-07-20", time: "15:00"),
            ],
            now: now, timeZone: calendar.timeZone)
        XCTAssertTrue(plans.isEmpty)
    }

    func testKeepsTaskDueLaterToday() {
        let now = date(2026, 7, 20, hour: 14)
        let plans = TaskNotificationPlanner.plans(
            for: [task(due: "2026-07-20", time: "15:00")],
            now: now, timeZone: calendar.timeZone)
        XCTAssertEqual(plans.count, 1)
    }

    // MARK: - Recurring tasks (one-shot at the next occurrence, grove-style)

    func testRecurringTaskGetsOneShotAtItsDueMoment() {
        let plans = TaskNotificationPlanner.plans(
            for: [
                task(
                    text: "Laundry", due: "2026-07-19", time: "18:00",
                    recurrence: RecurrenceRule(frequency: .weekly, byWeekday: [1]),
                    file: "Chores")
            ],
            now: earlyNow, timeZone: calendar.timeZone)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(
            plans.first?.body,
            notificationBody(2026, 7, 19, hour: 18, minute: 0))
        XCTAssertEqual(
            plans.first?.fireDateComponents,
            triggerComponents(2026, 7, 19, hour: 18, minute: 0))
    }

    func testOverdueRecurringTaskIsNotScheduled() {
        // Grove never schedules ahead: a stale occurrence gets nothing; the
        // rebuild after completing it schedules the next one.
        let now = date(2026, 7, 20, hour: 16)
        let plans = TaskNotificationPlanner.plans(
            for: [
                task(
                    due: "2026-07-19", time: "18:00",
                    recurrence: RecurrenceRule(frequency: .daily))
            ],
            now: now, timeZone: calendar.timeZone)
        XCTAssertTrue(plans.isEmpty)
    }

    func testNotificationBodyKeepsNonzeroMinutes() {
        let plans = TaskNotificationPlanner.plans(
            for: [task(text: "Laundry", due: "2026-07-18", time: "20:30")],
            now: earlyNow, timeZone: calendar.timeZone)
        XCTAssertEqual(
            plans.first?.body,
            notificationBody(2026, 7, 18, hour: 20, minute: 30))
    }

    // MARK: - Ordering and cap

    func testSoonestTasksWinWhenOverCap() {
        // 70 timed tasks on 70 distinct dates, handed over in reverse order.
        let dates = (0..<(TaskNotificationPlanner.maximumPlans + 10)).map {
            String(format: "2026-%02d-%02d", $0 / 28 + 1, $0 % 28 + 1)
        }
        let tasks = dates.reversed().enumerated().map { line, due in
            task(text: "T\(due)", due: due, time: "12:00", line: line)
        }
        let plans = TaskNotificationPlanner.plans(
            for: tasks, now: earlyNow, timeZone: calendar.timeZone)
        XCTAssertEqual(plans.count, TaskNotificationPlanner.maximumPlans)
        XCTAssertEqual(
            plans.map(\.title),
            dates.prefix(TaskNotificationPlanner.maximumPlans).map { "T\($0)" })
    }

    func testInventoryReportsTasksOmittedBySystemLimit() {
        let tasks = (0..<(TaskNotificationPlanner.maximumPlans + 3)).map { line in
            task(
                text: "Task \(line)",
                due: String(format: "2026-%02d-%02d", line / 28 + 1, line % 28 + 1),
                time: "09:00",
                line: line)
        }
        let inventory = TaskNotificationPlanner.inventory(
            for: tasks,
            now: earlyNow,
            timeZone: calendar.timeZone)

        XCTAssertEqual(inventory.plans.count, TaskNotificationPlanner.maximumPlans)
        XCTAssertEqual(inventory.eligibleCount, tasks.count)
        XCTAssertEqual(inventory.omittedBySystemLimit, 3)
    }

    func testNonexistentDSTWallTimeIsSkippedAndReported() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let zoneCalendar = TaskCalendar.gregorian(timeZone: newYork)
        let now = zoneCalendar.date(
            from: DateComponents(
                year: 2026, month: 3, day: 1, hour: 12))!
        let inventory = TaskNotificationPlanner.inventory(
            for: [task(due: "2026-03-08", time: "02:30")],
            now: now,
            timeZone: newYork)

        XCTAssertTrue(inventory.plans.isEmpty)
        XCTAssertEqual(inventory.invalidDateCount, 1)
    }

    func testTriggerCarriesExplicitGregorianCalendarAndTimeZone() throws {
        let timeZone = TimeZone(identifier: "Pacific/Auckland")!
        let plan = try XCTUnwrap(
            TaskNotificationPlanner.plans(
                for: [task(due: "2026-07-20", time: "15:00")],
                now: earlyNow,
                timeZone: timeZone
            ).first)

        XCTAssertEqual(plan.fireDateComponents.calendar?.identifier, .gregorian)
        XCTAssertEqual(plan.fireDateComponents.timeZone, timeZone)
    }

    // MARK: - Identifiers

    func testIdentifiersCarryThePrefixAndAreUnique() {
        let plans = TaskNotificationPlanner.plans(
            for: [
                task(due: "2026-07-20", time: "10:00", line: 0),
                task(
                    due: "2026-07-21", time: "10:00",
                    recurrence: .everyWeekday, line: 1),
            ],
            now: earlyNow, timeZone: calendar.timeZone)
        XCTAssertEqual(plans.count, 2)
        XCTAssertTrue(
            plans.allSatisfy {
                $0.identifier.hasPrefix(TaskNotificationPlanner.identifierPrefix)
            })
        XCTAssertEqual(Set(plans.map(\.identifier)).count, plans.count)
        XCTAssertFalse(plans.contains { $0.identifier.contains("/vault/") })
    }

    private func triggerComponents(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int,
        minute: Int
    ) -> DateComponents {
        var components = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return components
    }

    private func notificationBody(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int, minute: Int
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d, h:mm a")
        let moment = calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute))!
        return formatter.string(from: moment) + "."
    }
}
