import Foundation

/// Calendar semantics for Cove's fixed Markdown date format. Stored
/// `YYYY-MM-DD` values are Gregorian regardless of the user's system calendar.
enum TaskCalendar {
    static func gregorian(timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func nextMidnight(after date: Date,
                             calendar: Calendar = gregorian()) -> Date {
        let calendar = gregorian(timeZone: calendar.timeZone)
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start)!
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

    var fileURL: URL { URL(fileURLWithPath: filePath) }
    var recurrence: RecurrenceRule? { recurrenceTag.flatMap(RecurrenceRule.init(tagText:)) }

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

    init(filePath: String,
         lineNumber: Int,
         text: String,
         dueDateString: String?,
         dueTimeString: String?,
         recurrenceTag: String?,
         listName: String?) {
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.text = text
        self.dueDateString = dueDateString
        self.dueTimeString = dueTimeString
        self.recurrenceTag = recurrenceTag
        self.listName = listName
    }

    init(_ task: TaskItem) {
        self.init(filePath: task.fileURL.path,
                  lineNumber: task.lineNumber,
                  text: task.text,
                  dueDateString: task.dueDateString,
                  dueTimeString: task.dueTimeString,
                  recurrenceTag: task.recurrence?.tagText,
                  listName: task.listName)
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
    let isCompleted: Bool
    /// The list this task belongs to, for tasks under a `##` heading in the
    /// capture note. Nil for an ordinary task, which is what the Tasks
    /// screen shows.
    let listName: String?

    var id: String { "\(fileURL.path)#\(lineNumber)" }

    var identity: TaskIdentity { TaskIdentity(self) }

    var hasDueDate: Bool { dueDateString != nil }

    /// Start of the due day in Cove's Gregorian task calendar.
    var dueDate: Date? {
        dueDate(in: TaskCalendar.gregorian())
    }

    func dueDate(in calendar: Calendar) -> Date? {
        let calendar = TaskCalendar.gregorian(timeZone: calendar.timeZone)
        return dateComponents.flatMap(calendar.date(from:))
    }

    /// The due moment including the time of day, when a time is set.
    var dueDateTime: Date? {
        dueDateTime(in: TaskCalendar.gregorian())
    }

    func dueDateTime(in calendar: Calendar) -> Date? {
        guard var components = dateComponents, let time = timeComponents else { return nil }
        (components.hour, components.minute) = time
        return TaskCalendar.gregorian(timeZone: calendar.timeZone).date(from: components)
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
        let parts = dueTimeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
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
    let modificationDate: Date?
    let fileSize: Int?

    init(url: URL,
         title: String,
         tasks: [TaskItem],
         listNames: [String] = [],
         modificationDate: Date? = nil,
         fileSize: Int? = nil) {
        self.url = url
        self.title = title
        self.tasks = tasks
        self.listNames = listNames
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

    var id: String { name }
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
            $0.listName!
        }
        return listNames.map { name in
            let tasks = tasksByList[name] ?? []
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
