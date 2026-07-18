import XCTest
@testable import Cove

final class QuickTaskParserTests: XCTestCase {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Saturday 2026-07-18, 10:00 — matches a known weekday layout:
    /// Sun 19th, Mon 20th, … Fri 24th.
    private var saturdayMorning: Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 18, hour: 10))!
    }

    private func parse(_ input: String, now: Date? = nil) -> TaskDraft {
        QuickTaskParser.parse(input, now: now ?? saturdayMorning, calendar: calendar)
    }

    // MARK: - The spec examples

    func testGetBread3pTomorrow() {
        let draft = parse("get bread 3p tmr")
        XCTAssertEqual(draft.title, "Get bread")
        XCTAssertEqual(draft.dueDateString, "2026-07-19")
        XCTAssertEqual(draft.dueTimeString, "15:00")
        XCTAssertNil(draft.recurrence)
        XCTAssertEqual(draft.markdownLine, "- [ ] Get bread @due(2026-07-19 15:00)")
    }

    func testLaundryEverySunday6p() {
        let draft = parse("laundry every sun 6p")
        XCTAssertEqual(draft.title, "Laundry")
        XCTAssertEqual(draft.recurrence, .weekly(weekday: 1))
        XCTAssertEqual(draft.dueTimeString, "18:00")
        XCTAssertEqual(draft.dueDateString, "2026-07-19") // first upcoming Sunday
        XCTAssertEqual(draft.markdownLine,
                       "- [ ] Laundry @due(2026-07-19 18:00) @repeat(every sunday)")
    }

    func testTennisFridayHasNoTime() {
        let draft = parse("tennis fri")
        XCTAssertEqual(draft.title, "Tennis")
        XCTAssertEqual(draft.dueDateString, "2026-07-24")
        XCTAssertNil(draft.dueTimeString)
        XCTAssertNil(draft.recurrence)
        XCTAssertEqual(draft.markdownLine, "- [ ] Tennis @due(2026-07-24)")
    }

    // MARK: - Dates

    func testTodayAbbreviationsAndDefault() {
        XCTAssertEqual(parse("pay rent tdy").dueDateString, "2026-07-18")
        XCTAssertEqual(parse("pay rent today").dueDateString, "2026-07-18")
        // No scheduling tokens at all: due today.
        let bare = parse("pay rent")
        XCTAssertEqual(bare.title, "Pay rent")
        XCTAssertEqual(bare.dueDateString, "2026-07-18")
        XCTAssertNil(bare.dueTimeString)
    }

    func testWeekdayTokenOnItsOwnDayMeansToday() {
        XCTAssertEqual(parse("stretch sat").dueDateString, "2026-07-18")
    }

    func testNextWeekdaySkipsTheSoonestOne() {
        XCTAssertEqual(parse("dentist next fri").dueDateString, "2026-07-31")
        XCTAssertEqual(parse("dentist fri").dueDateString, "2026-07-24")
    }

    func testPastTimePushesImplicitDateForward() {
        // 10:00 now; "9a" already passed, so an implicit today becomes
        // tomorrow, while an explicit "today" stays put.
        XCTAssertEqual(parse("standup 9a").dueDateString, "2026-07-19")
        XCTAssertEqual(parse("standup 11a").dueDateString, "2026-07-18")
        XCTAssertEqual(parse("standup today 9a").dueDateString, "2026-07-18")
        // A weekday matching today with a passed time rolls a week out.
        XCTAssertEqual(parse("standup sat 9a").dueDateString, "2026-07-25")
    }

    // MARK: - Times

    func testTimeFormats() {
        XCTAssertEqual(QuickTaskParser.parseTime("3p"), "15:00")
        XCTAssertEqual(QuickTaskParser.parseTime("6pm"), "18:00")
        XCTAssertEqual(QuickTaskParser.parseTime("11a"), "11:00")
        XCTAssertEqual(QuickTaskParser.parseTime("3:30pm"), "15:30")
        XCTAssertEqual(QuickTaskParser.parseTime("12a"), "00:00")
        XCTAssertEqual(QuickTaskParser.parseTime("12p"), "12:00")
        XCTAssertEqual(QuickTaskParser.parseTime("15:00"), "15:00")
        XCTAssertEqual(QuickTaskParser.parseTime("9:05"), "09:05")
        XCTAssertNil(QuickTaskParser.parseTime("6"))
        XCTAssertNil(QuickTaskParser.parseTime("13pm"))
        XCTAssertNil(QuickTaskParser.parseTime("25:00"))
        XCTAssertNil(QuickTaskParser.parseTime("9:75"))
    }

    func testBareNumberStaysInTitle() {
        let draft = parse("buy 6 eggs tmr")
        XCTAssertEqual(draft.title, "Buy 6 eggs")
        XCTAssertNil(draft.dueTimeString)
    }

    // MARK: - Recurrence

    func testRecurrenceForms() {
        XCTAssertEqual(parse("standup daily 9a").recurrence, .daily)
        XCTAssertEqual(parse("standup every day 9a").recurrence, .daily)
        XCTAssertEqual(parse("standup everyday 9a").recurrence, .daily)
        XCTAssertEqual(parse("standup every weekday 9a").recurrence, .everyWeekday)
        XCTAssertEqual(parse("standup weekdays 9a").recurrence, .everyWeekday)
        XCTAssertEqual(parse("laundry every sunday").recurrence, .weekly(weekday: 1))
    }

    func testDailyRecurrenceStartsTodayUnlessTimePassed() {
        XCTAssertEqual(parse("stretch daily 11a").dueDateString, "2026-07-18")
        XCTAssertEqual(parse("stretch daily 9a").dueDateString, "2026-07-19")
    }

    func testEveryWeekdayStartsOnNextWeekday() {
        // Saturday now → first occurrence is Monday.
        XCTAssertEqual(parse("standup every weekday 9a").dueDateString, "2026-07-20")
    }

    // MARK: - Title handling

    func testSchedulingWordsInsideTitleSurvive() {
        // "friday" mid-sentence isn't consumed; only trailing tokens are.
        let draft = parse("plan friday party tmr")
        XCTAssertEqual(draft.title, "Plan friday party")
        XCTAssertEqual(draft.dueDateString, "2026-07-19")
    }

    func testTokensConsumedInAnyTrailingOrder() {
        let a = parse("laundry every sun 6p")
        let b = parse("laundry 6p every sun")
        XCTAssertEqual(a.title, b.title)
        XCTAssertEqual(a.recurrence, b.recurrence)
        XCTAssertEqual(a.dueTimeString, b.dueTimeString)
        XCTAssertEqual(a.dueDateString, b.dueDateString)
    }

    func testOnlySchedulingTokensYieldEmptyTitle() {
        XCTAssertEqual(parse("tmr 3p").title, "")
    }
}
