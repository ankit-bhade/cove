import Foundation
import OSLog

let widgetChannelLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ankitbhade.Cove",
    category: "Widget")

/// Opaque, deterministic notification identifiers. Task IDs contain absolute
/// note paths, so they must not be copied verbatim into the notification
/// database or diagnostics.
enum CoveTaskNotificationIdentifier {
    static let prefix = "cove-task:"

    static func identifier(forTaskID taskID: String) -> String {
        prefix + digest(taskID)
    }

    static func digest(_ value: String) -> String {
        let bytes = Array(value.utf8)
        let first = fnv1a(bytes, seed: 0xcbf29ce484222325)
        let second = fnv1a(bytes.reversed(), seed: 0x84222325cbf29ce4)
        return String(format: "%016llx%016llx", first, second)
    }

    private static func fnv1a<S: Sequence>(
        _ bytes: S,
        seed: UInt64
    ) -> UInt64 where S.Element == UInt8 {
        bytes.reduce(seed) { partial, byte in
            (partial ^ UInt64(byte)) &* 0x100000001b3
        }
    }
}

/// The channel between the app and its widget extension.
enum CoveSharedContainer {
    static let appGroupIdentifier = "group.com.ankitbhade.Cove"
    static let todayWidgetKind = "CoveTodayWidget"

    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }
}

enum WidgetStoreArtifact: String, Codable, Equatable, Sendable {
    case snapshot
    case bookmark
    case operationQueue
}

enum WidgetStoreError: LocalizedError, Equatable, Sendable {
    case appGroupUnavailable
    case artifactMissing(WidgetStoreArtifact)
    case unsupportedSchema(artifact: WidgetStoreArtifact, found: Int, supported: Int)
    case taskNotFound
    case queueCapacityReached(limit: Int)
    case readFailed(WidgetStoreArtifact)
    case writeFailed(WidgetStoreArtifact)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "The shared widget container is unavailable."
        case .artifactMissing(.snapshot):
            "Cove has not published widget data yet."
        case .artifactMissing(.bookmark):
            "The widget cannot access the selected vault yet."
        case .artifactMissing(.operationQueue):
            "The widget operation queue is unavailable."
        case .unsupportedSchema:
            "The shared widget data was written by an incompatible Cove version."
        case .taskNotFound:
            "That widget task is no longer in the current snapshot."
        case .queueCapacityReached:
            "Too many widget changes are waiting to sync. Open Cove before trying again."
        case .readFailed:
            "Cove could not read shared widget data."
        case .writeFailed:
            "Cove could not save shared widget data."
        }
    }
}

struct WidgetChannelHealth: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case ready
        case notPublished
        case unavailable
        case needsAttention
    }

    let state: State
    let pendingOperationCount: Int
    let failedOperationCount: Int
    let discardedFailureReceiptCount: Int
    let pendingQueueAtCapacity: Bool
    let legacyMigrationCleanupPending: Bool
    let snapshotAvailability: TodaySnapshotAvailability?
    let error: WidgetStoreError?
}

/// One task as the widget needs it: enough to draw the row, and enough to
/// re-find its line in the note when the checkbox is tapped.
struct SnapshotTask: Codable, Hashable, Sendable, Identifiable {
    let filePath: String
    let lineNumber: Int
    let text: String
    let dueDateString: String?
    let dueTimeString: String?
    let recurrenceTag: String?
    let recurrenceAnchorDateString: String?
    let isSectionedDocument: Bool
    let isCompleted: Bool
    /// Desired state accepted by the widget but not yet confirmed in
    /// Markdown. It is deliberately separate from authoritative completion.
    let pendingCompletion: Bool?
    /// The `##` section the line sits under, for a dated list item. It has to
    /// cross the App Group: a task's line is re-found by matching its text,
    /// its schedule, *and* its list, so a toggle sent back with no list would
    /// fail to match the very line the widget was drawing.
    let listName: String?

    private var notificationRawTaskID: String { "\(filePath)#\(lineNumber)" }
    private var semanticRawTaskID: String {
        let fields: [String?] = [
            filePath,
            String(lineNumber),
            text,
            dueDateString,
            dueTimeString,
            recurrenceTag,
            recurrenceAnchorDateString,
            isSectionedDocument ? "sectioned" : "unsectioned",
            listName.map(TaskListDocument.canonicalName),
        ]
        return fields.map { value in
            guard let value else { return "nil" }
            return "value:\(value.utf8.count):\(value)"
        }
        .joined(separator: "|")
    }

    /// App Intent parameters can be persisted by the system, so never hand
    /// them an absolute vault path. The opaque identifier fingerprints the
    /// semantic task, not just its current line: a stale timeline must not
    /// resolve a replacement task that later occupies the same path and line.
    var id: String {
        "cove-widget:" + CoveTaskNotificationIdentifier.digest(semanticRawTaskID)
    }
    var notificationIdentifier: String {
        CoveTaskNotificationIdentifier.identifier(forTaskID: notificationRawTaskID)
    }
    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var recurrence: RecurrenceRule? { recurrenceTag.flatMap(RecurrenceRule.init(tagText:)) }
    var identity: TaskIdentity {
        TaskIdentity(
            filePath: filePath,
            lineNumber: lineNumber,
            text: text,
            dueDateString: dueDateString,
            dueTimeString: dueTimeString,
            recurrenceTag: recurrenceTag,
            listName: listName,
            recurrenceAnchorDateString: recurrenceAnchorDateString,
            isSectionedDocument: isSectionedDocument)
    }

    init(
        filePath: String,
        lineNumber: Int,
        text: String,
        dueDateString: String?,
        dueTimeString: String?,
        recurrenceTag: String?,
        isCompleted: Bool,
        pendingCompletion: Bool? = nil,
        recurrenceAnchorDateString: String? = nil,
        isSectionedDocument: Bool = false,
        listName: String? = nil
    ) {
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.text = text
        self.dueDateString = dueDateString
        self.dueTimeString = dueTimeString
        self.recurrenceTag = recurrenceTag
        self.recurrenceAnchorDateString = recurrenceAnchorDateString
        self.isSectionedDocument = isSectionedDocument
        self.isCompleted = isCompleted
        self.pendingCompletion = pendingCompletion
        self.listName = listName
    }

    init(_ task: TaskItem) {
        self.init(
            filePath: task.fileURL.path,
            lineNumber: task.lineNumber,
            text: task.text,
            dueDateString: task.dueDateString,
            dueTimeString: task.dueTimeString,
            recurrenceTag: task.recurrence?.tagText,
            isCompleted: task.isCompleted,
            pendingCompletion: nil,
            recurrenceAnchorDateString: task.recurrenceAnchorDateString,
            isSectionedDocument: task.isSectionedDocument,
            listName: task.listName)
    }

    var taskItem: TaskItem {
        TaskItem(
            fileURL: fileURL,
            fileTitle: fileURL.deletingPathExtension().lastPathComponent,
            lineNumber: lineNumber,
            text: text,
            dueDateString: dueDateString,
            dueTimeString: dueTimeString,
            recurrence: recurrence,
            isCompleted: isCompleted,
            listName: listName,
            recurrenceAnchorDateString: recurrenceAnchorDateString,
            isSectionedDocument: isSectionedDocument)
    }

    func settingCompleted(_ isCompleted: Bool) -> SnapshotTask {
        SnapshotTask(
            filePath: filePath,
            lineNumber: lineNumber,
            text: text,
            dueDateString: dueDateString,
            dueTimeString: dueTimeString,
            recurrenceTag: recurrenceTag,
            isCompleted: isCompleted,
            pendingCompletion: nil,
            recurrenceAnchorDateString: recurrenceAnchorDateString,
            isSectionedDocument: isSectionedDocument,
            listName: listName)
    }

    func settingPendingCompletion(_ desiredCompletion: Bool) -> SnapshotTask {
        SnapshotTask(
            filePath: filePath,
            lineNumber: lineNumber,
            text: text,
            dueDateString: dueDateString,
            dueTimeString: dueTimeString,
            recurrenceTag: recurrenceTag,
            isCompleted: isCompleted,
            pendingCompletion: desiredCompletion,
            recurrenceAnchorDateString: recurrenceAnchorDateString,
            isSectionedDocument: isSectionedDocument,
            listName: listName)
    }

    private enum CodingKeys: String, CodingKey {
        case filePath
        case lineNumber
        case text
        case dueDateString
        case dueTimeString
        case recurrenceTag
        case recurrenceAnchorDateString
        case isSectionedDocument
        case isCompleted
        case pendingCompletion
        case listName
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            filePath: try values.decode(String.self, forKey: .filePath),
            lineNumber: try values.decode(Int.self, forKey: .lineNumber),
            text: try values.decode(String.self, forKey: .text),
            dueDateString: try values.decodeIfPresent(
                String.self, forKey: .dueDateString),
            dueTimeString: try values.decodeIfPresent(
                String.self, forKey: .dueTimeString),
            recurrenceTag: try values.decodeIfPresent(
                String.self, forKey: .recurrenceTag),
            isCompleted: try values.decode(Bool.self, forKey: .isCompleted),
            pendingCompletion: try values.decodeIfPresent(
                Bool.self, forKey: .pendingCompletion),
            recurrenceAnchorDateString: try values.decodeIfPresent(
                String.self, forKey: .recurrenceAnchorDateString),
            isSectionedDocument:
                try values.decodeIfPresent(
                    Bool.self, forKey: .isSectionedDocument) ?? false,
            // Absent in snapshots written before dated list items reached
            // the widget; those carried unlisted tasks only, so nil is the
            // right reading rather than a missing value.
            listName: try values.decodeIfPresent(String.self, forKey: .listName))
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(filePath, forKey: .filePath)
        try values.encode(lineNumber, forKey: .lineNumber)
        try values.encode(text, forKey: .text)
        try values.encodeIfPresent(dueDateString, forKey: .dueDateString)
        try values.encodeIfPresent(dueTimeString, forKey: .dueTimeString)
        try values.encodeIfPresent(recurrenceTag, forKey: .recurrenceTag)
        try values.encodeIfPresent(
            recurrenceAnchorDateString,
            forKey: .recurrenceAnchorDateString)
        try values.encode(isSectionedDocument, forKey: .isSectionedDocument)
        try values.encode(isCompleted, forKey: .isCompleted)
        try values.encodeIfPresent(
            pendingCompletion, forKey: .pendingCompletion)
        try values.encodeIfPresent(listName, forKey: .listName)
    }
}

enum TodaySnapshotAvailability: String, Codable, Equatable, Sendable {
    case available
    case vaultUnavailable
    case sharedContainerUnavailable
    case unreadable
    case notPublished
    case stale
}

struct SnapshotOptimisticMutation: Codable, Hashable, Sendable {
    let operationID: UUID
    let taskID: String
    let desiredCompletion: Bool
    let createdAt: Date
    let outcome: TaskCompletionMutationOutcome

    init(
        operationID: UUID,
        taskID: String,
        desiredCompletion: Bool,
        createdAt: Date,
        outcome: TaskCompletionMutationOutcome
    ) {
        self.operationID = operationID
        self.taskID = taskID
        self.desiredCompletion = desiredCompletion
        self.createdAt = createdAt
        self.outcome = outcome
    }

    private enum CodingKeys: String, CodingKey {
        case operationID
        case taskID
        case desiredCompletion
        case createdAt
        case outcome
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operationID = try container.decode(UUID.self, forKey: .operationID)
        taskID = try container.decode(String.self, forKey: .taskID)
        desiredCompletion = try container.decode(Bool.self, forKey: .desiredCompletion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        outcome =
            try container.decodeIfPresent(
                TaskCompletionMutationOutcome.self,
                forKey: .outcome) ?? .deferred
    }
}

/// What the widget draws. Version and revision make cross-process upgrades
/// and coordinated read-modify-write behavior explicit.
struct TodaySnapshot: Codable, Sendable {
    static let currentSchemaVersion = 3
    /// Enough rows for medium-widget refill and timeline transitions without
    /// persisting every task title/path in a very large `tasks.md`.
    static let maximumStoredTasks = 12
    static let optimisticMutationLifetime: TimeInterval = 24 * 60 * 60

    var schemaVersion: Int
    var revision: UInt64
    var dayString: String
    var generatedAt: Date
    var availability: TodaySnapshotAvailability
    var tasks: [SnapshotTask]
    var totalTaskCount: Int
    var totalOpenTaskCount: Int
    var optimisticMutations: [SnapshotOptimisticMutation]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        revision: UInt64 = 0,
        dayString: String,
        generatedAt: Date,
        availability: TodaySnapshotAvailability = .available,
        tasks: [SnapshotTask],
        totalTaskCount: Int? = nil,
        totalOpenTaskCount: Int? = nil,
        optimisticMutations: [SnapshotOptimisticMutation] = []
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.dayString = dayString
        self.generatedAt = generatedAt
        self.availability = availability
        self.tasks = Array(tasks.prefix(Self.maximumStoredTasks))
        self.totalTaskCount = totalTaskCount ?? tasks.count
        self.totalOpenTaskCount =
            totalOpenTaskCount ?? tasks.filter { !$0.isCompleted }.count
        self.optimisticMutations = optimisticMutations
        sortTasksForDisplay()
    }

    static let empty = TodaySnapshot(
        dayString: "",
        generatedAt: .distantPast,
        tasks: [])

    static func unavailable(
        _ reason: TodaySnapshotAvailability,
        at date: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> TodaySnapshot {
        precondition(reason != .available)
        return TodaySnapshot(
            dayString: QuickTaskParser.ymdString(from: date, timeZone: timeZone),
            generatedAt: date,
            availability: reason,
            tasks: [])
    }

    var openTasks: [SnapshotTask] { tasks.filter { !$0.isCompleted } }

    func task(matchingWidgetID taskID: String) -> SnapshotTask? {
        tasks.first { $0.id == taskID }
    }

    /// Today's rows, admitting exactly what the Tasks screen admits: every
    /// unlisted task due today plus a list's dated items due today. An
    /// undated list item has no day to be due on, so it never appears here.
    static func tasks(dueToday dayString: String, from allTasks: [TaskItem]) -> [SnapshotTask] {
        let today =
            allTasks
            .filter { $0.belongsOnTasksScreen && $0.dueDateString == dayString }
            .sorted(by: TaskItem.byDueDate)
        return (today.filter { !$0.isCompleted } + today.filter(\.isCompleted))
            .map(SnapshotTask.init)
    }

    static func building(
        for now: Date,
        from allTasks: [TaskItem],
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> TodaySnapshot {
        let dayString = QuickTaskParser.ymdString(from: now, timeZone: timeZone)
        let matching = tasks(dueToday: dayString, from: allTasks)
        return TodaySnapshot(
            dayString: dayString,
            generatedAt: now,
            tasks: matching,
            totalTaskCount: matching.count,
            totalOpenTaskCount: matching.filter { !$0.isCompleted }.count)
    }

    func valid(
        at now: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> TodaySnapshot {
        guard availability == .available else { return self }
        return dayString == QuickTaskParser.ymdString(from: now, timeZone: timeZone)
            ? self : .unavailable(.stale, at: now, timeZone: timeZone)
    }

    mutating func applyOptimisticCompletion(
        taskID: String,
        desiredCompletion: Bool,
        operationID: UUID,
        outcome: TaskCompletionMutationOutcome,
        at date: Date
    ) throws {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw WidgetStoreError.taskNotFound
        }
        let task = tasks[index]
        if outcome == .stale {
            tasks.remove(at: index)
            totalTaskCount = max(0, totalTaskCount - 1)
            if !task.isCompleted {
                totalOpenTaskCount = max(0, totalOpenTaskCount - 1)
            }
        } else if outcome == .deferred {
            // Pending is a promise to retry, not a claim that Markdown
            // changed. Keep authoritative completion/counts untouched.
            tasks[index] = task.settingPendingCompletion(desiredCompletion)
        } else if task.recurrence != nil && desiredCompletion {
            tasks.remove(at: index)
            totalTaskCount = max(0, totalTaskCount - 1)
            if !task.isCompleted {
                totalOpenTaskCount = max(0, totalOpenTaskCount - 1)
            }
        } else {
            if task.isCompleted != desiredCompletion {
                totalOpenTaskCount += desiredCompletion ? -1 : 1
                totalOpenTaskCount = max(0, totalOpenTaskCount)
            }
            tasks[index] = task.settingCompleted(desiredCompletion)
        }

        optimisticMutations.removeAll { $0.taskID == taskID }
        if outcome != .stale {
            optimisticMutations.append(
                SnapshotOptimisticMutation(
                    operationID: operationID,
                    taskID: taskID,
                    desiredCompletion: desiredCompletion,
                    createdAt: date,
                    outcome: outcome))
        }
        sortTasksForDisplay()
    }

    /// Applies unresolved widget-side desired states to a new app-published
    /// snapshot. Once the authoritative index agrees (or the task is gone),
    /// the marker is retired.
    func mergingOptimisticMutations(
        from previous: TodaySnapshot,
        at date: Date
    ) -> TodaySnapshot {
        guard availability == .available,
            previous.availability == .available,
            dayString == previous.dayString
        else { return self }

        var merged = self
        for mutation in previous.optimisticMutations
        where date.timeIntervalSince(mutation.createdAt) <= Self.optimisticMutationLifetime {
            guard let index = merged.tasks.firstIndex(where: { $0.id == mutation.taskID })
            else { continue }
            let task = merged.tasks[index]
            guard task.isCompleted != mutation.desiredCompletion else { continue }
            if mutation.outcome == .deferred {
                merged.tasks[index] = task.settingPendingCompletion(
                    mutation.desiredCompletion)
            } else if task.recurrence != nil && mutation.desiredCompletion {
                merged.tasks.remove(at: index)
                merged.totalTaskCount = max(0, merged.totalTaskCount - 1)
                merged.totalOpenTaskCount = max(0, merged.totalOpenTaskCount - 1)
            } else {
                merged.tasks[index] = task.settingCompleted(mutation.desiredCompletion)
                merged.totalOpenTaskCount += mutation.desiredCompletion ? -1 : 1
                merged.totalOpenTaskCount = max(0, merged.totalOpenTaskCount)
            }
            merged.optimisticMutations.append(mutation)
        }
        merged.sortTasksForDisplay()
        return merged
    }

    private mutating func sortTasksForDisplay() {
        tasks.sort { lhs, rhs in
            let lhsActionable = !lhs.isCompleted || lhs.pendingCompletion != nil
            let rhsActionable = !rhs.isCompleted || rhs.pendingCompletion != nil
            if lhsActionable != rhsActionable {
                return lhsActionable
            }
            return TaskItem.byDueDate(lhs.taskItem, rhs.taskItem)
        }
        if tasks.count > Self.maximumStoredTasks {
            tasks.removeLast(tasks.count - Self.maximumStoredTasks)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revision
        case dayString
        case generatedAt
        case availability
        case tasks
        case totalTaskCount
        case totalOpenTaskCount
        case optimisticMutations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else {
            throw WidgetStoreError.unsupportedSchema(
                artifact: .snapshot,
                found: schemaVersion,
                supported: Self.currentSchemaVersion)
        }
        revision = try container.decodeIfPresent(UInt64.self, forKey: .revision) ?? 0
        dayString = try container.decode(String.self, forKey: .dayString)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        availability =
            try container.decodeIfPresent(
                TodaySnapshotAvailability.self,
                forKey: .availability) ?? .available
        tasks = try container.decode([SnapshotTask].self, forKey: .tasks)
        totalTaskCount =
            try container.decodeIfPresent(Int.self, forKey: .totalTaskCount)
            ?? tasks.count
        totalOpenTaskCount =
            try container.decodeIfPresent(Int.self, forKey: .totalOpenTaskCount)
            ?? tasks.filter { !$0.isCompleted }.count
        optimisticMutations =
            try container.decodeIfPresent(
                [SnapshotOptimisticMutation].self,
                forKey: .optimisticMutations) ?? []
        sortTasksForDisplay()
    }
}

enum TaskCompletionMutationOutcome: String, Codable, Equatable, Sendable {
    case changed
    case alreadyDesired
    case stale
    case deferred
}

/// Legacy queue record retained only for migration.
struct PendingToggle: Codable, Hashable, Sendable {
    let filePath: String
    let lineNumber: Int
    let text: String
    let dueDateString: String?
    let dueTimeString: String?
    let recurrenceTag: String?
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

struct PendingTaskOperation: Codable, Hashable, Sendable, Identifiable {
    static let maxAttempts = 5

    let id: UUID
    let taskIdentity: TaskIdentity
    let desiredCompletion: Bool
    let createdAt: Date
    var attemptCount: Int

    init(
        id: UUID = UUID(),
        taskIdentity: TaskIdentity,
        desiredCompletion: Bool,
        createdAt: Date = Date(),
        attemptCount: Int = 0
    ) {
        self.id = id
        self.taskIdentity = taskIdentity
        self.desiredCompletion = desiredCompletion
        self.createdAt = createdAt
        self.attemptCount = attemptCount
    }

    init(task: SnapshotTask, desiredCompletion: Bool) {
        self.init(
            taskIdentity: task.identity,
            desiredCompletion: desiredCompletion)
    }

    var taskFingerprint: String {
        let task = SnapshotTask(
            filePath: taskIdentity.filePath,
            lineNumber: taskIdentity.lineNumber,
            text: taskIdentity.text,
            dueDateString: taskIdentity.dueDateString,
            dueTimeString: taskIdentity.dueTimeString,
            recurrenceTag: taskIdentity.recurrenceTag,
            isCompleted: false,
            recurrenceAnchorDateString: taskIdentity.recurrenceAnchorDateString,
            isSectionedDocument: taskIdentity.isSectionedDocument,
            listName: taskIdentity.listName)
        return task.id
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

enum WidgetOperationFailureReason: String, Codable, Equatable, Sendable {
    case retryLimitExceeded
    case staleTarget
    case sharedContainerUnavailable
}

struct WidgetOperationFailureReceipt: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let operationID: UUID
    /// Opaque correlation only; no title or filesystem path is retained.
    let taskFingerprint: String
    let desiredCompletion: Bool
    let attempts: Int
    let failedAt: Date
    let reason: WidgetOperationFailureReason
}

enum WidgetQueueResolution: Equatable, Sendable {
    case acknowledge(UUID)
    case recordFailure(UUID, WidgetOperationFailureReason)
}

struct WidgetQueueBatchResult: Equatable, Sendable {
    let acknowledgedCount: Int
    let retainedCount: Int
    let failedPermanentlyCount: Int
    let pendingCount: Int
    let queueAtCapacity: Bool
}

private struct PendingTaskOperationQueue: Codable, Sendable {
    static let currentSchemaVersion = 4

    var schemaVersion = Self.currentSchemaVersion
    var operations: [PendingTaskOperation] = []
    var failureReceipts: [WidgetOperationFailureReceipt] = []
    var discardedFailureReceiptCount = 0
    var legacyCleanupPending = false

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case operations
        case failureReceipts
        case discardedFailureReceiptCount
        case legacyCleanupPending
    }

    init(
        operations: [PendingTaskOperation] = [],
        failureReceipts: [WidgetOperationFailureReceipt] = [],
        discardedFailureReceiptCount: Int = 0,
        legacyCleanupPending: Bool = false
    ) {
        self.operations = operations
        self.failureReceipts = failureReceipts
        self.discardedFailureReceiptCount = discardedFailureReceiptCount
        self.legacyCleanupPending = legacyCleanupPending
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion =
            try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        operations =
            try container.decodeIfPresent(
                [PendingTaskOperation].self,
                forKey: .operations) ?? []
        failureReceipts =
            try container.decodeIfPresent(
                [WidgetOperationFailureReceipt].self,
                forKey: .failureReceipts) ?? []
        discardedFailureReceiptCount =
            try container.decodeIfPresent(
                Int.self,
                forKey: .discardedFailureReceiptCount) ?? 0
        legacyCleanupPending =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .legacyCleanupPending) ?? false
    }
}

/// Coordinated, atomic I/O for all cross-process widget state.
struct WidgetSnapshotStore: Sendable {
    static let maximumPendingOperations = 256
    static let maximumFailureReceipts = 100
    static let unreadableSnapshotBackupName =
        "today-unreadable-backup.json"

    private let containerURL: URL?

    init(containerURL: URL? = CoveSharedContainer.containerURL) {
        self.containerURL = containerURL
    }

    private var snapshotURL: URL? { containerURL?.appendingPathComponent("today.json") }
    private var unreadableSnapshotBackupURL: URL? {
        containerURL?.appendingPathComponent(
            Self.unreadableSnapshotBackupName)
    }
    private var bookmarkURL: URL? { containerURL?.appendingPathComponent("vault.bookmark") }
    private var pendingOperationsURL: URL? {
        containerURL?.appendingPathComponent("pending-task-operations-v2.json")
    }
    private var legacyPendingTogglesURL: URL? {
        containerURL?.appendingPathComponent("pending-toggles.json")
    }

    // MARK: - Snapshot

    /// Publishes an authoritative app snapshot while preserving any
    /// unresolved optimistic widget mutations from a concurrent tap.
    @discardableResult
    func writeSnapshot(_ snapshot: TodaySnapshot) -> Result<TodaySnapshot, WidgetStoreError> {
        do {
            let written = try coordinatedSnapshotUpdate(requireExisting: false) { previous in
                guard let previous else { return snapshot }
                return snapshot.mergingOptimisticMutations(
                    from: previous,
                    at: snapshot.generatedAt)
            }
            return .success(written)
        } catch {
            log(error, message: "Snapshot write failed")
            return .failure(storeError(error, artifact: .snapshot, writing: true))
        }
    }

    /// Publishes a durable "open/reconnect Cove" state instead of leaving
    /// yesterday's task titles visible after bookmark/vault recovery fails.
    @discardableResult
    func writeUnavailableSnapshot(
        _ reason: TodaySnapshotAvailability,
        at date: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Result<TodaySnapshot, WidgetStoreError> {
        precondition(reason != .available)
        do {
            let snapshot = TodaySnapshot.unavailable(
                reason,
                at: date,
                timeZone: timeZone)
            return .success(
                try coordinatedSnapshotUpdate(requireExisting: false) { _ in snapshot })
        } catch {
            log(error, message: "Unavailable snapshot write failed")
            return .failure(storeError(error, artifact: .snapshot, writing: true))
        }
    }

    func readSnapshotResult() -> Result<TodaySnapshot, WidgetStoreError> {
        guard let url = snapshotURL else { return .failure(.appGroupUnavailable) }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.artifactMissing(.snapshot))
        }
        do {
            return .success(
                try FileCoordination.read(at: url) {
                    try decodeSnapshot(Data(contentsOf: $0))
                })
        } catch {
            log(error, message: "Snapshot read failed")
            return .failure(storeError(error, artifact: .snapshot, writing: false))
        }
    }

    /// Compatibility convenience for timeline providers. Unlike the old
    /// silent empty fallback, channel failures become an explicit widget UI
    /// state.
    func readSnapshot() -> TodaySnapshot {
        switch readSnapshotResult() {
        case .success(let snapshot):
            return snapshot
        case .failure(.appGroupUnavailable):
            return .unavailable(.sharedContainerUnavailable)
        case .failure(.artifactMissing):
            return .unavailable(.notPublished)
        case .failure:
            return .unavailable(.unreadable)
        }
    }

    /// One coordinated read-modify-write for a widget tap, so two extension
    /// processes cannot overwrite each other's optimistic state.
    func applyOptimisticCompletion(
        taskID: String,
        desiredCompletion: Bool,
        operationID: UUID,
        outcome: TaskCompletionMutationOutcome,
        at date: Date
    ) throws -> TodaySnapshot {
        try coordinatedSnapshotUpdate(requireExisting: true) { previous in
            guard var snapshot = previous else {
                throw WidgetStoreError.artifactMissing(.snapshot)
            }
            try snapshot.applyOptimisticCompletion(
                taskID: taskID,
                desiredCompletion: desiredCompletion,
                operationID: operationID,
                outcome: outcome,
                at: date)
            return snapshot
        }
    }

    // MARK: - Bookmark

    @discardableResult
    func writeBookmark(_ data: Data) -> Result<Void, WidgetStoreError> {
        guard let url = bookmarkURL else { return .failure(.appGroupUnavailable) }
        do {
            try FileCoordination.write(at: url, options: .forReplacing) {
                try writeProtected(data, to: $0)
            }
            return .success(())
        } catch {
            log(error, message: "Shared bookmark write failed")
            return .failure(storeError(error, artifact: .bookmark, writing: true))
        }
    }

    func readBookmarkResult() -> Result<Data, WidgetStoreError> {
        guard let url = bookmarkURL else { return .failure(.appGroupUnavailable) }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.artifactMissing(.bookmark))
        }
        do {
            return .success(
                try FileCoordination.read(at: url) {
                    try Data(contentsOf: $0)
                })
        } catch {
            log(error, message: "Shared bookmark read failed")
            return .failure(storeError(error, artifact: .bookmark, writing: false))
        }
    }

    func readBookmark() -> Data? {
        try? readBookmarkResult().get()
    }

    // MARK: - Pending task operations

    func loadPendingOperations() throws -> [PendingTaskOperation] {
        try loadQueueMigratingIfNeeded().operations
    }

    func loadFailureReceipts() throws -> [WidgetOperationFailureReceipt] {
        try loadQueueMigratingIfNeeded().failureReceipts
    }

    /// Coalesces repeated desired-state writes for the same semantic task.
    /// The returned operation is the actual durable record callers must later
    /// acknowledge (which may be an existing record for the same state).
    @discardableResult
    func append(_ operation: PendingTaskOperation) throws -> PendingTaskOperation {
        try enqueue([operation]).first ?? operation
    }

    /// Batch enqueue performs one coordinated JSON rewrite for a burst of
    /// operations and keeps only the latest desired state per task.
    @discardableResult
    func enqueue(
        _ newOperations: [PendingTaskOperation]
    ) throws -> [PendingTaskOperation] {
        var durable: [PendingTaskOperation] = []
        try coordinatedQueueUpdate { queue in
            for operation in newOperations {
                if let sameID = queue.operations.first(where: { $0.id == operation.id }) {
                    durable.append(sameID)
                    continue
                }
                if let existing = queue.operations.first(where: {
                    $0.taskIdentity == operation.taskIdentity
                        && $0.desiredCompletion == operation.desiredCompletion
                }) {
                    durable.append(existing)
                    continue
                }
                queue.operations.removeAll {
                    $0.taskIdentity == operation.taskIdentity
                }
                guard queue.operations.count < Self.maximumPendingOperations else {
                    throw WidgetStoreError.queueCapacityReached(
                        limit: Self.maximumPendingOperations)
                }
                queue.operations.append(operation)
                durable.append(operation)
            }
        }
        return durable
    }

    func acknowledge(operationID: UUID) throws {
        _ = try applyQueueResolutions([.acknowledge(operationID)])
    }

    /// Applies all drain outcomes in one coordinated rewrite. Exhausted
    /// operations become durable receipts instead of disappearing silently.
    @discardableResult
    func applyQueueResolutions(
        _ resolutions: [WidgetQueueResolution],
        maxAttempts: Int = PendingTaskOperation.maxAttempts,
        now: Date = Date()
    ) throws -> WidgetQueueBatchResult {
        var acknowledged = 0
        var retained = 0
        var failedPermanently = 0
        var pendingCount = 0
        var queueAtCapacity = false
        try coordinatedQueueUpdate { queue in
            for resolution in resolutions {
                switch resolution {
                case .acknowledge(let id):
                    let oldCount = queue.operations.count
                    queue.operations.removeAll { $0.id == id }
                    if queue.operations.count != oldCount { acknowledged += 1 }
                case .recordFailure(let id, let reason):
                    guard let index = queue.operations.firstIndex(where: { $0.id == id })
                    else { continue }
                    queue.operations[index].attemptCount += 1
                    let operation = queue.operations[index]
                    if operation.attemptCount >= maxAttempts {
                        queue.operations.remove(at: index)
                        if !queue.failureReceipts.contains(where: {
                            $0.operationID == operation.id
                        }) {
                            queue.failureReceipts.append(
                                WidgetOperationFailureReceipt(
                                    id: UUID(),
                                    operationID: operation.id,
                                    taskFingerprint: operation.taskFingerprint,
                                    desiredCompletion: operation.desiredCompletion,
                                    attempts: operation.attemptCount,
                                    failedAt: now,
                                    reason: reason))
                        }
                        failedPermanently += 1
                    } else {
                        retained += 1
                    }
                }
            }
            pendingCount = queue.operations.count
            queueAtCapacity =
                queue.operations.count >= Self.maximumPendingOperations
        }
        return WidgetQueueBatchResult(
            acknowledgedCount: acknowledged,
            retainedCount: retained,
            failedPermanentlyCount: failedPermanently,
            pendingCount: pendingCount,
            queueAtCapacity: queueAtCapacity)
    }

    @discardableResult
    func recordFailure(
        operationID: UUID,
        maxAttempts: Int = PendingTaskOperation.maxAttempts
    ) throws -> Bool {
        try applyQueueResolutions(
            [.recordFailure(operationID, .retryLimitExceeded)],
            maxAttempts: maxAttempts
        ).failedPermanentlyCount > 0
    }

    func acknowledgeFailureReceipts(ids: Set<UUID>) throws {
        try coordinatedQueueUpdate { queue in
            queue.failureReceipts.removeAll { ids.contains($0.id) }
        }
    }

    /// Called only after the user has seen/handled the Settings warning.
    func acknowledgeAllFailureHistory() throws {
        try coordinatedQueueUpdate { queue in
            queue.failureReceipts.removeAll()
            queue.discardedFailureReceiptCount = 0
        }
    }

    func replace(_ operations: [PendingTaskOperation]) throws {
        guard operations.count <= Self.maximumPendingOperations else {
            throw WidgetStoreError.queueCapacityReached(
                limit: Self.maximumPendingOperations)
        }
        try coordinatedQueueUpdate {
            $0.operations = operations
        }
    }

    // MARK: - Health

    func health() -> WidgetChannelHealth {
        guard containerURL != nil else {
            return WidgetChannelHealth(
                state: .unavailable,
                pendingOperationCount: 0,
                failedOperationCount: 0,
                discardedFailureReceiptCount: 0,
                pendingQueueAtCapacity: false,
                legacyMigrationCleanupPending: false,
                snapshotAvailability: nil,
                error: .appGroupUnavailable)
        }

        let snapshotResult = readSnapshotResult()
        do {
            let queue = try loadQueueMigratingIfNeeded()
            let queueAtCapacity =
                queue.operations.count >= Self.maximumPendingOperations
            let queueNeedsAttention =
                !queue.failureReceipts.isEmpty
                || queue.discardedFailureReceiptCount > 0
                || queueAtCapacity
                || queue.legacyCleanupPending
            switch snapshotResult {
            case .success(let snapshot):
                let snapshotNeedsAttention = snapshot.availability != .available
                return WidgetChannelHealth(
                    state: queueNeedsAttention || snapshotNeedsAttention
                        ? .needsAttention : .ready,
                    pendingOperationCount: queue.operations.count,
                    failedOperationCount: queue.failureReceipts.count,
                    discardedFailureReceiptCount: queue.discardedFailureReceiptCount,
                    pendingQueueAtCapacity: queueAtCapacity,
                    legacyMigrationCleanupPending: queue.legacyCleanupPending,
                    snapshotAvailability: snapshot.availability,
                    error: nil)
            case .failure(.artifactMissing):
                return WidgetChannelHealth(
                    state: queueNeedsAttention ? .needsAttention : .notPublished,
                    pendingOperationCount: queue.operations.count,
                    failedOperationCount: queue.failureReceipts.count,
                    discardedFailureReceiptCount: queue.discardedFailureReceiptCount,
                    pendingQueueAtCapacity: queueAtCapacity,
                    legacyMigrationCleanupPending: queue.legacyCleanupPending,
                    snapshotAvailability: nil,
                    error: nil)
            case .failure(let error):
                return WidgetChannelHealth(
                    state: .needsAttention,
                    pendingOperationCount: queue.operations.count,
                    failedOperationCount: queue.failureReceipts.count,
                    discardedFailureReceiptCount: queue.discardedFailureReceiptCount,
                    pendingQueueAtCapacity: queueAtCapacity,
                    legacyMigrationCleanupPending: queue.legacyCleanupPending,
                    snapshotAvailability: nil,
                    error: error)
            }
        } catch {
            return WidgetChannelHealth(
                state: .needsAttention,
                pendingOperationCount: 0,
                failedOperationCount: 0,
                discardedFailureReceiptCount: 0,
                pendingQueueAtCapacity: false,
                legacyMigrationCleanupPending: false,
                snapshotAvailability: try? snapshotResult.get().availability,
                error: storeError(error, artifact: .operationQueue, writing: false))
        }
    }

    // MARK: - Coordinated internals

    private func coordinatedSnapshotUpdate(
        requireExisting: Bool,
        _ transform: (TodaySnapshot?) throws -> TodaySnapshot
    ) throws -> TodaySnapshot {
        guard let url = snapshotURL else { throw WidgetStoreError.appGroupUnavailable }
        return try FileCoordination.write(at: url, options: .forMerging) { coordinatedURL in
            let previous: TodaySnapshot?
            if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                let data = try Data(contentsOf: coordinatedURL)
                do {
                    previous = try decodeSnapshot(data)
                } catch let error as WidgetStoreError {
                    if case .unsupportedSchema(_, let found, let supported) = error,
                        found > supported
                    {
                        // Never let an older app overwrite state produced by
                        // a newer schema it cannot interpret.
                        throw error
                    }
                    guard !requireExisting else { throw error }
                    try preserveUnreadableSnapshot(data)
                    previous = nil
                } catch {
                    guard !requireExisting else { throw error }
                    try preserveUnreadableSnapshot(data)
                    previous = nil
                }
            } else {
                guard !requireExisting else {
                    throw WidgetStoreError.artifactMissing(.snapshot)
                }
                previous = nil
            }
            var updated = try transform(previous)
            updated.schemaVersion = TodaySnapshot.currentSchemaVersion
            updated.revision = (previous?.revision ?? 0) &+ 1
            let data = try JSONEncoder().encode(updated)
            try writeProtected(data, to: coordinatedURL)
            return updated
        }
    }

    private func decodeSnapshot(_ data: Data) throws -> TodaySnapshot {
        try JSONDecoder().decode(TodaySnapshot.self, from: data)
    }

    /// The snapshot is derived and can be rebuilt, but retaining the damaged
    /// bytes makes a repair auditable. One stable backup avoids unbounded
    /// private-container growth if storage keeps failing.
    private func preserveUnreadableSnapshot(_ data: Data) throws {
        guard let url = unreadableSnapshotBackupURL else {
            throw WidgetStoreError.appGroupUnavailable
        }
        guard !FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try writeProtected(data, to: url)
    }

    private func loadQueueMigratingIfNeeded() throws -> PendingTaskOperationQueue {
        guard let url = pendingOperationsURL else {
            throw WidgetStoreError.appGroupUnavailable
        }
        if FileManager.default.fileExists(atPath: url.path) {
            let queue = try coordinatedQueueRead(at: url)
            if queue.legacyCleanupPending {
                do {
                    try finishLegacyQueueCleanup()
                    return try coordinatedQueueRead(at: url)
                } catch {
                    log(error, message: "Legacy queue cleanup still pending")
                    return queue
                }
            }
            return queue
        }
        guard let legacyURL = legacyPendingTogglesURL,
            FileManager.default.fileExists(atPath: legacyURL.path)
        else { return PendingTaskOperationQueue() }

        let migrated = try FileCoordination.read(at: legacyURL) {
            try JSONDecoder().decode(
                [PendingToggle].self,
                from: Data(contentsOf: $0)
            )
            .map(\.pendingOperation)
        }
        try coordinatedQueueUpdate {
            $0.operations = migrated
            $0.legacyCleanupPending = true
        }
        do {
            try finishLegacyQueueCleanup()
        } catch {
            // The migrated operations are already durable. Preserve the flag
            // for health and a later cleanup retry instead of hiding failure.
            log(error, message: "Legacy queue cleanup deferred")
        }
        return try coordinatedQueueRead(at: url)
    }

    private func finishLegacyQueueCleanup() throws {
        guard let legacyURL = legacyPendingTogglesURL else {
            throw WidgetStoreError.appGroupUnavailable
        }
        if FileManager.default.fileExists(atPath: legacyURL.path) {
            try FileCoordination.write(
                at: legacyURL,
                options: .forDeleting
            ) { coordinatedURL in
                try FileManager.default.removeItem(at: coordinatedURL)
            }
        }
        try coordinatedQueueUpdate {
            $0.legacyCleanupPending = false
        }
    }

    private func coordinatedQueueRead(
        at url: URL
    ) throws -> PendingTaskOperationQueue {
        try FileCoordination.read(at: url) {
            try decodeQueue(Data(contentsOf: $0))
        }
    }

    private func coordinatedQueueUpdate(
        _ transform: (inout PendingTaskOperationQueue) throws -> Void
    ) throws {
        guard let url = pendingOperationsURL else {
            throw WidgetStoreError.appGroupUnavailable
        }
        try FileCoordination.write(at: url, options: .forMerging) { coordinatedURL in
            var queue = PendingTaskOperationQueue()
            if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                queue = try decodeQueue(Data(contentsOf: coordinatedURL))
            }
            try transform(&queue)
            // Failure history is user-visible health, but it cannot grow
            // without bound. Retain the newest receipts deterministically
            // and keep an explicit count of older history compacted away.
            queue.failureReceipts.sort {
                if $0.failedAt != $1.failedAt {
                    return $0.failedAt < $1.failedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            if queue.failureReceipts.count > Self.maximumFailureReceipts {
                let overflow =
                    queue.failureReceipts.count - Self.maximumFailureReceipts
                queue.failureReceipts.removeFirst(overflow)
                queue.discardedFailureReceiptCount += overflow
            }
            queue.schemaVersion = PendingTaskOperationQueue.currentSchemaVersion
            try writeProtected(
                JSONEncoder().encode(queue),
                to: coordinatedURL)
        }
    }

    private func decodeQueue(_ data: Data) throws -> PendingTaskOperationQueue {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = object["schemaVersion"] as? Int
        {
            guard (1...PendingTaskOperationQueue.currentSchemaVersion).contains(version) else {
                throw WidgetStoreError.unsupportedSchema(
                    artifact: .operationQueue,
                    found: version,
                    supported: PendingTaskOperationQueue.currentSchemaVersion)
            }
            return try JSONDecoder().decode(PendingTaskOperationQueue.self, from: data)
        }

        // Pre-envelope v2 was a raw array.
        let operations = try JSONDecoder().decode([PendingTaskOperation].self, from: data)
        return PendingTaskOperationQueue(operations: operations)
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path)
        #endif
        // Atomic rename prevents torn JSON; synchronizing the replacement
        // closes the additional power-loss window where the latest tap exists
        // only in the filesystem cache.
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
    }

    private func storeError(
        _ error: Error,
        artifact: WidgetStoreArtifact,
        writing: Bool
    ) -> WidgetStoreError {
        if let error = error as? WidgetStoreError { return error }
        return writing ? .writeFailed(artifact) : .readFailed(artifact)
    }

    private func log(_ error: Error, message: StaticString) {
        widgetChannelLogger.error(
            "\(message): \(error.localizedDescription, privacy: .private)")
    }
}
