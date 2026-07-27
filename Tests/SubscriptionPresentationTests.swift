import XCTest

@testable import Cove

/// The wording, against a fixed `now` and a fixed locale so nothing depends on
/// the machine running the suite.
final class SubscriptionPresentationTests: XCTestCase {

    private let zone = TimeZone(identifier: "America/New_York")!
    private let locale = Locale(identifier: "en_US")

    private func day(_ string: String) -> Date {
        SubscriptionMath.date(from: string, timeZone: zone)!
    }

    private func subscription(
        _ name: String = "Netflix",
        _ amount: String = "15.49",
        _ cycle: BillingCycle = .monthly,
        since: String = "2024-03-04",
        currency: String = "USD",
        status: SubscriptionStatus = .active
    ) -> Subscription {
        Subscription(
            fileURL: URL(fileURLWithPath: "/vault/Subscriptions.md"),
            lineNumber: 0,
            name: name,
            cost: Money(amount: Decimal(string: amount)!, currencyCode: currency),
            cycle: cycle,
            firstChargeDateString: since,
            status: status)
    }

    // MARK: - Renewal wording

    func testNearDatesAreNamedRatherThanDated() {
        let today = day("2026-07-27")
        XCTAssertEqual(
            SubscriptionPresentation.renewal(
                on: "2026-07-27", today: today, timeZone: zone, locale: locale),
            "Renews today")
        XCTAssertEqual(
            SubscriptionPresentation.renewal(
                on: "2026-07-28", today: today, timeZone: zone, locale: locale),
            "Renews tomorrow")
        XCTAssertEqual(
            SubscriptionPresentation.renewal(
                on: "2026-07-31", today: today, timeZone: zone, locale: locale),
            "Renews in 4 days")
    }

    func testFurtherDatesAreDated() {
        XCTAssertEqual(
            SubscriptionPresentation.renewal(
                on: "2026-11-02",
                today: day("2026-07-27"),
                timeZone: zone,
                locale: locale),
            "Renews Nov 2")
    }

    /// A date more than a year out needs its year, or "Renews Mar 4" is
    /// ambiguous with the one three months away.
    func testDistantDatesCarryTheirYear() {
        XCTAssertTrue(
            SubscriptionPresentation.renewal(
                on: "2028-02-29",
                today: day("2026-07-27"),
                timeZone: zone,
                locale: locale
            ).contains("2028"))
    }

    // MARK: - Imminence

    func testAChargeThisWeekIsImminentAndOneNextMonthIsNot() {
        let today = day("2026-07-27")
        XCTAssertTrue(
            SubscriptionPresentation.isImminent(
                "2026-07-31", today: today, timeZone: zone))
        XCTAssertFalse(
            SubscriptionPresentation.isImminent(
                "2026-09-01", today: today, timeZone: zone))
    }

    // MARK: - Row summary

    func testSummaryNamesCostCycleAndRenewal() {
        XCTAssertEqual(
            SubscriptionPresentation.summary(
                for: subscription(),
                on: day("2026-08-01"),
                timeZone: zone,
                locale: locale),
            "$15.49 · monthly · Renews in 3 days")
    }

    /// A paused charge has no next date it will ever reach, so it says what it
    /// is instead of naming one.
    func testPausedSummarySaysSoRatherThanNamingADate() {
        let summary = SubscriptionPresentation.summary(
            for: subscription(status: .paused),
            on: day("2026-07-27"),
            timeZone: zone,
            locale: locale)
        XCTAssertEqual(summary, "$15.49 · monthly · Paused")
        XCTAssertFalse(summary.contains("Renews"))
    }

    func testCancelledSummarySaysSo() {
        XCTAssertTrue(
            SubscriptionPresentation.summary(
                for: subscription(status: .cancelled),
                on: day("2026-07-27"),
                timeZone: zone,
                locale: locale
            ).hasSuffix("Cancelled"))
    }

    func testYearlyCycleIsWordedInTheSummary() {
        XCTAssertTrue(
            SubscriptionPresentation.summary(
                for: subscription("Domain", "14.00", .yearly, since: "2022-11-02"),
                on: day("2026-07-27"),
                timeZone: zone,
                locale: locale
            ).contains("yearly"))
    }

    // MARK: - Hub caption

    func testHubCaptionCountsActiveAndLeadsWithMonthlySpend() {
        XCTAssertEqual(
            SubscriptionPresentation.hubCaption(
                for: [
                    subscription(),
                    subscription("Domain", "120.00", .yearly, since: "2022-11-02"),
                ],
                locale: locale),
            "2 subscriptions · $25.49/mo")
    }

    func testHubCaptionIgnoresPausedCharges() {
        XCTAssertEqual(
            SubscriptionPresentation.hubCaption(
                for: [
                    subscription(),
                    subscription("Spotify", "11.99", status: .paused),
                ],
                locale: locale),
            "1 subscription · $15.49/mo")
    }

    /// The caption used to count every charge and then print the *leading*
    /// currency's monthly total beside it, which reads as one figure covering
    /// the other. Nothing is ever converted, so it never was. A mixed vault
    /// gets the count alone.
    func testHubCaptionOmitsTheAmountWhenCurrenciesAreMixed() {
        XCTAssertEqual(
            SubscriptionPresentation.hubCaption(
                for: [
                    subscription(),
                    subscription("Fastmail", "5.00", currency: "EUR"),
                ],
                locale: locale),
            "2 subscriptions")
    }

    func testHubCaptionWithNothingActive() {
        XCTAssertEqual(
            SubscriptionPresentation.hubCaption(
                for: [subscription(status: .cancelled)], locale: locale),
            "Nothing tracked yet")
    }

    // MARK: - Money

    func testMoneyFormatsInTheReadersLocaleNotTheFileFormat() {
        XCTAssertEqual(
            SubscriptionPresentation.money(
                Decimal(string: "1450")!, currencyCode: "USD", locale: locale),
            "$1,450.00")
    }
}
