import XCTest
@testable import Cove

/// An app-created *content* change rebuilds the index over the tree already
/// in memory; anything that can change the tree's shape still rescans.
@MainActor
final class VaultManagerRefreshTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var widgetRoot: URL!
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
        widgetRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "cove-refresh-widget-\(UUID().uuidString)",
                isDirectory: true)
        try fileManager.createDirectory(
            at: widgetRoot,
            withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: root)
        try? fileManager.removeItem(at: widgetRoot)
    }

    private func makeManager(recorder: ScanRecorder) -> VaultManager {
        let bookmarkStore = VaultBookmarkStore(
            defaults: defaults,
            creationOptions: [],
            resolutionOptions: [])
        return isolatedManager(
            bookmarkStore: bookmarkStore,
            loadOperation: {
                url, previousIndex, changedURLs, existingTree in
                await recorder.record(reusedTree: existingTree != nil)
                let node = try existingTree ?? VaultTreeScanner().scanTree(at: url)
                let index = try VaultIndexBuilder().buildCancellableIndex(
                    from: node, previous: previousIndex, changedURLs: changedURLs)
                return (node, index)
            })
    }

    private func isolatedManager(
        bookmarkStore: VaultBookmarkStore,
        loadOperation: @escaping VaultLoadOperation
    ) -> VaultManager {
        VaultManager(
            bookmarkStore: bookmarkStore,
            loadOperation: loadOperation,
            notificationRebuild: { _ in .superseded() },
            notificationCancel: { .superseded() },
            widgetStore: WidgetSnapshotStore(containerURL: widgetRoot),
            reloadWidgetTimelines: {})
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

    // MARK: - Capture undo

    /// Capture was the one mutating task action with no way back. Undo takes
    /// the line out again and leaves the rest of the note alone.
    func testUndoingACaptureRemovesOnlyThatLine() async throws {
        let manager = makeManager(recorder: ScanRecorder())
        await manager.openVault(at: root)

        var draft = TaskDraft(title: "Order cake")
        draft.dueDateString = "2026-07-21"
        let captured = try await manager.captureTask(draft)
        let record = try XCTUnwrap(captured)
        XCTAssertEqual(manager.index.allTasks.count, 2)

        try await manager.undoCapturedTask(record)

        XCTAssertEqual(manager.index.allTasks.count, 1)
        XCTAssertEqual(manager.index.allTasks.first?.text, "Buy milk")
        XCTAssertEqual(
            try String(
                contentsOf: root.appendingPathComponent("Tasks.md"),
                encoding: .utf8),
            "- [ ] Buy milk @due(2026-07-20)\n")
    }

    /// A list item's identity includes its list, so Undo has to find the line
    /// under the heading it was written to rather than missing it entirely.
    func testUndoingACaptureIntoAList() async throws {
        let manager = makeManager(recorder: ScanRecorder())
        await manager.openVault(at: root)
        try await manager.createList(named: "Groceries")

        let captured = try await manager.captureTask(
            TaskDraft(title: "Milk"), into: "Groceries")
        let record = try XCTUnwrap(captured)
        XCTAssertEqual(record.identity.listName, "Groceries")
        XCTAssertTrue(manager.index.allTasks.contains { $0.text == "Milk" })

        try await manager.undoCapturedTask(record)

        XCTAssertFalse(manager.index.allTasks.contains { $0.text == "Milk" })
        // The heading survives; only the line goes.
        XCTAssertTrue(manager.index.listNames.contains("Groceries"))
    }

    /// Undo re-finds its line semantically, so it targets the capture even
    /// after the note is edited around it.
    func testUndoingACaptureAfterTheNoteMovesOn() async throws {
        let manager = makeManager(recorder: ScanRecorder())
        await manager.openVault(at: root)

        var draft = TaskDraft(title: "Order cake")
        draft.dueDateString = "2026-07-21"
        let captured = try await manager.captureTask(draft)
        let record = try XCTUnwrap(captured)

        var later = TaskDraft(title: "Call plumber")
        later.dueDateString = "2026-07-22"
        try await manager.captureTask(later)
        XCTAssertEqual(manager.index.allTasks.count, 3)

        try await manager.undoCapturedTask(record)

        XCTAssertEqual(
            manager.index.allTasks.map(\.text).sorted(),
            ["Buy milk", "Call plumber"])
    }

    /// The whole point of matching semantically is refusing to guess. Two
    /// identical lines cannot be told apart, so Undo declines rather than
    /// removing whichever one it happened to find first.
    func testUndoingACaptureRefusesWhenTheLineIsAmbiguous() async throws {
        let manager = makeManager(recorder: ScanRecorder())
        await manager.openVault(at: root)

        var draft = TaskDraft(title: "Order cake")
        draft.dueDateString = "2026-07-21"
        let captured = try await manager.captureTask(draft)
        let record = try XCTUnwrap(captured)
        try await manager.captureTask(draft)
        XCTAssertEqual(manager.index.allTasks.count, 3)

        do {
            try await manager.undoCapturedTask(record)
            XCTFail("Expected an ambiguous-task refusal")
        } catch TaskParser.MutationError.ambiguousTask {
            // Expected: both lines stay.
        }
        XCTAssertEqual(manager.index.allTasks.count, 3)
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
        let manager = isolatedManager(
            bookmarkStore: bookmarkStore
        ) { url, previous, changed, existing in
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
        let manager = isolatedManager(
            bookmarkStore: bookmarkStore
        ) { url, previous, changed, existing in
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

    func testRootChangeEventForcesFullRefresh() {
        let nestedFile = root.appendingPathComponent("Tasks.md")

        XCTAssertNil(
            VaultManager.changedURLsForRefresh(
                [root],
                vaultRoot: root))
        XCTAssertNil(
            VaultManager.changedURLsForRefresh(
                [root, nestedFile],
                vaultRoot: root))
    }

    func testFileChangeEventRemainsTargeted() {
        let nestedFile = root.appendingPathComponent("Tasks.md")

        XCTAssertEqual(
            VaultManager.changedURLsForRefresh(
                [nestedFile],
                vaultRoot: root),
            [nestedFile])
    }

    func testClearCompletedUndoPreservesLaterUnrelatedEdits() async throws {
        let note = root.appendingPathComponent("Tasks.md")
        try """
        Intro
        - [x] Finished @due(2026-07-20)
        - [ ] Open @due(2026-07-21)
        """
        .write(to: note, atomically: true, encoding: .utf8)
        let manager = makeManager(recorder: ScanRecorder())
        await manager.openVault(at: root)

        let records = try await manager.clearCompletedTasks()
        XCTAssertEqual(records.count, 1)
        var afterClear = try String(contentsOf: note, encoding: .utf8)
        afterClear += "Added after clear\n"
        try afterClear.write(to: note, atomically: true, encoding: .utf8)

        try await manager.restoreDeletedTasks(records)

        let restored = try String(contentsOf: note, encoding: .utf8)
        XCTAssertTrue(restored.contains("- [x] Finished @due(2026-07-20)"))
        XCTAssertTrue(restored.contains("- [ ] Open @due(2026-07-21)"))
        XCTAssertTrue(restored.contains("Added after clear"))
    }

    func testClearCompletedPreflightPreventsPartialMultiFileClear() async throws {
        let first = root.appendingPathComponent("Tasks.md")
        let second = root.appendingPathComponent("Other.md")
        let firstLine = "- [x] First @due(2026-07-20)\n"
        try firstLine.write(to: first, atomically: true, encoding: .utf8)
        try "- [x] Second @due(2026-07-20)\n"
            .write(to: second, atomically: true, encoding: .utf8)
        let manager = makeManager(recorder: ScanRecorder())
        await manager.openVault(at: root)
        XCTAssertEqual(manager.index.completedTasks.count, 2)

        // Make the second indexed target stale before the bulk operation.
        try "- [ ] Second @due(2026-07-20)\n"
            .write(to: second, atomically: true, encoding: .utf8)

        await XCTAssertThrowsErrorAsync {
            _ = try await manager.clearCompletedTasks()
        }
        XCTAssertEqual(
            try String(contentsOf: first, encoding: .utf8),
            firstLine)
    }

    /// The Tasks screen shows a list's dated items, so its Clear All sweeps
    /// them — and leaves the undated ones, which it never showed, in place.
    func testClearCompletedTakesDatedListItemsButNotUndatedOnes() async throws {
        let note = root.appendingPathComponent("Tasks.md")
        try """
        - [x] Ordinary @due(2026-07-20)

        ## Groceries
        - [x] Bread
        - [x] Butter @due(2026-07-21)
        """
        .write(to: note, atomically: true, encoding: .utf8)
        let manager = makeManager(recorder: ScanRecorder())
        await manager.openVault(at: root)
        XCTAssertEqual(
            manager.index.completedTasks.map(\.text).sorted(),
            ["Butter", "Ordinary"])

        _ = try await manager.clearCompletedTasks()

        let cleared = try String(contentsOf: note, encoding: .utf8)
        XCTAssertFalse(cleared.contains("Ordinary"))
        XCTAssertFalse(cleared.contains("Butter"))
        XCTAssertTrue(cleared.contains("- [x] Bread"))
        XCTAssertTrue(cleared.contains("## Groceries"))
    }

    /// Checking a dated list item off from the Tasks screen has to re-find a
    /// line that lives under a `##` heading, which only works when the
    /// identity carries the list.
    func testTogglingADatedListItemRewritesItsLineInPlace() async throws {
        let note = root.appendingPathComponent("Tasks.md")
        try """
        ## Chores
        - [ ] Laundry @due(2026-07-21)
        - [ ] Milk
        """
        .write(to: note, atomically: true, encoding: .utf8)
        let manager = makeManager(recorder: ScanRecorder())
        await manager.openVault(at: root)
        let laundry = try XCTUnwrap(
            manager.index.incompleteTasks.first { $0.text == "Laundry" })
        XCTAssertEqual(laundry.listName, "Chores")

        _ = try await manager.toggleTask(laundry)

        let toggled = try String(contentsOf: note, encoding: .utf8)
        XCTAssertTrue(toggled.contains("- [x] Laundry @due(2026-07-21)"))
        XCTAssertTrue(toggled.contains("- [ ] Milk"))
    }

    func testListClearUndoRestoresOnlyRemovedItems() async throws {
        let note = root.appendingPathComponent("Tasks.md")
        try """
        ## Groceries
        - [x] Milk
        - [ ] Bread
        """
        .write(to: note, atomically: true, encoding: .utf8)
        let manager = makeManager(recorder: ScanRecorder())
        await manager.openVault(at: root)

        let records = try await manager.clearCompletedTasks(
            inList: "Groceries")
        XCTAssertEqual(records.count, 1)
        var afterClear = try String(contentsOf: note, encoding: .utf8)
        afterClear += "A later note\n"
        try afterClear.write(to: note, atomically: true, encoding: .utf8)

        try await manager.restoreDeletedTasks(records)

        let restored = try String(contentsOf: note, encoding: .utf8)
        XCTAssertTrue(restored.contains("- [x] Milk"))
        XCTAssertTrue(restored.contains("- [ ] Bread"))
        XCTAssertTrue(restored.contains("A later note"))
    }

    func testListDeletionUndoPreservesLaterTasksFileEdits() async throws {
        let note = root.appendingPathComponent("Tasks.md")
        try """
        ## Groceries
        - [ ] Milk

        ## Packing
        - [ ] Charger
        """
        .write(to: note, atomically: true, encoding: .utf8)
        let manager = makeManager(recorder: ScanRecorder())
        await manager.openVault(at: root)

        let record = try await manager.deleteList(named: "Groceries")
        var afterDelete = try String(contentsOf: note, encoding: .utf8)
        afterDelete = afterDelete.replacingOccurrences(
            of: "- [ ] Charger",
            with: "- [ ] Charger\n- [ ] Passport")
        try afterDelete.write(to: note, atomically: true, encoding: .utf8)

        try await manager.restoreDeletedList(record)

        let restored = try String(contentsOf: note, encoding: .utf8)
        XCTAssertTrue(restored.contains("## Groceries\n- [ ] Milk"))
        XCTAssertTrue(restored.contains("- [ ] Charger\n- [ ] Passport"))
    }
}

@MainActor
private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // Expected.
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
