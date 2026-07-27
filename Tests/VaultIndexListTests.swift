import XCTest
@testable import Cove

/// How the index separates list tasks from ordinary ones, and how it orders
/// dated against undated items.
final class VaultIndexListTests: XCTestCase {

    private func task(
        _ text: String,
        due: String? = nil,
        time: String? = nil,
        list: String? = nil,
        line: Int = 0,
        completed: Bool = false
    ) -> TaskItem {
        TaskItem(
            fileURL: URL(fileURLWithPath: "/vault/Tasks.md"),
            fileTitle: "Tasks",
            lineNumber: line,
            text: text,
            dueDateString: due,
            dueTimeString: time,
            recurrence: nil,
            isCompleted: completed,
            listName: list)
    }

    private func index(_ tasks: [TaskItem], lists: [String] = []) -> VaultIndex {
        VaultIndex(
            entries: [
                NoteIndexEntry(
                    url: URL(fileURLWithPath: "/vault/Tasks.md"),
                    title: "Tasks",
                    tasks: tasks)
            ],
            listNames: lists)
    }

    // MARK: - Separation

    func testUndatedListTasksAreExcludedFromTheTasksScreen() {
        let subject = index(
            [
                task("Ordinary", due: "2026-07-20"),
                task("Milk", list: "Groceries", line: 1),
            ],
            lists: ["Groceries"])
        XCTAssertEqual(subject.incompleteTasks.map(\.text), ["Ordinary"])
    }

    /// A dated list item is scheduled work, so it appears among the other
    /// scheduled work rather than only inside its list.
    func testDatedListTasksAppearOnTheTasksScreen() {
        let subject = index(
            [
                task("Ordinary", due: "2026-07-22"),
                task("Milk", list: "Groceries", line: 1),
                task("Laundry", due: "2026-07-20", list: "Chores", line: 2),
            ],
            lists: ["Groceries", "Chores"])
        XCTAssertEqual(subject.incompleteTasks.map(\.text), ["Laundry", "Ordinary"])
    }

    func testDatedListTasksStayInTheirListToo() {
        let subject = index(
            [task("Laundry", due: "2026-07-20", list: "Chores")],
            lists: ["Chores"])
        XCTAssertEqual(subject.lists.first?.openTasks.map(\.text), ["Laundry"])
    }

    func testUndatedCompletedListTasksAreExcludedToo() {
        let subject = index(
            [
                task("Done", due: "2026-07-20", completed: true),
                task("Bread", list: "Groceries", line: 1, completed: true),
            ],
            lists: ["Groceries"])
        XCTAssertEqual(subject.completedTasks.map(\.text), ["Done"])
    }

    /// The completed section admits exactly what the open sections do, which
    /// is what keeps the screen's Clear All clearing only what it showed.
    func testCompletedDatedListTasksAppearOnTheTasksScreen() {
        let subject = index(
            [
                task("Done", due: "2026-07-20", completed: true),
                task("Bread", list: "Groceries", line: 1, completed: true),
                task("Laundry", due: "2026-07-21", list: "Chores", line: 2, completed: true),
            ],
            lists: ["Groceries", "Chores"])
        XCTAssertEqual(subject.completedTasks.map(\.text), ["Done", "Laundry"])
    }

    // MARK: - Lists

    func testListsFollowHeadingOrderNotTaskOrder() {
        let subject = index(
            [
                task("Netflix", list: "Subscriptions", line: 1),
                task("Milk", list: "Groceries", line: 3),
            ],
            lists: ["Groceries", "Subscriptions"])
        XCTAssertEqual(subject.lists.map(\.name), ["Groceries", "Subscriptions"])
    }

    func testAListWithNoTasksStillExists() {
        let subject = index([], lists: ["Packing"])
        XCTAssertEqual(subject.lists.map(\.name), ["Packing"])
        XCTAssertTrue(subject.lists.first?.isEmpty == true)
    }

    func testListSplitsOpenFromCompleted() {
        let subject = index(
            [
                task("Milk", list: "Groceries", line: 1),
                task("Bread", list: "Groceries", line: 2, completed: true),
            ],
            lists: ["Groceries"])
        XCTAssertEqual(subject.lists.first?.openTasks.map(\.text), ["Milk"])
        XCTAssertEqual(subject.lists.first?.completedTasks.map(\.text), ["Bread"])
    }

    // MARK: - Ordering

    func testDatedItemsSortBeforeUndatedOnes() {
        let subject = index(
            [
                task("Milk", list: "Groceries", line: 1),
                task("Cake", due: "2026-07-22", list: "Groceries", line: 2),
                task("Eggs", list: "Groceries", line: 3),
            ],
            lists: ["Groceries"])
        XCTAssertEqual(
            subject.lists.first?.openTasks.map(\.text),
            ["Cake", "Milk", "Eggs"])
    }

    func testUndatedItemsKeepTheOrderTheyWereAdded() {
        let subject = index(
            [
                task("Eggs", list: "Groceries", line: 5),
                task("Milk", list: "Groceries", line: 2),
            ],
            lists: ["Groceries"])
        XCTAssertEqual(subject.lists.first?.openTasks.map(\.text), ["Milk", "Eggs"])
    }

    // MARK: - Capture note identity

    func testOnlyTheRootTasksNoteIsTheCaptureNote() {
        let root = URL(fileURLWithPath: "/vault", isDirectory: true)
        XCTAssertTrue(
            VaultManager.isCaptureNote(
                URL(fileURLWithPath: "/vault/Tasks.md"), vaultRoot: root))
        XCTAssertTrue(
            VaultManager.isCaptureNote(
                URL(fileURLWithPath: "/vault/tasks.md"), vaultRoot: root))
        XCTAssertFalse(
            VaultManager.isCaptureNote(
                URL(fileURLWithPath: "/vault/Work/Tasks.md"), vaultRoot: root))
        XCTAssertFalse(
            VaultManager.isCaptureNote(
                URL(fileURLWithPath: "/vault/Notes.md"), vaultRoot: root))
    }
}
