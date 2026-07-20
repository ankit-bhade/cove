import XCTest
@testable import Cove

final class NoteDocumentTests: XCTestCase {
    private var root: URL!
    private var noteURL: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("cove-notedocument-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        noteURL = root.appendingPathComponent("Note.md")
        try "original".write(to: noteURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    @MainActor private func loadedDocument() async -> NoteDocument {
        let document = NoteDocument(fileURL: noteURL)
        await document.load()
        return document
    }

    @MainActor func testLoadReadsFileContents() async {
        let document = await loadedDocument()
        XCTAssertEqual(document.loadState, .loaded)
        XCTAssertEqual(document.text, "original")
    }

    @MainActor func testExternalChangeIsAdoptedWhenThereAreNoLocalEdits() async throws {
        let document = await loadedDocument()
        try "changed externally".write(to: noteURL, atomically: true, encoding: .utf8)
        await document.reloadAfterExternalChange()
        XCTAssertEqual(document.text, "changed externally")
    }

    @MainActor func testLocalEditsWinOverAnExternalChange() async throws {
        let document = await loadedDocument()
        document.text = "local edit"
        try "changed externally".write(to: noteURL, atomically: true, encoding: .utf8)
        await document.reloadAfterExternalChange()
        XCTAssertEqual(document.text, "local edit")
    }

    @MainActor func testReloadIsANoOpWhenDiskIsUnchanged() async {
        let document = await loadedDocument()
        await document.reloadAfterExternalChange()
        XCTAssertEqual(document.text, "original")
    }

    @MainActor func testReloadIsANoOpWhenTheFileIsGone() async throws {
        let document = await loadedDocument()
        try fileManager.removeItem(at: noteURL)
        await document.reloadAfterExternalChange()
        XCTAssertEqual(document.text, "original")
    }

    @MainActor func testAdoptedExternalChangeIsNotResavedToDisk() async throws {
        let document = await loadedDocument()
        try "changed externally".write(to: noteURL, atomically: true, encoding: .utf8)
        let modified = try modificationDate()
        await document.reloadAfterExternalChange()
        await document.saveNow()
        XCTAssertEqual(try modificationDate(), modified)
    }

    @MainActor func testSaveFailureKeepsDocumentDirtyAndRetryable() async {
        struct InjectedFailure: Error {}
        let writer = NoteWriter { _ in throw InjectedFailure() }
        let document = NoteDocument(fileURL: noteURL, writer: writer)
        await document.load()
        document.text = "unsaved local edit"

        await document.saveNow()

        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.saveStatus, .failed)
        XCTAssertNotNil(document.saveErrorDescription)
        XCTAssertEqual(try? String(contentsOf: noteURL, encoding: .utf8), "original")
    }

    private func modificationDate() throws -> Date {
        try XCTUnwrap(fileManager.attributesOfItem(atPath: noteURL.path)[.modificationDate] as? Date)
    }
}
