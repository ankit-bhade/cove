import Foundation

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
    let dueDateString: String
    /// Validated 24-hour `HH:MM` when the task carries a time; only timed
    /// tasks get notifications.
    let dueTimeString: String?
    let recurrence: RecurrenceRule?
    let isCompleted: Bool

    var id: String { "\(fileURL.path)#\(lineNumber)" }

    /// Start of the due day in the current calendar, for display formatting.
    var dueDate: Date? {
        dateComponents.flatMap(Calendar.current.date(from:))
    }

    /// The due moment including the time of day, when a time is set.
    var dueDateTime: Date? {
        guard var components = dateComponents, let time = timeComponents else { return nil }
        (components.hour, components.minute) = time
        return Calendar.current.date(from: components)
    }

    private var dateComponents: DateComponents? {
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

/// One indexed note: its path, title, and due tasks.
struct NoteIndexEntry: Hashable, Sendable {
    let url: URL
    let title: String
    let tasks: [TaskItem]
}

/// The in-memory index of the vault, rebuilt from disk on launch and after
/// detected or app-created file changes. Never persisted.
struct VaultIndex: Sendable {
    var entries: [NoteIndexEntry] = []

    var allTasks: [TaskItem] { entries.flatMap(\.tasks) }

    /// Incomplete tasks sorted by due date, then time (date-only tasks
    /// first within a day), then note title and line.
    var incompleteTasks: [TaskItem] {
        allTasks.filter { !$0.isCompleted }.sorted(by: Self.byDueDate)
    }

    /// Completed tasks in the same order, for display below the open ones.
    var completedTasks: [TaskItem] {
        allTasks.filter(\.isCompleted).sorted(by: Self.byDueDate)
    }

    static func byDueDate(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        (lhs.dueDateString, lhs.dueTimeString ?? "", lhs.fileTitle, lhs.lineNumber)
            < (rhs.dueDateString, rhs.dueTimeString ?? "", rhs.fileTitle, rhs.lineNumber)
    }
}
