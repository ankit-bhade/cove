import Foundation

/// Context-aware Markdown surgery for `##` list sections in `Tasks.md`.
///
/// Only an exact level-two heading opens a list. A level-one heading closes
/// the current list, while deeper headings remain ordinary content inside the
/// current list. Fences, HTML comments, and front matter never affect section
/// boundaries.
enum TaskListDocument {
    enum EditError: LocalizedError, Equatable, Sendable {
        case invalidName
        case invalidTaskLine
        case missingSection(String)
        case duplicateSection(String)
        case nameAlreadyExists(String)

        var errorDescription: String? {
            switch self {
            case .invalidName:
                return "List names must be a single non-empty line."
            case .invalidTaskLine:
                return "A task must be one line and cannot contain control characters."
            case .missingSection(let name):
                return "The “\(name)” list no longer exists."
            case .duplicateSection(let name):
                return
                    "More than one “\(name)” heading exists. Resolve the duplicate headings before editing this list."
            case .nameAlreadyExists(let name):
                return "A list named “\(name)” already exists."
            }
        }
    }

    struct Diagnostic: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case duplicateSection
        }

        let kind: Kind
        let lineNumber: Int
        let message: String
    }

    struct SectionRemovalRecord: Equatable, Sendable {
        let name: String
        let sourceText: String
        let previousSectionName: String?
        let nextSectionName: String?
        let approximateLineNumber: Int
    }

    private enum Heading: Equatable {
        case document
        case list(String)
        case deeper
    }

    private struct SectionHeading {
        let name: String
        let lineIndex: Int
        let line: MarkdownContextScanner.Line
    }

    private struct SectionBounds {
        let headingStart: Int
        let headingLineRange: NSRange
        let end: Int
        let insertionPoint: Int
    }

    private static let headingRegex = try! NSRegularExpression(
        pattern: #"^(#{1,6})[ \t]+(\S.*?)[ \t]*$"#)

    /// The list name an exact `##` heading opens. A `#` heading returns an
    /// empty string to signal that an open list closes. `###` through `######`
    /// return nil and therefore stay inside the current list.
    static func headingName(in line: String) -> String? {
        switch heading(in: line) {
        case .document:
            return ""
        case .list(let name):
            return name
        case .deeper, nil:
            return nil
        }
    }

    static func sectionNames(in fileText: String) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        for section in sectionHeadings(in: fileText) {
            if seen.insert(canonicalName(section.name)).inserted {
                names.append(section.name)
            }
        }
        return names
    }

    static func diagnostics(in fileText: String) -> [Diagnostic] {
        var firstLines: [String: Int] = [:]
        var diagnostics: [Diagnostic] = []
        for section in sectionHeadings(in: fileText) {
            let key = canonicalName(section.name)
            if firstLines[key] != nil {
                diagnostics.append(
                    Diagnostic(
                        kind: .duplicateSection,
                        lineNumber: section.line.number,
                        message:
                            "Duplicate list heading “\(section.name)” makes edits ambiguous."))
            } else {
                firstLines[key] = section.line.number
            }
        }
        return diagnostics
    }

    static func containsSection(named name: String, in fileText: String) -> Bool {
        sectionHeadings(in: fileText).contains { matches($0.name, name) }
    }

    static func addingSectionResult(
        named name: String,
        to fileText: String
    ) -> Result<String, EditError> {
        guard let name = validatedName(name) else { return .failure(.invalidName) }
        let matches = matchingHeadings(named: name, in: fileText)
        guard matches.isEmpty else {
            return .failure(
                matches.count > 1 ? .duplicateSection(name) : .nameAlreadyExists(name))
        }

        let document = MarkdownContextScanner.scan(fileText)
        let newline = document.preferredLineEnding
        var result = fileText
        if result == "\u{FEFF}" {
            return .success(result + "## \(name)" + newline)
        }
        if !result.isEmpty {
            if !endsInLineEnding(result) { result += newline }
            if !result.hasSuffix(newline + newline) { result += newline }
        }
        return .success(result + "## \(name)" + newline)
    }

    /// Compatibility wrapper. Call `addingSectionResult` when an error must
    /// be surfaced rather than represented as nil.
    static func addingSection(named name: String, to fileText: String) -> String? {
        try? addingSectionResult(named: name, to: fileText).get()
    }

    static func insertingLineResult(
        _ line: String,
        inSection name: String,
        in fileText: String
    ) -> Result<String, EditError> {
        guard isValidSingleLine(line) else { return .failure(.invalidTaskLine) }
        guard let name = validatedName(name) else { return .failure(.invalidName) }

        let matches = matchingHeadings(named: name, in: fileText)
        guard matches.count <= 1 else { return .failure(.duplicateSection(name)) }
        if matches.isEmpty {
            switch addingSectionResult(named: name, to: fileText) {
            case .failure(let error):
                return .failure(error)
            case .success(let withSection):
                let newline = MarkdownContextScanner.scan(withSection).preferredLineEnding
                return .success(withSection + line + newline)
            }
        }

        guard let bounds = sectionBounds(for: matches[0], in: fileText) else {
            return .failure(.missingSection(name))
        }
        let document = MarkdownContextScanner.scan(fileText)
        let newline = document.preferredLineEnding
        let ns = fileText as NSString
        var head = ns.substring(to: bounds.insertionPoint)
        if !head.isEmpty, !endsInLineEnding(head) { head += newline }
        return .success(
            head + line + newline + ns.substring(from: bounds.insertionPoint))
    }

    /// Compatibility wrapper that is deliberately fail-closed on ambiguity.
    static func insertingLine(
        _ line: String,
        inSection name: String,
        in fileText: String
    ) -> String {
        (try? insertingLineResult(line, inSection: name, in: fileText).get()) ?? fileText
    }

    static func insertingUnlistedLineResult(
        _ line: String,
        in fileText: String
    ) -> Result<String, EditError> {
        guard isValidSingleLine(line) else { return .failure(.invalidTaskLine) }
        let document = MarkdownContextScanner.scan(fileText)
        var inList = false
        var insertionPoint = document.contentStart
        var sawUnlistedContent = false
        var sawList = false

        for entry in document.lines {
            if !entry.isLiteral, let heading = heading(in: entry.text) {
                switch heading {
                case .document:
                    inList = false
                    insertionPoint = NSMaxRange(entry.enclosingRange)
                    sawUnlistedContent = true
                case .list:
                    inList = true
                    sawList = true
                case .deeper:
                    break
                }
                continue
            }
            guard !inList,
                !entry.text.trimmingCharacters(in: .whitespaces).isEmpty
            else { continue }
            insertionPoint = NSMaxRange(entry.enclosingRange)
            sawUnlistedContent = true
        }

        if !sawUnlistedContent, sawList {
            insertionPoint = document.contentStart
        }

        let ns = fileText as NSString
        let newline = document.preferredLineEnding
        var head = ns.substring(to: insertionPoint)
        if !head.isEmpty, head != "\u{FEFF}", !endsInLineEnding(head) {
            head += newline
        }
        return .success(head + line + newline + ns.substring(from: insertionPoint))
    }

    static func insertingUnlistedLine(_ line: String, in fileText: String) -> String {
        (try? insertingUnlistedLineResult(line, in: fileText).get()) ?? fileText
    }

    static func removingSectionResult(
        named name: String,
        from fileText: String
    ) -> Result<String, EditError> {
        removingSectionWithRecordResult(
            named: name,
            from: fileText
        ).map(\.text)
    }

    static func removingSectionWithRecordResult(
        named name: String,
        from fileText: String
    ) -> Result<
        (text: String, record: SectionRemovalRecord),
        EditError
    > {
        let matches = matchingHeadings(named: name, in: fileText)
        guard !matches.isEmpty else { return .failure(.missingSection(name)) }
        guard matches.count == 1 else { return .failure(.duplicateSection(name)) }
        let section = matches[0]
        guard let bounds = sectionBounds(for: section, in: fileText) else {
            return .failure(.missingSection(name))
        }
        let headings = sectionHeadings(in: fileText)
        guard
            let sectionIndex = headings.firstIndex(where: {
                $0.line.range == section.line.range
            })
        else { return .failure(.missingSection(name)) }
        let ns = fileText as NSString
        let sourceRange = NSRange(
            location: bounds.headingStart,
            length: bounds.end - bounds.headingStart)
        let record = SectionRemovalRecord(
            name: section.name,
            sourceText: ns.substring(with: sourceRange),
            previousSectionName:
                sectionIndex > 0
                ? headings[sectionIndex - 1].name : nil,
            nextSectionName:
                sectionIndex + 1 < headings.count
                ? headings[sectionIndex + 1].name : nil,
            approximateLineNumber: section.line.number)
        return .success(
            (
                ns.substring(to: bounds.headingStart)
                    + ns.substring(from: bounds.end),
                record
            ))
    }

    /// Fail-closed compatibility wrapper: duplicate headings are never
    /// destructively collapsed into whichever section happened to come first.
    static func removingSection(named name: String, from fileText: String) -> String {
        (try? removingSectionResult(named: name, from: fileText).get()) ?? fileText
    }

    /// Semantic inverse of section deletion. Existing content is never
    /// replaced: the exact removed section is inserted beside a surviving
    /// neighboring list, or near its old line when both neighbors are gone.
    static func restoringSectionResult(
        _ record: SectionRemovalRecord,
        in fileText: String
    ) -> Result<String, EditError> {
        let existing = matchingHeadings(named: record.name, in: fileText)
        guard existing.count <= 1 else {
            return .failure(.duplicateSection(record.name))
        }
        if let existing = existing.first,
            let bounds = sectionBounds(for: existing, in: fileText)
        {
            let ns = fileText as NSString
            let existingText = ns.substring(
                with: NSRange(
                    location: bounds.headingStart,
                    length: bounds.end - bounds.headingStart))
            return existingText == record.sourceText
                ? .success(fileText)
                : .failure(.nameAlreadyExists(record.name))
        }

        let insertionPoint: Int
        if let next = record.nextSectionName {
            let matches = matchingHeadings(named: next, in: fileText)
            if matches.count == 1 {
                insertionPoint = matches[0].line.range.location
            } else {
                insertionPoint = fallbackInsertionPoint(
                    forLine: record.approximateLineNumber,
                    in: fileText)
            }
        } else if let previous = record.previousSectionName {
            let matches = matchingHeadings(named: previous, in: fileText)
            if matches.count == 1,
                let bounds = sectionBounds(for: matches[0], in: fileText)
            {
                insertionPoint = bounds.end
            } else {
                insertionPoint = fallbackInsertionPoint(
                    forLine: record.approximateLineNumber,
                    in: fileText)
            }
        } else {
            insertionPoint = fallbackInsertionPoint(
                forLine: record.approximateLineNumber,
                in: fileText)
        }

        let ns = fileText as NSString
        let newline = MarkdownContextScanner.scan(fileText).preferredLineEnding
        var source = record.sourceText
        let prefix = ns.substring(to: insertionPoint)
        let suffix = ns.substring(from: insertionPoint)
        if !prefix.isEmpty, !endsInLineEnding(prefix),
            !source.hasPrefix("\n"), !source.hasPrefix("\r")
        {
            source = newline + source
        }
        if !suffix.isEmpty, !endsInLineEnding(source),
            !suffix.hasPrefix("\n"), !suffix.hasPrefix("\r")
        {
            source += newline
        }
        return .success(
            ns.replacingCharacters(
                in: NSRange(location: insertionPoint, length: 0),
                with: source))
    }

    static func renamingSectionResult(
        named name: String,
        to newName: String,
        in fileText: String
    ) -> Result<String, EditError> {
        guard let newName = validatedName(newName) else { return .failure(.invalidName) }
        let sourceMatches = matchingHeadings(named: name, in: fileText)
        guard !sourceMatches.isEmpty else { return .failure(.missingSection(name)) }
        guard sourceMatches.count == 1 else { return .failure(.duplicateSection(name)) }

        if !matches(name, newName) {
            let destinationMatches = matchingHeadings(named: newName, in: fileText)
            guard destinationMatches.isEmpty else {
                return .failure(
                    destinationMatches.count > 1
                        ? .duplicateSection(newName) : .nameAlreadyExists(newName))
            }
        }

        let heading = sourceMatches[0]
        return .success(
            (fileText as NSString)
                .replacingCharacters(in: heading.line.range, with: "## \(newName)"))
    }

    static func renamingSection(
        named name: String,
        to newName: String,
        in fileText: String
    ) -> String? {
        try? renamingSectionResult(named: name, to: newName, in: fileText).get()
    }

    // MARK: - Section lookup

    private static func sectionHeadings(in fileText: String) -> [SectionHeading] {
        let document = MarkdownContextScanner.scan(fileText)
        return document.lines.enumerated().compactMap { index, line in
            guard !line.isLiteral, case .list(let name)? = heading(in: line.text) else {
                return nil
            }
            return SectionHeading(name: name, lineIndex: index, line: line)
        }
    }

    private static func matchingHeadings(
        named name: String,
        in fileText: String
    ) -> [SectionHeading] {
        sectionHeadings(in: fileText).filter { matches($0.name, name) }
    }

    private static func sectionBounds(
        for section: SectionHeading,
        in fileText: String
    ) -> SectionBounds? {
        let document = MarkdownContextScanner.scan(fileText)
        guard section.lineIndex < document.lines.count else { return nil }
        let headingLine = document.lines[section.lineIndex]
        var end = NSMaxRange(headingLine.enclosingRange)
        var insertionPoint = end

        if section.lineIndex + 1 < document.lines.count {
            for line in document.lines[(section.lineIndex + 1)...] {
                if !line.isLiteral, let boundary = heading(in: line.text) {
                    switch boundary {
                    case .document, .list:
                        return SectionBounds(
                            headingStart: headingLine.range.location,
                            headingLineRange: headingLine.range,
                            end: end,
                            insertionPoint: insertionPoint)
                    case .deeper:
                        break
                    }
                }
                end = NSMaxRange(line.enclosingRange)
                if !line.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    insertionPoint = end
                }
            }
        }
        return SectionBounds(
            headingStart: headingLine.range.location,
            headingLineRange: headingLine.range,
            end: end,
            insertionPoint: insertionPoint)
    }

    private static func fallbackInsertionPoint(
        forLine lineNumber: Int,
        in fileText: String
    ) -> Int {
        let lines = MarkdownContextScanner.scan(fileText).lines
        guard lineNumber < lines.count else {
            return (fileText as NSString).length
        }
        return lines[max(0, lineNumber)].enclosingRange.location
    }

    // MARK: - Validation

    private static func heading(in line: String) -> Heading? {
        let ns = line as NSString
        guard
            let match = headingRegex.firstMatch(
                in: line, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        let level = match.range(at: 1).length
        switch level {
        case 1:
            return .document
        case 2:
            return .list(ns.substring(with: match.range(at: 2)))
        default:
            return .deeper
        }
    }

    private static func validatedName(_ raw: String) -> String? {
        guard raw.rangeOfCharacter(from: .newlines) == nil,
            raw.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isValidSingleLine(_ line: String) -> Bool {
        !line.isEmpty
            && line.rangeOfCharacter(from: .newlines) == nil
            && line.unicodeScalars.allSatisfy {
                $0 == "\t" || !CharacterSet.controlCharacters.contains($0)
            }
    }

    static func canonicalName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        canonicalName(lhs) == canonicalName(rhs)
    }

    private static func endsInLineEnding(_ text: String) -> Bool {
        text.hasSuffix("\r\n") || text.hasSuffix("\n") || text.hasSuffix("\r")
    }
}
