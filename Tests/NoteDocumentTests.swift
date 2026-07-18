import XCTest
@testable import Cove

@MainActor
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

    private func loadedDocument() async -> NoteDocument {
        let document = NoteDocument(fileURL: noteURL)
        await document.load()
        return document
    }

    func testLoadReadsFileContents() async {
        let document = await loadedDocument()
        XCTAssertEqual(document.loadState, .loaded)
        XCTAssertEqual(document.text, "original")
    }

    func testExternalChangeIsAdoptedWhenThereAreNoLocalEdits() async throws {
        let document = await loadedDocument()
        try "changed externally".write(to: noteURL, atomically: true, encoding: .utf8)
        await document.reloadAfterExternalChange()
        XCTAssertEqual(document.text, "changed externally")
    }

    func testLocalEditsWinOverAnExternalChange() async throws {
        let document = await loadedDocument()
        document.text = "local edit"
        try "changed externally".write(to: noteURL, atomically: true, encoding: .utf8)
        await document.reloadAfterExternalChange()
        XCTAssertEqual(document.text, "local edit")
    }

    func testReloadIsANoOpWhenDiskIsUnchanged() async {
        let document = await loadedDocument()
        await document.reloadAfterExternalChange()
        XCTAssertEqual(document.text, "original")
    }

    func testReloadIsANoOpWhenTheFileIsGone() async throws {
        let document = await loadedDocument()
        try fileManager.removeItem(at: noteURL)
        await document.reloadAfterExternalChange()
        XCTAssertEqual(document.text, "original")
    }

    func testAdoptedExternalChangeIsNotResavedToDisk() async throws {
        let document = await loadedDocument()
        try "changed externally".write(to: noteURL, atomically: true, encoding: .utf8)
        let modified = try modificationDate()
        await document.reloadAfterExternalChange()
        await document.saveNow()
        XCTAssertEqual(try modificationDate(), modified)
    }

    private func modificationDate() throws -> Date {
        try XCTUnwrap(fileManager.attributesOfItem(atPath: noteURL.path)[.modificationDate] as? Date)
    }
}
