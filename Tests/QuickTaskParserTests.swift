import XCTest
@testable import Cove

/// Ports the grove-app parser test suite (`src/lib/parser/parse.test.ts`)
/// to Cove's `QuickTaskParser`, plus the documented Cove divergences:
/// undated input resolves to today, time ranges keep only their start
/// time, and hashtags are not a feature.
final class QuickTaskParserTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Grove's fixed "now": Wednesday, July 1, 2026, 10:00 AM.
    private var now: Date {
        calendar.date(
            from: DateComponents(
                year: 2026, month: 7, day: 1, hour: 10))!
    }

    private func parse(_ input: String) -> TaskDraft {
        QuickTaskParser.parse(input, now: now, timeZone: calendar.timeZone)
    }

    // MARK: - Plain capture

    func testUndatedTaskResolvesToToday() {
        // Cove divergence: grove leaves this undated; Cove tasks need @due.
        let p = parse("buy milk")
        XCTAssertEqual(p.title, "Buy milk")
        XCTAssertEqual(p.dueDateString, "2026-07-01")
        XCTAssertNil(p.dueTimeString)
        XCTAssertNil(p.recurrence)
    }

    func testDigitsInWordsAreNotTimes() {
        let p = parse("hw4 draft")
        XCTAssertEqual(p.title, "Hw4 draft")
        XCTAssertNil(p.dueTimeString)
    }

    // MARK: - Relative dates

    func testTomorrowForms() {
        XCTAssertEqual(parse("hw4 tmr").dueDateString, "2026-07-02")
        for word in ["tomorrow", "tmrw", "tom"] {
            XCTAssertEqual(parse("pack bags \(word)").dueDateString, "2026-07-02", word)
        }
        XCTAssertEqual(parse("hw4 tmr").title, "Hw4")
    }

    func testTodayForms() {
        for word in ["today", "tdy"] {
            XCTAssertEqual(parse("laundry \(word)").dueDateString, "2026-07-01", word)
        }
    }

    func testDayAfterTomorrow() {
        XCTAssertEqual(parse("mail form day after tomorrow").dueDateString, "2026-07-03")
    }

    func testTonightIsTodayAt8pm() {
        let p = parse("call mom tonight")
        XCTAssertEqual(p.title, "Call mom")
        XCTAssertEqual(p.dueDateString, "2026-07-01")
        XCTAssertEqual(p.dueTimeString, "20:00")
    }

    func testTonightKeepsAnExplicitTime() {
        XCTAssertEqual(parse("call mom tonight 9pm").dueTimeString, "21:00")
    }

    func testInUnits() {
        XCTAssertEqual(parse("submit paper in 3 days").dueDateString, "2026-07-04")
        XCTAssertEqual(parse("submit paper in 3 days").title, "Submit paper")
        XCTAssertEqual(parse("renew passport in 2 weeks").dueDateString, "2026-07-15")
        XCTAssertEqual(parse("dentist in 1 month").dueDateString, "2026-08-01")
        XCTAssertEqual(parse("ship it in 3d").dueDateString, "2026-07-04")
    }

    func testNextWeekIsNextMonday() {
        XCTAssertEqual(parse("plan trip next week").dueDateString, "2026-07-06")
    }

    // MARK: - Weekdays

    func testWeekdayWithTime() {
        let p = parse("meeting fri 3pm")
        XCTAssertEqual(p.title, "Meeting")
        XCTAssertEqual(p.dueDateString, "2026-07-03")
        XCTAssertEqual(p.dueTimeString, "15:00")
    }

    func testPlainWeekdayIncludesToday() {
        // Now is a Wednesday.
        XCTAssertEqual(parse("standup wed").dueDateString, "2026-07-01")
    }

    func testNextWeekdaySkipsToday() {
        XCTAssertEqual(parse("meeting next fri 2pm").dueDateString, "2026-07-03")
        XCTAssertEqual(parse("review next wed").dueDateString, "2026-07-08")
    }

    func testFullWeekdayNames() {
        let p = parse("birthday party saturday 6pm")
        XCTAssertEqual(p.title, "Birthday party")
        XCTAssertEqual(p.dueDateString, "2026-07-04")
        XCTAssertEqual(p.dueTimeString, "18:00")
    }

    func testWeekdayAbbreviationsInsideWordsDoNotMatch() {
        let p = parse("check the monitor")
        XCTAssertEqual(p.title, "Check the monitor")
        XCTAssertNil(p.dueTimeString)
        XCTAssertEqual(p.dueDateString, "2026-07-01")  // undated → today
    }

    // MARK: - Explicit dates

    func testSlashDates() {
        XCTAssertEqual(parse("rent 2/3").dueDateString, "2027-02-03")  // Feb 3 passed
        XCTAssertEqual(parse("rent 2/3").title, "Rent")
        XCTAssertEqual(parse("flight 9/12").dueDateString, "2026-09-12")
        XCTAssertEqual(parse("taxes 4/15/27").dueDateString, "2027-04-15")
    }

    func testMonthNameDates() {
        XCTAssertEqual(parse("conference sep 12").dueDateString, "2026-09-12")
        XCTAssertEqual(parse("gift feb 3rd").dueDateString, "2027-02-03")
    }

    func testInvalidSlashDateIsIgnored() {
        let p = parse("score was 15/2")
        XCTAssertEqual(p.title, "Score was 15/2")
        XCTAssertEqual(p.dueDateString, "2026-07-01")  // undated → today
    }

    // MARK: - Times

    func testCompactTimes() {
        let p = parse("retainer 940p")
        XCTAssertEqual(p.title, "Retainer")
        XCTAssertEqual(p.dueDateString, "2026-07-01")
        XCTAssertEqual(p.dueTimeString, "21:40")
        XCTAssertEqual(parse("run 630a").dueTimeString, "06:30")
    }

    func testMeridiemTimes() {
        XCTAssertEqual(parse("gym 6a").dueTimeString, "06:00")
        XCTAssertEqual(parse("call 3:30pm").dueTimeString, "15:30")
        XCTAssertEqual(parse("flight 12am").dueTimeString, "00:00")
        XCTAssertEqual(parse("lunch 12pm").dueTimeString, "12:00")
    }

    func testBareClockTimes() {
        XCTAssertEqual(parse("call 15:00").dueTimeString, "15:00")
        // Bare h:mm assumes afternoon for small hours, keeps morning ones.
        XCTAssertEqual(parse("coffee 5:30").dueTimeString, "17:30")
        XCTAssertEqual(parse("standup 9:15").dueTimeString, "09:15")
    }

    func testNoonAndMidnight() {
        XCTAssertEqual(parse("lunch noon").dueTimeString, "12:00")
        XCTAssertEqual(parse("deploy midnight").dueTimeString, "00:00")
    }

    func testDateAndTimeCombine() {
        let p = parse("buy milk tomorrow 5pm")
        XCTAssertEqual(p.title, "Buy milk")
        XCTAssertEqual(p.dueDateString, "2026-07-02")
        XCTAssertEqual(p.dueTimeString, "17:00")
    }

    func testBareTimeMeansTodayEvenWhenPassed() {
        // Now is 10:00; grove keeps a passed bare time on today.
        XCTAssertEqual(parse("standup 9a").dueDateString, "2026-07-01")
    }

    // MARK: - Time ranges

    func testRangesKeepTheStartTime() {
        // Cove divergence: no calendar events, so the end time is dropped
        // but the whole range span still leaves the title.
        let p = parse("dinner 7-9pm")
        XCTAssertEqual(p.title, "Dinner")
        XCTAssertEqual(p.dueTimeString, "19:00")
        XCTAssertEqual(parse("meeting 3-4:30pm").dueTimeString, "15:00")
        XCTAssertEqual(parse("brunch 11am-1pm").dueTimeString, "11:00")
        XCTAssertEqual(parse("workshop 2 to 4pm").dueTimeString, "14:00")
    }

    func testPlainRangesWithoutMeridiemAreNotTimes() {
        let p = parse("read pages 10-20")
        XCTAssertNil(p.dueTimeString)
        XCTAssertEqual(p.title, "Read pages 10-20")
    }

    // MARK: - Recurrence

    func testEveryWeekdaySet() {
        let p = parse("gym every mon wed 6a")
        XCTAssertEqual(p.title, "Gym")
        XCTAssertEqual(
            p.recurrence,
            RecurrenceRule(frequency: .weekly, byWeekday: [2, 4]))
        XCTAssertEqual(p.dueTimeString, "06:00")
        // Now is Wednesday July 1 → first occurrence is today.
        XCTAssertEqual(p.dueDateString, "2026-07-01")
    }

    func testEveryNUnits() {
        let p = parse("doctor every 2 weeks")
        XCTAssertEqual(p.title, "Doctor")
        XCTAssertEqual(p.recurrence, RecurrenceRule(frequency: .weekly, interval: 2))
        XCTAssertEqual(p.dueDateString, "2026-07-01")
    }

    func testSimpleRecurrenceForms() {
        XCTAssertEqual(
            parse("journal every day").recurrence,
            RecurrenceRule(frequency: .daily))
        XCTAssertEqual(
            parse("stretch daily").recurrence,
            RecurrenceRule(frequency: .daily))
        XCTAssertEqual(
            parse("rent every month").recurrence,
            RecurrenceRule(frequency: .monthly))
        XCTAssertEqual(
            parse("renew domain every year").recurrence,
            RecurrenceRule(frequency: .yearly))
        XCTAssertEqual(parse("standup every weekday").recurrence, .everyWeekday)
    }

    func testCommaAndSeparatedWeekdayLists() {
        XCTAssertEqual(
            parse("gym every mon, wed and fri").recurrence,
            RecurrenceRule(frequency: .weekly, byWeekday: [2, 4, 6]))
    }

    func testWeekdayRecurrenceStartsOnNextMatchingDay() {
        // Now is Wednesday; from {mon, fri} the soonest is Friday.
        XCTAssertEqual(parse("gym every mon fri").dueDateString, "2026-07-03")
    }

    // MARK: - Title cleanup

    func testStripsDanglingConnectors() {
        XCTAssertEqual(
            parse("dentist appointment on friday").title,
            "Dentist appointment")
        XCTAssertEqual(parse("meeting at 3pm").title, "Meeting")
    }

    func testConsumedMidSentenceTokensLeaveTheTitle() {
        // Grove parity: spans anywhere in the sentence are consumed, so a
        // second date word is removed from the title even though the first
        // one won the date slot.
        XCTAssertEqual(parse("plan friday party tmr").title, "Plan party")
        XCTAssertEqual(parse("plan friday party tmr").dueDateString, "2026-07-02")
    }

    func testHashtagsAreNotAFeature() {
        // Cove divergence: no lists, so a hashtag is just title text.
        XCTAssertEqual(parse("buy eggs #groceries").title, "Buy eggs #groceries")
    }

    // MARK: - Markdown line

    func testMarkdownLineRoundTrip() {
        XCTAssertEqual(
            parse("get bread 3p tmr").markdownLine,
            "- [ ] Get bread @due(2026-07-02 15:00)")
        XCTAssertEqual(
            parse("laundry every sun 6p").markdownLine,
            "- [ ] Laundry @due(2026-07-05 18:00) @repeat(every sunday)")
        XCTAssertEqual(
            parse("doctor every 2 weeks").markdownLine,
            "- [ ] Doctor @due(2026-07-01) @repeat(every 2 weeks)")
    }

    // MARK: - Undated capture (list items)

    /// The Lists screen passes `defaultingToToday: false`, so an item with
    /// no date word stays undated instead of landing on today.
    private func parseUndated(_ input: String) -> TaskDraft {
        QuickTaskParser.parse(
            input, now: now, timeZone: calendar.timeZone,
            defaultingToToday: false)
    }

    func testUndatedListItemStaysUndated() {
        let draft = parseUndated("milk")
        XCTAssertEqual(draft.title, "Milk")
        XCTAssertNil(draft.dueDateString)
        XCTAssertNil(draft.dueTimeString)
    }

    func testUndatedListItemMarkdownLineHasNoDueTag() {
        XCTAssertEqual(parseUndated("milk").markdownLine, "- [ ] Milk")
    }

    func testAListItemThatNamesADateKeepsIt() {
        let draft = parseUndated("order cake fri 3pm")
        XCTAssertEqual(draft.title, "Order cake")
        XCTAssertEqual(draft.dueDateString, "2026-07-03")
        XCTAssertEqual(draft.dueTimeString, "15:00")
        XCTAssertEqual(
            draft.markdownLine,
            "- [ ] Order cake @due(2026-07-03 15:00)")
    }

    func testARecurringListItemStillResolvesADate() {
        // A repeat rule implies its first occurrence, so the item is dated.
        XCTAssertEqual(
            parseUndated("rent monthly").markdownLine,
            "- [ ] Rent @due(2026-07-01) @repeat(monthly)")
    }

    func testDroppingTheDateFromADraftDropsTimeAndRepeat() {
        // What the sheet's date toggle does: the tags live inside and after
        // `@due`, so they can't outlive it.
        var draft = parse("laundry every sun 6p")
        draft.dueDateString = nil
        draft.dueTimeString = nil
        draft.recurrence = nil
        XCTAssertEqual(draft.markdownLine, "- [ ] Laundry")
    }

    // MARK: - Bounds

    /// The count in "in N weeks" is multiplied by seven, and the preview
    /// re-parses on every keystroke — an unclamped one would trap the
    /// process mid-sentence rather than produce a date.
    func testHugeRelativeCountsAreClampedRatherThanOverflowing() {
        let draft = parse("pay rent in 9223372036854775807 weeks")
        XCTAssertEqual(draft.title, "Pay rent")
        XCTAssertEqual(
            draft.dueDateString,
            parse("pay rent in \(QuickTaskParser.maximumRelativeUnits) weeks")
                .dueDateString)
    }

    func testHugeRecurrenceIntervalIsClamped() {
        XCTAssertEqual(
            parse("water plants every 9223372036854775807 weeks").recurrence?.interval,
            RecurrenceRule.maximumInterval)
    }
}
