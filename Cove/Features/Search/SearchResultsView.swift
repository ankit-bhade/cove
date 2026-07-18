import SwiftUI

/// Results list for the browser's search field. Debounces the query while
/// typing, runs one on-demand search over every Markdown file, and navigates
/// to the editor through the browser's existing `VaultNode` destination.
struct SearchResultsView: View {
    let query: String

    @Environment(VaultManager.self) private var vaultManager
    @State private var results: [SearchResult] = []
    @State private var hasSearched = false

    private let searcher = NoteSearcher()

    var body: some View {
        List(results) { result in
            NavigationLink(value: result.node) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(result.node.displayName, systemImage: "doc.text")
                    if let snippet = result.snippet {
                        Text(snippet)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .overlay {
            if hasSearched, results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
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
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            results = try await searcher.search(for: query, in: root)
            hasSearched = true
        } catch {
            // Cancelled by a newer query; its task will publish results.
        }
    }
}
