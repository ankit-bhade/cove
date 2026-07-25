import Foundation
#if os(macOS)
    import Darwin
#endif

#if os(macOS)
    /// FSEvents-style directory descriptors catch ordinary POSIX writes from
    /// command-line tools that never participate in NSFileCoordinator.
    /// Sources are rebuilt after any structural event so newly-created nested
    /// folders are watched as well.
    private final class LocalVaultWatcher: @unchecked Sendable {
        private let rootURL: URL
        private let queue = DispatchQueue(
            label: "com.ankitbhade.Cove.LocalVaultWatcher")
        private let changeHandler: @Sendable () -> Void
        private var sources: [DispatchSourceFileSystemObject] = []
        private var isStopped = false

        init(
            rootURL: URL,
            changeHandler: @escaping @Sendable () -> Void
        ) {
            self.rootURL = rootURL
            self.changeHandler = changeHandler
        }

        func start() throws {
            try queue.sync {
                try rebuildSources()
            }
        }

        func stop() {
            queue.sync {
                isStopped = true
                let oldSources = sources
                sources = []
                oldSources.forEach { $0.cancel() }
            }
        }

        private func rebuildSources() throws {
            guard !isStopped else { return }
            let oldSources = sources
            sources = []
            oldSources.forEach { $0.cancel() }

            let directories = try watchedDirectories()
            var newSources: [DispatchSourceFileSystemObject] = []
            for directory in directories {
                let descriptor = open(directory.path, O_EVTONLY)
                guard descriptor >= 0 else {
                    CoveLog.vault.error(
                        "A local vault directory could not be watched.")
                    continue
                }
                let source = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: descriptor,
                    eventMask: [
                        .write, .delete, .rename, .attrib,
                        .extend, .link, .revoke,
                    ],
                    queue: queue)
                source.setCancelHandler {
                    close(descriptor)
                }
                source.setEventHandler { [weak self] in
                    guard let self, !self.isStopped else { return }
                    self.changeHandler()
                    do {
                        try self.rebuildSources()
                    } catch {
                        CoveLog.vault.error(
                            "Local vault watcher refresh failed: \(error.localizedDescription, privacy: .private)")
                    }
                }
                source.resume()
                newSources.append(source)
            }
            sources = newSources
            guard !sources.isEmpty else {
                throw CocoaError(.fileReadNoPermission)
            }
        }

        private func watchedDirectories() throws -> [URL] {
            var result = [rootURL]
            guard
                let enumerator = FileManager.default.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                        .isHiddenKey,
                    ],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else {
                throw CocoaError(.fileReadUnknown)
            }
            for case let item as URL in enumerator {
                do {
                    let values = try item.resourceValues(forKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                        .isHiddenKey,
                    ])
                    if values.isDirectory == true,
                        values.isSymbolicLink != true,
                        values.isHidden != true
                    {
                        result.append(item)
                    }
                } catch {
                    CoveLog.vault.error(
                        "A local vault item could not be inspected for observation: \(error.localizedDescription, privacy: .private)"
                    )
                }
            }
            return result
        }
    }
#endif

/// `NSMetadataQuery` is useful for iCloud provider updates, but it does not
/// observe an ordinary local folder while Cove remains foregrounded. A root
/// file presenter covers coordinated Finder/Files/Obsidian-style changes and
/// reports moves, additions, removals, and writes beneath the vault.
private final class VaultDirectoryPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue
    private let changeHandler: @Sendable ([URL]) -> Void
    private let conflictHandler: @Sendable ([URL]) -> Void

    init(
        url: URL,
        changeHandler: @escaping @Sendable ([URL]) -> Void,
        conflictHandler: @escaping @Sendable ([URL]) -> Void
    ) {
        presentedItemURL = url
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.name = "com.ankitbhade.Cove.VaultFilePresenter"
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        self.changeHandler = changeHandler
        self.conflictHandler = conflictHandler
        super.init()
    }

    func presentedItemDidChange() {
        if let presentedItemURL { changeHandler([presentedItemURL]) }
    }

    func presentedItemDidMove(to newURL: URL) {
        let oldURL = presentedItemURL
        changeHandler([oldURL, newURL].compactMap { $0 })
    }

    func accommodatePresentedItemDeletion(
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        if let presentedItemURL { changeHandler([presentedItemURL]) }
        completionHandler(nil)
    }

    func presentedSubitemDidAppear(at url: URL) {
        changeHandler([url])
    }

    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        changeHandler([oldURL, newURL])
    }

    func presentedSubitemDidChange(at url: URL) {
        changeHandler([url])
    }

    func accommodatePresentedSubitemDeletion(
        at url: URL,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        changeHandler([url])
        completionHandler(nil)
    }

    func presentedSubitem(
        at url: URL,
        didGain version: NSFileVersion
    ) {
        changeHandler([url])
        if version.isConflict { conflictHandler([url]) }
    }

    func presentedSubitem(
        at url: URL,
        didResolveConflict version: NSFileVersion
    ) {
        changeHandler([url])
    }
}

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
    var onConflict: ((Set<URL>) -> Void)?
    var onIssue: ((String) -> Void)?

    private let query = NSMetadataQuery()
    private var presenter: VaultDirectoryPresenter?
    #if os(macOS)
        private var localWatcher: LocalVaultWatcher?
    #endif
    private var notificationObservers: [NSObjectProtocol] = []
    private var pendingChanges: Set<URL> = []
    private var debounceTask: Task<Void, Never>?

    init(vaultURL: URL) {
        self.vaultURL = vaultURL
    }

    func start() {
        let presenter = VaultDirectoryPresenter(
            url: vaultURL,
            changeHandler: { [weak self] urls in
                Task { @MainActor in
                    self?.handleUpdate(urls)
                }
            },
            conflictHandler: { [weak self] urls in
                Task { @MainActor in
                    self?.reportConflicts(urls)
                }
            })
        self.presenter = presenter
        NSFileCoordinator.addFilePresenter(presenter)

        #if os(macOS)
            let localWatcher = LocalVaultWatcher(
                rootURL: vaultURL
            ) { [weak self] in
                Task { @MainActor in
                    self?.handleUpdate([self?.vaultURL].compactMap { $0 })
                }
            }
            do {
                try localWatcher.start()
                self.localWatcher = localWatcher
            } catch {
                onIssue?(
                    "Live local-file observation could not start. Cove will still refresh when it returns to the foreground."
                )
            }
        #endif

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
        notificationObservers.append(
            center.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Reconcile once after gathering. Provider changes that
                    // happened between the initial scan and the query's
                    // baseline must not wait for a second notification.
                    self.handleUpdate([self.vaultURL])
                }
            })
        if !query.start() {
            onIssue?(
                "iCloud change observation could not start. Cove will keep watching coordinated local changes and refresh on foreground."
            )
        }
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        pendingChanges = []
        query.stop()
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
            self.presenter = nil
        }
        #if os(macOS)
            localWatcher?.stop()
            localWatcher = nil
        #endif
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
        reportConflicts(Array(relevant))
        pendingChanges.formUnion(relevant)
        scheduleFire()
    }

    private func reportConflicts(_ urls: [URL]) {
        let relevant = Self.relevantChangeURLs(from: urls, vaultURL: vaultURL)
        let unresolved = relevant.filter { url in
            !(NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).isEmpty
        }
        guard !unresolved.isEmpty else { return }
        onConflict?(unresolved)
    }

    private func scheduleFire() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.debounceDelay)
            } catch {
                return
            }
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
