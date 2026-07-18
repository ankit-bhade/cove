import XCTest
@testable import Cove

final class MarkdownParserTests: XCTestCase {
    // MARK: Headers

    func testParsesHeaderLevels() {
        let result = MarkdownParser.parse("# One\n### Three\n###### Six")
        XCTAssertEqual(result.headers.count, 3)
        XCTAssertEqual(result.headers[0].level, 1)
        XCTAssertEqual(result.headers[0].lineRange, NSRange(location: 0, length: 5))
        XCTAssertEqual(result.headers[0].markerRange, NSRange(location: 0, length: 1))
        XCTAssertEqual(result.headers[1].level, 3)
        XCTAssertEqual(result.headers[1].markerRange, NSRange(location: 6, length: 3))
        XCTAssertEqual(result.headers[2].level, 6)
    }

    func testHeaderLineRangeExcludesNewline() {
        let result = MarkdownParser.parse("## Two\nbody")
        XCTAssertEqual(result.headers[0].lineRange, NSRange(location: 0, length: 6))
    }

    func testIgnoresNonHeaders() {
        let result = MarkdownParser.parse("####### seven\n#nospace\ntext # inline\n#\n")
        XCTAssertTrue(result.headers.isEmpty)
    }

    // MARK: Bold

    func testParsesBoldSpan() {
        let result = MarkdownParser.parse("a **bold** b")
        XCTAssertEqual(result.boldSpans.count, 1)
        let bold = result.boldSpans[0]
        XCTAssertEqual(bold.range, NSRange(location: 2, length: 8))
        XCTAssertEqual(bold.leadingDelimiterRange, NSRange(location: 2, length: 2))
        XCTAssertEqual(bold.trailingDelimiterRange, NSRange(location: 8, length: 2))
    }

    func testParsesMultipleBoldSpans() {
        let result = MarkdownParser.parse("**a** and **b**")
        XCTAssertEqual(result.boldSpans.count, 2)
        XCTAssertEqual(result.boldSpans[1].range, NSRange(location: 10, length: 5))
    }

    func testIgnoresUnclosedAndEmptyBold() {
        XCTAssertTrue(MarkdownParser.parse("**oops").boldSpans.isEmpty)
        XCTAssertTrue(MarkdownParser.parse("****").boldSpans.isEmpty)
    }

    func testBoldDoesNotSpanLines() {
        XCTAssertTrue(MarkdownParser.parse("**a\nb**").boldSpans.isEmpty)
    }

    func testBoldRangesAreUTF16() {
        // The emoji is two UTF-16 units, so the span starts at 3, not 2.
        let result = MarkdownParser.parse("😀 **b**")
        XCTAssertEqual(result.boldSpans[0].range, NSRange(location: 3, length: 5))
    }

    // MARK: Checkboxes

    func testParsesUncheckedCheckbox() {
        let result = MarkdownParser.parse("- [ ] Task")
        XCTAssertEqual(result.checkboxes.count, 1)
        let checkbox = result.checkboxes[0]
        XCTAssertEqual(checkbox.markerRange, NSRange(location: 0, length: 5))
        XCTAssertEqual(checkbox.statusRange, NSRange(location: 3, length: 1))
        XCTAssertFalse(checkbox.isChecked)
        XCTAssertEqual(checkbox.textRange, NSRange(location: 6, length: 4))
        XCTAssertEqual(checkbox.toggledStatus, "x")
    }

    func testParsesCheckedCheckboxCaseInsensitively() {
        for status in ["x", "X"] {
            let result = MarkdownParser.parse("- [\(status)] Done")
            XCTAssertTrue(result.checkboxes[0].isChecked)
            XCTAssertEqual(result.checkboxes[0].toggledStatus, " ")
        }
    }

    func testParsesIndentedCheckbox() {
        let result = MarkdownParser.parse("  - [x] nested")
        XCTAssertEqual(result.checkboxes[0].markerRange, NSRange(location: 2, length: 5))
    }

    func testBareCheckboxHasEmptyTextRange() {
        let result = MarkdownParser.parse("- [ ]")
        XCTAssertEqual(result.checkboxes[0].textRange.length, 0)
    }

    func testRejectsMalformedCheckboxes() {
        for line in ["-[ ] a", "- [y] a", "- [ ]x", "- [] a", "x - [ ] a"] {
            XCTAssertTrue(MarkdownParser.parse(line).checkboxes.isEmpty, line)
        }
    }

    func testFindsCheckboxOnLaterLine() {
        let result = MarkdownParser.parse("# Title\n\n- [ ] first\n- [x] second")
        XCTAssertEqual(result.checkboxes.count, 2)
        XCTAssertEqual(result.checkboxes[1].markerRange, NSRange(location: 21, length: 5))
        XCTAssertTrue(result.checkboxes[1].isChecked)
    }

    // MARK: Hit testing

    func testCheckboxHitTestCoversMarkerOnly() {
        let result = MarkdownParser.parse("- [ ] Task")
        XCTAssertNotNil(result.checkbox(at: 0))
        XCTAssertNotNil(result.checkbox(at: 4))
        XCTAssertNil(result.checkbox(at: 5))
        XCTAssertNil(result.checkbox(at: 7))
    }

    func testCheckboxHitTestExcludesIndentation() {
        let result = MarkdownParser.parse("  - [ ] Task")
        XCTAssertNil(result.checkbox(at: 1))
        XCTAssertNotNil(result.checkbox(at: 2))
    }
}
