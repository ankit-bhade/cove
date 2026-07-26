import Foundation

enum TaskDraftValidationIssue: Equatable, Sendable {
    case emptyTitle
    case unsafeTitle
    case invalidDate(String)
    case invalidTime(String)
    case nonexistentLocalTime(date: String, time: String)
    case scheduleWithoutDate

    var message: String {
        switch self {
        case .emptyTitle:
            return "Enter a task title."
        case .unsafeTitle:
            return
                "Task titles cannot contain line breaks, control characters, or literal @due( / @repeat( / @anchor( tag openers."
        case .invalidDate(let value):
            return "The date \(value) does not exist."
        case .invalidTime(let value):
            return "The time \(value) is not a valid 24-hour time."
        case .nonexistentLocalTime(let date, let time):
            return
                "\(date) at \(time) does not exist in this time zone because the clock moves forward."
        case .scheduleWithoutDate:
            return "A time or repeat rule requires a due date."
        }
    }
}

struct TaskDraftValidationError: LocalizedError, Equatable, Sendable {
    let issues: [TaskDraftValidationIssue]
    var errorDescription: String? { issues.map(\.message).joined(separator: " ") }
}

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

    /// A one-line title safe to embed before Cove's reserved tags. Control
    /// characters/newlines become spaces and literal tag openers gain a space
    /// before `(` so they remain title text on the next parse.
    var sanitizedTitle: String {
        var result = ""
        let space = Unicode.Scalar(0x20)!
        for scalar in title.unicodeScalars {
            result.unicodeScalars.append(
                CharacterSet.controlCharacters.contains(scalar) ? space : scalar)
        }
        result = result.replacingOccurrences(
            of: "@due(", with: "@due (", options: .caseInsensitive)
        result = result.replacingOccurrences(
            of: "@repeat(", with: "@repeat (", options: .caseInsensitive)
        result = result.replacingOccurrences(
            of: "@anchor(", with: "@anchor (", options: .caseInsensitive)
        return
            result
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    var validationIssues: [TaskDraftValidationIssue] {
        validationIssues()
    }

    func validationIssues(
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> [TaskDraftValidationIssue] {
        var issues: [TaskDraftValidationIssue] = []
        if sanitizedTitle.isEmpty { issues.append(.emptyTitle) }
        if title.trimmingCharacters(in: .whitespaces) != sanitizedTitle {
            issues.append(.unsafeTitle)
        }
        if let dueDateString {
            let calendar = TaskCalendar.gregorian(
                timeZone: TimeZone(secondsFromGMT: 0)!)
            if TaskCalendar.dateComponents(from: dueDateString)?
                .isValidDate(in: calendar) != true
            {
                issues.append(.invalidDate(dueDateString))
            }
        }
        if let dueTimeString, TaskCalendar.timeComponents(from: dueTimeString) == nil {
            issues.append(.invalidTime(dueTimeString))
        }
        if let dueDateString, let dueTimeString,
            case .failure(.nonexistentLocalTime) = TaskCalendar.resolve(
                date: dueDateString,
                time: dueTimeString,
                timeZone: timeZone,
                nonexistentTime: .reject,
                repeatedTime: .first)
        {
            issues.append(
                .nonexistentLocalTime(
                    date: dueDateString,
                    time: dueTimeString))
        }
        if dueDateString == nil, dueTimeString != nil || recurrence != nil {
            issues.append(.scheduleWithoutDate)
        }
        return issues
    }

    func validatedMarkdownLine(
        timeZone: TimeZone = .autoupdatingCurrent
    ) throws -> String {
        let issues = validationIssues(timeZone: timeZone)
        guard issues.isEmpty else { throw TaskDraftValidationError(issues: issues) }
        guard let dueDateString else { return "- [ ] \(sanitizedTitle)" }
        var line = "- [ ] \(sanitizedTitle) @due(\(dueDateString)"
        if let dueTimeString { line += " \(dueTimeString)" }
        line += ")"
        if let recurrence { line += " @repeat(\(recurrence.tagText))" }
        return line
    }

    /// Compatibility for storage code that predates throwing validation.
    /// UI and storage boundaries should call `validatedMarkdownLine()`.
    var markdownLine: String {
        (try? validatedMarkdownLine()) ?? "- [ ] \(sanitizedTitle)"
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
    struct Diagnostic: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case impossibleDate
            case ambiguousDate
            case ambiguousTime
            case ambiguousRecurrence
            case invalidTime
            case valueTooLarge
            case pastTime
        }

        let kind: Kind
        let message: String
        let sourceRange: NSRange

        /// A sentence that cannot be written down correctly is refused. An
        /// invalid date/time cannot pass storage validation, and competing
        /// time or recurrence expressions have no safe implicit winner.
        /// The remaining diagnostics describe a task Cove *can* record and
        /// the user may well have meant: a bare past time is deliberately
        /// today (grove parity), a clamped count resolves to a real date, and
        /// an ambiguous numeric date has already been resolved one way in the
        /// live preview. Those warn and leave return working.
        var blocksCapture: Bool {
            switch kind {
            case .impossibleDate, .ambiguousTime, .ambiguousRecurrence, .invalidTime:
                return true
            case .ambiguousDate, .valueTooLarge, .pastTime:
                return false
            }
        }
    }

    struct ParseResult: Equatable, Sendable {
        let draft: TaskDraft
        let diagnostics: [Diagnostic]

        var canCapture: Bool {
            diagnostics.allSatisfy { !$0.blocksCapture }
                && draft.validationIssues.isEmpty
        }
    }

    // MARK: - Grammar fragments (grove's WD / MONTH / MERIDIEM)

    private static let wd =
        #"(?:sun(?:day)?|mon(?:day)?|tue(?:sday|s)?|wed(?:nesday|s)?|thu(?:rsday|rs|r)?|fri(?:day)?|sat(?:urday)?)"#
    private static let month =
        #"(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember|t)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"#
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
        #"\b("# + month + #")\s+(\d{1,3})(?:st|nd|rd|th)?\b"#)
    private static let slashDateRegex = regex(
        #"(?:^|\s)(\d{1,3})/(\d{1,3})(?:/(\d{2,4}))?(?=\s|$)"#)

    // Times
    private static let timeRangeRegex = regex(
        #"\b(\d{1,2})(?::(\d{2}))?\s*("# + meridiem + #")?\s*(?:-|–|—|to\s)\s*(\d{1,2})(?::(\d{2}))?\s*("# + meridiem
            + #")\b"#)
    private static let noonRegex = regex(#"\b(?:noon|midday)\b"#)
    private static let midnightRegex = regex(#"\bmidnight\b"#)
    private static let hourMinuteRegex = regex(
        #"\b(\d{1,2}):(\d{2})\s*("# + meridiem + #")?(?=\s|$|[.,!?])"#)
    private static let compactTimeRegex = regex(
        #"\b(\d{3,4})\s*("# + meridiem + #")(?=\s|$|[.,!?])"#)
    private static let hourMeridiemRegex = regex(
        #"\b(\d{1,2})\s*("# + meridiem + #")(?=\s|$|[.,!?])"#)

    /// Keyed by the singular unit, and by the adverb, that `everyUnitRegex`
    /// and `adverbRegex` above can produce. They sit here, beside the patterns
    /// they mirror, because the two have to be edited together: a synonym
    /// added to one alternation and not to the map is a miss, and these are
    /// consulted while a sentence is still being typed.
    private static let unitFrequencies: [String: RecurrenceRule.Frequency] = [
        "day": .daily, "week": .weekly, "month": .monthly, "year": .yearly,
    ]

    private static let adverbFrequencies: [String: RecurrenceRule.Frequency] = [
        "daily": .daily, "weekly": .weekly, "monthly": .monthly,
        "yearly": .yearly, "annually": .yearly,
    ]

    private static let monthNumbers: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2,
        "mar": 3, "march": 3, "apr": 4, "april": 4, "may": 5,
        "jun": 6, "june": 6, "jul": 7, "july": 7, "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
        "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    /// Upper bound on the count in "in N days/weeks/months". Weeks multiply
    /// the count by seven, so an unbounded one overflows and traps the
    /// process while the sentence is still being typed — the live preview
    /// re-parses on every keystroke. Ten thousand of any unit is centuries
    /// out and still lands inside the four-digit year the `@due` tag stores.
    static let maximumRelativeUnits = 10_000

    /// Tracks which parts of the input are already consumed by an extractor.
    private struct Claims {
        private(set) var spans: [NSRange] = []

        func overlaps(_ range: NSRange) -> Bool {
            spans.contains {
                range.location < $0.location + $0.length
                    && range.location + range.length > $0.location
            }
        }

        mutating func tryClaim(_ range: NSRange) -> Bool {
            guard !overlaps(range) else { return false }
            spans.append(range)
            return true
        }
    }

    // MARK: - Parse

    /// `defaultingToToday` resolves an undated sentence to today, which is
    /// what the Tasks screen needs (`@due` is required there). The Lists
    /// screen passes false and keeps the item undated — a grocery item
    /// isn't due today just because it was typed today.
    static func parse(
        _ input: String,
        now: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        defaultingToToday: Bool = true
    ) -> TaskDraft {
        parseWithDiagnostics(
            input,
            now: now,
            timeZone: timeZone,
            defaultingToToday: defaultingToToday
        ).draft
    }

    static func parseWithDiagnostics(
        _ input: String,
        now: Date,
        timeZone: TimeZone = .autoupdatingCurrent,
        defaultingToToday: Bool = true
    ) -> ParseResult {
        let calendar = TaskCalendar.gregorian(timeZone: timeZone)
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
        var diagnostics: [Diagnostic] = []
        var dateCandidates: Set<String> = []
        var timeSourceRange: NSRange?

        func text(_ match: NSTextCheckingResult, _ group: Int) -> String? {
            let range = match.range(at: group)
            guard range.location != NSNotFound else { return nil }
            return lower.substring(with: range)
        }
        func setDate(_ dayOffsetFromNow: Int) {
            let resolved = ymdString(
                from: addDays(
                    dayOffsetFromNow, to: now,
                    calendar: calendar),
                calendar: calendar)
            dateCandidates.insert(resolved)
            if date == nil { date = resolved }
        }
        func setDate(to resolved: Date) {
            let string = ymdString(from: resolved, calendar: calendar)
            dateCandidates.insert(string)
            if date == nil { date = string }
        }
        func recordInvalidTime(_ range: NSRange) {
            diagnostics.append(
                Diagnostic(
                    kind: .invalidTime,
                    message: "That is not a valid clock time.",
                    sourceRange: range))
        }
        func recordAmbiguousRecurrence(_ range: NSRange) {
            diagnostics.append(
                Diagnostic(
                    kind: .ambiguousRecurrence,
                    message:
                        "This sentence contains more than one repeat rule. Keep one rule or edit the task details.",
                    sourceRange: range))
        }
        func setRecurrence(
            _ rule: RecurrenceRule,
            range: NSRange
        ) {
            guard !claims.overlaps(range) else { return }
            guard recurrence == nil else {
                recordAmbiguousRecurrence(range)
                return
            }
            guard claims.tryClaim(range) else { return }
            recurrence = rule
        }
        func setTime(
            _ resolved: String,
            range: NSRange
        ) {
            guard !claims.overlaps(range) else { return }
            guard time == nil else {
                diagnostics.append(
                    Diagnostic(
                        kind: .ambiguousTime,
                        message:
                            "This sentence contains more than one time. Keep one time or edit the task details.",
                        sourceRange: range))
                return
            }
            guard claims.tryClaim(range) else { return }
            time = resolved
            timeSourceRange = range
        }

        // ---- 1. Recurrence ("every ...") ---------------------------------
        everyUnitRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, !claims.overlaps(m.range), let unit = text(m, 2) else {
                return
            }
            let singular = unit.hasSuffix("s") ? String(unit.dropLast()) : unit
            guard let frequency = unitFrequencies[singular] else { return }
            let typedInterval =
                text(m, 1).map { Int($0) ?? Int.max } ?? 1
            if typedInterval > RecurrenceRule.maximumInterval {
                diagnostics.append(
                    Diagnostic(
                        kind: .valueTooLarge,
                        message:
                            "Repeat intervals cannot exceed \(RecurrenceRule.maximumInterval). Choose a smaller interval.",
                        sourceRange: m.range))
            }
            setRecurrence(
                RecurrenceRule(
                    frequency: frequency,
                    interval: typedInterval),
                range: m.range)
        }

        everyWeekdaySetRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, !claims.overlaps(m.range), let list = text(m, 1) else {
                return
            }
            if list == "weekday" || list == "weekdays" {
                setRecurrence(.everyWeekday, range: m.range)
            } else {
                let weekdays =
                    list
                    .components(separatedBy: CharacterSet(charactersIn: " ,&"))
                    .filter { !$0.isEmpty && $0 != "and" }
                    .compactMap { RecurrenceRule.weekdayNumber(for: $0) }
                setRecurrence(
                    RecurrenceRule(frequency: .weekly, byWeekday: weekdays),
                    range: m.range)
            }
        }

        adverbRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, !claims.overlaps(m.range),
                let word = text(m, 1), let frequency = adverbFrequencies[word]
            else { return }
            setRecurrence(
                RecurrenceRule(frequency: frequency),
                range: m.range)
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
            setDate(
                to: upcomingWeekday(
                    2, from: tomorrow, includeToday: true,
                    calendar: calendar))
        }
        nextWeekdayRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, let weekday = RecurrenceRule.weekdayNumber(for: text(m, 1)!),
                claims.tryClaim(m.range)
            else { return }
            setDate(
                to: upcomingWeekday(
                    weekday, from: now, includeToday: false,
                    calendar: calendar))
        }
        weekdayRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, let weekday = RecurrenceRule.weekdayNumber(for: text(m, 1)!),
                claims.tryClaim(m.range)
            else { return }
            setDate(
                to: upcomingWeekday(
                    weekday, from: now, includeToday: true,
                    calendar: calendar))
        }
        inUnitsRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, let count = text(m, 1) else { return }
            let typed = Int(count) ?? Int.max
            let n = min(typed, maximumRelativeUnits)
            let unit = text(m, 2)!
            guard claims.tryClaim(m.range) else { return }
            if typed > maximumRelativeUnits {
                diagnostics.append(
                    Diagnostic(
                        kind: .valueTooLarge,
                        message:
                            "Relative dates cannot exceed \(maximumRelativeUnits) units. Choose a smaller value.",
                        sourceRange: m.range))
            }
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
                let day = text(m, 2).flatMap(Int.init), claims.tryClaim(m.range)
            else { return }
            guard (1...31).contains(day) else {
                diagnostics.append(
                    Diagnostic(
                        kind: .impossibleDate,
                        message: "Day \(day) is outside the valid range 1 through 31.",
                        sourceRange: m.range))
                return
            }
            guard
                let resolved = upcomingMonthDay(
                    month: monthNumber, day: day,
                    now: now, calendar: calendar)
            else {
                diagnostics.append(
                    Diagnostic(
                        kind: .impossibleDate,
                        message: "That month does not have day \(day).",
                        sourceRange: m.range))
                return
            }
            setDate(to: resolved)
        }
        slashDateRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, let monthNumber = text(m, 1).flatMap(Int.init),
                let day = text(m, 2).flatMap(Int.init)
            else { return }
            // The rule anchors on leading whitespace; claim only the token.
            let matched = lower.substring(with: m.range)
            let lead = matched.count - matched.drop(while: \.isWhitespace).count
            let token = NSRange(
                location: m.range.location + lead,
                length: m.range.length - lead)
            guard claims.tryClaim(token) else { return }
            guard (1...12).contains(monthNumber), (1...31).contains(day) else {
                diagnostics.append(
                    Diagnostic(
                        kind: .impossibleDate,
                        message:
                            "\(monthNumber)/\(day) is outside the valid month/day range.",
                        sourceRange: token))
                return
            }

            var resolved: Date?
            if let yearText = text(m, 3), var year = Int(yearText) {
                if year < 100 { year += 2000 }
                let components = DateComponents(
                    year: year, month: monthNumber, day: day, hour: 12)
                if components.isValidDate(in: calendar) {
                    resolved = calendar.date(from: components)
                }
            } else {
                resolved = upcomingMonthDay(
                    month: monthNumber, day: day,
                    now: now, calendar: calendar)
            }
            guard let resolved else {
                diagnostics.append(
                    Diagnostic(
                        kind: .impossibleDate,
                        message: "\(monthNumber)/\(day) is not a real calendar date.",
                        sourceRange: token))
                return
            }
            setDate(to: resolved)
        }

        // ---- 3. Time ranges (7-9pm, 3-4:30pm) -----------------------------
        // Cove has no calendar events, so the range's start time is used and
        // the end time is dropped; the whole range span still leaves the title.
        timeRangeRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, !claims.overlaps(m.range) else { return }
            let endMeridiem = normalizeMeridiem(text(m, 6))
            let startMeridiem = normalizeMeridiem(text(m, 3)) ?? endMeridiem
            let start = toHHMM(
                hour: text(m, 1).flatMap(Int.init) ?? 0,
                minute: text(m, 2).flatMap(Int.init) ?? 0,
                meridiem: startMeridiem)
            let end = toHHMM(
                hour: text(m, 4).flatMap(Int.init) ?? 0,
                minute: text(m, 5).flatMap(Int.init) ?? 0,
                meridiem: endMeridiem)
            guard let start, end != nil else {
                recordInvalidTime(m.range)
                return
            }
            setTime(start, range: m.range)
        }

        // ---- 4. Single times ----------------------------------------------
        noonRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m else { return }
            setTime("12:00", range: m.range)
        }
        midnightRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m else { return }
            setTime("00:00", range: m.range)
        }
        hourMinuteRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, !claims.overlaps(m.range) else { return }
            guard
                let resolved = toHHMM(
                    hour: text(m, 1).flatMap(Int.init) ?? 0,
                    minute: text(m, 2).flatMap(Int.init) ?? 0,
                    meridiem: normalizeMeridiem(text(m, 3)))
            else {
                recordInvalidTime(m.range)
                return
            }
            setTime(resolved, range: m.range)
        }
        compactTimeRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, !claims.overlaps(m.range), let digits = text(m, 1) else {
                return
            }
            let hour = Int(digits.dropLast(2)) ?? 0
            let minute = Int(digits.suffix(2)) ?? 0
            guard
                let resolved = toHHMM(
                    hour: hour, minute: minute,
                    meridiem: normalizeMeridiem(text(m, 2)))
            else {
                recordInvalidTime(m.range)
                return
            }
            setTime(resolved, range: m.range)
        }
        hourMeridiemRegex.enumerateMatches(in: lower as String, range: whole) { m, _, _ in
            guard let m, !claims.overlaps(m.range) else { return }
            guard
                let resolved = toHHMM(
                    hour: text(m, 1).flatMap(Int.init) ?? 0,
                    minute: 0,
                    meridiem: normalizeMeridiem(text(m, 2)))
            else {
                recordInvalidTime(m.range)
                return
            }
            setTime(resolved, range: m.range)
        }

        // ---- 5. Finalize ---------------------------------------------------
        if tonight, time == nil { time = "20:00" }

        // A bare time means today: `retainer 940p` is tonight's 9:40 PM.
        var resolvedBareTimeToToday = false
        if time != nil, date == nil, recurrence == nil {
            date = ymdString(from: now, calendar: calendar)
            resolvedBareTimeToToday = true
        }

        if let rule = recurrence, date == nil {
            if rule.frequency == .weekly, !rule.byWeekday.isEmpty {
                // First occurrence: the next matching weekday, today included.
                let candidates = rule.byWeekday.map {
                    upcomingWeekday(
                        $0, from: now, includeToday: true,
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
        let resolvedDate =
            date
            ?? (defaultingToToday
                ? ymdString(from: now, calendar: calendar) : nil)

        if let resolvedDate, let time {
            switch TaskCalendar.resolve(
                date: resolvedDate,
                time: time,
                timeZone: timeZone,
                nonexistentTime: .reject,
                repeatedTime: .first)
            {
            case .failure(.nonexistentLocalTime):
                diagnostics.append(
                    Diagnostic(
                        kind: .invalidTime,
                        message:
                            "\(resolvedDate) at \(time) does not exist in this time zone because the clock moves forward.",
                        sourceRange: timeSourceRange ?? whole))
            case .success, .failure:
                break
            }
        }

        if resolvedBareTimeToToday, let resolvedDate, let time,
            case .success(let resolution) = TaskCalendar.resolve(
                date: resolvedDate,
                time: time,
                timeZone: timeZone,
                nonexistentTime: .reject,
                repeatedTime: .first),
            resolution.date <= now
        {
            diagnostics.append(
                Diagnostic(
                    kind: .pastTime,
                    message:
                        "That time has already passed today. Add a date or choose a future time.",
                    sourceRange: timeSourceRange ?? whole))
        }

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

        if dateCandidates.count > 1 {
            diagnostics.append(
                Diagnostic(
                    kind: .ambiguousDate,
                    message:
                        "This sentence contains dates that resolve differently. Keep one date or choose it explicitly.",
                    sourceRange: whole))
        }

        return ParseResult(
            draft: TaskDraft(
                title: title,
                dueDateString: resolvedDate,
                dueTimeString: time,
                recurrence: recurrence),
            diagnostics: diagnostics)
    }

    // MARK: - Helpers

    private static func cleanedTitle(_ raw: String) -> String {
        var title =
            raw
            .replacingOccurrences(
                of: #"\s+"#, with: " ",
                options: .regularExpression
            )
            // Drop connector words left dangling once their token was consumed.
            .replacingOccurrences(
                of: #"\s+(?:at|on|due|by|from)\s*$"#, with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"^\s*(?:at|on)\s+"#, with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(
                of: #"[,;]\s*$"#, with: "",
                options: .regularExpression
            )
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
    private static func toHHMM(
        hour rawHour: Int, minute: Int,
        meridiem: String?
    ) -> String? {
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

    private static func addDays(
        _ days: Int, to date: Date,
        calendar: Calendar
    ) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    /// Next occurrence of `weekday` (1 = Sunday … 7 = Saturday) counted from
    /// `from`. Plain "fri" includes today; "next fri" is strictly future and
    /// lands a full week out when said on a Friday.
    private static func upcomingWeekday(
        _ weekday: Int, from: Date,
        includeToday: Bool,
        calendar: Calendar
    ) -> Date {
        var ahead = (weekday - calendar.component(.weekday, from: from) + 7) % 7
        if ahead == 0, !includeToday { ahead = 7 }
        return addDays(ahead, to: from, calendar: calendar)
    }

    /// Resolve month/day to a concrete date: the next time that day occurs.
    private static func upcomingMonthDay(
        month: Int, day: Int, now: Date,
        calendar: Calendar
    ) -> Date? {
        let currentYear = calendar.component(.year, from: now)
        let today = ymdString(from: now, calendar: calendar)
        // Eight years comfortably crosses the Gregorian leap-year cycle for
        // Feb 29 while still rejecting dates such as Apr 31.
        for year in currentYear...(currentYear + 8) {
            let components = DateComponents(
                year: year, month: month, day: day, hour: 12)
            guard components.isValidDate(in: calendar),
                let candidate = calendar.date(from: components)
            else { continue }
            if ymdString(from: candidate, calendar: calendar) >= today {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Formatting

    static func ymdString(
        from date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        ymdString(from: date, calendar: TaskCalendar.gregorian(timeZone: timeZone))
    }

    /// The resolved-calendar form, for the parser's own internals — they hold
    /// one Gregorian calendar for the whole parse rather than rebuilding it
    /// per token.
    static func ymdString(from date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
