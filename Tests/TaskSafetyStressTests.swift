import XCTest
@testable import Cove

final class TaskSafetyStressTests: XCTestCase {
    /// A generous ceiling catches accidental quadratic scans without making
    /// normal CI variance a failure. Local runs are normally far below it.
    func testTwentyThousandLineTasksDocumentStaysLinearEnough() throws {
        var lines: [String] = []
        lines.reserveCapacity(20_200)
        for index in 0..<20_000 {
            if index.isMultiple(of: 1_000) {
                lines.append("## List \(index / 1_000)")
                lines.append("### Nested context")
                lines.append("  * [ ] Live \(index) @due(2026-08-01)")
            } else if index.isMultiple(of: 997) {
                lines.append("```md")
                lines.append("- [ ] Example \(index) @due(2026-08-01)")
                lines.append("```")
            } else {
                lines.append("ordinary Markdown line \(index)")
            }
        }
        lines.append("- [ ] Duplicate @due(2026-08-02)")
        lines.append("- [ ] Duplicate @due(2026-08-02)")
        let text = "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"

        let clock = ContinuousClock()
        let start = clock.now
        let scan = TaskParser.scan(in: text, sectioned: true)
        let names = TaskListDocument.sectionNames(in: text)
        let inserted = try TaskListDocument.insertingLineResult(
            "- [ ] Tail",
            inSection: "List 19",
            in: text
        ).get()
        let elapsed = start.duration(to: clock.now)

        XCTAssertEqual(names.count, 20)
        XCTAssertTrue(scan.tasks.contains { $0.text == "Live 19000" })
        XCTAssertFalse(scan.tasks.contains { $0.text.hasPrefix("Example ") })
        XCTAssertTrue(scan.diagnostics.contains { $0.kind == .duplicateTask })
        XCTAssertTrue(inserted.contains("- [ ] Tail\r\n"))
        XCTAssertTrue(inserted.hasPrefix("\u{FEFF}"))
        XCTAssertLessThan(
            elapsed,
            .seconds(10),
            "20k-line parse/list transform took \(elapsed)")
    }
}
