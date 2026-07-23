import Foundation

/// Builds the vault tree from disk: one coordinated read of the vault root,
/// then a recursive listing that keeps folders and case-insensitive `.md`
/// files, ignoring hidden files and symbolic links.
struct VaultTreeScanner: Sendable {
    func scanTree(at rootURL: URL) throws -> VaultNode {
        try Task.checkCancellation()
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var scanResult: Result<VaultNode, Error>?

        coordinator.coordinate(readingItemAt: rootURL, options: [], error: &coordinationError) { url in
            scanResult = Result {
                try Task.checkCancellation()
                return VaultNode(
                    url: rootURL,
                    name: rootURL.lastPathComponent,
                    isDirectory: true,
                    children: try scanDirectory(at: url, representedBy: rootURL)
                )
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        guard let scanResult else {
            throw CocoaError(.fileReadUnknown)
        }
        return try scanResult.get()
    }

    /// Enumerates through the coordinator-provided URL while keeping the URL
    /// namespace the caller supplied in the resulting tree. Coordinators can
    /// canonicalize an accessor URL (notably `/var` to `/private/var`), and
    /// leaking that alternate spelling into the model breaks equality with
    /// change notifications and previously indexed entries.
    private func scanDirectory(at url: URL, representedBy representedURL: URL) throws -> [VaultNode] {
        try Task.checkCancellation()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        var folders: [VaultNode] = []
        var files: [VaultNode] = []

        for item in contents {
            try Task.checkCancellation()
            let name = item.lastPathComponent
            let representedItem = representedURL.appendingPathComponent(name)
            let values = try item.resourceValues(forKeys: keys)

            if name.hasPrefix(".") || values.isHidden == true { continue }
            if values.isSymbolicLink == true { continue }

            if values.isDirectory == true {
                folders.append(
                    VaultNode(
                        url: representedItem,
                        name: name,
                        isDirectory: true,
                        children: try scanDirectory(at: item, representedBy: representedItem)
                    )
                )
            } else if item.pathExtension.lowercased() == "md" {
                files.append(
                    VaultNode(
                        url: representedItem,
                        name: name,
                        isDirectory: false,
                        children: nil
                    )
                )
            }
        }

        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        try Task.checkCancellation()
        return folders + files
    }
}
