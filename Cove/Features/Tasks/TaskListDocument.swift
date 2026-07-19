import Foundation

/// Pure Markdown surgery for the list sections of the capture note.
///
/// A list is a `##` heading in `Tasks.md`; its items are the task lines
/// beneath it, up to the next heading of any level. Every operation here
/// takes and returns the whole file text, preserving all other Markdown
/// verbatim, so hand-edited notes survive round-trips through the Lists
/// screen.
///
/// Names are compared case- and whitespace-insensitively (a list typed as
/// "groceries" is the one shown as "Groceries"), but the heading's own
/// spelling is what the screen displays.
enum TaskListDocument {
    private static let headingRegex = try! NSRegularExpression(
        pattern: #"^(#{1,6})[ \t]+(\S.*?)[ \t]*$"#)

    /// The list name a heading line opens, or nil when the line is not a
    /// heading. A `#` heading closes the current list and opens none, so it
    /// returns an empty-named result the parser reads as "no list".
    static func headingName(in line: String) -> String? {
        let ns = line as NSString
        guard let match = headingRegex.firstMatch(
            in: line, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        // `#` is a document title, not a list: it ends the current section.
        guard ns.substring(with: match.range(at: 1)).count >= 2 else { return "" }
        return ns.substring(with: match.range(at: 2))
    }

    /// Every `##` list heading in the note, in file order — including lists
    /// with no items yet, which is why the index can't derive them from the
    /// tasks alone.
    static func sectionNames(in fileText: String) -> [String] {
        var names: [String] = []
        for line in lines(of: fileText) {
            if let name = headingName(in: line.text), !name.isEmpty,
               !names.contains(where: { matches($0, name) }) {
                names.append(name)
            }
        }
        return names
    }

    static func containsSection(named name: String, in fileText: String) -> Bool {
        sectionNames(in: fileText).contains { matches($0, name) }
    }

    /// Appends an empty `## name` heading, or returns nil when a list by
    /// that name already exists.
    static func addingSection(named name: String, to fileText: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !containsSection(named: trimmed, in: fileText) else { return nil }
        var text = fileText
        if !text.isEmpty {
            if !text.hasSuffix("\n") { text += "\n" }
            if !text.hasSuffix("\n\n") { text += "\n" }
        }
        return text + "## \(trimmed)\n"
    }

    /// Inserts a task line at the end of the named list's items, creating
    /// the list at the end of the note when it doesn't exist yet.
    static func insertingLine(_ line: String,
                              inSection name: String,
                              in fileText: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bounds = sectionBounds(named: trimmed, in: fileText) else {
            let withSection = addingSection(named: trimmed, to: fileText) ?? fileText
            return withSection + line + "\n"
        }
        let ns = fileText as NSString
        var text = ns.substring(to: bounds.insertionPoint)
        if !text.hasSuffix("\n") { text += "\n" }
        return text + line + "\n" + ns.substring(from: bounds.insertionPoint)
    }

    /// Removes a list's heading and every line under it. Returns the text
    /// unchanged when no such list exists.
    static func removingSection(named name: String, from fileText: String) -> String {
        guard let bounds = sectionBounds(named: name, in: fileText) else { return fileText }
        let ns = fileText as NSString
        return ns.substring(to: bounds.headingStart) + ns.substring(from: bounds.end)
    }

    /// Rewrites a list's heading, keeping its items. Returns nil when the
    /// list is missing or the new name is already taken by another list.
    static func renamingSection(named name: String,
                                to newName: String,
                                in fileText: String) -> String? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let bounds = sectionBounds(named: name, in: fileText) else {
            return nil
        }
        if !matches(name, trimmed), containsSection(named: trimmed, in: fileText) { return nil }
        return (fileText as NSString)
            .replacingCharacters(in: bounds.headingLineRange, with: "## \(trimmed)")
    }

    // MARK: - Section bounds

    private struct SectionBounds {
        /// UTF-16 offset where the heading line begins.
        let headingStart: Int
        /// UTF-16 range of the heading's text, excluding its line ending.
        let headingLineRange: NSRange
        /// UTF-16 offset just past the section's last line, where the next
        /// heading (or the end of the note) begins.
        let end: Int
        /// Where a new item goes: past the last item, before any trailing
        /// blank lines that separate this section from the next.
        let insertionPoint: Int
    }

    private static func sectionBounds(named name: String, in fileText: String) -> SectionBounds? {
        let all = lines(of: fileText)
        guard let headingIndex = all.firstIndex(where: {
            guard let heading = headingName(in: $0.text) else { return false }
            return !heading.isEmpty && matches(heading, name)
        }) else { return nil }

        let heading = all[headingIndex]
        var end = heading.enclosingRange.location + heading.enclosingRange.length
        var insertionPoint = end
        for line in all[(headingIndex + 1)...] {
            if headingName(in: line.text) != nil { break }
            end = line.enclosingRange.location + line.enclosingRange.length
            // Blank lines between the last item and the next heading belong
            // to the section on disk but shouldn't push new items past them.
            if !line.text.trimmingCharacters(in: .whitespaces).isEmpty {
                insertionPoint = end
            }
        }
        return SectionBounds(headingStart: heading.enclosingRange.location,
                             headingLineRange: heading.range,
                             end: end,
                             insertionPoint: insertionPoint)
    }

    // MARK: - Line helpers

    private struct Line {
        let text: String
        /// The line without its terminator.
        let range: NSRange
        /// The line including its terminator.
        let enclosingRange: NSRange
    }

    private static func lines(of text: String) -> [Line] {
        let ns = text as NSString
        var result: [Line] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines, .substringNotRequired]) {
            _, range, enclosingRange, _ in
            result.append(Line(text: ns.substring(with: range),
                               range: range,
                               enclosingRange: enclosingRange))
        }
        return result
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespaces)) == .orderedSame
    }
}
