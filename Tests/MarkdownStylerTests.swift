import XCTest
@testable import Cove

final class MarkdownStylerTests: XCTestCase {
    func testIncrementalStyleKeepsFencedCodeContext() throws {
        let text = """
            ```md
            # Not a heading
            - [x] Not a task
            ```
            # Real heading
            """
        let storage = NSTextStorage(string: text)
        MarkdownStyler.applyLiveStyles(to: storage)

        let codeHeading = (text as NSString).range(of: "# Not a heading")
        let codeTaskText = (text as NSString).range(of: "Not a task")
        MarkdownStyler.applyLiveStyles(
            to: storage,
            dirtyRange: codeHeading,
            includeNeighbors: false)
        MarkdownStyler.applyLiveStyles(
            to: storage,
            dirtyRange: codeTaskText,
            includeNeighbors: false)

        let codeFont = try XCTUnwrap(
            storage.attribute(
                .font,
                at: codeHeading.location,
                effectiveRange: nil) as? MarkdownStyler.PlatformFont)
        XCTAssertEqual(codeFont, MarkdownStyler.bodyFont)
        XCTAssertNil(
            storage.attribute(
                .strikethroughStyle,
                at: codeTaskText.location,
                effectiveRange: nil))
    }
}
