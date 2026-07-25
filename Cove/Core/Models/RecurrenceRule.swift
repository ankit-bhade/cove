import Foundation

/// A task's recurrence, stored in Markdown as `@repeat(<tag>)` after the
/// `@due` tag. The model mirrors the grove-app project: a frequency, an
/// interval, and — for weekly rules — an optional set of weekdays.
struct RecurrenceRule: Hashable, Sendable {
    enum Frequency: String, CaseIterable, Sendable {
        case daily, weekly, monthly, yearly
    }

    var frequency: Frequency
    /// Every N days/weeks/months/years; clamped to `1...maximumInterval`.
    var interval: Int
    /// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday), sorted and
    /// deduplicated. Only meaningful for weekly rules.
    var byWeekday: [Int]

    /// Upper bound on `interval`, enforced by the one initializer every other
    /// path routes through. The weekly arithmetic multiplies the interval by
    /// seven, so a number a person could type into quick entry — or leave in a
    /// note's `@repeat` tag — would overflow and trap the process rather than
    /// produce a date. A thousand of any unit is already past the point where
    /// a repeating task means anything.
    static let maximumInterval = 1_000

    /// Ceiling on the monthly/yearly occurrence search.
    ///
    /// Both searches start at the step nearest the reference date and advance
    /// monotonically, so they land in one or two iterations — a few more for
    /// a Feb-29 rule waiting out a leap year. The bound only exists so a
    /// candidate that somehow stops advancing returns nil instead of spinning
    /// on the main actor. It was `maximumInterval * 10_000`: ten million
    /// rounds of `Calendar` arithmetic is a hang, not a safety net.
    private static let maximumSearchSteps = 120

    init(frequency: Frequency, interval: Int = 1, byWeekday: [Int] = []) {
        self.frequency = frequency
        self.interval = min(max(1, interval), Self.maximumInterval)
        self.byWeekday = Array(Set(byWeekday)).sorted()
    }

    /// Monday through Friday.
    static let everyWeekday = RecurrenceRule(
        frequency: .weekly,
        byWeekday: [2, 3, 4, 5, 6])

    static let weekdayNames = [
        "sunday", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday",
    ]

    // MARK: - Tags

    /// The normalized text stored inside `@repeat(...)`:
    /// `daily` / `weekly` / `monthly` / `yearly`, `every N days`,
    /// `every weekday`, or `every monday wednesday` (full names,
    /// space-separated). `every sunday` — the Phase 8 form — is the
    /// single-day case of the weekday list.
    var tagText: String {
        if self == .everyWeekday { return "every weekday" }
        if frequency == .weekly, !byWeekday.isEmpty {
            return "every "
                + byWeekday
                .map { Self.weekdayNames[$0 - 1] }
                .joined(separator: " ")
        }
        if interval == 1 { return frequency.rawValue }
        let unit = [
            "daily": "days", "weekly": "weeks",
            "monthly": "months", "yearly": "years",
        ][frequency.rawValue]!
        return "every \(interval) \(unit)"
    }

    /// Parses the text inside `@repeat(...)`. Strict but forgiving of the
    /// forms a hand-typer would use: the adverbs, `every day|week|month|year`,
    /// `every N <units>`, `every weekday`, and `every <weekday list>` with
    /// full names or common abbreviations.
    init?(tagText: String) {
        switch tagText {
        case "daily": self.init(frequency: .daily); return
        case "weekly": self.init(frequency: .weekly); return
        case "monthly": self.init(frequency: .monthly); return
        case "yearly": self.init(frequency: .yearly); return
        default: break
        }
        guard tagText.hasPrefix("every ") else { return nil }
        let rest = String(tagText.dropFirst(6))

        if rest == "weekday" || rest == "weekdays" {
            self = .everyWeekday
            return
        }
        let singleUnits = [
            "day": Frequency.daily, "week": .weekly,
            "month": .monthly, "year": .yearly,
        ]
        if let frequency = singleUnits[rest] {
            self.init(frequency: frequency)
            return
        }
        // every N days/weeks/months/years
        let words = rest.split(separator: " ").map(String.init)
        if words.count == 2, let interval = Int(words[0]), interval >= 1 {
            let pluralUnits = [
                "days": Frequency.daily, "weeks": .weekly,
                "months": .monthly, "years": .yearly,
            ]
            guard let frequency = pluralUnits[words[1]] else { return nil }
            self.init(frequency: frequency, interval: interval)
            return
        }
        // every <weekday list>, space-separated
        let weekdays = words.compactMap { Self.weekdayNumber(for: $0) }
        guard !words.isEmpty, weekdays.count == words.count else { return nil }
        self.init(frequency: .weekly, byWeekday: weekdays)
    }

    /// Accepts full names and the common abbreviations the quick-entry
    /// grammar recognizes; returns the `Calendar` weekday number.
    static func weekdayNumber(for word: String) -> Int? {
        let aliases: [String: Int] = [
            "sun": 1, "sunday": 1,
            "mon": 2, "monday": 2,
            "tue": 3, "tues": 3, "tuesday": 3,
            "wed": 4, "weds": 4, "wednesday": 4,
            "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
            "fri": 6, "friday": 6,
            "sat": 7, "saturday": 7,
        ]
        return aliases[word]
    }

    // MARK: - Display

    /// Human-readable summary, e.g. "Every Monday and Wednesday",
    /// "Every weekday", "Every 2 weeks", "Every day" — mirroring grove's
    /// `describeRecurrence`.
    var displayName: String {
        if frequency == .weekly, !byWeekday.isEmpty {
            if self == .everyWeekday { return "Every weekday" }
            let names = byWeekday.map { Self.weekdayNames[$0 - 1].capitalized }
            let list =
                names.count == 1
                ? names[0]
                : names.dropLast().joined(separator: ", ") + " and " + names.last!
            return interval == 1
                ? "Every \(list)"
                : "Every \(interval) weeks on \(list)"
        }
        let unit = [
            "daily": "day", "weekly": "week",
            "monthly": "month", "yearly": "year",
        ][frequency.rawValue]!
        return interval == 1 ? "Every \(unit)" : "Every \(interval) \(unit)s"
    }

    // MARK: - Next occurrence

    /// Convenience for advancing one occurrence. For catch-up and stable
    /// month/year anchors use the overloads below.
    func nextDueDateString(
        after dateString: String,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        nextDueDateString(
            after: dateString,
            anchoredTo: dateString,
            timeZone: timeZone)
    }

    /// Returns the first occurrence in the anchor's cadence strictly after
    /// `referenceDateString`.
    ///
    /// The explicit anchor is what keeps "every month on the 31st" on the
    /// 31st after February, keeps Feb 29 yearly tasks on leap day when one
    /// exists, and keeps interval rules aligned when an overdue task catches
    /// up. Callers that persist recurrence state should retain the original
    /// occurrence as the anchor.
    func nextDueDateString(
        after referenceDateString: String,
        anchoredTo anchorDateString: String,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        let calendar = TaskCalendar.gregorian(timeZone: timeZone)
        guard let reference = Self.day(referenceDateString, calendar: calendar),
            let anchor = Self.day(anchorDateString, calendar: calendar)
        else { return nil }

        func format(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(
                format: "%04d-%02d-%02d",
                parts.year!, parts.month!, parts.day!)
        }
        func addDays(_ days: Int, to date: Date) -> Date {
            calendar.date(byAdding: .day, value: days, to: date)!
        }

        switch frequency {
        case .daily:
            if reference < anchor { return format(anchor) }
            let elapsed = calendar.dateComponents([.day], from: anchor, to: reference).day!
            let steps = elapsed / interval + 1
            return calendar.date(
                byAdding: .day, value: steps * interval, to: anchor
            ).map(format)

        case .weekly:
            if byWeekday.isEmpty {
                if reference < anchor { return format(anchor) }
                let elapsed =
                    calendar.dateComponents([.day], from: anchor, to: reference).day!
                let cadence = interval * 7
                let steps = elapsed / cadence + 1
                return calendar.date(
                    byAdding: .day, value: steps * cadence, to: anchor
                ).map(format)
            }

            // Weekday sets use Sunday-based weeks anchored to the week that
            // contains the original occurrence. Search at most one complete
            // interval cycle; the interval is bounded, so this is predictable.
            let anchorWeekday = calendar.component(.weekday, from: anchor)
            let anchorWeekStart = addDays(-(anchorWeekday - 1), to: anchor)
            var candidate = addDays(1, to: reference)
            if candidate < anchor { candidate = anchor }
            for _ in 0...(interval * 7 + 6) {
                let candidateWeekday = calendar.component(.weekday, from: candidate)
                if byWeekday.contains(candidateWeekday) {
                    let candidateWeekStart =
                        addDays(-(candidateWeekday - 1), to: candidate)
                    let weekDays =
                        calendar.dateComponents(
                            [.day], from: anchorWeekStart, to: candidateWeekStart
                        ).day!
                    let weekOffset = weekDays / 7
                    if weekOffset >= 0, weekOffset.isMultiple(of: interval) {
                        return format(candidate)
                    }
                }
                candidate = addDays(1, to: candidate)
            }
            return nil

        case .monthly:
            let anchorParts = calendar.dateComponents([.year, .month, .day], from: anchor)
            let referenceParts = calendar.dateComponents([.year, .month], from: reference)
            guard let anchorYear = anchorParts.year, let anchorMonth = anchorParts.month,
                let anchorDay = anchorParts.day, let referenceYear = referenceParts.year,
                let referenceMonth = referenceParts.month,
                let anchorMonthRange = calendar.range(of: .day, in: .month, for: anchor)
            else { return nil }
            let isEndOfMonth = anchorDay == anchorMonthRange.count
            let monthDifference =
                (referenceYear - anchorYear) * 12 + referenceMonth - anchorMonth
            var step = reference < anchor ? 0 : max(0, monthDifference / interval)

            while step <= Self.maximumSearchSteps {
                guard
                    let candidate = Self.monthlyDate(
                        anchorYear: anchorYear,
                        anchorMonth: anchorMonth,
                        anchorDay: anchorDay,
                        isEndOfMonth: isEndOfMonth,
                        monthOffset: step * interval,
                        calendar: calendar)
                else { return nil }
                if candidate > reference { return format(candidate) }
                step += 1
            }
            return nil

        case .yearly:
            let anchorParts = calendar.dateComponents([.year, .month, .day], from: anchor)
            let referenceYear = calendar.component(.year, from: reference)
            guard let anchorYear = anchorParts.year, let month = anchorParts.month,
                let day = anchorParts.day
            else { return nil }
            let yearDifference = referenceYear - anchorYear
            var step = reference < anchor ? 0 : max(0, yearDifference / interval)

            while step <= Self.maximumSearchSteps {
                let year = anchorYear + step * interval
                guard
                    let candidate = Self.clampedDate(
                        year: year, month: month, day: day, calendar: calendar)
                else { return nil }
                if candidate > reference { return format(candidate) }
                step += 1
            }
            return nil
        }
    }

    /// Advances from the current occurrence to the first scheduled occurrence
    /// after both that occurrence and `cutoffDateString`, without resetting an
    /// interval rule's cadence to the day the checkbox happened to be tapped.
    func nextDueDateString(
        afterOccurrence occurrenceDateString: String,
        catchingUpPast cutoffDateString: String,
        anchoredTo anchorDateString: String? = nil,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard
            let occurrence = Self.day(
                occurrenceDateString,
                calendar: TaskCalendar.gregorian(timeZone: timeZone)),
            let cutoff = Self.day(
                cutoffDateString,
                calendar: TaskCalendar.gregorian(timeZone: timeZone))
        else { return nil }
        let reference = max(occurrence, cutoff)
        let referenceString = Self.format(
            reference,
            calendar: TaskCalendar.gregorian(timeZone: timeZone))
        return nextDueDateString(
            after: referenceString,
            anchoredTo: anchorDateString ?? occurrenceDateString,
            timeZone: timeZone)
    }

    private static func day(_ string: String, calendar: Calendar) -> Date? {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2,
            parts[2].count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
            let day = Int(parts[2])
        else { return nil }
        let components = DateComponents(
            year: year, month: month, day: day, hour: 12)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    private static func format(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year!, parts.month!, parts.day!)
    }

    private static func monthlyDate(
        anchorYear: Int,
        anchorMonth: Int,
        anchorDay: Int,
        isEndOfMonth: Bool,
        monthOffset: Int,
        calendar: Calendar
    ) -> Date? {
        let absoluteMonth = anchorYear * 12 + (anchorMonth - 1) + monthOffset
        let year = absoluteMonth / 12
        let month = absoluteMonth % 12 + 1
        guard
            let first = calendar.date(
                from: DateComponents(year: year, month: month, day: 1, hour: 12)),
            let days = calendar.range(of: .day, in: .month, for: first)?.count
        else { return nil }
        let day = isEndOfMonth ? days : min(anchorDay, days)
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    private static func clampedDate(
        year: Int,
        month: Int,
        day: Int,
        calendar: Calendar
    ) -> Date? {
        guard
            let first = calendar.date(
                from: DateComponents(year: year, month: month, day: 1, hour: 12)),
            let days = calendar.range(of: .day, in: .month, for: first)?.count
        else { return nil }
        return calendar.date(
            from: DateComponents(
                year: year, month: month, day: min(day, days), hour: 12))
    }
}
