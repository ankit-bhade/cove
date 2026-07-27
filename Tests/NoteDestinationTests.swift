import XCTest

@testable import Cove

/// Opening a note *at a line* is only as good as the line arithmetic behind
/// it. A diagnostic that says "line 42" and a caret that lands on line 41 is
/// worse than not moving the caret at all, so the counting is pinned here
/// against the shapes real notes take: blank lines, CRLF, a missing final
/// newline, and a line number past the end.
final class NoteDestinationTests: XCTestCase {

    // MARK: - Line ranges

    func testRangeOfEachLine() throws {
        let text = "alpha\nbeta\ngamma"
        let ns = text as NSString

        XCTAssertEqual(ns.substring(with: try line(0, in: text)), "alpha")
        XCTAssertEqual(ns.substring(with: try line(1, in: text)), "beta")
        XCTAssertEqual(ns.substring(with: try line(2, in: text)), "gamma")
    }

    /// Blank lines are lines. They are also where an off-by-one shows up
    /// first, since a scanner that skipped them would drift by one per blank.
    func testBlankLinesAreCounted() throws {
        let text = "alpha\n\n\n- [ ] Buy milk @due(2026-07-20)\n"
        let range = try line(3, in: text)

        XCTAssertEqual(
            (text as NSString).substring(with: range),
            "- [ ] Buy milk @due(2026-07-20)")
    }

    /// The parsers count lines with their own scanner, so the editor has to
    /// agree with it or every diagnostic link lands in the wrong place.
    func testAgreesWithTheParsersOwnLineNumbers() throws {
        let text = """
            # Notes

            ```
            - [ ] fenced, not a task
            ```

            - [ ] Buy milk @due(2026-07-20)
            - [ ] Order cake @due(2026-07-21)
            """
        let tasks = TaskParser.tasks(in: text)
        XCTAssertEqual(tasks.count, 2)

        for task in tasks {
            let range = try XCTUnwrap(
                MarkdownParser.range(ofLine: task.lineNumber, in: text))
            XCTAssertEqual(
                (text as NSString).substring(with: range),
                task.sourceLine.trimmingCharacters(in: .newlines))
        }
    }

    func testRangeExcludesTheLineTerminator() throws {
        let range = try line(0, in: "alpha\nbeta\n")
        XCTAssertEqual(range, NSRange(location: 0, length: 5))
    }

    func testHandlesWindowsLineEndings() throws {
        let text = "alpha\r\nbeta\r\ngamma"
        XCTAssertEqual(
            (text as NSString).substring(with: try line(1, in: text)), "beta")
    }

    func testFinalLineWithoutATrailingNewline() throws {
        let text = "alpha\nbeta"
        XCTAssertEqual(
            (text as NSString).substring(with: try line(1, in: text)), "beta")
    }

    /// A stale index can name a line the note no longer has. Nothing should
    /// happen — the note still opens, just at the top.
    func testLineNumberPastTheEndIsNil() {
        XCTAssertNil(MarkdownParser.range(ofLine: 9, in: "alpha\nbeta\n"))
    }

    func testNegativeLineIsNil() {
        XCTAssertNil(MarkdownParser.range(ofLine: -1, in: "alpha\n"))
    }

    func testEmptyTextHasNoLines() {
        XCTAssertNil(MarkdownParser.range(ofLine: 0, in: ""))
    }

    // MARK: - The destination value

    /// The line is part of the identity. Two pushes of one note at different
    /// lines have to be different navigation values, or the second is treated
    /// as the destination already on screen and does nothing.
    func testSameNoteAtDifferentLinesAreDistinctValues() {
        let url = URL(fileURLWithPath: "/vault/Tasks.md")
        XCTAssertNotEqual(
            NoteDestination(url, line: 3), NoteDestination(url, line: 4))
        XCTAssertNotEqual(NoteDestination(url), NoteDestination(url, line: 0))
        XCTAssertEqual(
            NoteDestination(url, line: 3), NoteDestination(url, line: 3))
    }

    func testDefaultsToNoLine() {
        XCTAssertNil(NoteDestination(URL(fileURLWithPath: "/vault/A.md")).line)
    }

    private func line(_ number: Int, in text: String) throws -> NSRange {
        try XCTUnwrap(MarkdownParser.range(ofLine: number, in: text))
    }
}
