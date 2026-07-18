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
    let isCompleted: Bool

    var id: String { "\(fileURL.path)#\(lineNumber)" }

    /// Start of the due day in the current calendar, for display formatting.
    var dueDate: Date? {
        let parts = dueDateString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2]))
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

    /// Incomplete tasks sorted by due date (ties by note title, then line).
    var incompleteTasks: [TaskItem] {
        allTasks.filter { !$0.isCompleted }.sorted(by: Self.byDueDate)
    }

    /// Completed tasks in the same order, for display below the open ones.
    var completedTasks: [TaskItem] {
        allTasks.filter(\.isCompleted).sorted(by: Self.byDueDate)
    }

    private static func byDueDate(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        (lhs.dueDateString, lhs.fileTitle, lhs.lineNumber)
            < (rhs.dueDateString, rhs.fileTitle, rhs.lineNumber)
    }
}
