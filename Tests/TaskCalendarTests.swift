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
        let next = TaskCalendar.nextMidnight(after: noon, calendar: calendar)

        XCTAssertEqual(next.timeIntervalSince(start), 23 * 60 * 60)
        XCTAssertGreaterThan(next, noon)
    }

    func testNewYorkFallBackMidnightUsesCalendarDay() throws {
        let calendar = newYorkCalendar()
        let noon = try date(2026, 11, 1, hour: 12, calendar: calendar)
        let start = calendar.startOfDay(for: noon)
        let next = TaskCalendar.nextMidnight(after: noon, calendar: calendar)

        XCTAssertEqual(next.timeIntervalSince(start), 25 * 60 * 60)
        XCTAssertGreaterThan(next, noon)
    }

    func testTodaySnapshotChangesAcrossLocalMidnightAheadOfUTC() throws {
        var calendar = TaskCalendar.gregorian(
            timeZone: try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati")))
        calendar.locale = Locale(identifier: "en_US")
        let before = try date(2026, 7, 20, hour: 23, minute: 59, calendar: calendar)
        let after = try XCTUnwrap(calendar.date(byAdding: .minute, value: 2, to: before))
        let snapshot = TodaySnapshot(dayString: "2026-07-20",
                                     generatedAt: before,
                                     tasks: [])

        XCTAssertEqual(snapshot.valid(at: before, calendar: calendar).dayString,
                       "2026-07-20")
        XCTAssertTrue(snapshot.valid(at: after, calendar: calendar).tasks.isEmpty)
        XCTAssertEqual(snapshot.valid(at: after, calendar: calendar).dayString, "")
    }

    func testFormattingUsesInjectedZoneBehindUTC() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let calendar = TaskCalendar.gregorian(timeZone: zone)
        let instant = Date(timeIntervalSince1970: 1_774_156_400) // 2026-03-20 near UTC midnight
        let expected = calendar.dateComponents([.year, .month, .day], from: instant)
        let expectedText = String(format: "%04d-%02d-%02d",
                                  expected.year!, expected.month!, expected.day!)

        XCTAssertEqual(QuickTaskParser.ymdString(from: instant, calendar: calendar),
                       expectedText)
    }

    private func assertSystemCalendarDoesNotChangeStoredDate(_ identifier: Calendar.Identifier,
                                                              file: StaticString = #filePath,
                                                              line: UInt = #line) {
        let zone = TimeZone(secondsFromGMT: 0)!
        let gregorian = TaskCalendar.gregorian(timeZone: zone)
        let instant = gregorian.date(from: DateComponents(year: 2026, month: 7, day: 20,
                                                           hour: 12))!
        var systemCalendar = Calendar(identifier: identifier)
        systemCalendar.timeZone = zone

        let draft = QuickTaskParser.parse("Buy milk", now: instant,
                                          calendar: systemCalendar)
        XCTAssertEqual(draft.dueDateString, "2026-07-20", file: file, line: line)
        XCTAssertEqual(RecurrenceRule(frequency: .daily).nextDueDateString(
            after: "2026-12-31", calendar: systemCalendar),
                       "2027-01-01", file: file, line: line)
    }

    private func newYorkCalendar() -> Calendar {
        TaskCalendar.gregorian(timeZone: TimeZone(identifier: "America/New_York")!)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      hour: Int, minute: Int = 0,
                      calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute)))
    }
}
