import Foundation

/// Pure line-based scanner for the Markdown constructs the editor styles
/// live: ATX headers, `**bold**` spans, and `- [ ]` checkboxes. All ranges
/// are UTF-16 `NSRange`s so they apply directly to an `NSTextStorage`.
enum MarkdownParser {
    struct Header: Equatable {
        /// 1 through 6, one per leading `#`.
        let level: Int
        /// The whole line, excluding the trailing newline.
        let lineRange: NSRange
        /// The leading hashes.
        let markerRange: NSRange
    }

    struct Bold: Equatable {
        /// The full `**text**` span including both delimiters.
        let range: NSRange
        let leadingDelimiterRange: NSRange
        let trailingDelimiterRange: NSRange
    }

    struct Checkbox: Equatable {
        /// The `- [ ]` marker, excluding any leading indentation.
        let markerRange: NSRange
        /// The single status character between the brackets.
        let statusRange: NSRange
        let isChecked: Bool
        /// Whole source line excluding its terminator. Editor integrations
        /// use this to route recurring Cove tasks through semantic mutation
        /// instead of blindly flipping one character.
        let lineRange: NSRange
        /// The task text after the marker, excluding the separating space.
        /// Empty for a bare `- [ ]` line.
        let textRange: NSRange

        /// Replacement for `statusRange` that flips the checked state.
        var toggledStatus: String { isChecked ? " " : "x" }
    }

    struct Result: Equatable {
        var headers: [Header] = []
        var boldSpans: [Bold] = []
        var checkboxes: [Checkbox] = []

        /// The checkbox whose marker contains the given UTF-16 index, used to
        /// hit-test taps and clicks.
        func checkbox(at index: Int) -> Checkbox? {
            checkboxes.first { NSLocationInRange(index, $0.markerRange) }
        }
    }

    private static let headerRegex = try! NSRegularExpression(
        pattern: #"^(#{1,6})[ \t].*$"#)
    // Content excludes `*` and newlines, so spans never cross lines and
    // stray asterisks fall back to plain text.
    private static let boldRegex = try! NSRegularExpression(
        pattern: #"\*\*([^*\n]+?)\*\*"#)
    private static let checkboxRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*([-+*][ \t]+\[([ xX])\])(?=[ \t]|$)"#)

    static func parse(_ text: String) -> Result {
        let ns = text as NSString
        var result = Result()
        let document = MarkdownContextScanner.scan(text)

        for line in document.lines where !line.isLiteral {
            let lineNS = line.text as NSString
            let localRange = NSRange(location: 0, length: lineNS.length)

            if let match = headerRegex.firstMatch(in: line.text, range: localRange) {
                let marker = absolute(match.range(at: 1), line: line)
                result.headers.append(
                    Header(
                        level: marker.length,
                        lineRange: line.range,
                        markerRange: marker))
            }

            boldRegex.enumerateMatches(in: line.text, range: localRange) { match, _, _ in
                guard let match else { return }
                let range = absolute(match.range, line: line)
                result.boldSpans.append(
                    Bold(
                        range: range,
                        leadingDelimiterRange: NSRange(
                            location: range.location, length: 2),
                        trailingDelimiterRange: NSRange(
                            location: NSMaxRange(range) - 2, length: 2)))
            }

            if let match = checkboxRegex.firstMatch(in: line.text, range: localRange) {
                let marker = absolute(match.range(at: 1), line: line)
                let status = absolute(match.range(at: 2), line: line)
                var textStart = NSMaxRange(marker)
                while textStart < NSMaxRange(line.range) {
                    let character = ns.character(at: textStart)
                    guard character == 0x20 || character == 0x09 else { break }
                    textStart += 1
                }
                result.checkboxes.append(
                    Checkbox(
                        markerRange: marker,
                        statusRange: status,
                        isChecked: ns.substring(with: status).lowercased() == "x",
                        lineRange: line.range,
                        textRange: NSRange(
                            location: textStart,
                            length: max(0, NSMaxRange(line.range) - textStart))))
            }
        }

        return result
    }

    /// Returns a whole-document semantic replacement when an unchecked
    /// editor checkbox is a valid recurring Cove task. Ordinary Markdown
    /// checkboxes return nil and keep the platform text view's one-character
    /// toggle behavior. Duplicate recurring tasks fail closed rather than
    /// advancing whichever identical line happened to be tapped.
    static func recurringTaskToggleResult(
        for checkbox: Checkbox,
        in text: String,
        sectioned: Bool,
        todayDateString: String = QuickTaskParser.ymdString(from: Date())
    ) -> Swift.Result<String, TaskParser.MutationError>? {
        guard !checkbox.isChecked else { return nil }
        let scan = TaskParser.scan(in: text, sectioned: sectioned)
        guard
            let task = scan.tasks.first(where: {
                $0.statusRange == checkbox.statusRange
            }),
            task.recurrence != nil
        else { return nil }
        let identity = TaskIdentity(
            filePath: "/CoveEditor.md",
            lineNumber: task.lineNumber,
            text: task.text,
            dueDateString: task.dueDateString,
            dueTimeString: task.dueTimeString,
            recurrenceTag: task.recurrence?.tagText,
            listName: task.listName,
            recurrenceAnchorDateString: task.recurrenceAnchorDateString,
            isSectionedDocument: sectioned)
        return TaskParser.settingTaskCompletedResult(
            identity,
            to: true,
            todayDateString: todayDateString,
            in: text)
    }

    private static func absolute(
        _ range: NSRange,
        line: MarkdownContextScanner.Line
    ) -> NSRange {
        NSRange(location: line.range.location + range.location, length: range.length)
    }
}
