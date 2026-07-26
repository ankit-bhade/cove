import XCTest
@testable import Cove

/// A task identity is persisted state that crosses the App Group to the
/// widget and back, so the path it carries is validated against the vault a
/// write is about to open rather than trusted.
final class TaskIdentityPathTests: XCTestCase {
    private let vault = URL(fileURLWithPath: "/Users/someone/Vault", isDirectory: true)

    private func identity(path: String) -> TaskIdentity {
        TaskIdentity(
            filePath: path,
            lineNumber: 0,
            text: "Buy milk",
            dueDateString: "2026-07-23",
            dueTimeString: nil,
            recurrenceTag: nil,
            listName: nil)
    }

    func testNoteInsideTheVaultResolves() {
        XCTAssertEqual(
            identity(path: "/Users/someone/Vault/Tasks.md").fileURL(within: vault)?.path,
            "/Users/someone/Vault/Tasks.md")
        XCTAssertEqual(
            identity(path: "/Users/someone/Vault/Work/Plan.MD").fileURL(within: vault)?.path,
            "/Users/someone/Vault/Work/Plan.MD")
    }

    func testNoteOutsideTheVaultIsRejected() {
        XCTAssertNil(identity(path: "/Users/someone/Other/Tasks.md").fileURL(within: vault))
        XCTAssertNil(identity(path: "/Users/someone/Tasks.md").fileURL(within: vault))
        XCTAssertNil(
            identity(path: "/Users/someone/Vault/../Secrets.md")
                .fileURL(within: vault))
    }

    /// A sibling folder whose name merely starts with the vault's must not
    /// pass as being inside it.
    func testSiblingPathPrefixIsRejected() {
        XCTAssertNil(identity(path: "/Users/someone/Vault2/Tasks.md").fileURL(within: vault))
    }

    func testTheVaultRootItselfIsRejected() {
        XCTAssertNil(identity(path: "/Users/someone/Vault").fileURL(within: vault))
    }

    /// The scanner's own rules: Markdown files only, nothing hidden.
    func testNonMarkdownAndHiddenPathsAreRejected() {
        XCTAssertNil(identity(path: "/Users/someone/Vault/Tasks.txt").fileURL(within: vault))
        XCTAssertNil(identity(path: "/Users/someone/Vault/Tasks").fileURL(within: vault))
        XCTAssertNil(
            identity(path: "/Users/someone/Vault/.cove-recovery/Tasks.md")
                .fileURL(within: vault))
        XCTAssertNil(identity(path: "/Users/someone/Vault/.hidden.md").fileURL(within: vault))
    }

    func testExistingPackageAndSymlinkPathsAreRejected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "cove-identity-path-\(UUID().uuidString)",
                isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent(
            "Example.app",
            isDirectory: true)
        try FileManager.default.createDirectory(
            at: package,
            withIntermediateDirectories: true)
        let packagedNote = package.appendingPathComponent("Tasks.md")
        try "# Packaged\n".write(
            to: packagedNote,
            atomically: true,
            encoding: .utf8)
        XCTAssertEqual(
            try package.resourceValues(forKeys: [.isPackageKey]).isPackage,
            true)
        XCTAssertNil(
            identity(path: packagedNote.path).fileURL(within: root))

        let realNote = root.appendingPathComponent("Real.md")
        let linkedNote = root.appendingPathComponent("Linked.md")
        try "# Real\n".write(
            to: realNote,
            atomically: true,
            encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: linkedNote,
            withDestinationURL: realNote)
        XCTAssertNil(
            identity(path: linkedNote.path).fileURL(within: root))
    }
}
