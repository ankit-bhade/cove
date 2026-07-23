import Foundation

/// The observable outcome of one coordinated read-modify-write.
struct NoteMutationResult: Equatable, Sendable {
    let changed: Bool
    let resultingText: String
}

struct NoteSaveResult: Equatable, Sendable {
    let conflictCopyURL: URL?
}

struct RecoveryRecord: Equatable, Sendable {
    let originalURL: URL
    let recoveryURL: URL
}

/// Per-item coordinated filesystem operations for the vault: note reads and
/// saves, creation, rename, move, and delete. Every access runs inside
/// `NSFileCoordinator` so external presenters (iCloud, other processes) see
/// consistent state.
struct VaultFileOperations: Sendable {
    enum OperationError: LocalizedError, Equatable {
        case invalidName(String)
        case itemAlreadyExists(String)
        case cannotMoveIntoItself
        case fileMissing(String)

        var errorDescription: String? {
            switch self {
            case .invalidName(let name):
                return "“\(name)” is not a valid name."
            case .itemAlreadyExists(let name):
                return "An item named “\(name)” already exists here."
            case .cannotMoveIntoItself:
                return "A folder can’t be moved into itself."
            case .fileMissing(let name):
                return "“\(name)” no longer exists."
            }
        }
    }

    // MARK: - Notes

    func readNote(at url: URL) throws -> String {
        try coordinatedRead(at: url) { url in
            try String(contentsOf: url, encoding: .utf8)
        }
    }

    /// Saves note text in place. Refuses to write if the file is gone, so a
    /// pending autosave never resurrects a note that was renamed, moved, or
    /// deleted after it was opened.
    func saveNote(_ text: String, to url: URL) throws {
        try coordinatedWrite(at: url, options: .forReplacing) { url in
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw OperationError.fileMissing(url.lastPathComponent)
            }
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Re-reads and transforms an existing note inside one coordinated write.
    /// No parsed range or stale caller-side read can slip between the read and
    /// the atomic replacement.
    func coordinatedUpdateNote(
        at url: URL,
        transform: @Sendable (String) throws -> String?
    ) throws -> NoteMutationResult {
        var mutationResult: NoteMutationResult?
        try coordinatedWrite(at: url, options: .forMerging) { coordinatedURL in
            guard FileManager.default.fileExists(atPath: coordinatedURL.path) else {
                throw OperationError.fileMissing(coordinatedURL.lastPathComponent)
            }
            let current = try String(contentsOf: coordinatedURL, encoding: .utf8)
            guard let updated = try transform(current), updated != current else {
                mutationResult = NoteMutationResult(changed: false, resultingText: current)
                return
            }
            try updated.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            mutationResult = NoteMutationResult(changed: true, resultingText: updated)
        }
        guard let mutationResult else { throw CocoaError(.fileWriteUnknown) }
        return mutationResult
    }

    /// Persists an editor revision while preserving a concurrently changed
    /// disk version in a uniquely named sibling. The note and the prospective
    /// conflict copy are coordinated together, and neither file is silently
    /// overwritten.
    func saveNote(
        _ text: String,
        to url: URL,
        expectedDiskText: String,
        conflictIdentifier: String
    ) throws -> NoteSaveResult {
        let stem = url.deletingPathExtension().lastPathComponent
        let conflictName = "\(stem).cove-conflict-\(conflictIdentifier).md"
        let conflictURL = url.deletingLastPathComponent()
            .appendingPathComponent(conflictName, isDirectory: false)

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<NoteSaveResult, Error>?
        coordinator.coordinate(
            writingItemAt: url, options: .forMerging,
            writingItemAt: conflictURL, options: [],
            error: &coordinationError
        ) { coordinatedURL, coordinatedConflictURL in
            result = Result {
                guard FileManager.default.fileExists(atPath: coordinatedURL.path) else {
                    throw OperationError.fileMissing(coordinatedURL.lastPathComponent)
                }
                let diskText = try String(contentsOf: coordinatedURL, encoding: .utf8)
                var preservedURL: URL?
                if diskText != expectedDiskText, diskText != text {
                    if FileManager.default.fileExists(atPath: coordinatedConflictURL.path) {
                        let preserved = try String(
                            contentsOf: coordinatedConflictURL,
                            encoding: .utf8)
                        guard preserved == diskText else {
                            throw OperationError.itemAlreadyExists(
                                coordinatedConflictURL.lastPathComponent)
                        }
                    } else {
                        try Data(diskText.utf8).write(
                            to: coordinatedConflictURL,
                            options: .withoutOverwriting)
                    }
                    preservedURL = coordinatedConflictURL
                }
                if diskText != text {
                    try text.write(to: coordinatedURL, atomically: true, encoding: .utf8)
                }
                return NoteSaveResult(conflictCopyURL: preservedURL)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return try result.get()
    }

    /// Rewrites the named note through `transform`, creating it if it
    /// doesn't exist yet. The whole read-modify-write happens inside one
    /// coordinated write, which is what makes quick capture and the Lists
    /// screen's section surgery safe against a syncing external copy.
    /// Returning nil from `transform` leaves the file untouched.
    @discardableResult
    func updateNote(
        named name: String,
        in folder: URL,
        transform: @Sendable (String) throws -> String?
    ) throws -> URL {
        let fileName = try noteFileName(from: name)
        let destination = folder.appendingPathComponent(fileName, isDirectory: false)
        try coordinatedWrite(at: destination, options: .forMerging) { url in
            let text: String
            if FileManager.default.fileExists(atPath: url.path) {
                text = try String(contentsOf: url, encoding: .utf8)
            } else {
                text = ""
            }
            guard let updated = try transform(text), updated != text else { return }
            try updated.write(to: url, atomically: true, encoding: .utf8)
        }
        return destination
    }

    @discardableResult
    func createNote(named name: String, in folder: URL) throws -> URL {
        let fileName = try noteFileName(from: name)
        let destination = folder.appendingPathComponent(fileName, isDirectory: false)
        try coordinatedWrite(at: destination, options: []) { url in
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw OperationError.itemAlreadyExists(fileName)
            }
            try "".write(to: url, atomically: true, encoding: .utf8)
        }
        return destination
    }

    @discardableResult
    func createFolder(named name: String, in folder: URL) throws -> URL {
        let folderName = try validated(name)
        let destination = folder.appendingPathComponent(folderName, isDirectory: true)
        try coordinatedWrite(at: destination, options: []) { url in
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw OperationError.itemAlreadyExists(folderName)
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        return destination
    }

    // MARK: - Rename, move, delete

    @discardableResult
    func rename(itemAt url: URL, to newName: String) throws -> URL {
        let isDirectory = try isDirectory(url)
        let name = isDirectory ? try validated(newName) : try noteFileName(from: newName)
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: isDirectory)
        guard destination.path != url.path else { return url }

        // A case-only rename collides with itself on case-insensitive
        // filesystems (APFS default), so skip the existence check there.
        let isCaseOnlyRename = name.lowercased() == url.lastPathComponent.lowercased()
        try coordinatedMove(
            from: url, to: destination,
            checkDestinationExists: !isCaseOnlyRename)
        return destination
    }

    @discardableResult
    func move(itemAt url: URL, into folder: URL) throws -> URL {
        let isDirectory = try isDirectory(url)
        if isDirectory {
            let sourcePath = url.standardizedFileURL.path
            let folderPath = folder.standardizedFileURL.path
            if folderPath == sourcePath || folderPath.hasPrefix(sourcePath + "/") {
                throw OperationError.cannotMoveIntoItself
            }
        }
        let destination = folder.appendingPathComponent(
            url.lastPathComponent,
            isDirectory: isDirectory)
        guard destination.path != url.path else { return url }
        try coordinatedMove(from: url, to: destination)
        return destination
    }

    func delete(itemAt url: URL) throws {
        try coordinatedWrite(at: url, options: .forDeleting) { url in
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Moves a note or folder into the vault's hidden recovery area. The
    /// encoded relative path makes recovery inspectable even after relaunch;
    /// the UUID prevents collisions without ever replacing an older item; the
    /// leading timestamp is what `purgeRecovery` sweeps on.
    func moveToRecovery(
        itemAt url: URL, vaultRoot: URL,
        now: Date = Date()
    ) throws -> RecoveryRecord {
        let recoveryFolder = vaultRoot.appendingPathComponent(
            Self.recoveryFolderName,
            isDirectory: true)
        try coordinatedWrite(at: recoveryFolder, options: []) { folder in
            if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: false)
            }
        }

        let rootPath = vaultRoot.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        let relative =
            itemPath.hasPrefix(rootPath + "/")
            ? String(itemPath.dropFirst(rootPath.count + 1))
            : url.lastPathComponent
        let encodedPath = Data(relative.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        let recoveredName =
            "\(Self.recoveryTimestamp(now))--\(UUID().uuidString.lowercased())--\(encodedPath)--\(url.lastPathComponent)"
        let destination = recoveryFolder.appendingPathComponent(
            recoveredName, isDirectory: try isDirectory(url))
        try coordinatedMove(from: url, to: destination)
        return RecoveryRecord(originalURL: url, recoveryURL: destination)
    }

    /// Removes recovery entries older than `retention`, so deleting a note
    /// eventually frees its space instead of parking it in the vault forever.
    ///
    /// Entries whose name carries no deletion timestamp were written before
    /// this sweep existed, which means a previous run of the app put them
    /// there and no live Undo can still point at them; they are swept too.
    /// One unremovable entry must not abandon the rest of the sweep.
    func purgeRecovery(
        vaultRoot: URL,
        retention: TimeInterval = recoveryRetention,
        now: Date = Date()
    ) throws {
        let folder = vaultRoot.appendingPathComponent(
            Self.recoveryFolderName,
            isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }

        // Names, not URLs: the coordinator may hand back a different location
        // for the folder, and each entry is coordinated again on its own.
        let names = try coordinatedRead(at: folder) { url in
            try FileManager.default.contentsOfDirectory(atPath: url.path)
        }
        let cutoff = now.addingTimeInterval(-retention)
        for name in names {
            let deletedAt = Self.recoveryDeletionDate(fromName: name)
            guard deletedAt.map({ $0 < cutoff }) ?? true else { continue }
            try? delete(itemAt: folder.appendingPathComponent(name))
        }
    }

    // MARK: - Recovery naming

    static let recoveryFolderName = ".cove-recovery"

    /// How long a deleted item stays recoverable. Undo itself is a transient
    /// affordance; this window is for the delete noticed a day later, and it
    /// is what keeps the recovery area from growing without bound.
    static let recoveryRetention: TimeInterval = 7 * 24 * 60 * 60

    /// Recovery entries are named
    /// `<timestamp>--<uuid>--<encoded path>--<name>`. The timestamp records
    /// when the item was deleted, which is what the sweep needs: an item's own
    /// dates travel with it through the move and say nothing about when it
    /// left the vault. Formatted by hand in UTC rather than with a
    /// `DateFormatter`, which is neither `Sendable` nor locale-neutral.
    static func recoveryTimestamp(
        _ date: Date,
        calendar: Calendar = utcCalendar()
    ) -> String {
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02d-%02d%02d%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// The deletion moment encoded in a recovery entry's name, or nil if it
    /// carries none. Only the span before the first `--` is read, and the
    /// timestamp never contains one, so an encoded path is never mistaken
    /// for it.
    static func recoveryDeletionDate(
        fromName name: String,
        calendar: Calendar = utcCalendar()
    ) -> Date? {
        guard let stamp = name.components(separatedBy: "--").first else { return nil }
        let fields = stamp.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 2, fields[0].count == 8, fields[1].count == 6,
            let day = Int(fields[0]), let time = Int(fields[1])
        else { return nil }
        var parts = DateComponents()
        parts.year = day / 10000
        parts.month = (day / 100) % 100
        parts.day = day % 100
        parts.hour = time / 10000
        parts.minute = (time / 100) % 100
        parts.second = time % 100
        return calendar.date(from: parts)
    }

    static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    @discardableResult
    func restore(_ record: RecoveryRecord) throws -> URL {
        try restore(record, to: record.originalURL)
    }

    /// Restores a recovery item under a user-selected replacement name when
    /// its original path has since been occupied. Existing items are never
    /// overwritten.
    @discardableResult
    func restore(_ record: RecoveryRecord, as newName: String) throws -> URL {
        let directory = try isDirectory(record.recoveryURL)
        let component = directory ? try validated(newName) : try noteFileName(from: newName)
        let destination = record.originalURL.deletingLastPathComponent()
            .appendingPathComponent(component, isDirectory: directory)
        return try restore(record, to: destination)
    }

    @discardableResult
    private func restore(_ record: RecoveryRecord, to destination: URL) throws -> URL {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw OperationError.itemAlreadyExists(destination.lastPathComponent)
        }
        try coordinatedMove(from: record.recoveryURL, to: destination)
        return destination
    }

    // MARK: - Names

    private func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            !trimmed.hasPrefix("."),
            !trimmed.contains("/"),
            !trimmed.contains(":")
        else {
            throw OperationError.invalidName(name)
        }
        return trimmed
    }

    private func noteFileName(from name: String) throws -> String {
        let base = try validated(name)
        return base.lowercased().hasSuffix(".md") ? base : base + ".md"
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    }

    // MARK: - Coordination

    private func coordinatedRead<T>(at url: URL, _ body: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try body(url) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    private func coordinatedWrite(
        at url: URL,
        options: NSFileCoordinator.WritingOptions,
        _ body: (URL) throws -> Void
    ) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { url in
            result = Result { try body(url) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }

    private func coordinatedMove(
        from source: URL, to destination: URL,
        checkDestinationExists: Bool = true
    ) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: destination, options: .forReplacing,
            error: &coordinationError
        ) { source, destination in
            result = Result {
                if checkDestinationExists,
                    FileManager.default.fileExists(atPath: destination.path)
                {
                    throw OperationError.itemAlreadyExists(destination.lastPathComponent)
                }
                try FileManager.default.moveItem(at: source, to: destination)
                coordinator.item(at: source, didMoveTo: destination)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        try result.get()
    }
}

/// The process-local serialization boundary for every note mutation. The
/// coordinated operation inside it remains the cross-process boundary used
/// by the app, widget, and file providers.
actor VaultRepository {
    private let fileOperations: VaultFileOperations

    init(fileOperations: VaultFileOperations = VaultFileOperations()) {
        self.fileOperations = fileOperations
    }

    func updateNote(
        at url: URL,
        transform: @Sendable (String) throws -> String?
    ) throws -> NoteMutationResult {
        try fileOperations.coordinatedUpdateNote(at: url, transform: transform)
    }

    func updateNote(
        named name: String,
        in folder: URL,
        transform: @Sendable (String) throws -> String?
    ) throws -> URL {
        try fileOperations.updateNote(named: name, in: folder, transform: transform)
    }
}
