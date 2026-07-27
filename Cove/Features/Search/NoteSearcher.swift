import Foundation

/// One file that matched a search: the tree node plus a snippet of the first
/// matching content line (nil when only the title matched).
struct SearchResult: Identifiable, Hashable, Sendable {
    let node: VaultNode
    let snippet: String?
    /// Zero-based line the snippet came from, so opening the result lands on
    /// the match rather than at the top of the note. Nil for a title-only hit,
    /// which has no line to land on.
    let lineNumber: Int?

    init(node: VaultNode, snippet: String?, lineNumber: Int? = nil) {
        self.node = node
        self.snippet = snippet
        self.lineNumber = lineNumber
    }

    var id: String { node.id }

    var destination: NoteDestination {
        NoteDestination(node.url, line: lineNumber)
    }
}

/// Bounded search output plus the diagnostics needed to avoid presenting a
/// partial scan as a definitive "no matches" result.
struct SearchReport: Equatable, Sendable {
    let results: [SearchResult]
    let skippedFileCount: Int
    let isResultLimitReached: Bool

    static let empty = SearchReport(
        results: [], skippedFileCount: 0, isResultLimitReached: false)
}

/// On-demand full-text search over the vault's Markdown files. Every search
/// reads each file with a coordinated read; nothing is indexed or persisted.
struct NoteSearcher: Sendable {
    struct Limits: Equatable, Sendable {
        /// Enough room for broad searches without allowing an accidental
        /// one-character query to retain the entire vault in view state.
        var maximumResults = 200
        /// One row needs context, not a whole minified document line.
        var maximumSnippetCharacters = 240
        /// Avoid materializing very large/offloaded documents merely because a
        /// search field changed. The skipped count is surfaced to the user.
        var maximumContentFileBytes = 8 * 1_024 * 1_024

        static let standard = Limits()
    }

    private let fileOperations = VaultFileOperations()
    private let limits: Limits

    init(limits: Limits = .standard) {
        self.limits = limits
    }

    /// Case-insensitively matches the query against each file's title and
    /// contents, in tree (display) order. The compatibility API returns only
    /// rows; UI callers should use `searchReport` so skipped files are visible.
    /// Async so callers on the main actor hop off it for the file reads, and
    /// so cancellation (from a superseding search) stops the scan early.
    func search(for query: String, in root: VaultNode) async throws -> [SearchResult] {
        try await searchReport(for: query, in: root).results
    }

    /// Bounded search with explicit partial-result diagnostics.
    func searchReport(for query: String, in root: VaultNode) async throws -> SearchReport {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .empty }

        var results: [SearchResult] = []
        var skippedFileCount = 0
        var reachedLimit = false
        for node in root.allFiles {
            try Task.checkCancellation()
            let titleMatches = Self.matches(query, in: node.displayName)
            // A title hit is already a complete result; don't download and scan
            // an iCloud document only to decorate it with a snippet.
            if titleMatches {
                results.append(SearchResult(node: node, snippet: nil))
                if results.count >= limits.maximumResults {
                    reachedLimit = true
                    break
                }
                continue
            }

            let values: URLResourceValues
            do {
                values = try node.url.resourceValues(forKeys: [.fileSizeKey])
            } catch {
                skippedFileCount += 1
                continue
            }
            if let size = values.fileSize, size > limits.maximumContentFileBytes {
                skippedFileCount += 1
                continue
            }

            let text: String
            do {
                text = try fileOperations.readNote(at: node.url)
            } catch {
                skippedFileCount += 1
                continue
            }
            try Task.checkCancellation()
            let match = Self.firstMatch(
                for: query,
                in: text,
                maximumCharacters: limits.maximumSnippetCharacters)
            let snippet = match?.snippet
            if titleMatches || snippet != nil {
                results.append(
                    SearchResult(
                        node: node,
                        snippet: snippet,
                        lineNumber: match?.lineNumber))
                if results.count >= limits.maximumResults {
                    reachedLimit = true
                    break
                }
            }
        }
        return SearchReport(
            results: results,
            skippedFileCount: skippedFileCount,
            isResultLimitReached: reachedLimit)
    }

    /// Trimmed first line containing the query, or nil if no line matches.
    static func firstMatchingLine(
        for query: String,
        in text: String,
        maximumCharacters: Int = Limits.standard.maximumSnippetCharacters
    ) -> String? {
        firstMatch(for: query, in: text, maximumCharacters: maximumCharacters)?
            .snippet
    }

    /// The first matching line and where it sits. The line number is what
    /// lets a result open the note *at* the match; it is counted the way
    /// every other line number in the app is, so it agrees with the editor.
    static func firstMatch(
        for query: String,
        in text: String,
        maximumCharacters: Int = Limits.standard.maximumSnippetCharacters
    ) -> (snippet: String, lineNumber: Int)? {
        var match: (snippet: String, lineNumber: Int)?
        var lineNumber = 0
        text.enumerateLines { line, stop in
            if matches(query, in: line) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let snippet =
                    trimmed.count > maximumCharacters
                    ? String(trimmed.prefix(maximumCharacters)) + "…"
                    : trimmed
                match = (snippet, lineNumber)
                stop = true
            }
            lineNumber += 1
        }
        return match
    }

    static func matches(_ query: String, in text: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
