import Foundation
import Observation

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

    /// Flips one task's checkbox in its original Markdown file: re-reads the
    /// file, re-finds the task by content, rewrites the line, and rescans so
    /// the index reflects the change. The tree is refreshed even when the
    /// toggle fails, so a stale list corrects itself.
    func toggleTask(_ task: TaskItem) async throws {
        let ops = fileOperations
        var toggleError: Error?
        do {
            try await Task.detached(priority: .userInitiated) {
                let text = try ops.readNote(at: task.fileURL)
                guard let updated = TaskParser.togglingTask(
                    withText: task.text,
                    dueDateString: task.dueDateString,
                    isCompleted: task.isCompleted,
                    preferredLineNumber: task.lineNumber,
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
        } catch {
            endAccess()
            rootNode = nil
            index = VaultIndex()
            vaultURL = nil
            lastErrorDescription = error.localizedDescription
            state = .recoveryNeeded
        }
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
