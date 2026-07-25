import XCTest
@testable import Cove

final class RecurrenceRuleTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func next(_ rule: RecurrenceRule, after: String) -> String? {
        rule.nextDueDateString(after: after, timeZone: calendar.timeZone)
    }

    // MARK: - Tags

    func testTagRoundTrip() {
        let rules: [RecurrenceRule] = [
            RecurrenceRule(frequency: .daily),
            RecurrenceRule(frequency: .weekly),
            RecurrenceRule(frequency: .monthly),
            RecurrenceRule(frequency: .yearly),
            .everyWeekday,
            RecurrenceRule(frequency: .weekly, byWeekday: [1]),
            RecurrenceRule(frequency: .weekly, byWeekday: [2, 4, 6]),
            RecurrenceRule(frequency: .daily, interval: 3),
            RecurrenceRule(frequency: .weekly, interval: 2),
            RecurrenceRule(frequency: .monthly, interval: 6),
        ]
        for rule in rules {
            XCTAssertEqual(RecurrenceRule(tagText: rule.tagText), rule, rule.tagText)
        }
    }

    func testNormalizedTagForms() {
        XCTAssertEqual(RecurrenceRule(frequency: .daily).tagText, "daily")
        XCTAssertEqual(RecurrenceRule.everyWeekday.tagText, "every weekday")
        XCTAssertEqual(
            RecurrenceRule(frequency: .weekly, byWeekday: [1]).tagText,
            "every sunday")
        XCTAssertEqual(
            RecurrenceRule(frequency: .weekly, byWeekday: [2, 4]).tagText,
            "every monday wednesday")
        XCTAssertEqual(
            RecurrenceRule(frequency: .weekly, interval: 2).tagText,
            "every 2 weeks")
    }

    func testParsesHandTypedVariants() {
        XCTAssertEqual(
            RecurrenceRule(tagText: "every day"),
            RecurrenceRule(frequency: .daily))
        XCTAssertEqual(
            RecurrenceRule(tagText: "every sun"),
            RecurrenceRule(frequency: .weekly, byWeekday: [1]))
        XCTAssertEqual(
            RecurrenceRule(tagText: "every mon wed fri"),
            RecurrenceRule(frequency: .weekly, byWeekday: [2, 4, 6]))
        XCTAssertEqual(RecurrenceRule(tagText: "every weekdays"), .everyWeekday)
        XCTAssertEqual(
            RecurrenceRule(tagText: "every 3 days"),
            RecurrenceRule(frequency: .daily, interval: 3))
    }

    func testRejectsUnknownTags() {
        for tag in [
            "sometimes", "every", "every fortnight", "Daily",
            "every 0 weeks", "every 2 fortnights", "weekly on monday",
            "every monday and wednesday", "",
        ] {
            XCTAssertNil(RecurrenceRule(tagText: tag), tag)
        }
    }

    // MARK: - Display (grove's describeRecurrence)

    func testDisplayNames() {
        XCTAssertEqual(RecurrenceRule(frequency: .daily).displayName, "Every day")
        XCTAssertEqual(RecurrenceRule(frequency: .weekly).displayName, "Every week")
        XCTAssertEqual(RecurrenceRule.everyWeekday.displayName, "Every weekday")
        XCTAssertEqual(
            RecurrenceRule(frequency: .weekly, byWeekday: [2]).displayName,
            "Every Monday")
        XCTAssertEqual(
            RecurrenceRule(frequency: .weekly, byWeekday: [2, 4]).displayName,
            "Every Monday and Wednesday")
        XCTAssertEqual(
            RecurrenceRule(frequency: .weekly, byWeekday: [2, 4, 6]).displayName,
            "Every Monday, Wednesday and Friday")
        XCTAssertEqual(
            RecurrenceRule(frequency: .weekly, interval: 2).displayName,
            "Every 2 weeks")
        XCTAssertEqual(RecurrenceRule(frequency: .yearly).displayName, "Every year")
    }

    // MARK: - Next occurrence (grove's nextOccurrence)

    // 2026-07-18 is a Saturday.

    func testDaily() {
        XCTAssertEqual(
            next(
                RecurrenceRule(frequency: .daily),
                after: "2026-07-18"), "2026-07-19")
        XCTAssertEqual(
            next(
                RecurrenceRule(frequency: .daily, interval: 3),
                after: "2026-07-18"), "2026-07-21")
        XCTAssertEqual(
            next(
                RecurrenceRule(frequency: .daily),
                after: "2026-12-31"), "2027-01-01")
    }

    func testWeeklyWithoutWeekdaysRepeatsTheSameDay() {
        XCTAssertEqual(
            next(
                RecurrenceRule(frequency: .weekly),
                after: "2026-07-18"), "2026-07-25")
    }

    func testWeeklyWalksToTheNextListedWeekday() {
        // From Wednesday 07-15 with {Mon, Wed} → Monday 07-20.
        XCTAssertEqual(
            next(
                RecurrenceRule(frequency: .weekly, byWeekday: [2, 4]),
                after: "2026-07-15"), "2026-07-20")
        // Every weekday: Friday → Monday, Saturday → Monday.
        XCTAssertEqual(next(.everyWeekday, after: "2026-07-17"), "2026-07-20")
        XCTAssertEqual(next(.everyWeekday, after: "2026-07-18"), "2026-07-20")
    }

    func testWeeklyIntervalJumpsWholeWeeks() {
        // Every 2 weeks from Saturday 07-18 → Saturday 08-01.
        XCTAssertEqual(
            next(
                RecurrenceRule(frequency: .weekly, interval: 2),
                after: "2026-07-18"), "2026-08-01")
    }

    func testMonthlyClampsToShortMonths() {
        XCTAssertEqual(
            next(
                RecurrenceRule(frequency: .monthly),
                after: "2026-01-31"), "2026-02-28")
        XCTAssertEqual(
            next(
                RecurrenceRule(frequency: .monthly),
                after: "2026-07-18"), "2026-08-18")
    }

    func testYearlyHandlesLeapDay() {
        XCTAssertEqual(
            next(
                RecurrenceRule(frequency: .yearly),
                after: "2028-02-29"), "2029-02-28")
        XCTAssertEqual(
            next(
                RecurrenceRule(frequency: .yearly),
                after: "2026-07-18"), "2027-07-18")
    }

    func testExplicitMonthlyAnchorSurvivesShortMonthClamp() {
        let rule = RecurrenceRule(frequency: .monthly)
        XCTAssertEqual(
            rule.nextDueDateString(
                after: "2026-01-30",
                anchoredTo: "2026-01-30",
                timeZone: calendar.timeZone),
            "2026-02-28")
        XCTAssertEqual(
            rule.nextDueDateString(
                after: "2026-02-28",
                anchoredTo: "2026-01-30",
                timeZone: calendar.timeZone),
            "2026-03-30")
    }

    func testExplicitLeapDayAnchorReturnsToLeapDay() {
        let rule = RecurrenceRule(frequency: .yearly)
        XCTAssertEqual(
            rule.nextDueDateString(
                after: "2029-02-28",
                anchoredTo: "2028-02-29",
                timeZone: calendar.timeZone),
            "2030-02-28")
        XCTAssertEqual(
            rule.nextDueDateString(
                after: "2031-02-28",
                anchoredTo: "2028-02-29",
                timeZone: calendar.timeZone),
            "2032-02-29")
    }

    func testOverdueIntervalRulePreservesCadence() {
        let rule = RecurrenceRule(frequency: .daily, interval: 3)
        XCTAssertEqual(
            rule.nextDueDateString(
                afterOccurrence: "2026-06-01",
                catchingUpPast: "2026-07-18",
                timeZone: calendar.timeZone),
            "2026-07-19")
    }

    func testUnparseableDateReturnsNil() {
        XCTAssertNil(next(RecurrenceRule(frequency: .daily), after: "soon"))
    }

    // MARK: - Interval bounds

    func testIntervalIsClampedToTheSupportedRange() {
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, interval: 0).interval, 1)
        XCTAssertEqual(RecurrenceRule(frequency: .weekly, interval: -5).interval, 1)
        XCTAssertEqual(
            RecurrenceRule(frequency: .weekly, interval: .max).interval,
            RecurrenceRule.maximumInterval)
        XCTAssertEqual(
            RecurrenceRule(tagText: "every 9223372036854775807 weeks")?.interval,
            RecurrenceRule.maximumInterval)
    }

    /// The weekly arithmetic multiplies the interval by seven, so an
    /// unclamped one read back out of a note's `@repeat` tag would overflow
    /// and trap the process on the next completion.
    func testHugeWeeklyIntervalAdvancesInsteadOfOverflowing() throws {
        let rule = try XCTUnwrap(RecurrenceRule(tagText: "every 9223372036854775807 weeks"))
        let advanced = try XCTUnwrap(next(rule, after: "2026-07-18"))
        XCTAssertGreaterThan(advanced, "2026-07-18")
    }
}
