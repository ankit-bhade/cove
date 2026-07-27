import CryptoKit
import Foundation
import Observation
import OSLog

/// A local, crash-recovery copy of a dirty editor. It lives in Cove's own
/// Application Support container, never in the user's vault, so it cannot
/// participate in iCloud conflicts or appear as another Markdown note.
struct EditorRecoveryDraft: Codable, Equatable, Sendable {
    let originalURL: URL
    let baseText: String
    let text: String
    let updatedAt: Date
}

/// A draft's identity and age, without its text.
///
/// Listing and counting drafts needs only these two fields, and a draft's
/// text is a whole note. Decoding the full record to render a filename and a
/// date meant the recovery list held a complete copy of every unsaved note in
/// view state for as long as the screen was open.
struct EditorRecoveryDraftSummary: Codable, Equatable, Sendable, Identifiable {
    let originalURL: URL
    let updatedAt: Date

    var id: URL { originalURL }
}

struct EditorRecoveryDraftStore: Sendable {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let applicationSupport =
                FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first ?? FileManager.default.temporaryDirectory
            self.directory =
                applicationSupport
                .appendingPathComponent("Cove", isDirectory: true)
                .appendingPathComponent("Recovery Drafts", isDirectory: true)
        }
    }

    func load(for originalURL: URL) throws -> EditorRecoveryDraft? {
        let url = draftURL(for: originalURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let draft = try JSONDecoder().decode(
            EditorRecoveryDraft.self,
            from: Data(contentsOf: url))
        guard
            draft.originalURL.standardizedFileURL
                == originalURL.standardizedFileURL
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return draft
    }

    func save(_ draft: EditorRecoveryDraft) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(draft)
        let destination = draftURL(for: draft.originalURL)
        if FileManager.default.fileExists(atPath: destination.path) {
            try DurableFileWriter.replace(data, at: destination)
        } else {
            try DurableFileWriter.create(data, at: destination)
        }
        #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: destination.path)
        #endif
    }

    func remove(for originalURL: URL) throws {
        let url = draftURL(for: originalURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Newest first. Decodes only the identity fields, so listing drafts does
    /// not pull every unsaved note into memory.
    func summaries() throws -> [EditorRecoveryDraftSummary] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        return try urls.map { url in
            try JSONDecoder().decode(
                EditorRecoveryDraftSummary.self,
                from: Data(contentsOf: url))
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func draftURL(for originalURL: URL) -> URL {
        let data = Data(originalURL.standardizedFileURL.absoluteString.utf8)
        let identifier = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent("\(identifier).json")
    }
}

/// Serializes recovery-draft writes for one open document and keeps them in
/// order.
///
/// The journal exists because the draft write is a whole-document encode, an
/// `fsync`, and an atomic replace. Running that on the main actor once per
/// debounce made typing stutter on a large note, so the ordinary path now
/// runs detached. Scene suspension still has to write synchronously — there
/// is no time left to await anything — so both paths share one lock rather
/// than this being an actor, and a monotonic generation makes the later
/// intent win no matter which path observes the lock second.
final class EditorDraftJournal: @unchecked Sendable {
    private let store: EditorRecoveryDraftStore
    private let lock = NSLock()
    private var writtenGeneration: UInt64 = 0

    init(store: EditorRecoveryDraftStore) {
        self.store = store
    }

    func write(_ draft: EditorRecoveryDraft, generation: UInt64) throws {
        try apply(generation: generation) { try store.save(draft) }
    }

    func clear(for originalURL: URL, generation: UInt64) throws {
        try apply(generation: generation) { try store.remove(for: originalURL) }
    }

    private func apply(generation: UInt64, _ body: () throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        // A slower detached write that lost the race to a newer intent must
        // not put the older text back.
        guard generation > writtenGeneration else { return }
        try body()
        writtenGeneration = generation
    }
}

/// Serializes every physical write for one open document. Pending revisions
/// coalesce, while an edit arriving during a write is persisted immediately
/// after the active revision.
actor NoteWriter {
    struct Revision: Sendable {
        let number: UInt64
        let text: String
        let expectedDiskText: String
    }

    struct PersistedRevision: Sendable {
        let number: UInt64
        let text: String
        let conflictCopyURL: URL?
    }

    typealias Persist = @Sendable (Revision) async throws -> PersistedRevision

    private var newestPending: Revision?
    private var isWriting = false
    private var lastPersisted: PersistedRevision?
    private var idleWaiters: [CheckedContinuation<PersistedRevision, Error>] = []
    private let persist: Persist

    init(
        fileURL: URL,
        fileOperations: VaultFileOperations = VaultFileOperations(),
        sessionID: UUID = UUID()
    ) {
        let conflictPrefix = sessionID.uuidString.lowercased()
        persist = { revision in
            try await Task.detached(priority: .userInitiated) {
                let save = try fileOperations.saveNote(
                    revision.text,
                    to: fileURL,
                    expectedDiskText: revision.expectedDiskText,
                    conflictIdentifier: "\(conflictPrefix)-r\(revision.number)")
                return PersistedRevision(
                    number: revision.number,
                    text: revision.text,
                    conflictCopyURL: save.conflictCopyURL)
            }.value
        }
    }

    init(persist: @escaping Persist) {
        self.persist = persist
    }

    func submit(_ revision: Revision) async throws -> PersistedRevision {
        newestPending = revision
        if isWriting {
            return try await withCheckedThrowingContinuation { continuation in
                idleWaiters.append(continuation)
            }
        }

        isWriting = true
        do {
            let persisted = try await drain()
            isWriting = false
            let waiters = idleWaiters
            idleWaiters = []
            waiters.forEach { $0.resume(returning: persisted) }
            return persisted
        } catch {
            isWriting = false
            let waiters = idleWaiters
            idleWaiters = []
            waiters.forEach { $0.resume(throwing: error) }
            throw error
        }
    }

    /// Waits until the latest submitted revision is physically persisted.
    func flush() async throws -> PersistedRevision? {
        if isWriting {
            return try await withCheckedThrowingContinuation { continuation in
                idleWaiters.append(continuation)
            }
        }
        if let pending = newestPending {
            return try await submit(pending)
        }
        return lastPersisted
    }

    /// Internal observation point used by deterministic writer tests. The
    /// editor never branches on this value.
    var pendingRevisionNumber: UInt64? { newestPending?.number }

    private func drain() async throws -> PersistedRevision {
        var newestResult: PersistedRevision?
        while let pending = newestPending {
            newestPending = nil
            // A revision queued while our previous physical write was in
            // flight still carries the editor's older baseline. The writer
            // knows its own last write is now the correct expected disk text.
            let effective = Revision(
                number: pending.number,
                text: pending.text,
                expectedDiskText: lastPersisted?.text ?? pending.expectedDiskText)
            do {
                let persisted = try await persist(effective)
                lastPersisted = persisted
                newestResult = persisted
            } catch {
                // Keep the newest local revision retryable. If another edit
                // arrived during the failed write it is already pending and
                // supersedes the failed physical revision.
                if newestPending == nil { newestPending = pending }
                throw error
            }
        }
        guard let newestResult else { throw CocoaError(.fileWriteUnknown) }
        return newestResult
    }
}

/// State for one open note: coordinated loading, dirty tracking, debounced
/// serialized autosave, and external-change preservation.
@MainActor
@Observable
final class NoteDocument {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum SaveStatus: Equatable {
        case saved
        case pending
        case saving
        case failed
        /// Recovered edits are held back from disk until the banner above is
        /// answered. Without its own case this read as `pending` forever,
        /// which is the one thing it is not: nothing is on its way to disk.
        case awaitingReview
    }

    static let autosaveDelay: Duration = .seconds(1)

    let fileURL: URL
    private(set) var loadState: LoadState = .loading
    private(set) var saveErrorDescription: String?
    private(set) var conflictDescription: String?
    /// The sibling note the banner is talking about — a preserved conflict
    /// copy, or a recovery copy of edits that could not be saved in place.
    /// Naming a file in a banner and then giving the reader no way to open it
    /// is the same fault as printing a line number and opening at the top.
    private(set) var preservedCopyURL: URL?
    private(set) var recoveredDraftDescription: String?
    private(set) var isSaving = false

    var saveStatus: SaveStatus {
        if saveErrorDescription != nil { return .failed }
        if isSaving { return .saving }
        if recoveredDraftDescription != nil { return .awaitingReview }
        return isDirty ? .pending : .saved
    }

    var isDirty: Bool { text != lastSavedText }
    var protectsAgainstNavigationPruning: Bool {
        isDirty || recoveredDraftDescription != nil || isSaving
    }

    var text: String = "" {
        didSet {
            guard loadState == .loaded, text != oldValue else { return }
            revisionNumber &+= 1
            if text == lastSavedText {
                autosaveTask?.cancel()
                autosaveTask = nil
                scheduleDraftPersistence()
            } else {
                scheduleDraftPersistence()
                if recoveredDraftDescription == nil {
                    scheduleAutosave()
                }
            }
        }
    }

    private var lastSavedText = ""
    private var revisionNumber: UInt64 = 0
    private var lastSavedRevision: UInt64?
    private var activeSaveCount = 0
    private var lastErrorWasExternalReload = false
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var draftTask: Task<Void, Never>?
    @ObservationIgnored private let fileOperations: VaultFileOperations
    @ObservationIgnored private let writer: NoteWriter
    @ObservationIgnored private let draftStore: EditorRecoveryDraftStore
    @ObservationIgnored private let draftJournal: EditorDraftJournal
    @ObservationIgnored private var draftGeneration: UInt64 = 0
    @ObservationIgnored var onPersisted: (@MainActor @Sendable (URL) -> Void)?

    init(
        fileURL: URL,
        fileOperations: VaultFileOperations = VaultFileOperations(),
        writer: NoteWriter? = nil,
        draftStore: EditorRecoveryDraftStore = EditorRecoveryDraftStore()
    ) {
        self.fileURL = fileURL
        self.fileOperations = fileOperations
        self.draftStore = draftStore
        self.draftJournal = EditorDraftJournal(store: draftStore)
        self.writer =
            writer
            ?? NoteWriter(
                fileURL: fileURL,
                fileOperations: fileOperations)
    }

    func load() async {
        guard loadState == .loading else { return }
        let operations = fileOperations
        let url = fileURL
        let draft: EditorRecoveryDraft?
        do {
            draft = try draftStore.load(for: fileURL)
        } catch {
            // A damaged recovery record must never make a readable Markdown
            // file unopenable. Surface the recovery failure after loading the
            // actual note.
            draft = nil
            saveErrorDescription =
                "A saved recovery draft could not be read: \(error.localizedDescription)"
        }

        do {
            let contents = try await Task.detached(priority: .userInitiated) {
                try operations.readNote(at: url)
            }.value
            if let draft,
                draft.text != contents,
                draft.text != draft.baseText
            {
                // Keep the base the draft was actually edited from. Accepting
                // it later will therefore create a conflict copy if disk has
                // also changed since the draft was captured.
                lastSavedText = draft.baseText
                text = draft.text
                recoveredDraftDescription =
                    "Recovered unsaved edits from \(draft.updatedAt.formatted(date: .abbreviated, time: .shortened)). Review them before saving."
            } else {
                lastSavedText = contents
                text = contents
                do {
                    try clearDraft()
                } catch {
                    saveErrorDescription =
                        "The note opened, but an obsolete recovery draft could not be removed: \(error.localizedDescription)"
                }
            }
            loadState = .loaded
        } catch {
            CoveLog.document.error("Load failed: \(error.localizedDescription, privacy: .private)")
            if let draft, draft.text != draft.baseText {
                // The original may have been renamed or deleted while Cove
                // was suspended. Keep the editor and explicit export action
                // available instead of stranding the only surviving copy.
                lastSavedText = draft.baseText
                text = draft.text
                recoveredDraftDescription =
                    "The original note is unavailable. Your recovered edits are shown here; save a recovery copy before leaving."
                saveErrorDescription = error.localizedDescription
                lastErrorWasExternalReload = true
                loadState = .loaded
            } else {
                loadState = .failed(error.localizedDescription)
            }
        }
    }

    func reloadAfterExternalChange() async {
        guard loadState == .loaded else { return }
        let operations = fileOperations
        let url = fileURL
        do {
            let contents = try await Task.detached(priority: .userInitiated) {
                try operations.readNote(at: url)
            }.value
            if contents != lastSavedText, !isDirty {
                lastSavedText = contents
                text = contents
            }
            if lastErrorWasExternalReload {
                saveErrorDescription = nil
                lastErrorWasExternalReload = false
            }
        } catch {
            // A missing or temporarily unavailable file is surfaced if the
            // user tries to save; it must not erase the editor's live text.
            CoveLog.document.error("External reload failed: \(error.localizedDescription, privacy: .private)")
            saveErrorDescription =
                "Cove could not reload this note after an external change: \(error.localizedDescription)"
            lastErrorWasExternalReload = true
        }
    }

    /// Explicit lifecycle flush. It first submits the live revision, then
    /// waits for the writer to become idle.
    func flush() async {
        autosaveTask?.cancel()
        autosaveTask = nil
        draftTask?.cancel()
        draftTask = nil
        await persistRecoveryDraft()
        // A recovered draft is deliberately review-first. A scene transition
        // must preserve it locally, not silently overwrite a newer disk file.
        guard recoveredDraftDescription == nil else { return }
        await save()
        do {
            if let persisted = try await writer.flush() {
                adopt(persisted)
            }
        } catch {
            CoveLog.document.error("Flush failed: \(error.localizedDescription, privacy: .private)")
            saveErrorDescription = error.localizedDescription
            lastErrorWasExternalReload = false
        }
    }

    func retrySave() async {
        saveErrorDescription = nil
        lastErrorWasExternalReload = false
        await flush()
    }

    /// Synchronously journals live text before the scene can be suspended or
    /// the navigation stack can release the editor.
    func prepareForSuspension() {
        autosaveTask?.cancel()
        autosaveTask = nil
        draftTask?.cancel()
        draftTask = nil
        persistRecoveryDraftSynchronously()
    }

    func acceptRecoveredDraft() async {
        recoveredDraftDescription = nil
        await flush()
    }

    func discardRecoveredDraft() async {
        let operations = fileOperations
        let url = fileURL
        do {
            let contents = try await Task.detached(priority: .userInitiated) {
                try operations.readNote(at: url)
            }.value
            recoveredDraftDescription = nil
            lastSavedText = contents
            text = contents
            try clearDraft()
            saveErrorDescription = nil
            lastErrorWasExternalReload = false
        } catch {
            saveErrorDescription =
                "The recovered draft is still safe, but the current note could not be loaded: \(error.localizedDescription)"
            lastErrorWasExternalReload = true
        }
    }

    /// Writes the live buffer to an exclusively-created ordinary note at the
    /// vault root when the original URL no longer exists. This is the escape
    /// hatch for external rename/delete races and for a recovered draft whose
    /// parent folder moved while Cove was suspended.
    func saveRecoveryCopy(in vaultRoot: URL) async {
        prepareForSuspension()
        let operations = fileOperations
        let originalURL = fileURL
        let liveText = text
        do {
            let copyURL = try await Task.detached(priority: .userInitiated) {
                try operations.createRecoveryCopy(
                    liveText,
                    for: originalURL,
                    in: vaultRoot)
            }.value
            lastSavedText = liveText
            recoveredDraftDescription = nil
            try clearDraft()
            saveErrorDescription = nil
            lastErrorWasExternalReload = false
            conflictDescription =
                "Saved the recovered edits as \(copyURL.lastPathComponent)."
            preservedCopyURL = copyURL
            onPersisted?(copyURL)
        } catch {
            saveErrorDescription =
                "The recovery draft is still safe, but Cove could not save a copy: \(error.localizedDescription)"
            lastErrorWasExternalReload = false
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.autosaveDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    private func scheduleDraftPersistence() {
        draftTask?.cancel()
        draftTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.persistRecoveryDraft()
        }
    }

    /// The typing path. Encoding a whole document, synchronizing it, and
    /// swapping it into place is far too much to do on the main actor once
    /// per debounce, so the work is handed off and only the outcome comes
    /// back. Suspension uses `persistRecoveryDraftSynchronously` instead.
    private func persistRecoveryDraft() async {
        guard let intent = nextDraftIntent() else { return }
        let journal = draftJournal
        let result = await Task.detached(priority: .utility) { () -> (any Error)? in
            do {
                try Self.apply(intent, to: journal)
                return nil
            } catch {
                return error
            }
        }.value
        if let result { reportDraftFailure(result) }
    }

    private func persistRecoveryDraftSynchronously() {
        guard let intent = nextDraftIntent() else { return }
        do {
            try Self.apply(intent, to: draftJournal)
        } catch {
            reportDraftFailure(error)
        }
    }

    private enum DraftIntent: Sendable {
        case write(EditorRecoveryDraft, generation: UInt64)
        case clear(URL, generation: UInt64)
    }

    /// Takes the generation on the main actor, so the ordering the journal
    /// enforces is the order the edits actually happened in.
    private func nextDraftIntent() -> DraftIntent? {
        guard loadState == .loaded else { return nil }
        draftGeneration += 1
        if isDirty {
            return .write(
                EditorRecoveryDraft(
                    originalURL: fileURL,
                    baseText: lastSavedText,
                    text: text,
                    updatedAt: Date()),
                generation: draftGeneration)
        }
        return .clear(fileURL, generation: draftGeneration)
    }

    private nonisolated static func apply(
        _ intent: DraftIntent,
        to journal: EditorDraftJournal
    ) throws {
        switch intent {
        case .write(let draft, let generation):
            try journal.write(draft, generation: generation)
        case .clear(let url, let generation):
            try journal.clear(for: url, generation: generation)
        }
    }

    /// Retires the draft through the journal rather than the store, so an
    /// older detached write still in flight cannot put it back.
    private func clearDraft() throws {
        draftGeneration += 1
        try draftJournal.clear(for: fileURL, generation: draftGeneration)
    }

    private func reportDraftFailure(_ error: any Error) {
        CoveLog.document.error(
            "Recovery draft write failed: \(error.localizedDescription, privacy: .private)")
        saveErrorDescription =
            "Cove could not preserve a recovery draft: \(error.localizedDescription)"
        lastErrorWasExternalReload = false
    }

    private func save() async {
        guard loadState == .loaded, isDirty else { return }
        let revision = NoteWriter.Revision(
            number: revisionNumber,
            text: text,
            expectedDiskText: lastSavedText)
        activeSaveCount += 1
        isSaving = true
        defer {
            activeSaveCount -= 1
            isSaving = activeSaveCount > 0
        }
        do {
            let persisted = try await writer.submit(revision)
            adopt(persisted)
            saveErrorDescription = nil
            lastErrorWasExternalReload = false
        } catch {
            CoveLog.document.error("Save failed: \(error.localizedDescription, privacy: .private)")
            saveErrorDescription = error.localizedDescription
            lastErrorWasExternalReload = false
        }
    }

    private func adopt(_ persisted: NoteWriter.PersistedRevision) {
        if let lastSavedRevision, persisted.number <= lastSavedRevision {
            return
        }
        lastSavedRevision = persisted.number
        lastSavedText = persisted.text
        if let conflictURL = persisted.conflictCopyURL {
            CoveLog.document.notice("Preserved external edit as \(conflictURL.lastPathComponent, privacy: .private)")
            conflictDescription = "External edits were preserved in \(conflictURL.lastPathComponent)."
            preservedCopyURL = conflictURL
        }
        if text == lastSavedText {
            do {
                try clearDraft()
            } catch {
                saveErrorDescription =
                    "The note was saved, but Cove could not remove its recovery draft: \(error.localizedDescription)"
            }
        }
        onPersisted?(fileURL)
    }
}
