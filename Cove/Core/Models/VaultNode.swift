import Foundation

/// One entry in the vault tree: a folder or a Markdown file.
///
/// `children` is non-nil for folders (possibly empty) and nil for files,
/// which is what `List(_:children:)` expects for disclosure rows.
struct VaultNode: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let children: [VaultNode]?

    var id: String { url.path }

    /// Name shown in the browser: folders keep their name, files drop the
    /// `.md` extension.
    var displayName: String {
        isDirectory ? name : url.deletingPathExtension().lastPathComponent
    }

    /// The subtree flattened into its files, preserving the scanner's
    /// folders-first alphabetical order. Used by search and the index.
    var allFiles: [VaultNode] {
        guard let children else { return [self] }
        return children.flatMap(\.allFiles)
    }
}
