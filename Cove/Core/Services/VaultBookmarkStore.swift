import Foundation
import OSLog

private let bookmarkLogger = Logger(subsystem: "com.ankitbhade.Cove", category: "Vault")

/// Persists the vault's security-scoped bookmark in `UserDefaults` and
/// resolves it back into a URL on launch.
struct VaultBookmarkStore {
    enum StoreError: LocalizedError {
        case persistenceFailed

        var errorDescription: String? {
            "Cove could not persist access to this vault."
        }
    }

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

    init(
        defaults: UserDefaults = .standard,
        creationOptions: URL.BookmarkCreationOptions = Self.platformCreationOptions,
        resolutionOptions: URL.BookmarkResolutionOptions = Self.platformResolutionOptions
    ) {
        self.defaults = defaults
        self.creationOptions = creationOptions
        self.resolutionOptions = resolutionOptions
    }

    var hasBookmark: Bool {
        defaults.data(forKey: Self.bookmarkKey) != nil
    }

    /// The stored bookmark itself, for handing to the widget extension
    /// through the shared App Group container.
    var bookmarkData: Data? {
        defaults.data(forKey: Self.bookmarkKey)
    }

    /// The URL must be within an active security scope when this is called.
    func saveBookmark(for url: URL) throws {
        try saveBookmarkData(makeBookmarkData(for: url))
    }

    /// Creates bookmark bytes without mutating the currently stored
    /// selection. Vault switching uses this to fully validate a candidate
    /// before replacing the last known-good bookmark.
    func makeBookmarkData(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: creationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil)
    }

    /// Commits already-created bookmark bytes and verifies the defaults store
    /// accepted the exact value. `UserDefaults.set` has no throwing variant,
    /// so the read-back is what prevents an apparent success from losing the
    /// selected vault at the next launch.
    func saveBookmarkData(_ data: Data) throws {
        defaults.set(data, forKey: Self.bookmarkKey)
        guard defaults.data(forKey: Self.bookmarkKey) == data else {
            throw StoreError.persistenceFailed
        }
    }

    func clearBookmark() {
        defaults.removeObject(forKey: Self.bookmarkKey)
    }

    func resolve() -> Resolution {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else {
            return .noBookmark
        }
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: resolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale)
        } catch {
            bookmarkLogger.error("Bookmark restoration failed: \(error.localizedDescription, privacy: .private)")
            return .stale
        }
        if isStale {
            do {
                try refreshBookmark(for: url)
            } catch {
                bookmarkLogger.error(
                    "Stale bookmark refresh failed: \(error.localizedDescription, privacy: .private)")
                return .stale
            }
        }
        return .resolved(url)
    }

    /// Re-creates a stale bookmark before reporting restoration success. A
    /// stale bookmark that cannot be renewed is not silently accepted for one
    /// session only; the recovery screen asks for a durable re-selection.
    private func refreshBookmark(for url: URL) throws {
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }
        try saveBookmark(for: url)
    }
}
