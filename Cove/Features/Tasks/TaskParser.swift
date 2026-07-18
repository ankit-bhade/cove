import Foundation

/// Pure line-based scanner for the fixed task syntax:
///
///     - [ ] Task text @due(YYYY-MM-DD)
///
/// The syntax is strict by spec: no leading indentation, exactly one space
/// after `]` and before `@due`, a real calendar date, and nothing after the
/// closing parenthesis except trailing whitespace. The status may be ` `,
/// `x`, or `X` (matching the editor's checkbox parser). When the text itself
/// contains an `@due(...)`, the last one on the line is the tag.
enum TaskParser {
    struct ParsedTask: Equatable, Sendable {
        /// 0-based line index within the parsed text.
        let lineNumber: Int
        /// UTF-16 range of the single status character in the parsed text.
        let statusRange: NSRange
        /// The task text between the marker and the `@due` tag.
        let text: String
        /// The validated `YYYY-MM-DD` date. Zero-padded, so lexicographic
        /// order is chronological order.
        let dueDateString: String
        let isCompleted: Bool
    }

    private static let taskLineRegex = try! NSRegularExpression(
        pattern: #"^- \[([ xX])\] (\S(?:.*\S)?) @due\((\d{4})-(\d{2})-(\d{2})\)[ \t]*$"#)

    private static let gregorian = Calendar(identifier: .gregorian)

    static func tasks(in text: String) -> [ParsedTask] {
        let ns = text as NSString
        var tasks: [ParsedTask] = []
        var lineNumber = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            defer { lineNumber += 1 }
            let line = ns.substring(with: lineRange)
            let wholeLine = NSRange(location: 0, length: (line as NSString).length)
            guard let match = taskLineRegex.firstMatch(in: line, range: wholeLine) else { return }

            let year = Int((line as NSString).substring(with: match.range(at: 3)))!
            let month = Int((line as NSString).substring(with: match.range(at: 4)))!
            let day = Int((line as NSString).substring(with: match.range(at: 5)))!
            guard DateComponents(year: year, month: month, day: day)
                .isValidDate(in: gregorian) else { return }

            let statusInLine = match.range(at: 1)
            let status = (line as NSString).substring(with: statusInLine)
            tasks.append(ParsedTask(
                lineNumber: lineNumber,
                statusRange: NSRange(location: lineRange.location + statusInLine.location,
                                     length: statusInLine.length),
                text: (line as NSString).substring(with: match.range(at: 2)),
                dueDateString: String(format: "%04d-%02d-%02d", year, month, day),
                isCompleted: status.lowercased() == "x"))
        }
        return tasks
    }

    /// Returns `fileText` with the matching task's status flipped, or nil if
    /// no task in the text matches. Called on a fresh read of the file, so a
    /// task indexed earlier is re-found by content: among tasks with the same
    /// text, due date, and state, the one on the remembered line wins (in
    /// case of duplicates), falling back to the first if lines have shifted.
    static func togglingTask(withText taskText: String,
                             dueDateString: String,
                             isCompleted: Bool,
                             preferredLineNumber: Int,
                             in fileText: String) -> String? {
        let candidates = tasks(in: fileText).filter {
            $0.text == taskText
                && $0.dueDateString == dueDateString
                && $0.isCompleted == isCompleted
        }
        guard let match = candidates.first(where: { $0.lineNumber == preferredLineNumber })
                ?? candidates.first else { return nil }
        return (fileText as NSString)
            .replacingCharacters(in: match.statusRange, with: isCompleted ? " " : "x")
    }
}
