import Foundation
import Observation
import WidgetKit

/// Owns the vault lifecycle: restoring the saved bookmark on launch, opening
/// a newly picked folder, keeping security-scoped access balanced, and
/// holding the scanned tree for the browser.
@MainActor
@Observable
final class VaultManager {
    enum State: Equatable {
        /// Resolving the saved bookmark on launch.
        case restoring
        /// No vault selected yet (first launch, or the user cancelled).
        case needsVault
        /// The saved bookmark is stale/invalid or the folder is unreadable.
        case recoveryNeeded
        /// A vault is open and its tree is loaded.
        case open
    }

    /// The task couldn't be re-found in its file when toggling (it was
    /// edited or removed since the index was built).
    struct TaskChangedOnDiskError: LocalizedError {
        var errorDescription: String? {
            "That task has changed on disk, so it wasn’t updated."
        }
    }

    private(set) var state: State = .restoring
    private(set) var rootNode: VaultNode?
    private(set) var vaultURL: URL?
    private(set) var lastErrorDescription: String?

    /// In-memory index (file path, title, due tasks per note), rebuilt with
    /// every tree load: launch, app-created mutations, external changes, and
    /// explicit refreshes.
    private(set) var index = VaultIndex()

    /// Bumped once per detected external change event, after the tree rescan
    /// has been kicked off. Open editors observe it to reload from disk.
    private(set) var externalChangeCount = 0

    private let bookmarkStore: VaultBookmarkStore
    private let scanner = VaultTreeScanner()
    private let fileOperations = VaultFileOperations()
    private let indexBuilder = VaultIndexBuilder()
    private let notificationScheduler = TaskNotificationScheduler()
    private let widgetStore = WidgetSnapshotStore()

    /// Set only when `startAccessingSecurityScopedResource()` returned true,
    /// so every stop is matched to a successful start. `@ObservationIgnored`
    /// keeps it a plain stored property so `deinit` can release it.
    @ObservationIgnored private var securityScopedURL: URL?

    @ObservationIgnored private var changeObserver: VaultChangeObserver?

    init(bookmarkStore: VaultBookmarkStore = VaultBookmarkStore()) {
        self.bookmarkStore = bookmarkStore
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    /// Called once at launch to resolve the persisted bookmark.
    func restore() async {
        guard state == .restoring else { return }
        switch bookmarkStore.resolve() {
        case .noBookmark:
            state = .needsVault
        case .stale:
            state = .recoveryNeeded
        case .resolved(let url):
            beginAccess(to: url)
            await loadTree(from: url)
        }
    }

    /// Called with a folder URL freshly returned by the system picker.
    func openVault(at url: URL) async {
        endAccess()
        beginAccess(to: url)
        do {
            try bookmarkStore.saveBookmark(for: url)
        } catch {
            lastErrorDescription = error.localizedDescription
        }
        await loadTree(from: url)
    }

    func refresh() async {
        guard let vaultURL else { return }
        await loadTree(from: vaultURL)
    }

    // MARK: - File operations

    func createNote(named name: String, in folder: URL) async throws {
        try await perform { try $0.createNote(named: name, in: folder) }
    }

    func createFolder(named name: String, in folder: URL) async throws {
        try await perform { try $0.createFolder(named: name, in: folder) }
    }

    func rename(itemAt url: URL, to newName: String) async throws {
        try await perform { try $0.rename(itemAt: url, to: newName) }
    }

    func move(itemAt url: URL, into folder: URL) async throws {
        try await perform { try $0.move(itemAt: url, into: folder) }
    }

    func deleteItem(at url: URL) async throws {
        try await perform { try $0.delete(itemAt: url) }
    }

    // MARK: - Tasks

    /// The note at the vault root that quick-added tasks are appended to.
    /// Created on demand; any existing note with this name is appended to.
    nonisolated static let quickTaskNoteName = "Tasks.md"

    /// The capture note is the one note whose `##` headings mean lists and
    /// whose list items may go undated. Matched at the vault root only, so a
    /// `Tasks.md` in a subfolder stays an ordinary note.
    nonisolated static func isCaptureNote(_ url: URL, vaultRoot: URL) -> Bool {
        url.lastPathComponent.caseInsensitiveCompare(quickTaskNoteName) == .orderedSame
            && url.deletingLastPathComponent().standardizedFileURL.path
                == vaultRoot.standardizedFileURL.path
    }

    /// The lists in the capture note, from the current index.
    var lists: [TaskList] { index.lists }

    /// Toggles one task in its original Markdown file: re-reads the file,
    /// re-finds the task by content, rewrites the line (flipping the status,
    /// or advancing a recurring task's due date to its next occurrence), and
    /// rescans so the index reflects the change. The tree is refreshed even
    /// when the toggle fails, so a stale list corrects itself.
    func toggleTask(_ task: TaskItem) async throws {
        let ops = fileOperations
        let today = QuickTaskParser.ymdString(from: Date())
        var toggleError: Error?
        do {
            try await Task.detached(priority: .userInitiated) {
                let text = try ops.readNote(at: task.fileURL)
                guard let updated = TaskParser.togglingTask(
                    withText: task.text,
                    dueDateString: task.dueDateString,
                    dueTimeString: task.dueTimeString,
                    recurrence: task.recurrence,
                    isCompleted: task.isCompleted,
                    listName: task.listName,
                    preferredLineNumber: task.lineNumber,
                    todayDateString: today,
                    in: text) else {
                    throw TaskChangedOnDiskError()
                }
                try ops.saveNote(updated, to: task.fileURL)
            }.value
        } catch {
            toggleError = error
        }
        await refresh()
        if let toggleError { throw toggleError }
    }

    /// Deletes one task's line from its original Markdown file: re-reads the
    /// file, re-finds the task by content, drops the whole line, and rescans.
    /// The tree is refreshed even when the delete fails, so a stale list
    /// corrects itself rather than offering the same phantom row again.
    func deleteTask(_ task: TaskItem) async throws {
        let ops = fileOperations
        var deleteError: Error?
        do {
            try await Task.detached(priority: .userInitiated) {
                let text = try ops.readNote(at: task.fileURL)
                guard let updated = TaskParser.removingTask(
                    withText: task.text,
                    dueDateString: task.dueDateString,
                    dueTimeString: task.dueTimeString,
                    recurrence: task.recurrence,
                    isCompleted: task.isCompleted,
                    listName: task.listName,
                    preferredLineNumber: task.lineNumber,
                    in: text) else {
                    throw TaskChangedOnDiskError()
                }
                try ops.saveNote(updated, to: task.fileURL)
            }.value
        } catch {
            deleteError = error
        }
        await refresh()
        if let deleteError { throw deleteError }
    }

    /// Removes all completed Cove task lines from their original Markdown
    /// notes, then rebuilds the index even if one of the file writes fails.
    func clearCompletedTasks() async throws {
        let fileURLs = Set(index.completedTasks.map(\.fileURL))
        guard !fileURLs.isEmpty else { return }

        let ops = fileOperations
        let root = vaultURL
        var clearError: Error?
        do {
            try await Task.detached(priority: .userInitiated) {
                for fileURL in fileURLs {
                    let text = try ops.readNote(at: fileURL)
                    // In the capture note this must parse sectioned, or the
                    // Tasks screen's Clear All would also delete completed
                    // items out of the lists it never showed.
                    let sectioned = root.map { Self.isCaptureNote(fileURL, vaultRoot: $0) } ?? false
                    let updated = TaskParser.clearingCompletedTasks(in: text, sectioned: sectioned)
                    if updated != text {
                        try ops.saveNote(updated, to: fileURL)
                    }
                }
            }.value
        } catch {
            clearError = error
        }
        await refresh()
        if let clearError { throw clearError }
    }

    /// Appends a quick-added task's Markdown line to the capture note at the
    /// vault root, then rescans (which also reschedules notifications).
    /// With a `list`, the line goes under that `##` heading instead of the
    /// end of the note, and the heading is created if it's missing.
    func captureTask(_ draft: TaskDraft, into list: String? = nil) async throws {
        guard let vaultURL else { return }
        let line = draft.markdownLine
        guard let list else {
            try await perform { try $0.appendLine(line, toNoteNamed: Self.quickTaskNoteName,
                                                  in: vaultURL) }
            return
        }
        try await perform {
            try $0.updateNote(named: Self.quickTaskNoteName, in: vaultURL) { text in
                TaskListDocument.insertingLine(line, inSection: list, in: text)
            }
        }
    }

    // MARK: - Lists

    /// A list already exists under that name.
    struct ListExistsError: LocalizedError {
        let name: String
        var errorDescription: String? { "A list named “\(name)” already exists." }
    }

    /// Adds an empty `## name` heading to the capture note.
    func createList(named name: String) async throws {
        guard let vaultURL else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !index.listNames.contains(where: {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }) else { throw ListExistsError(name: trimmed) }

        try await perform {
            try $0.updateNote(named: Self.quickTaskNoteName, in: vaultURL) { text in
                TaskListDocument.addingSection(named: trimmed, to: text)
            }
        }
    }

    /// Renames a list's heading, keeping its items under it.
    func renameList(named name: String, to newName: String) async throws {
        guard let vaultURL else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else { return }
        guard !index.listNames.contains(where: {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
                && $0.caseInsensitiveCompare(name) != .orderedSame
        }) else { throw ListExistsError(name: trimmed) }

        try await perform {
            try $0.updateNote(named: Self.quickTaskNoteName, in: vaultURL) { text in
                TaskListDocument.renamingSection(named: name, to: trimmed, in: text)
            }
        }
    }

    /// Removes a list's heading and every task under it.
    func deleteList(named name: String) async throws {
        guard let vaultURL else { return }
        try await perform {
            try $0.updateNote(named: Self.quickTaskNoteName, in: vaultURL) { text in
                TaskListDocument.removingSection(named: name, from: text)
            }
        }
    }

    /// Runs one coordinated mutation off the main actor, then rescans so the
    /// tree reflects the app-created change.
    private func perform(_ operation: @escaping @Sendable (VaultFileOperations) throws -> Void) async throws {
        let ops = fileOperations
        try await Task.detached(priority: .userInitiated) {
            try operation(ops)
        }.value
        await refresh()
    }

    private func loadTree(from url: URL) async {
        let scanner = self.scanner
        let builder = indexBuilder
        // Toggles the widget couldn't write itself are applied first, so the
        // scan that follows already sees them and the index is built once.
        await applyPendingWidgetToggles()
        do {
            let (node, index) = try await Task.detached(priority: .userInitiated) {
                let node = try scanner.scanTree(at: url)
                return (node, builder.buildIndex(from: node))
            }.value
            rootNode = node
            self.index = index
            vaultURL = url
            lastErrorDescription = nil
            state = .open
            startObservingChanges(at: url)
            // Every index rebuild — launch, mutations, external changes,
            // foreground refreshes — reschedules the task notifications.
            let scheduler = notificationScheduler
            let tasks = index.allTasks
            Task { await scheduler.rebuildNotifications(for: tasks) }
            publishWidgetState(tasks: tasks)
        } catch {
            endAccess()
            rootNode = nil
            index = VaultIndex()
            vaultURL = nil
            lastErrorDescription = error.localizedDescription
            state = .recoveryNeeded
            publishWidgetState(tasks: [])
        }
    }

    // MARK: - Widget

    /// Publishes what the widget extension needs into the shared App Group
    /// container: today's tasks to draw, and the vault bookmark so a tapped
    /// checkbox can reach the note itself. Runs on every index rebuild, which
    /// is the same set of moments that reschedules notifications.
    private func publishWidgetState(tasks: [TaskItem]) {
        widgetStore.writeSnapshot(TodaySnapshot.building(for: Date(), from: tasks))
        if let bookmark = bookmarkStore.bookmarkData {
            widgetStore.writeBookmark(bookmark)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: CoveSharedContainer.todayWidgetKind)
    }

    /// Applies toggles the widget recorded but couldn't write — the extension
    /// may not be able to resolve the vault bookmark from its own process.
    /// Each one goes through the same re-find-then-rewrite path as an in-app
    /// toggle, so a line that changed meanwhile is left alone rather than
    /// overwritten. The queue is cleared regardless: a toggle that no longer
    /// matches is stale, and retrying it forever would be worse than dropping it.
    private func applyPendingWidgetToggles() async {
        let pending = widgetStore.readPendingToggles()
        guard !pending.isEmpty else { return }
        widgetStore.clearPendingToggles()

        let ops = fileOperations
        let today = QuickTaskParser.ymdString(from: Date())
        await Task.detached(priority: .userInitiated) {
            for toggle in pending {
                guard let text = try? ops.readNote(at: toggle.fileURL),
                      let updated = TaskParser.togglingTask(
                        withText: toggle.text,
                        dueDateString: toggle.dueDateString,
                        dueTimeString: toggle.dueTimeString,
                        recurrence: toggle.recurrence,
                        isCompleted: toggle.wasCompleted,
                        listName: nil,
                        preferredLineNumber: toggle.lineNumber,
                        todayDateString: today,
                        in: text)
                else { continue }
                try? ops.saveNote(updated, to: toggle.fileURL)
            }
        }.value
    }

    // MARK: - External change detection

    private func startObservingChanges(at url: URL) {
        guard changeObserver?.vaultURL != url else { return }
        changeObserver?.stop()
        let observer = VaultChangeObserver(vaultURL: url)
        observer.onChange = { [weak self] _ in
            guard let self else { return }
            Task { await self.handleExternalChange() }
        }
        observer.start()
        changeObserver = observer
    }

    private func handleExternalChange() async {
        externalChangeCount += 1
        await refresh()
    }

    private func beginAccess(to url: URL) {
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }
    }

    private func endAccess() {
        changeObserver?.stop()
        changeObserver = nil
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }
}
