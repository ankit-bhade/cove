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
        try fileManager.createDirectory(
            at: root.appendingPathComponent("Projects"),
            withIntermediateDirectories: true)
        try makeFile(
            "Projects/Plan.md",
            contents: """
                # Plan
                - [ ] Ship the roadmap @due(2026-08-01)
                - [x] Draft outline @due(2026-07-01)
                """)
        try makeFile(
            "Groceries.md",
            contents: """
                - [ ] Order cake @due(2026-09-15)
                - [ ] Buy milk @due(2026-07-20)
                """)
        try makeFile("Journal.md", contents: "Nothing due today.\n")
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func makeFile(_ path: String, contents: String) throws {
        try contents.write(
            to: root.appendingPathComponent(path),
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
        XCTAssertEqual(
            incomplete.map(\.text),
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
        try fileManager.createDirectory(
            at: root.appendingPathComponent(".cove-recovery"),
            withIntermediateDirectories: true)
        try makeFile(
            ".cove-recovery/Deleted.md",
            contents: "- [ ] Hidden @due(2026-07-20)\n")

        let tree = try VaultTreeScanner().scanTree(at: root)
        let index = try VaultIndexBuilder().buildCancellableIndex(from: tree)

        XCTAssertFalse(tree.allFiles.contains { $0.name == "Deleted.md" })
        XCTAssertFalse(index.allTasks.contains { $0.text == "Hidden" })
    }

    // MARK: - Unreadable notes

    /// A note the app can't read is one bad file, not a bad vault: the rest
    /// of the index has to survive it.
    func testUnreadableNoteIsIndexedWithoutTasksAndKeepsTheVaultLoading() throws {
        try Data([0x2D, 0x20, 0x5B, 0x20, 0x5D, 0xFF, 0xFE, 0xFF])
            .write(to: root.appendingPathComponent("Broken.md"))

        let index = try builtIndex()

        XCTAssertEqual(index.entries.count, 4)
        XCTAssertEqual(index.entries.first { $0.title == "Broken" }?.tasks.count, 0)
        // Every task in the readable notes is still indexed.
        XCTAssertEqual(index.allTasks.count, 4)
    }

    /// The skipped note carries no cache key, so the next rebuild reads it
    /// again rather than trusting a failure forever.
    func testUnreadableNoteIsNotCachedAcrossRebuilds() throws {
        let brokenURL = root.appendingPathComponent("Broken.md")
        try Data([0xFF, 0xFE, 0xFF]).write(to: brokenURL)

        let tree = try VaultTreeScanner().scanTree(at: root)
        let first = try VaultIndexBuilder().buildCancellableIndex(from: tree)
        XCTAssertNil(first.entries.first { $0.title == "Broken" }?.modificationDate)

        try "- [ ] Fixed now @due(2026-08-02)\n".write(
            to: brokenURL,
            atomically: true,
            encoding: .utf8)
        let second = try VaultIndexBuilder().buildCancellableIndex(
            from: tree,
            previous: first)
        XCTAssertEqual(
            second.entries.first { $0.title == "Broken" }?.tasks.first?.text,
            "Fixed now")
    }

    func testTransientUnreadableNoteRetainsLastKnownTasks() throws {
        let scanner = VaultTreeScanner()
        let tree = try scanner.scanTree(at: root)
        let first = try VaultIndexBuilder().buildCancellableIndex(from: tree)
        let groceriesURL = root.appendingPathComponent("Groceries.md")
        try Data([0xFF, 0xFE, 0xFF]).write(to: groceriesURL)

        let second = try VaultIndexBuilder().buildCancellableIndex(
            from: tree,
            previous: first)

        XCTAssertEqual(
            second.entries.first { $0.url == groceriesURL }?.tasks.map(\.text),
            ["Order cake", "Buy milk"])
        XCTAssertNil(
            second.entries.first { $0.url == groceriesURL }?.modificationDate)
    }

    func testCatchAllRefreshDoesNotTrustSameSizeAndTimestamp() throws {
        let scanner = VaultTreeScanner()
        let builder = VaultIndexBuilder()
        let tree = try scanner.scanTree(at: root)
        let first = try builder.buildCancellableIndex(from: tree)
        let groceriesURL = root.appendingPathComponent("Groceries.md")
        let originalDate = try XCTUnwrap(
            groceriesURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate)
        let oldText = try String(
            contentsOf: groceriesURL,
            encoding: .utf8)
        let replacement = oldText.replacingOccurrences(
            of: "Order cake",
            with: "Order pies")
        XCTAssertEqual(oldText.utf8.count, replacement.utf8.count)
        try replacement.write(
            to: groceriesURL,
            atomically: true,
            encoding: .utf8)
        try fileManager.setAttributes(
            [.modificationDate: originalDate],
            ofItemAtPath: groceriesURL.path)

        let refreshed = try builder.buildCancellableIndex(
            from: tree,
            previous: first,
            changedURLs: nil)

        XCTAssertTrue(
            refreshed.allTasks.contains { $0.text == "Order pies" })
        XCTAssertFalse(
            refreshed.allTasks.contains { $0.text == "Order cake" })
    }

    func testConflictAndRecoveryCopiesNeverBecomeOperationalTasks() throws {
        try makeFile(
            "Plan.cove-conflict-icloud-abc.md",
            contents: "- [ ] Conflict copy @due(2026-08-03)\n")
        try makeFile(
            "Plan.cove-recovered-20260724-203000.md",
            contents: "- [ ] Recovery copy @due(2026-08-04)\n")

        let index = try builtIndex()

        XCTAssertTrue(
            index.entries.contains {
                $0.url.lastPathComponent.contains(".cove-conflict-")
            })
        XCTAssertTrue(
            index.entries.contains {
                $0.url.lastPathComponent.contains(".cove-recovered-")
            })
        XCTAssertFalse(
            index.allTasks.contains {
                $0.text == "Conflict copy" || $0.text == "Recovery copy"
            })
    }

    func testLargeVaultScanAndIndexRegression() throws {
        for folderNumber in 0..<20 {
            let folder = root.appendingPathComponent(
                "Bulk-\(folderNumber)",
                isDirectory: true)
            try fileManager.createDirectory(
                at: folder,
                withIntermediateDirectories: true)
            for noteNumber in 0..<100 {
                try "- [ ] Task \(folderNumber)-\(noteNumber) @due(2026-08-01)\n"
                    .write(
                        to: folder.appendingPathComponent(
                            "Note-\(noteNumber).md"),
                        atomically: true,
                        encoding: .utf8)
            }
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTClockMetric()], options: options) {
            XCTAssertNoThrow {
                let tree = try VaultTreeScanner().scanTree(at: self.root)
                let index = try VaultIndexBuilder().buildIndex(from: tree)
                XCTAssertEqual(tree.allFiles.count, 2_003)
                XCTAssertEqual(index.allTasks.count, 2_004)
            }
        }
    }
}
