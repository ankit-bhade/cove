import XCTest
@testable import Cove

final class NoteSearcherTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("cove-searcher-tests-\(UUID().uuidString)", isDirectory: true)

        // root/
        //   Projects/
        //     Plan.md        ("Ship the ROADMAP by June")
        //   Groceries.md     ("- [ ] Milk\n- [ ] Eggs")
        //   Journal.md       ("Café visit today")
        try fileManager.createDirectory(at: root.appendingPathComponent("Projects"),
                                        withIntermediateDirectories: true)
        try makeFile("Projects/Plan.md", contents: "# Plan\nShip the ROADMAP by June\n")
        try makeFile("Groceries.md", contents: "- [ ] Milk\n- [ ] Eggs\n")
        try makeFile("Journal.md", contents: "Café visit today\n")
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func makeFile(_ path: String, contents: String) throws {
        try contents.write(to: root.appendingPathComponent(path),
                           atomically: true, encoding: .utf8)
    }

    private func scannedTree() throws -> VaultNode {
        try VaultTreeScanner().scanTree(at: root)
    }

    // MARK: - Pure matching helpers

    func testMatchesIsCaseInsensitive() {
        XCTAssertTrue(NoteSearcher.matches("roadmap", in: "Ship the ROADMAP by June"))
        XCTAssertTrue(NoteSearcher.matches("MILK", in: "- [ ] Milk"))
        XCTAssertFalse(NoteSearcher.matches("bread", in: "- [ ] Milk"))
    }

    func testMatchesIsDiacriticInsensitive() {
        XCTAssertTrue(NoteSearcher.matches("cafe", in: "Café visit today"))
    }

    func testFirstMatchingLineReturnsTrimmedFirstHit() {
        let text = "# Plan\n   Ship the ROADMAP by June\nroadmap again\n"
        XCTAssertEqual(NoteSearcher.firstMatchingLine(for: "roadmap", in: text),
                       "Ship the ROADMAP by June")
    }

    func testFirstMatchingLineReturnsNilWithoutMatch() {
        XCTAssertNil(NoteSearcher.firstMatchingLine(for: "bread", in: "- [ ] Milk\n"))
    }

    // MARK: - Tree flattening

    func testAllFilesFlattensTreeInDisplayOrder() throws {
        let files = try scannedTree().allFiles
        XCTAssertEqual(files.map(\.name), ["Plan.md", "Groceries.md", "Journal.md"])
        XCTAssertTrue(files.allSatisfy { !$0.isDirectory })
    }

    // MARK: - Search

    func testSearchFindsContentMatchWithSnippet() async throws {
        let results = try await NoteSearcher().search(for: "roadmap", in: scannedTree())
        XCTAssertEqual(results.map(\.node.name), ["Plan.md"])
        XCTAssertEqual(results.first?.snippet, "Ship the ROADMAP by June")
    }

    func testSearchFindsTitleMatchWithoutContentSnippet() async throws {
        let results = try await NoteSearcher().search(for: "groceries", in: scannedTree())
        XCTAssertEqual(results.map(\.node.name), ["Groceries.md"])
        XCTAssertNil(results.first?.snippet)
    }

    func testSearchWithBlankQueryReturnsNothing() async throws {
        let results = try await NoteSearcher().search(for: "   ", in: scannedTree())
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchWithNoMatchesReturnsNothing() async throws {
        let results = try await NoteSearcher().search(for: "zzz-nothing", in: scannedTree())
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchMatchesMultipleFilesInTreeOrder() async throws {
        let results = try await NoteSearcher().search(for: "] ", in: scannedTree())
        XCTAssertEqual(results.map(\.node.name), ["Groceries.md"])

        let all = try await NoteSearcher().search(for: "e", in: scannedTree())
        XCTAssertEqual(all.map(\.node.name), ["Plan.md", "Groceries.md", "Journal.md"])
    }
}
