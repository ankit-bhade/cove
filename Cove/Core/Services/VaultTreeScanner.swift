import Foundation

/// Builds the vault tree from disk: one coordinated read of the vault root,
/// then a recursive listing that keeps folders and case-insensitive `.md`
/// files, ignoring hidden files and symbolic links.
struct VaultTreeScanner: Sendable {
    func scanTree(at rootURL: URL) throws -> VaultNode {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var scanResult: Result<VaultNode, Error>?

        coordinator.coordinate(readingItemAt: rootURL, options: [], error: &coordinationError) { url in
            scanResult = Result {
                VaultNode(url: url,
                          name: url.lastPathComponent,
                          isDirectory: true,
                          children: try scanDirectory(at: url))
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

    private func scanDirectory(at url: URL) throws -> [VaultNode] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey]
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        var folders: [VaultNode] = []
        var files: [VaultNode] = []

        for item in contents {
            let name = item.lastPathComponent
            let values = try? item.resourceValues(forKeys: keys)

            if name.hasPrefix(".") || values?.isHidden == true { continue }
            if values?.isSymbolicLink == true { continue }

            if values?.isDirectory == true {
                folders.append(VaultNode(url: item,
                                         name: name,
                                         isDirectory: true,
                                         children: try scanDirectory(at: item)))
            } else if item.pathExtension.lowercased() == "md" {
                files.append(VaultNode(url: item,
                                       name: name,
                                       isDirectory: false,
                                       children: nil))
            }
        }

        folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return folders + files
    }
}
