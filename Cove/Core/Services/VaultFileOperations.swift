import Foundation

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

    /// Appends one line to the named note in `folder`, creating the note if
    /// it doesn't exist yet. The read-modify-write runs inside a single
    /// coordinated write so a syncing external copy can't be clobbered
    /// mid-append.
    @discardableResult
    func appendLine(_ line: String, toNoteNamed name: String, in folder: URL) throws -> URL {
        let fileName = try noteFileName(from: name)
        let destination = folder.appendingPathComponent(fileName, isDirectory: false)
        try coordinatedWrite(at: destination, options: .forMerging) { url in
            var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            text += line + "\n"
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return destination
    }

    /// Rewrites the named note through `transform`, creating it if it
    /// doesn't exist yet. Like `appendLine`, the whole read-modify-write
    /// happens inside one coordinated write, which is what makes the Lists
    /// screen's section surgery safe against a syncing external copy.
    /// Returning nil from `transform` leaves the file untouched.
    @discardableResult
    func updateNote(named name: String,
                    in folder: URL,
                    transform: @Sendable (String) -> String?) throws -> URL {
        let fileName = try noteFileName(from: name)
        let destination = folder.appendingPathComponent(fileName, isDirectory: false)
        try coordinatedWrite(at: destination, options: .forMerging) { url in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            guard let updated = transform(text), updated != text else { return }
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
        let isDirectory = isDirectory(url)
        let name = isDirectory ? try validated(newName) : try noteFileName(from: newName)
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: isDirectory)
        guard destination.path != url.path else { return url }

        // A case-only rename collides with itself on case-insensitive
        // filesystems (APFS default), so skip the existence check there.
        let isCaseOnlyRename = name.lowercased() == url.lastPathComponent.lowercased()
        try coordinatedMove(from: url, to: destination,
                            checkDestinationExists: !isCaseOnlyRename)
        return destination
    }

    @discardableResult
    func move(itemAt url: URL, into folder: URL) throws -> URL {
        let isDirectory = isDirectory(url)
        if isDirectory {
            let sourcePath = url.standardizedFileURL.path
            let folderPath = folder.standardizedFileURL.path
            if folderPath == sourcePath || folderPath.hasPrefix(sourcePath + "/") {
                throw OperationError.cannotMoveIntoItself
            }
        }
        let destination = folder.appendingPathComponent(url.lastPathComponent,
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

    // MARK: - Names

    private func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("."),
              !trimmed.contains("/"),
              !trimmed.contains(":") else {
            throw OperationError.invalidName(name)
        }
        return trimmed
    }

    private func noteFileName(from name: String) throws -> String {
        let base = try validated(name)
        return base.lowercased().hasSuffix(".md") ? base : base + ".md"
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
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

    private func coordinatedWrite(at url: URL,
                                  options: NSFileCoordinator.WritingOptions,
                                  _ body: (URL) throws -> Void) throws {
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

    private func coordinatedMove(from source: URL, to destination: URL,
                                 checkDestinationExists: Bool = true) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: destination, options: .forReplacing,
                               error: &coordinationError) { source, destination in
            result = Result {
                if checkDestinationExists,
                   FileManager.default.fileExists(atPath: destination.path) {
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
