import Foundation

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
/// * `pending-toggles.json` — toggles the widget could not apply itself,
///   drained by the app on its next refresh.
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
    static var pendingTogglesURL: URL? {
        containerURL?.appendingPathComponent("pending-toggles.json")
    }
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
    static func building(for now: Date, from allTasks: [TaskItem]) -> TodaySnapshot {
        let dayString = QuickTaskParser.ymdString(from: now)
        return TodaySnapshot(dayString: dayString,
                             generatedAt: now,
                             tasks: tasks(dueToday: dayString, from: allTasks))
    }

    /// The snapshot as of `now`, emptied if it was built for another day.
    func valid(at now: Date) -> TodaySnapshot {
        dayString == QuickTaskParser.ymdString(from: now) ? self : .empty
    }
}

/// One toggle the widget applied to its snapshot but could not write to disk,
/// waiting for the app to apply it for real.
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

/// Reads and writes the shared files. Both processes use this one type so the
/// file names and the JSON shape can't drift apart.
struct WidgetSnapshotStore: Sendable {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {}

    // MARK: - Snapshot

    func writeSnapshot(_ snapshot: TodaySnapshot) {
        guard let url = CoveSharedContainer.snapshotURL,
              let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func readSnapshot() -> TodaySnapshot {
        guard let url = CoveSharedContainer.snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(TodaySnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    // MARK: - Bookmark

    func writeBookmark(_ data: Data) {
        guard let url = CoveSharedContainer.bookmarkURL else { return }
        try? data.write(to: url, options: .atomic)
    }

    func readBookmark() -> Data? {
        CoveSharedContainer.bookmarkURL.flatMap { try? Data(contentsOf: $0) }
    }

    // MARK: - Pending toggles

    func appendPendingToggle(_ toggle: PendingToggle) {
        var pending = readPendingToggles()
        guard !pending.contains(toggle) else { return }
        pending.append(toggle)
        writePendingToggles(pending)
    }

    func readPendingToggles() -> [PendingToggle] {
        guard let url = CoveSharedContainer.pendingTogglesURL,
              let data = try? Data(contentsOf: url),
              let pending = try? decoder.decode([PendingToggle].self, from: data)
        else { return [] }
        return pending
    }

    func writePendingToggles(_ pending: [PendingToggle]) {
        guard let url = CoveSharedContainer.pendingTogglesURL else { return }
        if pending.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? encoder.encode(pending) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clearPendingToggles() {
        writePendingToggles([])
    }
}
