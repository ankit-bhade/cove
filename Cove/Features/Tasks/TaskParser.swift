import Foundation

/// Pure line-based scanner for the fixed task syntax:
///
///     - [ ] Task text @due(YYYY-MM-DD)
///     - [ ] Task text @due(YYYY-MM-DD HH:MM)
///     - [ ] Task text @due(YYYY-MM-DD HH:MM) @repeat(every sunday)
///
/// The syntax is strict by spec: no leading indentation, exactly one space
/// after `]` and before `@due`, a real calendar date, a valid 24-hour time
/// when present, a recognized `@repeat` tag when present, and nothing after
/// the last closing parenthesis except trailing whitespace. The status may
/// be ` `, `x`, or `X` (matching the editor's checkbox parser). When the
/// text itself contains an `@due(...)`, the last one on the line is the tag.
///
/// `sectioned` parsing adds the one relaxation the Lists feature needs, and
/// it applies to the capture note (`Tasks.md`) alone: a `##` heading opens a
/// named list, tasks below it carry that `listName`, and *those* tasks may
/// omit `@due` entirely (a grocery item rarely has a due date). A `#`
/// heading closes the current list. Every other note parses unsectioned,
/// where headings mean nothing and `@due` stays mandatory — so no stray
/// checkbox anywhere in the vault becomes a task.
enum TaskParser {
    struct ParsedTask: Equatable, Sendable {
        /// 0-based line index within the parsed text.
        let lineNumber: Int
        /// UTF-16 range of the whole line, including its line ending when
        /// present. Used when clearing completed tasks from their notes.
        let lineRange: NSRange
        /// UTF-16 range of the single status character in the parsed text.
        let statusRange: NSRange
        /// UTF-16 range of the `YYYY-MM-DD` date in the parsed text, so a
        /// recurring task's date can be advanced in place. Nil for an
        /// undated list item.
        let dueDateRange: NSRange?
        /// The task text between the marker and the `@due` tag.
        let text: String
        /// The validated `YYYY-MM-DD` date, or nil for an undated list item.
        /// Zero-padded, so lexicographic order is chronological order.
        let dueDateString: String?
        /// The validated `HH:MM` 24-hour time, when the tag carries one.
        let dueTimeString: String?
        let recurrence: RecurrenceRule?
        let isCompleted: Bool
        /// The `##` list this task sits under, when parsed `sectioned`.
        let listName: String?
    }

    private static let taskLineRegex = try! NSRegularExpression(
        pattern:
            #"^- \[([ xX])\] (\S(?:.*\S)?) @due\(((\d{4})-(\d{2})-(\d{2}))( (\d{2}):(\d{2}))?\)( @repeat\(([a-z0-9 ]+)\))?[ \t]*$"#
    )

    /// Same marker, no tags — only honored inside a list section, and only
    /// when the text carries no `@due(` of its own (so a line with a
    /// malformed date stays rejected instead of becoming an oddly-titled
    /// undated item).
    private static let undatedTaskLineRegex = try! NSRegularExpression(
        pattern: #"^- \[([ xX])\] (\S(?:.*\S)?)[ \t]*$"#)

    private static let gregorian = TaskCalendar.gregorian(timeZone: TimeZone(secondsFromGMT: 0)!)

    static func tasks(in text: String, sectioned: Bool = false) -> [ParsedTask] {
        let ns = text as NSString
        var tasks: [ParsedTask] = []
        var lineNumber = 0
        var listName: String?
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: [.byLines, .substringNotRequired]
        ) {
            _, lineRange, enclosingRange, _ in
            defer { lineNumber += 1 }
            let line = ns.substring(with: lineRange)
            let wholeLine = NSRange(location: 0, length: (line as NSString).length)

            if sectioned, let heading = TaskListDocument.headingName(in: line) {
                // A `#` heading yields an empty name: it closes the open list
                // without opening one.
                listName = heading.isEmpty ? nil : heading
                return
            }

            guard let match = taskLineRegex.firstMatch(in: line, range: wholeLine) else {
                if sectioned, let list = listName,
                    let undated = undatedTask(
                        in: line, lineNumber: lineNumber,
                        lineRange: lineRange,
                        enclosingRange: enclosingRange,
                        listName: list)
                {
                    tasks.append(undated)
                }
                return
            }

            let year = Int((line as NSString).substring(with: match.range(at: 4)))!
            let month = Int((line as NSString).substring(with: match.range(at: 5)))!
            let day = Int((line as NSString).substring(with: match.range(at: 6)))!
            guard
                DateComponents(year: year, month: month, day: day)
                    .isValidDate(in: gregorian)
            else { return }

            var timeString: String?
            if match.range(at: 7).location != NSNotFound {
                let hour = Int((line as NSString).substring(with: match.range(at: 8)))!
                let minute = Int((line as NSString).substring(with: match.range(at: 9)))!
                guard (0...23).contains(hour), (0...59).contains(minute) else { return }
                timeString = String(format: "%02d:%02d", hour, minute)
            }

            var recurrence: RecurrenceRule?
            if match.range(at: 10).location != NSNotFound {
                let tag = (line as NSString).substring(with: match.range(at: 11))
                guard let rule = RecurrenceRule(tagText: tag) else { return }
                recurrence = rule
            }

            let statusInLine = match.range(at: 1)
            let status = (line as NSString).substring(with: statusInLine)
            let dateInLine = match.range(at: 3)
            tasks.append(
                ParsedTask(
                    lineNumber: lineNumber,
                    lineRange: enclosingRange,
                    statusRange: NSRange(
                        location: lineRange.location + statusInLine.location,
                        length: statusInLine.length),
                    dueDateRange: NSRange(
                        location: lineRange.location + dateInLine.location,
                        length: dateInLine.length),
                    text: (line as NSString).substring(with: match.range(at: 2)),
                    dueDateString: String(format: "%04d-%02d-%02d", year, month, day),
                    dueTimeString: timeString,
                    recurrence: recurrence,
                    isCompleted: status.lowercased() == "x",
                    listName: listName))
        }
        return tasks
    }

    /// A bare `- [ ] text` line inside a list section.
    private static func undatedTask(
        in line: String,
        lineNumber: Int,
        lineRange: NSRange,
        enclosingRange: NSRange,
        listName: String
    ) -> ParsedTask? {
        let ns = line as NSString
        guard !line.contains("@due("),
            let match = undatedTaskLineRegex.firstMatch(
                in: line, range: NSRange(location: 0, length: ns.length))
        else { return nil }

        let statusInLine = match.range(at: 1)
        return ParsedTask(
            lineNumber: lineNumber,
            lineRange: enclosingRange,
            statusRange: NSRange(
                location: lineRange.location + statusInLine.location,
                length: statusInLine.length),
            dueDateRange: nil,
            text: ns.substring(with: match.range(at: 2)),
            dueDateString: nil,
            dueTimeString: nil,
            recurrence: nil,
            isCompleted: ns.substring(with: statusInLine).lowercased() == "x",
            listName: listName)
    }

    /// Returns `fileText` with the matching task toggled, or nil if no task
    /// in the text matches. Called on a fresh read of the file, so a task
    /// indexed earlier is re-found by content: among tasks with the same
    /// text, schedule, and state, the one on the remembered line wins (in
    /// case of duplicates), falling back to the first if lines have shifted.
    ///
    /// Completing an incomplete *recurring* task advances its due date to
    /// the rule's next occurrence after the later of the current due date
    /// and `todayDateString`, leaving the checkbox open — the line is the
    /// task's single home, so recurrence rolls it forward instead of
    /// checking it off. Every other toggle flips the status character.
    static func togglingTask(
        withText taskText: String,
        dueDateString: String?,
        dueTimeString: String?,
        recurrence: RecurrenceRule?,
        isCompleted: Bool,
        listName: String?,
        preferredLineNumber: Int,
        todayDateString: String,
        in fileText: String
    ) -> String? {
        guard
            let match = matchingTask(
                withText: taskText,
                dueDateString: dueDateString,
                dueTimeString: dueTimeString,
                recurrence: recurrence,
                isCompleted: isCompleted,
                listName: listName,
                preferredLineNumber: preferredLineNumber,
                in: fileText)
        else { return nil }

        if let rule = match.recurrence, !match.isCompleted,
            let currentDate = match.dueDateString, let dateRange = match.dueDateRange
        {
            let base = max(currentDate, todayDateString)
            guard let next = rule.nextDueDateString(after: base) else { return nil }
            return (fileText as NSString)
                .replacingCharacters(in: dateRange, with: next)
        }
        return (fileText as NSString)
            .replacingCharacters(in: match.statusRange, with: isCompleted ? " " : "x")
    }

    /// Idempotently puts the identified task in `desiredCompletion`. The
    /// latest file text is parsed on every call. For an incomplete recurring
    /// task, completing means advancing that occurrence once; a retry carrying
    /// the old due-date identity no longer matches and is therefore stale,
    /// never a second toggle.
    static func settingTaskCompleted(
        _ identity: TaskIdentity,
        to desiredCompletion: Bool,
        todayDateString: String,
        in fileText: String
    ) -> String? {
        guard let match = matchingTask(identity, in: fileText) else { return nil }
        if match.isCompleted == desiredCompletion { return fileText }

        if desiredCompletion,
            let rule = match.recurrence,
            let currentDate = match.dueDateString,
            let dateRange = match.dueDateRange
        {
            let base = max(currentDate, todayDateString)
            guard let next = rule.nextDueDateString(after: base) else { return nil }
            return (fileText as NSString).replacingCharacters(in: dateRange, with: next)
        }

        return (fileText as NSString).replacingCharacters(
            in: match.statusRange,
            with: desiredCompletion ? "x" : " ")
    }

    /// Returns `fileText` with the matching task's whole line removed, or nil
    /// if no task in the text matches. Re-finds the task the same way
    /// `togglingTask` does, so a line that changed on disk is left alone and
    /// the caller can report it instead of deleting the wrong task.
    static func removingTask(
        withText taskText: String,
        dueDateString: String?,
        dueTimeString: String?,
        recurrence: RecurrenceRule?,
        isCompleted: Bool,
        listName: String?,
        preferredLineNumber: Int,
        in fileText: String
    ) -> String? {
        guard
            let match = matchingTask(
                withText: taskText,
                dueDateString: dueDateString,
                dueTimeString: dueTimeString,
                recurrence: recurrence,
                isCompleted: isCompleted,
                listName: listName,
                preferredLineNumber: preferredLineNumber,
                in: fileText)
        else { return nil }
        return (fileText as NSString).replacingCharacters(in: match.lineRange, with: "")
    }

    /// Deletes by semantic identity while deliberately ignoring completion
    /// state, so a concurrent completion followed by deletion still removes
    /// the intended line rather than a stale offset or an unrelated task.
    static func removingTask(_ identity: TaskIdentity, in fileText: String) -> String? {
        guard let match = matchingTask(identity, in: fileText) else { return nil }
        return (fileText as NSString).replacingCharacters(in: match.lineRange, with: "")
    }

    static func matchingTask(
        _ identity: TaskIdentity,
        in fileText: String
    ) -> ParsedTask? {
        let candidates = tasks(in: fileText, sectioned: identity.listName != nil).filter {
            $0.text == identity.text
                && $0.dueDateString == identity.dueDateString
                && $0.dueTimeString == identity.dueTimeString
                && $0.recurrence == identity.recurrence
                && $0.listName == identity.listName
        }
        return candidates.first(where: { $0.lineNumber == identity.lineNumber })
            ?? candidates.first
    }

    /// Re-finds one indexed task in a fresh read of its file: among tasks with
    /// the same text, schedule, and state, the one on the remembered line wins
    /// (in case of duplicates), falling back to the first if lines shifted.
    private static func matchingTask(
        withText taskText: String,
        dueDateString: String?,
        dueTimeString: String?,
        recurrence: RecurrenceRule?,
        isCompleted: Bool,
        listName: String?,
        preferredLineNumber: Int,
        in fileText: String
    ) -> ParsedTask? {
        // An undated task only exists in a sectioned parse, and the list a
        // task belongs to is part of its identity — two lists can hold the
        // same item text.
        let candidates = tasks(in: fileText, sectioned: listName != nil).filter {
            $0.text == taskText
                && $0.dueDateString == dueDateString
                && $0.dueTimeString == dueTimeString
                && $0.recurrence == recurrence
                && $0.isCompleted == isCompleted
                && $0.listName == listName
        }
        return candidates.first(where: { $0.lineNumber == preferredLineNumber })
            ?? candidates.first
    }

    /// Removes every completed line matching Cove's strict task syntax while
    /// preserving incomplete tasks and all other Markdown verbatim. Each
    /// screen clears only what it shows: with no `inList` name, tasks that
    /// belong to a list are left alone (the Tasks screen's Clear All), and
    /// with one, only that list's items go (a list's own Clear Completed).
    static func clearingCompletedTasks(
        in fileText: String,
        sectioned: Bool = false,
        inList listName: String? = nil
    ) -> String {
        let completedRanges = tasks(in: fileText, sectioned: sectioned)
            .filter { $0.isCompleted && belongsToList(listName, $0.listName) }
            .map(\.lineRange)
            .sorted { $0.location > $1.location }
        guard !completedRanges.isEmpty else { return fileText }

        let result = NSMutableString(string: fileText)
        for range in completedRanges {
            result.replaceCharacters(in: range, with: "")
        }
        return result as String
    }

    /// A list's identity is its heading text, matched the way the rest of the
    /// feature matches it: case-insensitively. No name means the unlisted
    /// tasks, which are the only ones the Tasks screen shows.
    private static func belongsToList(_ wanted: String?, _ actual: String?) -> Bool {
        guard let wanted else { return actual == nil }
        return actual?.caseInsensitiveCompare(wanted) == .orderedSame
    }
}
