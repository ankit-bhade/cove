import XCTest
@testable import Cove

/// The App Group channel's pure parts: which tasks reach the widget, how a
/// snapshot survives a round trip through JSON, and when a stale one expires.
/// The container I/O itself isn't covered — an App Group container isn't
/// available to the test host — nor is the widget extension, which can't be
/// loaded in-process.
final class WidgetSnapshotTests: XCTestCase {

    private let calendar = Calendar.current

    private func task(
        _ text: String,
        due: String?,
        time: String? = nil,
        recurrence: RecurrenceRule? = nil,
        completed: Bool = false,
        list: String? = nil,
        line: Int = 0,
        file: String = "/vault/Tasks.md"
    ) -> TaskItem {
        TaskItem(
            fileURL: URL(fileURLWithPath: file),
            fileTitle: "Tasks",
            lineNumber: line,
            text: text,
            dueDateString: due,
            dueTimeString: time,
            recurrence: recurrence,
            isCompleted: completed,
            listName: list)
    }

    // MARK: - What reaches the widget

    func testKeepsOnlyTasksDueOnTheGivenDay() {
        let tasks = [
            task("Today", due: "2026-07-19", line: 0),
            task("Tomorrow", due: "2026-07-20", line: 1),
            task("Yesterday", due: "2026-07-18", line: 2),
        ]
        let snapshot = TodaySnapshot.tasks(dueToday: "2026-07-19", from: tasks)
        XCTAssertEqual(snapshot.map(\.text), ["Today"])
    }

    func testExcludesListItems() {
        // List items never appear on the Tasks screen, so they have no place
        // on a widget that mirrors it.
        let tasks = [
            task("Ordinary", due: "2026-07-19", line: 0),
            task("Milk", due: "2026-07-19", list: "Groceries", line: 1),
        ]
        let snapshot = TodaySnapshot.tasks(dueToday: "2026-07-19", from: tasks)
        XCTAssertEqual(snapshot.map(\.text), ["Ordinary"])
    }

    func testExcludesUndatedTasks() {
        let tasks = [
            task("Someday", due: nil, list: "Ideas", line: 0),
            task("Due", due: "2026-07-19", line: 1),
        ]
        let snapshot = TodaySnapshot.tasks(dueToday: "2026-07-19", from: tasks)
        XCTAssertEqual(snapshot.map(\.text), ["Due"])
    }

    func testIncompleteTasksSortAheadOfCompletedOnes() {
        // A row checked off in the widget settles below the work that's left
        // rather than holding its place in the middle of the list.
        let tasks = [
            task(
                "Done early", due: "2026-07-19", time: "08:00",
                completed: true, line: 0),
            task("Still open", due: "2026-07-19", time: "17:00", line: 1),
        ]
        let snapshot = TodaySnapshot.tasks(dueToday: "2026-07-19", from: tasks)
        XCTAssertEqual(snapshot.map(\.text), ["Still open", "Done early"])
    }

    func testOrdersOpenTasksByTimeWithDateOnlyFirst() {
        let tasks = [
            task("Afternoon", due: "2026-07-19", time: "15:00", line: 0),
            task("No time", due: "2026-07-19", line: 1),
            task("Morning", due: "2026-07-19", time: "08:30", line: 2),
        ]
        let snapshot = TodaySnapshot.tasks(dueToday: "2026-07-19", from: tasks)
        XCTAssertEqual(snapshot.map(\.text), ["No time", "Morning", "Afternoon"])
    }

    func testOpenTasksExcludeCompletedOnes() {
        let snapshot = TodaySnapshot(
            dayString: "2026-07-19",
            generatedAt: Date(),
            tasks: TodaySnapshot.tasks(
                dueToday: "2026-07-19",
                from: [
                    task("Open", due: "2026-07-19", line: 0),
                    task("Closed", due: "2026-07-19", completed: true, line: 1),
                ]))
        XCTAssertEqual(snapshot.tasks.count, 2)
        XCTAssertEqual(snapshot.openTasks.map(\.text), ["Open"])
    }

    // MARK: - Staleness

    func testSnapshotFromAnotherDayReadsAsEmpty() {
        // Otherwise a widget that hasn't been refreshed since yesterday would
        // present yesterday's list as today's.
        let yesterday = TodaySnapshot(
            dayString: "2026-07-18",
            generatedAt: Date(),
            tasks: TodaySnapshot.tasks(
                dueToday: "2026-07-18",
                from: [task("Old", due: "2026-07-18")]))
        let now = calendar.date(
            from: DateComponents(
                year: 2026, month: 7, day: 19,
                hour: 9))!
        XCTAssertTrue(yesterday.valid(at: now).tasks.isEmpty)
    }

    func testSnapshotFromTheSameDaySurvives() {
        let now = calendar.date(
            from: DateComponents(
                year: 2026, month: 7, day: 19,
                hour: 9))!
        let snapshot = TodaySnapshot.building(
            for: now, from: [task("Keep me", due: "2026-07-19")])
        XCTAssertEqual(snapshot.valid(at: now).tasks.map(\.text), ["Keep me"])
    }

    // MARK: - Round trips

    func testSnapshotTaskSurvivesJSON() throws {
        let original = SnapshotTask(
            task(
                "Water the plants",
                due: "2026-07-19",
                time: "17:30",
                recurrence: RecurrenceRule(
                    frequency: .weekly,
                    interval: 2),
                line: 4))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SnapshotTask.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.recurrence, RecurrenceRule(frequency: .weekly, interval: 2))
    }

    func testSnapshotTaskConvertsBackToATaskItem() {
        // The widget reuses the app's own display logic, so the round trip
        // has to preserve everything that logic reads.
        let item = task("Reply to Maya", due: "2026-07-19", time: "08:30", line: 3)
        let restored = SnapshotTask(item).taskItem
        XCTAssertEqual(restored.text, item.text)
        XCTAssertEqual(restored.dueDateString, item.dueDateString)
        XCTAssertEqual(restored.dueTimeString, item.dueTimeString)
        XCTAssertEqual(restored.lineNumber, item.lineNumber)
        XCTAssertEqual(restored.fileURL.path, item.fileURL.path)
        XCTAssertEqual(restored.id, item.id)
    }

    func testToggledFlipsOnlyCompletion() {
        let original = SnapshotTask(task("Task", due: "2026-07-19", time: "09:00"))
        let toggled = original.toggled()
        XCTAssertTrue(toggled.isCompleted)
        XCTAssertEqual(toggled.id, original.id)
        XCTAssertEqual(toggled.text, original.text)
        XCTAssertEqual(toggled.toggled(), original)
    }

    func testPendingTogglePreservesThePreTapState() {
        // The app matches on the state the line had before the tap; recording
        // the post-tap state would make every re-find miss.
        let completed = SnapshotTask(task("Task", due: "2026-07-19", completed: true))
        XCTAssertTrue(PendingToggle(completed).wasCompleted)
        XCTAssertFalse(PendingToggle(completed.toggled()).wasCompleted)
    }

    func testPendingToggleSurvivesJSON() throws {
        let toggle = PendingToggle(
            SnapshotTask(
                task(
                    "Standup", due: "2026-07-19", time: "09:30",
                    recurrence: .everyWeekday)))
        let data = try JSONEncoder().encode([toggle])
        let decoded = try JSONDecoder().decode([PendingToggle].self, from: data)
        XCTAssertEqual(decoded, [toggle])
        XCTAssertEqual(decoded.first?.recurrence, .everyWeekday)
    }

    func testPendingDesiredStateOperationSurvivesJSON() throws {
        let snapshotTask = SnapshotTask(
            task(
                "Standup", due: "2026-07-19",
                time: "09:30", line: 4))
        let operation = PendingTaskOperation(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            taskIdentity: snapshotTask.identity,
            desiredCompletion: true,
            createdAt: Date(timeIntervalSince1970: 123),
            attemptCount: 2)

        let decoded = try JSONDecoder().decode(
            PendingTaskOperation.self,
            from: JSONEncoder().encode(operation))

        XCTAssertEqual(decoded, operation)
        XCTAssertTrue(decoded.desiredCompletion)
    }

    func testConcurrentQueueAppendsDoNotLoseOperations() async throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstStore = WidgetSnapshotStore(containerURL: root)
        let secondStore = WidgetSnapshotStore(containerURL: root)
        let first = PendingTaskOperation(
            task: SnapshotTask(
                task("First", due: "2026-07-19", line: 1)), desiredCompletion: true)
        let second = PendingTaskOperation(
            task: SnapshotTask(
                task("Second", due: "2026-07-19", line: 2)), desiredCompletion: true)

        async let appendFirst: Void = Task.detached { try firstStore.append(first) }.value
        async let appendSecond: Void = Task.detached { try secondStore.append(second) }.value
        _ = try await (appendFirst, appendSecond)

        XCTAssertEqual(
            Set(try firstStore.loadPendingOperations().map(\.id)),
            Set([first.id, second.id]))
    }

    func testQueueAcknowledgesOnlySuccessfulOperation() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(containerURL: root)
        let first = PendingTaskOperation(
            task: SnapshotTask(
                task("First", due: "2026-07-19", line: 1)), desiredCompletion: true)
        let second = PendingTaskOperation(
            task: SnapshotTask(
                task("Second", due: "2026-07-19", line: 2)), desiredCompletion: true)
        try store.append(first)
        try store.append(second)

        try store.acknowledge(operationID: first.id)

        XCTAssertEqual(try store.loadPendingOperations(), [second])
    }

    func testMalformedQueueIsNotSilentlyReplaced() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let queueURL = root.appendingPathComponent("pending-task-operations-v2.json")
        let malformed = Data("not json".utf8)
        try malformed.write(to: queueURL)
        let store = WidgetSnapshotStore(containerURL: root)

        XCTAssertThrowsError(try store.loadPendingOperations())
        XCTAssertEqual(try Data(contentsOf: queueURL), malformed)
    }

    func testFailedAttemptsAreCountedAgainstTheOperation() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(containerURL: root)
        let operation = PendingTaskOperation(
            task: SnapshotTask(
                task("Stuck", due: "2026-07-19", line: 1)), desiredCompletion: true)
        try store.append(operation)

        XCTAssertFalse(try store.recordFailure(operationID: operation.id, maxAttempts: 3))
        XCTAssertFalse(try store.recordFailure(operationID: operation.id, maxAttempts: 3))

        XCTAssertEqual(try store.loadPendingOperations().map(\.attemptCount), [2])
    }

    func testOperationIsDroppedOnceItExhaustsItsAttempts() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(containerURL: root)
        let stuck = PendingTaskOperation(
            task: SnapshotTask(
                task("Stuck", due: "2026-07-19", line: 1)), desiredCompletion: true)
        let healthy = PendingTaskOperation(
            task: SnapshotTask(
                task("Healthy", due: "2026-07-19", line: 2)), desiredCompletion: true)
        try store.append(stuck)
        try store.append(healthy)

        try store.recordFailure(operationID: stuck.id, maxAttempts: 2)
        let dropped = try store.recordFailure(operationID: stuck.id, maxAttempts: 2)

        XCTAssertTrue(dropped)
        XCTAssertEqual(try store.loadPendingOperations().map(\.id), [healthy.id])
    }

    func testRecordingFailureForAnUnknownOperationLeavesTheQueueAlone() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(containerURL: root)
        let operation = PendingTaskOperation(
            task: SnapshotTask(
                task("Queued", due: "2026-07-19", line: 1)), desiredCompletion: true)
        try store.append(operation)

        XCTAssertFalse(try store.recordFailure(operationID: UUID()))

        XCTAssertEqual(try store.loadPendingOperations(), [operation])
    }

    func testLegacyQueueIsPersistedUnderStableIdentifiersOnMigration() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyURL = root.appendingPathComponent("pending-toggles.json")
        let legacy = [
            PendingToggle(SnapshotTask(task("First", due: "2026-07-19", line: 1))),
            PendingToggle(SnapshotTask(task("Second", due: "2026-07-19", line: 2))),
        ]
        try JSONEncoder().encode(legacy).write(to: legacyURL)
        let store = WidgetSnapshotStore(containerURL: root)

        let migrated = try store.loadPendingOperations()
        // Acknowledging one must not take the other down with it: before the
        // migration was persisted, the first acknowledgment wrote an empty v2
        // file that then shadowed the legacy one forever.
        try store.acknowledge(operationID: try XCTUnwrap(migrated.first).id)

        XCTAssertEqual(migrated.count, 2)
        XCTAssertEqual(
            try store.loadPendingOperations().map(\.id),
            [try XCTUnwrap(migrated.last).id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    func testMigratedOperationsKeepTheirIdentifiersAcrossReads() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyURL = root.appendingPathComponent("pending-toggles.json")
        let legacy = [PendingToggle(SnapshotTask(task("Only", due: "2026-07-19", line: 1)))]
        try JSONEncoder().encode(legacy).write(to: legacyURL)
        let store = WidgetSnapshotStore(containerURL: root)

        let first = try store.loadPendingOperations()
        let second = try store.loadPendingOperations()

        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    private func temporaryContainer() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "cove-widget-store-\(UUID().uuidString)",
                isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
