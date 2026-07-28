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

/// What a deleted subscription needs to come back: its exact source line and
/// the category it sat under. Unlike a task, it is restored into its `##`
/// section rather than between remembered neighbours — a subscription note is
/// a short list whose order carries no meaning, so re-inserting under the
/// right heading is the whole of "put it back".
struct DeletedSubscriptionRecord: Sendable {
    let identity: SubscriptionIdentity
    let originalLine: String
    let category: String?
    let sourceNoteURL: URL
}

struct TaskToggleRecord: Sendable {
    let originalIdentity: TaskIdentity
    let previousCompletion: Bool
    let advancedRecurrence: Bool
    let completedOnDateString: String
}

/// What one in-place task edit changed, and enough to reverse it.
///
/// The identity is the *edited* line's, read back out of the parser, so Undo
/// re-finds the line semantically and refuses on ambiguity like every other
/// task mutation. `previousBody` is the span the coordinated write actually
/// replaced — the recurrence anchor included, when the line carried one.
struct TaskEditRecord: Sendable {
    let identity: TaskIdentity
    let noteURL: URL
    let previousBody: String
}

/// Refused before a coordinated write is attempted.
enum TaskUpdateError: LocalizedError, Equatable, Sendable {
    case dueDateRequired

    var errorDescription: String? {
        switch self {
        case .dueDateRequired:
            return "A task outside a list needs a due date."
        }
    }
}

/// A value produced *inside* a coordinated transform and read after it.
///
/// Undo restores bytes, and the only bytes worth restoring are the ones the
/// coordinated read actually saw — a caller-side read before the write is
/// exactly the stale read `VaultRepository` exists to prevent. The transform
/// is `@Sendable` and may run more than once, since the coordinated write
/// retries when the file changes under it, so the last recorded value is the
/// one belonging to the text that was committed.
final class CoordinatedTransformOutput<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value?

    var value: Value? { lock.withLock { storage } }

    func record(_ value: Value) {
        lock.withLock { storage = value }
    }
}

typealias VaultLoadOperation =
    @Sendable (
        _ url: URL,
        _ previousIndex: VaultIndex,
        _ changedURLs: Set<URL>?,
        _ existingTree: VaultNode?
    ) async throws -> (VaultNode, VaultIndex)

struct CoveStorageHealth: Equatable, Sendable {
    enum AccessState: Equatable, Sendable {
        case unavailable
        case directlyAccessible
        case securityScoped
    }

    let lastIssue: String?
    let unavailableNoteCount: Int
    let taskDiagnosticCount: Int
    let subscriptionDiagnosticCount: Int
    let unresolvedConflictURLs: [URL]
    let conflictReviewURLs: [URL]
    let bookmarkIsPersisted: Bool
    let accessState: AccessState
    let recoveryItemCount: Int
    let recoveryDraftCount: Int

    /// What the vault is asking of the reader, if anything.
    ///
    /// Three states rather than two because recovery is not a fault. A
    /// recovered draft is work Cove *saved*; reporting it in the same alert
    /// red as an unreadable note would misstate it, and reporting it not at
    /// all — which is what "Ready" did — leaves edits sitting in Application
    /// Support with nothing on screen saying so.
    enum Attention: Equatable, Sendable {
        case ready
        /// Something is waiting to be recovered, and nothing is wrong.
        case recovery
        case needsAttention
    }

    /// Only *drafts* raise the recovery state, never `recoveryItemCount`.
    /// Deleted items live under `.cove-recovery` for a week by design, so any
    /// vault where something has been deleted recently would sit permanently
    /// in a non-ready state — a signal that is always on is not a signal.
    /// A draft is a crash-recovered editor buffer, which is genuinely
    /// unfinished business.
    var attention: Attention {
        if lastIssue != nil
            || unavailableNoteCount > 0
            || taskDiagnosticCount > 0
            || subscriptionDiagnosticCount > 0
            || !unresolvedConflictURLs.isEmpty
            || !conflictReviewURLs.isEmpty
            || !bookmarkIsPersisted
        {
            return .needsAttention
        }
        return recoveryDraftCount > 0 ? .recovery : .ready
    }
}

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

    struct VaultUnavailableError: LocalizedError {
        var errorDescription: String? {
            "No vault is currently open."
        }
    }

    private(set) var state: State = .restoring
    private(set) var rootNode: VaultNode?
    private(set) var vaultURL: URL?
    private(set) var lastErrorDescription: String?
    private(set) var unresolvedConflictURLs: Set<URL> = []
    private(set) var conflictReviewURLs: Set<URL> = []
    private(set) var recoveryItemCount = 0
    private(set) var recoveryDraftCount = 0
    private(set) var notificationHealth: TaskNotificationHealth?
    private(set) var widgetHealth: WidgetChannelHealth?

    /// In-memory index (file path, title, due tasks per note), rebuilt with
    /// every tree load: launch, app-created mutations, external changes, and
    /// explicit refreshes.
    private(set) var index = VaultIndex()

    /// Bumped once per detected external change event, after the tree rescan
    /// has been kicked off. Open editors observe it to reload from disk.
    private(set) var externalChangeCount = 0

    var storageHealth: CoveStorageHealth {
        let accessState: CoveStorageHealth.AccessState
        if securityScopedURL != nil {
            accessState = .securityScoped
        } else if state == .open {
            accessState = .directlyAccessible
        } else {
            accessState = .unavailable
        }
        return CoveStorageHealth(
            lastIssue: lastErrorDescription,
            unavailableNoteCount: index.indexingFailures.count,
            taskDiagnosticCount: index.taskDiagnostics.count,
            subscriptionDiagnosticCount: index.subscriptionDiagnostics.count,
            unresolvedConflictURLs: unresolvedConflictURLs.sorted {
                $0.path < $1.path
            },
            conflictReviewURLs: conflictReviewURLs.sorted {
                $0.path < $1.path
            },
            bookmarkIsPersisted: bookmarkStore.hasBookmark,
            accessState: accessState,
            recoveryItemCount: recoveryItemCount,
            recoveryDraftCount: recoveryDraftCount)
    }

    private let bookmarkStore: VaultBookmarkStore
    private let fileOperations = VaultFileOperations()
    private let repository = VaultRepository()
    private let loadOperation: VaultLoadOperation
    private let rebuildNotifications: @Sendable ([TaskItem]) async -> TaskNotificationHealth
    private let cancelNotifications: @Sendable () async -> TaskNotificationHealth
    private let widgetStore: WidgetSnapshotStore
    private let reloadWidgetTimelines: @MainActor @Sendable () -> Void

    /// Set only when `startAccessingSecurityScopedResource()` returned true,
    /// so every stop is matched to a successful start. `@ObservationIgnored`
    /// keeps it a plain stored property so `deinit` can release it.
    @ObservationIgnored private var securityScopedURL: URL?

    @ObservationIgnored private var changeObserver: VaultChangeObserver?
    @ObservationIgnored private var loadGeneration: UInt64 = 0
    @ObservationIgnored private var requestedVaultURL: URL?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Notes named by targeted refreshes that have not yet been committed to
    /// the index. Accumulated across coalesced calls so a superseded refresh
    /// hands its work to the one that replaced it.
    @ObservationIgnored private var pendingChangedURLs: Set<URL> = []
    @ObservationIgnored private var protectedEditorURLs: Set<URL> = []

    /// True while `rootNode` is a tree no pending load is about to replace.
    /// An index-only refresh may reuse the scanned tree only then: it cancels
    /// whatever load is in flight, so reusing the tree across a requested
    /// scan would commit the very tree that scan was going to correct.
    @ObservationIgnored private var treeIsCurrent = false
    /// The task set (and day) the widget and notifications were last
    /// reconciled against. Nil forces the next reconcile to run.
    @ObservationIgnored private var lastDerivedStateFingerprint: Int?
    /// When the recovery area and draft store were last counted. Walking them
    /// is a filesystem trip that only a delete or a draft can change, so it
    /// does not belong on the path a checkbox tap takes.
    @ObservationIgnored private var lastStorageCountAt: Date?

    init(
        bookmarkStore: VaultBookmarkStore = VaultBookmarkStore(),
        loadOperation: VaultLoadOperation? = nil,
        notificationRebuild:
            (@Sendable ([TaskItem]) async -> TaskNotificationHealth)? = nil,
        notificationCancel:
            (@Sendable () async -> TaskNotificationHealth)? = nil,
        widgetStore: WidgetSnapshotStore = WidgetSnapshotStore(),
        reloadWidgetTimelines:
            (@MainActor @Sendable () -> Void)? = nil
    ) {
        let notificationScheduler = TaskNotificationScheduler()
        self.bookmarkStore = bookmarkStore
        self.rebuildNotifications =
            notificationRebuild
            ?? { tasks in
                await notificationScheduler.rebuildNotifications(
                    for: tasks)
            }
        self.cancelNotifications =
            notificationCancel
            ?? {
                await notificationScheduler.cancelAllNotifications()
            }
        self.widgetStore = widgetStore
        self.reloadWidgetTimelines =
            reloadWidgetTimelines
            ?? {
                WidgetCenter.shared.reloadTimelines(
                    ofKind: CoveSharedContainer.todayWidgetKind)
            }
        self.loadOperation =
            loadOperation ?? { url, previousIndex, changedURLs, existingTree in
                try await Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    let node = try existingTree ?? VaultTreeScanner().scanTree(at: url)
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
            await publishUnavailableDerivedState()
        case .stale:
            state = .recoveryNeeded
            await publishUnavailableDerivedState()
        case .resolved(let url):
            beginAccess(to: url)
            await purgeRecoveryArea(at: url)
            await loadTree(from: url)
        }
    }

    /// Called with a folder URL freshly returned by the system picker.
    func openVault(at url: URL) async {
        guard protectedEditorURLs.isEmpty else {
            lastErrorDescription =
                "Finish saving or export the open note’s recovery copy before switching vaults."
            return
        }
        let candidateURL = url.standardizedFileURL
        let didStartCandidateScope =
            candidateURL.startAccessingSecurityScopedResource()
        let candidateBookmark: Data
        do {
            candidateBookmark = try bookmarkStore.makeBookmarkData(
                for: candidateURL)
        } catch {
            if didStartCandidateScope {
                candidateURL.stopAccessingSecurityScopedResource()
            }
            lastErrorDescription = error.localizedDescription
            if vaultURL == nil {
                state = bookmarkStore.hasBookmark ? .recoveryNeeded : .needsVault
            }
            return
        }

        // Keep the complete last-good session and its security scope alive
        // while the candidate scans. Picking an unreadable folder must not
        // destroy the working vault or its durable bookmark.
        let previousRoot = rootNode
        let previousIndex = index
        let previousURL = vaultURL
        let previousState = state
        let previousTreeWasCurrent = treeIsCurrent
        let previousScope = securityScopedURL
        let previousConflicts = unresolvedConflictURLs
        let previousConflictCopies = conflictReviewURLs

        await loadTree(from: candidateURL, deferDerivedState: true)

        guard
            state == .open,
            vaultURL?.standardizedFileURL == candidateURL
        else {
            if didStartCandidateScope {
                candidateURL.stopAccessingSecurityScopedResource()
            }
            return
        }

        do {
            try bookmarkStore.saveBookmarkData(candidateBookmark)
        } catch {
            // The candidate loaded, but access could not be made durable.
            // Roll the in-memory session back as one transaction.
            if didStartCandidateScope {
                candidateURL.stopAccessingSecurityScopedResource()
            }
            rootNode = previousRoot
            index = previousIndex
            vaultURL = previousURL
            state = previousState
            treeIsCurrent = previousTreeWasCurrent
            requestedVaultURL = previousURL
            unresolvedConflictURLs = previousConflicts
            conflictReviewURLs = previousConflictCopies
            lastErrorDescription = error.localizedDescription
            changeObserver?.stop()
            changeObserver = nil
            if let previousURL, previousState == .open {
                startObservingChanges(at: previousURL)
            }
            return
        }

        if didStartCandidateScope {
            securityScopedURL = candidateURL
            if let previousScope {
                previousScope.stopAccessingSecurityScopedResource()
            }
        } else if previousScope?.standardizedFileURL != candidateURL {
            previousScope?.stopAccessingSecurityScopedResource()
            securityScopedURL = nil
        }
        if previousURL?.standardizedFileURL != candidateURL {
            unresolvedConflictURLs = []
            conflictReviewURLs = []
        }
        // Only now that the candidate bookmark is durable may it consume
        // pending widget operations. A failed vault switch must leave the
        // previous vault and its queue completely untouched.
        let widgetChanges = await applyPendingWidgetOperations(
            vaultRoot: candidateURL)
        // A different vault's derived state was never reconciled against this
        // one's task set, so the fingerprint from before the switch says
        // nothing about what has to be republished now.
        lastDerivedStateFingerprint = nil
        if widgetChanges.isEmpty {
            await reconcileDerivedState(for: index)
        } else {
            await refreshIndex(changedURLs: widgetChanges)
        }
        await purgeRecoveryArea(at: candidateURL)
        await refreshStorageCounts(at: candidateURL, force: true)
    }

    /// Sweeps the recovery area's expired entries once per vault open, rather
    /// than on every refresh: the area only grows through deletion, and a
    /// launch is the natural moment to take out the trash. Undo only ever
    /// points at an entry deleted this session, so the sweep can't race it,
    /// and a failure here must never keep the vault from opening.
    private func purgeRecoveryArea(at url: URL) async {
        let operations = fileOperations
        do {
            try await Task.detached(priority: .utility) {
                // Stranded write temporaries go first and never throw: they
                // are pure housekeeping, and the recovery sweep is the part
                // whose failure the user needs to hear about.
                operations.purgeWriteTemporaries(vaultRoot: url)
                try operations.purgeRecovery(vaultRoot: url)
            }.value
        } catch {
            CoveLog.vault.error(
                "Recovery sweep failed: \(error.localizedDescription, privacy: .private)")
            reportStorageIssue(
                "Cove could not finish cleaning its recovery area: \(error.localizedDescription)")
        }
    }

    func refresh() async {
        guard let url = requestedVaultURL ?? vaultURL else { return }
        await loadTree(from: url, coalescing: true)
    }

    /// Rebuilds the index over the tree already in memory, re-reading only
    /// the notes named. An app-created content change writes inside a file
    /// that is already in the tree, so re-enumerating every folder in the
    /// vault to learn that nothing moved is work whose answer is known —
    /// and in an iCloud vault it is the expensive half of a checkbox tap.
    /// Falls back to a full scan whenever the tree can't be trusted, which
    /// keeps every structural change on the rescan path it has always taken.
    private func refreshIndex(changedURLs: Set<URL>) async {
        guard let url = requestedVaultURL ?? vaultURL else { return }
        await loadTree(
            from: url, coalescing: true,
            changedURLs: changedURLs, reusingTree: true)
    }

    /// Called by open editors after a physical save, so a direct edit to
    /// Tasks.md reaches the index and downstream reconcilers without waiting
    /// for an eventual provider notification.
    func noteDidPersist(at url: URL) async {
        guard state == .open, isInTree(url) else { return }
        await refreshIndex(changedURLs: [url])
    }

    func setEditorProtection(_ protected: Bool, for url: URL) {
        let standardized = url.standardizedFileURL
        if protected {
            protectedEditorURLs.insert(standardized)
        } else {
            protectedEditorURLs.remove(standardized)
        }
    }

    func isEditorProtected(_ url: URL) -> Bool {
        protectedEditorURLs.contains(url.standardizedFileURL)
    }

    func reportStorageIssue(_ description: String) {
        lastErrorDescription = description
    }

    // MARK: - File operations

    /// Returns the note it created, so the caller can open it. Creating a
    /// note and leaving the reader in the browser to find and tap it is a
    /// step the app already knows the answer to.
    @discardableResult
    func createNote(named name: String, in folder: URL) async throws -> URL {
        try await performReturning { try $0.createNote(named: name, in: folder) }
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

    func recoveryRecords() async throws -> [RecoveryRecord] {
        let vaultRoot = try requireOpenVaultURL()
        let operations = fileOperations
        return try await Task.detached(priority: .utility) {
            try operations.recoveryRecords(vaultRoot: vaultRoot)
        }.value
    }

    func recoveryDrafts() async throws -> [EditorRecoveryDraftSummary] {
        let vaultRoot = try requireOpenVaultURL()
        let store = EditorRecoveryDraftStore()
        let drafts = try await Task.detached(priority: .utility) {
            try store.summaries()
        }.value
        return drafts.filter { Self.isInside(vaultRoot, $0.originalURL) }
    }

    /// Drafts are keyed by absolute path and outlive the vault they were
    /// written for, so one belonging to a folder the user no longer has open
    /// must not be listed — or counted — under the current vault.
    nonisolated private static func isInside(_ vaultRoot: URL, _ url: URL) -> Bool {
        let root = vaultRoot.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        return components.count > root.count
            && Array(components.prefix(root.count)) == root
    }

    /// Reads the draft's text at the moment it is exported rather than
    /// holding it from the moment the list was drawn.
    @discardableResult
    func exportRecoveryDraft(
        _ summary: EditorRecoveryDraftSummary
    ) async throws -> URL {
        let vaultRoot = try requireOpenVaultURL()
        let operations = fileOperations
        let store = EditorRecoveryDraftStore()
        let originalURL = summary.originalURL
        let destination = try await Task.detached(priority: .userInitiated) {
            guard let draft = try store.load(for: originalURL) else {
                throw VaultFileOperations.OperationError.fileMissing(
                    originalURL.lastPathComponent)
            }
            return try operations.createRecoveryCopy(
                draft.text,
                for: draft.originalURL,
                in: vaultRoot)
        }.value
        do {
            try await Task.detached(priority: .utility) {
                try store.remove(for: originalURL)
            }.value
        } catch {
            reportStorageIssue(
                "The recovery copy was saved, but Cove could not remove its old draft: \(error.localizedDescription)"
            )
        }
        await refresh()
        return destination
    }

    func discardRecoveryDraft(_ summary: EditorRecoveryDraftSummary) async throws {
        let store = EditorRecoveryDraftStore()
        let originalURL = summary.originalURL
        try await Task.detached(priority: .userInitiated) {
            try store.remove(for: originalURL)
        }.value
        await refreshStorageCounts(at: try requireOpenVaultURL())
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
    /// How long a targeted refresh will reuse the last recovery counts.
    nonisolated private static let storageCountInterval: TimeInterval = 30

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

    // MARK: - Trackers

    /// The folder at the vault root that tracker notes live in, created on
    /// demand with the first charge.
    ///
    /// Trackers get a folder rather than sitting beside `Tasks.md` at the root
    /// because there will be more than one of them, and a vault root
    /// accumulating a note per tracker is a root that stops being about the
    /// user's own notes. It is still a *fixed* location — one path, nothing to
    /// configure, no ambiguity about which file is meant.
    nonisolated static let trackerFolderName = "Trackers"

    /// The note inside it that recurring charges are recorded in.
    nonisolated static let subscriptionNoteName = "Subscriptions.md"

    nonisolated static func trackerFolderURL(in vaultRoot: URL) -> URL {
        vaultRoot.appendingPathComponent(trackerFolderName, isDirectory: true)
    }

    nonisolated static func subscriptionNoteURL(in vaultRoot: URL) -> URL {
        trackerFolderURL(in: vaultRoot)
            .appendingPathComponent(subscriptionNoteName, isDirectory: false)
    }

    /// The subscription note is the one note whose `- Name @cost(…)` lines are
    /// recurring charges and whose `##` headings are categories. Matched at
    /// `Trackers/Subscriptions.md` only, so a `Subscriptions.md` anywhere else
    /// — including the vault root — stays an ordinary note.
    ///
    /// The folder name is matched case-insensitively like the file name is: a
    /// path-string comparison is case-sensitive, and APFS is not, so `trackers/`
    /// and `Trackers/` are the same folder on disk and must read the same here.
    nonisolated static func isSubscriptionNote(_ url: URL, vaultRoot: URL) -> Bool {
        let parent = url.deletingLastPathComponent()
        return url.lastPathComponent.caseInsensitiveCompare(subscriptionNoteName)
            == .orderedSame
            && parent.lastPathComponent.caseInsensitiveCompare(trackerFolderName)
                == .orderedSame
            && parent.deletingLastPathComponent().standardizedFileURL.path
                == vaultRoot.standardizedFileURL.path
    }

    /// A `Subscriptions.md` sitting at the vault root instead of inside
    /// `Trackers/`. It is an ordinary note as far as everything else is
    /// concerned, and the tracker's empty state says so — otherwise moving the
    /// file, or making it by hand in the obvious place, shows an empty tracker
    /// with nothing explaining why.
    var misplacedSubscriptionNoteURL: URL? {
        guard let vaultURL else { return nil }
        let candidate = vaultURL.appendingPathComponent(
            Self.subscriptionNoteName, isDirectory: false)
        guard index.subscriptions.isEmpty,
            rootNode?.allFiles.contains(where: {
                $0.url.standardizedFileURL == candidate.standardizedFileURL
            }) == true
        else { return nil }
        return candidate
    }

    /// Every recurring charge, from the current index.
    var subscriptions: [Subscription] { index.subscriptions }

    /// A category already exists under that name.
    struct SubscriptionCategoryExistsError: LocalizedError {
        let name: String
        var errorDescription: String? {
            "A category named “\(name)” already exists."
        }
    }

    /// One coordinated read-modify-write of the subscription note, creating
    /// `Trackers/` first when it isn't there yet.
    ///
    /// `updateNote(named:in:)` creates the *file* on demand but not the folder
    /// holding it, so without this the very first charge fails on a vault that
    /// has never had a tracker.
    private func mutateSubscriptionNote(
        _ transform: @escaping @Sendable (String) throws -> String?
    ) async throws {
        let vaultURL = try requireOpenVaultURL()
        try await ensureTrackerFolder(in: vaultURL)
        try await mutateNote(
            named: Self.subscriptionNoteName,
            in: Self.trackerFolderURL(in: vaultURL),
            transform: transform)
    }

    /// Creates `Trackers/` unless it is already there. An existing folder is
    /// success, not a collision.
    private func ensureTrackerFolder(in vaultURL: URL) async throws {
        let folder = Self.trackerFolderURL(in: vaultURL)
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        let operations = fileOperations
        let name = Self.trackerFolderName
        do {
            try await Task.detached(priority: .userInitiated) {
                _ = try operations.createFolder(named: name, in: vaultURL)
            }.value
        } catch VaultFileOperations.OperationError.itemAlreadyExists {
            return
        }
    }

    /// Writes a new charge into the subscription note, under `category` when
    /// one is given — created on demand, since a category is only a heading.
    /// Without one the line goes into the note's unlisted region rather than
    /// the end of the file, which would otherwise file it under whichever
    /// heading happens to sit last.
    func addSubscription(
        _ draft: SubscriptionDraft,
        into category: String? = nil
    ) async throws {
        let line = try draft.validatedMarkdownLine()
        try await mutateSubscriptionNote { text in
            guard let category else {
                return try TaskListDocument.insertingUnlistedLineResult(
                    line, in: text
                ).get()
            }
            return try TaskListDocument.insertingLineResult(
                line, inSection: category, in: text
            ).get()
        }
    }

    /// Rewrites one charge's line, moving it between categories when that
    /// changed. Both halves of a move happen inside one coordinated
    /// read-modify-write, so a failure can never leave the line removed from
    /// its old category and missing from its new one.
    func updateSubscription(
        _ subscription: Subscription,
        to draft: SubscriptionDraft,
        category: String?
    ) async throws {
        let line = try draft.validatedMarkdownLine()
        let identity = subscription.identity
        let expectedStatus = subscription.status
        let newStatus = draft.status
        let staysPut =
            TaskListDocument.canonicalName(category ?? "")
            == TaskListDocument.canonicalName(subscription.category ?? "")

        try await mutateSubscriptionNote { text in
            // Every other field is inside the semantic key, so a change made
            // elsewhere makes the match fail rather than being overwritten.
            // Status is deliberately outside it — that is what lets "set this
            // to paused" find a line already paused — which leaves it the one
            // field a whole-line rewrite could silently revert. A sheet opened
            // before another device cancelled a charge must not reactivate it
            // on save.
            //
            // Writing the status the file already holds is not a revert, so it
            // is allowed: that is the idempotent replay the exclusion exists
            // for.
            let currentStatus = try SubscriptionParser.matching(
                identity, in: text
            ).status
            guard currentStatus == expectedStatus || currentStatus == newStatus
            else {
                throw SubscriptionParser.MutationError.statusChangedOnDisk(
                    currentStatus)
            }
            if staysPut {
                return try SubscriptionParser.replacingSubscriptionResult(
                    identity, with: line, in: text)
            }
            let removed = try SubscriptionParser.removingSubscriptionResult(
                identity, in: text)
            guard let category else {
                return try TaskListDocument.insertingUnlistedLineResult(
                    line, in: removed
                ).get()
            }
            return try TaskListDocument.insertingLineResult(
                line, inSection: category, in: removed
            ).get()
        }
    }

    /// Pausing, cancelling, or reactivating — the one field a row can change
    /// without opening the sheet.
    func setSubscriptionStatus(
        _ subscription: Subscription,
        to status: SubscriptionStatus
    ) async throws {
        var draft = SubscriptionDraft(subscription)
        draft.status = status
        try await updateSubscription(
            subscription, to: draft, category: subscription.category)
    }

    /// Removes one charge's line, returning what Undo needs to put it back.
    @discardableResult
    func deleteSubscription(
        _ subscription: Subscription
    ) async throws -> DeletedSubscriptionRecord {
        let url = Self.subscriptionNoteURL(in: try requireOpenVaultURL())
        let identity = subscription.identity
        // What Undo puts back is captured inside the coordinated write rather
        // than by a read before it. Status, the bullet, and spacing are all
        // outside the semantic key, so a line changed between the two reads is
        // still removed — and a preflight copy of it would restore the version
        // that no longer existed.
        let removed = CoordinatedTransformOutput<
            SubscriptionParser.ParsedSubscription
        >()
        _ = try await repository.updateNote(at: url) { text in
            let removal = try SubscriptionParser
                .removingSubscriptionWithRecordResult(identity, in: text)
            removed.record(removal.removed)
            return removal.text
        }
        await refreshIndex(changedURLs: [url])
        guard let parsed = removed.value else {
            throw SubscriptionParser.MutationError.subscriptionMissing
        }
        return DeletedSubscriptionRecord(
            identity: identity,
            originalLine: parsed.sourceLine,
            category: parsed.category,
            sourceNoteURL: url)
    }

    func restoreDeletedSubscription(
        _ record: DeletedSubscriptionRecord
    ) async throws {
        let line = record.originalLine.trimmingCharacters(in: .newlines)
        let category = record.category
        try await mutateSubscriptionNote { text in
            guard let category else {
                return try TaskListDocument.insertingUnlistedLineResult(
                    line, in: text
                ).get()
            }
            return try TaskListDocument.insertingLineResult(
                line, inSection: category, in: text
            ).get()
        }
    }

    /// Adds an empty `## name` heading to the subscription note.
    func createSubscriptionCategory(named name: String) async throws {
        // Fails fast on a closed vault; `mutateSubscriptionNote` needs the URL
        // itself and resolves it again.
        _ = try requireOpenVaultURL()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !index.subscriptionCategoryNames.contains(where: {
                TaskListDocument.canonicalName($0)
                    == TaskListDocument.canonicalName(trimmed)
            })
        else { throw SubscriptionCategoryExistsError(name: trimmed) }

        try await mutateSubscriptionNote { text in
            try TaskListDocument.addingSectionResult(named: trimmed, to: text).get()
        }
    }

    /// Renames a category's heading, keeping every charge under it.
    func renameSubscriptionCategory(
        named name: String,
        to newName: String
    ) async throws {
        _ = try requireOpenVaultURL()
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != name else { return }
        guard
            !index.subscriptionCategoryNames.contains(where: {
                TaskListDocument.canonicalName($0)
                    == TaskListDocument.canonicalName(trimmed)
                    && TaskListDocument.canonicalName($0)
                        != TaskListDocument.canonicalName(name)
            })
        else { throw SubscriptionCategoryExistsError(name: trimmed) }

        try await mutateSubscriptionNote { text in
            try TaskListDocument.renamingSectionResult(
                named: name, to: trimmed, in: text
            ).get()
        }
    }

    /// Removes a category's heading and everything filed under it, returning
    /// the exact source section for semantic Undo.
    ///
    /// This takes the charges with it, exactly as deleting a task list takes
    /// its tasks. Keeping them by relocating every line into the note's
    /// unlisted region was the alternative, and it is worse in the way that
    /// matters: it silently rewrites lines the user did not ask to touch, and
    /// its Undo cannot put them back where they were. Emptying a category
    /// first — each charge's own sheet has a Category field — is the explicit
    /// path, and the confirmation dialog says how many charges are at stake.
    @discardableResult
    func deleteSubscriptionCategory(
        named name: String
    ) async throws -> TaskListDocument.SectionRemovalRecord {
        let url = Self.subscriptionNoteURL(in: try requireOpenVaultURL())
        let preflightText = try await repository.readNote(at: url)
        let removal = try TaskListDocument.removingSectionWithRecordResult(
            named: name,
            from: preflightText
        ).get()
        _ = try await repository.updateNote(at: url) { text in
            guard text == preflightText else {
                throw VaultFileOperations.OperationError.fileChangedDuringWrite(
                    url.lastPathComponent)
            }
            return try TaskListDocument.removingSectionResult(
                named: name, from: text
            ).get()
        }
        await refreshIndex(changedURLs: [url])
        return removal.record
    }

    func restoreDeletedSubscriptionCategory(
        _ record: TaskListDocument.SectionRemovalRecord
    ) async throws {
        try await mutateSubscriptionNote { text in
            try TaskListDocument.restoringSectionResult(record, in: text).get()
        }
    }

    /// Toggles one task in its original Markdown file: re-reads the file,
    /// re-finds the task by content, rewrites the line (flipping the status,
    /// or advancing a recurring task's due date to its next occurrence), and
    /// rescans so the index reflects the change. The tree is refreshed even
    /// when the toggle fails, so a stale list corrects itself.
    ///
    /// Returns `nil` when the line was already in the state the tap asked for
    /// and nothing was written. Completion is deliberately outside the
    /// semantic key, so a checkbox another device already ticked is *found*
    /// rather than missed — which means the tap is a no-op, and an Undo
    /// registered for it would reverse a change this device never made.
    @discardableResult
    func toggleTask(_ task: TaskItem) async throws -> TaskToggleRecord? {
        let completedOn = QuickTaskParser.ymdString(from: Date())
        let desiredCompletion = !task.isCompleted
        let changed = try await setTaskCompleted(
            task,
            to: desiredCompletion,
            completedOnDateString: completedOn)
        guard changed else { return nil }
        return TaskToggleRecord(
            originalIdentity: task.identity,
            previousCompletion: task.isCompleted,
            advancedRecurrence:
                desiredCompletion && task.recurrence != nil,
            completedOnDateString: completedOn)
    }

    /// Idempotent semantic completion used by the app, Undo, and widget
    /// retries. The transform re-parses the newest coordinated file text.
    func setTaskCompleted(_ task: TaskItem, to desiredCompletion: Bool) async throws {
        _ = try await setTaskCompleted(
            task,
            to: desiredCompletion,
            completedOnDateString: QuickTaskParser.ymdString(from: Date()))
    }

    /// Whether the coordinated write actually changed the file.
    @discardableResult
    private func setTaskCompleted(
        _ task: TaskItem,
        to desiredCompletion: Bool,
        completedOnDateString: String
    ) async throws -> Bool {
        let identity = task.identity
        var toggleError: Error?
        var changed = false
        do {
            changed = try await repository.updateNote(at: task.fileURL) { text in
                try TaskParser.settingTaskCompletedResult(
                    identity,
                    to: desiredCompletion,
                    todayDateString: completedOnDateString,
                    in: text
                ).get()
            }.changed
        } catch {
            toggleError = error
        }
        await refreshIndex(changedURLs: [task.fileURL])
        if let toggleError { throw toggleError }
        return changed
    }

    /// Semantic inverse of one completed toggle. Recurring completion moved
    /// the due date (and may have inserted an anchor), so it has a dedicated
    /// inverse; ordinary toggles restore only their checkbox character.
    func undoTaskToggle(_ record: TaskToggleRecord) async throws {
        let url = record.originalIdentity.fileURL
        var undoError: Error?
        do {
            _ = try await repository.updateNote(at: url) { text in
                if record.advancedRecurrence {
                    return try TaskParser.revertingRecurringCompletionResult(
                        record.originalIdentity,
                        completedOn: record.completedOnDateString,
                        in: text
                    ).get()
                }
                return try TaskParser.restoringCheckboxStateResult(
                    record.originalIdentity,
                    to: record.previousCompletion,
                    in: text
                ).get()
            }
        } catch {
            undoError = error
        }
        await refreshIndex(changedURLs: [url])
        if let undoError { throw undoError }
    }

    /// Rewrites one task's title and schedule in place.
    ///
    /// Rescheduling used to mean opening the note and editing Markdown by
    /// hand, which is the one thing every other task action on these screens
    /// does not ask for. The write is the same shape as the rest: re-read
    /// under coordination, re-find the line semantically, refuse when that is
    /// not unique, and rescan afterwards whether or not it succeeded.
    ///
    /// Returns `nil` when the edited line cannot be read back as a task, which
    /// leaves the edit in place but registers no Undo — the alternative is an
    /// Undo record pointing at a line the parser does not agree exists.
    @discardableResult
    func updateTask(_ task: TaskItem, to draft: TaskDraft) async throws -> TaskEditRecord? {
        // `@due` is optional only inside a list section of the capture note,
        // so an unlisted task cannot be edited into an undated one — it would
        // simply stop being a task.
        guard draft.dueDateString != nil || task.listName != nil else {
            throw TaskUpdateError.dueDateRequired
        }
        let body = try draft.validatedLineBody()
        let identity = task.identity
        let keepsAnchor = draft.hasSameSchedule(as: task)
        let editedLine = CoordinatedTransformOutput<String>()
        let previousBody = CoordinatedTransformOutput<String>()
        var editError: Error?
        do {
            _ = try await repository.updateNote(at: task.fileURL) { text in
                let replacement = try TaskParser.replacingTaskResult(
                    identity,
                    withBody: body,
                    keepingRecurrenceAnchor: keepsAnchor,
                    in: text
                ).get()
                editedLine.record(replacement.newLine)
                previousBody.record(replacement.previousBody)
                return replacement.text
            }
        } catch {
            editError = error
        }
        await refreshIndex(changedURLs: [task.fileURL])
        if let editError { throw editError }
        guard let editedLine = editedLine.value,
            let previousBody = previousBody.value,
            let editedIdentity = Self.identity(
                forLine: editedLine,
                in: task.fileURL,
                list: task.listName,
                isSectionedDocument: task.isSectionedDocument)
        else { return nil }
        return TaskEditRecord(
            identity: editedIdentity,
            noteURL: task.fileURL,
            previousBody: previousBody)
    }

    /// Puts one edit's line back exactly as it was, anchor included — the body
    /// it restores is the one the coordinated write replaced.
    func undoTaskEdit(_ record: TaskEditRecord) async throws {
        var undoError: Error?
        do {
            _ = try await repository.updateNote(at: record.noteURL) { text in
                try TaskParser.replacingTaskResult(
                    record.identity,
                    withBody: record.previousBody,
                    // The body being restored already carries whatever anchor
                    // the line had; keeping the edited line's would append a
                    // second one.
                    keepingRecurrenceAnchor: false,
                    in: text
                ).get().text
            }
        } catch {
            undoError = error
        }
        await refreshIndex(changedURLs: [record.noteURL])
        if let undoError { throw undoError }
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
        // The line Undo puts back is the one the coordinated write took out,
        // not the one the index last saw: completion, the bullet, and interior
        // spacing are all outside the semantic key, so a line edited elsewhere
        // is still found — and restoring the index's copy of it would quietly
        // undo that edit too.
        let removedLine = CoordinatedTransformOutput<String>()
        var deleteError: Error?
        do {
            _ = try await repository.updateNote(at: task.fileURL) { text in
                let removal = try TaskParser.removingTaskWithLineResult(
                    identity, in: text
                ).get()
                removedLine.record(removal.removedLine)
                return removal.text
            }
        } catch {
            deleteError = error
        }
        await refreshIndex(changedURLs: [task.fileURL])
        if let deleteError { throw deleteError }
        return Self.deletedTaskRecord(
            for: task,
            among: siblings,
            originalLine: removedLine.value)
    }

    func restoreDeletedTask(_ record: DeletedTaskRecord) async throws {
        try await restoreDeletedTasks([record])
    }

    /// Restores task lines semantically against the newest coordinated file
    /// contents. Used by both single-delete Undo and grouped bulk-clear Undo,
    /// so later prose or task edits are never replaced with an old snapshot.
    func restoreDeletedTasks(_ records: [DeletedTaskRecord]) async throws {
        let batches = Dictionary(grouping: records, by: \.sourceNoteURL)
        var changedURLs: Set<URL> = []
        var restoreError: Error?
        do {
            for (url, records) in batches.sorted(by: { $0.key.path < $1.key.path }) {
                _ = try await repository.updateNote(at: url) { text in
                    try Self.restoringDeletedTasks(records, in: text)
                }
                changedURLs.insert(url)
            }
        } catch {
            restoreError = error
        }
        await refreshIndex(changedURLs: changedURLs.union(batches.keys))
        if let restoreError { throw restoreError }
    }

    nonisolated private static func restoringDeletedTasks(
        _ records: [DeletedTaskRecord],
        in originalText: String
    ) throws -> String {
        var text = originalText
        for record in records.sorted(by: {
            $0.approximateLineNumber < $1.approximateLineNumber
        }) {
            text = try restoringDeletedTask(record, in: text)
        }
        return text
    }

    nonisolated private static func restoringDeletedTask(
        _ record: DeletedTaskRecord,
        in text: String
    ) throws -> String {
        // Undo is idempotent and never restores the entire old document.
        switch TaskParser.matchResult(record.identity, in: text) {
        case .matched:
            return text
        case .ambiguous(let matches):
            throw TaskParser.MutationError.ambiguousTask(
                matches.map(\.lineNumber))
        case .missing:
            break
        }

        let insertionLocation: Int
        if let next = record.nextIdentity,
            case .matched(let match) = TaskParser.matchResult(next, in: text)
        {
            insertionLocation = match.lineRange.location
        } else if let previous = record.previousIdentity,
            case .matched(let match) = TaskParser.matchResult(previous, in: text)
        {
            insertionLocation = NSMaxRange(match.lineRange)
        } else {
            insertionLocation = lineStart(
                for: record.approximateLineNumber, in: text)
        }

        var line = record.originalLine
        if insertionLocation == (text as NSString).length,
            !text.isEmpty, !text.hasSuffix("\n"), !text.hasSuffix("\r")
        {
            line = "\n" + line
        }
        return (text as NSString).replacingCharacters(
            in: NSRange(location: insertionLocation, length: 0),
            with: line)
    }

    /// `originalLine` is the text the coordinated removal actually took out,
    /// when the caller had one. The index's own copy is the fallback for the
    /// bulk paths, which preflight completion against the coordinated bytes
    /// before they remove anything.
    nonisolated private static func deletedTaskRecord(
        for task: TaskItem,
        among siblings: [TaskItem],
        originalLine: String? = nil
    ) -> DeletedTaskRecord {
        let siblingIndex = siblings.firstIndex {
            $0.identity == task.identity
        }
        let previous = siblingIndex.flatMap {
            $0 > 0 ? siblings[$0 - 1].identity : nil
        }
        let next = siblingIndex.flatMap {
            $0 + 1 < siblings.count ? siblings[$0 + 1].identity : nil
        }
        return DeletedTaskRecord(
            identity: task.identity,
            originalLine: originalLine
                ?? task.sourceLine ?? markdownLine(for: task) + "\n",
            previousIdentity: previous,
            nextIdentity: next,
            approximateLineNumber: task.lineNumber,
            sourceNoteURL: task.fileURL)
    }

    nonisolated private static func removingDeletedTasks(
        _ records: [DeletedTaskRecord],
        from originalText: String
    ) throws -> String {
        // Preflight every identity before producing a mutation. If a task was
        // completed in the index but has since been reopened, a bulk clear
        // must not delete that now-incomplete line.
        for record in records {
            switch TaskParser.matchResult(record.identity, in: originalText) {
            case .matched(let task) where task.isCompleted:
                continue
            case .matched, .missing:
                throw TaskParser.MutationError.taskMissing
            case .ambiguous(let tasks):
                throw TaskParser.MutationError.ambiguousTask(
                    tasks.map(\.lineNumber))
            }
        }

        var text = originalText
        for record in records.sorted(by: {
            $0.approximateLineNumber > $1.approximateLineNumber
        }) {
            text = try TaskParser.removingTaskResult(
                record.identity,
                in: text
            ).get()
        }
        return text
    }

    private func rollbackClearedTaskBatches(
        _ batches: [(URL, [DeletedTaskRecord])]
    ) async -> Error? {
        var firstError: Error?
        for (url, records) in batches.reversed() {
            do {
                _ = try await repository.updateNote(at: url) { text in
                    try Self.restoringDeletedTasks(records, in: text)
                }
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        return firstError
    }

    nonisolated private static func markdownLine(for task: TaskItem) -> String {
        var line = "- [\(task.isCompleted ? "x" : " ")] \(task.text)"
        if let date = task.dueDateString {
            line += " @due(\(date)"
            if let time = task.dueTimeString { line += " \(time)" }
            line += ")"
            if let recurrence = task.recurrence {
                line += " @repeat(\(recurrence.tagText))"
                if let anchor = task.recurrenceAnchorDateString {
                    line += " @anchor(\(anchor))"
                }
            }
        }
        return line
    }

    nonisolated private static func lineStart(for lineNumber: Int, in text: String) -> Int {
        let ns = text as NSString
        var currentLine = 0
        var result = ns.length
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: [.byLines, .substringNotRequired]
        ) {
            _, lineRange, _, stop in
            if currentLine == lineNumber {
                result = lineRange.location
                stop.pointee = true
            }
            currentLine += 1
        }
        return result
    }

    /// Removes the completed tasks represented by the current index. Every
    /// file is preflighted before the first write, and a later failure rolls
    /// back earlier batches semantically. The returned records power grouped
    /// Undo without replacing unrelated edits made after the clear.
    @discardableResult
    func clearCompletedTasks() async throws -> [DeletedTaskRecord] {
        try await clearCompletedTaskRecords(index.completedTasks)
    }

    /// Writes a quick-added task's Markdown line into the capture note at the
    /// vault root, then rescans (which also reschedules notifications).
    /// With a `list`, the line goes under that `##` heading, created if it's
    /// missing. Without one, it goes into the note's unlisted region rather
    /// than the end of the file, which would otherwise put it inside the last
    /// list and hide it from the Tasks screen.
    /// What one capture wrote, and enough to take it back.
    ///
    /// The identity is built by parsing the line Cove just generated, which is
    /// the same round trip every generated line already makes — so Undo can
    /// only ever target a line the parser agrees exists, and it re-finds that
    /// line semantically rather than by remembering where it was put.
    struct CapturedTaskRecord: Sendable {
        let identity: TaskIdentity
        let noteURL: URL
        let listName: String?
    }

    @discardableResult
    func captureTask(
        _ draft: TaskDraft,
        into list: String? = nil
    ) async throws -> CapturedTaskRecord? {
        let vaultURL = try requireOpenVaultURL()
        let line = try draft.validatedMarkdownLine()
        let noteURL = try await mutateNote(
            named: Self.quickTaskNoteName, in: vaultURL
        ) { text in
            guard let list else {
                return try TaskListDocument.insertingUnlistedLineResult(
                    line,
                    in: text
                ).get()
            }
            guard TaskListDocument.containsSection(named: list, in: text) else {
                throw TaskListDocument.EditError.missingSection(list)
            }
            return try TaskListDocument.insertingLineResult(
                line,
                inSection: list,
                in: text
            ).get()
        }
        guard
            let identity = Self.identity(
                forLine: line, in: noteURL, list: list,
                isSectionedDocument: true)
        else { return nil }
        return CapturedTaskRecord(
            identity: identity, noteURL: noteURL, listName: list)
    }

    /// The identity of a line Cove has just written or is about to write, read
    /// back out of the parser rather than assembled by hand.
    ///
    /// A list item is parsed under a synthetic heading, because a line's list
    /// is context the line itself does not carry — and the list is part of
    /// what re-finds it, so dropping it here would make Undo miss the very
    /// line the write produced.
    ///
    /// `isSectionedDocument` travels with the identity because it decides how
    /// the *note* is re-parsed later: a capture always lands in the sectioned
    /// capture note, while an edit can be to a task in any note, where a `##`
    /// heading means nothing at all.
    nonisolated private static func identity(
        forLine line: String,
        in noteURL: URL,
        list: String?,
        isSectionedDocument: Bool
    ) -> TaskIdentity? {
        let sectioned = isSectionedDocument || list != nil
        let text = list.map { "## \($0)\n\(line)\n" } ?? "\(line)\n"
        guard let task = TaskParser.tasks(in: text, sectioned: sectioned).first
        else { return nil }
        return TaskIdentity(
            filePath: noteURL.path,
            lineNumber: task.lineNumber,
            text: task.text,
            dueDateString: task.dueDateString,
            dueTimeString: task.dueTimeString,
            recurrenceTag: task.recurrence?.tagText,
            listName: task.listName,
            recurrenceAnchorDateString: task.recurrenceAnchorDateString,
            isSectionedDocument: sectioned)
    }

    /// Takes back one capture. Every other mutating task action registers
    /// Undo; return in the quick-entry field wrote straight to the note with
    /// nothing between a mis-parsed sentence and the file but the live
    /// preview. Removal re-finds the line semantically and refuses on
    /// ambiguity, exactly as a swipe-delete does.
    func undoCapturedTask(_ record: CapturedTaskRecord) async throws {
        var removeError: Error?
        do {
            _ = try await repository.updateNote(at: record.noteURL) { text in
                try TaskParser.removingTaskResult(record.identity, in: text).get()
            }
        } catch {
            removeError = error
        }
        await refreshIndex(changedURLs: [record.noteURL])
        if let removeError { throw removeError }
    }

    // MARK: - Lists

    /// A list already exists under that name.
    struct ListExistsError: LocalizedError {
        let name: String
        var errorDescription: String? { "A list named “\(name)” already exists." }
    }

    /// Adds an empty `## name` heading to the capture note.
    func createList(named name: String) async throws {
        let vaultURL = try requireOpenVaultURL()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !index.listNames.contains(where: {
                TaskListDocument.canonicalName($0)
                    == TaskListDocument.canonicalName(trimmed)
            })
        else { throw ListExistsError(name: trimmed) }

        try await mutateNote(named: Self.quickTaskNoteName, in: vaultURL) { text in
            try TaskListDocument.addingSectionResult(
                named: trimmed,
                to: text
            ).get()
        }
    }

    /// Renames a list's heading, keeping its items under it.
    func renameList(named name: String, to newName: String) async throws {
        let vaultURL = try requireOpenVaultURL()
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != name else { return }
        guard
            !index.listNames.contains(where: {
                TaskListDocument.canonicalName($0)
                    == TaskListDocument.canonicalName(trimmed)
                    && TaskListDocument.canonicalName($0)
                        != TaskListDocument.canonicalName(name)
            })
        else { throw ListExistsError(name: trimmed) }

        try await mutateNote(named: Self.quickTaskNoteName, in: vaultURL) { text in
            try TaskListDocument.renamingSectionResult(
                named: name,
                to: trimmed,
                in: text
            ).get()
        }
    }

    /// Removes a list's completed items, leaving its open ones and its
    /// heading in place. The capture note is the only file lists live in, so
    /// this is one coordinated read-modify-write rather than the per-file
    /// sweep the Tasks screen's Clear All needs.
    @discardableResult
    func clearCompletedTasks(inList name: String) async throws -> [DeletedTaskRecord] {
        guard
            let list = index.lists.first(where: {
                TaskListDocument.canonicalName($0.name)
                    == TaskListDocument.canonicalName(name)
            })
        else {
            throw TaskListDocument.EditError.missingSection(name)
        }
        return try await clearCompletedTaskRecords(list.completedTasks)
    }

    private func clearCompletedTaskRecords(
        _ tasks: [TaskItem]
    ) async throws -> [DeletedTaskRecord] {
        guard !tasks.isEmpty else { return [] }
        let tasksByURL = Dictionary(grouping: tasks, by: \.fileURL)
        let batches: [(URL, [DeletedTaskRecord])] =
            tasksByURL
            .map { url, tasks in
                let siblings = index.allTasks
                    .filter {
                        $0.fileURL.standardizedFileURL
                            == url.standardizedFileURL
                    }
                    .sorted { $0.lineNumber < $1.lineNumber }
                return (
                    url,
                    tasks.map {
                        Self.deletedTaskRecord(
                            for: $0,
                            among: siblings)
                    }
                )
            }
            .sorted { $0.0.path < $1.0.path }

        // Refuse the whole operation before writing when any target is
        // already stale. The write transforms repeat the same checks against
        // coordinated current bytes.
        for (url, records) in batches {
            let text = try await repository.readNote(at: url)
            _ = try Self.removingDeletedTasks(records, from: text)
        }

        var applied: [(URL, [DeletedTaskRecord])] = []
        do {
            for (url, records) in batches {
                _ = try await repository.updateNote(at: url) { text in
                    try Self.removingDeletedTasks(
                        records,
                        from: text)
                }
                applied.append((url, records))
            }
        } catch {
            let rollbackError = await rollbackClearedTaskBatches(applied)
            await refreshIndex(changedURLs: Set(batches.map(\.0)))
            if let rollbackError {
                reportStorageIssue(
                    "Cove could not fully roll back a failed bulk clear: \(rollbackError.localizedDescription)"
                )
            }
            throw error
        }

        await refreshIndex(changedURLs: Set(batches.map(\.0)))
        return batches.flatMap(\.1)
    }

    /// Removes a list's heading and content while returning its exact source
    /// section for semantic Undo.
    @discardableResult
    func deleteList(
        named name: String
    ) async throws -> TaskListDocument.SectionRemovalRecord {
        let vaultURL = try requireOpenVaultURL()
        let url = vaultURL.appendingPathComponent(
            Self.quickTaskNoteName,
            isDirectory: false)
        let preflightText = try await repository.readNote(at: url)
        let removal = try TaskListDocument.removingSectionWithRecordResult(
            named: name,
            from: preflightText
        ).get()
        _ = try await repository.updateNote(at: url) { text in
            guard text == preflightText else {
                throw VaultFileOperations.OperationError.fileChangedDuringWrite(
                    url.lastPathComponent)
            }
            return try TaskListDocument.removingSectionResult(
                named: name,
                from: text
            ).get()
        }
        await refreshIndex(changedURLs: [url])
        return removal.record
    }

    func restoreDeletedList(
        _ record: TaskListDocument.SectionRemovalRecord
    ) async throws {
        let vaultURL = try requireOpenVaultURL()
        let url = vaultURL.appendingPathComponent(
            Self.quickTaskNoteName,
            isDirectory: false)
        _ = try await repository.updateNote(at: url) { text in
            try TaskListDocument.restoringSectionResult(
                record,
                in: text
            ).get()
        }
        await refreshIndex(changedURLs: [url])
    }

    private func requireOpenVaultURL() throws -> URL {
        guard state == .open, let vaultURL else {
            throw VaultUnavailableError()
        }
        return vaultURL
    }

    /// Runs one coordinated mutation off the main actor, then rescans so the
    /// tree reflects the app-created change.
    private func perform(_ operation: @escaping @Sendable (VaultFileOperations) throws -> Void) async throws {
        try await performReturning(operation)
    }

    /// `perform` for an operation whose result the caller needs — the URL a
    /// create produced, say. The rescan still happens before the value comes
    /// back, so a caller that navigates to it finds it in the tree.
    @discardableResult
    private func performReturning<T: Sendable>(
        _ operation: @escaping @Sendable (VaultFileOperations) throws -> T
    ) async throws -> T {
        let ops = fileOperations
        let result = try await Task.detached(priority: .userInitiated) {
            try operation(ops)
        }.value
        await refresh()
        return result
    }

    /// The capture note is created on demand, so a mutation that lands in a
    /// note the tree has never seen is a structural change and takes the full
    /// rescan; every later write to it only changes contents.
    @discardableResult
    private func mutateNote(
        named name: String,
        in folder: URL,
        transform: @escaping @Sendable (String) throws -> String?
    ) async throws -> URL {
        let url = try await repository.updateNote(
            named: name, in: folder,
            transform: transform)
        if isInTree(url) {
            await refreshIndex(changedURLs: [url])
        } else {
            await refresh()
        }
        return url
    }

    private func isInTree(_ url: URL) -> Bool {
        rootNode?.allFiles.contains {
            $0.url.standardizedFileURL == url.standardizedFileURL
        } ?? false
    }

    private func loadTree(
        from url: URL,
        coalescing: Bool = false,
        changedURLs: Set<URL>? = nil,
        reusingTree: Bool = false,
        deferDerivedState: Bool = false
    ) async {
        let existingTree =
            reusingTree && treeIsCurrent
                && vaultURL?.standardizedFileURL == url.standardizedFileURL
            ? rootNode : nil
        if existingTree == nil { treeIsCurrent = false }
        loadGeneration &+= 1
        let generation = loadGeneration
        requestedVaultURL = url
        // Coalescing cancels the load in flight, so a targeted refresh that
        // is superseded inside the debounce window would otherwise take its
        // changed notes down with it — save two notes 100 ms apart and the
        // first one's index entry stays stale until the next full rescan.
        // The pending set accumulates instead, and only a full rescan (which
        // re-reads everything anyway) clears it.
        if let changedURLs {
            pendingChangedURLs.formUnion(changedURLs)
        } else {
            pendingChangedURLs.removeAll()
        }
        let accumulated = changedURLs == nil ? nil : pendingChangedURLs
        refreshTask?.cancel()

        let task = Task { [weak self] in
            if coalescing {
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }
            }
            await self?.performLoad(
                from: url,
                generation: generation,
                changedURLs: accumulated,
                existingTree: existingTree,
                deferDerivedState: deferDerivedState)
        }
        refreshTask = task
        await task.value
    }

    private func performLoad(
        from url: URL,
        generation: UInt64,
        changedURLs: Set<URL>?,
        existingTree: VaultNode?,
        deferDerivedState: Bool
    ) async {
        guard isCurrentLoad(generation: generation, url: url) else { return }
        let startedAt = Date()
        let loadOperation = self.loadOperation
        let previousIndex = index
        // Toggles the widget couldn't write itself are applied first, so the
        // scan that follows already sees them and the index is built once.
        // A candidate vault is deliberately excluded until its bookmark has
        // committed; otherwise a failed folder switch could consume a queue
        // against a vault the user never actually selected.
        let widgetChanges =
            deferDerivedState
            ? Set<URL>()
            : await applyPendingWidgetOperations(vaultRoot: url)
        let effectiveChanges: Set<URL>?
        if changedURLs == nil {
            effectiveChanges = nil
        } else {
            effectiveChanges = changedURLs!.union(widgetChanges)
        }
        guard isCurrentLoad(generation: generation, url: url) else { return }

        let scanTask = Task {
            try await loadOperation(
                url, previousIndex, effectiveChanges, existingTree)
        }
        do {
            let (node, index) = try await withTaskCancellationHandler {
                try await scanTask.value
            } onCancel: {
                scanTask.cancel()
            }
            guard isCurrentLoad(generation: generation, url: url) else { return }
            // The changed notes this load carried are now in the index, so
            // the next targeted refresh starts from an empty set.
            pendingChangedURLs.subtract(effectiveChanges ?? pendingChangedURLs)
            rootNode = node
            treeIsCurrent = true
            self.index = index
            vaultURL = url
            lastErrorDescription = nil
            state = .open
            startObservingChanges(at: url)
            if !deferDerivedState {
                await reconcileDerivedState(for: index)
                guard isCurrentLoad(generation: generation, url: url) else {
                    return
                }
                // A full scan is the load that follows a delete, a restore, or
                // an app return, so it always recounts; a targeted one cannot
                // have moved either number.
                await refreshStorageCounts(
                    at: url, force: effectiveChanges == nil)
            }
            CoveLog.index.info(
                "Vault indexing completed in \(Date().timeIntervalSince(startedAt), privacy: .private) seconds."
            )
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentLoad(generation: generation, url: url) else { return }
            CoveLog.vault.error("Vault load failed: \(error.localizedDescription, privacy: .private)")
            if let lastGoodURL = vaultURL, rootNode != nil, state == .open {
                // A transient provider, metadata, or decoding failure during
                // refresh must not tear down a valid session or cancel all of
                // its derived state. Keep showing the last-good snapshot and
                // retry on the next observer/foreground refresh.
                requestedVaultURL = lastGoodURL
                treeIsCurrent = true
                lastErrorDescription =
                    "Cove could not refresh the vault. The last known-good view is still open. \(error.localizedDescription)"
                startObservingChanges(at: lastGoodURL)
            } else {
                endAccess()
                rootNode = nil
                treeIsCurrent = false
                index = VaultIndex()
                vaultURL = nil
                lastErrorDescription = error.localizedDescription
                state = .recoveryNeeded
                await publishUnavailableDerivedState()
            }
        }
    }

    private func isCurrentLoad(generation: UInt64, url: URL) -> Bool {
        generation == loadGeneration
            && requestedVaultURL?.standardizedFileURL == url.standardizedFileURL
    }

    /// Reconciles the task notifications and the widget from one index
    /// snapshot — but only when that snapshot could actually change either.
    ///
    /// Both are derived from the *tasks*, and a rebuild happens for any
    /// content change at all: typing a sentence into an ordinary note used to
    /// rewrite the widget snapshot and diff every pending notification for a
    /// task set that had not moved. The fingerprint is the task set plus the
    /// day, because a widget snapshot is built for a particular day and a
    /// snapshot built for another one reads as empty.
    private func reconcileDerivedState(for index: VaultIndex) async {
        let tasks = index.allTasks
        let fingerprint = Self.derivedStateFingerprint(for: tasks)
        guard fingerprint != lastDerivedStateFingerprint else { return }
        lastDerivedStateFingerprint = fingerprint
        publishWidgetState(tasks: tasks)
        let health = await rebuildNotifications(tasks)
        if health.state != .superseded {
            notificationHealth = health
        }
    }

    /// Reconciles even when the task set has not moved.
    ///
    /// Newly granted notification permission is exactly that case: nothing
    /// about the tasks changed, and nothing is scheduled either — so the
    /// fingerprint would skip the one rebuild that matters. The same is true
    /// of a retry after a scheduling failure.
    func rescheduleDerivedState() async {
        lastDerivedStateFingerprint = nil
        guard state == .open else { return }
        await reconcileDerivedState(for: index)
    }

    nonisolated private static func derivedStateFingerprint(
        for tasks: [TaskItem]
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(tasks)
        // The day, so a snapshot published yesterday is rebuilt today even
        // when not one task line has changed.
        hasher.combine(
            TaskCalendar.gregorian().startOfDay(for: Date()))
        return hasher.finalize()
    }

    /// Counts what is sitting in the recovery area and the draft store.
    ///
    /// `force` is every full scan — vault open, a structural change, a
    /// foreground rescan — because those are the moments a delete or a
    /// restore has just happened. A targeted refresh (a checkbox, a capture)
    /// cannot have changed either count, so it is throttled rather than
    /// walking two directories behind every tap. The cost of the throttle is
    /// that a draft written moments ago may not be counted until the next
    /// full scan, which the scene-activation rescan guarantees.
    private func refreshStorageCounts(
        at vaultRoot: URL,
        force: Bool = false
    ) async {
        if !force, let last = lastStorageCountAt,
            Date().timeIntervalSince(last) < Self.storageCountInterval
        {
            return
        }
        lastStorageCountAt = Date()
        let operations = fileOperations
        let draftStore = EditorRecoveryDraftStore()
        do {
            let counts = try await Task.detached(priority: .utility) {
                let draftCount = try draftStore.summaries().filter {
                    Self.isInside(vaultRoot, $0.originalURL)
                }.count
                return (
                    try operations.recoveryRecords(vaultRoot: vaultRoot).count,
                    draftCount
                )
            }.value
            guard
                vaultURL?.standardizedFileURL
                    == vaultRoot.standardizedFileURL
            else { return }
            recoveryItemCount = counts.0
            recoveryDraftCount = counts.1
        } catch {
            reportStorageIssue(
                "Cove could not inspect recovery storage: \(error.localizedDescription)")
        }
    }

    // MARK: - Widget

    /// Publishes what the widget extension needs into the shared App Group
    /// container: today's tasks to draw, and the vault bookmark so a tapped
    /// checkbox can reach the note itself. Runs on every index rebuild, which
    /// is the same set of moments that reschedules notifications.
    private func publishWidgetState(tasks: [TaskItem]) {
        var failures: [String] = []
        if case .failure(let error) = widgetStore.writeSnapshot(
            TodaySnapshot.building(for: Date(), from: tasks))
        {
            failures.append(error.localizedDescription)
        }
        if let bookmark = bookmarkStore.bookmarkData {
            if case .failure(let error) = widgetStore.writeBookmark(bookmark) {
                failures.append(error.localizedDescription)
            }
        }
        widgetHealth = widgetStore.health()
        #if os(iOS)
            if !failures.isEmpty {
                reportStorageIssue(
                    "Cove could not update the Today widget: "
                        + failures.joined(separator: " "))
            }
        #endif
        reloadWidgetTimelines()
    }

    /// Clears derived state when there is intentionally no usable vault.
    /// This is awaited so old task reminders cannot survive a stale bookmark,
    /// while the widget receives an explicit reconnect state rather than a
    /// misleading successful “All clear.”
    private func publishUnavailableDerivedState() async {
        // Whatever was reconciled belonged to a vault that is no longer open,
        // so the next reconcile must run rather than compare against it.
        lastDerivedStateFingerprint = nil
        lastStorageCountAt = nil
        notificationHealth = await cancelNotifications()
        if case .failure(let error) =
            widgetStore.writeUnavailableSnapshot(.vaultUnavailable)
        {
            #if os(iOS)
                reportStorageIssue(
                    "Cove could not mark the Today widget unavailable: \(error.localizedDescription)"
                )
            #endif
        }
        widgetHealth = widgetStore.health()
        reloadWidgetTimelines()
    }

    /// Applies toggles the widget recorded but couldn't write — the extension
    /// may not be able to resolve the vault bookmark from its own process.
    /// Each one goes through the same re-find-then-rewrite path as an in-app
    /// toggle, so a line that changed meanwhile is left alone rather than
    /// overwritten.
    ///
    /// Operations are acknowledged individually, on success or against a
    /// definitively stale target. A transient failure keeps the operation
    /// queued but counts an attempt against it, so a tap survives an
    /// unavailable vault without an unappliable one being retried on every
    /// launch forever.
    private func applyPendingWidgetOperations(
        vaultRoot: URL
    ) async -> Set<URL> {
        let pending: [PendingTaskOperation]
        do {
            pending = try widgetStore.loadPendingOperations()
        } catch {
            // A missing App Group is normal for the ad-hoc macOS build. A
            // malformed or inaccessible iOS queue is retained for diagnosis
            // and retry rather than being replaced with an empty file.
            CoveLog.widget.error(
                "Pending operation queue load failed: \(error.localizedDescription, privacy: .private)")
            #if os(iOS)
                reportStorageIssue(
                    "Cove could not read pending Today widget changes: \(error.localizedDescription)"
                )
            #endif
            widgetHealth = widgetStore.health()
            return []
        }
        guard !pending.isEmpty else {
            widgetHealth = widgetStore.health()
            return []
        }

        let today = QuickTaskParser.ymdString(from: Date())
        var changedURLs: Set<URL> = []
        var resolutions: [WidgetQueueResolution] = []
        for operation in pending {
            // A queued path that doesn't resolve inside the vault now open —
            // a note deleted and replaced by a folder, an operation left over
            // from a vault the user has since swapped away from — can never
            // apply, so it is dropped rather than retried.
            guard let noteURL = operation.taskIdentity.fileURL(within: vaultRoot) else {
                resolutions.append(
                    .recordFailure(operation.id, .staleTarget))
                continue
            }
            do {
                let result = try await repository.updateNote(at: noteURL) {
                    text in
                    try TaskParser.settingTaskCompletedResult(
                        operation.taskIdentity,
                        to: operation.desiredCompletion,
                        todayDateString: today,
                        in: text
                    ).get()
                }
                if result.changed {
                    changedURLs.insert(noteURL)
                    resolutions.append(.acknowledge(operation.id))
                    continue
                }
                switch TaskParser.matchResult(
                    operation.taskIdentity,
                    in: result.resultingText)
                {
                case .matched(let task)
                where task.isCompleted == operation.desiredCompletion:
                    resolutions.append(.acknowledge(operation.id))
                case .missing:
                    resolutions.append(
                        .recordFailure(operation.id, .staleTarget))
                case .ambiguous(_), .matched(_):
                    resolutions.append(
                        .recordFailure(operation.id, .retryLimitExceeded))
                }
            } catch VaultFileOperations.OperationError.fileMissing(_) {
                // A deleted note is a definitive stale target, not a
                // transient provider failure.
                resolutions.append(
                    .recordFailure(operation.id, .staleTarget))
            } catch TaskParser.MutationError.taskMissing {
                resolutions.append(
                    .recordFailure(operation.id, .staleTarget))
            } catch {
                // Normal file/coordinator/iCloud failures stay queued, up to
                // the attempt ceiling.
                resolutions.append(
                    .recordFailure(operation.id, .retryLimitExceeded))
                CoveLog.widget.error(
                    "Pending operation retained after failure: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
        do {
            let result = try widgetStore.applyQueueResolutions(resolutions)
            if result.failedPermanentlyCount > 0 {
                #if os(iOS)
                    reportStorageIssue(
                        "\(result.failedPermanentlyCount) Today widget change could not be applied. Review Widget health in Settings."
                    )
                #endif
            }
        } catch {
            // Note changes may already be durable. Leaving the queue intact is
            // intentional: desired-state replay is idempotent and safer than
            // claiming those operations were acknowledged.
            CoveLog.widget.error(
                "Widget operation bookkeeping failed: \(error.localizedDescription, privacy: .private)"
            )
            #if os(iOS)
                reportStorageIssue(
                    "Cove applied widget changes but could not update their queue: \(error.localizedDescription)"
                )
            #endif
        }
        widgetHealth = widgetStore.health()
        return changedURLs
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
        observer.onConflict = { [weak self] conflicts in
            guard let self else { return }
            Task { await self.materializeNativeConflicts(at: conflicts) }
        }
        observer.onIssue = { [weak self] issue in
            self?.reportStorageIssue(issue)
        }
        observer.start()
        changeObserver = observer
    }

    private func handleExternalChange(_ changes: Set<URL>) async {
        externalChangeCount += 1
        unresolvedConflictURLs.subtract(changes)
        unresolvedConflictURLs.formUnion(
            changes.filter {
                !(NSFileVersion.unresolvedConflictVersionsOfItem(at: $0) ?? [])
                    .isEmpty
            })
        guard let url = requestedVaultURL ?? vaultURL else { return }
        await loadTree(
            from: url,
            coalescing: true,
            changedURLs: Self.changedURLsForRefresh(
                changes, vaultRoot: url))
    }

    /// macOS' root descriptor reports only that something below the vault
    /// changed. Treating that root URL as a targeted file refresh reuses the
    /// old tree and can miss same-size, timestamp-preserving edits as well as
    /// newly added or removed paths. A root event therefore requests the safe
    /// fallback: a fresh tree scan and full index rebuild.
    nonisolated static func changedURLsForRefresh(
        _ changes: Set<URL>,
        vaultRoot: URL
    ) -> Set<URL>? {
        guard !changes.isEmpty else { return nil }
        let root = vaultRoot.standardizedFileURL
        guard
            !changes.contains(where: {
                $0.standardizedFileURL == root
            })
        else { return nil }
        return changes
    }

    private func materializeNativeConflicts(at conflicts: Set<URL>) async {
        unresolvedConflictURLs.formUnion(conflicts)
        let operations = fileOperations
        do {
            let copies = try await Task.detached(priority: .utility) {
                try conflicts.flatMap {
                    try operations.materializeUnresolvedConflictVersions(at: $0)
                }
            }.value
            conflictReviewURLs.formUnion(copies)
            if let first = copies.first {
                reportStorageIssue(
                    copies.count == 1
                        ? "Cove preserved an unresolved iCloud version as \(first.lastPathComponent). Review both notes; Cove has not marked the conflict resolved."
                        : "Cove preserved \(copies.count) unresolved iCloud versions as conflict notes. Review them in Notes; Cove has not marked the conflicts resolved."
                )
                await refresh()
            } else {
                reportStorageIssue(
                    "An unresolved iCloud conflict needs review. Cove has not marked it resolved.")
            }
        } catch {
            reportStorageIssue(
                "An iCloud conflict remains unresolved, and Cove could not create its review copy: \(error.localizedDescription)"
            )
        }
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
