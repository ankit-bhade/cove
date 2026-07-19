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
        /// recurring task's date can be advanced in place.
        let dueDateRange: NSRange
        /// The task text between the marker and the `@due` tag.
        let text: String
        /// The validated `YYYY-MM-DD` date. Zero-padded, so lexicographic
        /// order is chronological order.
        let dueDateString: String
        /// The validated `HH:MM` 24-hour time, when the tag carries one.
        let dueTimeString: String?
        let recurrence: RecurrenceRule?
        let isCompleted: Bool
    }

    private static let taskLineRegex = try! NSRegularExpression(
        pattern: #"^- \[([ xX])\] (\S(?:.*\S)?) @due\(((\d{4})-(\d{2})-(\d{2}))( (\d{2}):(\d{2}))?\)( @repeat\(([a-z0-9 ]+)\))?[ \t]*$"#)

    private static let gregorian = Calendar(identifier: .gregorian)

    static func tasks(in text: String) -> [ParsedTask] {
        let ns = text as NSString
        var tasks: [ParsedTask] = []
        var lineNumber = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines, .substringNotRequired]) {
            _, lineRange, enclosingRange, _ in
            defer { lineNumber += 1 }
            let line = ns.substring(with: lineRange)
            let wholeLine = NSRange(location: 0, length: (line as NSString).length)
            guard let match = taskLineRegex.firstMatch(in: line, range: wholeLine) else { return }

            let year = Int((line as NSString).substring(with: match.range(at: 4)))!
            let month = Int((line as NSString).substring(with: match.range(at: 5)))!
            let day = Int((line as NSString).substring(with: match.range(at: 6)))!
            guard DateComponents(year: year, month: month, day: day)
                .isValidDate(in: gregorian) else { return }

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
            tasks.append(ParsedTask(
                lineNumber: lineNumber,
                lineRange: enclosingRange,
                statusRange: NSRange(location: lineRange.location + statusInLine.location,
                                     length: statusInLine.length),
                dueDateRange: NSRange(location: lineRange.location + dateInLine.location,
                                      length: dateInLine.length),
                text: (line as NSString).substring(with: match.range(at: 2)),
                dueDateString: String(format: "%04d-%02d-%02d", year, month, day),
                dueTimeString: timeString,
                recurrence: recurrence,
                isCompleted: status.lowercased() == "x"))
        }
        return tasks
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
    static func togglingTask(withText taskText: String,
                             dueDateString: String,
                             dueTimeString: String?,
                             recurrence: RecurrenceRule?,
                             isCompleted: Bool,
                             preferredLineNumber: Int,
                             todayDateString: String,
                             in fileText: String) -> String? {
        let candidates = tasks(in: fileText).filter {
            $0.text == taskText
                && $0.dueDateString == dueDateString
                && $0.dueTimeString == dueTimeString
                && $0.recurrence == recurrence
                && $0.isCompleted == isCompleted
        }
        guard let match = candidates.first(where: { $0.lineNumber == preferredLineNumber })
                ?? candidates.first else { return nil }

        if let rule = match.recurrence, !match.isCompleted {
            let base = max(match.dueDateString, todayDateString)
            guard let next = rule.nextDueDateString(after: base) else { return nil }
            return (fileText as NSString)
                .replacingCharacters(in: match.dueDateRange, with: next)
        }
        return (fileText as NSString)
            .replacingCharacters(in: match.statusRange, with: isCompleted ? " " : "x")
    }

    /// Removes every completed line matching Cove's strict task syntax while
    /// preserving incomplete tasks and all other Markdown verbatim.
    static func clearingCompletedTasks(in fileText: String) -> String {
        let completedRanges = tasks(in: fileText)
            .filter(\.isCompleted)
            .map(\.lineRange)
            .sorted { $0.location > $1.location }
        guard !completedRanges.isEmpty else { return fileText }

        let result = NSMutableString(string: fileText)
        for range in completedRanges {
            result.replaceCharacters(in: range, with: "")
        }
        return result as String
    }
}
