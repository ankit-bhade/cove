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
        return try VaultIndexBuilder().buildIndex(from: tree)
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

    func testIncrementalRebuildUpdatesOnlyChangedNoteAndMatchesFullBuild() throws {
        let scanner = VaultTreeScanner()
        let builder = VaultIndexBuilder()
        let originalTree = try scanner.scanTree(at: root)
        let original = try builder.buildCancellableIndex(from: originalTree)
        let groceriesURL = root.appendingPathComponent("Groceries.md")
        let journalURL = root.appendingPathComponent("Journal.md")
        let cachedJournal = try XCTUnwrap(original.entries.first { $0.url == journalURL })
        try makeFile("Groceries.md", contents: "- [ ] Tea @due(2026-07-21)\n")
        let changedTree = try scanner.scanTree(at: root)

        let incremental = try builder.buildCancellableIndex(
            from: changedTree, previous: original, changedURLs: [groceriesURL])
        let clean = try builder.buildCancellableIndex(from: changedTree)

        XCTAssertEqual(incremental.entries, clean.entries)
        XCTAssertEqual(incremental.listNames, clean.listNames)
        XCTAssertEqual(incremental.allTasks.map(\.text).filter { $0 == "Tea" }, ["Tea"])
        XCTAssertEqual(incremental.entries.first { $0.url == journalURL }, cachedJournal)
    }

    func testDeletedNoteDisappearsFromIncrementalIndex() throws {
        let scanner = VaultTreeScanner()
        let builder = VaultIndexBuilder()
        let originalTree = try scanner.scanTree(at: root)
        let original = try builder.buildCancellableIndex(from: originalTree)
        let deletedURL = root.appendingPathComponent("Groceries.md")
        try fileManager.removeItem(at: deletedURL)

        let changedTree = try scanner.scanTree(at: root)
        let incremental = try builder.buildCancellableIndex(
            from: changedTree, previous: original, changedURLs: [deletedURL])

        XCTAssertFalse(incremental.entries.contains { $0.url == deletedURL })
        XCTAssertFalse(incremental.allTasks.contains { $0.fileURL == deletedURL })
    }

    func testRecoveryDirectoryNeverEntersTreeOrIndex() throws {
        try fileManager.createDirectory(at: root.appendingPathComponent(".cove-recovery"),
                                        withIntermediateDirectories: true)
        try makeFile(".cove-recovery/Deleted.md",
                     contents: "- [ ] Hidden @due(2026-07-20)\n")

        let tree = try VaultTreeScanner().scanTree(at: root)
        let index = try VaultIndexBuilder().buildCancellableIndex(from: tree)

        XCTAssertFalse(tree.allFiles.contains { $0.name == "Deleted.md" })
        XCTAssertFalse(index.allTasks.contains { $0.text == "Hidden" })
    }
}
