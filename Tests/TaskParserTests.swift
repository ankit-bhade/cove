import XCTest
@testable import Cove

final class TaskParserTests: XCTestCase {

    // MARK: - Matching lines

    func testParsesIncompleteTaskLine() {
        let tasks = TaskParser.tasks(in: "- [ ] Buy milk @due(2026-07-20)\n")
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.text, "Buy milk")
        XCTAssertEqual(tasks.first?.dueDateString, "2026-07-20")
        XCTAssertEqual(tasks.first?.lineNumber, 0)
        XCTAssertEqual(tasks.first?.isCompleted, false)
    }

    func testParsesCompletedTaskWithEitherCase() {
        let tasks = TaskParser.tasks(in: """
            - [x] Done low @due(2026-01-01)
            - [X] Done high @due(2026-01-02)
            """)
        XCTAssertEqual(tasks.map(\.isCompleted), [true, true])
        XCTAssertEqual(tasks.map(\.lineNumber), [0, 1])
    }

    func testTaskLinesMixedWithOtherContent() {
        let text = """
            # Groceries
            Some intro text.
            - [ ] Milk @due(2026-07-19)
            - [ ] No due date here
            - [x] Eggs @due(2026-07-18)
            """
        let tasks = TaskParser.tasks(in: text)
        XCTAssertEqual(tasks.map(\.text), ["Milk", "Eggs"])
        XCTAssertEqual(tasks.map(\.lineNumber), [2, 4])
    }

    func testLastDueTagOnLineWinsAndTextKeepsEarlierOnes() {
        let tasks = TaskParser.tasks(in: "- [ ] Move @due(2026-01-01) party @due(2026-02-02)\n")
        XCTAssertEqual(tasks.first?.text, "Move @due(2026-01-01) party")
        XCTAssertEqual(tasks.first?.dueDateString, "2026-02-02")
    }

    func testAllowsTrailingWhitespace() {
        let tasks = TaskParser.tasks(in: "- [ ] Water plants @due(2026-07-19)  \n")
        XCTAssertEqual(tasks.count, 1)
    }

    // MARK: - Non-matching lines

    func testRejectsAlternateSyntax() {
        let text = """
            - [ ] Missing due tag
            - [ ]Tight marker @due(2026-07-19)
            - [ ]  Two spaces after marker @due(2026-07-19)
            - [ ] @due(2026-07-19)
            - [ ] Trailing text @due(2026-07-19) extra
            * [ ] Star bullet @due(2026-07-19)
            -[ ] No space @due(2026-07-19)
            """
        XCTAssertTrue(TaskParser.tasks(in: text).isEmpty)
    }

    func testRejectsIndentedTaskLine() {
        XCTAssertTrue(TaskParser.tasks(in: "  - [ ] Indented @due(2026-07-19)\n").isEmpty)
    }

    func testRejectsInvalidOrMalformedDates() {
        let text = """
            - [ ] Bad day @due(2026-02-30)
            - [ ] Bad month @due(2026-13-01)
            - [ ] Not padded @due(2026-7-9)
            - [ ] Not a date @due(soon)
            """
        XCTAssertTrue(TaskParser.tasks(in: text).isEmpty)
    }

    func testAcceptsLeapDayOnlyInLeapYears() {
        XCTAssertEqual(TaskParser.tasks(in: "- [ ] Leap @due(2028-02-29)").count, 1)
        XCTAssertTrue(TaskParser.tasks(in: "- [ ] No leap @due(2026-02-29)").isEmpty)
    }

    // MARK: - Toggling

    func testTogglingIncompleteTaskChecksIt() {
        let text = "Intro\n- [ ] Buy milk @due(2026-07-20)\n"
        let updated = TaskParser.togglingTask(
            withText: "Buy milk", dueDateString: "2026-07-20",
            isCompleted: false, preferredLineNumber: 1, in: text)
        XCTAssertEqual(updated, "Intro\n- [x] Buy milk @due(2026-07-20)\n")
    }

    func testTogglingCompletedTaskUnchecksIt() {
        let text = "- [X] Buy milk @due(2026-07-20)\n"
        let updated = TaskParser.togglingTask(
            withText: "Buy milk", dueDateString: "2026-07-20",
            isCompleted: true, preferredLineNumber: 0, in: text)
        XCTAssertEqual(updated, "- [ ] Buy milk @due(2026-07-20)\n")
    }

    func testTogglingPrefersRememberedLineAmongDuplicates() {
        let text = """
            - [ ] Call mom @due(2026-07-20)
            - [ ] Call mom @due(2026-07-20)
            """
        let updated = TaskParser.togglingTask(
            withText: "Call mom", dueDateString: "2026-07-20",
            isCompleted: false, preferredLineNumber: 1, in: text)
        XCTAssertEqual(updated, """
            - [ ] Call mom @due(2026-07-20)
            - [x] Call mom @due(2026-07-20)
            """)
    }

    func testTogglingFallsBackWhenLinesShifted() {
        let text = "New first line\n- [ ] Buy milk @due(2026-07-20)\n"
        let updated = TaskParser.togglingTask(
            withText: "Buy milk", dueDateString: "2026-07-20",
            isCompleted: false, preferredLineNumber: 0, in: text)
        XCTAssertEqual(updated, "New first line\n- [x] Buy milk @due(2026-07-20)\n")
    }

    func testTogglingReturnsNilWhenTaskIsGone() {
        XCTAssertNil(TaskParser.togglingTask(
            withText: "Buy milk", dueDateString: "2026-07-20",
            isCompleted: false, preferredLineNumber: 0, in: "Nothing here\n"))
        // Same text but the state on disk no longer matches.
        XCTAssertNil(TaskParser.togglingTask(
            withText: "Buy milk", dueDateString: "2026-07-20",
            isCompleted: false, preferredLineNumber: 0,
            in: "- [x] Buy milk @due(2026-07-20)\n"))
    }
}
