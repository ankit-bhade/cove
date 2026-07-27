import Foundation

/// Everything the subscription tracker computes: when the next charge lands,
/// what a cycle costs per month and per year, and which charges fall inside a
/// window.
///
/// Pure and tested against a fixed `now`, the way `TaskPresentation` is. Dates
/// are Gregorian `YYYY-MM-DD` strings throughout, so a lexicographic comparison
/// is a chronological one and the arithmetic never depends on the reader's
/// system calendar.
///
/// **No currency is ever converted.** Conversion needs a rate, a rate needs a
/// network, and the vault has no backend. Every total is per currency instead;
/// a vault that uses one currency sees one set of figures.
enum SubscriptionMath {

    /// Ceiling on any occurrence walk.
    ///
    /// A daily subscription has one charge a day, so a month-long window is
    /// already thirty of them and this is not a tight bound — it exists so a
    /// rule that somehow stops advancing returns what it has instead of
    /// spinning, which is the same reasoning behind `RecurrenceRule`'s own
    /// search ceiling.
    static let maximumProjectedOccurrences = 512

    // MARK: - Occurrences

    /// The first charge on or after `today`.
    ///
    /// `RecurrenceRule.nextDueDateString(after:anchoredTo:)` is strictly after
    /// its reference, so the reference is the day *before* today — a charge
    /// falling today is the next charge, not a missed one.
    static func nextChargeDateString(
        for subscription: Subscription,
        on today: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard let yesterday = addingDays(-1, to: dateString(from: today, timeZone: timeZone), timeZone: timeZone)
        else { return nil }
        return subscription.cycle.rule.nextDueDateString(
            after: yesterday,
            anchoredTo: subscription.firstChargeDateString,
            timeZone: timeZone)
    }

    /// Every charge in `start...end`, inclusive, in order.
    static func chargeDateStrings(
        for subscription: Subscription,
        from start: String,
        through end: String,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [String] {
        guard start <= end,
            var reference = addingDays(-1, to: start, timeZone: timeZone)
        else { return [] }

        var results: [String] = []
        while results.count < maximumProjectedOccurrences {
            guard
                let next = subscription.cycle.rule.nextDueDateString(
                    after: reference,
                    anchoredTo: subscription.firstChargeDateString,
                    timeZone: timeZone),
                next <= end
            else { break }
            results.append(next)
            reference = next
        }
        return results
    }

    // MARK: - Normalization

    /// What this subscription costs in an average month.
    ///
    /// Month and year cycles are exact — a monthly subscription's monthly cost
    /// is its own price. Day and week cycles have no whole-number answer and
    /// use the mean Gregorian year, so their figures are averages;
    /// `totalsAreExact` is what lets a screen say so.
    static func monthlyEquivalent(_ subscription: Subscription) -> Decimal {
        subscription.cost.amount * subscription.cycle.occurrencesPerYear / 12
    }

    static func yearlyEquivalent(_ subscription: Subscription) -> Decimal {
        subscription.cost.amount * subscription.cycle.occurrencesPerYear
    }

    /// Whether every cycle present divides a year exactly, so the monthly
    /// figures are precise rather than averaged.
    static func totalsAreExact(_ subscriptions: [Subscription]) -> Bool {
        subscriptions
            .filter(\.countsTowardSpending)
            .allSatisfy { $0.cycle.normalizesExactly }
    }

    // MARK: - Totals

    struct CurrencyTotal: Identifiable, Hashable, Sendable {
        let currencyCode: String
        let monthly: Decimal
        let yearly: Decimal
        let subscriptionCount: Int

        var id: String { currencyCode }
    }

    /// One total per currency present, largest yearly spend first. Paused and
    /// cancelled subscriptions are excluded.
    static func totals(for subscriptions: [Subscription]) -> [CurrencyTotal] {
        let counted = subscriptions.filter(\.countsTowardSpending)
        let byCurrency = Dictionary(grouping: counted) { $0.cost.currencyCode }
        return
            byCurrency
            .map { code, items in
                CurrencyTotal(
                    currencyCode: code,
                    monthly: items.reduce(0) { $0 + monthlyEquivalent($1) },
                    yearly: items.reduce(0) { $0 + yearlyEquivalent($1) },
                    subscriptionCount: items.count)
            }
            .sorted {
                $0.yearly == $1.yearly
                    ? $0.currencyCode < $1.currencyCode
                    : $0.yearly > $1.yearly
            }
    }

    // MARK: - Spend breakdown

    struct SpendBar: Identifiable, Hashable, Sendable {
        let label: String
        let monthly: Decimal
        /// The pooled tail, when there were more charges than the chart shows.
        let isRemainder: Bool

        var id: String { isRemainder ? "\u{0}remainder" : label }
    }

    /// The largest monthly charges in one currency, biggest first, with
    /// everything past `limit` pooled into a single remainder bar.
    ///
    /// This is broken down by *subscription* rather than by category on
    /// purpose. A category breakdown says nothing at all for a vault that
    /// hasn't used categories — and the list already groups by category, so a
    /// chart repeating that grouping would be the second time the screen said
    /// it. "What is costing me the most" is the question a breakdown is for,
    /// and it has an answer either way.
    static func spendBars(
        for subscriptions: [Subscription],
        currencyCode: String,
        limit: Int = 8
    ) -> [SpendBar] {
        guard limit > 0 else { return [] }
        let counted =
            subscriptions
            .filter {
                $0.countsTowardSpending && $0.cost.currencyCode == currencyCode
            }
            .sorted {
                let left = monthlyEquivalent($0)
                let right = monthlyEquivalent($1)
                return left == right
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : left > right
            }
        guard counted.count > limit else {
            return counted.map {
                SpendBar(
                    label: $0.name,
                    monthly: monthlyEquivalent($0),
                    isRemainder: false)
            }
        }

        // Keep one slot for the remainder rather than showing `limit` bars and
        // silently dropping the tail, which would make the bars stop adding up
        // to the total printed directly above them.
        let shown = counted.prefix(limit - 1)
        let rest = counted.dropFirst(limit - 1)
        var bars = shown.map {
            SpendBar(
                label: $0.name,
                monthly: monthlyEquivalent($0),
                isRemainder: false)
        }
        bars.append(
            SpendBar(
                label: "\(rest.count) more",
                monthly: rest.reduce(0) { $0 + monthlyEquivalent($1) },
                isRemainder: true))
        return bars
    }

    // MARK: - Upcoming

    struct UpcomingCharge: Identifiable, Hashable, Sendable {
        let subscription: Subscription
        let dateString: String

        var id: String { "\(subscription.id)@\(dateString)" }
    }

    /// Active charges landing in the next `days` days, today included,
    /// soonest first.
    static func upcomingCharges(
        for subscriptions: [Subscription],
        within days: Int,
        on today: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [UpcomingCharge] {
        let start = dateString(from: today, timeZone: timeZone)
        guard days >= 0, let end = addingDays(days, to: start, timeZone: timeZone)
        else { return [] }

        return
            subscriptions
            .filter(\.countsTowardSpending)
            .flatMap { subscription in
                chargeDateStrings(
                    for: subscription,
                    from: start,
                    through: end,
                    timeZone: timeZone
                )
                .map { UpcomingCharge(subscription: subscription, dateString: $0) }
            }
            .sorted {
                ($0.dateString, $0.subscription.name, $0.subscription.id)
                    < ($1.dateString, $1.subscription.name, $1.subscription.id)
            }
    }

    // MARK: - Date helpers

    static func dateString(
        from date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let parts = TaskCalendar.gregorian(timeZone: timeZone)
            .dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    static func date(
        from string: String,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Date? {
        let calendar = TaskCalendar.gregorian(timeZone: timeZone)
        guard var components = TaskCalendar.dateComponents(from: string),
            components.isValidDate(in: calendar)
        else { return nil }
        // Noon-anchored, so adding days can never be undone by a DST shift.
        components.hour = 12
        return calendar.date(from: components)
    }

    /// Whole days from `start` to `end`, negative when `end` is earlier.
    static func daysBetween(
        _ start: String,
        _ end: String,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Int? {
        guard let from = date(from: start, timeZone: timeZone),
            let to = date(from: end, timeZone: timeZone)
        else { return nil }
        return TaskCalendar.gregorian(timeZone: timeZone)
            .dateComponents([.day], from: from, to: to).day
    }

    private static func addingDays(
        _ days: Int,
        to dateString: String,
        timeZone: TimeZone
    ) -> String? {
        guard let base = date(from: dateString, timeZone: timeZone),
            let shifted = TaskCalendar.gregorian(timeZone: timeZone)
                .date(byAdding: .day, value: days, to: base)
        else { return nil }
        return Self.dateString(from: shifted, timeZone: timeZone)
    }
}
