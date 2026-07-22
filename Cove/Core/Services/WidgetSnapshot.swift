import Foundation
import OSLog

let widgetChannelLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ankitbhade.Cove",
    category: "Widget")

/// The channel between the app and its widget extension.
///
/// The app reads the vault through a per-device security-scoped bookmark in
/// `UserDefaults`; the widget runs in its own process and cannot reach either.
/// Everything the two share therefore lives in an App Group container:
///
/// * `today.json` — a snapshot of the tasks due today, written on every index
///   rebuild. This is what the widget renders. It is derived state, never a
///   source of truth: the Markdown files remain that.
/// * `vault.bookmark` — the vault bookmark, so the widget's toggle intent can
///   write a completed task straight back to its note.
/// * `pending-task-operations-v2.json` — durable, idempotent desired-state
///   operations, acknowledged individually after the Markdown mutation lands.
///   The pre-upgrade `pending-toggles.json` is read only for migration.
///
/// The bookmark path is best-effort by design. Whether an extension can
/// resolve a bookmark the host app created is not guaranteed on iOS, so the
/// queue is what keeps the checkbox honest: a tap always lands in the note,
/// either immediately or the next time the app runs.
enum CoveSharedContainer {
    static let appGroupIdentifier = "group.com.ankitbhade.Cove"

    /// The widget kind, shared so the app reloads exactly what it published.
    static let todayWidgetKind = "CoveTodayWidget"

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static var snapshotURL: URL? { containerURL?.appendingPathComponent("today.json") }
    static var bookmarkURL: URL? { containerURL?.appendingPathComponent("vault.bookmark") }
}

/// One task as the widget needs it: enough to draw the row, and enough to
/// re-find its line in the note when the checkbox is tapped. Deliberately a
/// separate type from `TaskItem` — this one crosses a process boundary and is
/// persisted, so it is plain `Codable` values with no `URL` or `RecurrenceRule`
/// to version.
struct SnapshotTask: Codable, Hashable, Sendable, Identifiable {
    /// Absolute path of the note the task lives in.
    let filePath: String
    /// 0-based line index when the snapshot was written.
    let lineNumber: Int
    let text: String
    let dueDateString: String?
    let dueTimeString: String?
    /// `RecurrenceRule.tagText`, round-tripped rather than re-encoded.
    let recurrenceTag: String?
    let isCompleted: Bool

    /// Matches `TaskItem.id`, so the two sides agree on what a row is.
    var id: String { "\(filePath)#\(lineNumber)" }

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var recurrence: RecurrenceRule? { recurrenceTag.flatMap(RecurrenceRule.init(tagText:)) }
    var identity: TaskIdentity {
        TaskIdentity(filePath: filePath,
                     lineNumber: lineNumber,
                     text: text,
                     dueDateString: dueDateString,
                     dueTimeString: dueTimeString,
                     recurrenceTag: recurrenceTag,
                     listName: nil)
    }

    init(filePath: String,
         lineNumber: Int,
         text: String,
         dueDateString: String?,
         dueTimeString: String?,
         recurrenceTag: String?,
         isCompleted: Bool) {
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.text = text
        self.dueDateString = dueDateString
        self.dueTimeString = dueTimeString
        self.recurrenceTag = recurrenceTag
        self.isCompleted = isCompleted
    }

    init(_ task: TaskItem) {
        self.init(filePath: task.fileURL.path,
                  lineNumber: task.lineNumber,
                  text: task.text,
                  dueDateString: task.dueDateString,
                  dueTimeString: task.dueTimeString,
                  recurrenceTag: task.recurrence?.tagText,
                  isCompleted: task.isCompleted)
    }

    /// Back to a `TaskItem`, so the widget can reuse the app's own display
    /// logic (`isOverdue(at:)`, `relativeDueDescription(at:)`) rather than
    /// wording a date its own way.
    var taskItem: TaskItem {
        TaskItem(fileURL: fileURL,
                 fileTitle: fileURL.deletingPathExtension().lastPathComponent,
                 lineNumber: lineNumber,
                 text: text,
                 dueDateString: dueDateString,
                 dueTimeString: dueTimeString,
                 recurrence: recurrence,
                 isCompleted: isCompleted,
                 listName: nil)
    }

    /// The same task with its checkbox flipped, for the widget's optimistic
    /// redraw before the note has been re-indexed.
    func toggled() -> SnapshotTask {
        SnapshotTask(filePath: filePath,
                     lineNumber: lineNumber,
                     text: text,
                     dueDateString: dueDateString,
                     dueTimeString: dueTimeString,
                     recurrenceTag: recurrenceTag,
                     isCompleted: !isCompleted)
    }
}

/// What the widget draws: the tasks due on `dayString`, and when it was built.
struct TodaySnapshot: Codable, Sendable {
    /// The `YYYY-MM-DD` the snapshot was built for. The widget compares it
    /// against the current day so a stale snapshot across midnight reads as
    /// empty rather than as yesterday's list.
    var dayString: String
    var generatedAt: Date
    var tasks: [SnapshotTask]

    static let empty = TodaySnapshot(dayString: "", generatedAt: .distantPast, tasks: [])

    var openTasks: [SnapshotTask] { tasks.filter { !$0.isCompleted } }

    /// Tasks due today, incomplete first so a just-checked row settles below
    /// the work that is left rather than holding its place.
    static func tasks(dueToday dayString: String, from allTasks: [TaskItem]) -> [SnapshotTask] {
        let today = allTasks
            .filter { $0.listName == nil && $0.dueDateString == dayString }
            .sorted(by: VaultIndex.byDueDate)
        return (today.filter { !$0.isCompleted } + today.filter(\.isCompleted))
            .map(SnapshotTask.init)
    }

    /// The snapshot for a day, built from the whole index.
    static func building(for now: Date,
                         from allTasks: [TaskItem],
                         calendar: Calendar = TaskCalendar.gregorian()) -> TodaySnapshot {
        let dayString = QuickTaskParser.ymdString(from: now, calendar: calendar)
        return TodaySnapshot(dayString: dayString,
                             generatedAt: now,
                             tasks: tasks(dueToday: dayString, from: allTasks))
    }

    /// The snapshot as of `now`, emptied if it was built for another day.
    func valid(at now: Date,
               calendar: Calendar = TaskCalendar.gregorian()) -> TodaySnapshot {
        dayString == QuickTaskParser.ymdString(from: now, calendar: calendar) ? self : .empty
    }
}

/// Legacy queue record retained only so an ephemeral pre-upgrade queue can be
/// decoded and converted without crashing either process.
struct PendingToggle: Codable, Hashable, Sendable {
    let filePath: String
    let lineNumber: Int
    let text: String
    let dueDateString: String?
    let dueTimeString: String?
    let recurrenceTag: String?
    /// The completion state the task had *before* the tap — what the app's
    /// re-find must match to be sure it is rewriting the same line.
    let wasCompleted: Bool

    init(_ task: SnapshotTask) {
        filePath = task.filePath
        lineNumber = task.lineNumber
        text = task.text
        dueDateString = task.dueDateString
        dueTimeString = task.dueTimeString
        recurrenceTag = task.recurrenceTag
        wasCompleted = task.isCompleted
    }

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var recurrence: RecurrenceRule? { recurrenceTag.flatMap(RecurrenceRule.init(tagText:)) }
}

/// A retry-safe widget mutation. It records the desired final state rather
/// than an instruction to toggle, so applying it more than once cannot undo a
/// successful first attempt.
struct PendingTaskOperation: Codable, Hashable, Sendable, Identifiable {
    /// How many drains an operation may fail before it is given up on. The
    /// queue is durable, so without a ceiling an operation that can never
    /// apply would be retried on every launch for the life of the vault.
    static let maxAttempts = 5

    let id: UUID
    let taskIdentity: TaskIdentity
    let desiredCompletion: Bool
    let createdAt: Date
    /// Failed drains so far. Only the app's drain counts attempts; the
    /// widget's own write failing is the expected case the queue exists for.
    var attemptCount: Int

    init(id: UUID = UUID(),
         taskIdentity: TaskIdentity,
         desiredCompletion: Bool,
         createdAt: Date = Date(),
         attemptCount: Int = 0) {
        self.id = id
        self.taskIdentity = taskIdentity
        self.desiredCompletion = desiredCompletion
        self.createdAt = createdAt
        self.attemptCount = attemptCount
    }

    init(task: SnapshotTask, desiredCompletion: Bool) {
        self.init(taskIdentity: task.identity,
                  desiredCompletion: desiredCompletion)
    }
}

private extension PendingToggle {
    var pendingOperation: PendingTaskOperation {
        PendingTaskOperation(
            taskIdentity: TaskIdentity(
                filePath: filePath,
                lineNumber: lineNumber,
                text: text,
                dueDateString: dueDateString,
                dueTimeString: dueTimeString,
                recurrenceTag: recurrenceTag,
                listName: nil),
            desiredCompletion: !wasCompleted)
    }
}

/// Reads and writes the shared files. Both processes use this one type so the
/// file names and the JSON shape can't drift apart.
struct WidgetSnapshotStore: Sendable {
    private let containerURL: URL?

    init(containerURL: URL? = CoveSharedContainer.containerURL) {
        self.containerURL = containerURL
    }

    private var snapshotURL: URL? { containerURL?.appendingPathComponent("today.json") }
    private var bookmarkURL: URL? { containerURL?.appendingPathComponent("vault.bookmark") }
    private var pendingOperationsURL: URL? {
        containerURL?.appendingPathComponent("pending-task-operations-v2.json")
    }
    private var legacyPendingTogglesURL: URL? {
        containerURL?.appendingPathComponent("pending-toggles.json")
    }

    // MARK: - Snapshot

    func writeSnapshot(_ snapshot: TodaySnapshot) {
        guard let url = snapshotURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            widgetChannelLogger.error("Snapshot write failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func readSnapshot() -> TodaySnapshot {
        guard let url = snapshotURL,
              FileManager.default.fileExists(atPath: url.path) else { return .empty }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(TodaySnapshot.self, from: data)
        } catch {
            widgetChannelLogger.error("Snapshot read failed: \(error.localizedDescription, privacy: .private)")
            return .empty
        }
    }

    // MARK: - Bookmark

    func writeBookmark(_ data: Data) {
        guard let url = bookmarkURL else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            widgetChannelLogger.error("Shared bookmark write failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func readBookmark() -> Data? {
        guard let url = bookmarkURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            widgetChannelLogger.error("Shared bookmark read failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    // MARK: - Pending task operations

    /// The queue, migrating a pre-upgrade one on first read.
    ///
    /// Migration is persisted before it is returned. Converting a legacy
    /// toggle mints a fresh id, so leaving the records in the legacy file
    /// would hand out different ids on every read — and then acknowledging or
    /// counting an attempt against one of them would address an operation the
    /// file doesn't contain.
    func loadPendingOperations() throws -> [PendingTaskOperation] {
        guard let url = pendingOperationsURL else { throw CocoaError(.fileNoSuchFile) }
        if FileManager.default.fileExists(atPath: url.path) {
            return try coordinatedQueueRead(at: url)
        }
        guard let legacyURL = legacyPendingTogglesURL,
              FileManager.default.fileExists(atPath: legacyURL.path) else { return [] }
        let data = try Data(contentsOf: legacyURL)
        let migrated = try JSONDecoder().decode([PendingToggle].self, from: data)
            .map(\.pendingOperation)
        try replace(migrated)
        // The v2 file now supersedes it; a failed removal is harmless because
        // the legacy file is never consulted again once v2 exists.
        try? FileManager.default.removeItem(at: legacyURL)
        return migrated
    }

    func append(_ operation: PendingTaskOperation) throws {
        try coordinatedQueueUpdate { operations in
            guard !operations.contains(where: { $0.id == operation.id }) else { return }
            operations.append(operation)
        }
    }

    func acknowledge(operationID: UUID) throws {
        try coordinatedQueueUpdate { operations in
            operations.removeAll { $0.id == operationID }
        }
    }

    /// Counts one failed drain against an operation, dropping it once it has
    /// exhausted `maxAttempts`. Returns whether it was dropped.
    ///
    /// If this write itself fails the attempt goes uncounted — which is the
    /// right outcome, since a queue that can't be written can't be pruned
    /// either.
    @discardableResult
    func recordFailure(operationID: UUID,
                       maxAttempts: Int = PendingTaskOperation.maxAttempts) throws -> Bool {
        var dropped = false
        try coordinatedQueueUpdate { operations in
            guard let index = operations.firstIndex(where: { $0.id == operationID })
            else { return }
            operations[index].attemptCount += 1
            if operations[index].attemptCount >= maxAttempts {
                operations.remove(at: index)
                dropped = true
            }
        }
        return dropped
    }

    func replace(_ operations: [PendingTaskOperation]) throws {
        try coordinatedQueueUpdate { $0 = operations }
    }

    private func coordinatedQueueRead(at url: URL) throws -> [PendingTaskOperation] {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<[PendingTaskOperation], Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) {
            coordinatedURL in
            result = Result {
                let data = try Data(contentsOf: coordinatedURL)
                return try JSONDecoder().decode([PendingTaskOperation].self, from: data)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    private func coordinatedQueueUpdate(
        _ transform: (inout [PendingTaskOperation]) throws -> Void
    ) throws {
        guard let url = pendingOperationsURL else { throw CocoaError(.fileNoSuchFile) }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: url, options: .forMerging,
                               error: &coordinationError) { coordinatedURL in
            result = Result {
                var operations: [PendingTaskOperation]
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    let data = try Data(contentsOf: coordinatedURL)
                    operations = try JSONDecoder().decode(
                        [PendingTaskOperation].self, from: data)
                } else {
                    operations = []
                }
                try transform(&operations)
                let data = try JSONEncoder().encode(operations)
                try data.write(to: coordinatedURL, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }
}
