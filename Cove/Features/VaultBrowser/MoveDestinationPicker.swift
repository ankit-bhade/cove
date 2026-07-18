import SwiftUI

/// Sheet listing every eligible destination folder for a move: the vault root
/// and its subfolders, indented by depth. The moved folder's own subtree is
/// excluded, and the item's current parent is shown disabled.
struct MoveDestinationPicker: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let node: VaultNode
    let onPick: (URL) -> Void

    private struct Destination: Identifiable {
        let url: URL
        let name: String
        let depth: Int
        var id: String { url.path }
    }

    private var destinations: [Destination] {
        guard let root = vaultManager.rootNode else { return [] }
        var rows = [Destination(url: root.url, name: root.name, depth: 0)]
        appendSubfolders(of: root, depth: 1, to: &rows)
        return rows
    }

    private func appendSubfolders(of folder: VaultNode, depth: Int, to rows: inout [Destination]) {
        for child in folder.children ?? [] where child.isDirectory {
            if child.id == node.id { continue }
            rows.append(Destination(url: child.url, name: child.name, depth: depth))
            appendSubfolders(of: child, depth: depth + 1, to: &rows)
        }
    }

    private var currentParentPath: String {
        node.url.deletingLastPathComponent().standardizedFileURL.path
    }

    var body: some View {
        NavigationStack {
            List(destinations) { destination in
                Button {
                    onPick(destination.url)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        CoveIconTile(systemName: "folder.fill", tint: CoveTheme.seaGlass)
                        Text(destination.name)
                            .font(.body.weight(.medium))
                    }
                    .padding(.vertical, 3)
                    .padding(.leading, CGFloat(destination.depth) * 20)
                }
                .disabled(destination.url.standardizedFileURL.path == currentParentPath)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden)
            .background(CoveTheme.canvas(for: colorScheme))
            .navigationTitle("Move “\(node.displayName)”")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
        #endif
    }
}
