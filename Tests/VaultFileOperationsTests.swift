import XCTest
@testable import Cove

final class VaultFileOperationsTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default
    private let ops = VaultFileOperations()

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("cove-fileops-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func url(_ path: String) -> URL {
        root.appendingPathComponent(path)
    }

    private func exists(_ path: String) -> Bool {
        fileManager.fileExists(atPath: url(path).path)
    }

    // MARK: - Update

    func testUpdateNoteCreatesTheNoteOnFirstUse() throws {
        let destination = try ops.updateNote(named: "Tasks.md", in: root) { text in
            TaskListDocument.addingSection(named: "Groceries", to: text)
        }
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8),
                       "## Groceries\n")
    }

    func testUpdateNoteRewritesExistingContent() throws {
        let file = url("Tasks.md")
        try "## Groceries\n- [ ] Milk\n".write(to: file, atomically: true, encoding: .utf8)
        try ops.updateNote(named: "Tasks", in: root) { text in
            TaskListDocument.insertingLine("- [ ] Eggs", inSection: "Groceries", in: text)
        }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8),
                       "## Groceries\n- [ ] Milk\n- [ ] Eggs\n")
    }

    func testUpdateNoteLeavesTheFileAloneWhenTheTransformReturnsNil() throws {
        let file = url("Tasks.md")
        try "## Groceries\n".write(to: file, atomically: true, encoding: .utf8)
        try ops.updateNote(named: "Tasks", in: root) { _ in nil }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "## Groceries\n")
    }

    func testUpdateNoteAddsAMissingTrailingNewline() throws {
        let file = url("Tasks.md")
        try "# Tasks\n- [ ] Old @due(2026-07-19)".write(to: file, atomically: true,
                                                        encoding: .utf8)
        try ops.updateNote(named: "Tasks", in: root) { text in
            TaskListDocument.insertingUnlistedLine("- [ ] New @due(2026-07-20)", in: text)
        }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), """
            # Tasks
            - [ ] Old @due(2026-07-19)
            - [ ] New @due(2026-07-20)

            """)
    }

    // MARK: - Create

    func testCreateNoteAppendsMarkdownExtension() throws {
        let created = try ops.createNote(named: "Ideas", in: root)
        XCTAssertEqual(created.lastPathComponent, "Ideas.md")
        XCTAssertEqual(try String(contentsOf: created, encoding: .utf8), "")
    }

    func testCreateNoteKeepsExplicitExtensionCaseInsensitively() throws {
        XCTAssertEqual(try ops.createNote(named: "Plan.MD", in: root).lastPathComponent,
                       "Plan.MD")
        XCTAssertEqual(try ops.createNote(named: "Notes.md", in: root).lastPathComponent,
                       "Notes.md")
    }

    func testCreateNoteTrimsWhitespace() throws {
        let created = try ops.createNote(named: "  Ideas ", in: root)
        XCTAssertEqual(created.lastPathComponent, "Ideas.md")
    }

    func testCreateNoteRejectsDuplicate() throws {
        try ops.createNote(named: "Ideas", in: root)
        XCTAssertThrowsError(try ops.createNote(named: "Ideas", in: root)) { error in
            XCTAssertEqual(error as? VaultFileOperations.OperationError,
                           .itemAlreadyExists("Ideas.md"))
        }
    }

    func testCreateNoteRejectsInvalidNames() {
        for name in ["", "   ", ".hidden", "a/b", "a:b"] {
            XCTAssertThrowsError(try ops.createNote(named: name, in: root),
                                 "expected \"\(name)\" to be rejected")
        }
    }

    func testCreateFolder() throws {
        let created = try ops.createFolder(named: "Projects", in: root)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(fileManager.fileExists(atPath: created.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCreateFolderRejectsDuplicate() throws {
        try ops.createFolder(named: "Projects", in: root)
        XCTAssertThrowsError(try ops.createFolder(named: "Projects", in: root))
    }

    // MARK: - Read and save

    func testReadAndSaveNoteRoundTripsUTF8() throws {
        let note = try ops.createNote(named: "Unicode", in: root)
        let contents = "# Héllo 🚀\n- [ ] Do the thing @due(2026-07-20)\n"
        try ops.saveNote(contents, to: note)
        XCTAssertEqual(try ops.readNote(at: note), contents)
    }

    func testSaveNoteToMissingFileThrows() {
        XCTAssertThrowsError(try ops.saveNote("text", to: url("gone.md"))) { error in
            XCTAssertEqual(error as? VaultFileOperations.OperationError,
                           .fileMissing("gone.md"))
        }
    }

    func testReadMissingNoteThrows() {
        XCTAssertThrowsError(try ops.readNote(at: url("gone.md")))
    }

    func testCoordinatedUpdateReportsUnchangedTextWithoutWriting() throws {
        let note = try ops.createNote(named: "Stable", in: root)
        try ops.saveNote("unchanged\n", to: note)
        let before = try modificationDate(of: note)

        let result = try ops.coordinatedUpdateNote(at: note) { $0 }

        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.resultingText, "unchanged\n")
        XCTAssertEqual(try modificationDate(of: note), before)
    }

    func testConcurrentIndependentTaskMutationsAreBothPreserved() async throws {
        let note = try ops.createNote(named: "Concurrent", in: root)
        let initial = "- [ ] Alpha @due(2026-07-20)\n- [ ] Beta @due(2026-07-21)\n"
        try ops.saveNote(initial, to: note)
        let parsed = TaskParser.tasks(in: initial)
        let alpha = identity(for: parsed[0], in: note)
        let beta = identity(for: parsed[1], in: note)
        let repository = VaultRepository()

        async let first = repository.updateNote(at: note) { text in
            TaskParser.settingTaskCompleted(alpha, to: true,
                                            todayDateString: "2026-07-19", in: text)
        }
        async let second = repository.updateNote(at: note) { text in
            TaskParser.settingTaskCompleted(beta, to: true,
                                            todayDateString: "2026-07-19", in: text)
        }
        _ = try await (first, second)

        XCTAssertEqual(try ops.readNote(at: note),
                       "- [x] Alpha @due(2026-07-20)\n- [x] Beta @due(2026-07-21)\n")
    }

    func testConcurrentToggleAndDeletePreserveBothValidChanges() async throws {
        let note = try ops.createNote(named: "Concurrent", in: root)
        let initial = "- [ ] Keep @due(2026-07-20)\n- [ ] Remove @due(2026-07-21)\n"
        try ops.saveNote(initial, to: note)
        let parsed = TaskParser.tasks(in: initial)
        let keep = identity(for: parsed[0], in: note)
        let remove = identity(for: parsed[1], in: note)
        let appRepository = VaultRepository()
        let widgetRepository = VaultRepository()

        async let toggle = appRepository.updateNote(at: note) { text in
            TaskParser.settingTaskCompleted(keep, to: true,
                                            todayDateString: "2026-07-19", in: text)
        }
        async let delete = widgetRepository.updateNote(at: note) { text in
            TaskParser.removingTask(remove, in: text)
        }
        _ = try await (toggle, delete)

        XCTAssertEqual(try ops.readNote(at: note),
                       "- [x] Keep @due(2026-07-20)\n")
    }

    func testRepeatedDesiredCompletionIsIdempotent() async throws {
        let note = try ops.createNote(named: "Retry", in: root)
        let initial = "- [ ] Retry me @due(2026-07-20)\n"
        try ops.saveNote(initial, to: note)
        let identity = identity(
            for: try XCTUnwrap(TaskParser.tasks(in: initial).first), in: note)
        let repository = VaultRepository()

        for _ in 0..<3 {
            _ = try await repository.updateNote(at: note) { text in
                TaskParser.settingTaskCompleted(identity, to: true,
                                                todayDateString: "2026-07-19", in: text)
            }
        }

        XCTAssertEqual(try ops.readNote(at: note),
                       "- [x] Retry me @due(2026-07-20)\n")
    }

    // MARK: - Rename

    func testRenameNoteAddsExtensionAndKeepsContents() throws {
        let note = try ops.createNote(named: "Old", in: root)
        try ops.saveNote("body\n", to: note)
        let renamed = try ops.rename(itemAt: note, to: "New")
        XCTAssertEqual(renamed.lastPathComponent, "New.md")
        XCTAssertFalse(exists("Old.md"))
        XCTAssertEqual(try ops.readNote(at: renamed), "body\n")
    }

    func testRenameFolder() throws {
        let folder = try ops.createFolder(named: "Old", in: root)
        try ops.createNote(named: "Inside", in: folder)
        let renamed = try ops.rename(itemAt: folder, to: "New")
        XCTAssertEqual(renamed.lastPathComponent, "New")
        XCTAssertTrue(exists("New/Inside.md"))
        XCTAssertFalse(exists("Old"))
    }

    func testRenameToExistingNameThrows() throws {
        let note = try ops.createNote(named: "A", in: root)
        try ops.createNote(named: "B", in: root)
        XCTAssertThrowsError(try ops.rename(itemAt: note, to: "B"))
    }

    func testCaseOnlyRenameSucceeds() throws {
        let note = try ops.createNote(named: "note", in: root)
        let renamed = try ops.rename(itemAt: note, to: "Note")
        XCTAssertEqual(renamed.lastPathComponent, "Note.md")
        let names = try fileManager.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(names, ["Note.md"])
    }

    func testRenameToSameNameIsNoOp() throws {
        let note = try ops.createNote(named: "Same", in: root)
        let renamed = try ops.rename(itemAt: note, to: "Same")
        XCTAssertEqual(renamed, note)
        XCTAssertTrue(exists("Same.md"))
    }

    // MARK: - Move

    func testMoveNoteIntoFolder() throws {
        let note = try ops.createNote(named: "Loose", in: root)
        let folder = try ops.createFolder(named: "Projects", in: root)
        let moved = try ops.move(itemAt: note, into: folder)
        XCTAssertEqual(moved, folder.appendingPathComponent("Loose.md", isDirectory: false))
        XCTAssertTrue(exists("Projects/Loose.md"))
        XCTAssertFalse(exists("Loose.md"))
    }

    func testMoveFolderIntoFolder() throws {
        let source = try ops.createFolder(named: "Source", in: root)
        try ops.createNote(named: "Inside", in: source)
        let target = try ops.createFolder(named: "Target", in: root)
        try ops.move(itemAt: source, into: target)
        XCTAssertTrue(exists("Target/Source/Inside.md"))
        XCTAssertFalse(exists("Source"))
    }

    func testMoveFolderIntoItselfThrows() throws {
        let folder = try ops.createFolder(named: "Loop", in: root)
        XCTAssertThrowsError(try ops.move(itemAt: folder, into: folder)) { error in
            XCTAssertEqual(error as? VaultFileOperations.OperationError,
                           .cannotMoveIntoItself)
        }
    }

    func testMoveFolderIntoItsDescendantThrows() throws {
        let outer = try ops.createFolder(named: "Outer", in: root)
        let inner = try ops.createFolder(named: "Inner", in: outer)
        XCTAssertThrowsError(try ops.move(itemAt: outer, into: inner)) { error in
            XCTAssertEqual(error as? VaultFileOperations.OperationError,
                           .cannotMoveIntoItself)
        }
    }

    func testMoveOntoExistingItemThrows() throws {
        let note = try ops.createNote(named: "Dup", in: root)
        let folder = try ops.createFolder(named: "Projects", in: root)
        try ops.createNote(named: "Dup", in: folder)
        XCTAssertThrowsError(try ops.move(itemAt: note, into: folder))
    }

    // MARK: - Delete

    func testDeleteNote() throws {
        let note = try ops.createNote(named: "Doomed", in: root)
        try ops.delete(itemAt: note)
        XCTAssertFalse(exists("Doomed.md"))
    }

    func testDeleteFolderRecursively() throws {
        let folder = try ops.createFolder(named: "Doomed", in: root)
        try ops.createNote(named: "Inside", in: folder)
        try ops.delete(itemAt: folder)
        XCTAssertFalse(exists("Doomed"))
    }

    func testDeleteMovesNoteToRecoveryAndRestoreReturnsIt() throws {
        let note = try ops.createNote(named: "Recoverable", in: root)
        try ops.saveNote("body\n", to: note)

        let record = try ops.moveToRecovery(itemAt: note, vaultRoot: root)
        XCTAssertFalse(fileManager.fileExists(atPath: note.path))
        XCTAssertTrue(fileManager.fileExists(atPath: record.recoveryURL.path))

        try ops.restore(record)
        XCTAssertEqual(try ops.readNote(at: note), "body\n")
        XCTAssertFalse(fileManager.fileExists(atPath: record.recoveryURL.path))
    }

    func testRecoveryRestoreRefusesToOverwriteOccupiedOriginalPath() throws {
        let note = try ops.createNote(named: "Recoverable", in: root)
        let record = try ops.moveToRecovery(itemAt: note, vaultRoot: root)
        try "replacement\n".write(to: note, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ops.restore(record)) { error in
            XCTAssertEqual(error as? VaultFileOperations.OperationError,
                           .itemAlreadyExists("Recoverable.md"))
        }
        XCTAssertEqual(try ops.readNote(at: note), "replacement\n")
        XCTAssertTrue(fileManager.fileExists(atPath: record.recoveryURL.path))
    }

    func testRecoveryCanRestoreUnderAUserSelectedName() throws {
        let note = try ops.createNote(named: "Recoverable", in: root)
        try ops.saveNote("recovered\n", to: note)
        let record = try ops.moveToRecovery(itemAt: note, vaultRoot: root)
        try "occupied\n".write(to: note, atomically: true, encoding: .utf8)

        let restored = try ops.restore(record, as: "Recovered Copy")

        XCTAssertEqual(restored.lastPathComponent, "Recovered Copy.md")
        XCTAssertEqual(try ops.readNote(at: restored), "recovered\n")
        XCTAssertEqual(try ops.readNote(at: note), "occupied\n")
    }

    // MARK: - Recovery sweep

    func testRecoveryTimestampRoundTrips() {
        let moment = Date(timeIntervalSince1970: 1_753_200_061)
        let stamp = VaultFileOperations.recoveryTimestamp(moment)
        let parsed = VaultFileOperations.recoveryDeletionDate(
            fromName: "\(stamp)--abc--def--Note.md")
        XCTAssertEqual(parsed?.timeIntervalSince1970, moment.timeIntervalSince1970)
    }

    func testRecoveryDeletionDateIgnoresAnUntimestampedName() {
        // The pre-sweep format: a bare UUID first, no deletion timestamp.
        XCTAssertNil(VaultFileOperations.recoveryDeletionDate(
            fromName: "b8f1c2d3-4e5f--Rm9v--Note.md"))
    }

    func testMoveToRecoveryStampsTheDeletionMoment() throws {
        let note = try ops.createNote(named: "Doomed", in: root)
        let moment = Date(timeIntervalSince1970: 1_700_000_000)

        let record = try ops.moveToRecovery(itemAt: note, vaultRoot: root, now: moment)

        let stamped = VaultFileOperations.recoveryDeletionDate(
            fromName: record.recoveryURL.lastPathComponent)
        XCTAssertEqual(stamped?.timeIntervalSince1970, moment.timeIntervalSince1970)
    }

    func testPurgeRemovesEntriesPastTheRetentionWindow() throws {
        let note = try ops.createNote(named: "Ancient", in: root)
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = try ops.moveToRecovery(itemAt: note, vaultRoot: root, now: deletedAt)

        try ops.purgeRecovery(vaultRoot: root,
                              retention: VaultFileOperations.recoveryRetention,
                              now: deletedAt.addingTimeInterval(8 * 24 * 60 * 60))

        XCTAssertFalse(fileManager.fileExists(atPath: record.recoveryURL.path))
    }

    func testPurgeKeepsEntriesInsideTheRetentionWindow() throws {
        let note = try ops.createNote(named: "Recent", in: root)
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = try ops.moveToRecovery(itemAt: note, vaultRoot: root, now: deletedAt)

        try ops.purgeRecovery(vaultRoot: root,
                              retention: VaultFileOperations.recoveryRetention,
                              now: deletedAt.addingTimeInterval(6 * 24 * 60 * 60))

        XCTAssertTrue(fileManager.fileExists(atPath: record.recoveryURL.path))
        try ops.restore(record)
        XCTAssertTrue(exists("Recent.md"))
    }

    func testPurgeSweepsEntriesWrittenBeforeTimestampsExisted() throws {
        let folder = root.appendingPathComponent(VaultFileOperations.recoveryFolderName,
                                                 isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = folder.appendingPathComponent(
            "\(UUID().uuidString.lowercased())--Rm9v--Note.md")
        try "orphaned\n".write(to: legacy, atomically: true, encoding: .utf8)

        try ops.purgeRecovery(vaultRoot: root)

        XCTAssertFalse(fileManager.fileExists(atPath: legacy.path))
    }

    func testPurgeRemovesRecoveredFoldersWholesale() throws {
        let folder = try ops.createFolder(named: "Archive", in: root)
        try ops.createNote(named: "Inside", in: folder)
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = try ops.moveToRecovery(itemAt: folder, vaultRoot: root, now: deletedAt)

        try ops.purgeRecovery(vaultRoot: root,
                              now: deletedAt.addingTimeInterval(30 * 24 * 60 * 60))

        XCTAssertFalse(fileManager.fileExists(atPath: record.recoveryURL.path))
    }

    func testPurgeIsANoOpWithoutARecoveryArea() throws {
        XCTAssertNoThrow(try ops.purgeRecovery(vaultRoot: root))
    }

    private func modificationDate(of url: URL) throws -> Date {
        try XCTUnwrap(fileManager.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    }

    private func identity(for task: TaskParser.ParsedTask, in note: URL) -> TaskIdentity {
        TaskIdentity(filePath: note.path,
                     lineNumber: task.lineNumber,
                     text: task.text,
                     dueDateString: task.dueDateString,
                     dueTimeString: task.dueTimeString,
                     recurrenceTag: task.recurrence?.tagText,
                     listName: task.listName)
    }
}
