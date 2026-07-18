import Foundation

/// Persists the vault's security-scoped bookmark in `UserDefaults` and
/// resolves it back into a URL on launch.
struct VaultBookmarkStore {
    enum Resolution: Equatable {
        case noBookmark
        case resolved(URL)
        case stale
    }

    static let bookmarkKey = "vaultBookmark"

    #if os(macOS)
    static let platformCreationOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
    static let platformResolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope]
    #else
    // iOS document-picker URLs produce implicitly security-scoped bookmarks.
    static let platformCreationOptions: URL.BookmarkCreationOptions = []
    static let platformResolutionOptions: URL.BookmarkResolutionOptions = []
    #endif

    private let defaults: UserDefaults
    private let creationOptions: URL.BookmarkCreationOptions
    private let resolutionOptions: URL.BookmarkResolutionOptions

    init(defaults: UserDefaults = .standard,
         creationOptions: URL.BookmarkCreationOptions = Self.platformCreationOptions,
         resolutionOptions: URL.BookmarkResolutionOptions = Self.platformResolutionOptions) {
        self.defaults = defaults
        self.creationOptions = creationOptions
        self.resolutionOptions = resolutionOptions
    }

    var hasBookmark: Bool {
        defaults.data(forKey: Self.bookmarkKey) != nil
    }

    /// The URL must be within an active security scope when this is called.
    func saveBookmark(for url: URL) throws {
        let data = try url.bookmarkData(options: creationOptions,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        defaults.set(data, forKey: Self.bookmarkKey)
    }

    func clearBookmark() {
        defaults.removeObject(forKey: Self.bookmarkKey)
    }

    func resolve() -> Resolution {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else {
            return .noBookmark
        }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: resolutionOptions,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale) else {
            return .stale
        }
        if isStale {
            refreshBookmark(for: url)
        }
        return .resolved(url)
    }

    /// Best-effort re-creation of a bookmark the system reported stale.
    /// Failure is fine: the resolved URL is still usable this session, and a
    /// later failure surfaces the reselect-vault flow.
    private func refreshBookmark(for url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        try? saveBookmark(for: url)
    }
}
