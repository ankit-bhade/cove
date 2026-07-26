import CryptoKit
import Foundation
#if canImport(Darwin)
    import Darwin
#endif

/// Writes a complete replacement beside its destination, synchronizes it,
/// and then atomically swaps it into place. `replaceItemAt` keeps the
/// destination's metadata by default (permissions, Finder tags, and other
/// extended attributes) instead of giving the note the temporary file's
/// metadata. New files use an exclusive create so a non-cooperating writer
/// cannot slip between an existence check and creation.
enum DurableFileWriter {
    static func replace(
        _ data: Data,
        at destination: URL,
        validating: (() throws -> Void)? = nil
    ) throws {
        let fileManager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            VaultFileOperations.writeTemporaryPrefix
                + UUID().uuidString.lowercased(),
            isDirectory: false)
        var temporaryExists = false
        defer {
            if temporaryExists {
                do {
                    try fileManager.removeItem(at: temporary)
                } catch {
                    CoveLog.vault.error(
                        "Temporary write cleanup failed: \(error.localizedDescription, privacy: .private)")
                }
            }
        }

        try data.write(to: temporary, options: .withoutOverwriting)
        temporaryExists = true
        try synchronizeFile(at: temporary)

        guard fileManager.fileExists(atPath: destination.path) else {
            throw VaultFileOperations.OperationError.fileMissing(
                destination.lastPathComponent)
        }
        // The temporary file is fully written and synchronized before this
        // final compare. That leaves only the rename syscall-sized window for
        // a writer that ignores NSFileCoordinator.
        try validating?()
        _ = try fileManager.replaceItemAt(
            destination,
            withItemAt: temporary,
            backupItemName: nil,
            options: [])
        temporaryExists = false
        synchronizeDirectoryBestEffort(at: directory)
    }

    static func create(_ data: Data, at destination: URL) throws {
        let fileManager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            VaultFileOperations.createTemporaryPrefix
                + UUID().uuidString.lowercased())
        var temporaryExists = false
        defer {
            if temporaryExists {
                do {
                    try fileManager.removeItem(at: temporary)
                } catch {
                    CoveLog.vault.error(
                        "Temporary create cleanup failed: \(error.localizedDescription, privacy: .private)")
                }
            }
        }

        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            temporaryExists = true
            try synchronizeFile(at: temporary)

            #if canImport(Darwin)
                let renameResult: Int32 = temporary.withUnsafeFileSystemRepresentation {
                    sourcePath in
                    destination.withUnsafeFileSystemRepresentation {
                        destinationPath in
                        guard let sourcePath, let destinationPath else {
                            errno = EINVAL
                            return Int32(-1)
                        }
                        return renamex_np(
                            sourcePath,
                            destinationPath,
                            UInt32(RENAME_EXCL))
                    }
                }
                guard renameResult == 0 else {
                    if errno == EEXIST {
                        throw VaultFileOperations.OperationError.itemAlreadyExists(
                            destination.lastPathComponent)
                    }
                    throw POSIXError(
                        POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                temporaryExists = false
            #else
                try fileManager.moveItem(at: temporary, to: destination)
                temporaryExists = false
            #endif
        } catch {
            if fileManager.fileExists(atPath: destination.path) {
                throw VaultFileOperations.OperationError.itemAlreadyExists(
                    destination.lastPathComponent)
            }
            throw error
        }
        synchronizeDirectoryBestEffort(at: directory)
    }

    private static func synchronizeFile(at url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer {
            do {
                try handle.close()
            } catch {
                CoveLog.vault.error(
                    "Synchronized file close failed: \(error.localizedDescription, privacy: .private)")
            }
        }
        try handle.synchronize()
    }

    private static func synchronizeDirectoryBestEffort(at url: URL) {
        #if os(macOS) || os(iOS)
            let descriptor = open(url.path, O_RDONLY)
            guard descriptor >= 0 else {
                // Some security-scoped File Provider directories cannot be
                // opened as raw descriptors even after the coordinated file
                // replacement succeeded. There is no safe rollback once the
                // new name is visible, so record the weaker durability rather
                // than claiming the content save itself failed.
                CoveLog.vault.warning(
                    "Directory durability sync was unavailable after a completed file write.")
                return
            }
            defer { close(descriptor) }
            if fsync(descriptor) != 0 {
                CoveLog.vault.warning(
                    "Directory durability sync was unavailable after a completed file write.")
            }
        #endif
    }
}

/// The one `NSFileCoordinator` call shape the app and the widget both use.
///
/// Every coordinated access is the same five lines: make a coordinator, hand
/// it an `NSError` out-parameter, capture the accessor's value or its throw,
/// then work out which of the two failed. Written out per call site that shape
/// had drifted into five near-identical copies across two files — and the line
/// easiest to leave out of a sixth (`if let coordinationError { throw }`) is
/// exactly the one that turns a coordination failure into a silent no-op.
enum FileCoordination {
    static func read<T>(at url: URL, _ body: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result { try body(url) }
        }
        return try resolve(result, coordinationError, fallback: .fileReadUnknown)
    }

    static func write<T>(
        at url: URL,
        options: NSFileCoordinator.WritingOptions,
        _ body: (URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) {
            url in
            result = Result { try body(url) }
        }
        return try resolve(result, coordinationError, fallback: .fileWriteUnknown)
    }

    /// Two items coordinated together: a move, or a save beside the conflict
    /// copy it may have to write. The coordinator itself reaches the body so a
    /// move can report `item(at:didMoveTo:)` from inside the coordination,
    /// which is the only reason it is exposed.
    static func write<T>(
        at url: URL,
        options: NSFileCoordinator.WritingOptions,
        and otherURL: URL,
        options otherOptions: NSFileCoordinator.WritingOptions,
        _ body: (NSFileCoordinator, URL, URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<T, Error>?
        coordinator.coordinate(
            writingItemAt: url, options: options,
            writingItemAt: otherURL, options: otherOptions,
            error: &coordinationError
        ) { first, second in
            result = Result { try body(coordinator, first, second) }
        }
        return try resolve(result, coordinationError, fallback: .fileWriteUnknown)
    }

    /// A coordinator that reported no error and never ran its accessor isn't a
    /// documented outcome, but treating it as success would silently claim a
    /// write that never happened.
    private static func resolve<T>(
        _ result: Result<T, Error>?,
        _ coordinationError: NSError?,
        fallback: CocoaError.Code
    ) throws -> T {
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(fallback) }
        return try result.get()
    }
}

/// The observable outcome of one coordinated read-modify-write.
struct NoteMutationResult: Equatable, Sendable {
    let changed: Bool
    let resultingText: String
}

struct NoteSaveResult: Equatable, Sendable {
    let conflictCopyURL: URL?
}

struct RecoveryRecord: Equatable, Sendable {
    let identifier: UUID
    let originalURL: URL
    let recoveryURL: URL
    let deletedAt: Date
}

private struct RecoveryManifest: Codable, Sendable {
    static let currentSchemaVersion = 1
    static let ownerIdentifier = "com.ankitbhade.Cove.recovery"

    var schemaVersion = currentSchemaVersion
    var ownerIdentifier = Self.ownerIdentifier
    var entries: [RecoveryManifestEntry] = []

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case ownerIdentifier
        case entries
    }

    private struct AnyCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let allKeys = try decoder.container(
            keyedBy: AnyCodingKey.self
        ).allKeys.map(\.stringValue)
        let keySet = Set(allKeys)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchema = try container.decodeIfPresent(
            Int.self, forKey: .schemaVersion)
        let decodedOwner = try container.decodeIfPresent(
            String.self, forKey: .ownerIdentifier)

        // Manifests created before ownership metadata was introduced are
        // still Cove manifests: their exact shape was just `entries`.
        if decodedSchema == nil, decodedOwner == nil {
            guard keySet == [CodingKeys.entries.rawValue] else {
                throw DecodingError.dataCorruptedError(
                    forKey: .entries,
                    in: container,
                    debugDescription:
                        "The legacy recovery manifest does not have Cove's expected shape.")
            }
            schemaVersion = Self.currentSchemaVersion
            ownerIdentifier = Self.ownerIdentifier
        } else {
            guard
                keySet
                    == [
                        CodingKeys.schemaVersion.rawValue,
                        CodingKeys.ownerIdentifier.rawValue,
                        CodingKeys.entries.rawValue,
                    ],
                decodedSchema == Self.currentSchemaVersion,
                decodedOwner == Self.ownerIdentifier
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: container,
                    debugDescription:
                        "The recovery manifest is not owned by this Cove version.")
            }
            schemaVersion = decodedSchema ?? Self.currentSchemaVersion
            ownerIdentifier = decodedOwner ?? Self.ownerIdentifier
        }
        entries =
            try container.decodeIfPresent(
                [RecoveryManifestEntry].self, forKey: .entries) ?? []
    }
}

private struct RecoveryManifestEntry: Codable, Equatable, Sendable {
    let identifier: UUID
    let originalRelativePath: String
    let recoveryName: String
    let deletedAt: Date
    let isDirectory: Bool
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
        case fileChangedDuringWrite(String)

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
            case .fileChangedDuringWrite(let name):
                return "“\(name)” changed again while Cove was saving it. Your edit was not reported as saved."
            }
        }
    }

    // MARK: - Notes

    func readNote(at url: URL) throws -> String {
        try FileCoordination.read(at: url) { url in
            try String(contentsOf: url, encoding: .utf8)
        }
    }

    /// Saves note text in place. Refuses to write if the file is gone, so a
    /// pending autosave never resurrects a note that was renamed, moved, or
    /// deleted after it was opened.
    func saveNote(_ text: String, to url: URL) throws {
        try FileCoordination.write(at: url, options: .forReplacing) { url in
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw OperationError.fileMissing(url.lastPathComponent)
            }
            try DurableFileWriter.replace(Data(text.utf8), at: url)
            guard try String(contentsOf: url, encoding: .utf8) == text else {
                throw OperationError.fileChangedDuringWrite(url.lastPathComponent)
            }
        }
    }

    /// Re-reads and transforms an existing note inside one coordinated write.
    /// No parsed range or stale caller-side read can slip between the read and
    /// the atomic replacement.
    func coordinatedUpdateNote(
        at url: URL,
        transform: @Sendable (String) throws -> String?
    ) throws -> NoteMutationResult {
        try FileCoordination.write(at: url, options: .forMerging) { coordinatedURL in
            guard FileManager.default.fileExists(atPath: coordinatedURL.path) else {
                throw OperationError.fileMissing(coordinatedURL.lastPathComponent)
            }
            var current = try String(contentsOf: coordinatedURL, encoding: .utf8)
            for _ in 0..<3 {
                guard let updated = try transform(current), updated != current else {
                    return NoteMutationResult(changed: false, resultingText: current)
                }

                // NSFileCoordinator serializes cooperating presenters. A CLI
                // or editor may ignore it, so validate the exact bytes again
                // immediately before the replacement and retry the pure
                // transform against the newer version.
                let latest = try String(contentsOf: coordinatedURL, encoding: .utf8)
                guard latest == current else {
                    current = latest
                    continue
                }
                try DurableFileWriter.replace(
                    Data(updated.utf8),
                    at: coordinatedURL
                ) {
                    guard
                        try String(
                            contentsOf: coordinatedURL,
                            encoding: .utf8) == current
                    else {
                        throw OperationError.fileChangedDuringWrite(
                            coordinatedURL.lastPathComponent)
                    }
                }
                guard try String(contentsOf: coordinatedURL, encoding: .utf8) == updated else {
                    throw OperationError.fileChangedDuringWrite(
                        coordinatedURL.lastPathComponent)
                }
                return NoteMutationResult(changed: true, resultingText: updated)
            }
            throw OperationError.fileChangedDuringWrite(
                coordinatedURL.lastPathComponent)
        }
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
        let preflightDiskText = try readNote(at: url)
        let diskDigest = Self.contentDigest(Data(preflightDiskText.utf8))
        let conflictName = Self.conflictFileName(
            originalURL: url,
            identifier: "\(conflictIdentifier)-\(diskDigest)")
        let conflictURL = url.deletingLastPathComponent()
            .appendingPathComponent(conflictName, isDirectory: false)

        return try FileCoordination.write(
            at: url, options: .forMerging,
            and: conflictURL, options: []
        ) { _, coordinatedURL, coordinatedConflictURL in
            guard FileManager.default.fileExists(atPath: coordinatedURL.path) else {
                throw OperationError.fileMissing(coordinatedURL.lastPathComponent)
            }
            let diskText = try String(contentsOf: coordinatedURL, encoding: .utf8)
            guard diskText == preflightDiskText else {
                // Re-entering this method calculates a content-addressed name
                // for the newer disk bytes. A second external edit can never
                // collide with the first preserved revision and strand retry.
                throw OperationError.fileChangedDuringWrite(
                    coordinatedURL.lastPathComponent)
            }
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
                    try DurableFileWriter.create(
                        Data(diskText.utf8),
                        at: coordinatedConflictURL)
                }
                preservedURL = coordinatedConflictURL
            }
            if diskText != text {
                // Revalidate the non-coordinating-writer boundary once more
                // after any conflict-copy work and before replacing the note.
                let latest = try String(contentsOf: coordinatedURL, encoding: .utf8)
                guard latest == diskText else {
                    throw OperationError.fileChangedDuringWrite(
                        coordinatedURL.lastPathComponent)
                }
                try DurableFileWriter.replace(
                    Data(text.utf8),
                    at: coordinatedURL
                ) {
                    guard
                        try String(
                            contentsOf: coordinatedURL,
                            encoding: .utf8) == diskText
                    else {
                        throw OperationError.fileChangedDuringWrite(
                            coordinatedURL.lastPathComponent)
                    }
                }
                guard try String(contentsOf: coordinatedURL, encoding: .utf8) == text else {
                    throw OperationError.fileChangedDuringWrite(
                        coordinatedURL.lastPathComponent)
                }
            }
            return NoteSaveResult(conflictCopyURL: preservedURL)
        }
    }

    /// Copies every currently unresolved native file-version conflict into a
    /// user-visible sibling note. The underlying `NSFileVersion`s remain
    /// unresolved; Cove never makes the irreversible resolution choice for
    /// the user. Content-addressed names make repeated observer deliveries
    /// idempotent, and the index recognizes these copies as non-operational
    /// so their task lines cannot schedule duplicate reminders.
    func materializeUnresolvedConflictVersions(
        at url: URL
    ) throws -> [URL] {
        let versions =
            NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        guard !versions.isEmpty else { return [] }

        let currentData = try FileCoordination.read(at: url) {
            try Data(contentsOf: $0)
        }
        var copies: [URL] = []
        for version in versions {
            let versionData = try FileCoordination.read(at: version.url) {
                try Data(contentsOf: $0)
            }
            guard versionData != currentData else { continue }

            let digest = SHA256.hash(data: versionData)
                .prefix(8)
                .map { String(format: "%02x", $0) }
                .joined()
            let name = Self.conflictFileName(
                originalURL: url,
                identifier: "icloud-\(digest)")
            let destination = url.deletingLastPathComponent()
                .appendingPathComponent(name)
            try FileCoordination.write(at: destination, options: []) { coordinatedURL in
                if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                    let existing = try Data(contentsOf: coordinatedURL)
                    guard existing == versionData else {
                        throw OperationError.itemAlreadyExists(
                            coordinatedURL.lastPathComponent)
                    }
                } else {
                    try DurableFileWriter.create(
                        versionData,
                        at: coordinatedURL)
                }
            }
            copies.append(destination)
        }
        return copies
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
        try FileCoordination.write(at: destination, options: .forMerging) { url in
            var exists = FileManager.default.fileExists(atPath: url.path)
            var current =
                exists
                ? try String(contentsOf: url, encoding: .utf8)
                : ""
            for _ in 0..<3 {
                guard
                    let updated = try transform(current),
                    updated != current
                else { return }
                if exists {
                    let latest = try String(contentsOf: url, encoding: .utf8)
                    guard latest == current else {
                        current = latest
                        continue
                    }
                    do {
                        try DurableFileWriter.replace(
                            Data(updated.utf8),
                            at: url
                        ) {
                            guard
                                try String(
                                    contentsOf: url,
                                    encoding: .utf8) == current
                            else {
                                throw OperationError.fileChangedDuringWrite(
                                    url.lastPathComponent)
                            }
                        }
                    } catch OperationError.fileChangedDuringWrite {
                        current = try String(
                            contentsOf: url,
                            encoding: .utf8)
                        continue
                    }
                } else {
                    do {
                        try DurableFileWriter.create(
                            Data(updated.utf8),
                            at: url)
                        exists = true
                    } catch OperationError.itemAlreadyExists {
                        exists = true
                        current = try String(
                            contentsOf: url,
                            encoding: .utf8)
                        continue
                    }
                }
                guard
                    try String(contentsOf: url, encoding: .utf8) == updated
                else {
                    throw OperationError.fileChangedDuringWrite(
                        url.lastPathComponent)
                }
                return
            }
            throw OperationError.fileChangedDuringWrite(url.lastPathComponent)
        }
        return destination
    }

    @discardableResult
    func createNote(named name: String, in folder: URL) throws -> URL {
        let fileName = try noteFileName(from: name)
        let destination = folder.appendingPathComponent(fileName, isDirectory: false)
        try FileCoordination.write(at: destination, options: []) { url in
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw OperationError.itemAlreadyExists(fileName)
            }
            try DurableFileWriter.create(Data(), at: url)
        }
        return destination
    }

    /// Exports editor text that can no longer be saved to its original URL
    /// (for example after an external rename or deletion). The copy is
    /// exclusively created at the vault root and never overwrites another
    /// recovery. Its Cove marker keeps copied task lines non-operational until
    /// the user reviews and renames the note.
    @discardableResult
    func createRecoveryCopy(
        _ text: String,
        for originalURL: URL,
        in folder: URL
    ) throws -> URL {
        let originalStem = originalURL.deletingPathExtension().lastPathComponent
        let timestamp = Self.recoveryTimestamp(Date())
        for attempt in 0..<100 {
            let suffix =
                attempt == 0
                ? ".cove-recovered-\(timestamp).md"
                : ".cove-recovered-\(timestamp)-\(attempt + 1).md"
            let stem = Self.truncatedUTF8(
                originalStem,
                maximumBytes: max(1, 240 - suffix.utf8.count))
            let destination = folder.appendingPathComponent(stem + suffix)
            do {
                try FileCoordination.write(at: destination, options: []) { url in
                    try DurableFileWriter.create(Data(text.utf8), at: url)
                }
                return destination
            } catch OperationError.itemAlreadyExists {
                continue
            }
        }
        throw OperationError.itemAlreadyExists(
            "\(originalStem).cove-recovered-\(timestamp).md")
    }

    @discardableResult
    func createFolder(named name: String, in folder: URL) throws -> URL {
        let folderName = try validated(name)
        let destination = folder.appendingPathComponent(folderName, isDirectory: true)
        try FileCoordination.write(at: destination, options: []) { url in
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
        try FileCoordination.write(at: url, options: .forDeleting) { url in
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Moves a note or folder into the vault's hidden recovery area. Original
    /// relative paths live in an atomic JSON manifest instead of the filename,
    /// so arbitrarily deep/Unicode paths remain recoverable after relaunch
    /// without exceeding a filesystem component limit.
    func moveToRecovery(
        itemAt url: URL, vaultRoot: URL,
        now: Date = Date()
    ) throws -> RecoveryRecord {
        let recoveryFolder = vaultRoot.appendingPathComponent(
            Self.recoveryFolderName,
            isDirectory: true)
        try FileCoordination.write(at: recoveryFolder, options: []) { folder in
            if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: false)
            }
        }

        let rootPath = vaultRoot.standardizedFileURL.path
        let itemPath = url.standardizedFileURL.path
        guard itemPath.hasPrefix(rootPath + "/") else {
            throw OperationError.fileMissing(url.lastPathComponent)
        }
        let relativePath = String(itemPath.dropFirst(rootPath.count + 1))
        let identifier = UUID()
        let directory = try isDirectory(url)
        let recoveredName = Self.recoveryFileName(
            originalName: url.lastPathComponent,
            deletedAt: now,
            identifier: identifier)
        let destination = recoveryFolder.appendingPathComponent(
            recoveredName, isDirectory: directory)
        let manifestEntry = RecoveryManifestEntry(
            identifier: identifier,
            originalRelativePath: relativePath,
            recoveryName: recoveredName,
            deletedAt: now,
            isDirectory: directory)

        // Commit metadata first. If the process dies after the move, the
        // record is already durable; if it dies before, listing ignores the
        // harmless entry whose recovery item does not exist.
        try updateRecoveryManifest(vaultRoot: vaultRoot) { manifest in
            manifest.entries.removeAll { $0.identifier == identifier }
            manifest.entries.append(manifestEntry)
        }
        do {
            try coordinatedMove(from: url, to: destination)
        } catch {
            do {
                try updateRecoveryManifest(vaultRoot: vaultRoot) { manifest in
                    manifest.entries.removeAll { $0.identifier == identifier }
                }
            } catch {
                CoveLog.vault.error(
                    "A failed recovery move left a stale manifest record.")
            }
            throw error
        }
        return RecoveryRecord(
            identifier: identifier,
            originalURL: url,
            recoveryURL: destination,
            deletedAt: now)
    }

    /// Durable records available to a future recovery UI after relaunch.
    /// Stale manifest rows are ignored; they are reconciled by the purge.
    func recoveryRecords(vaultRoot: URL) throws -> [RecoveryRecord] {
        let manifest = try loadRecoveryManifest(vaultRoot: vaultRoot)
        return manifest.entries.compactMap { entry in
            guard
                let originalURL = safeRecoveryOriginalURL(
                    relativePath: entry.originalRelativePath,
                    vaultRoot: vaultRoot),
                let recoveryURL = safeRecoveryItemURL(
                    for: entry,
                    vaultRoot: vaultRoot)
            else { return nil }
            guard FileManager.default.fileExists(atPath: recoveryURL.path) else {
                return nil
            }
            return RecoveryRecord(
                identifier: entry.identifier,
                originalURL: originalURL,
                recoveryURL: recoveryURL,
                deletedAt: entry.deletedAt)
        }
        .sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Removes recovery entries older than `retention`, so deleting a note
    /// eventually frees its space instead of parking it in the vault forever.
    ///
    /// Only entries named in Cove's owned manifest are eligible. Unknown
    /// contents of a pre-existing `.cove-recovery` folder belong to the user
    /// or another tool and must never be inferred to be Cove trash.
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

        // Never delete the only recoverable bytes if their ownership or path
        // metadata is corrupt. Recovery health is surfaced and unknown items
        // stay untouched until the manifest can be repaired.
        let manifest = try loadRecoveryManifest(vaultRoot: vaultRoot)
        let cutoff = now.addingTimeInterval(-retention)
        var firstError: Error?
        var purgedIdentifiers = Set<UUID>()
        for entry in manifest.entries where entry.deletedAt < cutoff {
            guard
                let item = safeRecoveryItemURL(
                    for: entry,
                    vaultRoot: vaultRoot)
            else {
                if firstError == nil {
                    firstError = CocoaError(.fileReadCorruptFile)
                }
                continue
            }
            guard FileManager.default.fileExists(atPath: item.path) else {
                purgedIdentifiers.insert(entry.identifier)
                continue
            }
            do {
                try delete(itemAt: item)
                purgedIdentifiers.insert(entry.identifier)
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        // Drop records whose item was purged, rolled back, or manually
        // removed. Keep recent records even if one older orphan failed.
        do {
            try updateRecoveryManifest(vaultRoot: vaultRoot) { manifest in
                manifest.entries.removeAll { entry in
                    if purgedIdentifiers.contains(entry.identifier) {
                        return true
                    }
                    guard
                        let item = safeRecoveryItemURL(
                            for: entry,
                            vaultRoot: vaultRoot)
                    else { return false }
                    return !FileManager.default.fileExists(atPath: item.path)
                }
            }
        } catch {
            if firstError == nil { firstError = error }
        }
        if let firstError { throw firstError }
    }

    /// Removes write temporaries that a crash or a kill stranded in the vault.
    ///
    /// `DurableFileWriter` stages every replacement beside its destination and
    /// unlinks it on the way out, but a process that dies between the staging
    /// write and the rename leaves the file behind. They are hidden, so the
    /// scanner ignores them and nothing in Cove ever notices — meanwhile an
    /// iCloud vault syncs and stores each one forever. Anything still present
    /// from a previous launch is by definition abandoned, since a live write
    /// cleans up its own temporary; the age floor keeps this sweep clear of a
    /// write in flight on another device.
    ///
    /// Failures are collected rather than thrown: a stranded temporary is
    /// housekeeping, and it must never keep a vault from opening.
    func purgeWriteTemporaries(
        vaultRoot: URL,
        minimumAge: TimeInterval = writeTemporaryMinimumAge,
        now: Date = Date()
    ) {
        let names: [String]
        do {
            names = try FileCoordination.read(at: vaultRoot) { url in
                try FileManager.default.subpathsOfDirectory(atPath: url.path)
            }
        } catch {
            CoveLog.vault.error(
                "Write-temporary sweep could not enumerate the vault: \(error.localizedDescription, privacy: .private)"
            )
            return
        }

        let cutoff = now.addingTimeInterval(-minimumAge)
        for name in names {
            let component = (name as NSString).lastPathComponent
            guard Self.isWriteTemporaryName(component) else { continue }
            let item = vaultRoot.appendingPathComponent(name)
            let modifiedAt = try? item.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            guard modifiedAt.map({ $0 < cutoff }) ?? true else { continue }
            do {
                try FileManager.default.removeItem(at: item)
            } catch {
                CoveLog.vault.error(
                    "Stranded write temporary could not be removed: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    static func isWriteTemporaryName(_ name: String) -> Bool {
        let prefix: String
        if name.hasPrefix(writeTemporaryPrefix) {
            prefix = writeTemporaryPrefix
        } else if name.hasPrefix(createTemporaryPrefix) {
            prefix = createTemporaryPrefix
        } else {
            return false
        }
        let identifier = String(name.dropFirst(prefix.count))
        return identifier.count == 36
            && identifier == identifier.lowercased()
            && UUID(uuidString: identifier) != nil
    }

    // MARK: - Recovery naming

    static let recoveryFolderName = ".cove-recovery"
    static let recoveryManifestName = "manifest.json"
    static let writeTemporaryPrefix = ".cove-write-"
    static let createTemporaryPrefix = ".cove-create-"

    /// A temporary younger than this may belong to a write that is still
    /// running, here or on another device sharing the folder.
    static let writeTemporaryMinimumAge: TimeInterval = 60 * 60

    /// How long a deleted item stays recoverable. Undo itself is a transient
    /// affordance; this window is for the delete noticed a day later, and it
    /// is what keeps the recovery area from growing without bound.
    static let recoveryRetention: TimeInterval = 7 * 24 * 60 * 60

    /// Cove-created conflict notes stay visible in the Notes browser, but
    /// their copied task lines must never become a second source of reminders
    /// or widget tasks while the conflict is being resolved.
    static func isConflictDocument(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".md") && name.contains(".cove-conflict-")
    }

    static func isOperationallyExcludedDocument(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return isConflictDocument(url)
            || (name.hasSuffix(".md") && name.contains(".cove-recovered-"))
    }

    /// Keeps generated names below the 255-byte component ceiling even when
    /// the original note name contains multi-byte Unicode scalars.
    static func conflictFileName(originalURL: URL, identifier: String) -> String {
        let suffix = ".cove-conflict-\(identifier).md"
        let maximumStemBytes = max(1, 240 - suffix.utf8.count)
        let stem = truncatedUTF8(
            originalURL.deletingPathExtension().lastPathComponent,
            maximumBytes: maximumStemBytes)
        return stem + suffix
    }

    private static func contentDigest(_ data: Data) -> String {
        SHA256.hash(data: data)
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func recoveryFileName(
        originalName: String,
        deletedAt: Date,
        identifier: UUID
    ) -> String {
        let prefix =
            "\(recoveryTimestamp(deletedAt))--\(identifier.uuidString.lowercased())--"
        let suffix = truncatedUTF8(
            originalName,
            maximumBytes: max(1, 240 - prefix.utf8.count))
        return prefix + suffix
    }

    /// Recovery entries are named `<timestamp>--<uuid>--<short name>`; the
    /// manifest carries the complete original relative path. The timestamp
    /// also binds the filename to the manifest row and makes recovery storage
    /// inspectable without decoding JSON. Formatted by hand in UTC rather
    /// than with a `DateFormatter`, which is neither `Sendable` nor
    /// locale-neutral.
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

    private func loadRecoveryManifest(
        vaultRoot: URL
    ) throws -> RecoveryManifest {
        let url = recoveryManifestURL(vaultRoot: vaultRoot)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return RecoveryManifest()
        }
        return try FileCoordination.read(at: url) {
            try JSONDecoder().decode(
                RecoveryManifest.self,
                from: Data(contentsOf: $0))
        }
    }

    private func updateRecoveryManifest(
        vaultRoot: URL,
        transform: (inout RecoveryManifest) throws -> Void
    ) throws {
        let recoveryFolder = vaultRoot.appendingPathComponent(
            Self.recoveryFolderName,
            isDirectory: true)
        if !FileManager.default.fileExists(atPath: recoveryFolder.path) {
            try FileCoordination.write(at: recoveryFolder, options: []) { folder in
                if !FileManager.default.fileExists(atPath: folder.path) {
                    try FileManager.default.createDirectory(
                        at: folder,
                        withIntermediateDirectories: false)
                }
            }
        }
        let manifestURL = recoveryManifestURL(vaultRoot: vaultRoot)
        try FileCoordination.write(
            at: manifestURL,
            options: .forMerging
        ) { coordinatedURL in
            var manifest: RecoveryManifest
            if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                manifest = try JSONDecoder().decode(
                    RecoveryManifest.self,
                    from: Data(contentsOf: coordinatedURL))
            } else {
                manifest = RecoveryManifest()
            }
            try transform(&manifest)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(manifest)
            if FileManager.default.fileExists(atPath: coordinatedURL.path) {
                try DurableFileWriter.replace(data, at: coordinatedURL)
            } else {
                try DurableFileWriter.create(data, at: coordinatedURL)
            }
        }
    }

    private func recoveryManifestURL(vaultRoot: URL) -> URL {
        vaultRoot
            .appendingPathComponent(Self.recoveryFolderName, isDirectory: true)
            .appendingPathComponent(Self.recoveryManifestName)
    }

    private func safeRecoveryOriginalURL(
        relativePath: String,
        vaultRoot: URL
    ) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            return nil
        }
        let root = vaultRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate =
            root
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    /// A manifest row is allowed to name only the exact Cove-generated item
    /// carrying that row's UUID. This prevents a damaged or hand-edited
    /// manifest from turning cleanup into path traversal or from claiming an
    /// unrelated file in the recovery folder.
    private func safeRecoveryItemURL(
        for entry: RecoveryManifestEntry,
        vaultRoot: URL
    ) -> URL? {
        let name = entry.recoveryName
        let expectedPrefix =
            "\(Self.recoveryTimestamp(entry.deletedAt))--"
            + "\(entry.identifier.uuidString.lowercased())--"
        guard
            !name.isEmpty,
            name == (name as NSString).lastPathComponent,
            !name.contains("/"),
            name.hasPrefix(expectedPrefix),
            name.utf8.count > expectedPrefix.utf8.count
        else { return nil }

        let folder = vaultRoot.appendingPathComponent(
            Self.recoveryFolderName,
            isDirectory: true)
        let candidate =
            folder
            .appendingPathComponent(name, isDirectory: entry.isDirectory)
            .standardizedFileURL
        guard
            candidate.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
        else { return nil }
        return candidate
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
        let vaultRoot = record.recoveryURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        do {
            try updateRecoveryManifest(vaultRoot: vaultRoot) { manifest in
                manifest.entries.removeAll {
                    $0.identifier == record.identifier
                }
            }
        } catch {
            // Restore already succeeded. A stale row cannot overwrite or
            // resurrect anything and `recoveryRecords` filters its now-missing
            // recovery URL; keep the successful user operation truthful.
            CoveLog.vault.error(
                "A restored item left a stale recovery manifest record.")
        }
        return destination
    }

    // MARK: - Names

    private func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            !trimmed.hasPrefix("."),
            !trimmed.contains("/"),
            !trimmed.contains(":"),
            !trimmed.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            }),
            trimmed.utf8.count <= 240
        else {
            throw OperationError.invalidName(name)
        }
        return trimmed
    }

    private func noteFileName(from name: String) throws -> String {
        let base = try validated(name)
        let result = base.lowercased().hasSuffix(".md") ? base : base + ".md"
        guard result.utf8.count <= 240 else {
            throw OperationError.invalidName(name)
        }
        return result
    }

    private func isDirectory(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    }

    // MARK: - Coordination

    private func coordinatedMove(
        from source: URL, to destination: URL,
        checkDestinationExists: Bool = true
    ) throws {
        try FileCoordination.write(
            at: source, options: .forMoving,
            and: destination, options: .forReplacing
        ) { coordinator, source, destination in
            if checkDestinationExists,
                FileManager.default.fileExists(atPath: destination.path)
            {
                throw OperationError.itemAlreadyExists(destination.lastPathComponent)
            }
            try FileManager.default.moveItem(at: source, to: destination)
            coordinator.item(at: source, didMoveTo: destination)
        }
    }

    private static func truncatedUTF8(
        _ value: String,
        maximumBytes: Int
    ) -> String {
        guard value.utf8.count > maximumBytes else { return value }
        var result = ""
        result.reserveCapacity(min(value.count, maximumBytes))
        for character in value {
            let candidate = result + String(character)
            guard candidate.utf8.count <= maximumBytes else { break }
            result = candidate
        }
        return result.isEmpty ? "item" : result
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

    func readNote(at url: URL) throws -> String {
        try fileOperations.readNote(at: url)
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
