import XCTest

@testable import Cove

/// Editing a task from its details sheet: what reaches the file, what Undo
/// puts back, and what is refused before anything is written.
@MainActor
final class VaultManagerTaskEditTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var widgetRoot: URL!
    private let fileManager = FileManager.default

    override func setUp() async throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "cove-task-edit-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        suiteName = "cove-task-edit-defaults-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        widgetRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "cove-task-edit-widget-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: widgetRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? fileManager.removeItem(at: root)
        try? fileManager.removeItem(at: widgetRoot)
    }

    func testEditingATaskRewritesItsTitleAndSchedule() async throws {
        try write("- [ ] Buy milk @due(2026-07-20)\n", to: "Tasks.md")
        let manager = makeManager()
        await manager.openVault(at: root)
        let task = try XCTUnwrap(manager.index.allTasks.first)

        var draft = TaskDraft(task)
        draft.title = "Buy oat milk"
        draft.dueDateString = "2026-08-01"
        draft.dueTimeString = "09:00"
        let record = try await manager.updateTask(task, to: draft)

        XCTAssertEqual(
            try read("Tasks.md"),
            "- [ ] Buy oat milk @due(2026-08-01 09:00)\n")
        XCTAssertEqual(manager.index.allTasks.first?.text, "Buy oat milk")
        XCTAssertEqual(record?.previousBody, "Buy milk @due(2026-07-20)")
    }

    func testUndoingAnEditRestoresTheLineItReplaced() async throws {
        try write("Intro\n  * [x] Buy milk @due(2026-07-20)\n", to: "Tasks.md")
        let manager = makeManager()
        await manager.openVault(at: root)
        let task = try XCTUnwrap(manager.index.allTasks.first)

        var draft = TaskDraft(task)
        draft.dueDateString = "2026-08-01"
        let edit = try await manager.updateTask(task, to: draft)
        let record = try XCTUnwrap(edit)
        XCTAssertEqual(
            try read("Tasks.md"), "Intro\n  * [x] Buy milk @due(2026-08-01)\n")

        try await manager.undoTaskEdit(record)
        XCTAssertEqual(
            try read("Tasks.md"), "Intro\n  * [x] Buy milk @due(2026-07-20)\n")
    }

    /// `@due` is optional only inside a list section, so an unlisted task
    /// cannot be edited into an undated one — it would stop being a task.
    func testEditingAnUnlistedTaskToUndatedIsRefused() async throws {
        try write("- [ ] Buy milk @due(2026-07-20)\n", to: "Tasks.md")
        let manager = makeManager()
        await manager.openVault(at: root)
        let task = try XCTUnwrap(manager.index.allTasks.first)

        var draft = TaskDraft(task)
        draft.dueDateString = nil
        do {
            _ = try await manager.updateTask(task, to: draft)
            XCTFail("Expected an undated unlisted task to be refused")
        } catch let error as TaskUpdateError {
            XCTAssertEqual(error, .dueDateRequired)
        }
        XCTAssertEqual(
            try read("Tasks.md"), "- [ ] Buy milk @due(2026-07-20)\n")
    }

    func testEditingAListItemMayDropItsDate() async throws {
        try write("## Groceries\n- [ ] Buy milk @due(2026-07-20)\n", to: "Tasks.md")
        let manager = makeManager()
        await manager.openVault(at: root)
        let task = try XCTUnwrap(manager.index.allTasks.first)

        var draft = TaskDraft(task)
        draft.dueDateString = nil
        draft.dueTimeString = nil
        _ = try await manager.updateTask(task, to: draft)

        XCTAssertEqual(try read("Tasks.md"), "## Groceries\n- [ ] Buy milk\n")
        XCTAssertEqual(manager.index.allTasks.first?.listName, "Groceries")
    }

    /// The same refusal every other task mutation makes: after an external
    /// edit leaves two indistinguishable lines, "the first one that looks like
    /// this" is not evidence of which one was tapped.
    func testEditingRefusesWhenTheLineIsAmbiguous() async throws {
        try write("- [ ] Buy milk @due(2026-07-20)\n", to: "Tasks.md")
        let manager = makeManager()
        await manager.openVault(at: root)
        let task = try XCTUnwrap(manager.index.allTasks.first)

        try write(
            """
            - [ ] Buy milk @due(2026-07-20)
            - [ ] Buy milk @due(2026-07-20)

            """, to: "Tasks.md")

        var draft = TaskDraft(task)
        draft.title = "Buy oat milk"
        do {
            _ = try await manager.updateTask(task, to: draft)
            XCTFail("Expected the ambiguous line to be refused")
        } catch let error as TaskParser.MutationError {
            XCTAssertEqual(error, .ambiguousTask([0, 1]))
        }
        XCTAssertFalse(try read("Tasks.md").contains("oat"))
    }

    /// A task another device rescheduled meanwhile is a different task by the
    /// semantic key, so the edit is refused rather than applied to whatever
    /// now sits on that line.
    func testEditingRefusesWhenTheScheduleChangedOnDisk() async throws {
        try write("- [ ] Buy milk @due(2026-07-20)\n", to: "Tasks.md")
        let manager = makeManager()
        await manager.openVault(at: root)
        let task = try XCTUnwrap(manager.index.allTasks.first)

        try write("- [ ] Buy milk @due(2026-09-09)\n", to: "Tasks.md")

        var draft = TaskDraft(task)
        draft.title = "Buy oat milk"
        do {
            _ = try await manager.updateTask(task, to: draft)
            XCTFail("Expected the stale line to be refused")
        } catch let error as TaskParser.MutationError {
            XCTAssertEqual(error, .taskMissing)
        }
        XCTAssertEqual(
            try read("Tasks.md"), "- [ ] Buy milk @due(2026-09-09)\n")
    }

    /// Editing the title of a recurring task leaves its cadence exactly where
    /// it was; moving its date makes the new date the anchor.
    func testEditingKeepsTheAnchorOnlyWhileTheScheduleIsUnchanged() async throws {
        try write(
            "- [ ] Water plants @due(2026-07-20) @repeat(monthly) @anchor(2026-01-31)\n",
            to: "Tasks.md")
        let manager = makeManager()
        await manager.openVault(at: root)
        let task = try XCTUnwrap(manager.index.allTasks.first)

        var draft = TaskDraft(task)
        draft.title = "Water the plants"
        _ = try await manager.updateTask(task, to: draft)
        XCTAssertEqual(
            try read("Tasks.md"),
            "- [ ] Water the plants @due(2026-07-20) @repeat(monthly) @anchor(2026-01-31)\n"
        )

        let renamed = try XCTUnwrap(manager.index.allTasks.first)
        var rescheduled = TaskDraft(renamed)
        rescheduled.dueDateString = "2026-08-15"
        _ = try await manager.updateTask(renamed, to: rescheduled)
        XCTAssertEqual(
            try read("Tasks.md"),
            "- [ ] Water the plants @due(2026-08-15) @repeat(monthly)\n")
    }

    // MARK: - Helpers

    private func write(_ contents: String, to name: String) throws {
        try contents.write(
            to: root.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8)
    }

    private func read(_ name: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(name), encoding: .utf8)
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
