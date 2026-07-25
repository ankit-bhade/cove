import XCTest
@testable import Cove

/// `TaskItem.dueDate` resolves through `Calendar.current`, so these tests
/// build their fixed `now` values with the same calendar rather than a UTC
/// one — otherwise the day arithmetic under test would straddle time zones.
final class TaskPresentationTests: XCTestCase {

    private let calendar = Calendar.current

    private func now(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int = 9, minute: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func task(
        text: String = "Task",
        due: String?,
        time: String? = nil,
        recurrence: RecurrenceRule? = nil,
        completed: Bool = false
    ) -> TaskItem {
        TaskItem(
            fileURL: URL(fileURLWithPath: "/vault/Note.md"),
            fileTitle: "Note",
            lineNumber: 0,
            text: text,
            dueDateString: due,
            dueTimeString: time,
            recurrence: recurrence,
            isCompleted: completed,
            listName: nil)
    }

    // MARK: - Overdue

    func testDateOnlyTaskIsNotOverdueOnItsOwnDay() {
        let item = task(due: "2026-07-19")
        XCTAssertFalse(item.isOverdue(at: now(2026, 7, 19, hour: 23)))
    }

    func testDateOnlyTaskIsOverdueTheNextDay() {
        let item = task(due: "2026-07-19")
        XCTAssertTrue(item.isOverdue(at: now(2026, 7, 20, hour: 0)))
    }

    func testTimedTaskIsOverdueOnlyAfterItsMoment() {
        let item = task(due: "2026-07-19", time: "15:00")
        XCTAssertFalse(item.isOverdue(at: now(2026, 7, 19, hour: 14, minute: 59)))
        XCTAssertTrue(item.isOverdue(at: now(2026, 7, 19, hour: 15, minute: 1)))
    }

    func testCompletedTaskIsNeverOverdue() {
        let item = task(due: "2020-01-01", time: "09:00", completed: true)
        XCTAssertFalse(item.isOverdue(at: now(2026, 7, 19)))
    }

    // MARK: - Relative wording

    func testTodayTomorrowAndYesterdayReadRelatively() {
        let today = now(2026, 7, 19)
        XCTAssertEqual(task(due: "2026-07-19").relativeDueDescription(at: today), "Today")
        XCTAssertEqual(task(due: "2026-07-20").relativeDueDescription(at: today), "Tomorrow")
        XCTAssertEqual(task(due: "2026-07-18").relativeDueDescription(at: today), "Yesterday")
    }

    func testDatesInsideTheComingWeekUseWeekdayNames() {
        // 2026-07-19 is a Sunday; +3 days is Wednesday.
        let description = task(due: "2026-07-22")
            .relativeDueDescription(at: now(2026, 7, 19))
        XCTAssertEqual(description, "Wednesday")
    }

    func testDistantSameYearDateOmitsTheYear() {
        let description = task(due: "2026-09-14")
            .relativeDueDescription(at: now(2026, 7, 19))
        XCTAssertFalse(description.contains("2026"))
        XCTAssertTrue(description.contains("14"))
    }

    func testDifferentYearDateIncludesTheYear() {
        let description = task(due: "2027-09-14")
            .relativeDueDescription(at: now(2026, 7, 19))
        XCTAssertTrue(description.contains("2027"))
    }

    func testTimeIsAppendedToTheDayDescription() {
        let description = task(due: "2026-07-19", time: "15:30")
            .relativeDueDescription(at: now(2026, 7, 19, hour: 8))
        XCTAssertTrue(description.hasPrefix("Today, "), description)
        XCTAssertTrue(description.contains("30"), description)
    }

    // MARK: - Due wording over raw strings

    /// The quick-capture preview formats a `TaskDraft`, which has no
    /// `TaskItem` to hang the wording off. Both paths must read identically,
    /// or a task would change its words the moment it was saved.
    func testDraftShapedInputMatchesTheTaskRowWording() {
        let today = now(2026, 7, 19, hour: 8)
        for (date, time) in [
            ("2026-07-19", nil), ("2026-07-20", "15:30"),
            ("2026-07-22", nil), ("2027-09-14", "09:00"),
        ]
            as [(String, String?)]
        {
            XCTAssertEqual(
                DueDescription.text(
                    dueDateString: date, dueTimeString: time,
                    at: today, timeZone: calendar.timeZone),
                task(due: date, time: time).relativeDueDescription(at: today),
                "\(date) \(time ?? "-")")
        }
    }

    /// An undated list item has no due wording at all — its row shows no
    /// capsule, and neither does the capture preview.
    func testUndatedInputHasNoWording() {
        XCTAssertEqual(
            DueDescription.text(
                dueDateString: nil, dueTimeString: nil,
                at: now(2026, 7, 19), timeZone: calendar.timeZone),
            "")
    }

    // MARK: - Grouping

    func testTasksLandInTheExpectedSections() {
        let today = now(2026, 7, 19, hour: 12)
        XCTAssertEqual(TaskGroup.kind(for: task(due: "2026-07-18"), now: today), .overdue)
        XCTAssertEqual(TaskGroup.kind(for: task(due: "2026-07-19"), now: today), .today)
        XCTAssertEqual(TaskGroup.kind(for: task(due: "2026-07-20"), now: today), .tomorrow)
        XCTAssertEqual(TaskGroup.kind(for: task(due: "2026-07-25"), now: today), .upcoming)
    }

    func testTodaysPassedTimedTaskIsOverdueRatherThanToday() {
        let today = now(2026, 7, 19, hour: 12)
        let item = task(due: "2026-07-19", time: "09:00")
        XCTAssertEqual(TaskGroup.kind(for: item, now: today), .overdue)
    }

    func testGroupingKeepsSortedOrderAndDropsEmptySections() {
        let today = now(2026, 7, 19, hour: 12)
        let tasks = [
            task(text: "Late", due: "2026-07-17"),
            task(text: "Now", due: "2026-07-19"),
            task(text: "Later", due: "2026-08-01"),
        ]
        let groups = TaskGroup.grouping(tasks, now: today)

        // No task falls on tomorrow, so that section is absent entirely.
        XCTAssertEqual(groups.map(\.kind), [.overdue, .today, .upcoming])
        XCTAssertEqual(groups.flatMap(\.tasks).map(\.text), ["Late", "Now", "Later"])
    }

    func testGroupingPreservesRelativeOrderWithinASection() {
        let today = now(2026, 7, 19, hour: 0, minute: 1)
        let tasks = [
            task(text: "First", due: "2026-07-19"),
            task(text: "Second", due: "2026-07-19", time: "08:00"),
            task(text: "Third", due: "2026-07-19", time: "17:00"),
        ]
        let groups = TaskGroup.grouping(tasks, now: today)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].tasks.map(\.text), ["First", "Second", "Third"])
    }

    func testGroupsNameThemselvesWithoutTheirCounts() {
        // The header sets the count beside the name in its own weight, so the
        // name has to stay a bare noun.
        let today = now(2026, 7, 19, hour: 12)
        let groups = TaskGroup.grouping(
            [task(due: "2026-07-19"), task(due: "2026-07-19")], now: today)
        XCTAssertEqual(groups.first?.name, "Today")
        XCTAssertEqual(groups.first?.tasks.count, 2)
    }

    func testOnlyUpcomingFoldsAway() {
        // Overdue, Today, and Tomorrow are the screen's reason for existing
        // and are never put behind a chevron; Upcoming is unbounded and is.
        let today = now(2026, 7, 19, hour: 12)
        let groups = TaskGroup.grouping(
            [
                task(due: "2026-07-17"),
                task(due: "2026-07-19"),
                task(due: "2026-07-20"),
                task(due: "2026-08-01"),
            ],
            now: today)
        XCTAssertEqual(
            groups.filter(\.isCollapsible).map(\.kind), [.upcoming])
    }

    // MARK: - Undated list items

    func testAnUndatedItemIsNeverOverdue() {
        let item = task(text: "Milk", due: nil)
        XCTAssertFalse(item.isOverdue(at: now(2026, 7, 19, hour: 12)))
        XCTAssertFalse(item.isDue(onSameDayAs: now(2026, 7, 19, hour: 12)))
        XCTAssertFalse(item.hasDueDate)
    }

    func testAnUndatedItemHasNoDueDescription() {
        XCTAssertEqual(
            task(text: "Milk", due: nil)
                .relativeDueDescription(at: now(2026, 7, 19, hour: 12)), "")
    }
}
