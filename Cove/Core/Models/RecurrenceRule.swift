import Foundation

/// A task's recurrence, stored in Markdown as `@repeat(<tag>)` after the
/// `@due` tag. The rule set is fixed: `daily`, `every weekday`, or
/// `every <weekday name>`; tags are stored in exactly those normalized forms.
enum RecurrenceRule: Hashable, Sendable {
    case daily
    case everyWeekday
    /// `Calendar` weekday numbering: 1 = Sunday … 7 = Saturday.
    case weekly(weekday: Int)

    static let weekdayNames = [
        "sunday", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday",
    ]

    /// Parses the text inside `@repeat(...)`. Strict by design: only the
    /// normalized forms produced by `tagText` are recognized, mirroring the
    /// strictness of the task-line syntax.
    init?(tagText: String) {
        switch tagText {
        case "daily":
            self = .daily
        case "every weekday":
            self = .everyWeekday
        default:
            guard tagText.hasPrefix("every "),
                  let index = Self.weekdayNames.firstIndex(of: String(tagText.dropFirst(6)))
            else { return nil }
            self = .weekly(weekday: index + 1)
        }
    }

    /// The normalized text stored inside `@repeat(...)`.
    var tagText: String {
        switch self {
        case .daily: "daily"
        case .everyWeekday: "every weekday"
        case .weekly(let weekday): "every \(Self.weekdayNames[weekday - 1])"
        }
    }

    /// "Daily", "Every weekday", "Every Sunday" — for rows and pickers.
    var displayName: String {
        switch self {
        case .daily: "Daily"
        case .everyWeekday: "Every weekday"
        case .weekly(let weekday): "Every \(Self.weekdayNames[weekday - 1].capitalized)"
        }
    }

    /// Whether a date (as `Calendar` weekday number) is an occurrence.
    func matches(weekday: Int) -> Bool {
        switch self {
        case .daily: true
        case .everyWeekday: (2...6).contains(weekday)
        case .weekly(let day): weekday == day
        }
    }

    /// The next occurrence strictly after the given `YYYY-MM-DD` date, in
    /// the same format. Nil only for an unparseable input date.
    func nextDueDateString(after dateString: String,
                           calendar: Calendar = .current) -> String? {
        let parts = dateString.split(separator: "-").compactMap { Int($0) }
        // Anchor at noon so day arithmetic is immune to DST transitions.
        guard parts.count == 3,
              var date = calendar.date(from: DateComponents(
                  year: parts[0], month: parts[1], day: parts[2], hour: 12))
        else { return nil }
        repeat {
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            date = next
        } while !matches(weekday: calendar.component(.weekday, from: date))
        let next = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", next.year!, next.month!, next.day!)
    }
}
