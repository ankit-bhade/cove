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

    func testFailedVaultSwitchKeepsLastGoodVaultAndBookmark() async throws {
        let failingRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "cove-failing-switch-\(UUID().uuidString)",
                isDirectory: true)
        try fileManager.createDirectory(
            at: failingRoot,
            withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: failingRoot) }
        struct InjectedFailure: LocalizedError {
            var errorDescription: String? { "Injected candidate failure" }
        }
        let bookmarkStore = VaultBookmarkStore(
            defaults: defaults,
            creationOptions: [],
            resolutionOptions: [])
        let manager = VaultManager(bookmarkStore: bookmarkStore) {
            url, previous, changed, existing in
            if url.standardizedFileURL == failingRoot.standardizedFileURL {
                throw InjectedFailure()
            }
            let node = try existing ?? VaultTreeScanner().scanTree(at: url)
            let index = try VaultIndexBuilder().buildCancellableIndex(
                from: node,
                previous: previous,
                changedURLs: changed)
            return (node, index)
        }

        await manager.openVault(at: root)
        let originalBookmark = bookmarkStore.bookmarkData
        await manager.openVault(at: failingRoot)

        XCTAssertEqual(manager.state, .open)
        XCTAssertEqual(
            manager.vaultURL?.standardizedFileURL,
            root.standardizedFileURL)
        XCTAssertEqual(bookmarkStore.bookmarkData, originalBookmark)
        XCTAssertTrue(
            manager.lastErrorDescription?.contains(
                "Injected candidate failure") == true)
    }

    func testTransientRefreshFailureRetainsLastGoodIndex() async throws {
        let loader = ControllableVaultLoader()
        let bookmarkStore = VaultBookmarkStore(
            defaults: defaults,
            creationOptions: [],
            resolutionOptions: [])
        let manager = VaultManager(bookmarkStore: bookmarkStore) {
            url, previous, changed, existing in
            try await loader.load(
                url: url,
                previous: previous,
                changed: changed,
                existing: existing)
        }

        await manager.openVault(at: root)
        let oldTasks = manager.index.allTasks
        await loader.failNextLoad()
        await manager.refresh()

        XCTAssertEqual(manager.state, .open)
        XCTAssertEqual(manager.index.allTasks, oldTasks)
        XCTAssertEqual(
            manager.vaultURL?.standardizedFileURL,
            root.standardizedFileURL)
        XCTAssertTrue(
            manager.lastErrorDescription?.contains(
                "last known-good") == true)
    }

    func testDirtyEditorProtectionBlocksVaultSwitch() async throws {
        let secondRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "cove-protected-switch-\(UUID().uuidString)",
                isDirectory: true)
        try fileManager.createDirectory(
            at: secondRoot,
            withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: secondRoot) }
        let manager = makeManager(recorder: ScanRecorder())

        await manager.openVault(at: root)
        let note = root.appendingPathComponent("Tasks.md")
        manager.setEditorProtection(true, for: note)
        await manager.openVault(at: secondRoot)

        XCTAssertEqual(
            manager.vaultURL?.standardizedFileURL,
            root.standardizedFileURL)
        XCTAssertTrue(
            manager.lastErrorDescription?.contains(
                "before switching vaults") == true)
    }
}

private actor ScanRecorder {
    private(set) var reuse: [Bool] = []

    func record(reusedTree: Bool) {
        reuse.append(reusedTree)
    }
}

private actor ControllableVaultLoader {
    private var shouldFail = false

    func failNextLoad() {
        shouldFail = true
    }

    func load(
        url: URL,
        previous: VaultIndex,
        changed: Set<URL>?,
        existing: VaultNode?
    ) throws -> (VaultNode, VaultIndex) {
        if shouldFail {
            shouldFail = false
            throw CocoaError(.fileReadUnknown)
        }
        let node = try existing ?? VaultTreeScanner().scanTree(at: url)
        let index = try VaultIndexBuilder().buildCancellableIndex(
            from: node,
            previous: previous,
            changedURLs: changed)
        return (node, index)
    }
}
