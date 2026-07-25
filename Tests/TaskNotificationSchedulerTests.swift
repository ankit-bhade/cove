import XCTest
@testable import Cove

final class TaskNotificationSchedulerTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func task(
        _ text: String,
        due: String,
        time: String,
        line: Int = 0
    ) -> TaskItem {
        TaskItem(
            fileURL: URL(fileURLWithPath: "/vault/Tasks.md"),
            fileTitle: "Tasks",
            lineNumber: line,
            text: text,
            dueDateString: due,
            dueTimeString: time,
            recurrence: nil,
            isCompleted: false,
            listName: nil)
    }

    private var now: Date {
        TaskCalendar.gregorian(timeZone: utc).date(
            from: DateComponents(
                year: 2026, month: 7, day: 1, hour: 9))!
    }

    func testAuthorizedReconciliationAddsAndThenRetainsMatchingRequest() async {
        let center = MockTaskNotificationCenter(permission: .authorized)
        let scheduler = TaskNotificationScheduler(center: center)
        let tasks = [task("Lunch", due: "2026-07-02", time: "12:00")]

        let first = await scheduler.rebuildNotifications(
            for: tasks, now: now, timeZone: utc)
        let second = await scheduler.rebuildNotifications(
            for: tasks, now: now, timeZone: utc)

        XCTAssertEqual(first.state, .reconciled)
        XCTAssertEqual(first.addedCount, 1)
        XCTAssertEqual(second.addedCount, 0)
        XCTAssertEqual(second.unchangedCount, 1)
        let identifiers = await center.coveIdentifiers()
        XCTAssertEqual(identifiers.count, 1)
    }

    func testDeniedReconciliationStillRemovesStaleCoveRequests() async {
        let center = MockTaskNotificationCenter(permission: .denied)
        await center.seed(identifier: TaskNotificationPlanner.identifierPrefix + "old")
        await center.seed(identifier: "another-feature")
        let scheduler = TaskNotificationScheduler(center: center)

        let health = await scheduler.rebuildNotifications(
            for: [], now: now, timeZone: utc)

        XCTAssertEqual(health.state, .permissionDenied)
        XCTAssertEqual(health.removedCount, 1)
        let identifiers = await center.identifiers()
        XCTAssertEqual(identifiers, ["another-feature"])
    }

    func testUnknownPermissionIsNotReportedAsDenied() async {
        let center = MockTaskNotificationCenter(permission: .unknown)
        let scheduler = TaskNotificationScheduler(center: center)

        let health = await scheduler.rebuildNotifications(
            for: [], now: now, timeZone: utc)

        XCTAssertEqual(health.state, .permissionUnknown)
    }

    func testSchedulingFailureIsTypedAndVisibleInHealth() async {
        let center = MockTaskNotificationCenter(
            permission: .authorized,
            failAdds: true)
        let scheduler = TaskNotificationScheduler(center: center)

        let health = await scheduler.rebuildNotifications(
            for: [task("Fail", due: "2026-07-02", time: "12:00")],
            now: now,
            timeZone: utc)

        XCTAssertEqual(health.state, .failed)
        XCTAssertEqual(health.failures.map(\.operation), [.add])
        XCTAssertEqual(health.pendingCount, 0)
    }

    func testNewerRebuildSupersedesOlderAndWinsFinalState() async {
        let center = MockTaskNotificationCenter(
            permission: .authorized,
            addDelayNanoseconds: 100_000_000)
        let scheduler = TaskNotificationScheduler(center: center)
        let oldTask = task("Old", due: "2026-07-02", time: "10:00")
        let latestTask = task("Latest", due: "2026-07-02", time: "11:00", line: 1)
        let referenceNow = now
        let timeZone = utc

        let first = Task {
            await scheduler.rebuildNotifications(
                for: [oldTask], now: referenceNow, timeZone: timeZone)
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        let second = Task {
            await scheduler.rebuildNotifications(
                for: [latestTask], now: referenceNow, timeZone: timeZone)
        }

        let firstHealth = await first.value
        let secondHealth = await second.value
        let identifiers = await center.coveIdentifiers()
        XCTAssertEqual(firstHealth.state, .superseded)
        XCTAssertEqual(secondHealth.state, .reconciled)
        XCTAssertEqual(
            identifiers,
            [CoveTaskNotificationIdentifier.identifier(forTaskID: latestTask.id)])
    }

    func testCancelAllRemovesOnlyCoveOwnedRequests() async {
        let center = MockTaskNotificationCenter(permission: .authorized)
        await center.seed(identifier: TaskNotificationPlanner.identifierPrefix + "one")
        await center.seed(identifier: TaskNotificationPlanner.identifierPrefix + "two")
        await center.seed(identifier: "another-feature")
        let scheduler = TaskNotificationScheduler(center: center)

        let health = await scheduler.cancelAllNotifications()

        XCTAssertEqual(health.state, .cancelledAll)
        XCTAssertEqual(health.removedCount, 2)
        let identifiers = await center.identifiers()
        XCTAssertEqual(identifiers, ["another-feature"])
    }
}

private actor MockTaskNotificationCenter: TaskNotificationCenter {
    private let currentPermission: TaskNotificationPermission
    private let failAdds: Bool
    private let addDelayNanoseconds: UInt64
    private var requests: [String: TaskNotificationPendingRequest] = [:]

    init(
        permission: TaskNotificationPermission,
        failAdds: Bool = false,
        addDelayNanoseconds: UInt64 = 0
    ) {
        currentPermission = permission
        self.failAdds = failAdds
        self.addDelayNanoseconds = addDelayNanoseconds
    }

    func permission() async -> TaskNotificationPermission {
        currentPermission
    }

    func pendingRequests() async -> [TaskNotificationPendingRequest] {
        Array(requests.values)
    }

    func add(_ plan: TaskNotificationPlan) async throws {
        if addDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: addDelayNanoseconds)
        }
        try Task.checkCancellation()
        if failAdds { throw CocoaError(.fileWriteUnknown) }
        requests[plan.identifier] = TaskNotificationPendingRequest(
            identifier: plan.identifier,
            title: plan.title,
            body: plan.body,
            dateComponents: plan.fireDateComponents,
            repeats: false)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) async {
        for identifier in identifiers {
            requests.removeValue(forKey: identifier)
        }
    }

    func seed(identifier: String) {
        requests[identifier] = TaskNotificationPendingRequest(
            identifier: identifier,
            title: "",
            body: "",
            dateComponents: nil,
            repeats: false)
    }

    func identifiers() -> [String] {
        requests.keys.sorted()
    }

    func coveIdentifiers() -> [String] {
        requests.keys.filter {
            $0.hasPrefix(TaskNotificationPlanner.identifierPrefix)
        }.sorted()
    }
}
