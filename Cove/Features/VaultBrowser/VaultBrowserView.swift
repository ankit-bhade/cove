import SwiftUI

/// Read-only tree of the vault: folders first, then Markdown files.
struct VaultBrowserView: View {
    @Environment(VaultManager.self) private var vaultManager

    private var nodes: [VaultNode] {
        vaultManager.rootNode?.children ?? []
    }

    var body: some View {
        NavigationStack {
            List(nodes, children: \.children) { node in
                Label(node.displayName,
                      systemImage: node.isDirectory ? "folder" : "doc.text")
            }
            .overlay {
                if nodes.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "doc.text",
                        description: Text("This folder has no Markdown files yet.")
                    )
                }
            }
            .navigationTitle(vaultManager.rootNode?.name ?? "Vault")
            .toolbar {
                Button {
                    Task { await vaultManager.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}
