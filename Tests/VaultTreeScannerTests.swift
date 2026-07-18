import XCTest
@testable import Cove

final class VaultTreeScannerTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("cove-scanner-tests-\(UUID().uuidString)", isDirectory: true)

        // root/
        //   Projects/
        //     Plan.md
        //     Inner/
        //       Deep.MD
        //   Archive/            (empty folder)
        //   .hidden-folder/note.md
        //   .hidden.md
        //   Zebra.md
        //   apple.md
        //   notes.txt
        //   link-note.md    -> Zebra.md   (symlink)
        //   link-folder     -> Projects   (symlink)
        try makeDir("Projects")
        try makeDir("Projects/Inner")
        try makeDir("Archive")
        try makeDir(".hidden-folder")
        try makeFile("Projects/Plan.md")
        try makeFile("Projects/Inner/Deep.MD")
        try makeFile(".hidden-folder/note.md")
        try makeFile(".hidden.md")
        try makeFile("Zebra.md")
        try makeFile("apple.md")
        try makeFile("notes.txt")
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("link-note.md"),
            withDestinationURL: root.appendingPathComponent("Zebra.md"))
        try fileManager.createSymbolicLink(
            at: root.appendingPathComponent("link-folder"),
            withDestinationURL: root.appendingPathComponent("Projects"))
    }

    override func tearDownWithError() throws {
        try? fileManager.removeItem(at: root)
    }

    private func makeDir(_ path: String) throws {
        try fileManager.createDirectory(at: root.appendingPathComponent(path),
                                        withIntermediateDirectories: true)
    }

    private func makeFile(_ path: String, contents: String = "# Note\n") throws {
        try contents.write(to: root.appendingPathComponent(path),
                           atomically: true, encoding: .utf8)
    }

    func testRootListsFoldersFirstThenFilesAlphabetically() throws {
        let tree = try VaultTreeScanner().scanTree(at: root)
        XCTAssertTrue(tree.isDirectory)
        XCTAssertEqual(tree.children?.map(\.name),
                       ["Archive", "Projects", "apple.md", "Zebra.md"])
    }

    func testHiddenFilesAndFoldersAreIgnored() throws {
        let tree = try VaultTreeScanner().scanTree(at: root)
        let names = tree.children?.map(\.name) ?? []
        XCTAssertFalse(names.contains(".hidden.md"))
        XCTAssertFalse(names.contains(".hidden-folder"))
    }

    func testSymbolicLinksAreIgnored() throws {
        let tree = try VaultTreeScanner().scanTree(at: root)
        let names = tree.children?.map(\.name) ?? []
        XCTAssertFalse(names.contains("link-note.md"))
        XCTAssertFalse(names.contains("link-folder"))
    }

    func testMarkdownExtensionIsCaseInsensitive() throws {
        let tree = try VaultTreeScanner().scanTree(at: root)
        let projects = try XCTUnwrap(tree.children?.first { $0.name == "Projects" })
        XCTAssertEqual(projects.children?.map(\.name), ["Inner", "Plan.md"])

        let inner = try XCTUnwrap(projects.children?.first { $0.name == "Inner" })
        XCTAssertEqual(inner.children?.map(\.name), ["Deep.MD"])
    }

    func testNonMarkdownFilesAreExcluded() throws {
        let tree = try VaultTreeScanner().scanTree(at: root)
        let names = tree.children?.map(\.name) ?? []
        XCTAssertFalse(names.contains("notes.txt"))
    }

    func testEmptyFolderHasEmptyChildren() throws {
        let tree = try VaultTreeScanner().scanTree(at: root)
        let archive = try XCTUnwrap(tree.children?.first { $0.name == "Archive" })
        XCTAssertTrue(archive.isDirectory)
        XCTAssertEqual(archive.children, [])
    }

    func testFilesHaveNilChildrenAndDisplayNameDropsExtension() throws {
        let tree = try VaultTreeScanner().scanTree(at: root)
        let zebra = try XCTUnwrap(tree.children?.first { $0.name == "Zebra.md" })
        XCTAssertFalse(zebra.isDirectory)
        XCTAssertNil(zebra.children)
        XCTAssertEqual(zebra.displayName, "Zebra")
    }

    func testScanningMissingFolderThrows() {
        let missing = root.appendingPathComponent("does-not-exist")
        XCTAssertThrowsError(try VaultTreeScanner().scanTree(at: missing))
    }
}
