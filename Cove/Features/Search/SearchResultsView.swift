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
                            HStack(alignment: .top, spacing: 12) {
                                CoveIconTile(systemName: "doc.text.fill")
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(result.node.displayName)
                                        .font(.body.weight(.semibold))
                                    if let snippet = result.snippet {
                                        Text(snippet)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .lineSpacing(2)
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                } header: {
                    Text("\(results.count) \(results.count == 1 ? "result" : "results")")
                        .font(.caption.weight(.semibold))
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
                    ProgressView().tint(CoveTheme.teal)
                    Text("Searching your notes…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if hasSearched, results.isEmpty {
                ContentUnavailableView {
                    Label("No Notes Found", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different title or phrase.")
                }
            } else if let searchError {
                ContentUnavailableView {
                    Label("Search Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(searchError)
                }
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
