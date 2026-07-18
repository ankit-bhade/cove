import SwiftUI

/// Vault tree with mutations: create note/folder, rename, move, delete, and
/// navigation into the editor. Folders sort first, then files, alphabetically.
struct VaultBrowserView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.colorScheme) private var colorScheme

    @State private var namePrompt: NamePrompt?
    @State private var nameInput = ""
    @State private var nodeToMove: VaultNode?
    @State private var nodeToDelete: VaultNode?
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var nodes: [VaultNode] {
        vaultManager.rootNode?.children ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    treeList
                } else {
                    SearchResultsView(query: searchText)
                }
            }
            .navigationDestination(for: VaultNode.self) { node in
                EditorView(fileURL: node.url)
            }
            .searchable(text: $searchText, prompt: "Search all notes")
            .navigationTitle("Notes")
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

    // MARK: - Tree

    private var treeList: some View {
        List {
            Section {
                vaultOverview
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 14, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if nodes.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Your Vault Is Ready", systemImage: "doc.badge.plus")
                    } description: {
                        Text("Create your first Markdown note with the + button above.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    OutlineGroup(nodes, children: \.children) { node in
                        row(for: node)
                    }
                } header: {
                    Text("Library")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
    }

    private var vaultOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image("LaunchIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: CoveTheme.navy.opacity(0.18), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(vaultManager.rootNode?.name ?? "Your Vault")
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    Text("Your Markdown workspace")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(CoveTheme.teal)
                    .accessibilityLabel("Vault connected")
            }

            Divider().opacity(0.6)

            HStack(spacing: 24) {
                overviewStat(value: noteCount, label: noteCount == 1 ? "Note" : "Notes",
                             systemImage: "doc.text.fill")
                overviewStat(value: folderCount, label: folderCount == 1 ? "Folder" : "Folders",
                             systemImage: "folder.fill")
                Spacer()
                Text("Auto-saved")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background { CoveCardBackground() }
    }

    private func overviewStat(value: Int, label: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CoveTheme.teal)
            Text("\(value) \(label)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var noteCount: Int {
        vaultManager.rootNode?.allFiles.count ?? 0
    }

    private var folderCount: Int {
        func count(in nodes: [VaultNode]) -> Int {
            nodes.reduce(0) { result, node in
                result + (node.isDirectory ? 1 : 0) + count(in: node.children ?? [])
            }
        }
        return count(in: nodes)
    }

    @ViewBuilder
    private func row(for node: VaultNode) -> some View {
        Group {
            if node.isDirectory {
                nodeLabel(node)
            } else {
                NavigationLink(value: node) {
                    nodeLabel(node)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu { contextMenu(for: node) }
    }

    private func nodeLabel(_ node: VaultNode) -> some View {
        HStack(spacing: 11) {
            CoveIconTile(systemName: node.isDirectory ? "folder.fill" : "doc.text.fill",
                         tint: node.isDirectory ? CoveTheme.seaGlass : CoveTheme.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if node.isDirectory {
                    let itemCount = node.children?.count ?? 0
                    Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
