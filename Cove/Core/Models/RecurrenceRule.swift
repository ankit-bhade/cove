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

    init(frequency: Frequency, interval: Int = 1, byWeekday: [Int] = []) {
        self.frequency = frequency
        self.interval = min(max(1, interval), Self.maximumInterval)
        self.byWeekday = Array(Set(byWeekday)).sorted()
    }

    /// Monday through Friday.
    static let everyWeekday = RecurrenceRule(frequency: .weekly,
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
            return "every " + byWeekday
                .map { Self.weekdayNames[$0 - 1] }
                .joined(separator: " ")
        }
        if interval == 1 { return frequency.rawValue }
        let unit = ["daily": "days", "weekly": "weeks",
                    "monthly": "months", "yearly": "years"][frequency.rawValue]!
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
        let singleUnits = ["day": Frequency.daily, "week": .weekly,
                           "month": .monthly, "year": .yearly]
        if let frequency = singleUnits[rest] {
            self.init(frequency: frequency)
            return
        }
        // every N days/weeks/months/years
        let words = rest.split(separator: " ").map(String.init)
        if words.count == 2, let interval = Int(words[0]), interval >= 1 {
            let pluralUnits = ["days": Frequency.daily, "weeks": .weekly,
                               "months": .monthly, "years": .yearly]
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
            let list = names.count == 1
                ? names[0]
                : names.dropLast().joined(separator: ", ") + " and " + names.last!
            return interval == 1
                ? "Every \(list)"
                : "Every \(interval) weeks on \(list)"
        }
        let unit = ["daily": "day", "weekly": "week",
                    "monthly": "month", "yearly": "year"][frequency.rawValue]!
        return interval == 1 ? "Every \(unit)" : "Every \(interval) \(unit)s"
    }

    // MARK: - Next occurrence

    /// The next occurrence strictly after the given `YYYY-MM-DD` date, in
    /// the same format — a port of grove's `nextOccurrence`. Nil only for an
    /// unparseable input date.
    func nextDueDateString(after dateString: String,
                           calendar: Calendar = TaskCalendar.gregorian()) -> String? {
        let calendar = TaskCalendar.gregorian(timeZone: calendar.timeZone)
        let parts = dateString.split(separator: "-").compactMap { Int($0) }
        // Anchor at noon so day arithmetic is immune to DST transitions.
        guard parts.count == 3,
              let from = calendar.date(from: DateComponents(
                  year: parts[0], month: parts[1], day: parts[2], hour: 12))
        else { return nil }

        func format(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d",
                          parts.year!, parts.month!, parts.day!)
        }
        func addDays(_ days: Int, to date: Date) -> Date {
            calendar.date(byAdding: .day, value: days, to: date)!
        }

        switch frequency {
        case .daily:
            return format(addDays(interval, to: from))

        case .weekly:
            let fromWeekday = calendar.component(.weekday, from: from)
            let days = byWeekday.isEmpty ? [fromWeekday] : byWeekday
            if interval == 1 {
                // Walk forward to the next listed weekday.
                for offset in 1...7 {
                    let candidate = addDays(offset, to: from)
                    if days.contains(calendar.component(.weekday, from: candidate)) {
                        return format(candidate)
                    }
                }
                return nil
            }
            // interval > 1: within the same week move to the next listed
            // weekday; otherwise jump ahead `interval` weeks to the first.
            if let sameWeekNext = days.first(where: { $0 > fromWeekday }) {
                return format(addDays(sameWeekNext - fromWeekday, to: from))
            }
            let startOfWeek = addDays(-(fromWeekday - 1), to: from)
            return format(addDays(interval * 7 + (days.min()! - 1), to: startOfWeek))

        case .monthly:
            // Same day-of-month, clamped so Jan 31 recurs on Feb 28.
            guard let jumped = calendar.date(byAdding: .month, value: interval,
                                             to: from) else { return nil }
            // Calendar clamps overflow itself (Jan 31 + 1 month = Feb 28),
            // matching grove's explicit clamp.
            return format(jumped)

        case .yearly:
            guard var next = calendar.date(byAdding: .year, value: interval,
                                           to: from) else { return nil }
            // Feb 29 → Feb 28 on non-leap years (Calendar already clamps,
            // but keep parity explicit if it ever rolled forward).
            if calendar.component(.month, from: next)
                != calendar.component(.month, from: from) {
                next = addDays(-1, to: next)
            }
            return format(next)
        }
    }
}
