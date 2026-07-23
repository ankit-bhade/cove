import XCTest
@testable import Cove

/// An app-created *content* change rebuilds the index over the tree already
/// in memory; anything that can change the tree's shape still rescans.
@MainActor
final class VaultManagerRefreshTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let fileManager = FileManager.default

    override func setUp() async throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "cove-refresh-tests-\(UUID().uuidString)",
                isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try "- [ ] Buy milk @due(2026-07-20)\n"
            .write(
                to: root.appendingPathComponent("Tasks.md"),
                atomically: true, encoding: .utf8)

        suiteName = "cove-refresh-defaults-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: root)
    }

    private func makeManager(recorder: ScanRecorder) -> VaultManager {
        let bookmarkStore = VaultBookmarkStore(
            defaults: defaults,
            creationOptions: [],
            resolutionOptions: [])
        return VaultManager(bookmarkStore: bookmarkStore) {
            url, previousIndex, changedURLs, existingTree in
            await recorder.record(reusedTree: existingTree != nil)
            let node = try existingTree ?? VaultTreeScanner().scanTree(at: url)
            let index = try VaultIndexBuilder().buildCancellableIndex(
                from: node, previous: previousIndex, changedURLs: changedURLs)
            return (node, index)
        }
    }

    func testCaptureRebuildsTheIndexWithoutRescanningTheTree() async throws {
        let recorder = ScanRecorder()
        let manager = makeManager(recorder: recorder)

        await manager.openVault(at: root)
        XCTAssertEqual(manager.index.allTasks.count, 1)

        var draft = TaskDraft(title: "Order cake")
        draft.dueDateString = "2026-07-21"
        try await manager.captureTask(draft)

        // Reused the tree, and still re-read the note it wrote to.
        let reuse = await recorder.reuse
        XCTAssertEqual(reuse, [false, true])
        XCTAssertEqual(manager.index.allTasks.count, 2)
        XCTAssertTrue(manager.index.allTasks.contains { $0.text == "Order cake" })
    }

    func testTogglingATaskRebuildsTheIndexWithoutRescanningTheTree() async throws {
        let recorder = ScanRecorder()
        let manager = makeManager(recorder: recorder)

        await manager.openVault(at: root)
        let task = try XCTUnwrap(manager.index.allTasks.first)
        try await manager.toggleTask(task)

        let reuse = await recorder.reuse
        XCTAssertEqual(reuse, [false, true])
        XCTAssertEqual(manager.index.allTasks.first?.isCompleted, true)
    }

    func testCreatingANoteRescansTheTree() async throws {
        let recorder = ScanRecorder()
        let manager = makeManager(recorder: recorder)

        await manager.openVault(at: root)
        try await manager.createNote(named: "Journal", in: root)

        let reuse = await recorder.reuse
        XCTAssertEqual(reuse, [false, false])
        XCTAssertTrue(
            manager.rootNode?.allFiles.contains {
                $0.url.lastPathComponent == "Journal.md"
            } == true)
    }

    /// The capture note is created on demand, so the write that creates it
    /// changes the tree and has to take the full rescan.
    func testCaptureIntoAMissingNoteRescansTheTree() async throws {
        try fileManager.removeItem(at: root.appendingPathComponent("Tasks.md"))
        let recorder = ScanRecorder()
        let manager = makeManager(recorder: recorder)

        await manager.openVault(at: root)
        var draft = TaskDraft(title: "Order cake")
        draft.dueDateString = "2026-07-21"
        try await manager.captureTask(draft)

        let reuse = await recorder.reuse
        XCTAssertEqual(reuse, [false, false])
        XCTAssertEqual(manager.index.allTasks.count, 1)
    }

    func testCaptureWithoutAnOpenVaultReportsAnError() async throws {
        let manager = makeManager(recorder: ScanRecorder())

        do {
            try await manager.captureTask(TaskDraft(title: "Order cake"))
            XCTFail("Expected capture to fail while no vault is open")
        } catch is VaultManager.VaultUnavailableError {
            // Expected.
        }
    }

    func testListMutationWithoutAnOpenVaultReportsAnError() async throws {
        let manager = makeManager(recorder: ScanRecorder())

        do {
            try await manager.createList(named: "Groceries")
            XCTFail("Expected list creation to fail while no vault is open")
        } catch is VaultManager.VaultUnavailableError {
            // Expected.
        }
    }
}

private actor ScanRecorder {
    private(set) var reuse: [Bool] = []

    func record(reusedTree: Bool) {
        reuse.append(reusedTree)
    }
}
