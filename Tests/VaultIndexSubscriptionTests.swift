import XCTest

@testable import Cove

/// How subscriptions reach the index, and — the half that would fail silently
/// — that the two grammars stay out of each other's way.
final class VaultIndexSubscriptionTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "cove-subscription-index-tests-\(UUID().uuidString)",
                isDirectory: true)
        try fileManager.createDirectory(
            at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func makeFile(_ path: String, contents: String) throws {
        let url = root.appendingPathComponent(path)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func builtIndex() throws -> VaultIndex {
        let tree = try VaultTreeScanner().scanTree(at: root)
        return try VaultIndexBuilder().buildIndex(from: tree)
    }

    private let subscriptionNote = """
        ## Streaming
        - Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)
        - Spotify @cost(11.99 USD) @every(month) @since(2023-08-19) @status(paused)

        ## Empty
        """

    // MARK: - Reaching the index

    func testSubscriptionsAreIndexedFromTheSubscriptionNote() throws {
        try makeFile("Subscriptions.md", contents: subscriptionNote)
        let index = try builtIndex()
        XCTAssertEqual(index.subscriptions.map(\.name), ["Netflix", "Spotify"])
        XCTAssertEqual(index.subscriptions.first?.category, "Streaming")
    }

    func testCategoriesIncludeOnesWithNothingUnderThem() throws {
        try makeFile("Subscriptions.md", contents: subscriptionNote)
        XCTAssertEqual(
            try builtIndex().subscriptionCategoryNames, ["Streaming", "Empty"])
    }

    func testSubscriptionsCarryTheirFileAndLine() throws {
        try makeFile("Subscriptions.md", contents: subscriptionNote)
        let netflix = try builtIndex().subscriptions.first { $0.name == "Netflix" }
        XCTAssertEqual(netflix?.fileURL.lastPathComponent, "Subscriptions.md")
        XCTAssertEqual(netflix?.lineNumber, 1)
        XCTAssertEqual(netflix?.sourceLine?.hasSuffix("\n"), true)
    }

    // MARK: - The crossover guard

    /// A `Subscriptions.md` in a subfolder is an ordinary note, exactly as a
    /// nested `Tasks.md` is.
    func testOnlyTheRootNoteTracksSubscriptions() throws {
        try makeFile("Archive/Subscriptions.md", contents: subscriptionNote)
        XCTAssertTrue(try builtIndex().subscriptions.isEmpty)
    }

    func testSubscriptionLinesInAnOrdinaryNoteAreNotIndexed() throws {
        try makeFile("Journal.md", contents: subscriptionNote)
        XCTAssertTrue(try builtIndex().subscriptions.isEmpty)
    }

    /// The failure that would be invisible: subscription lines are not
    /// checkboxes, so the task parser must produce no warnings about them.
    func testSubscriptionLinesProduceNoTaskDiagnostics() throws {
        try makeFile("Subscriptions.md", contents: subscriptionNote)
        let index = try builtIndex()
        XCTAssertTrue(index.taskDiagnostics.isEmpty)
        XCTAssertTrue(index.allTasks.isEmpty)
    }

    func testTaskLinesProduceNoSubscriptionDiagnostics() throws {
        try makeFile(
            "Tasks.md",
            contents: """
                - [ ] Ship the roadmap @due(2026-08-01)

                ## Groceries
                - [ ] Milk
                """)
        let index = try builtIndex()
        XCTAssertTrue(index.subscriptions.isEmpty)
        XCTAssertTrue(index.subscriptionDiagnostics.isEmpty)
        XCTAssertEqual(index.allTasks.count, 2)
    }

    /// The two notes coexist in one vault without either claiming the other's
    /// headings.
    func testListsAndCategoriesDoNotLeakIntoEachOther() throws {
        try makeFile(
            "Tasks.md",
            contents: """
                ## Groceries
                - [ ] Milk
                """)
        try makeFile("Subscriptions.md", contents: subscriptionNote)
        let index = try builtIndex()
        XCTAssertEqual(index.listNames, ["Groceries"])
        XCTAssertEqual(index.subscriptionCategoryNames, ["Streaming", "Empty"])
        XCTAssertEqual(index.subscriptions.count, 2)
        XCTAssertEqual(index.allTasks.map(\.text), ["Milk"])
    }

    /// A note may hold both, since the subscription note is still an ordinary
    /// note in every other respect.
    func testTheSubscriptionNoteMayAlsoHoldTasks() throws {
        try makeFile(
            "Subscriptions.md",
            contents: """
                - [ ] Review these @due(2027-01-05)
                - Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)
                """)
        let index = try builtIndex()
        XCTAssertEqual(index.subscriptions.map(\.name), ["Netflix"])
        XCTAssertEqual(index.allTasks.map(\.text), ["Review these"])
    }

    // MARK: - Diagnostics

    func testMalformedLinesAreReportedThroughTheIndex() throws {
        try makeFile(
            "Subscriptions.md",
            contents: "- Netflix @cost(abc USD) @every(month) @since(2024-03-04)\n")
        let index = try builtIndex()
        XCTAssertTrue(index.subscriptions.isEmpty)
        XCTAssertEqual(index.subscriptionDiagnostics.count, 1)
        XCTAssertEqual(
            index.subscriptionDiagnostics.first?.fileURL.lastPathComponent,
            "Subscriptions.md")
    }

    // MARK: - Incremental rebuilds

    /// An unchanged note reuses its entry, so its subscriptions and categories
    /// have to survive the reuse path rather than being dropped.
    func testUnchangedNoteReusesItsSubscriptions() throws {
        try makeFile("Subscriptions.md", contents: subscriptionNote)
        let tree = try VaultTreeScanner().scanTree(at: root)
        let builder = VaultIndexBuilder()
        let first = try builder.buildIndex(from: tree)
        let second = try builder.buildCancellableIndex(
            from: tree, previous: first, changedURLs: [])
        XCTAssertEqual(second.subscriptions.map(\.name), ["Netflix", "Spotify"])
        XCTAssertEqual(second.subscriptionCategoryNames, ["Streaming", "Empty"])
    }
}
