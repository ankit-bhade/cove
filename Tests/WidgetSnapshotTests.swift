import XCTest
@testable import Cove

/// The App Group channel's pure parts and its coordinated file store. Tests
/// use a temporary container; the signed App Group entitlement and widget
/// extension lifecycle still require device coverage.
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

    func testBuiltSnapshotIsCappedButPreservesFullCounts() {
        let tasks = (0..<(TodaySnapshot.maximumStoredTasks + 8)).map { line in
            task(
                "Task \(line)",
                due: "2026-07-19",
                line: line)
        }

        let now = calendar.date(
            from: DateComponents(
                year: 2026, month: 7, day: 19, hour: 9))!
        let snapshot = TodaySnapshot.building(for: now, from: tasks)

        XCTAssertEqual(snapshot.tasks.count, TodaySnapshot.maximumStoredTasks)
        XCTAssertEqual(snapshot.totalTaskCount, tasks.count)
        XCTAssertEqual(snapshot.totalOpenTaskCount, tasks.count)
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
        let valid = yesterday.valid(at: now)
        XCTAssertTrue(valid.tasks.isEmpty)
        XCTAssertEqual(valid.availability, .stale)
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

    func testUnavailableSnapshotDoesNotTurnIntoAllClearAtMidnight() {
        let unavailable = TodaySnapshot.unavailable(
            .vaultUnavailable,
            at: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(
            unavailable.valid(at: Date(timeIntervalSince1970: 10_000_000)).availability,
            .vaultUnavailable)
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

    func testSnapshotTaskRoundTripPreservesAnchorAndSectionedIdentity() throws {
        let original = SnapshotTask(
            filePath: "/vault/tasks.md",
            lineNumber: 7,
            text: "Billing",
            dueDateString: "2026-02-28",
            dueTimeString: "09:30",
            recurrenceTag: "monthly",
            isCompleted: false,
            recurrenceAnchorDateString: "2026-01-30",
            isSectionedDocument: true)

        let decoded = try JSONDecoder().decode(
            SnapshotTask.self,
            from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(
            decoded.identity.recurrenceAnchorDateString,
            "2026-01-30")
        XCTAssertTrue(decoded.identity.isSectionedDocument)
        XCTAssertEqual(
            decoded.taskItem.recurrenceAnchorDateString,
            "2026-01-30")
        XCTAssertTrue(decoded.taskItem.isSectionedDocument)
    }

    func testLegacySnapshotTaskDefaultsNewIdentityFields() throws {
        let legacy = Data(
            """
            {
              "filePath": "/vault/tasks.md",
              "lineNumber": 2,
              "text": "Legacy",
              "dueDateString": "2026-07-19",
              "recurrenceTag": "daily",
              "isCompleted": false
            }
            """.utf8)

        let decoded = try JSONDecoder().decode(
            SnapshotTask.self,
            from: legacy)

        XCTAssertNil(decoded.recurrenceAnchorDateString)
        XCTAssertFalse(decoded.isSectionedDocument)
        XCTAssertNil(decoded.identity.recurrenceAnchorDateString)
        XCTAssertFalse(decoded.identity.isSectionedDocument)
    }

    func testLegacySnapshotWithoutSchemaMigratesWithDefaults() throws {
        let legacy = LegacyTodaySnapshot(
            dayString: "2026-07-19",
            generatedAt: Date(timeIntervalSince1970: 123),
            tasks: [SnapshotTask(task("Legacy", due: "2026-07-19"))])

        let decoded = try JSONDecoder().decode(
            TodaySnapshot.self,
            from: JSONEncoder().encode(legacy))

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.revision, 0)
        XCTAssertEqual(decoded.availability, .available)
        XCTAssertEqual(decoded.totalOpenTaskCount, 1)
    }

    func testSnapshotTaskConvertsBackToATaskItem() {
        // The widget reuses the app's own display logic, so the round trip
        // has to preserve everything that logic reads.
        let item = task("Reply to Maya", due: "2026-07-19", time: "08:30", line: 3)
        let snapshotTask = SnapshotTask(item)
        let restored = snapshotTask.taskItem
        XCTAssertEqual(restored.text, item.text)
        XCTAssertEqual(restored.dueDateString, item.dueDateString)
        XCTAssertEqual(restored.dueTimeString, item.dueTimeString)
        XCTAssertEqual(restored.lineNumber, item.lineNumber)
        XCTAssertEqual(restored.fileURL.path, item.fileURL.path)
        // In-app identity is unchanged by the round trip; it is the *widget*
        // id that must never carry a vault path, because an App Intent
        // parameter can be persisted by the system.
        XCTAssertEqual(restored.id, item.id)
        XCTAssertTrue(snapshotTask.id.hasPrefix("cove-widget:"))
        XCTAssertFalse(snapshotTask.id.contains(item.fileURL.path))
        XCTAssertEqual(
            snapshotTask.notificationIdentifier,
            CoveTaskNotificationIdentifier.identifier(forTaskID: item.id))
    }

    func testSettingCompletedChangesOnlyCompletion() {
        let original = SnapshotTask(task("Task", due: "2026-07-19", time: "09:00"))
        let completed = original.settingCompleted(true)
        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(completed.id, original.id)
        XCTAssertEqual(completed.text, original.text)
        XCTAssertEqual(completed.settingCompleted(false), original)
        // Desired state, not a flip: applying it twice is the same as once.
        XCTAssertEqual(completed.settingCompleted(true), completed)
    }

    func testDeferredCompletionRemainsAuthoritativelyOpenAndShowsPending() throws {
        var snapshot = TodaySnapshot(
            dayString: "2026-07-19",
            generatedAt: Date(),
            tasks: [
                SnapshotTask(task("First", due: "2026-07-19", line: 1)),
                SnapshotTask(task("Second", due: "2026-07-19", line: 2)),
            ])
        let firstID = try XCTUnwrap(snapshot.tasks.first?.id)

        try snapshot.applyOptimisticCompletion(
            taskID: firstID,
            desiredCompletion: true,
            operationID: UUID(),
            outcome: .deferred,
            at: Date())

        let pending = try XCTUnwrap(snapshot.tasks.first { $0.id == firstID })
        XCTAssertFalse(pending.isCompleted)
        XCTAssertEqual(pending.pendingCompletion, true)
        XCTAssertEqual(snapshot.totalOpenTaskCount, 2)
        XCTAssertEqual(snapshot.optimisticMutations.count, 1)
    }

    func testConfirmedCompletionResortsBelowOpenWork() throws {
        var snapshot = TodaySnapshot(
            dayString: "2026-07-19",
            generatedAt: Date(),
            tasks: [
                SnapshotTask(task("First", due: "2026-07-19", line: 1)),
                SnapshotTask(task("Second", due: "2026-07-19", line: 2)),
            ])
        let firstID = try XCTUnwrap(snapshot.tasks.first?.id)

        try snapshot.applyOptimisticCompletion(
            taskID: firstID,
            desiredCompletion: true,
            operationID: UUID(),
            outcome: .changed,
            at: Date())

        XCTAssertEqual(snapshot.tasks.map(\.text), ["Second", "First"])
        XCTAssertTrue(try XCTUnwrap(snapshot.tasks.last).isCompleted)
        XCTAssertEqual(snapshot.totalOpenTaskCount, 1)
    }

    func testAuthoritativePublishMergesThenRetiresOptimisticState() throws {
        let originalTasks = [
            SnapshotTask(task("First", due: "2026-07-19", line: 1)),
            SnapshotTask(task("Second", due: "2026-07-19", line: 2)),
        ]
        var previous = TodaySnapshot(
            dayString: "2026-07-19",
            generatedAt: Date(),
            tasks: originalTasks)
        let taskID = try XCTUnwrap(previous.tasks.first?.id)
        try previous.applyOptimisticCompletion(
            taskID: taskID,
            desiredCompletion: true,
            operationID: UUID(),
            outcome: .changed,
            at: Date())

        let stalePublish = TodaySnapshot(
            dayString: "2026-07-19",
            generatedAt: Date(),
            tasks: originalTasks
        )
        .mergingOptimisticMutations(from: previous, at: Date())
        XCTAssertTrue(
            try XCTUnwrap(stalePublish.tasks.first { $0.id == taskID }).isCompleted)
        XCTAssertEqual(stalePublish.optimisticMutations.count, 1)

        let freshTasks = originalTasks.map {
            $0.id == taskID ? $0.settingCompleted(true) : $0
        }
        let freshPublish = TodaySnapshot(
            dayString: "2026-07-19",
            generatedAt: Date(),
            tasks: freshTasks
        )
        .mergingOptimisticMutations(from: stalePublish, at: Date())
        XCTAssertTrue(freshPublish.optimisticMutations.isEmpty)
    }

    func testPendingTogglePreservesThePreTapState() {
        // The app matches on the state the line had before the tap; recording
        // the post-tap state would make every re-find miss.
        let completed = SnapshotTask(task("Task", due: "2026-07-19", completed: true))
        XCTAssertTrue(PendingToggle(completed).wasCompleted)
        XCTAssertFalse(PendingToggle(completed.settingCompleted(false)).wasCompleted)
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

    func testConcurrentSnapshotTransformsDoNotLoseOptimisticChanges() async throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(containerURL: root)
        let snapshot = TodaySnapshot(
            dayString: "2026-07-19",
            generatedAt: Date(),
            tasks: [
                SnapshotTask(task("First", due: "2026-07-19", line: 1)),
                SnapshotTask(task("Second", due: "2026-07-19", line: 2)),
            ])
        _ = try store.writeSnapshot(snapshot).get()
        let ids = snapshot.tasks.map(\.id)

        async let first: TodaySnapshot = Task.detached {
            try store.applyOptimisticCompletion(
                taskID: ids[0],
                desiredCompletion: true,
                operationID: UUID(),
                outcome: .deferred,
                at: Date())
        }.value
        async let second: TodaySnapshot = Task.detached {
            try store.applyOptimisticCompletion(
                taskID: ids[1],
                desiredCompletion: true,
                operationID: UUID(),
                outcome: .deferred,
                at: Date())
        }.value
        _ = try await (first, second)

        let final = try store.readSnapshotResult().get()
        XCTAssertTrue(final.tasks.allSatisfy { !$0.isCompleted })
        XCTAssertTrue(final.tasks.allSatisfy { $0.pendingCompletion == true })
        XCTAssertEqual(final.optimisticMutations.count, 2)
        XCTAssertEqual(final.revision, 3)
    }

    func testRepeatedDesiredStateOperationsCoalesce() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(containerURL: root)
        let snapshotTask = SnapshotTask(
            task("Same", due: "2026-07-19", line: 1))
        let first = PendingTaskOperation(
            task: snapshotTask,
            desiredCompletion: true)
        let duplicate = PendingTaskOperation(
            task: snapshotTask,
            desiredCompletion: true)

        let durableFirst = try store.append(first)
        let durableDuplicate = try store.append(duplicate)

        XCTAssertEqual(durableDuplicate.id, durableFirst.id)
        XCTAssertEqual(try store.loadPendingOperations().count, 1)
    }

    func testLatestOppositeDesiredStateReplacesOlderOperation() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(containerURL: root)
        let snapshotTask = SnapshotTask(
            task("Same", due: "2026-07-19", line: 1))
        try store.append(
            PendingTaskOperation(task: snapshotTask, desiredCompletion: true))
        let latest = try store.append(
            PendingTaskOperation(task: snapshotTask, desiredCompletion: false))

        XCTAssertEqual(try store.loadPendingOperations(), [latest])
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
        let receipt = try XCTUnwrap(store.loadFailureReceipts().first)
        XCTAssertEqual(receipt.operationID, stuck.id)
        XCTAssertFalse(receipt.taskFingerprint.contains("/vault/"))
        XCTAssertEqual(receipt.reason, .retryLimitExceeded)
    }

    func testBatchQueueResolutionUsesOneResultAndKeepsFailureReceipt() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(containerURL: root)
        let first = PendingTaskOperation(
            task: SnapshotTask(task("First", due: "2026-07-19", line: 1)),
            desiredCompletion: true)
        let second = PendingTaskOperation(
            task: SnapshotTask(task("Second", due: "2026-07-19", line: 2)),
            desiredCompletion: true)
        try store.enqueue([first, second])

        let result = try store.applyQueueResolutions(
            [
                .acknowledge(first.id),
                .recordFailure(second.id, .retryLimitExceeded),
            ],
            maxAttempts: 1)

        XCTAssertEqual(result.acknowledgedCount, 1)
        XCTAssertEqual(result.failedPermanentlyCount, 1)
        XCTAssertEqual(result.pendingCount, 0)
        XCTAssertEqual(try store.loadFailureReceipts().count, 1)
        XCTAssertEqual(store.health().state, .needsAttention)
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

    func testUnavailableSnapshotIsDurablyPublished() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(containerURL: root)

        _ = try store.writeUnavailableSnapshot(
            .vaultUnavailable,
            at: Date(timeIntervalSince1970: 123)
        ).get()

        XCTAssertEqual(
            try store.readSnapshotResult().get().availability,
            .vaultUnavailable)
    }

    func testMissingAppGroupReturnsTypedHealthAndSnapshotState() {
        let store = WidgetSnapshotStore(containerURL: nil)

        guard case .failure(let error) = store.readSnapshotResult() else {
            return XCTFail("Expected a typed App Group failure")
        }
        XCTAssertEqual(error, .appGroupUnavailable)
        XCTAssertEqual(store.health().state, .unavailable)
        XCTAssertEqual(store.readSnapshot().availability, .sharedContainerUnavailable)
    }

    func testFutureSnapshotSchemaIsRejectedWithoutReplacement() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshotURL = root.appendingPathComponent("today.json")
        let future = Data(
            """
            {"schemaVersion":999,"revision":0,"dayString":"2026-07-19","generatedAt":0,"availability":"available","tasks":[],"totalTaskCount":0,"totalOpenTaskCount":0,"optimisticMutations":[]}
            """.utf8)
        try future.write(to: snapshotURL)
        let store = WidgetSnapshotStore(containerURL: root)

        guard case .failure(let error) = store.readSnapshotResult() else {
            return XCTFail("Expected a future-schema failure")
        }
        XCTAssertEqual(
            error,
            .unsupportedSchema(
                artifact: .snapshot,
                found: 999,
                supported: TodaySnapshot.currentSchemaVersion))
        XCTAssertEqual(try Data(contentsOf: snapshotURL), future)
    }

    func testZeroSnapshotSchemaIsRejected() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshotURL = root.appendingPathComponent("today.json")
        try Data(
            """
            {"schemaVersion":0,"revision":0,"dayString":"2026-07-19","generatedAt":0,"availability":"available","tasks":[],"totalTaskCount":0,"totalOpenTaskCount":0,"optimisticMutations":[]}
            """.utf8
        ).write(to: snapshotURL)

        guard
            case .failure(let error) =
                WidgetSnapshotStore(containerURL: root).readSnapshotResult()
        else { return XCTFail("Expected an invalid-schema failure") }
        XCTAssertEqual(
            error,
            .unsupportedSchema(
                artifact: .snapshot,
                found: 0,
                supported: TodaySnapshot.currentSchemaVersion))
    }

    func testPendingQueueRejectsNewDistinctWorkAtCapacityWithoutDroppingOldWork() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(containerURL: root)
        let operations = (0..<WidgetSnapshotStore.maximumPendingOperations).map { line in
            PendingTaskOperation(
                task: SnapshotTask(
                    task("Task \(line)", due: "2026-07-19", line: line)),
                desiredCompletion: true)
        }
        try store.enqueue(operations)
        let overflow = PendingTaskOperation(
            task: SnapshotTask(
                task("Overflow", due: "2026-07-19", line: operations.count)),
            desiredCompletion: true)

        XCTAssertThrowsError(try store.append(overflow)) { error in
            XCTAssertEqual(
                error as? WidgetStoreError,
                .queueCapacityReached(
                    limit: WidgetSnapshotStore.maximumPendingOperations))
        }
        XCTAssertEqual(
            try store.loadPendingOperations().map(\.id),
            operations.map(\.id))
        XCTAssertTrue(store.health().pendingQueueAtCapacity)
    }

    func testFailureReceiptsKeepNewestBoundedHistoryAndReportCompaction() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(containerURL: root)
        let count = WidgetSnapshotStore.maximumFailureReceipts + 2
        let operations = (0..<count).map { line in
            PendingTaskOperation(
                task: SnapshotTask(
                    task("Failure \(line)", due: "2026-07-19", line: line)),
                desiredCompletion: true)
        }
        try store.enqueue(operations)

        _ = try store.applyQueueResolutions(
            operations.enumerated().map { _, operation in
                .recordFailure(operation.id, .retryLimitExceeded)
            },
            maxAttempts: 1,
            now: Date(timeIntervalSince1970: 123))

        XCTAssertEqual(
            try store.loadFailureReceipts().count,
            WidgetSnapshotStore.maximumFailureReceipts)
        let health = store.health()
        XCTAssertEqual(health.discardedFailureReceiptCount, 2)
        XCTAssertEqual(health.state, .needsAttention)
    }

    func testZeroQueueSchemaIsRejectedWithoutReplacingIt() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let queueURL = root.appendingPathComponent(
            "pending-task-operations-v2.json")
        let invalid = Data(
            """
            {"schemaVersion":0,"operations":[],"failureReceipts":[]}
            """.utf8)
        try invalid.write(to: queueURL)
        let store = WidgetSnapshotStore(containerURL: root)

        XCTAssertThrowsError(try store.loadPendingOperations()) { error in
            XCTAssertEqual(
                error as? WidgetStoreError,
                .unsupportedSchema(
                    artifact: .operationQueue,
                    found: 0,
                    supported: 4))
        }
        XCTAssertEqual(try Data(contentsOf: queueURL), invalid)
    }

    func testUnavailableSnapshotHealthIsNotReady() throws {
        let root = try temporaryContainer()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = WidgetSnapshotStore(containerURL: root)
        _ = try store.writeUnavailableSnapshot(.vaultUnavailable).get()

        XCTAssertEqual(store.health().state, .needsAttention)
        XCTAssertEqual(
            store.health().snapshotAvailability,
            .vaultUnavailable)
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

private struct LegacyTodaySnapshot: Codable {
    let dayString: String
    let generatedAt: Date
    let tasks: [SnapshotTask]
}
