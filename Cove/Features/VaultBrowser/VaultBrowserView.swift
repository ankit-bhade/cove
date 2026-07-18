import SwiftUI

/// Vault tree with mutations: create note/folder, rename, move, delete, and
/// navigation into the editor. Folders sort first, then files, alphabetically.
struct VaultBrowserView: View {
    @Environment(VaultManager.self) private var vaultManager

    @State private var namePrompt: NamePrompt?
    @State private var nameInput = ""
    @State private var nodeToMove: VaultNode?
    @State private var nodeToDelete: VaultNode?
    @State private var errorMessage: String?

    private var nodes: [VaultNode] {
        vaultManager.rootNode?.children ?? []
    }

    var body: some View {
        NavigationStack {
            List(nodes, children: \.children) { node in
                row(for: node)
            }
            .navigationDestination(for: VaultNode.self) { node in
                EditorView(fileURL: node.url)
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
            .toolbar { toolbarContent }
            .alert(
                namePrompt?.title ?? "",
                isPresented: dismissBinding($namePrompt),
                presenting: namePrompt
            ) { prompt in
                TextField("Name", text: $nameInput)
                Button("Cancel", role: .cancel) {}
                Button(prompt.confirmTitle) { submit(prompt) }
            }
            .sheet(item: $nodeToMove) { node in
                MoveDestinationPicker(node: node) { destination in
                    run { try await vaultManager.move(itemAt: node.url, into: destination) }
                }
            }
            .confirmationDialog(
                "Delete “\(nodeToDelete?.displayName ?? "")”?",
                isPresented: dismissBinding($nodeToDelete),
                titleVisibility: .visible,
                presenting: nodeToDelete
            ) { node in
                Button("Delete", role: .destructive) {
                    run { try await vaultManager.deleteItem(at: node.url) }
                }
            } message: { node in
                Text(node.isDirectory
                     ? "The folder and everything inside it will be deleted."
                     : "The note will be deleted.")
            }
            .alert(
                "Something Went Wrong",
                isPresented: dismissBinding($errorMessage)
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for node: VaultNode) -> some View {
        Group {
            if node.isDirectory {
                Label(node.displayName, systemImage: "folder")
            } else {
                NavigationLink(value: node) {
                    Label(node.displayName, systemImage: "doc.text")
                }
            }
        }
        .contextMenu { contextMenu(for: node) }
    }

    @ViewBuilder
    private func contextMenu(for node: VaultNode) -> some View {
        if node.isDirectory {
            Button {
                present(NamePrompt(kind: .newNote(in: node.url)))
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
            Button {
                present(NamePrompt(kind: .newFolder(in: node.url)))
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Divider()
        }
        Button {
            present(NamePrompt(kind: .rename(node)))
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            nodeToMove = node
        } label: {
            Label("Move…", systemImage: "arrow.turn.down.right")
        }
        Divider()
        Button(role: .destructive) {
            nodeToDelete = node
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button {
                    if let root = vaultManager.vaultURL {
                        present(NamePrompt(kind: .newNote(in: root)))
                    }
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                Button {
                    if let root = vaultManager.vaultURL {
                        present(NamePrompt(kind: .newFolder(in: root)))
                    }
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        ToolbarItem {
            Button {
                Task { await vaultManager.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - Actions

    private func present(_ prompt: NamePrompt) {
        nameInput = prompt.initialText
        namePrompt = prompt
    }

    private func submit(_ prompt: NamePrompt) {
        let name = nameInput
        run {
            switch prompt.kind {
            case .newNote(let folder):
                try await vaultManager.createNote(named: name, in: folder)
            case .newFolder(let folder):
                try await vaultManager.createFolder(named: name, in: folder)
            case .rename(let node):
                try await vaultManager.rename(itemAt: node.url, to: name)
            }
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Presentation binding for optional state: reads presence, and clears
    /// the state when the presentation is dismissed.
    private func dismissBinding<T>(_ state: Binding<T?>) -> Binding<Bool> {
        Binding(
            get: { state.wrappedValue != nil },
            set: { if !$0 { state.wrappedValue = nil } }
        )
    }
}

/// One pending create-or-rename prompt: what to do and where.
struct NamePrompt: Identifiable {
    enum Kind {
        case newNote(in: URL)
        case newFolder(in: URL)
        case rename(VaultNode)
    }

    let kind: Kind
    let id = UUID()

    var title: String {
        switch kind {
        case .newNote: "New Note"
        case .newFolder: "New Folder"
        case .rename(let node): node.isDirectory ? "Rename Folder" : "Rename Note"
        }
    }

    var confirmTitle: String {
        switch kind {
        case .newNote, .newFolder: "Create"
        case .rename: "Rename"
        }
    }

    var initialText: String {
        if case .rename(let node) = kind { node.displayName } else { "" }
    }
}
