import XCTest
@testable import Cove

final class VaultBookmarkStoreTests: XCTestCase {
    private static let suiteName = "VaultBookmarkStoreTests"

    private var defaults: UserDefaults!
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)

        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cove-bookmark-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: Self.suiteName)
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeStore() -> VaultBookmarkStore {
        VaultBookmarkStore(defaults: defaults)
    }

    func testResolveWithNoBookmarkReturnsNoBookmark() {
        XCTAssertEqual(makeStore().resolve(), .noBookmark)
        XCTAssertFalse(makeStore().hasBookmark)
    }

    func testResolveWithCorruptDataReturnsStale() {
        defaults.set(Data("not a bookmark".utf8), forKey: VaultBookmarkStore.bookmarkKey)
        XCTAssertEqual(makeStore().resolve(), .stale)
    }

    func testSaveAndResolveRoundTripsURL() throws {
        let store = makeStore()
        try store.saveBookmark(for: tempDirectory)
        XCTAssertTrue(store.hasBookmark)

        guard case .resolved(let url) = store.resolve() else {
            return XCTFail("Expected .resolved, got \(store.resolve())")
        }
        XCTAssertEqual(
            url.resolvingSymlinksInPath().standardizedFileURL.path,
            tempDirectory.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    func testResolveAfterFolderDeletedReturnsStale() throws {
        let store = makeStore()
        try store.saveBookmark(for: tempDirectory)
        try FileManager.default.removeItem(at: tempDirectory)

        XCTAssertEqual(store.resolve(), .stale)
    }

    func testClearBookmarkRemovesData() throws {
        let store = makeStore()
        try store.saveBookmark(for: tempDirectory)
        store.clearBookmark()

        XCTAssertFalse(store.hasBookmark)
        XCTAssertEqual(store.resolve(), .noBookmark)
    }

    func testPreparingCandidateBookmarkDoesNotReplaceLastGoodSelection() throws {
        let store = makeStore()
        try store.saveBookmark(for: tempDirectory)
        let originalData = try XCTUnwrap(store.bookmarkData)
        let candidate = tempDirectory.appendingPathComponent(
            "Candidate",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: candidate,
            withIntermediateDirectories: true)

        _ = try store.makeBookmarkData(for: candidate)

        XCTAssertEqual(store.bookmarkData, originalData)
        guard case .resolved(let resolved) = store.resolve() else {
            return XCTFail("Expected last-good bookmark to remain resolved")
        }
        XCTAssertEqual(
            resolved.standardizedFileURL,
            tempDirectory.standardizedFileURL)
    }
}
