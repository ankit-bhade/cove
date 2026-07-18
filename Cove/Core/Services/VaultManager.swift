import Foundation
import Observation

/// Owns the vault lifecycle: restoring the saved bookmark on launch, opening
/// a newly picked folder, keeping security-scoped access balanced, and
/// holding the scanned tree for the browser.
@MainActor
@Observable
final class VaultManager {
    enum State: Equatable {
        /// Resolving the saved bookmark on launch.
        case restoring
        /// No vault selected yet (first launch, or the user cancelled).
        case needsVault
        /// The saved bookmark is stale/invalid or the folder is unreadable.
        case recoveryNeeded
        /// A vault is open and its tree is loaded.
        case open
    }

    private(set) var state: State = .restoring
    private(set) var rootNode: VaultNode?
    private(set) var vaultURL: URL?
    private(set) var lastErrorDescription: String?

    private let bookmarkStore: VaultBookmarkStore
    private let scanner = VaultTreeScanner()

    /// Set only when `startAccessingSecurityScopedResource()` returned true,
    /// so every stop is matched to a successful start. `@ObservationIgnored`
    /// keeps it a plain stored property so `deinit` can release it.
    @ObservationIgnored private var securityScopedURL: URL?

    init(bookmarkStore: VaultBookmarkStore = VaultBookmarkStore()) {
        self.bookmarkStore = bookmarkStore
    }

    deinit {
        securityScopedURL?.stopAccessingSecurityScopedResource()
    }

    /// Called once at launch to resolve the persisted bookmark.
    func restore() async {
        guard state == .restoring else { return }
        switch bookmarkStore.resolve() {
        case .noBookmark:
            state = .needsVault
        case .stale:
            state = .recoveryNeeded
        case .resolved(let url):
            beginAccess(to: url)
            await loadTree(from: url)
        }
    }

    /// Called with a folder URL freshly returned by the system picker.
    func openVault(at url: URL) async {
        endAccess()
        beginAccess(to: url)
        do {
            try bookmarkStore.saveBookmark(for: url)
        } catch {
            lastErrorDescription = error.localizedDescription
        }
        await loadTree(from: url)
    }

    func refresh() async {
        guard let vaultURL else { return }
        await loadTree(from: vaultURL)
    }

    private func loadTree(from url: URL) async {
        let scanner = self.scanner
        do {
            let node = try await Task.detached(priority: .userInitiated) {
                try scanner.scanTree(at: url)
            }.value
            rootNode = node
            vaultURL = url
            lastErrorDescription = nil
            state = .open
        } catch {
            endAccess()
            rootNode = nil
            vaultURL = nil
            lastErrorDescription = error.localizedDescription
            state = .recoveryNeeded
        }
    }

    private func beginAccess(to url: URL) {
        if url.startAccessingSecurityScopedResource() {
            securityScopedURL = url
        }
    }

    private func endAccess() {
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }
}
