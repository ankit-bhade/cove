import XCTest
@testable import Cove

@MainActor
final class VaultManagerLatestWinsTests: XCTestCase {
    func testOlderVaultLoadCannotReplaceNewerCompletion() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cove-latest-load-\(UUID().uuidString)",
                                    isDirectory: true)
        let firstURL = root.appendingPathComponent("First", isDirectory: true)
        let secondURL = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstURL,
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondURL,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "cove-latest-load-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bookmarkStore = VaultBookmarkStore(defaults: defaults,
                                               creationOptions: [],
                                               resolutionOptions: [])
        let loader = DelayedVaultLoader()
        let manager = VaultManager(bookmarkStore: bookmarkStore) {
            url, _, _, _ in
            await loader.load(url)
        }

        let firstOpen = Task { await manager.openVault(at: firstURL) }
        await loader.waitUntilStarted(firstURL)
        let secondOpen = Task { await manager.openVault(at: secondURL) }
        await loader.waitUntilStarted(secondURL)

        await loader.finish(secondURL)
        await secondOpen.value
        XCTAssertEqual(manager.vaultURL?.standardizedFileURL,
                       secondURL.standardizedFileURL)
        XCTAssertEqual(manager.rootNode?.name, "Second")

        // The injected loader deliberately ignores cancellation and returns
        // A after B, exercising the generation/URL commit guard itself.
        await loader.finish(firstURL)
        await firstOpen.value
        XCTAssertEqual(manager.vaultURL?.standardizedFileURL,
                       secondURL.standardizedFileURL)
        XCTAssertEqual(manager.rootNode?.name, "Second")
        XCTAssertEqual(manager.state, .open)
    }
}

private actor DelayedVaultLoader {
    private var started: Set<URL> = []
    private var continuations: [URL: CheckedContinuation<(VaultNode, VaultIndex), Never>] = [:]

    func load(_ url: URL) async -> (VaultNode, VaultIndex) {
        started.insert(url.standardizedFileURL)
        return await withCheckedContinuation { continuation in
            continuations[url.standardizedFileURL] = continuation
        }
    }

    func waitUntilStarted(_ url: URL) async {
        while !started.contains(url.standardizedFileURL) { await Task.yield() }
    }

    func finish(_ url: URL) {
        let standardized = url.standardizedFileURL
        continuations.removeValue(forKey: standardized)?.resume(returning: (
            VaultNode(url: url,
                      name: url.lastPathComponent,
                      isDirectory: true,
                      children: []),
            VaultIndex()
        ))
    }
}
