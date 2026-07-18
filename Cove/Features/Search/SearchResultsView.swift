import SwiftUI

/// Results list for the browser's search field. Debounces the query while
/// typing, runs one on-demand search over every Markdown file, and navigates
/// to the editor through the browser's existing `VaultNode` destination.
struct SearchResultsView: View {
    let query: String

    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var results: [SearchResult] = []
    @State private var hasSearched = false

    private let searcher = NoteSearcher()

    var body: some View {
        List {
            if hasSearched, !results.isEmpty {
                Section {
                    ForEach(results) { result in
                        NavigationLink(value: result.node) {
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
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .background(CoveTheme.canvas(for: colorScheme))
        .overlay {
            if hasSearched, results.isEmpty {
                ContentUnavailableView {
                    Label("No Notes Found", systemImage: "magnifyingglass")
                } description: {
                    Text("Try a different title or phrase.")
                }
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
