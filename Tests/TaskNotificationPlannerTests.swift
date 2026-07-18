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
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour))!
    }

    private func task(text: String = "Task",
                      due: String,
                      file: String = "Note",
                      line: Int = 0,
                      completed: Bool = false) -> TaskItem {
        TaskItem(fileURL: URL(fileURLWithPath: "/vault/\(file).md"),
                 fileTitle: file,
                 lineNumber: line,
                 text: text,
                 dueDateString: due,
                 isCompleted: completed)
    }

    // MARK: - Which tasks get a plan

    func testPlansIncompleteFutureTask() {
        let plans = TaskNotificationPlanner.plans(
            for: [task(text: "Buy milk", due: "2026-07-20", file: "Groceries")],
            now: earlyNow, calendar: calendar)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.title, "Buy milk")
        XCTAssertEqual(plans.first?.body, "Due 2026-07-20 · Groceries")
        XCTAssertEqual(plans.first?.fireDateComponents,
                       DateComponents(year: 2026, month: 7, day: 20,
                                      hour: TaskNotificationPlanner.fireHour, minute: 0))
    }

    func testSkipsCompletedTasks() {
        let plans = TaskNotificationPlanner.plans(
            for: [task(due: "2026-07-20", completed: true)],
            now: earlyNow, calendar: calendar)
        XCTAssertTrue(plans.isEmpty)
    }

    func testSkipsTasksWhoseFireTimeHasPassed() {
        // Due yesterday, and due today with the fire hour already past.
        let now = date(2026, 7, 20, hour: TaskNotificationPlanner.fireHour + 1)
        let plans = TaskNotificationPlanner.plans(
            for: [task(due: "2026-07-19"), task(due: "2026-07-20")],
            now: now, calendar: calendar)
        XCTAssertTrue(plans.isEmpty)
    }

    func testKeepsTaskDueTodayBeforeFireHour() {
        let now = date(2026, 7, 20, hour: TaskNotificationPlanner.fireHour - 1)
        let plans = TaskNotificationPlanner.plans(
            for: [task(due: "2026-07-20")],
            now: now, calendar: calendar)
        XCTAssertEqual(plans.count, 1)
    }

    // MARK: - Ordering and cap

    func testSoonestTasksWinWhenOverCap() {
        // 70 tasks on 70 distinct dates, handed over in reverse order.
        let dates = (0..<(TaskNotificationPlanner.maximumPlans + 10)).map {
            String(format: "2026-%02d-%02d", $0 / 28 + 1, $0 % 28 + 1)
        }
        let tasks = dates.reversed().enumerated().map { line, due in
            task(text: "T\(due)", due: due, line: line)
        }
        let plans = TaskNotificationPlanner.plans(
            for: tasks, now: earlyNow, calendar: calendar)
        XCTAssertEqual(plans.count, TaskNotificationPlanner.maximumPlans)
        // Sorted soonest-first, keeping exactly the earliest dates.
        XCTAssertEqual(plans.map(\.title),
                       dates.prefix(TaskNotificationPlanner.maximumPlans).map { "T\($0)" })
    }

    // MARK: - Identifiers

    func testIdentifiersCarryThePrefixAndAreUnique() {
        let plans = TaskNotificationPlanner.plans(
            for: [task(due: "2026-07-20", line: 0),
                  task(due: "2026-07-21", line: 1)],
            now: earlyNow, calendar: calendar)
        XCTAssertTrue(plans.allSatisfy {
            $0.identifier.hasPrefix(TaskNotificationPlanner.identifierPrefix)
        })
        XCTAssertEqual(Set(plans.map(\.identifier)).count, plans.count)
    }
}
