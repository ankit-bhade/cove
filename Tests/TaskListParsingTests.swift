import XCTest
@testable import Cove

/// The list half of `TaskParser`: `##` sections, undated items, and the
/// guarantee that none of it leaks into an ordinary note's parse.
final class TaskListParsingTests: XCTestCase {

    private let note = """
        - [ ] Renew passport @due(2026-07-25)

        ## Groceries
        - [ ] Milk
        - [x] Bread
        - [ ] Order cake @due(2026-07-22 15:00)

        ## Subscriptions
        - [ ] Netflix @due(2026-08-01) @repeat(monthly)
        """

    // MARK: - Sectioned parsing

    func testTasksAboveTheFirstHeadingHaveNoList() {
        let tasks = TaskParser.tasks(in: note, sectioned: true)
        XCTAssertEqual(tasks.first?.text, "Renew passport")
        XCTAssertNil(tasks.first?.listName)
    }

    func testTasksUnderAHeadingCarryItsName() {
        let tasks = TaskParser.tasks(in: note, sectioned: true)
        XCTAssertEqual(
            tasks.map(\.listName),
            [nil, "Groceries", "Groceries", "Groceries", "Subscriptions"])
    }

    func testUndatedListItemsAreParsed() {
        let tasks = TaskParser.tasks(in: note, sectioned: true)
        let milk = tasks.first { $0.text == "Milk" }
        XCTAssertNotNil(milk)
        XCTAssertNil(milk?.dueDateString)
        XCTAssertNil(milk?.dueDateRange)
        XCTAssertEqual(milk?.isCompleted, false)
    }

    func testUndatedListItemsRecordCompletion() {
        let tasks = TaskParser.tasks(in: note, sectioned: true)
        XCTAssertEqual(tasks.first { $0.text == "Bread" }?.isCompleted, true)
    }

    func testListItemsKeepFullSchedulesAndRecurrence() {
        let tasks = TaskParser.tasks(in: note, sectioned: true)
        let cake = tasks.first { $0.text == "Order cake" }
        XCTAssertEqual(cake?.dueDateString, "2026-07-22")
        XCTAssertEqual(cake?.dueTimeString, "15:00")

        let netflix = tasks.first { $0.text == "Netflix" }
        XCTAssertEqual(netflix?.recurrence, RecurrenceRule(frequency: .monthly))
    }

    func testATopLevelHeadingClosesTheOpenList() {
        let text = """
            ## Groceries
            - [ ] Milk
            # Notes
            - [ ] Loose end @due(2026-07-20)
            """
        let tasks = TaskParser.tasks(in: text, sectioned: true)
        XCTAssertEqual(tasks.map(\.listName), ["Groceries", nil])
    }

    func testAMalformedDueTagIsNotTreatedAsAnUndatedItem() {
        let text = "## Groceries\n- [ ] Milk @due(2026-13-45)\n"
        XCTAssertTrue(TaskParser.tasks(in: text, sectioned: true).isEmpty)
    }

    func testIndentedAndAlternateBulletListLinesAreParsed() {
        let text = "## Groceries\n  - [ ] Milk\n\t* [x] Bread\n+ [ ] Eggs\n"
        let tasks = TaskParser.tasks(in: text, sectioned: true)
        XCTAssertEqual(tasks.map(\.text), ["Milk", "Bread", "Eggs"])
        XCTAssertEqual(tasks.map(\.isCompleted), [false, true, false])
    }

    // MARK: - Unsectioned parsing is unchanged

    func testUnsectionedParsingIgnoresHeadingsAndUndatedLines() {
        let tasks = TaskParser.tasks(in: note)
        XCTAssertEqual(tasks.map(\.text), ["Renew passport", "Order cake", "Netflix"])
        XCTAssertTrue(tasks.allSatisfy { $0.listName == nil })
    }

    // MARK: - Toggling and removing list items

    /// An undated list item, identified the way the Lists screen identifies
    /// one: no date, no time, no rule — just its text and its heading.
    private func listItem(_ text: String, list: String, line: Int) -> TaskIdentity {
        TaskIdentity(
            filePath: "/vault/Tasks.md",
            lineNumber: line,
            text: text,
            dueDateString: nil,
            dueTimeString: nil,
            recurrenceTag: nil,
            listName: list)
    }

    func testTogglingAnUndatedListItemChecksIt() {
        let result = TaskParser.settingTaskCompleted(
            listItem("Milk", list: "Groceries", line: 3),
            to: true, todayDateString: "2026-07-19", in: note)
        XCTAssertEqual(
            result,
            note.replacingOccurrences(
                of: "- [ ] Milk",
                with: "- [x] Milk"))
    }

    func testTogglingDoesNotCrossListBoundaries() {
        let text = """
            ## Groceries
            - [ ] Milk
            ## Pantry
            - [ ] Milk
            """
        let result = TaskParser.settingTaskCompleted(
            listItem("Milk", list: "Pantry", line: 3),
            to: true, todayDateString: "2026-07-19", in: text)
        XCTAssertEqual(
            result,
            """
            ## Groceries
            - [ ] Milk
            ## Pantry
            - [x] Milk
            """)
    }

    func testRemovingAnUndatedListItemDropsItsLine() {
        let result = TaskParser.removingTask(
            listItem("Milk", list: "Groceries", line: 3), in: note)
        XCTAssertEqual(result, note.replacingOccurrences(of: "- [ ] Milk\n", with: ""))
    }

    // MARK: - Clearing completed

    func testClearingCompletedLeavesListItemsAlone() {
        let text = """
            - [x] Ordinary @due(2026-07-01)

            ## Groceries
            - [x] Bread
            - [x] Butter @due(2026-07-02)
            """
        XCTAssertEqual(
            TaskParser.clearingCompletedTasks(in: text, sectioned: true),
            """

            ## Groceries
            - [x] Bread
            - [x] Butter @due(2026-07-02)
            """)
    }

    func testClearingCompletedInAListLeavesEverythingElseAlone() {
        let text = """
            - [x] Ordinary @due(2026-07-01)

            ## Groceries
            - [x] Bread
            - [ ] Milk
            - [x] Butter @due(2026-07-02)

            ## Packing
            - [x] Charger
            """
        XCTAssertEqual(
            TaskParser.clearingCompletedTasks(in: text, sectioned: true, inList: "Groceries"),
            """
            - [x] Ordinary @due(2026-07-01)

            ## Groceries
            - [ ] Milk

            ## Packing
            - [x] Charger
            """)
    }

    func testClearingCompletedMatchesTheListNameCaseInsensitively() {
        let text = """
            ## Groceries
            - [x] Bread
            """
        XCTAssertEqual(
            TaskParser.clearingCompletedTasks(in: text, sectioned: true, inList: "groceries"),
            "## Groceries\n")
    }
}
