import XCTest

@testable import Cove

/// Normalization, occurrences, and totals, against a fixed `now` so nothing
/// depends on the day the suite runs.
final class SubscriptionMathTests: XCTestCase {

    private let zone = TimeZone(identifier: "America/New_York")!

    private func day(_ string: String) -> Date {
        SubscriptionMath.date(from: string, timeZone: zone)!
    }

    private func subscription(
        _ name: String,
        _ amount: String,
        _ cycle: BillingCycle = .monthly,
        since: String,
        currency: String = "USD",
        status: SubscriptionStatus = .active,
        category: String? = nil,
        line: Int = 0
    ) -> Subscription {
        Subscription(
            fileURL: URL(fileURLWithPath: "/vault/Subscriptions.md"),
            lineNumber: line,
            name: name,
            cost: Money(
                amount: Decimal(string: amount)!, currencyCode: currency),
            cycle: cycle,
            firstChargeDateString: since,
            status: status,
            category: category)
    }

    // MARK: - Next charge

    func testNextChargeIsTheFirstOccurrenceOnOrAfterToday() {
        let netflix = subscription("Netflix", "15.49", since: "2024-03-04")
        XCTAssertEqual(
            SubscriptionMath.nextChargeDateString(
                for: netflix, on: day("2026-07-27"), timeZone: zone),
            "2026-08-04")
    }

    /// A charge falling today is the next charge, not a missed one.
    func testAChargeDueTodayIsTheNextCharge() {
        let netflix = subscription("Netflix", "15.49", since: "2024-03-04")
        XCTAssertEqual(
            SubscriptionMath.nextChargeDateString(
                for: netflix, on: day("2026-08-04"), timeZone: zone),
            "2026-08-04")
    }

    func testASubscriptionStartingInTheFutureChargesOnItsFirstDate() {
        let future = subscription("Later", "5.00", since: "2026-12-01")
        XCTAssertEqual(
            SubscriptionMath.nextChargeDateString(
                for: future, on: day("2026-07-27"), timeZone: zone),
            "2026-12-01")
    }

    /// The trap the anchored arithmetic exists for: a charge on the 31st must
    /// not walk backwards to the 28th the first time it passes February.
    func testMonthEndAnchorDoesNotWalkBackwards() {
        let rent = subscription("Rent", "1450.00", since: "2025-01-31")
        XCTAssertEqual(
            SubscriptionMath.chargeDateStrings(
                for: rent,
                from: "2025-01-01",
                through: "2025-05-31",
                timeZone: zone),
            ["2025-01-31", "2025-02-28", "2025-03-31", "2025-04-30", "2025-05-31"])
    }

    /// A yearly charge anchored to leap day returns to leap day when one
    /// exists rather than being pinned to the 28th forever.
    func testLeapDayAnchorReturnsToLeapDay() {
        let leap = subscription("Leap", "9.00", .yearly, since: "2024-02-29")
        XCTAssertEqual(
            SubscriptionMath.chargeDateStrings(
                for: leap,
                from: "2025-01-01",
                through: "2028-12-31",
                timeZone: zone),
            ["2025-02-28", "2026-02-28", "2027-02-28", "2028-02-29"])
    }

    func testChargesAcrossADaylightSavingTransition() {
        // US DST springs forward on 2026-03-08.
        let daily = subscription(
            "Daily", "1.00", BillingCycle(frequency: .daily), since: "2026-03-06")
        XCTAssertEqual(
            SubscriptionMath.chargeDateStrings(
                for: daily,
                from: "2026-03-06",
                through: "2026-03-10",
                timeZone: zone),
            [
                "2026-03-06", "2026-03-07", "2026-03-08", "2026-03-09",
                "2026-03-10",
            ])
    }

    // MARK: - Normalization

    func testMonthlyCycleNormalizesExactly() {
        let netflix = subscription("Netflix", "15.49", since: "2024-03-04")
        XCTAssertEqual(
            SubscriptionMath.monthlyEquivalent(netflix), Decimal(string: "15.49"))
        XCTAssertEqual(
            SubscriptionMath.yearlyEquivalent(netflix),
            Decimal(string: "185.88"))
    }

    func testYearlyCycleSpreadsAcrossTwelveMonths() {
        let domain = subscription("Domain", "120.00", .yearly, since: "2022-11-02")
        XCTAssertEqual(
            SubscriptionMath.monthlyEquivalent(domain), Decimal(10))
        XCTAssertEqual(SubscriptionMath.yearlyEquivalent(domain), Decimal(120))
    }

    func testQuarterlyCycleIsFourChargesAYear() {
        let quarterly = subscription("Q", "30.00", .quarterly, since: "2024-01-01")
        XCTAssertEqual(SubscriptionMath.yearlyEquivalent(quarterly), Decimal(120))
        XCTAssertEqual(SubscriptionMath.monthlyEquivalent(quarterly), Decimal(10))
    }

    /// Week and day cycles have no whole-number answer, so their figures are
    /// averages — and the screen has to be able to say so.
    func testWeeklyCycleIsAveragedAndReportedAsInexact() {
        let weekly = subscription("W", "7.00", .weekly, since: "2024-01-01")
        let yearly = SubscriptionMath.yearlyEquivalent(weekly)
        XCTAssertGreaterThan(yearly, Decimal(365))
        XCTAssertLessThan(yearly, Decimal(366))
        XCTAssertFalse(SubscriptionMath.totalsAreExact([weekly]))
    }

    func testMonthAndYearCyclesTogetherAreExact() {
        XCTAssertTrue(
            SubscriptionMath.totalsAreExact([
                subscription("A", "1.00", since: "2024-01-01"),
                subscription("B", "1.00", .yearly, since: "2024-01-01"),
            ]))
    }

    /// A paused subscription is not spending, so an inexact one that is paused
    /// must not make the totals read as averaged.
    func testPausedSubscriptionsDoNotAffectExactness() {
        XCTAssertTrue(
            SubscriptionMath.totalsAreExact([
                subscription("A", "1.00", since: "2024-01-01"),
                subscription(
                    "W", "7.00", .weekly, since: "2024-01-01", status: .paused),
            ]))
    }

    // MARK: - Totals

    func testTotalsExcludePausedAndCancelled() {
        let totals = SubscriptionMath.totals(for: [
            subscription("A", "10.00", since: "2024-01-01"),
            subscription("B", "5.00", since: "2024-01-01", status: .paused),
            subscription("C", "3.00", since: "2024-01-01", status: .cancelled),
        ])
        XCTAssertEqual(totals.count, 1)
        XCTAssertEqual(totals[0].monthly, Decimal(10))
        XCTAssertEqual(totals[0].subscriptionCount, 1)
    }

    /// Currencies are never converted, so two of them are two totals.
    func testMixedCurrenciesProduceSeparateTotals() {
        let totals = SubscriptionMath.totals(for: [
            subscription("A", "10.00", since: "2024-01-01", currency: "USD"),
            subscription("B", "99.00", since: "2024-01-01", currency: "GBP"),
        ])
        XCTAssertEqual(totals.map(\.currencyCode), ["GBP", "USD"])
        XCTAssertEqual(totals[0].monthly, Decimal(99))
        XCTAssertEqual(totals[1].monthly, Decimal(10))
    }

    // MARK: - Spend bars

    func testSpendBarsAreRankedByMonthlyCost() {
        let bars = SubscriptionMath.spendBars(
            for: [
                subscription("Small", "1.00", since: "2024-01-01"),
                subscription("Big", "120.00", .yearly, since: "2024-01-01", line: 1),
                subscription("Medium", "5.00", since: "2024-01-01", line: 2),
            ],
            currencyCode: "USD")
        XCTAssertEqual(bars.map(\.label), ["Big", "Medium", "Small"])
        XCTAssertEqual(bars.first?.monthly, Decimal(10))
    }

    func testSpendBarsExcludePausedAndOtherCurrencies() {
        let bars = SubscriptionMath.spendBars(
            for: [
                subscription("Active", "5.00", since: "2024-01-01"),
                subscription(
                    "Paused", "50.00", since: "2024-01-01", status: .paused,
                    line: 1),
                subscription(
                    "Pounds", "99.00", since: "2024-01-01", currency: "GBP",
                    line: 2),
            ],
            currencyCode: "USD")
        XCTAssertEqual(bars.map(\.label), ["Active"])
    }

    /// The bars sit under a total, so a dropped tail would make them visibly
    /// fail to add up to it. Past the limit the rest is pooled, not discarded.
    func testSpendBarsPoolTheTailRatherThanDroppingIt() {
        let many = (1...10).map { index in
            subscription(
                "Sub \(index)",
                "\(index).00",
                since: "2024-01-01",
                line: index)
        }
        let bars = SubscriptionMath.spendBars(
            for: many, currencyCode: "USD", limit: 4)
        XCTAssertEqual(bars.count, 4)
        XCTAssertEqual(bars.map(\.label), ["Sub 10", "Sub 9", "Sub 8", "7 more"])
        XCTAssertTrue(bars.last?.isRemainder == true)
        // 1 through 7 pooled.
        XCTAssertEqual(bars.last?.monthly, Decimal(28))
        XCTAssertEqual(
            bars.reduce(0) { $0 + $1.monthly },
            Decimal(55))
    }

    func testSpendBarsBelowTheLimitCarryNoRemainder() {
        let bars = SubscriptionMath.spendBars(
            for: [
                subscription("A", "1.00", since: "2024-01-01"),
                subscription("B", "2.00", since: "2024-01-01", line: 1),
            ],
            currencyCode: "USD",
            limit: 8)
        XCTAssertEqual(bars.count, 2)
        XCTAssertFalse(bars.contains { $0.isRemainder })
    }

    // MARK: - Upcoming

    func testUpcomingChargesAreWithinTheWindowAndSortedSoonestFirst() {
        let charges = SubscriptionMath.upcomingCharges(
            for: [
                subscription("Netflix", "15.49", since: "2024-03-04"),
                subscription("Rent", "1450.00", since: "2021-06-01", line: 1),
                subscription(
                    "Far", "1.00", .yearly, since: "2024-12-25", line: 2),
            ],
            within: 14,
            on: day("2026-07-27"),
            timeZone: zone)
        XCTAssertEqual(
            charges.map { "\($0.subscription.name) \($0.dateString)" },
            ["Rent 2026-08-01", "Netflix 2026-08-04"])
    }

    func testUpcomingChargesExcludePausedSubscriptions() {
        let charges = SubscriptionMath.upcomingCharges(
            for: [
                subscription(
                    "Netflix", "15.49", since: "2024-03-04", status: .paused)
            ],
            within: 30,
            on: day("2026-07-27"),
            timeZone: zone)
        XCTAssertTrue(charges.isEmpty)
    }

    // MARK: - Bounds

    /// A daily subscription really does have hundreds of charges a year, so
    /// the ceiling has to be above that rather than a tight cap.
    func testDailyChargesAcrossAYearAreNotTruncated() {
        let daily = subscription(
            "Daily", "1.00", BillingCycle(frequency: .daily), since: "2026-01-01")
        let charges = SubscriptionMath.chargeDateStrings(
            for: daily,
            from: "2026-01-01",
            through: "2026-12-31",
            timeZone: zone)
        XCTAssertEqual(charges.count, 365)
    }

    func testAnInvertedRangeYieldsNothing() {
        let netflix = subscription("Netflix", "15.49", since: "2024-03-04")
        XCTAssertTrue(
            SubscriptionMath.chargeDateStrings(
                for: netflix,
                from: "2026-08-01",
                through: "2026-07-01",
                timeZone: zone
            ).isEmpty)
    }
}
