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
        pattern: #"^(#{1,6})[ \t].*$"#, options: [.anchorsMatchLines])
    // Content excludes `*` and newlines, so spans never cross lines and
    // stray asterisks fall back to plain text.
    private static let boldRegex = try! NSRegularExpression(
        pattern: #"\*\*([^*\n]+?)\*\*"#)
    private static let checkboxRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*(- \[([ xX])\])(?=[ \t]|$)"#, options: [.anchorsMatchLines])

    static func parse(_ text: String) -> Result {
        let ns = text as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var result = Result()

        headerRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let marker = match.range(at: 1)
            result.headers.append(
                Header(
                    level: marker.length,
                    lineRange: match.range,
                    markerRange: marker))
        }

        boldRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let range = match.range
            result.boldSpans.append(
                Bold(
                    range: range,
                    leadingDelimiterRange: NSRange(location: range.location, length: 2),
                    trailingDelimiterRange: NSRange(location: NSMaxRange(range) - 2, length: 2)))
        }

        checkboxRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let marker = match.range(at: 1)
            let status = match.range(at: 2)
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: marker)
            var textStart = NSMaxRange(marker)
            if textStart < contentsEnd {
                textStart += 1  // skip the space/tab after "]"
            }
            result.checkboxes.append(
                Checkbox(
                    markerRange: marker,
                    statusRange: status,
                    isChecked: ns.substring(with: status).lowercased() == "x",
                    textRange: NSRange(location: textStart, length: max(0, contentsEnd - textStart))))
        }

        return result
    }
}
