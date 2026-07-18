import XCTest
@testable import Cove

final class RecurrenceRuleTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: - Tags

    func testTagRoundTrip() {
        let rules: [RecurrenceRule] = [.daily, .everyWeekday]
            + (1...7).map { .weekly(weekday: $0) }
        for rule in rules {
            XCTAssertEqual(RecurrenceRule(tagText: rule.tagText), rule)
        }
    }

    func testRejectsUnknownTags() {
        for tag in ["sometimes", "every", "every fortnight", "Daily",
                    "every  sunday", "weekly", ""] {
            XCTAssertNil(RecurrenceRule(tagText: tag), tag)
        }
    }

    func testDisplayNames() {
        XCTAssertEqual(RecurrenceRule.daily.displayName, "Daily")
        XCTAssertEqual(RecurrenceRule.everyWeekday.displayName, "Every weekday")
        XCTAssertEqual(RecurrenceRule.weekly(weekday: 1).displayName, "Every Sunday")
        XCTAssertEqual(RecurrenceRule.weekly(weekday: 6).displayName, "Every Friday")
    }

    // MARK: - Next occurrence

    // 2026-07-18 is a Saturday.

    func testDailyAdvancesOneDay() {
        XCTAssertEqual(RecurrenceRule.daily
            .nextDueDateString(after: "2026-07-18", calendar: calendar), "2026-07-19")
    }

    func testDailyRollsOverMonthAndYear() {
        XCTAssertEqual(RecurrenceRule.daily
            .nextDueDateString(after: "2026-07-31", calendar: calendar), "2026-08-01")
        XCTAssertEqual(RecurrenceRule.daily
            .nextDueDateString(after: "2026-12-31", calendar: calendar), "2027-01-01")
    }

    func testEveryWeekdaySkipsWeekends() {
        // Friday → Monday; Saturday → Monday; Monday → Tuesday.
        XCTAssertEqual(RecurrenceRule.everyWeekday
            .nextDueDateString(after: "2026-07-17", calendar: calendar), "2026-07-20")
        XCTAssertEqual(RecurrenceRule.everyWeekday
            .nextDueDateString(after: "2026-07-18", calendar: calendar), "2026-07-20")
        XCTAssertEqual(RecurrenceRule.everyWeekday
            .nextDueDateString(after: "2026-07-20", calendar: calendar), "2026-07-21")
    }

    func testWeeklyAdvancesStrictlyToNextOccurrence() {
        // From a Sunday to the following Sunday, never the same day.
        XCTAssertEqual(RecurrenceRule.weekly(weekday: 1)
            .nextDueDateString(after: "2026-07-19", calendar: calendar), "2026-07-26")
        // From Saturday to the next Sunday.
        XCTAssertEqual(RecurrenceRule.weekly(weekday: 1)
            .nextDueDateString(after: "2026-07-18", calendar: calendar), "2026-07-19")
    }

    func testUnparseableDateReturnsNil() {
        XCTAssertNil(RecurrenceRule.daily
            .nextDueDateString(after: "soon", calendar: calendar))
    }
}
