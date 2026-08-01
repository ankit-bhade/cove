import Foundation

/// An amount in one currency, as a subscription note stores it.
///
/// `Decimal`, never `Double`: a binary float cannot hold 15.49, and a total
/// built from a dozen of them drifts by cents in a screen whose entire job is
/// to add money up.
///
/// The currency code is carried rather than assumed, and it is *never*
/// converted — conversion needs a rate, a rate needs a network, and the vault
/// has no backend. Totals are computed per currency instead; a vault that uses
/// one currency, which is the ordinary case, sees one set of figures.
struct Money: Hashable, Sendable {
    let amount: Decimal
    /// Three ASCII letters, upper-cased. Held as a string rather than an enum
    /// because the note is the source of truth and a person may reasonably
    /// write a code Cove has never heard of.
    let currencyCode: String

    init(amount: Decimal, currencyCode: String) {
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
    }

    /// The fixed rendering that goes inside `@cost(...)`: no grouping
    /// separators, always two fraction digits, POSIX locale. This is a file
    /// format, not a display — presentation formats with the user's locale and
    /// currency style, exactly as a stored `YYYY-MM-DD` is formatted for
    /// reading rather than shown raw.
    var tagValue: String {
        "\(Self.canonicalAmountString(amount)) \(currencyCode)"
    }

    static func canonicalAmountString(_ amount: Decimal) -> String {
        amount.formatted(
            .number
                .precision(.fractionLength(2))
                .grouping(.never)
                .locale(Locale(identifier: "en_US_POSIX")))
    }
}

/// Whether a subscription is still being paid for.
///
/// `active` is the absence of a `@status(...)` tag rather than a value written
/// on every line: the overwhelming majority of lines are active, and a tag
/// repeated on all of them is noise in a file meant to be read by hand.
enum SubscriptionStatus: String, CaseIterable, Sendable {
    case active
    case paused
    case cancelled

    /// Only a status Cove writes appears in the file; `active` is implicit.
    var tagValue: String? { self == .active ? nil : rawValue }

    var displayName: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .cancelled: "Cancelled"
        }
    }

    /// Paused and cancelled subscriptions are excluded from every total and
    /// from the upcoming-charge list. They differ only in intent, which is the
    /// user's business rather than the arithmetic's.
    var countsTowardSpending: Bool { self == .active }
}

/// How often a subscription is billed.
///
/// A thin wrapper over `RecurrenceRule` rather than a parallel implementation:
/// the interval clamping, the anchored occurrence arithmetic, and the month-end
/// and leap-day handling are all already there and already tested. What the
/// wrapper adds is a *narrowing* — a weekday set (`every mon wed fri`) is a
/// perfectly good task recurrence and is not a billing cycle, so it cannot be
/// constructed here at all.
struct BillingCycle: Hashable, Sendable {
    /// Guaranteed to carry no weekday set.
    let rule: RecurrenceRule

    init(frequency: RecurrenceRule.Frequency, interval: Int = 1) {
        self.rule = RecurrenceRule(frequency: frequency, interval: interval)
    }

    init?(rule: RecurrenceRule) {
        guard rule.byWeekday.isEmpty else { return nil }
        self.rule = rule
    }

    var frequency: RecurrenceRule.Frequency { rule.frequency }
    var interval: Int { rule.interval }

    static let monthly = BillingCycle(frequency: .monthly)
    static let yearly = BillingCycle(frequency: .yearly)
    static let weekly = BillingCycle(frequency: .weekly)
    static let quarterly = BillingCycle(frequency: .monthly, interval: 3)

    /// The presets a picker offers, in the order they are worth offering.
    static let presets: [BillingCycle] = [
        .monthly,
        .yearly,
        .quarterly,
        .weekly,
        BillingCycle(frequency: .monthly, interval: 6),
    ]

    // MARK: - Tag text

    /// The fixed text inside `@every(...)`, read as the words after "every":
    /// `month`, `year`, `week`, `day`, or `3 months`.
    ///
    /// This is deliberately not `RecurrenceRule.tagText`, which is worded for
    /// `@repeat(...)` and would produce `@every(monthly)` — "every monthly".
    var tagText: String {
        let singular = Self.singularUnit(frequency)
        return interval == 1 ? singular : "\(interval) \(singular)s"
    }

    /// Parses the text inside `@every(...)`.
    ///
    /// Every form `RecurrenceRule` understands is accepted, plus the bare unit
    /// forms `@every(...)` reads naturally — so `month`, `monthly`,
    /// `every month`, `every 1 month`, `3 months`, and `every 3 months` all
    /// read as the same cycle. Widening here cannot change a line's meaning; it
    /// only stops a hand-typed file from being rejected over wording.
    ///
    /// A weekday set parses as a perfectly good `RecurrenceRule` and is then
    /// refused, because it is not a billing cycle.
    init?(tagText: String) {
        let normalized =
            tagText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(
                of: #"[ \t]+"#, with: " ", options: .regularExpression
            )
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        // The adverbs, "every month", "every 3 months" — and weekday sets,
        // which `init?(rule:)` then refuses.
        if let rule = RecurrenceRule(tagText: normalized) {
            self.init(rule: rule)
            return
        }

        // The unit forms. `RecurrenceRule` requires a plural after a count
        // ("every 3 months") and has no bare-unit form at all, so both are
        // handled here.
        var rest = normalized
        if rest.hasPrefix("every ") { rest = String(rest.dropFirst(6)) }
        let words = rest.split(separator: " ").map(String.init)
        switch words.count {
        case 1:
            guard let frequency = Self.units[words[0]] else { return nil }
            self.init(frequency: frequency)
        case 2:
            guard let interval = Int(words[0]), interval >= 1,
                let frequency = Self.units[words[1]]
            else { return nil }
            self.init(frequency: frequency, interval: interval)
        default:
            return nil
        }
    }

    // MARK: - Display

    /// "Monthly", "Yearly", "Every 3 months".
    var displayName: String {
        guard interval == 1 else {
            return "Every \(interval) \(Self.singularUnit(frequency))s"
        }
        switch frequency {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    // MARK: - Normalization

    /// How many times a year this cycle bills.
    ///
    /// Month and year cycles are exact — twelve monthly charges a year,
    /// four quarterly ones — so a monthly subscription's monthly figure is its
    /// own price to the cent. Day and week cycles have no whole-number answer,
    /// so they use the mean Gregorian year (365.25 days) and the figures they
    /// produce are averages. `SubscriptionMath.totalsAreExact` reports which
    /// case a screen is in, so the UI can say so rather than implying a bank
    /// statement will match.
    var occurrencesPerYear: Decimal {
        let interval = Decimal(interval)
        switch frequency {
        case .daily: return Self.daysPerYear / interval
        case .weekly: return Self.daysPerYear / (7 * interval)
        case .monthly: return 12 / interval
        case .yearly: return 1 / interval
        }
    }

    /// Whether this cycle divides a year exactly.
    var normalizesExactly: Bool {
        switch frequency {
        case .monthly, .yearly: true
        case .daily, .weekly: false
        }
    }

    private static let daysPerYear = Decimal(string: "365.25")!

    /// Singular and plural together, so `1 month` and `3 months` are both read
    /// without the count and the noun having to agree.
    private static let units: [String: RecurrenceRule.Frequency] = [
        "day": .daily, "days": .daily,
        "week": .weekly, "weeks": .weekly,
        "month": .monthly, "months": .monthly,
        "year": .yearly, "years": .yearly,
    ]

    private static func singularUnit(_ frequency: RecurrenceRule.Frequency) -> String {
        switch frequency {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        }
    }
}

/// Stable identity used to re-find a subscription's line after re-reading its
/// note, mirroring `TaskIdentity`.
///
/// Status is deliberately *not* part of it, for the same reason completion is
/// not part of a task's: a semantic "set this to paused" has to find the line
/// after another caller has already put it in that state, or a replayed or
/// concurrent edit fails against content that is already correct.
struct SubscriptionIdentity: Hashable, Sendable {
    let filePath: String
    /// 0-based line index when the index was built. A hint for diagnostics
    /// only — every mutation re-finds its line by meaning, because after an
    /// external edit shifts the lines a remembered number is not evidence.
    let lineNumber: Int
    let name: String
    let costAmount: Decimal
    let currencyCode: String
    let cycleTag: String
    let firstChargeDateString: String
    let category: String?

    var fileURL: URL { URL(fileURLWithPath: filePath) }

    /// Canonical grouping key for category comparisons, so a case- or
    /// diacritic-only rename of a heading does not make its lines unfindable.
    var canonicalCategory: String? {
        category.map(TaskListDocument.canonicalName)
    }

    init(
        filePath: String,
        lineNumber: Int,
        name: String,
        costAmount: Decimal,
        currencyCode: String,
        cycleTag: String,
        firstChargeDateString: String,
        category: String?
    ) {
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.name = name
        self.costAmount = costAmount
        self.currencyCode = currencyCode.uppercased()
        self.cycleTag = cycleTag
        self.firstChargeDateString = firstChargeDateString
        self.category = category
    }

    init(_ subscription: Subscription) {
        self.init(
            filePath: subscription.fileURL.path,
            lineNumber: subscription.lineNumber,
            name: subscription.name,
            costAmount: subscription.cost.amount,
            currencyCode: subscription.cost.currencyCode,
            cycleTag: subscription.cycle.tagText,
            firstChargeDateString: subscription.firstChargeDateString,
            category: subscription.category)
    }
}

/// One recurring charge collected from the subscription note.
///
/// Ranges are absent by design, exactly as they are on `TaskItem`: the file is
/// re-read and re-parsed at mutation time, so nothing held here can go stale.
struct Subscription: Identifiable, Hashable, Sendable {
    let fileURL: URL
    /// 0-based line index at the time the index was built.
    let lineNumber: Int
    let name: String
    let cost: Money
    let cycle: BillingCycle
    /// The **first** charge date, `YYYY-MM-DD`, and the permanent anchor of
    /// the series.
    ///
    /// This is the whole scheduling design. Storing the *next* charge would
    /// mean rewriting the file as time passes — and an anchor that moves is
    /// exactly what made "every month on the 31st" walk backwards off February
    /// in the task recurrence this replaced. Deriving the next charge from a
    /// fixed first charge means the file is never rewritten by the passage of
    /// time, and it answers "how long have I been paying for this" for free.
    let firstChargeDateString: String
    let status: SubscriptionStatus
    /// The `##` heading this line sits under, when it has one.
    let category: String?
    /// The original line including its terminator, so a delete Undo restores
    /// the user's own bullet, indentation, and spacing rather than a
    /// normalized rewrite.
    let sourceLine: String?

    init(
        fileURL: URL,
        lineNumber: Int,
        name: String,
        cost: Money,
        cycle: BillingCycle,
        firstChargeDateString: String,
        status: SubscriptionStatus = .active,
        category: String? = nil,
        sourceLine: String? = nil
    ) {
        self.fileURL = fileURL
        self.lineNumber = lineNumber
        self.name = name
        self.cost = cost
        self.cycle = cycle
        self.firstChargeDateString = firstChargeDateString
        self.status = status
        self.category = category
        self.sourceLine = sourceLine
    }

    var id: String { "\(fileURL.path)#\(lineNumber)" }

    var identity: SubscriptionIdentity { SubscriptionIdentity(self) }

    var countsTowardSpending: Bool { status.countsTowardSpending }

    /// Start of the first charge day in Cove's Gregorian task calendar.
    func firstChargeDate(in timeZone: TimeZone) -> Date? {
        guard
            let components = TaskCalendar.dateComponents(
                from: firstChargeDateString),
            components.isValidDate(in: TaskCalendar.gregorian(timeZone: timeZone))
        else { return nil }
        return TaskCalendar.gregorian(timeZone: timeZone).date(from: components)
    }
}
