import XCTest
@testable import Cove

/// The App Group channel's pure parts: which tasks reach the widget, how a
/// snapshot survives a round trip through JSON, and when a stale one expires.
/// The container I/O itself isn't covered — an App Group container isn't
/// available to the test host — nor is the widget extension, which can't be
/// loaded in-process.
final class WidgetSnapshotTests: XCTestCase {

    private let calendar = Calendar.current

    private func task(_ text: String,
                      due: String?,
                      time: String? = nil,
                      recurrence: RecurrenceRule? = nil,
                      completed: Bool = false,
                      list: String? = nil,
                      line: Int = 0,
                      file: String = "/vault/Tasks.md") -> TaskItem {
        TaskItem(fileURL: URL(fileURLWithPath: file),
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
        let tasks = [task("Today", due: "2026-07-19", line: 0),
                     task("Tomorrow", due: "2026-07-20", line: 1),
                     task("Yesterday", due: "2026-07-18", line: 2)]
        let snapshot = TodaySnapshot.tasks(dueToday: "2026-07-19", from: tasks)
        XCTAssertEqual(snapshot.map(\.text), ["Today"])
    }

    func testExcludesListItems() {
        // List items never appear on the Tasks screen, so they have no place
        // on a widget that mirrors it.
        let tasks = [task("Ordinary", due: "2026-07-19", line: 0),
                     task("Milk", due: "2026-07-19", list: "Groceries", line: 1)]
        let snapshot = TodaySnapshot.tasks(dueToday: "2026-07-19", from: tasks)
        XCTAssertEqual(snapshot.map(\.text), ["Ordinary"])
    }

    func testExcludesUndatedTasks() {
        let tasks = [task("Someday", due: nil, list: "Ideas", line: 0),
                     task("Due", due: "2026-07-19", line: 1)]
        let snapshot = TodaySnapshot.tasks(dueToday: "2026-07-19", from: tasks)
        XCTAssertEqual(snapshot.map(\.text), ["Due"])
    }

    func testIncompleteTasksSortAheadOfCompletedOnes() {
        // A row checked off in the widget settles below the work that's left
        // rather than holding its place in the middle of the list.
        let tasks = [task("Done early", due: "2026-07-19", time: "08:00",
                          completed: true, line: 0),
                     task("Still open", due: "2026-07-19", time: "17:00", line: 1)]
        let snapshot = TodaySnapshot.tasks(dueToday: "2026-07-19", from: tasks)
        XCTAssertEqual(snapshot.map(\.text), ["Still open", "Done early"])
    }

    func testOrdersOpenTasksByTimeWithDateOnlyFirst() {
        let tasks = [task("Afternoon", due: "2026-07-19", time: "15:00", line: 0),
                     task("No time", due: "2026-07-19", line: 1),
                     task("Morning", due: "2026-07-19", time: "08:30", line: 2)]
        let snapshot = TodaySnapshot.tasks(dueToday: "2026-07-19", from: tasks)
        XCTAssertEqual(snapshot.map(\.text), ["No time", "Morning", "Afternoon"])
    }

    func testOpenTasksExcludeCompletedOnes() {
        let snapshot = TodaySnapshot(
            dayString: "2026-07-19",
            generatedAt: Date(),
            tasks: TodaySnapshot.tasks(dueToday: "2026-07-19", from: [
                task("Open", due: "2026-07-19", line: 0),
                task("Closed", due: "2026-07-19", completed: true, line: 1)]))
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
            tasks: TodaySnapshot.tasks(dueToday: "2026-07-18",
                                       from: [task("Old", due: "2026-07-18")]))
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19,
                                                     hour: 9))!
        XCTAssertTrue(yesterday.valid(at: now).tasks.isEmpty)
    }

    func testSnapshotFromTheSameDaySurvives() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19,
                                                     hour: 9))!
        let snapshot = TodaySnapshot.building(
            for: now, from: [task("Keep me", due: "2026-07-19")])
        XCTAssertEqual(snapshot.valid(at: now).tasks.map(\.text), ["Keep me"])
    }

    // MARK: - Round trips

    func testSnapshotTaskSurvivesJSON() throws {
        let original = SnapshotTask(task("Water the plants",
                                         due: "2026-07-19",
                                         time: "17:30",
                                         recurrence: RecurrenceRule(frequency: .weekly,
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
        let toggle = PendingToggle(SnapshotTask(
            task("Standup", due: "2026-07-19", time: "09:30",
                 recurrence: .everyWeekday)))
        let data = try JSONEncoder().encode([toggle])
        let decoded = try JSONDecoder().decode([PendingToggle].self, from: data)
        XCTAssertEqual(decoded, [toggle])
        XCTAssertEqual(decoded.first?.recurrence, .everyWeekday)
    }
}
