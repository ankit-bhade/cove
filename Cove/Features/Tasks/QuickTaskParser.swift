import Foundation

/// The interpreted result of one quick-entry sentence, shown for
/// confirmation before it is written to Markdown.
struct TaskDraft: Equatable, Sendable {
    var title: String
    /// Always resolved to a concrete `YYYY-MM-DD` (today when the sentence
    /// names no date).
    var dueDateString: String
    /// 24-hour `HH:MM`, only when the sentence names a time.
    var dueTimeString: String?
    var recurrence: RecurrenceRule?

    /// The Markdown task line this draft saves as.
    var markdownLine: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var line = "- [ ] \(title) @due(\(dueDateString)"
        if let dueTimeString { line += " \(dueTimeString)" }
        line += ")"
        if let recurrence { line += " @repeat(\(recurrence.tagText))" }
        return line
    }
}

/// Interprets one quick-entry sentence — "get bread 3p tmr",
/// "laundry every sun 6p", "tennis fri" — into a `TaskDraft`. Pure and
/// deterministic given `now` and `calendar`, so it is fully unit-testable.
///
/// Scheduling tokens are consumed from the *end* of the sentence (one date,
/// one time, one recurrence, in any order); everything left is the title,
/// so words like "friday" inside the title survive as long as scheduling
/// details come last.
enum QuickTaskParser {
    static func parse(_ input: String, now: Date, calendar: Calendar = .current) -> TaskDraft {
        var tokens = input.split(whereSeparator: \.isWhitespace).map(String.init)

        var time: String?
        var recurrence: RecurrenceRule?
        var dateToken: DateToken?

        // Consume trailing scheduling tokens until one doesn't parse or its
        // slot is already taken.
        scan: while let last = tokens.last?.lowercased() {
            let secondToLast = tokens.count >= 2 ? tokens[tokens.count - 2].lowercased() : nil

            if recurrence == nil, let two = secondToLast,
               let rule = parseRecurrence(word: two, argument: last) {
                recurrence = rule
                tokens.removeLast(2)
            } else if recurrence == nil, let rule = parseRecurrence(single: last) {
                recurrence = rule
                tokens.removeLast()
            } else if dateToken == nil, secondToLast == "next",
                      let weekday = weekdayNumber(for: last) {
                dateToken = .nextWeekday(weekday)
                tokens.removeLast(2)
            } else if dateToken == nil, let token = parseDateWord(last) {
                dateToken = token
                tokens.removeLast()
            } else if time == nil, let parsed = parseTime(last) {
                time = parsed
                tokens.removeLast()
            } else {
                break scan
            }
        }

        var title = tokens.joined(separator: " ")
        if let first = title.first {
            title = first.uppercased() + title.dropFirst()
        }

        let date = resolveDate(dateToken, recurrence: recurrence, time: time,
                               now: now, calendar: calendar)
        return TaskDraft(title: title, dueDateString: date,
                         dueTimeString: time, recurrence: recurrence)
    }

    // MARK: - Dates

    private enum DateToken {
        case today
        case tomorrow
        /// Soonest occurrence of the weekday, today included.
        case weekday(Int)
        /// The occurrence after the soonest one.
        case nextWeekday(Int)
    }

    private static func parseDateWord(_ word: String) -> DateToken? {
        switch word {
        case "tdy", "today": .today
        case "tmr", "tmrw", "tom", "tomorrow": .tomorrow
        default: weekdayNumber(for: word).map(DateToken.weekday)
        }
    }

    private static func resolveDate(_ token: DateToken?,
                                    recurrence: RecurrenceRule?,
                                    time: String?,
                                    now: Date,
                                    calendar: Calendar) -> String {
        let today = ymdString(from: now, calendar: calendar)
        // A named time that has already passed pushes an *implicit* today
        // (and the soonest-weekday case) forward; explicit today/tomorrow
        // are taken literally.
        let timePassed = time.map { $0 <= hmString(from: now, calendar: calendar) } ?? false

        switch token {
        case .today:
            return today
        case .tomorrow:
            return dayAfter(today, calendar: calendar)
        case .weekday(let weekday), .nextWeekday(let weekday):
            var date = today
            let todayMatches = calendar.component(.weekday, from: now) == weekday
            if !todayMatches || timePassed {
                date = RecurrenceRule.weekly(weekday: weekday)
                    .nextDueDateString(after: today, calendar: calendar) ?? today
            }
            if case .nextWeekday = token! {
                date = RecurrenceRule.weekly(weekday: weekday)
                    .nextDueDateString(after: date, calendar: calendar) ?? date
            }
            return date
        case nil:
            if let recurrence {
                // First occurrence: today when today matches (and any named
                // time hasn't passed), else the next occurrence.
                let todayMatches = recurrence.matches(
                    weekday: calendar.component(.weekday, from: now))
                if todayMatches && !timePassed { return today }
                return recurrence.nextDueDateString(after: today, calendar: calendar) ?? today
            }
            return timePassed ? dayAfter(today, calendar: calendar) : today
        }
    }

    private static func dayAfter(_ dateString: String, calendar: Calendar) -> String {
        RecurrenceRule.daily.nextDueDateString(after: dateString, calendar: calendar)
            ?? dateString
    }

    // MARK: - Recurrence

    private static func parseRecurrence(single word: String) -> RecurrenceRule? {
        switch word {
        case "daily", "everyday": .daily
        case "weekdays": .everyWeekday
        default: nil
        }
    }

    private static func parseRecurrence(word: String, argument: String) -> RecurrenceRule? {
        guard word == "every" else { return nil }
        switch argument {
        case "day": return .daily
        case "weekday": return .everyWeekday
        default: return weekdayNumber(for: argument).map { .weekly(weekday: $0) }
        }
    }

    // MARK: - Tokens

    private static let weekdayAliases: [String: Int] = [
        "sun": 1, "sunday": 1,
        "mon": 2, "monday": 2,
        "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "weds": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6,
        "sat": 7, "saturday": 7,
    ]

    private static func weekdayNumber(for word: String) -> Int? {
        weekdayAliases[word]
    }

    private static let amPmTimeRegex = try! NSRegularExpression(
        pattern: #"^(\d{1,2})(?::(\d{2}))?(a|p|am|pm)$"#)
    private static let twentyFourHourTimeRegex = try! NSRegularExpression(
        pattern: #"^(\d{1,2}):(\d{2})$"#)

    /// Parses "3p", "6pm", "3:30pm", "11a", or 24-hour "15:00" into a
    /// normalized `HH:MM`. Bare numbers are never times, so "buy 6 eggs"
    /// keeps its 6.
    static func parseTime(_ word: String) -> String? {
        let word = word.lowercased()
        let ns = word as NSString
        let whole = NSRange(location: 0, length: ns.length)

        if let match = amPmTimeRegex.firstMatch(in: word, range: whole) {
            var hour = Int(ns.substring(with: match.range(at: 1)))!
            let minute = match.range(at: 2).location == NSNotFound
                ? 0 : Int(ns.substring(with: match.range(at: 2)))!
            guard (1...12).contains(hour), (0...59).contains(minute) else { return nil }
            let isPM = ns.substring(with: match.range(at: 3)).hasPrefix("p")
            if hour == 12 { hour = 0 }
            if isPM { hour += 12 }
            return String(format: "%02d:%02d", hour, minute)
        }
        if let match = twentyFourHourTimeRegex.firstMatch(in: word, range: whole) {
            let hour = Int(ns.substring(with: match.range(at: 1)))!
            let minute = Int(ns.substring(with: match.range(at: 2)))!
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return String(format: "%02d:%02d", hour, minute)
        }
        return nil
    }

    // MARK: - Formatting

    static func ymdString(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private static func hmString(from date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour!, parts.minute!)
    }
}
