import Foundation

/// Watches the open vault for external (iCloud) changes using
/// `NSMetadataQuery` with the accessible-external-documents scope, which
/// covers security-scoped folders the app reached through the system picker.
/// Update notifications are filtered to non-hidden items under the vault,
/// debounced (iCloud delivers bursts), and reported through `onChange`.
/// The initial gathering pass is only a baseline and never reported.
@MainActor
final class VaultChangeObserver {
    static let debounceDelay: Duration = .milliseconds(600)

    let vaultURL: URL
    var onChange: ((Set<URL>) -> Void)?

    private let query = NSMetadataQuery()
    private var notificationObservers: [NSObjectProtocol] = []
    private var pendingChanges: Set<URL> = []
    private var debounceTask: Task<Void, Never>?

    init(vaultURL: URL) {
        self.vaultURL = vaultURL
    }

    func start() {
        query.searchScopes = [NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)

        let center = NotificationCenter.default
        notificationObservers.append(
            center.addObserver(
                forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
            ) { [weak self] notification in
                let urls = Self.changedURLs(from: notification)
                MainActor.assumeIsolated {
                    self?.handleUpdate(urls)
                }
            })
        query.start()
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        pendingChanges = []
        query.stop()
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers = []
    }

    /// Keeps items that live under the vault root with no hidden path
    /// components. Both sides are normalized the same way, so `/private`
    /// aliasing cannot split them.
    nonisolated static func relevantChangeURLs(from urls: [URL], vaultURL: URL) -> Set<URL> {
        let rootURL = vaultURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = rootURL.path
        var relevant: Set<URL> = []
        for url in urls {
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            let path = resolved.path
            guard path == rootPath || path.hasPrefix(rootPath + "/") else { continue }
            let relativeComponents = path.dropFirst(rootPath.count).split(separator: "/")
            guard !relativeComponents.contains(where: { $0.hasPrefix(".") }) else { continue }
            relevant.insert(resolved)
        }
        return relevant
    }

    nonisolated private static func changedURLs(from notification: Notification) -> [URL] {
        let itemKeys = [
            NSMetadataQueryUpdateAddedItemsKey,
            NSMetadataQueryUpdateChangedItemsKey,
            NSMetadataQueryUpdateRemovedItemsKey,
        ]
        return
            itemKeys
            .flatMap { notification.userInfo?[$0] as? [NSMetadataItem] ?? [] }
            .compactMap { $0.value(forAttribute: NSMetadataItemURLKey) as? URL }
    }

    private func handleUpdate(_ urls: [URL]) {
        query.disableUpdates()
        defer { query.enableUpdates() }

        let relevant = Self.relevantChangeURLs(from: urls, vaultURL: vaultURL)
        guard !relevant.isEmpty else { return }
        pendingChanges.formUnion(relevant)
        scheduleFire()
    }

    private func scheduleFire() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceDelay)
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    private func fire() {
        let changes = pendingChanges
        pendingChanges = []
        guard !changes.isEmpty else { return }
        onChange?(changes)
    }
}
