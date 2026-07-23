import SwiftUI

/// Sheet listing every eligible destination folder for a move: the vault root
/// and its subfolders, indented by depth. The moved folder's own subtree is
/// excluded, and the item's current parent is shown disabled.
struct MoveDestinationPicker: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.dismiss) private var dismiss

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
                let isCurrent = destination.url.standardizedFileURL.path == currentParentPath
                Button {
                    onPick(destination.url)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        CoveIconTile(systemName: "folder.fill", tint: CoveTheme.moss)
                        Text(destination.name)
                            .font(.body.weight(.medium))
                        Spacer()
                        // Without this the row is simply inert, which reads
                        // as a bug rather than as "it is already here".
                        if isCurrent {
                            CoveCountBadge("Current", tint: .secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    // Deep vaults should still leave room for the folder
                    // name; cap visual indentation while preserving order.
                    .padding(.leading, CGFloat(min(destination.depth, 4)) * 16)
                }
                .disabled(isCurrent)
                .accessibilityHint(isCurrent ? "Already contains this item"
                                   : "Moves the item into this folder")
            }
            .coveListStyle()
            .coveReadableWidth(620)
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
