import Foundation

/// The interpreted result of one quick-entry sentence, shown for
/// confirmation before it is written to Markdown.
struct TaskDraft: Equatable, Sendable {
    var title: String
    /// A concrete `YYYY-MM-DD`, or nil when the task is undated. Only list
    /// items may go undated; a task bound for the Tasks screen is resolved
    /// to today by its caller, since `@due` is required there.
    var dueDateString: String?
    /// 24-hour `HH:MM`, only when the sentence names a time.
    var dueTimeString: String?
    var recurrence: RecurrenceRule?

    /// The Markdown task line this draft saves as. Without a date there is
    /// no `@due` tag to hang a time or a repeat rule off, so both are
    /// dropped — the syntax puts them inside and after the tag.
    var markdownLine: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dueDateString else { return "- [ ] \(title)" }
        var line = "- [ ] \(title) @due(\(dueDateString)"
        if let dueTimeString { line += " \(dueTimeString)" }
        line += ")"
        if let recurrence { line += " @repeat(\(recurrence.tagText))" }
        return line
    }
}

/// Natural-language capture parser — a Swift port of the grove-app parser
/// (`src/lib/parser/parse.ts`), matching its grammar and resolution rules.
///
/// Turns strings like `gym every mon wed 6a`, `rent 2/3`, `retainer 940p`,
/// `meeting next fri 2pm`, or `buy eggs tmr` into a `TaskDraft`. Tokens are
/// recognized anywhere in the sentence; each extractor claims the character
/// span it consumed, and the title is the input minus the claimed spans
/// (with dangling connector words like "at"/"on" tidied away).
///
/// Pure and deterministic: pass `now` for testability. Divergences from
/// grove, forced by Cove's fixed rules, are noted inline: no hashtag lists,
/// undated input resolves to today, and a time range keeps its start time.
enum QuickTaskParser {
    // MARK: - Grammar fragments (grove's WD / MONTH / MERIDIEM)

    private static let wd = #"(?:sun(?:day)?|mon(?:day)?|tue(?:sday|s)?|wed(?:nesday|s)?|thu(?:rsday|rs|r)?|fri(?:day)?|sat(?:urday)?)"#
    private static let month = #"(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember|t)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"#
    private static let meridiem = #"(?:am|pm|a|p)"#

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    // Recurrence
    private static let everyUnitRegex = regex(
        #"\bevery\s+(?:(\d+)\s+)?(day|days|week|weeks|month|months|year|years)\b"#)
    private static let everyWeekdaySetRegex = regex(
        #"\bevery\s+(weekdays?|"# + wd + #"(?:(?:\s*,\s*|\s+and\s+|\s*&\s*|\s+)"# + wd + #")*)\b"#)
    private static let adverbRegex = regex(
        #"\b(daily|weekly|monthly|yearly|annually)\b"#)

    // Dates
    private static let dayAfterTomorrowRegex = regex(#"\b(?:day after tomorrow)\b"#)
    private static let tomorrowRegex = regex(#"\b(?:tomorrow|tmrw|tmr|tom)\b"#)
    private static let todayRegex = regex(#"\b(?:today|tdy)\b"#)
    private static let tonightRegex = regex(#"\b(?:tonight|tonite)\b"#)
    private static let nextWeekRegex = regex(#"\bnext\s+week\b"#)
    private static let nextWeekdayRegex = regex(#"\bnext\s+("# + wd + #")\b"#)
    private static let weekdayRegex = regex(#"\b(?:this\s+)?("# + wd + #")\b"#)
    private static let inUnitsRegex = regex(#"\bin\s+(\d+)\s*(days?|weeks?|months?|d|w|mo)\b"#)
    private static let monthDayRegex = regex(
        #"\b("# + month + #")\s+(\d{1,2})(?:st|nd|rd|th)?\b"#)
    private static let slashDateRegex = regex(
        #"(?:^|\s)(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?(?=\s|$)"#)

    // Times
    private static let timeRangeRegex = regex(
        #"\b(\d{1,2})(?::(\d{2}))?\s*("# + meridiem + #")?\s*(?:-|–|—|to\s)\s*(\d{1,2})(?::(\d{2}))?\s*("# + meridiem + #")\b"#)
    private static let noonRegex = regex(#"\b(?:noon|midday)\b"#)
    private static let midnightRegex = regex(#"\bmidnight\b"#)
    private static let hourMinuteRegex = regex(
        #"\b(\d{1,2}):(\d{2})\s*("# + meridiem + #")?(?=\s|$|[.,!?])"#)
    private static let compactTimeRegex = regex(
        #"\b(\d{3,4})\s*("# + meridiem + #")(?=\s|$|[.,!?])"#)
    private static let hourMeridiemRegex = regex(
        #"\b(\d{1,2})\s*("# + meridiem + #")(?=\s|$|[.,!?])"#)

    private static let monthNumbers: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2,
        "mar": 3, "march": 3, "apr": 4, "april": 4, "may": 5,
        "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
        "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    /// Tracks which parts of the input are already consumed by an extractor.
    private struct Claims {
        private(set) var spans: [NSRange] = []

        mutating func tryClaim(_ range: NSRange) -> Bool {
            let overlaps = spans.contains {
                range.location < $0.location + $0.length
                    && range.location + range.length > $0.location
            }
            guard !overlaps else { return false }
            spans.append(range)
            return true
        }
    }

    // MARK: - Parse

    /// `defaultingToToday` resolves an undated sentence to today, which is
    /// what the Tasks screen needs (`@due` is required there). The Lists
    /// screen passes false and keeps the item undated — a grocery item
    /// isn't due today just because it was typed today.
    static func parse(_ input: String,
                      now: Date,
                      calendar: Calendar = .current,
                      defaultingToToday: Bool = true) -> TaskDraft {
        let lower = input.lowercased() as NSString
        // Title spans slice the original input; fall back to the lowered
        // string in the rare case lowercasing changed UTF-16 lengths.
        let original = input as NSString
        let titleSource = original.length == lower.length ? original : lower
        let whole = NSRange(location: 0, length: lower.length)
        var claims = Claims()

        var date: String?
        var time: String?
        var recurrence: RecurrenceRule?
        var tonight = false

        func text(_ match: NSTextCheckingResult, _ group: Int) -> String? {
            let range = match.range(at: group)
            guard range.location != NSNotFound else { return nil }
            return lower.substring(with: range)
        }
        func setDate(_ dayOffsetFromNow: Int) {
            if date == nil {
                date = ymdString(from: addDays(dayOffsetFromNow, to: now,
                                               calendar: calendar),
                                 calendar: calendar)
            }
        }
        func setDate(to resolved: Date) {
            if date == nil { date = ymdString(from: resolved, calendar: calendar) }
        }

        // ---- 1. Recurrence ("every ...") ---------------------------------
        everyUnitRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, claims.tryClaim(m.range), recurrence == nil else { return }
            let interval = text(m, 1).flatMap(Int.init) ?? 1
            let unit = text(m, 2)!
            let frequencies: [String: RecurrenceRule.Frequency] = [
                "day": .daily, "week": .weekly, "month": .monthly, "year": .yearly]
            let singular = unit.hasSuffix("s") ? String(unit.dropLast()) : unit
            recurrence = RecurrenceRule(frequency: frequencies[singular]!,
                                        interval: interval)
        }

        everyWeekdaySetRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, claims.tryClaim(m.range), recurrence == nil else { return }
            let list = text(m, 1)!
            if list == "weekday" || list == "weekdays" {
                recurrence = .everyWeekday
            } else {
                let weekdays = list
                    .components(separatedBy: CharacterSet(charactersIn: " ,&"))
                    .filter { !$0.isEmpty && $0 != "and" }
                    .compactMap { RecurrenceRule.weekdayNumber(for: $0) }
                recurrence = RecurrenceRule(frequency: .weekly, byWeekday: weekdays)
            }
        }

        adverbRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, claims.tryClaim(m.range), recurrence == nil else { return }
            let word = text(m, 1)!
            let frequencies: [String: RecurrenceRule.Frequency] = [
                "daily": .daily, "weekly": .weekly, "monthly": .monthly,
                "yearly": .yearly, "annually": .yearly]
            recurrence = RecurrenceRule(frequency: frequencies[word]!)
        }

        // ---- 2. Dates (in grove's rule order) -----------------------------
        dayAfterTomorrowRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, claims.tryClaim(m.range) else { return }
            setDate(2)
        }
        tomorrowRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, claims.tryClaim(m.range) else { return }
            setDate(1)
        }
        todayRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, claims.tryClaim(m.range) else { return }
            setDate(0)
        }
        tonightRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, claims.tryClaim(m.range) else { return }
            tonight = true
            setDate(0)
        }
        nextWeekRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, claims.tryClaim(m.range) else { return }
            // Next Monday, counted from tomorrow.
            let tomorrow = addDays(1, to: now, calendar: calendar)
            setDate(to: upcomingWeekday(2, from: tomorrow, includeToday: true,
                                        calendar: calendar))
        }
        nextWeekdayRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, let weekday = RecurrenceRule.weekdayNumber(for: text(m, 1)!),
                  claims.tryClaim(m.range) else { return }
            setDate(to: upcomingWeekday(weekday, from: now, includeToday: false,
                                        calendar: calendar))
        }
        weekdayRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, let weekday = RecurrenceRule.weekdayNumber(for: text(m, 1)!),
                  claims.tryClaim(m.range) else { return }
            setDate(to: upcomingWeekday(weekday, from: now, includeToday: true,
                                        calendar: calendar))
        }
        inUnitsRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, let n = text(m, 1).flatMap(Int.init) else { return }
            let unit = text(m, 2)!
            guard claims.tryClaim(m.range) else { return }
            if unit.hasPrefix("d") {
                setDate(n)
            } else if unit.hasPrefix("mo") {
                if let jumped = calendar.date(byAdding: .month, value: n, to: now) {
                    setDate(to: jumped)
                }
            } else {
                setDate(n * 7)
            }
        }
        monthDayRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, let monthNumber = monthNumbers[text(m, 1)!],
                  let day = text(m, 2).flatMap(Int.init),
                  (1...31).contains(day),
                  let resolved = upcomingMonthDay(month: monthNumber, day: day,
                                                  now: now, calendar: calendar),
                  claims.tryClaim(m.range) else { return }
            setDate(to: resolved)
        }
        slashDateRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, let monthNumber = text(m, 1).flatMap(Int.init),
                  let day = text(m, 2).flatMap(Int.init),
                  (1...12).contains(monthNumber), (1...31).contains(day) else { return }
            var resolved: Date?
            if let yearText = text(m, 3), var year = Int(yearText) {
                if year < 100 { year += 2000 }
                resolved = calendar.date(from: DateComponents(
                    year: year, month: monthNumber, day: day, hour: 12))
            } else {
                resolved = upcomingMonthDay(month: monthNumber, day: day,
                                            now: now, calendar: calendar)
            }
            guard let resolved else { return }
            // The rule anchors on leading whitespace; claim only the token.
            let matched = lower.substring(with: m.range)
            let lead = matched.count - matched.drop(while: \.isWhitespace).count
            let token = NSRange(location: m.range.location + lead,
                                length: m.range.length - lead)
            guard claims.tryClaim(token) else { return }
            setDate(to: resolved)
        }

        // ---- 3. Time ranges (7-9pm, 3-4:30pm) -----------------------------
        // Cove has no calendar events, so the range's start time is used and
        // the end time is dropped; the whole range span still leaves the title.
        timeRangeRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m else { return }
            let endMeridiem = normalizeMeridiem(text(m, 6))
            let startMeridiem = normalizeMeridiem(text(m, 3)) ?? endMeridiem
            guard let start = toHHMM(hour: text(m, 1).flatMap(Int.init) ?? 0,
                                     minute: text(m, 2).flatMap(Int.init) ?? 0,
                                     meridiem: startMeridiem),
                  toHHMM(hour: text(m, 4).flatMap(Int.init) ?? 0,
                         minute: text(m, 5).flatMap(Int.init) ?? 0,
                         meridiem: endMeridiem) != nil,
                  claims.tryClaim(m.range) else { return }
            if time == nil { time = start }
        }

        // ---- 4. Single times ----------------------------------------------
        noonRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, claims.tryClaim(m.range) else { return }
            if time == nil { time = "12:00" }
        }
        midnightRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, claims.tryClaim(m.range) else { return }
            if time == nil { time = "00:00" }
        }
        hourMinuteRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, let resolved = toHHMM(hour: text(m, 1).flatMap(Int.init) ?? 0,
                                               minute: text(m, 2).flatMap(Int.init) ?? 0,
                                               meridiem: normalizeMeridiem(text(m, 3))),
                  claims.tryClaim(m.range) else { return }
            if time == nil { time = resolved }
        }
        compactTimeRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, let digits = text(m, 1) else { return }
            let hour = Int(digits.dropLast(2)) ?? 0
            let minute = Int(digits.suffix(2)) ?? 0
            guard let resolved = toHHMM(hour: hour, minute: minute,
                                        meridiem: normalizeMeridiem(text(m, 2))),
                  claims.tryClaim(m.range) else { return }
            if time == nil { time = resolved }
        }
        hourMeridiemRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, let resolved = toHHMM(hour: text(m, 1).flatMap(Int.init) ?? 0,
                                               minute: 0,
                                               meridiem: normalizeMeridiem(text(m, 2))),
                  claims.tryClaim(m.range) else { return }
            if time == nil { time = resolved }
        }

        // ---- 5. Finalize ---------------------------------------------------
        if tonight, time == nil { time = "20:00" }

        // A bare time means today: `retainer 940p` is tonight's 9:40 PM.
        if time != nil, date == nil, recurrence == nil {
            date = ymdString(from: now, calendar: calendar)
        }

        if let rule = recurrence, date == nil {
            if rule.frequency == .weekly, !rule.byWeekday.isEmpty {
                // First occurrence: the next matching weekday, today included.
                let candidates = rule.byWeekday.map {
                    upcomingWeekday($0, from: now, includeToday: true,
                                    calendar: calendar)
                }
                date = ymdString(from: candidates.min()!, calendar: calendar)
            } else {
                date = ymdString(from: now, calendar: calendar)
            }
        }

        // Cove divergence: tasks require @due, so undated input lands today
        // (grove leaves it undated). List items are the exception — see
        // `defaultingToToday`.
        let resolvedDate = date ?? (defaultingToToday
                                    ? ymdString(from: now, calendar: calendar) : nil)

        // ---- 6. Title: input minus consumed spans --------------------------
        var title = ""
        var cursor = 0
        for span in claims.spans.sorted(by: { $0.location < $1.location }) {
            title += titleSource.substring(
                with: NSRange(location: cursor, length: span.location - cursor))
            cursor = span.location + span.length
        }
        title += titleSource.substring(
            with: NSRange(location: cursor, length: titleSource.length - cursor))
        title = cleanedTitle(title)

        return TaskDraft(title: title, dueDateString: resolvedDate,
                         dueTimeString: time, recurrence: recurrence)
    }

    // MARK: - Helpers

    private static func cleanedTitle(_ raw: String) -> String {
        var title = raw
            .replacingOccurrences(of: #"\s+"#, with: " ",
                                  options: .regularExpression)
            // Drop connector words left dangling once their token was consumed.
            .replacingOccurrences(of: #"\s+(?:at|on|due|by|from)\s*$"#, with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\s*(?:at|on)\s+"#, with: "",
                                  options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"[,;]\s*$"#, with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if let first = title.first {
            title = first.uppercased() + title.dropFirst()
        }
        return title
    }

    private static func normalizeMeridiem(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return raw.hasPrefix("a") ? "am" : "pm"
    }

    /// Grove's `toHHMM`: with a meridiem the hour must be 1–12; without one,
    /// 13+ reads as 24-hour and small hours (1–6) likely mean afternoon.
    private static func toHHMM(hour rawHour: Int, minute: Int,
                               meridiem: String?) -> String? {
        var hour = rawHour
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "pm", hour != 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        } else {
            guard hour <= 23 else { return nil }
            if (1...6).contains(hour) { hour += 12 }
        }
        guard (0...59).contains(minute) else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func addDays(_ days: Int, to date: Date,
                                calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    /// Next occurrence of `weekday` (1 = Sunday … 7 = Saturday) counted from
    /// `from`. Plain "fri" includes today; "next fri" is strictly future and
    /// lands a full week out when said on a Friday.
    private static func upcomingWeekday(_ weekday: Int, from: Date,
                                        includeToday: Bool,
                                        calendar: Calendar) -> Date {
        var ahead = (weekday - calendar.component(.weekday, from: from) + 7) % 7
        if ahead == 0, !includeToday { ahead = 7 }
        return addDays(ahead, to: from, calendar: calendar)
    }

    /// Resolve month/day to a concrete date: the next time that day occurs.
    private static func upcomingMonthDay(month: Int, day: Int, now: Date,
                                         calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: now)
        guard let candidate = calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: 12)) else { return nil }
        if ymdString(from: candidate, calendar: calendar)
            < ymdString(from: now, calendar: calendar) {
            return calendar.date(byAdding: .year, value: 1, to: candidate)
        }
        return candidate
    }

    // MARK: - Formatting

    static func ymdString(from date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
