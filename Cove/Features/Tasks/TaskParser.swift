import Foundation

/// Shared line/context pass used by the task index, list surgery, and editor.
/// It lives in this explicitly shared source file so the widget target uses
/// exactly the same Markdown boundaries as the app.
enum MarkdownContextScanner {
    struct Line: Equatable, Sendable {
        let number: Int
        let text: String
        let range: NSRange
        let enclosingRange: NSRange
        let lineEnding: String
        let isLiteral: Bool
    }

    struct Document: Equatable, Sendable {
        let lines: [Line]
        let preferredLineEnding: String
        let hasByteOrderMark: Bool
        var contentStart: Int { hasByteOrderMark ? 1 : 0 }
    }

    private struct Fence {
        let character: unichar
        let length: Int
    }

    static func scan(_ text: String) -> Document {
        let ns = text as NSString
        let hasBOM = ns.length > 0 && ns.character(at: 0) == 0xFEFF
        var rawLines: [(String, NSRange, NSRange, String)] = []
        var cursor = 0
        while cursor < ns.length {
            var start = 0
            var end = 0
            var contentsEnd = 0
            ns.getLineStart(
                &start,
                end: &end,
                contentsEnd: &contentsEnd,
                for: NSRange(location: cursor, length: 0))
            guard end > cursor else { break }
            let contentStart = cursor + (cursor == 0 && hasBOM ? 1 : 0)
            let range = NSRange(
                location: contentStart,
                length: max(0, contentsEnd - contentStart))
            rawLines.append(
                (
                    ns.substring(with: range),
                    range,
                    NSRange(location: contentStart, length: end - contentStart),
                    ns.substring(
                        with: NSRange(location: contentsEnd, length: end - contentsEnd))
                ))
            cursor = end
        }

        var lines: [Line] = []
        lines.reserveCapacity(rawLines.count)
        // Front matter only exists when it is actually closed. An opening
        // `---` with no terminator is a thematic break, and treating it as an
        // unterminated block would silently hide every task in the note.
        let frontMatterEnd = closedFrontMatterEnd(in: rawLines.map(\.0))
        var inHTMLComment = false
        var fence: Fence?

        for (number, raw) in rawLines.enumerated() {
            let text = raw.0
            var literal = false
            if let frontMatterEnd, number <= frontMatterEnd {
                literal = true
            } else if let openFence = fence {
                literal = true
                if isClosingFence(text, matching: openFence) { fence = nil }
            } else if inHTMLComment {
                literal = true
                if text.contains("-->") { inHTMLComment = false }
            } else if let opening = openingFence(in: text) {
                literal = true
                fence = opening
            } else if text.contains("<!--") {
                literal = true
                if !text.contains("-->") { inHTMLComment = true }
            }
            lines.append(
                Line(
                    number: number,
                    text: text,
                    range: raw.1,
                    enclosingRange: raw.2,
                    lineEnding: raw.3,
                    isLiteral: literal))
        }

        return Document(
            lines: lines,
            preferredLineEnding: preferredLineEnding(in: ns),
            hasByteOrderMark: hasBOM)
    }

    /// The index of the closing delimiter of a real YAML front-matter block,
    /// or nil when the note does not open with one that is ever closed.
    private static func closedFrontMatterEnd(in lines: [String]) -> Int? {
        guard let first = lines.first,
            first.trimmingCharacters(in: .whitespaces) == "---"
        else { return nil }
        for index in 1..<lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." { return index }
        }
        return nil
    }

    private static func preferredLineEnding(in text: NSString) -> String {
        for index in 0..<text.length {
            if text.character(at: index) == 0x0D {
                return index + 1 < text.length && text.character(at: index + 1) == 0x0A
                    ? "\r\n" : "\r"
            }
            if text.character(at: index) == 0x0A { return "\n" }
        }
        return "\n"
    }

    private static func openingFence(in line: String) -> Fence? {
        let ns = line as NSString
        var index = 0
        while index < ns.length, index < 3, ns.character(at: index) == 0x20 {
            index += 1
        }
        guard index < ns.length else { return nil }
        let character = ns.character(at: index)
        guard character == 0x60 || character == 0x7E else { return nil }
        let length = runLength(of: character, from: index, in: ns)
        guard length >= 3 else { return nil }
        if character == 0x60 {
            let suffix = NSRange(
                location: index + length,
                length: ns.length - index - length)
            if ns.range(of: "`", options: [], range: suffix).location != NSNotFound {
                return nil
            }
        }
        return Fence(character: character, length: length)
    }

    private static func isClosingFence(_ line: String, matching fence: Fence) -> Bool {
        let ns = line as NSString
        var index = 0
        while index < ns.length, index < 3, ns.character(at: index) == 0x20 {
            index += 1
        }
        guard index < ns.length, ns.character(at: index) == fence.character else {
            return false
        }
        let length = runLength(of: fence.character, from: index, in: ns)
        guard length >= fence.length else { return false }
        return ns.substring(from: index + length)
            .trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func runLength(
        of character: unichar,
        from start: Int,
        in text: NSString
    ) -> Int {
        var index = start
        while index < text.length, text.character(at: index) == character {
            index += 1
        }
        return index - start
    }
}

/// Context-aware scanner and mutation helpers for Cove task lines.
///
/// Binary checkboxes may use `-`, `*`, or `+` bullets and may be indented,
/// which covers normal nested Markdown and Obsidian lists. Task-looking text
/// in front matter, fenced code, or HTML comments is never indexed or edited.
enum TaskParser {
    struct ParsedTask: Equatable, Sendable {
        let lineNumber: Int
        /// Whole source line including its existing terminator, but excluding
        /// an initial BOM. This makes delete/restore integrations lossless.
        let sourceLine: String
        let lineRange: NSRange
        let statusRange: NSRange
        let dueDateRange: NSRange?
        let text: String
        let dueDateString: String?
        let dueTimeString: String?
        let recurrence: RecurrenceRule?
        let recurrenceAnchorDateString: String?
        /// Whole leading-space + `@anchor(...)` suffix, for exact Undo.
        let recurrenceAnchorTagRange: NSRange?
        /// End of meaningful line content, before trailing spaces.
        let metadataInsertionLocation: Int
        let isCompleted: Bool
        let listName: String?
    }

    struct Diagnostic: Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case malformedTask
            case impossibleDate
            case unsupportedCheckboxStatus
            case unsupportedCheckboxForm
            case duplicateTask
        }

        let kind: Kind
        let lineNumber: Int
        let message: String
    }

    struct ScanResult: Equatable, Sendable {
        let tasks: [ParsedTask]
        let diagnostics: [Diagnostic]
    }

    enum MatchResult: Equatable, Sendable {
        case matched(ParsedTask)
        case missing
        case ambiguous([ParsedTask])
    }

    enum MutationError: LocalizedError, Equatable, Sendable {
        case taskMissing
        case ambiguousTask([Int])
        case invalidRecurrence

        var errorDescription: String? {
            switch self {
            case .taskMissing:
                return "The task changed or was removed in another editor."
            case .ambiguousTask(let lines):
                let shown = lines.map { String($0 + 1) }.joined(separator: ", ")
                return
                    "More than one matching task exists on lines \(shown). Resolve the duplicate tasks before editing."
            case .invalidRecurrence:
                return "The recurring task’s next date could not be calculated."
            }
        }
    }

    private struct SemanticKey: Hashable {
        let text: String
        let dueDateString: String?
        let dueTimeString: String?
        let recurrence: RecurrenceRule?
        let listName: String?
    }

    private static let taskLineRegex = try! NSRegularExpression(
        pattern:
            #"^[ \t]*[-+*][ \t]+\[([ xX])\][ \t]+(\S(?:.*\S)?)[ \t]+@due\(((\d{4})-(\d{2})-(\d{2}))(?:[ \t]+(\d{2}):(\d{2}))?\)(?:[ \t]+@repeat\(([a-z0-9 ]+)\)([ \t]+@anchor\(((\d{4})-(\d{2})-(\d{2}))\))?)?[ \t]*$"#
    )

    private static let undatedTaskLineRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*[-+*][ \t]+\[([ xX])\][ \t]+(\S(?:.*\S)?)[ \t]*$"#)

    private static let checkboxCandidateRegex = try! NSRegularExpression(
        pattern:
            #"^[ \t]*(?:(?:>[ \t]*)+)?(?:[-+*]|\d+[.)])[ \t]+\[([^\]\r\n])\]"#)

    private static let gregorian = TaskCalendar.gregorian(
        timeZone: TimeZone(secondsFromGMT: 0)!)

    static func tasks(in text: String, sectioned: Bool = false) -> [ParsedTask] {
        scan(in: text, sectioned: sectioned).tasks
    }

    static func scan(in text: String, sectioned: Bool = false) -> ScanResult {
        let document = MarkdownContextScanner.scan(text)
        var tasks: [ParsedTask] = []
        var diagnostics: [Diagnostic] = []
        var listName: String?

        for line in document.lines {
            guard !line.isLiteral else { continue }

            if sectioned, let heading = TaskListDocument.headingName(in: line.text) {
                listName = heading.isEmpty ? nil : heading
                continue
            }

            let ns = line.text as NSString
            let wholeLine = NSRange(location: 0, length: ns.length)
            if let match = taskLineRegex.firstMatch(in: line.text, range: wholeLine) {
                guard
                    let parsed = datedTask(
                        match,
                        line: line,
                        listName: sectioned ? listName : nil,
                        diagnostics: &diagnostics)
                else { continue }
                tasks.append(parsed)
                continue
            }

            if sectioned, let listName,
                let parsed = undatedTask(in: line, listName: listName)
            {
                tasks.append(parsed)
                continue
            }

            diagnoseRejectedCandidate(
                line,
                insideList: sectioned && listName != nil,
                diagnostics: &diagnostics)
        }

        var firstByKey: [SemanticKey: ParsedTask] = [:]
        for task in tasks {
            let key = semanticKey(for: task)
            if firstByKey[key] != nil {
                guard diagnostics.count < maximumDiagnosticsPerNote else { break }
                diagnostics.append(
                    Diagnostic(
                        kind: .duplicateTask,
                        lineNumber: task.lineNumber,
                        message:
                            "This task has the same title and schedule as another task, so destructive edits are disabled until one is made distinct."
                    ))
            } else {
                firstByKey[key] = task
            }
        }
        return ScanResult(
            tasks: tasks,
            diagnostics: Array(diagnostics.prefix(maximumDiagnosticsPerNote)))
    }

    /// Diagnostics live in the index for as long as the note does, and each
    /// one carries a sentence. A note of plain Obsidian checklists produces
    /// one per line, so an unbounded scan would keep a full explanatory
    /// string per checkbox in memory for the whole session. Settings shows
    /// far fewer than this; the cap exists so the *index* stays small, and
    /// the point of a diagnostic — this note has something wrong in it, here
    /// is where to look — survives truncation intact.
    static let maximumDiagnosticsPerNote = 20

    private static func datedTask(
        _ match: NSTextCheckingResult,
        line: MarkdownContextScanner.Line,
        listName: String?,
        diagnostics: inout [Diagnostic]
    ) -> ParsedTask? {
        let ns = line.text as NSString
        let year = Int(ns.substring(with: match.range(at: 4)))!
        let month = Int(ns.substring(with: match.range(at: 5)))!
        let day = Int(ns.substring(with: match.range(at: 6)))!
        let dueDate = String(format: "%04d-%02d-%02d", year, month, day)
        guard
            DateComponents(year: year, month: month, day: day)
                .isValidDate(in: gregorian)
        else {
            diagnostics.append(
                Diagnostic(
                    kind: .impossibleDate,
                    lineNumber: line.number,
                    message: "The due date \(dueDate) does not exist."))
            return nil
        }

        var timeString: String?
        if match.range(at: 7).location != NSNotFound {
            let hour = Int(ns.substring(with: match.range(at: 7)))!
            let minute = Int(ns.substring(with: match.range(at: 8)))!
            guard (0...23).contains(hour), (0...59).contains(minute) else {
                diagnostics.append(
                    Diagnostic(
                        kind: .malformedTask,
                        lineNumber: line.number,
                        message: "The due time must be a valid 24-hour HH:MM time."))
                return nil
            }
            timeString = String(format: "%02d:%02d", hour, minute)
        }

        var recurrence: RecurrenceRule?
        if match.range(at: 9).location != NSNotFound {
            let tag = ns.substring(with: match.range(at: 9))
            guard let rule = RecurrenceRule(tagText: tag) else {
                diagnostics.append(
                    Diagnostic(
                        kind: .malformedTask,
                        lineNumber: line.number,
                        message: "The @repeat tag is not a supported recurrence rule."))
                return nil
            }
            recurrence = rule
        }

        var recurrenceAnchor: String?
        var recurrenceAnchorTagRange: NSRange?
        if match.range(at: 10).location != NSNotFound {
            let year = Int(ns.substring(with: match.range(at: 12)))!
            let month = Int(ns.substring(with: match.range(at: 13)))!
            let day = Int(ns.substring(with: match.range(at: 14)))!
            let anchor = String(format: "%04d-%02d-%02d", year, month, day)
            guard
                DateComponents(year: year, month: month, day: day)
                    .isValidDate(in: gregorian)
            else {
                diagnostics.append(
                    Diagnostic(
                        kind: .impossibleDate,
                        lineNumber: line.number,
                        message: "The recurrence anchor \(anchor) does not exist."))
                return nil
            }
            recurrenceAnchor = anchor
            recurrenceAnchorTagRange = absolute(match.range(at: 10), in: line)
        }

        let statusInLine = match.range(at: 1)
        let dateInLine = match.range(at: 3)
        return ParsedTask(
            lineNumber: line.number,
            sourceLine: line.text + line.lineEnding,
            lineRange: line.enclosingRange,
            statusRange: absolute(statusInLine, in: line),
            dueDateRange: absolute(dateInLine, in: line),
            text: ns.substring(with: match.range(at: 2)),
            dueDateString: dueDate,
            dueTimeString: timeString,
            recurrence: recurrence,
            recurrenceAnchorDateString: recurrenceAnchor,
            recurrenceAnchorTagRange: recurrenceAnchorTagRange,
            metadataInsertionLocation: metadataInsertionLocation(in: line),
            isCompleted: ns.substring(with: statusInLine).lowercased() == "x",
            listName: listName)
    }

    private static func undatedTask(
        in line: MarkdownContextScanner.Line,
        listName: String
    ) -> ParsedTask? {
        guard !line.text.localizedCaseInsensitiveContains("@due("),
            !line.text.localizedCaseInsensitiveContains("@repeat(")
        else { return nil }
        let ns = line.text as NSString
        guard
            let match = undatedTaskLineRegex.firstMatch(
                in: line.text, range: NSRange(location: 0, length: ns.length))
        else { return nil }

        let status = match.range(at: 1)
        return ParsedTask(
            lineNumber: line.number,
            sourceLine: line.text + line.lineEnding,
            lineRange: line.enclosingRange,
            statusRange: absolute(status, in: line),
            dueDateRange: nil,
            text: ns.substring(with: match.range(at: 2)),
            dueDateString: nil,
            dueTimeString: nil,
            recurrence: nil,
            recurrenceAnchorDateString: nil,
            recurrenceAnchorTagRange: nil,
            metadataInsertionLocation: metadataInsertionLocation(in: line),
            isCompleted: ns.substring(with: status).lowercased() == "x",
            listName: listName)
    }

    private static func diagnoseRejectedCandidate(
        _ line: MarkdownContextScanner.Line,
        insideList: Bool,
        diagnostics: inout [Diagnostic]
    ) {
        // This runs for every non-task line in every note, so past the cap it
        // must not even reach the regex — a note of plain checklists would
        // otherwise pay for a match and a message string per line, all to
        // build diagnostics that are discarded.
        guard diagnostics.count < maximumDiagnosticsPerNote else { return }
        let ns = line.text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        guard let candidate = checkboxCandidateRegex.firstMatch(in: line.text, range: whole) else {
            return
        }
        let status = ns.substring(with: candidate.range(at: 1))
        if ![" ", "x", "X"].contains(status) {
            diagnostics.append(
                Diagnostic(
                    kind: .unsupportedCheckboxStatus,
                    lineNumber: line.number,
                    message:
                        "Checkbox status “\(status)” is preserved but is not a Cove task state. Use [ ] or [x]."))
            return
        }
        if line.text.localizedCaseInsensitiveContains("@due(")
            || line.text.localizedCaseInsensitiveContains("@repeat(")
            || line.text.localizedCaseInsensitiveContains("@anchor(")
        {
            diagnostics.append(
                Diagnostic(
                    kind: .malformedTask,
                    lineNumber: line.number,
                    message:
                        "This task-looking line has malformed @due or @repeat syntax and was not indexed."))
        } else if insideList {
            diagnostics.append(
                Diagnostic(
                    kind: .unsupportedCheckboxForm,
                    lineNumber: line.number,
                    message:
                        "Ordered and blockquote checkboxes are preserved but are not editable Cove task forms. Use -, *, or + bullets."
                ))
        } else {
            diagnostics.append(
                Diagnostic(
                    kind: .unsupportedCheckboxForm,
                    lineNumber: line.number,
                    message:
                        "This checkbox form is preserved but is not indexed as a Cove task. Use an indented -, *, or + bullet."
                ))
        }
    }

    // MARK: - Identity and mutation

    static func matchResult(
        _ identity: TaskIdentity,
        in fileText: String
    ) -> MatchResult {
        let candidates = tasks(
            in: fileText,
            sectioned: identity.requiresSectionedParsing
        ).filter {
            $0.text == identity.text
                && $0.dueDateString == identity.dueDateString
                && $0.dueTimeString == identity.dueTimeString
                && $0.recurrence == identity.recurrence
                && sameList($0.listName, identity.listName)
                && (identity.recurrenceAnchorDateString == nil
                    || $0.recurrenceAnchorDateString
                        == identity.recurrenceAnchorDateString)
        }
        switch candidates.count {
        case 0:
            return .missing
        case 1:
            return .matched(candidates[0])
        default:
            return .ambiguous(candidates)
        }
    }

    /// Returns a match only when the semantic identity is unique. A remembered
    /// line number is a useful display hint, not authority to mutate one of
    /// several indistinguishable tasks after external edits. Settings lists
    /// every duplicate diagnostic with a link to the note and line, which is
    /// the way out of an ambiguous pair.
    static func matchingTask(
        _ identity: TaskIdentity,
        in fileText: String
    ) -> ParsedTask? {
        guard case .matched(let task) = matchResult(identity, in: fileText) else {
            return nil
        }
        return task
    }

    static func settingTaskCompletedResult(
        _ identity: TaskIdentity,
        to desiredCompletion: Bool,
        todayDateString: String,
        in fileText: String,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Result<String, MutationError> {
        let match: ParsedTask
        switch matchResult(identity, in: fileText) {
        case .missing:
            return .failure(.taskMissing)
        case .ambiguous(let tasks):
            return .failure(.ambiguousTask(tasks.map(\.lineNumber)))
        case .matched(let task):
            match = task
        }

        if match.isCompleted == desiredCompletion { return .success(fileText) }
        if desiredCompletion,
            let rule = match.recurrence,
            let currentDate = match.dueDateString,
            let dateRange = match.dueDateRange
        {
            let anchor = match.recurrenceAnchorDateString ?? currentDate
            guard
                let next = rule.nextDueDateString(
                    afterOccurrence: currentDate,
                    catchingUpPast: todayDateString,
                    anchoredTo: anchor,
                    timeZone: timeZone)
            else { return .failure(.invalidRecurrence) }
            let result = NSMutableString(string: fileText)
            result.replaceCharacters(in: dateRange, with: next)
            if match.recurrenceAnchorDateString == nil {
                result.insert(
                    " @anchor(\(currentDate))",
                    at: match.metadataInsertionLocation)
            }
            return .success(result as String)
        }

        return .success(
            (fileText as NSString).replacingCharacters(
                in: match.statusRange,
                with: desiredCompletion ? "x" : " "))
    }

    static func settingTaskCompleted(
        _ identity: TaskIdentity,
        to desiredCompletion: Bool,
        todayDateString: String,
        in fileText: String
    ) -> String? {
        try? settingTaskCompletedResult(
            identity,
            to: desiredCompletion,
            todayDateString: todayDateString,
            in: fileText
        ).get()
    }

    /// Restores only the checkbox state and deliberately does not apply
    /// recurrence semantics. This is for Undo: completing a recurring task
    /// advances its date, while undoing a previously hand-checked recurring
    /// line must be able to put its exact `[x]` state back.
    static func restoringCheckboxStateResult(
        _ identity: TaskIdentity,
        to isCompleted: Bool,
        in fileText: String
    ) -> Result<String, MutationError> {
        let match: ParsedTask
        switch matchResult(identity, in: fileText) {
        case .missing:
            return .failure(.taskMissing)
        case .ambiguous(let tasks):
            return .failure(.ambiguousTask(tasks.map(\.lineNumber)))
        case .matched(let task):
            match = task
        }
        guard match.isCompleted != isCompleted else {
            return .success(fileText)
        }
        return .success(
            (fileText as NSString).replacingCharacters(
                in: match.statusRange,
                with: isCompleted ? "x" : " "))
    }

    /// Reverses the date advance performed when a recurring occurrence was
    /// completed. Storage/UI integrations should use this for Undo; merely
    /// setting the old occurrence to incomplete cannot find the advanced line.
    static func revertingRecurringCompletionResult(
        _ originalIdentity: TaskIdentity,
        completedOn todayDateString: String,
        in fileText: String,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Result<String, MutationError> {
        guard let originalDate = originalIdentity.dueDateString,
            let recurrence = originalIdentity.recurrence,
            let advancedDate = recurrence.nextDueDateString(
                afterOccurrence: originalDate,
                catchingUpPast: todayDateString,
                anchoredTo: originalIdentity.recurrenceAnchorDateString ?? originalDate,
                timeZone: timeZone)
        else { return .failure(.invalidRecurrence) }

        let advancedIdentity = TaskIdentity(
            filePath: originalIdentity.filePath,
            lineNumber: originalIdentity.lineNumber,
            text: originalIdentity.text,
            dueDateString: advancedDate,
            dueTimeString: originalIdentity.dueTimeString,
            recurrenceTag: originalIdentity.recurrenceTag,
            listName: originalIdentity.listName,
            recurrenceAnchorDateString:
                originalIdentity.recurrenceAnchorDateString ?? originalDate,
            isSectionedDocument: originalIdentity.isSectionedDocument)
        let match: ParsedTask
        switch matchResult(advancedIdentity, in: fileText) {
        case .missing:
            return .failure(.taskMissing)
        case .ambiguous(let tasks):
            return .failure(.ambiguousTask(tasks.map(\.lineNumber)))
        case .matched(let task):
            match = task
        }
        guard let range = match.dueDateRange else { return .failure(.invalidRecurrence) }
        let result = NSMutableString(string: fileText)
        result.replaceCharacters(in: range, with: originalDate)
        if originalIdentity.recurrenceAnchorDateString == nil,
            let anchorRange = match.recurrenceAnchorTagRange
        {
            result.replaceCharacters(in: anchorRange, with: "")
        }
        return .success(result as String)
    }

    /// One removal: the text left behind and the exact line that left it.
    struct TaskRemoval: Equatable, Sendable {
        let text: String
        /// The removed line as the file actually held it, terminator included.
        let removedLine: String
    }

    /// Removes one task's line and reports what was removed.
    ///
    /// Completion, the bullet character, and interior spacing are all outside
    /// the semantic key, so the line a delete finds is not necessarily the one
    /// the index last saw. Undo restores bytes, so the bytes it restores have
    /// to come from the same coordinated read the removal was computed
    /// against rather than from the index.
    static func removingTaskWithLineResult(
        _ identity: TaskIdentity,
        in fileText: String
    ) -> Result<TaskRemoval, MutationError> {
        switch matchResult(identity, in: fileText) {
        case .missing:
            return .failure(.taskMissing)
        case .ambiguous(let tasks):
            return .failure(.ambiguousTask(tasks.map(\.lineNumber)))
        case .matched(let task):
            return .success(
                TaskRemoval(
                    text: (fileText as NSString).replacingCharacters(
                        in: task.lineRange, with: ""),
                    removedLine: task.sourceLine))
        }
    }

    /// One in-place edit: the text left behind, and enough to reverse it.
    struct TaskReplacement: Equatable, Sendable {
        let text: String
        /// The body the matched line carried before the edit — the title and
        /// its tags, without the marker. What Undo writes back.
        let previousBody: String
        /// The whole edited line, terminator excluded. Its identity is read
        /// back out of the parser rather than assembled, exactly as a
        /// capture's is.
        let newLine: String
    }

    /// Rewrites one task's title and schedule in place.
    ///
    /// Only the part of the line *after* the marker is replaced. The
    /// indentation, the bullet character, the checkbox state, and the line's
    /// own terminator all stay as the file had them: an edit changed the task,
    /// not how the file writes it down, and rewriting the whole line
    /// canonically would silently flatten a nested Obsidian checkbox or tick a
    /// box another device had just ticked.
    ///
    /// `keepingRecurrenceAnchor` carries the one tag a draft cannot express.
    /// The anchor records the occurrence a recurring task was last advanced
    /// from, so it survives an edit that left the schedule alone and goes with
    /// one that did not — a new due date *is* a new anchor.
    static func replacingTaskResult(
        _ identity: TaskIdentity,
        withBody body: String,
        keepingRecurrenceAnchor keepsAnchor: Bool,
        in fileText: String
    ) -> Result<TaskReplacement, MutationError> {
        let match: ParsedTask
        switch matchResult(identity, in: fileText) {
        case .missing:
            return .failure(.taskMissing)
        case .ambiguous(let tasks):
            return .failure(.ambiguousTask(tasks.map(\.lineNumber)))
        case .matched(let task):
            match = task
        }

        let ns = fileText as NSString
        guard let bodyRange = bodyRange(of: match, in: ns) else {
            return .failure(.taskMissing)
        }
        var newBody = body
        if keepsAnchor, let anchor = match.recurrenceAnchorDateString,
            match.recurrence != nil
        {
            newBody += " @anchor(\(anchor))"
        }
        let text = ns.replacingCharacters(in: bodyRange, with: newBody)
        let marker = ns.substring(
            with: NSRange(
                location: match.lineRange.location,
                length: bodyRange.location - match.lineRange.location))
        return .success(
            TaskReplacement(
                text: text,
                previousBody: ns.substring(with: bodyRange),
                newLine: marker + newBody))
    }

    /// The span between a line's `- [ ] ` marker and its trailing whitespace —
    /// the title and tags, and nothing that says how the line is written.
    private static func bodyRange(
        of task: ParsedTask,
        in ns: NSString
    ) -> NSRange? {
        var location = task.statusRange.location + task.statusRange.length
        guard location < ns.length,
            ns.character(at: location) == 0x5D  // ]
        else { return nil }
        location += 1
        while location < ns.length {
            let character = ns.character(at: location)
            guard character == 0x20 || character == 0x09 else { break }
            location += 1
        }
        guard location <= task.metadataInsertionLocation else { return nil }
        return NSRange(
            location: location,
            length: task.metadataInsertionLocation - location)
    }

    static func removingTaskResult(
        _ identity: TaskIdentity,
        in fileText: String
    ) -> Result<String, MutationError> {
        removingTaskWithLineResult(identity, in: fileText).map(\.text)
    }

    static func removingTask(_ identity: TaskIdentity, in fileText: String) -> String? {
        try? removingTaskResult(identity, in: fileText).get()
    }

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

    private static func semanticKey(for task: ParsedTask) -> SemanticKey {
        SemanticKey(
            text: task.text,
            dueDateString: task.dueDateString,
            dueTimeString: task.dueTimeString,
            recurrence: task.recurrence,
            listName: task.listName.map(TaskListDocument.canonicalName))
    }

    private static func sameList(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (.some(let lhs), .some(let rhs)):
            return TaskListDocument.canonicalName(lhs)
                == TaskListDocument.canonicalName(rhs)
        default:
            return false
        }
    }

    private static func belongsToList(_ wanted: String?, _ actual: String?) -> Bool {
        guard let wanted else { return actual == nil }
        guard let actual else { return false }
        return TaskListDocument.canonicalName(wanted)
            == TaskListDocument.canonicalName(actual)
    }

    private static func absolute(
        _ range: NSRange,
        in line: MarkdownContextScanner.Line
    ) -> NSRange {
        NSRange(location: line.range.location + range.location, length: range.length)
    }

    private static func metadataInsertionLocation(
        in line: MarkdownContextScanner.Line
    ) -> Int {
        let ns = line.text as NSString
        var end = ns.length
        while end > 0 {
            let character = ns.character(at: end - 1)
            guard character == 0x20 || character == 0x09 else { break }
            end -= 1
        }
        return line.range.location + end
    }
}
