import Foundation

/// Everything the subscription tracker computes: when the next charge lands,
/// what a cycle costs per month and per year, and how the charges fall across
/// the coming months.
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
    /// A daily subscription genuinely has ~365 charges in a projected year, so
    /// this is not a tight bound — it exists so a rule that somehow stops
    /// advancing returns what it has instead of spinning, which is the same
    /// reasoning behind `RecurrenceRule`'s own search ceiling.
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

    struct CategoryTotal: Identifiable, Hashable, Sendable {
        /// Nil for lines that sit above every `##` heading.
        let category: String?
        let monthly: Decimal
        let subscriptionCount: Int

        var id: String { category ?? "\u{0}uncategorized" }
        var displayName: String { category ?? "Uncategorized" }
    }

    /// Monthly spend per `##` category within one currency, largest first.
    static func categoryTotals(
        for subscriptions: [Subscription],
        currencyCode: String
    ) -> [CategoryTotal] {
        let counted = subscriptions.filter {
            $0.countsTowardSpending && $0.cost.currencyCode == currencyCode
        }
        let byCategory = Dictionary(grouping: counted) {
            $0.category.map(TaskListDocument.canonicalName)
        }
        return
            byCategory
            .map { _, items in
                CategoryTotal(
                    category: items.first?.category,
                    monthly: items.reduce(0) { $0 + monthlyEquivalent($1) },
                    subscriptionCount: items.count)
            }
            .sorted {
                $0.monthly == $1.monthly
                    ? $0.displayName < $1.displayName
                    : $0.monthly > $1.monthly
            }
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

    // MARK: - Projection

    struct MonthBucket: Identifiable, Hashable, Sendable {
        /// First day of the month, `YYYY-MM-DD`.
        let monthStartDateString: String
        let total: Decimal
        let chargeCount: Int

        var id: String { monthStartDateString }
    }

    /// What each of the next `months` calendar months actually costs, starting
    /// with the month `from` falls in.
    ///
    /// This is the figure a flat monthly average hides: a yearly subscription
    /// contributes nothing to eleven months and its whole price to one. Months
    /// are counted in full, charges already made this month included, because
    /// the question the chart answers is "what does March cost" rather than
    /// "what is left to pay".
    static func monthlyProjection(
        for subscriptions: [Subscription],
        currencyCode: String,
        months: Int,
        from today: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [MonthBucket] {
        guard months > 0 else { return [] }
        let calendar = TaskCalendar.gregorian(timeZone: timeZone)
        let parts = calendar.dateComponents(
            [.year, .month], from: today)
        guard let year = parts.year, let month = parts.month else { return [] }

        let starts: [String] = (0..<months).compactMap { offset in
            let absolute = year * 12 + (month - 1) + offset
            return String(
                format: "%04d-%02d-01", absolute / 12, absolute % 12 + 1)
        }
        guard let first = starts.first, let lastStart = starts.last,
            let end = endOfMonthDateString(for: lastStart, timeZone: timeZone)
        else { return [] }

        let counted = subscriptions.filter {
            $0.countsTowardSpending && $0.cost.currencyCode == currencyCode
        }
        var totals: [String: Decimal] = [:]
        var counts: [String: Int] = [:]
        for subscription in counted {
            for date in chargeDateStrings(
                for: subscription, from: first, through: end, timeZone: timeZone)
            {
                let key = String(date.prefix(7)) + "-01"
                totals[key, default: 0] += subscription.cost.amount
                counts[key, default: 0] += 1
            }
        }
        return starts.map { start in
            MonthBucket(
                monthStartDateString: start,
                total: totals[start] ?? 0,
                chargeCount: counts[start] ?? 0)
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

    private static func endOfMonthDateString(
        for monthStart: String,
        timeZone: TimeZone
    ) -> String? {
        let calendar = TaskCalendar.gregorian(timeZone: timeZone)
        guard let start = date(from: monthStart, timeZone: timeZone),
            let range = calendar.range(of: .day, in: .month, for: start)
        else { return nil }
        return String(monthStart.prefix(8))
            + String(format: "%02d", range.count)
    }
}
