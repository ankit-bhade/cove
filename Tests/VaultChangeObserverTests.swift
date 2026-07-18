import XCTest
@testable import Cove

final class VaultChangeObserverTests: XCTestCase {
    private let vault = URL(fileURLWithPath: "/Vault", isDirectory: true)

    private func relevant(_ paths: [String]) -> Set<URL> {
        VaultChangeObserver.relevantChangeURLs(
            from: paths.map { URL(fileURLWithPath: $0) },
            vaultURL: vault
        )
    }

    func testKeepsItemsUnderTheVault() {
        let result = relevant(["/Vault/Note.md", "/Vault/Sub/Deep.md"])
        XCTAssertEqual(result, [URL(fileURLWithPath: "/Vault/Note.md"),
                                URL(fileURLWithPath: "/Vault/Sub/Deep.md")])
    }

    func testKeepsTheVaultRootItself() {
        XCTAssertEqual(relevant(["/Vault"]), [URL(fileURLWithPath: "/Vault")])
    }

    func testDropsItemsOutsideTheVault() {
        XCTAssertTrue(relevant(["/Elsewhere/Note.md", "/VaultOther/Note.md"]).isEmpty)
    }

    func testSiblingWithVaultPathPrefixIsNotInsideTheVault() {
        // "/Vault2" starts with "/Vault" as a string but is a sibling folder.
        XCTAssertTrue(relevant(["/Vault2/Note.md"]).isEmpty)
    }

    func testDropsHiddenPathComponents() {
        XCTAssertTrue(relevant(["/Vault/.hidden.md", "/Vault/.trash/Note.md"]).isEmpty)
    }

    func testNormalizesNonStandardPaths() {
        let result = relevant(["/Vault/Sub/../Note.md"])
        XCTAssertEqual(result, [URL(fileURLWithPath: "/Vault/Note.md")])
    }
}
