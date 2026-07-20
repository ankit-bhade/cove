import Foundation
import Observation
import OSLog

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

    init(fileURL: URL,
         fileOperations: VaultFileOperations = VaultFileOperations(),
         sessionID: UUID = UUID()) {
        let conflictPrefix = sessionID.uuidString.lowercased()
        persist = { revision in
            try await Task.detached(priority: .userInitiated) {
                let save = try fileOperations.saveNote(
                    revision.text,
                    to: fileURL,
                    expectedDiskText: revision.expectedDiskText,
                    conflictIdentifier: "\(conflictPrefix)-r\(revision.number)")
                return PersistedRevision(number: revision.number,
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
    }

    static let autosaveDelay: Duration = .seconds(1)

    let fileURL: URL
    private(set) var loadState: LoadState = .loading
    private(set) var saveErrorDescription: String?
    private(set) var conflictDescription: String?
    private(set) var isSaving = false

    var saveStatus: SaveStatus {
        if saveErrorDescription != nil { return .failed }
        if isSaving { return .saving }
        return isDirty ? .pending : .saved
    }

    var isDirty: Bool { text != lastSavedText }

    var text: String = "" {
        didSet {
            guard loadState == .loaded, text != oldValue else { return }
            revisionNumber &+= 1
            if text == lastSavedText {
                autosaveTask?.cancel()
                autosaveTask = nil
            } else {
                scheduleAutosave()
            }
        }
    }

    private var lastSavedText = ""
    private var revisionNumber: UInt64 = 0
    private var lastSavedRevision: UInt64 = 0
    private var activeSaveCount = 0
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private let fileOperations: VaultFileOperations
    @ObservationIgnored private let writer: NoteWriter

    init(fileURL: URL,
         fileOperations: VaultFileOperations = VaultFileOperations(),
         writer: NoteWriter? = nil) {
        self.fileURL = fileURL
        self.fileOperations = fileOperations
        self.writer = writer ?? NoteWriter(fileURL: fileURL,
                                           fileOperations: fileOperations)
    }

    func load() async {
        guard loadState == .loading else { return }
        let operations = fileOperations
        let url = fileURL
        do {
            let contents = try await Task.detached(priority: .userInitiated) {
                try operations.readNote(at: url)
            }.value
            lastSavedText = contents
            text = contents
            loadState = .loaded
        } catch {
            CoveLog.document.error("Load failed: \(error.localizedDescription, privacy: .private)")
            loadState = .failed(error.localizedDescription)
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
            guard contents != lastSavedText, !isDirty else { return }
            lastSavedText = contents
            text = contents
        } catch {
            // A missing or temporarily unavailable file is surfaced if the
            // user tries to save; it must not erase the editor's live text.
            CoveLog.document.error("External reload failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Explicit lifecycle flush. It first submits the live revision, then
    /// waits for the writer to become idle.
    func flush() async {
        autosaveTask?.cancel()
        autosaveTask = nil
        await save()
        do {
            if let persisted = try await writer.flush() {
                adopt(persisted)
            }
        } catch {
            CoveLog.document.error("Flush failed: \(error.localizedDescription, privacy: .private)")
            saveErrorDescription = error.localizedDescription
        }
    }

    func saveNow() async {
        await flush()
    }

    func retrySave() async {
        saveErrorDescription = nil
        await flush()
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

    private func save() async {
        guard loadState == .loaded, isDirty else { return }
        let revision = NoteWriter.Revision(number: revisionNumber,
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
        } catch {
            CoveLog.document.error("Save failed: \(error.localizedDescription, privacy: .private)")
            saveErrorDescription = error.localizedDescription
        }
    }

    private func adopt(_ persisted: NoteWriter.PersistedRevision) {
        guard persisted.number >= lastSavedRevision else { return }
        lastSavedRevision = persisted.number
        lastSavedText = persisted.text
        if let conflictURL = persisted.conflictCopyURL {
            CoveLog.document.notice("Preserved external edit as \(conflictURL.lastPathComponent, privacy: .private)")
            conflictDescription = "External edits were preserved in \(conflictURL.lastPathComponent)."
        }
    }
}
