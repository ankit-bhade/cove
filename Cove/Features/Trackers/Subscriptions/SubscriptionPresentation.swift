import Foundation

/// How a subscription is worded on screen. Pure and tested against a fixed
/// `now`, the way `TaskPresentation` is.
///
/// The stored `@cost(15.49 USD)` is a file format; everything here formats it
/// in the reader's own locale, which is the same split `DueDescription` makes
/// for a stored `YYYY-MM-DD`.
enum SubscriptionPresentation {

    /// An amount in the reader's locale, with the currency's own symbol and
    /// fraction digits.
    static func money(
        _ amount: Decimal,
        currencyCode: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        amount.formatted(
            .currency(code: currencyCode).locale(locale))
    }

    static func money(_ money: Money, locale: Locale = .autoupdatingCurrent) -> String {
        self.money(
            money.amount, currencyCode: money.currencyCode, locale: locale)
    }

    /// The line under a subscription's name: what it costs, how often, and
    /// when it next lands — or why it doesn't.
    ///
    /// A paused or cancelled charge says so instead of naming a next date it
    /// will never reach.
    static func summary(
        for subscription: Subscription,
        on today: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let cost = money(subscription.cost, locale: locale)
        let cycle = subscription.cycle.displayName.lowercased()
        guard subscription.status == .active else {
            return "\(cost) · \(cycle) · \(subscription.status.displayName)"
        }
        guard
            let next = SubscriptionMath.nextChargeDateString(
                for: subscription, on: today, timeZone: timeZone)
        else {
            return "\(cost) · \(cycle)"
        }
        return
            "\(cost) · \(cycle) · \(renewal(on: next, today: today, timeZone: timeZone, locale: locale))"
    }

    /// "Renews today", "Renews tomorrow", "Renews in 4 days", "Renews Nov 2".
    ///
    /// The near dates are named rather than dated for the same reason the task
    /// rows say "Today" — a date a reader has to convert into a distance is a
    /// date they have to think about.
    static func renewal(
        on dateString: String,
        today: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let todayString = SubscriptionMath.dateString(from: today, timeZone: timeZone)
        guard let days = SubscriptionMath.daysBetween(
            todayString, dateString, timeZone: timeZone)
        else { return "Renews \(dateString)" }

        switch days {
        case ..<0: return "Overdue"
        case 0: return "Renews today"
        case 1: return "Renews tomorrow"
        case 2...6: return "Renews in \(days) days"
        default:
            guard let date = SubscriptionMath.date(
                from: dateString, timeZone: timeZone)
            else { return "Renews \(dateString)" }
            var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            if days > 300 { style = style.year() }
            return "Renews \(date.formatted(style.locale(locale)))"
        }
    }

    /// A charge that lands within the week reads as soon; that is the only
    /// thing a subscription row raises its voice for, which is the same rule
    /// the task rows follow for lateness.
    static func isImminent(
        _ dateString: String,
        today: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Bool {
        let todayString = SubscriptionMath.dateString(from: today, timeZone: timeZone)
        guard let days = SubscriptionMath.daysBetween(
            todayString, dateString, timeZone: timeZone)
        else { return false }
        return days >= 0 && days <= 6
    }

    /// "3 subscriptions · $94.20/mo" — the caption under the tracker's name on
    /// the Trackers hub.
    ///
    /// The amount appears only when every charge is in one currency. It used
    /// to show the leading currency's monthly total beside a count of *all*
    /// the subscriptions, which reads as one figure covering the other — and
    /// nothing is ever converted, so it never was. A hub row is one line and
    /// has no room for a total per currency, so a mixed vault gets the count
    /// alone and the tracker's own screen reports the currencies separately.
    static func hubCaption(
        for subscriptions: [Subscription],
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let active = subscriptions.filter(\.countsTowardSpending)
        guard !active.isEmpty else { return "Nothing tracked yet" }
        let count = active.count
        let noun = count == 1 ? "subscription" : "subscriptions"
        let totals = SubscriptionMath.totals(for: active)
        guard totals.count == 1, let only = totals.first else {
            return "\(count) \(noun)"
        }
        let monthly = money(
            only.monthly, currencyCode: only.currencyCode, locale: locale)
        return "\(count) \(noun) · \(monthly)/mo"
    }
}
