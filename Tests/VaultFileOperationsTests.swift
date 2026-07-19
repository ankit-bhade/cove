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

    // MARK: - Append

    func testAppendLineCreatesTheNoteOnFirstUse() throws {
        let destination = try ops.appendLine("- [ ] Get bread @due(2026-07-19 15:00)",
                                             toNoteNamed: "Tasks.md", in: root)
        XCTAssertEqual(destination.lastPathComponent, "Tasks.md")
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8),
                       "- [ ] Get bread @due(2026-07-19 15:00)\n")
    }

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

    func testAppendLineAppendsToExistingContentAddingMissingNewline() throws {
        let file = url("Tasks.md")
        try "# Tasks\n- [ ] Old @due(2026-07-19)".write(to: file, atomically: true,
                                                        encoding: .utf8)
        try ops.appendLine("- [ ] New @due(2026-07-20)", toNoteNamed: "Tasks", in: root)
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
}
