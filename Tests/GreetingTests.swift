import XCTest
@testable import Cove

final class GreetingTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int) -> Date {
        calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour))!
    }

    private func text(_ date: Date, name: String? = nil) -> String {
        Greeting.text(for: date, name: name, calendar: calendar)
    }

    func testEveryHourProducesAGreeting() {
        for hour in 0..<24 {
            XCTAssertFalse(
                text(date(2026, 7, 19, hour: hour)).isEmpty,
                "hour \(hour) produced no greeting")
        }
    }

    func testNameIsInterpolatedWhenSet() {
        for hour in 0..<24 {
            let greeting = text(date(2026, 7, 19, hour: hour), name: "Ankit")
            XCTAssertTrue(greeting.contains("Ankit"), "hour \(hour): \(greeting)")
            XCTAssertFalse(greeting.contains("%@"), "hour \(hour): \(greeting)")
        }
    }

    func testBlankNameFallsBackToTheImpersonalPhrase() {
        let moment = date(2026, 7, 19, hour: 9)
        let plain = text(moment)
        XCTAssertEqual(text(moment, name: ""), plain)
        XCTAssertEqual(text(moment, name: "   "), plain)
    }

    func testNameIsTrimmed() {
        let greeting = text(date(2026, 7, 19, hour: 9), name: "  Ankit \n")
        XCTAssertTrue(greeting.contains("Ankit"))
        XCTAssertFalse(greeting.contains("  Ankit"))
    }

    func testGreetingIsStableWithinAStretchOfTheSameDay() {
        // The browser re-renders every minute; the phrase must not reshuffle.
        XCTAssertEqual(
            text(date(2026, 7, 19, hour: 9)),
            text(date(2026, 7, 19, hour: 10)))
    }

    func testGreetingChangesAcrossStretches() {
        let morning = text(date(2026, 7, 19, hour: 9))
        let evening = text(date(2026, 7, 19, hour: 19))
        XCTAssertNotEqual(morning, evening)
    }

    func testMorningAndEveningUseTheExpectedFamiliarPhrases() {
        // The seeded pick lands on some phrase in the stretch; assert the
        // stretch itself is chosen correctly by checking membership.
        let morningPhrases = Greeting.stretches.first { $0.startHour == 8 }!.phrases
        XCTAssertTrue(morningPhrases.map(\.plain).contains(text(date(2026, 7, 19, hour: 8))))

        let nightPhrases = Greeting.stretches.first { $0.startHour == 21 }!.phrases
        XCTAssertTrue(nightPhrases.map(\.plain).contains(text(date(2026, 7, 19, hour: 23))))
    }

    func testStretchesAreOrderedAndCoverMidnight() {
        XCTAssertEqual(Greeting.stretches.first?.startHour, 0)
        let starts = Greeting.stretches.map(\.startHour)
        XCTAssertEqual(starts, starts.sorted())
        XCTAssertTrue(Greeting.stretches.allSatisfy { !$0.phrases.isEmpty })
    }
}
