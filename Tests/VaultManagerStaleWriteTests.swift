import XCTest

@testable import Cove

/// What happens when the file moved between the index being built and the
/// write going out — the two-device case, and the reason completion and status
/// are outside the semantic keys that re-find a line.
///
/// The index is deliberately left stale in each test by writing to the note
/// directly: that is exactly the state another device's edit leaves this one
/// in until the next rebuild.
@MainActor
final class VaultManagerStaleWriteTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var widgetRoot: URL!
    private let fileManager = FileManager.default

    override func setUp() async throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "cove-stale-write-tests-\(UUID().uuidString)",
                isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        suiteName = "cove-stale-write-defaults-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        widgetRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "cove-stale-write-widget-\(UUID().uuidString)",
                isDirectory: true)
        try fileManager.createDirectory(
            at: widgetRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: root)
        try? fileManager.removeItem(at: widgetRoot)
    }

    // MARK: - Tasks

    func testTogglingATaskAlreadyCompletedOnDiskRegistersNoUndo() async throws {
        try write("- [ ] Buy milk @due(2026-07-20)\n", to: "Tasks.md")
        let manager = makeManager()
        await manager.openVault(at: root)
        let task = try XCTUnwrap(manager.index.allTasks.first)

        // Another device ticks the same checkbox.
        try write("- [x] Buy milk @due(2026-07-20)\n", to: "Tasks.md")

        let record = try await manager.toggleTask(task)
        XCTAssertNil(record)
        XCTAssertEqual(manager.index.allTasks.first?.isCompleted, true)
    }

    func testTogglingATaskThatIsStillOpenReturnsItsUndoRecord() async throws {
        try write("- [ ] Buy milk @due(2026-07-20)\n", to: "Tasks.md")
        let manager = makeManager()
        await manager.openVault(at: root)
        let task = try XCTUnwrap(manager.index.allTasks.first)

        let record = try await manager.toggleTask(task)
        XCTAssertEqual(record?.previousCompletion, false)
        XCTAssertEqual(manager.index.allTasks.first?.isCompleted, true)
    }

    func testDeletingATaskRestoresTheLineTheWriteActuallyRemoved() async throws {
        try write("- [ ] Buy milk @due(2026-07-20)\n", to: "Tasks.md")
        let manager = makeManager()
        await manager.openVault(at: root)
        let task = try XCTUnwrap(manager.index.allTasks.first)

        // Completed elsewhere after the index was built. The delete still
        // finds the line — completion is outside the semantic key — so what
        // Undo puts back has to be the completed version.
        try write("* [x] Buy milk @due(2026-07-20)\n", to: "Tasks.md")

        let record = try await manager.deleteTask(task)
        XCTAssertEqual(record.originalLine, "* [x] Buy milk @due(2026-07-20)\n")

        try await manager.restoreDeletedTask(record)
        XCTAssertEqual(
            try read("Tasks.md"), "* [x] Buy milk @due(2026-07-20)\n")
    }

    // MARK: - Subscriptions

    func testEditingASubscriptionRefusesWhenItsStatusChangedOnDisk() async throws {
        try writeSubscriptions(
            "- Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)\n")
        let manager = makeManager()
        await manager.openVault(at: root)
        let subscription = try XCTUnwrap(manager.index.subscriptions.first)

        // Cancelled on another device while the sheet was open.
        try writeSubscriptions(
            "- Netflix @cost(15.49 USD) @every(month) @since(2024-03-04) @status(cancelled)\n"
        )

        var draft = SubscriptionDraft(subscription)
        draft.amount = Decimal(string: "17.99")!
        do {
            try await manager.updateSubscription(
                subscription, to: draft, category: nil)
            XCTFail("Expected the stale status to be refused")
        } catch let error as SubscriptionParser.MutationError {
            XCTAssertEqual(error, .statusChangedOnDisk(.cancelled))
        }
        XCTAssertTrue(try readSubscriptions().contains("@status(cancelled)"))
        XCTAssertTrue(try readSubscriptions().contains("15.49"))
    }

    /// Writing the status the file already holds is the idempotent replay the
    /// exclusion from the semantic key exists for, so it is not refused.
    func testEditingASubscriptionIntoTheStatusItAlreadyHasIsAllowed() async throws {
        try writeSubscriptions(
            "- Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)\n")
        let manager = makeManager()
        await manager.openVault(at: root)
        let subscription = try XCTUnwrap(manager.index.subscriptions.first)

        try writeSubscriptions(
            "- Netflix @cost(15.49 USD) @every(month) @since(2024-03-04) @status(paused)\n"
        )

        var draft = SubscriptionDraft(subscription)
        draft.status = .paused
        draft.amount = Decimal(string: "17.99")!
        try await manager.updateSubscription(
            subscription, to: draft, category: nil)

        let text = try readSubscriptions()
        XCTAssertTrue(text.contains("17.99"))
        XCTAssertTrue(text.contains("@status(paused)"))
    }

    func testDeletingASubscriptionRestoresTheLineTheWriteActuallyRemoved()
        async throws
    {
        try writeSubscriptions(
            "- Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)\n")
        let manager = makeManager()
        await manager.openVault(at: root)
        let subscription = try XCTUnwrap(manager.index.subscriptions.first)

        try writeSubscriptions(
            "- Netflix @cost(15.49 USD) @every(month) @since(2024-03-04) @status(paused)\n"
        )

        let record = try await manager.deleteSubscription(subscription)
        XCTAssertTrue(record.originalLine.contains("@status(paused)"))
        XCTAssertEqual(try readSubscriptions().trimmingCharacters(in: .whitespacesAndNewlines), "")

        try await manager.restoreDeletedSubscription(record)
        XCTAssertTrue(try readSubscriptions().contains("@status(paused)"))
    }

    // MARK: - Helpers

    private func write(_ text: String, to name: String) throws {
        try text.write(
            to: root.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8)
    }

    private func read(_ name: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }

    private var subscriptionNoteURL: URL {
        root
            .appendingPathComponent("Trackers", isDirectory: true)
            .appendingPathComponent("Subscriptions.md")
    }

    private func writeSubscriptions(_ text: String) throws {
        try fileManager.createDirectory(
            at: subscriptionNoteURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try text.write(to: subscriptionNoteURL, atomically: true, encoding: .utf8)
    }

    private func readSubscriptions() throws -> String {
        try String(contentsOf: subscriptionNoteURL, encoding: .utf8)
    }

    private func makeManager() -> VaultManager {
        VaultManager(
            bookmarkStore: VaultBookmarkStore(
                defaults: defaults,
                creationOptions: [],
                resolutionOptions: []),
            loadOperation: { url, previousIndex, changedURLs, existingTree in
                let node = try existingTree ?? VaultTreeScanner().scanTree(at: url)
                let index = try VaultIndexBuilder().buildCancellableIndex(
                    from: node, previous: previousIndex, changedURLs: changedURLs)
                return (node, index)
            },
            notificationRebuild: { _ in .superseded() },
            notificationCancel: { .superseded() },
            widgetStore: WidgetSnapshotStore(containerURL: widgetRoot),
            reloadWidgetTimelines: {})
    }
}
