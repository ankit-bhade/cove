import Foundation
import Observation
import WidgetKit

struct DeletedTaskRecord: Sendable {
    let identity: TaskIdentity
    let originalLine: String
    let previousIdentity: TaskIdentity?
    let nextIdentity: TaskIdentity?
    let approximateLineNumber: Int
    let sourceNoteURL: URL
}

typealias VaultLoadOperation = @Sendable (
    _ url: URL,
    _ previousIndex: VaultIndex,
    _ changedURLs: Set<URL>?
) async throws -> (VaultNode, VaultIndex)

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
    private let fileOperations = VaultFileOperations()
    private let repository = VaultRepository()
    private let loadOperation: VaultLoadOperation
    private let notificationScheduler = TaskNotificationScheduler()
    private let widgetStore = WidgetSnapshotStore()

    /// Set only when `startAccessingSecurityScopedResource()` returned true,
    /// so every stop is matched to a successful start. `@ObservationIgnored`
    /// keeps it a plain stored property so `deinit` can release it.
    @ObservationIgnored private var securityScopedURL: URL?

    @ObservationIgnored private var changeObserver: VaultChangeObserver?
    @ObservationIgnored private var loadGeneration: UInt64 = 0
    @ObservationIgnored private var requestedVaultURL: URL?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(bookmarkStore: VaultBookmarkStore = VaultBookmarkStore(),
         loadOperation: VaultLoadOperation? = nil) {
        self.bookmarkStore = bookmarkStore
        self.loadOperation = loadOperation ?? { url, previousIndex, changedURLs in
            try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let node = try VaultTreeScanner().scanTree(at: url)
                let index = try VaultIndexBuilder().buildCancellableIndex(
                    from: node, previous: previousIndex, changedURLs: changedURLs)
                try Task.checkCancellation()
                return (node, index)
            }.value
        }
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
        guard let url = requestedVaultURL ?? vaultURL else { return }
        await loadTree(from: url, coalescing: true)
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

    @discardableResult
    func deleteItem(at url: URL) async throws -> RecoveryRecord {
        guard let vaultRoot = requestedVaultURL ?? vaultURL else {
            throw VaultFileOperations.OperationError.fileMissing(url.lastPathComponent)
        }
        let operations = fileOperations
        let record = try await Task.detached(priority: .userInitiated) {
            try operations.moveToRecovery(itemAt: url, vaultRoot: vaultRoot)
        }.value
        await refresh()
        return record
    }

    func restoreDeletedItem(_ record: RecoveryRecord) async throws {
        let operations = fileOperations
        try await Task.detached(priority: .userInitiated) {
            _ = try operations.restore(record)
        }.value
        await refresh()
    }

    func restoreDeletedItem(_ record: RecoveryRecord, as newName: String) async throws {
        let operations = fileOperations
        try await Task.detached(priority: .userInitiated) {
            _ = try operations.restore(record, as: newName)
        }.value
        await refresh()
    }

    /// Metadata observation is explicitly tied to the foreground lifecycle.
    /// A foreground refresh starts a fresh observer after reconciling disk.
    func stopObservingExternalChanges() {
        changeObserver?.stop()
        changeObserver = nil
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
        try await setTaskCompleted(task, to: !task.isCompleted)
    }

    /// Idempotent semantic completion used by the app, Undo, and widget
    /// retries. The transform re-parses the newest coordinated file text.
    func setTaskCompleted(_ task: TaskItem, to desiredCompletion: Bool) async throws {
        let identity = task.identity
        let today = QuickTaskParser.ymdString(from: Date(),
                                              calendar: TaskCalendar.gregorian())
        var toggleError: Error?
        do {
            _ = try await repository.updateNote(at: task.fileURL) { text in
                guard let updated = TaskParser.settingTaskCompleted(
                    identity, to: desiredCompletion,
                    todayDateString: today, in: text) else {
                    throw TaskChangedOnDiskError()
                }
                return updated
            }
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
    @discardableResult
    func deleteTask(_ task: TaskItem) async throws -> DeletedTaskRecord {
        let identity = task.identity
        let siblings = index.allTasks
            .filter { $0.fileURL.standardizedFileURL == task.fileURL.standardizedFileURL }
            .sorted { $0.lineNumber < $1.lineNumber }
        let siblingIndex = siblings.firstIndex(where: { $0.identity == identity })
        let previous = siblingIndex.flatMap { $0 > 0 ? siblings[$0 - 1].identity : nil }
        let next = siblingIndex.flatMap { $0 + 1 < siblings.count ? siblings[$0 + 1].identity : nil }
        let record = DeletedTaskRecord(
            identity: identity,
            originalLine: Self.markdownLine(for: task) + "\n",
            previousIdentity: previous,
            nextIdentity: next,
            approximateLineNumber: task.lineNumber,
            sourceNoteURL: task.fileURL)
        var deleteError: Error?
        do {
            _ = try await repository.updateNote(at: task.fileURL) { text in
                guard let updated = TaskParser.removingTask(identity, in: text) else {
                    throw TaskChangedOnDiskError()
                }
                return updated
            }
        } catch {
            deleteError = error
        }
        await refresh()
        if let deleteError { throw deleteError }
        return record
    }

    func restoreDeletedTask(_ record: DeletedTaskRecord) async throws {
        _ = try await repository.updateNote(at: record.sourceNoteURL) { text in
            // Undo is idempotent and never restores the entire old document.
            if TaskParser.matchingTask(record.identity, in: text) != nil { return text }

            let insertionLocation: Int
            if let next = record.nextIdentity,
               let match = TaskParser.matchingTask(next, in: text) {
                insertionLocation = match.lineRange.location
            } else if let previous = record.previousIdentity,
                      let match = TaskParser.matchingTask(previous, in: text) {
                insertionLocation = NSMaxRange(match.lineRange)
            } else {
                insertionLocation = Self.lineStart(
                    for: record.approximateLineNumber, in: text)
            }

            var line = record.originalLine
            if insertionLocation == (text as NSString).length,
               !text.isEmpty, !text.hasSuffix("\n"), !text.hasSuffix("\r") {
                line = "\n" + line
            }
            return (text as NSString).replacingCharacters(
                in: NSRange(location: insertionLocation, length: 0),
                with: line)
        }
        await refresh()
    }

    nonisolated private static func markdownLine(for task: TaskItem) -> String {
        var line = "- [\(task.isCompleted ? "x" : " ")] \(task.text)"
        if let date = task.dueDateString {
            line += " @due(\(date)"
            if let time = task.dueTimeString { line += " \(time)" }
            line += ")"
            if let recurrence = task.recurrence {
                line += " @repeat(\(recurrence.tagText))"
            }
        }
        return line
    }

    nonisolated private static func lineStart(for lineNumber: Int, in text: String) -> Int {
        let ns = text as NSString
        var currentLine = 0
        var result = ns.length
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length),
                               options: [.byLines, .substringNotRequired]) {
            _, lineRange, _, stop in
            if currentLine == lineNumber {
                result = lineRange.location
                stop.pointee = true
            }
            currentLine += 1
        }
        return result
    }

    /// Removes all completed Cove task lines from their original Markdown
    /// notes, then rebuilds the index even if one of the file writes fails.
    func clearCompletedTasks() async throws {
        let fileURLs = Set(index.completedTasks.map(\.fileURL))
        guard !fileURLs.isEmpty else { return }

        let repository = repository
        let root = vaultURL
        var clearError: Error?
        do {
            for fileURL in fileURLs {
                _ = try await repository.updateNote(at: fileURL) { text in
                    // In the capture note this must parse sectioned, or the
                    // Tasks screen's Clear All would also delete completed
                    // items out of the lists it never showed.
                    let sectioned = root.map { Self.isCaptureNote(fileURL, vaultRoot: $0) } ?? false
                    return TaskParser.clearingCompletedTasks(in: text, sectioned: sectioned)
                }
            }
        } catch {
            clearError = error
        }
        await refresh()
        if let clearError { throw clearError }
    }

    /// Writes a quick-added task's Markdown line into the capture note at the
    /// vault root, then rescans (which also reschedules notifications).
    /// With a `list`, the line goes under that `##` heading, created if it's
    /// missing. Without one, it goes into the note's unlisted region rather
    /// than the end of the file, which would otherwise put it inside the last
    /// list and hide it from the Tasks screen.
    func captureTask(_ draft: TaskDraft, into list: String? = nil) async throws {
        guard let vaultURL else { return }
        let line = draft.markdownLine
        try await mutateNote(named: Self.quickTaskNoteName, in: vaultURL) { text in
                guard let list else {
                    return TaskListDocument.insertingUnlistedLine(line, in: text)
                }
                return TaskListDocument.insertingLine(line, inSection: list, in: text)
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

        try await mutateNote(named: Self.quickTaskNoteName, in: vaultURL) { text in
                TaskListDocument.addingSection(named: trimmed, to: text)
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

        try await mutateNote(named: Self.quickTaskNoteName, in: vaultURL) { text in
                TaskListDocument.renamingSection(named: name, to: trimmed, in: text)
        }
    }

    /// Removes a list's completed items, leaving its open ones and its
    /// heading in place. The capture note is the only file lists live in, so
    /// this is one coordinated read-modify-write rather than the per-file
    /// sweep the Tasks screen's Clear All needs.
    func clearCompletedTasks(inList name: String) async throws {
        guard let vaultURL else { return }
        try await mutateNote(named: Self.quickTaskNoteName, in: vaultURL) { text in
                TaskParser.clearingCompletedTasks(in: text, sectioned: true, inList: name)
        }
    }

    /// Removes a list's heading and every task under it.
    func deleteList(named name: String) async throws {
        guard let vaultURL else { return }
        try await mutateNote(named: Self.quickTaskNoteName, in: vaultURL) { text in
                TaskListDocument.removingSection(named: name, from: text)
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

    private func mutateNote(
        named name: String,
        in folder: URL,
        transform: @escaping @Sendable (String) throws -> String?
    ) async throws {
        _ = try await repository.updateNote(named: name, in: folder, transform: transform)
        await refresh()
    }

    private func loadTree(from url: URL,
                          coalescing: Bool = false,
                          changedURLs: Set<URL>? = nil) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        requestedVaultURL = url
        refreshTask?.cancel()

        let task = Task { [weak self] in
            if coalescing {
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
            }
            await self?.performLoad(from: url,
                                    generation: generation,
                                    changedURLs: changedURLs)
        }
        refreshTask = task
        await task.value
    }

    private func performLoad(from url: URL,
                             generation: UInt64,
                             changedURLs: Set<URL>?) async {
        guard isCurrentLoad(generation: generation, url: url) else { return }
        let startedAt = Date()
        let loadOperation = self.loadOperation
        let previousIndex = index
        // Toggles the widget couldn't write itself are applied first, so the
        // scan that follows already sees them and the index is built once.
        await applyPendingWidgetOperations()
        guard isCurrentLoad(generation: generation, url: url) else { return }

        let scanTask = Task {
            try await loadOperation(url, previousIndex, changedURLs)
        }
        do {
            let (node, index) = try await withTaskCancellationHandler {
                try await scanTask.value
            } onCancel: {
                scanTask.cancel()
            }
            guard isCurrentLoad(generation: generation, url: url) else { return }
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
            CoveLog.index.info("Indexed \(node.allFiles.count, privacy: .public) notes in \(Date().timeIntervalSince(startedAt), privacy: .public) seconds")
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentLoad(generation: generation, url: url) else { return }
            CoveLog.vault.error("Vault load failed: \(error.localizedDescription, privacy: .private)")
            endAccess()
            rootNode = nil
            index = VaultIndex()
            vaultURL = nil
            lastErrorDescription = error.localizedDescription
            state = .recoveryNeeded
            publishWidgetState(tasks: [])
        }
    }

    private func isCurrentLoad(generation: UInt64, url: URL) -> Bool {
        generation == loadGeneration
            && requestedVaultURL?.standardizedFileURL == url.standardizedFileURL
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
    private func applyPendingWidgetOperations() async {
        let pending: [PendingTaskOperation]
        do {
            pending = try widgetStore.loadPendingOperations()
        } catch {
            // A missing App Group is normal for the ad-hoc macOS build. A
            // malformed or inaccessible iOS queue is retained for diagnosis
            // and retry rather than being replaced with an empty file.
            CoveLog.widget.error("Pending operation queue load failed: \(error.localizedDescription, privacy: .private)")
            return
        }
        guard !pending.isEmpty else { return }

        let today = QuickTaskParser.ymdString(from: Date(),
                                              calendar: TaskCalendar.gregorian())
        for operation in pending {
            do {
                _ = try await repository.updateNote(
                    at: operation.taskIdentity.fileURL
                ) { text in
                    TaskParser.settingTaskCompleted(
                        operation.taskIdentity,
                        to: operation.desiredCompletion,
                        todayDateString: today,
                        in: text)
                }
                try widgetStore.acknowledge(operationID: operation.id)
            } catch VaultFileOperations.OperationError.fileMissing(_) {
                // A deleted note is a definitive stale target, not a
                // transient provider failure.
                do {
                    try widgetStore.acknowledge(operationID: operation.id)
                } catch {
                    CoveLog.widget.error("Stale operation acknowledgment failed: \(error.localizedDescription, privacy: .private)")
                }
            } catch {
                // Normal file/coordinator/iCloud failures stay queued.
                CoveLog.widget.error("Pending operation retained after failure: \(error.localizedDescription, privacy: .private)")
                continue
            }
        }
    }

    // MARK: - External change detection

    private func startObservingChanges(at url: URL) {
        guard changeObserver?.vaultURL != url else { return }
        changeObserver?.stop()
        let observer = VaultChangeObserver(vaultURL: url)
        observer.onChange = { [weak self] changes in
            guard let self else { return }
            Task { await self.handleExternalChange(changes) }
        }
        observer.start()
        changeObserver = observer
    }

    private func handleExternalChange(_ changes: Set<URL>) async {
        externalChangeCount += 1
        guard let url = requestedVaultURL ?? vaultURL else { return }
        await loadTree(from: url, coalescing: true, changedURLs: changes)
    }

    private func beginAccess(to url: URL) {
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }
    }

    private func endAccess() {
        refreshTask?.cancel()
        refreshTask = nil
        requestedVaultURL = nil
        changeObserver?.stop()
        changeObserver = nil
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }
}
