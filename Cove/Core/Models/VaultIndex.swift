import Foundation

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
    /// Recurring charges, populated for the subscription note alone. Every
    /// other note indexes none, the same way `listNames` is populated for the
    /// capture note alone.
    let subscriptions: [Subscription]
    /// The `##` headings of the subscription note — its categories, whether or
    /// not anything sits under them yet.
    let subscriptionCategoryNames: [String]
    /// Malformed/ambiguous task syntax discovered without modifying the note.
    /// UI can surface these instead of silently omitting task-looking lines.
    let taskDiagnostics: [TaskParser.Diagnostic]
    /// The same disclosure for subscription lines: a line that looks like a
    /// charge but could not be read is reported rather than dropped.
    let subscriptionDiagnostics: [SubscriptionParser.Diagnostic]
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
        subscriptions: [Subscription] = [],
        subscriptionCategoryNames: [String] = [],
        taskDiagnostics: [TaskParser.Diagnostic] = [],
        subscriptionDiagnostics: [SubscriptionParser.Diagnostic] = [],
        indexingErrorDescription: String? = nil,
        modificationDate: Date? = nil,
        fileSize: Int? = nil
    ) {
        self.url = url
        self.title = title
        self.tasks = tasks
        self.listNames = listNames
        self.subscriptions = subscriptions
        self.subscriptionCategoryNames = subscriptionCategoryNames
        self.taskDiagnostics = taskDiagnostics
        self.subscriptionDiagnostics = subscriptionDiagnostics
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
    /// The `##` category headings in the subscription note, in file order, and
    /// held separately for the same reason: a category with nothing under it
    /// yet is still a category.
    var subscriptionCategoryNames: [String] = []

    var allTasks: [TaskItem] { entries.flatMap(\.tasks) }

    /// Every recurring charge in the vault, which in practice means every line
    /// of the subscription note.
    var subscriptions: [Subscription] { entries.flatMap(\.subscriptions) }

    var taskDiagnostics: [(fileURL: URL, diagnostic: TaskParser.Diagnostic)] {
        entries.flatMap { entry in
            entry.taskDiagnostics.map { (entry.url, $0) }
        }
    }

    var subscriptionDiagnostics: [(fileURL: URL, diagnostic: SubscriptionParser.Diagnostic)] {
        entries.flatMap { entry in
            entry.subscriptionDiagnostics.map { (entry.url, $0) }
        }
    }

    var indexingFailures: [(fileURL: URL, description: String)] {
        entries.compactMap { entry in
            entry.indexingErrorDescription.map { (entry.url, $0) }
        }
    }

    /// Incomplete tasks sorted by due date, then time (date-only tasks
    /// first within a day), then note title and line. A list's *dated* items
    /// are included and its undated ones are not — see
    /// `TaskItem.belongsOnTasksScreen`.
    var incompleteTasks: [TaskItem] {
        allTasks.filter { !$0.isCompleted && $0.belongsOnTasksScreen }
            .sorted(by: TaskItem.byDueDate)
    }

    /// Completed tasks in the same order, for display below the open ones.
    /// It admits the same tasks the open section does, which is what keeps
    /// the screen's Clear All clearing exactly what it showed.
    var completedTasks: [TaskItem] {
        allTasks.filter { $0.isCompleted && $0.belongsOnTasksScreen }
            .sorted(by: TaskItem.byDueDate)
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
                openTasks: tasks.filter { !$0.isCompleted }
                    .sorted(by: TaskItem.byDueDate),
                completedTasks: tasks.filter(\.isCompleted)
                    .sorted(by: TaskItem.byDueDate))
        }
    }
}
