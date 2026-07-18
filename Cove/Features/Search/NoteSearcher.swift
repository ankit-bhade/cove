import Foundation

/// One file that matched a search: the tree node plus a snippet of the first
/// matching content line (nil when only the title matched).
struct SearchResult: Identifiable, Hashable, Sendable {
    let node: VaultNode
    let snippet: String?

    var id: String { node.id }
}

/// On-demand full-text search over the vault's Markdown files. Every search
/// reads each file with a coordinated read; nothing is indexed or persisted.
struct NoteSearcher: Sendable {
    private let fileOperations = VaultFileOperations()

    /// Case-insensitively matches the query against each file's title and
    /// contents, in tree (display) order. Unreadable files are skipped.
    /// Async so callers on the main actor hop off it for the file reads, and
    /// so cancellation (from a superseding search) stops the scan early.
    func search(for query: String, in root: VaultNode) async throws -> [SearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var results: [SearchResult] = []
        for node in Self.allFiles(under: root) {
            try Task.checkCancellation()
            let titleMatches = Self.matches(query, in: node.displayName)
            let snippet = (try? fileOperations.readNote(at: node.url))
                .flatMap { Self.firstMatchingLine(for: query, in: $0) }
            if titleMatches || snippet != nil {
                results.append(SearchResult(node: node, snippet: snippet))
            }
        }
        return results
    }

    /// Flattens the tree into its files, preserving the scanner's
    /// folders-first alphabetical order.
    static func allFiles(under node: VaultNode) -> [VaultNode] {
        guard let children = node.children else { return [node] }
        return children.flatMap { allFiles(under: $0) }
    }

    /// Trimmed first line containing the query, or nil if no line matches.
    static func firstMatchingLine(for query: String, in text: String) -> String? {
        var snippet: String?
        text.enumerateLines { line, stop in
            if matches(query, in: line) {
                snippet = line.trimmingCharacters(in: .whitespaces)
                stop = true
            }
        }
        return snippet
    }

    static func matches(_ query: String, in text: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
