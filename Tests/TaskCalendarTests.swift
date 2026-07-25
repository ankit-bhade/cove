import XCTest
@testable import Cove

final class TaskCalendarTests: XCTestCase {
    func testStoredDatesStayGregorianWithBuddhistSystemCalendar() {
        assertSystemCalendarDoesNotChangeStoredDate(.buddhist)
    }

    func testStoredDatesStayGregorianWithHebrewSystemCalendar() {
        assertSystemCalendarDoesNotChangeStoredDate(.hebrew)
    }

    func testNewYorkSpringForwardMidnightUsesCalendarDay() throws {
        let calendar = newYorkCalendar()
        let noon = try date(2026, 3, 8, hour: 12, calendar: calendar)
        let start = calendar.startOfDay(for: noon)
        let next = TaskCalendar.nextMidnight(after: noon, timeZone: calendar.timeZone)

        XCTAssertEqual(next.timeIntervalSince(start), 23 * 60 * 60)
        XCTAssertGreaterThan(next, noon)
    }

    func testNewYorkFallBackMidnightUsesCalendarDay() throws {
        let calendar = newYorkCalendar()
        let noon = try date(2026, 11, 1, hour: 12, calendar: calendar)
        let start = calendar.startOfDay(for: noon)
        let next = TaskCalendar.nextMidnight(after: noon, timeZone: calendar.timeZone)

        XCTAssertEqual(next.timeIntervalSince(start), 25 * 60 * 60)
        XCTAssertGreaterThan(next, noon)
    }

    func testRejectsNonexistentSpringForwardWallTime() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(
            TaskCalendar.resolve(
                date: "2026-03-08",
                time: "02:30",
                timeZone: zone,
                nonexistentTime: .reject,
                repeatedTime: .first),
            .failure(
                .nonexistentLocalTime(
                    date: "2026-03-08",
                    time: "02:30")))
    }

    func testRepeatedFallBackWallTimeHasExplicitFirstAndLastPolicies() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let first = try TaskCalendar.resolve(
            date: "2026-11-01",
            time: "01:30",
            timeZone: zone,
            nonexistentTime: .reject,
            repeatedTime: .first
        ).get()
        let last = try TaskCalendar.resolve(
            date: "2026-11-01",
            time: "01:30",
            timeZone: zone,
            nonexistentTime: .reject,
            repeatedTime: .last
        ).get()
        XCTAssertEqual(first.kind, .firstRepeatedTime)
        XCTAssertEqual(last.kind, .lastRepeatedTime)
        XCTAssertEqual(last.date.timeIntervalSince(first.date), 60 * 60)
    }

    func testTodaySnapshotChangesAcrossLocalMidnightAheadOfUTC() throws {
        var calendar = TaskCalendar.gregorian(
            timeZone: try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati")))
        calendar.locale = Locale(identifier: "en_US")
        let before = try date(2026, 7, 20, hour: 23, minute: 59, calendar: calendar)
        let after = try XCTUnwrap(calendar.date(byAdding: .minute, value: 2, to: before))
        let snapshot = TodaySnapshot(
            dayString: "2026-07-20",
            generatedAt: before,
            tasks: [])

        XCTAssertEqual(
            snapshot.valid(at: before, timeZone: calendar.timeZone).dayString,
            "2026-07-20")

        // Past local midnight the snapshot is yesterday's, so it stops being
        // presentable. It reports itself stale rather than empty: an empty
        // list of today's tasks is a claim that there is nothing due, which
        // is exactly what a widget that hasn't refreshed cannot know.
        let stale = snapshot.valid(at: after, timeZone: calendar.timeZone)
        XCTAssertTrue(stale.tasks.isEmpty)
        XCTAssertEqual(stale.availability, .stale)
        XCTAssertNotEqual(stale.availability, .available)
    }

    func testFormattingUsesInjectedZoneBehindUTC() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let calendar = TaskCalendar.gregorian(timeZone: zone)
        let instant = Date(timeIntervalSince1970: 1_774_156_400)  // 2026-03-20 near UTC midnight
        let expected = calendar.dateComponents([.year, .month, .day], from: instant)
        let expectedText = String(
            format: "%04d-%02d-%02d",
            expected.year!, expected.month!, expected.day!)

        XCTAssertEqual(
            QuickTaskParser.ymdString(from: instant, timeZone: calendar.timeZone),
            expectedText)
    }

    /// Date APIs take a time zone rather than a calendar, so a non-Gregorian
    /// calendar can no longer be handed to one at all — the type now enforces
    /// what this used to check at run time. What remains worth asserting is
    /// that `TaskCalendar` itself builds a Gregorian calendar and that the
    /// stored strings come out in Gregorian years: a Buddhist reading of this
    /// instant is 2569 and a Hebrew one 5786, so "2026-07-20" could not
    /// survive either.
    private func assertSystemCalendarDoesNotChangeStoredDate(
        _ identifier: Calendar.Identifier,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let zone = TimeZone(secondsFromGMT: 0)!
        let gregorian = TaskCalendar.gregorian(timeZone: zone)
        XCTAssertEqual(gregorian.identifier, .gregorian, file: file, line: line)
        XCTAssertNotEqual(gregorian.identifier, identifier, file: file, line: line)

        let instant = gregorian.date(
            from: DateComponents(
                year: 2026, month: 7, day: 20,
                hour: 12))!

        let draft = QuickTaskParser.parse("Buy milk", now: instant, timeZone: zone)
        XCTAssertEqual(draft.dueDateString, "2026-07-20", file: file, line: line)
        XCTAssertEqual(
            QuickTaskParser.ymdString(from: instant, timeZone: zone),
            "2026-07-20", file: file, line: line)
        XCTAssertEqual(
            RecurrenceRule(frequency: .daily).nextDueDateString(
                after: "2026-12-31", timeZone: zone),
            "2027-01-01", file: file, line: line)
    }

    private func newYorkCalendar() -> Calendar {
        TaskCalendar.gregorian(timeZone: TimeZone(identifier: "America/New_York")!)
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int, minute: Int = 0,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year, month: month, day: day, hour: hour, minute: minute)))
    }
}
