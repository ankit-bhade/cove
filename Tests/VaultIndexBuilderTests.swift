import XCTest
@testable import Cove

final class VaultIndexBuilderTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("cove-index-tests-\(UUID().uuidString)", isDirectory: true)

        // root/
        //   Projects/
        //     Plan.md      (one incomplete task, one completed)
        //   Groceries.md   (two incomplete tasks, later due date first in file)
        //   Journal.md     (no tasks)
        try fileManager.createDirectory(at: root.appendingPathComponent("Projects"),
                                        withIntermediateDirectories: true)
        try makeFile("Projects/Plan.md", contents: """
            # Plan
            - [ ] Ship the roadmap @due(2026-08-01)
            - [x] Draft outline @due(2026-07-01)
            """)
        try makeFile("Groceries.md", contents: """
            - [ ] Order cake @due(2026-09-15)
            - [ ] Buy milk @due(2026-07-20)
            """)
        try makeFile("Journal.md", contents: "Nothing due today.\n")
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func makeFile(_ path: String, contents: String) throws {
        try contents.write(to: root.appendingPathComponent(path),
                           atomically: true, encoding: .utf8)
    }

    private func builtIndex() throws -> VaultIndex {
        let tree = try VaultTreeScanner().scanTree(at: root)
        return VaultIndexBuilder().buildIndex(from: tree)
    }

    func testIndexHasOneEntryPerFileWithTitles() throws {
        let index = try builtIndex()
        XCTAssertEqual(index.entries.map(\.title), ["Plan", "Groceries", "Journal"])
        XCTAssertEqual(index.entries.map(\.tasks.count), [2, 2, 0])
    }

    func testTasksCarryTheirFileAndLine() throws {
        let index = try builtIndex()
        let milk = index.allTasks.first { $0.text == "Buy milk" }
        XCTAssertEqual(milk?.fileTitle, "Groceries")
        XCTAssertEqual(milk?.fileURL.lastPathComponent, "Groceries.md")
        XCTAssertEqual(milk?.lineNumber, 1)
    }

    func testIncompleteTasksSortByDueDateAcrossFiles() throws {
        let incomplete = try builtIndex().incompleteTasks
        XCTAssertEqual(incomplete.map(\.text),
                       ["Buy milk", "Ship the roadmap", "Order cake"])
        XCTAssertTrue(incomplete.allSatisfy { !$0.isCompleted })
    }

    func testCompletedTasksAreSeparate() throws {
        let completed = try builtIndex().completedTasks
        XCTAssertEqual(completed.map(\.text), ["Draft outline"])
    }
}
