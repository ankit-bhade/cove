import XCTest
@testable import Cove

final class NoteDocumentTests: XCTestCase {
    private var root: URL!
    private var noteURL: URL!
    private var draftStore: EditorRecoveryDraftStore!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("cove-notedocument-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        noteURL = root.appendingPathComponent("Note.md")
        try "original".write(to: noteURL, atomically: true, encoding: .utf8)
        draftStore = EditorRecoveryDraftStore(
            directory: root.appendingPathComponent("Drafts", isDirectory: true))
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    @MainActor private func loadedDocument() async -> NoteDocument {
        let document = NoteDocument(
            fileURL: noteURL,
            draftStore: draftStore)
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
        await document.flush()
        XCTAssertEqual(try modificationDate(), modified)
    }

    @MainActor func testSaveFailureKeepsDocumentDirtyAndRetryable() async {
        struct InjectedFailure: Error {}
        let writer = NoteWriter { _ in throw InjectedFailure() }
        let document = NoteDocument(
            fileURL: noteURL,
            writer: writer,
            draftStore: draftStore)
        await document.load()
        document.text = "unsaved local edit"

        await document.flush()

        XCTAssertTrue(document.isDirty)
        XCTAssertEqual(document.saveStatus, .failed)
        XCTAssertNotNil(document.saveErrorDescription)
        XCTAssertEqual(try? String(contentsOf: noteURL, encoding: .utf8), "original")
    }

    @MainActor func testSuspensionDraftIsRecoveredWithoutOverwritingDisk() async throws {
        let document = await loadedDocument()
        document.text = "unsaved local edit"
        document.prepareForSuspension()

        try "newer external edit".write(
            to: noteURL,
            atomically: true,
            encoding: .utf8)
        let relaunched = NoteDocument(
            fileURL: noteURL,
            draftStore: draftStore)
        await relaunched.load()

        XCTAssertEqual(relaunched.loadState, .loaded)
        XCTAssertEqual(relaunched.text, "unsaved local edit")
        XCTAssertNotNil(relaunched.recoveredDraftDescription)
        XCTAssertEqual(
            try String(contentsOf: noteURL, encoding: .utf8),
            "newer external edit")
    }

    @MainActor func testMissingOriginalStillOpensItsRecoveryDraft() async throws {
        let document = await loadedDocument()
        document.text = "only surviving edit"
        document.prepareForSuspension()
        try fileManager.removeItem(at: noteURL)

        let relaunched = NoteDocument(
            fileURL: noteURL,
            draftStore: draftStore)
        await relaunched.load()

        XCTAssertEqual(relaunched.loadState, .loaded)
        XCTAssertEqual(relaunched.text, "only surviving edit")
        XCTAssertNotNil(relaunched.recoveredDraftDescription)
        XCTAssertTrue(relaunched.protectsAgainstNavigationPruning)
    }

    @MainActor func testMissingOriginalCanBeExportedAsNonOperationalRecoveryCopy() async throws {
        let document = await loadedDocument()
        document.text = "- [ ] recovered task @due(2026-08-01)\n"
        document.prepareForSuspension()
        try fileManager.removeItem(at: noteURL)

        await document.saveRecoveryCopy(in: root)

        let copies = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.contains(".cove-recovered-") }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(
            try String(contentsOf: try XCTUnwrap(copies.first), encoding: .utf8),
            "- [ ] recovered task @due(2026-08-01)\n")
        XCTAssertFalse(document.isDirty)
    }

    /// A draft is the only copy of whatever was unsaved, so bytes that cannot
    /// be decoded are set aside rather than cleared by the load that failed to
    /// read them — and the note itself still opens.
    @MainActor func testUnreadableDraftIsQuarantinedRatherThanDeleted() async throws {
        try fileManager.createDirectory(
            at: draftStore.directory, withIntermediateDirectories: true)
        let draftURL = draftStore.draftURL(for: noteURL)
        try Data("{ not a draft".utf8).write(to: draftURL)

        let document = await loadedDocument()

        XCTAssertEqual(document.loadState, .loaded)
        XCTAssertEqual(document.text, "original")
        XCTAssertFalse(fileManager.fileExists(atPath: draftURL.path))
        let quarantine =
            draftURL
            .deletingPathExtension()
            .appendingPathExtension("unreadable")
        XCTAssertEqual(
            try String(contentsOf: quarantine, encoding: .utf8), "{ not a draft")
        XCTAssertEqual(
            document.saveErrorDescription?.contains(quarantine.lastPathComponent),
            true)
        // A quarantined record is not a draft, so it is not listed or counted.
        XCTAssertTrue(try draftStore.summaries().isEmpty)
    }

    /// One slot per note: a second unreadable record replaces the first rather
    /// than growing a container the user has no view of.
    func testQuarantineKeepsTheNewestUnreadableRecord() throws {
        try fileManager.createDirectory(
            at: draftStore.directory, withIntermediateDirectories: true)
        let draftURL = draftStore.draftURL(for: noteURL)

        try Data("first".utf8).write(to: draftURL)
        let quarantine = try XCTUnwrap(draftStore.quarantineUnreadable(for: noteURL))
        try Data("second".utf8).write(to: draftURL)
        XCTAssertEqual(try draftStore.quarantineUnreadable(for: noteURL), quarantine)

        XCTAssertEqual(try String(contentsOf: quarantine, encoding: .utf8), "second")
        XCTAssertNil(try draftStore.quarantineUnreadable(for: noteURL))
    }

    func testRecoveryDraftEnumerationIsNewestFirstAndCounted() throws {
        let older = EditorRecoveryDraft(
            originalURL: noteURL,
            baseText: "original",
            text: "older edit",
            updatedAt: Date(timeIntervalSince1970: 100))
        let secondURL = root.appendingPathComponent("Second.md")
        let newer = EditorRecoveryDraft(
            originalURL: secondURL,
            baseText: "",
            text: "newer edit",
            updatedAt: Date(timeIntervalSince1970: 200))

        try draftStore.save(older)
        try draftStore.save(newer)
        try Data("ignored".utf8).write(
            to: draftStore.directory.appendingPathComponent("README.txt"))

        // Summaries carry identity and age only — the recovery list renders a
        // filename and a date, and decoding the text of every unsaved note to
        // draw that would hold a copy of each in memory.
        let summaries = try draftStore.summaries()
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries.map(\.originalURL), [secondURL, noteURL])
        XCTAssertEqual(summaries.map(\.updatedAt), [newer.updatedAt, older.updatedAt])
        // The full record is still reachable one draft at a time.
        XCTAssertEqual(try draftStore.load(for: secondURL), newer)
    }

    @MainActor func testPersistCallbackFiresOnceForOneRevision() async {
        let document = await loadedDocument()
        var callbackCount = 0
        document.onPersisted = { _ in callbackCount += 1 }
        document.text = "saved once"

        await document.flush()

        XCTAssertEqual(callbackCount, 1)
    }

    private func modificationDate() throws -> Date {
        try XCTUnwrap(fileManager.attributesOfItem(atPath: noteURL.path)[.modificationDate] as? Date)
    }
}
