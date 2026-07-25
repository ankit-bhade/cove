import Foundation

/// Calendar semantics for Cove's fixed Markdown date format. Stored
/// `YYYY-MM-DD` values are Gregorian regardless of the user's system calendar.
///
/// Date-handling APIs across the app therefore take a **time zone**, not a
/// calendar. They used to take a `Calendar` and immediately rebuild it as
/// Gregorian with the incoming one's time zone — correct, but a signature that
/// asked for something it then discarded, so a caller passing a Hebrew or
/// Buddhist calendar was silently overridden with nothing saying so. The zone
/// is the only part that was ever honored, and now it is the only part asked
/// for.
enum TaskCalendar {
    enum NonexistentTimePolicy: Equatable, Sendable {
        case reject
        case nextValidTime
    }

    enum RepeatedTimePolicy: Equatable, Sendable {
        case reject
        case first
        case last
    }

    enum ResolutionKind: Equatable, Sendable {
        case exact
        case shiftedForward
        case firstRepeatedTime
        case lastRepeatedTime
    }

    struct Resolution: Equatable, Sendable {
        let date: Date
        let kind: ResolutionKind
    }

    enum ResolutionError: LocalizedError, Equatable, Sendable {
        case invalidDate(String)
        case invalidTime(String)
        case nonexistentLocalTime(date: String, time: String)
        case repeatedLocalTime(date: String, time: String)

        var errorDescription: String? {
            switch self {
            case .invalidDate(let date):
                return "The date \(date) does not exist."
            case .invalidTime(let time):
                return "The time \(time) is not a valid 24-hour time."
            case .nonexistentLocalTime(let date, let time):
                return "\(date) at \(time) does not exist in this time zone because the clock moves forward."
            case .repeatedLocalTime(let date, let time):
                return "\(date) at \(time) occurs twice in this time zone because the clock moves backward."
            }
        }
    }

    static func gregorian(timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func nextMidnight(
        after date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Date {
        let calendar = gregorian(timeZone: timeZone)
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start)!
    }

    /// Resolves a stored wall-clock date and time with explicit DST policy.
    /// Foundation's plain `Calendar.date(from:)` silently normalizes missing
    /// times and silently chooses one copy of repeated times; task reminders
    /// should make both decisions deliberately.
    static func resolve(
        date dateString: String,
        time timeString: String,
        timeZone: TimeZone = .autoupdatingCurrent,
        nonexistentTime: NonexistentTimePolicy = .nextValidTime,
        repeatedTime: RepeatedTimePolicy = .first
    ) -> Result<Resolution, ResolutionError> {
        let calendar = gregorian(timeZone: timeZone)
        guard let dateParts = dateComponents(from: dateString),
            dateParts.isValidDate(in: calendar),
            let noon = calendar.date(
                from: DateComponents(
                    year: dateParts.year,
                    month: dateParts.month,
                    day: dateParts.day,
                    hour: 12))
        else { return .failure(.invalidDate(dateString)) }
        guard let timeParts = timeComponents(from: timeString) else {
            return .failure(.invalidTime(timeString))
        }

        let components = DateComponents(
            year: dateParts.year,
            month: dateParts.month,
            day: dateParts.day,
            hour: timeParts.hour,
            minute: timeParts.minute)
        let start = calendar.startOfDay(for: noon)
        let searchStart = calendar.date(byAdding: .second, value: -1, to: start)!

        func strict(_ policy: Calendar.RepeatedTimePolicy) -> Date? {
            calendar.nextDate(
                after: searchStart,
                matching: components,
                matchingPolicy: .strict,
                repeatedTimePolicy: policy,
                direction: .forward
            ).flatMap { sameWallClock($0, as: components, calendar: calendar) ? $0 : nil }
        }

        let first = strict(.first)
        let last = strict(.last)
        if let first, let last {
            if first == last { return .success(Resolution(date: first, kind: .exact)) }
            switch repeatedTime {
            case .reject:
                return .failure(
                    .repeatedLocalTime(date: dateString, time: timeString))
            case .first:
                return .success(Resolution(date: first, kind: .firstRepeatedTime))
            case .last:
                return .success(Resolution(date: last, kind: .lastRepeatedTime))
            }
        }

        guard nonexistentTime == .nextValidTime,
            let shifted = calendar.nextDate(
                after: searchStart,
                matching: components,
                matchingPolicy: .nextTimePreservingSmallerComponents,
                repeatedTimePolicy: .first,
                direction: .forward),
            sameDay(shifted, as: components, calendar: calendar)
        else {
            return .failure(
                .nonexistentLocalTime(date: dateString, time: timeString))
        }
        return .success(Resolution(date: shifted, kind: .shiftedForward))
    }

    static func dateComponents(from string: String) -> DateComponents? {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2,
            parts[2].count == 2, let year = Int(parts[0]), let month = Int(parts[1]),
            let day = Int(parts[2])
        else { return nil }
        return DateComponents(year: year, month: month, day: day)
    }

    static func timeComponents(from string: String) -> (hour: Int, minute: Int)? {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
            let hour = Int(parts[0]), let minute = Int(parts[1]),
            (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return (hour, minute)
    }

    private static func sameWallClock(
        _ date: Date,
        as components: DateComponents,
        calendar: Calendar
    ) -> Bool {
        let actual = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date)
        return actual.year == components.year
            && actual.month == components.month
            && actual.day == components.day
            && actual.hour == components.hour
            && actual.minute == components.minute
    }

    private static func sameDay(
        _ date: Date,
        as components: DateComponents,
        calendar: Calendar
    ) -> Bool {
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == components.year
            && actual.month == components.month
            && actual.day == components.day
    }
}

/// Stable, serializable task identity used to re-find a line after re-reading
/// its latest note contents. Completion is intentionally not identity: a
/// semantic set-completed operation must still find a task after another
/// caller has already put it in the desired state.
struct TaskIdentity: Codable, Hashable, Sendable {
    let filePath: String
    let lineNumber: Int
    let text: String
    let dueDateString: String?
    let dueTimeString: String?
    let recurrenceTag: String?
    let listName: String?
    /// Original recurrence-series anchor. Optional for identities decoded
    /// from pre-anchor widget snapshots and for non-recurring tasks.
    let recurrenceAnchorDateString: String?
    let isSectionedDocument: Bool

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var recurrence: RecurrenceRule? { recurrenceTag.flatMap(RecurrenceRule.init(tagText:)) }

    /// Canonical grouping key for list comparisons. The displayed spelling
    /// remains untouched, while case/diacritic-only external renames do not
    /// make an otherwise identical task impossible to re-find.
    var canonicalListName: String? { listName.map(TaskListDocument.canonicalName) }

    /// Legacy snapshots did not store this bit. A file named `Tasks.md` is
    /// conservatively parsed as sectioned so an unlisted task can never match
    /// an identical task under a list heading.
    var requiresSectionedParsing: Bool {
        isSectionedDocument
            || listName != nil
            || fileURL.lastPathComponent.caseInsensitiveCompare("Tasks.md") == .orderedSame
    }

    /// The note to mutate, but only when the recorded path still resolves
    /// inside `vaultRoot`. An identity is persisted state: it crosses the App
    /// Group to the widget and back, and it can outlive the vault it was
    /// written against — a queued toggle survives the user picking a
    /// different folder. So a write validates the path against the vault it
    /// is about to open rather than trusting the string, and holds it to the
    /// same rules the scanner uses: inside the vault, a Markdown file,
    /// nothing hidden or symlinked on the way in.
    func fileURL(within vaultRoot: URL) -> URL? {
        let url = fileURL.standardizedFileURL
        guard url.pathExtension.lowercased() == "md" else { return nil }
        let resolved = url.resolvingSymlinksInPath().pathComponents
        let root = vaultRoot.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard resolved.count > root.count,
            Array(resolved.prefix(root.count)) == root,
            !resolved.dropFirst(root.count).contains(where: { $0.hasPrefix(".") })
        else { return nil }
        return url
    }

    init(
        filePath: String,
        lineNumber: Int,
        text: String,
        dueDateString: String?,
        dueTimeString: String?,
        recurrenceTag: String?,
        listName: String?,
        recurrenceAnchorDateString: String? = nil,
        isSectionedDocument: Bool = false
    ) {
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.text = text
        self.dueDateString = dueDateString
        self.dueTimeString = dueTimeString
        self.recurrenceTag = recurrenceTag
        self.listName = listName
        self.recurrenceAnchorDateString = recurrenceAnchorDateString
        self.isSectionedDocument = isSectionedDocument
    }

    init(_ task: TaskItem) {
        self.init(
            filePath: task.fileURL.path,
            lineNumber: task.lineNumber,
            text: task.text,
            dueDateString: task.dueDateString,
            dueTimeString: task.dueTimeString,
            recurrenceTag: task.recurrence?.tagText,
            listName: task.listName,
            recurrenceAnchorDateString: task.recurrenceAnchorDateString,
            isSectionedDocument: task.isSectionedDocument)
    }

    private enum CodingKeys: String, CodingKey {
        case filePath
        case lineNumber
        case text
        case dueDateString
        case dueTimeString
        case recurrenceTag
        case listName
        case recurrenceAnchorDateString
        case isSectionedDocument
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            filePath: try values.decode(String.self, forKey: .filePath),
            lineNumber: try values.decode(Int.self, forKey: .lineNumber),
            text: try values.decode(String.self, forKey: .text),
            dueDateString: try values.decodeIfPresent(String.self, forKey: .dueDateString),
            dueTimeString: try values.decodeIfPresent(String.self, forKey: .dueTimeString),
            recurrenceTag: try values.decodeIfPresent(String.self, forKey: .recurrenceTag),
            listName: try values.decodeIfPresent(String.self, forKey: .listName),
            recurrenceAnchorDateString: try values.decodeIfPresent(
                String.self, forKey: .recurrenceAnchorDateString),
            isSectionedDocument:
                try values.decodeIfPresent(Bool.self, forKey: .isSectionedDocument)
                ?? false)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(filePath, forKey: .filePath)
        try values.encode(lineNumber, forKey: .lineNumber)
        try values.encode(text, forKey: .text)
        try values.encodeIfPresent(dueDateString, forKey: .dueDateString)
        try values.encodeIfPresent(dueTimeString, forKey: .dueTimeString)
        try values.encodeIfPresent(recurrenceTag, forKey: .recurrenceTag)
        try values.encodeIfPresent(listName, forKey: .listName)
        try values.encodeIfPresent(
            recurrenceAnchorDateString, forKey: .recurrenceAnchorDateString)
        try values.encode(isSectionedDocument, forKey: .isSectionedDocument)
    }
}

/// One due task collected from a note, carrying enough to display it and to
/// re-find its line when toggling. Ranges are deliberately absent: the file
/// is re-read and re-parsed at toggle time, so nothing here goes stale.
struct TaskItem: Identifiable, Hashable, Sendable {
    let fileURL: URL
    /// Title of the containing note (file name without `.md`).
    let fileTitle: String
    /// 0-based line index at the time the index was built.
    let lineNumber: Int
    /// The task text between the marker and the `@due` tag.
    let text: String
    /// Validated `YYYY-MM-DD`; lexicographic order is chronological order.
    /// Nil only for an undated item in a list, where `@due` is optional.
    let dueDateString: String?
    /// Validated 24-hour `HH:MM` when the task carries a time; only timed
    /// tasks get notifications.
    let dueTimeString: String?
    let recurrence: RecurrenceRule?
    let recurrenceAnchorDateString: String?
    let isSectionedDocument: Bool
    /// Original task line, including its line ending, captured during indexing.
    /// Keeping it lets a delete Undo restore the user's bullet, indentation,
    /// spacing, and CRLF convention instead of reconstructing normalized text.
    let sourceLine: String?
    let isCompleted: Bool
    /// The list this task belongs to, for tasks under a `##` heading in the
    /// capture note. Nil for an ordinary task, which is what the Tasks
    /// screen shows.
    let listName: String?

    init(
        fileURL: URL,
        fileTitle: String,
        lineNumber: Int,
        text: String,
        dueDateString: String?,
        dueTimeString: String?,
        recurrence: RecurrenceRule?,
        isCompleted: Bool,
        listName: String?,
        recurrenceAnchorDateString: String? = nil,
        isSectionedDocument: Bool = false,
        sourceLine: String? = nil
    ) {
        self.fileURL = fileURL
        self.fileTitle = fileTitle
        self.lineNumber = lineNumber
        self.text = text
        self.dueDateString = dueDateString
        self.dueTimeString = dueTimeString
        self.recurrence = recurrence
        self.recurrenceAnchorDateString = recurrenceAnchorDateString
        self.isSectionedDocument = isSectionedDocument
        self.sourceLine = sourceLine
        self.isCompleted = isCompleted
        self.listName = listName
    }

    var id: String { "\(fileURL.path)#\(lineNumber)" }

    var identity: TaskIdentity { TaskIdentity(self) }

    var hasDueDate: Bool { dueDateString != nil }

    /// Start of the due day in Cove's Gregorian task calendar.
    var dueDate: Date? {
        dueDate(in: .autoupdatingCurrent)
    }

    func dueDate(in timeZone: TimeZone) -> Date? {
        guard let components = dateComponents,
            components.isValidDate(in: TaskCalendar.gregorian(timeZone: timeZone))
        else { return nil }
        return TaskCalendar.gregorian(timeZone: timeZone).date(from: components)
    }

    /// The due moment including the time of day, when a time is set.
    var dueDateTime: Date? {
        dueDateTime(in: .autoupdatingCurrent)
    }

    func dueDateTime(in timeZone: TimeZone) -> Date? {
        guard let resolution = dueDateTimeResolution(in: timeZone) else { return nil }
        return try? resolution.get().date
    }

    /// Typed resolution for callers that can surface an invalid/nonexistent
    /// wall-clock time rather than silently dropping it. Cove rejects spring
    /// DST-gap times and consistently chooses the first copy of a repeated
    /// fall-back time.
    func dueDateTimeResolution(
        in timeZone: TimeZone
    ) -> Result<TaskCalendar.Resolution, TaskCalendar.ResolutionError>? {
        guard let dueDateString, let dueTimeString else { return nil }
        return TaskCalendar.resolve(
            date: dueDateString,
            time: dueTimeString,
            timeZone: timeZone,
            nonexistentTime: .reject,
            repeatedTime: .first
        )
    }

    private var dateComponents: DateComponents? {
        guard let dueDateString else { return nil }
        let parts = dueDateString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Parsed `(hour, minute)` of `dueTimeString`, when present.
    var timeComponents: (hour: Int, minute: Int)? {
        guard let dueTimeString else { return nil }
        return TaskCalendar.timeComponents(from: dueTimeString)
    }
}

/// One indexed note: its path, title, and due tasks. Deliberately not its
/// contents — search re-reads from disk by design (no persisted index), so
/// holding the text here would keep a copy of the whole vault in memory that
/// nothing ever reads. The modification date and size are what let an
/// unchanged note reuse its entry across an incremental rebuild.
struct NoteIndexEntry: Hashable, Sendable {
    let url: URL
    let title: String
    let tasks: [TaskItem]
    let listNames: [String]
    /// Malformed/ambiguous task syntax discovered without modifying the note.
    /// UI can surface these instead of silently omitting task-looking lines.
    let taskDiagnostics: [TaskParser.Diagnostic]
    /// A transient read/indexing failure. A last-known-good task projection may
    /// still be present, but the UI can disclose that it is stale.
    let indexingErrorDescription: String?
    let modificationDate: Date?
    let fileSize: Int?

    init(
        url: URL,
        title: String,
        tasks: [TaskItem],
        listNames: [String] = [],
        taskDiagnostics: [TaskParser.Diagnostic] = [],
        indexingErrorDescription: String? = nil,
        modificationDate: Date? = nil,
        fileSize: Int? = nil
    ) {
        self.url = url
        self.title = title
        self.tasks = tasks
        self.listNames = listNames
        self.taskDiagnostics = taskDiagnostics
        self.indexingErrorDescription = indexingErrorDescription
        self.modificationDate = modificationDate
        self.fileSize = fileSize
    }
}

/// One named list from the capture note: its `##` heading and the tasks
/// under it. A list with no items still exists, so it is built from the
/// note's headings rather than inferred from the tasks.
struct TaskList: Identifiable, Hashable, Sendable {
    let name: String
    /// Incomplete items, dated ones first in due order, undated after in
    /// the order they were added.
    let openTasks: [TaskItem]
    let completedTasks: [TaskItem]

    var id: String { TaskListDocument.canonicalName(name) }
    var isEmpty: Bool { openTasks.isEmpty && completedTasks.isEmpty }
}

/// The in-memory index of the vault, rebuilt from disk on launch and after
/// detected or app-created file changes. Never persisted.
struct VaultIndex: Sendable {
    var entries: [NoteIndexEntry] = []
    /// The `##` list headings in the capture note, in file order. Held
    /// separately so a list the user created but hasn't filled yet is still
    /// a list.
    var listNames: [String] = []

    var allTasks: [TaskItem] { entries.flatMap(\.tasks) }

    var taskDiagnostics: [(fileURL: URL, diagnostic: TaskParser.Diagnostic)] {
        entries.flatMap { entry in
            entry.taskDiagnostics.map { (entry.url, $0) }
        }
    }

    var indexingFailures: [(fileURL: URL, description: String)] {
        entries.compactMap { entry in
            entry.indexingErrorDescription.map { (entry.url, $0) }
        }
    }

    /// Incomplete tasks sorted by due date, then time (date-only tasks
    /// first within a day), then note title and line. List tasks are
    /// excluded: the Lists screen keeps them visually separate.
    var incompleteTasks: [TaskItem] {
        allTasks.filter { !$0.isCompleted && $0.listName == nil }.sorted(by: Self.byDueDate)
    }

    /// Completed tasks in the same order, for display below the open ones.
    var completedTasks: [TaskItem] {
        allTasks.filter { $0.isCompleted && $0.listName == nil }.sorted(by: Self.byDueDate)
    }

    /// Every list in the capture note, heading order preserved.
    var lists: [TaskList] {
        let tasksByList = Dictionary(grouping: allTasks.filter { $0.listName != nil }) {
            TaskListDocument.canonicalName($0.listName!)
        }
        return listNames.map { name in
            let tasks = tasksByList[TaskListDocument.canonicalName(name)] ?? []
            return TaskList(
                name: name,
                openTasks: tasks.filter { !$0.isCompleted }.sorted(by: Self.byDueDate),
                completedTasks: tasks.filter(\.isCompleted).sorted(by: Self.byDueDate))
        }
    }

    /// Undated tasks sort after every dated one: the sentinel is past any
    /// real zero-padded date, so a list reads "what's scheduled, then the
    /// rest in the order I added it".
    static func byDueDate(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        (lhs.dueDateString ?? "9999-99-99", lhs.dueTimeString ?? "", lhs.fileTitle, lhs.lineNumber)
            < (rhs.dueDateString ?? "9999-99-99", rhs.dueTimeString ?? "", rhs.fileTitle, rhs.lineNumber)
    }
}
