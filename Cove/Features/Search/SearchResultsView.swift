import SwiftUI

/// Results list for the browser's search field. Debounces the query while
/// typing, runs one on-demand search over every Markdown file, and navigates
/// to the editor by pushing the note's URL onto the browser's `[URL]` path.
struct SearchResultsView: View {
    let query: String

    @Environment(VaultManager.self) private var vaultManager
    @State private var results: [SearchResult] = []
    @State private var hasSearched = false
    @State private var isSearching = false
    @State private var searchError: String?

    private let searcher = NoteSearcher()

    var body: some View {
        List {
            if hasSearched, !results.isEmpty {
                Section {
                    ForEach(results) { result in
                        NavigationLink(value: result.node.url) {
                            // A snippet wraps, so the tile pins to the top —
                            // and the row is the same note row the browser
                            // draws, since it opens the same note.
                            CoveRow(systemName: "doc.text.fill", alignment: .top) {
                                CoveRowTitle(
                                    title: result.node.displayName,
                                    caption: result.snippet,
                                    captionIsLabel: false)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                } header: {
                    CoveSectionHeader(
                        results.count == 1 ? "Result" : "Results",
                        count: results.count)
                }
            }
        }
        .coveListStyle()
        .coveReadableWidth()
        .overlay {
            if isSearching {
                // The debounce plus a full-vault read is long enough that a
                // blank list reads as "no matches" instead of "working".
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching your notes…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if hasSearched, results.isEmpty {
                // Cove's own empty state rather than the system's: a search
                // that finds nothing is the most-seen empty screen in the
                // app, and the generic one looks like a different product.
                CoveEmptyState(
                    "No Notes Found",
                    systemName: "magnifyingglass",
                    description: "Try a different title or phrase — search reads every note's text as well as its name."
                )
            } else if let searchError {
                CoveEmptyState(
                    "Search Unavailable",
                    systemName: "exclamationmark.triangle",
                    description: searchError
                )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSearching)
        .task(id: query) {
            await runSearch()
        }
    }

    /// Restarted by `.task(id:)` on every keystroke; the sleep is the
    /// debounce, since a superseded task is cancelled mid-sleep.
    private func runSearch() async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let root = vaultManager.rootNode else {
            results = []
            hasSearched = false
            isSearching = false
            searchError = nil
            return
        }
        isSearching = true
        searchError = nil
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            results = try await searcher.search(for: query, in: root)
            hasSearched = true
            isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            hasSearched = false
            isSearching = false
            searchError = error.localizedDescription
        }
    }
}
