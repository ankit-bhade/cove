import SwiftUI

/// Level-by-level vault browser with mutations and editor navigation. Each
/// folder is pushed onto the navigation stack and shows a scoped overview of
/// the content beneath it.
struct VaultBrowserView: View {
    @Environment(VaultManager.self) private var vaultManager
    /// Set in Settings; empty means the greetings stay impersonal.
    @AppStorage(Greeting.nameStorageKey) private var greetingName = ""

    @State private var namePrompt: NamePrompt?
    @State private var nameInput = ""
    @State private var nodeToMove: VaultNode?
    @State private var nodeToDelete: VaultNode?
    @State private var errorMessage: String?
    @State private var searchText = ""
    /// Drives the navigation stack directly: each folder is a real push, so
    /// the system back button, its parent-folder title, and the iOS
    /// swipe-back gesture all work the way they do everywhere else.
    @State private var folderPath: [URL] = []

    var body: some View {
        NavigationStack(path: $folderPath) {
            browserLevel(folderURL: nil)
                .navigationDestination(for: URL.self) { folderURL in
                    browserLevel(folderURL: folderURL)
                }
                .navigationDestination(for: VaultNode.self) { node in
                    EditorView(fileURL: node.url)
                }
        }
        .onChange(of: vaultManager.vaultURL) { _, _ in
            folderPath.removeAll()
            searchText = ""
        }
        .onChange(of: vaultManager.rootNode) { _, _ in
            // External moves or deletes can invalidate the current URL.
            // Return to the closest parent that still exists.
            while let currentURL = folderPath.last,
                  folderNode(at: currentURL) == nil {
                folderPath.removeLast()
            }
        }
        .alert(
            namePrompt?.title ?? "",
            isPresented: dismissBinding($namePrompt),
            presenting: namePrompt
        ) { prompt in
            TextField(prompt.placeholder, text: $nameInput)
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            // An empty name always fails validation downstream, so the
            // confirm button stays inert rather than opening an error alert.
            Button(prompt.confirmTitle) { submit(prompt) }
                .disabled(trimmedName.isEmpty)
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

    // MARK: - Folder levels

    private func browserLevel(folderURL: URL?) -> some View {
        let folder = folderNode(at: folderURL)
        let destinationURL = folder?.url ?? vaultManager.vaultURL

        return Group {
            if searchText.isEmpty {
                folderList(folder: folder)
            } else {
                SearchResultsView(query: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Search all notes")
        .navigationTitle(folderURL == nil ? "Notes" : folder?.displayName ?? "Folder")
        .toolbar {
            if let destinationURL {
                toolbarContent(in: destinationURL)
            }
        }
    }

    private func folderList(folder: VaultNode?) -> some View {
        let nodes = folder?.children ?? []

        return List {
            if let folder {
                Section {
                    vaultOverview(for: folder)
                        .listRowInsets(CoveTheme.dashboardRowInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if nodes.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("This Folder Is Ready", systemImage: "doc.badge.plus")
                    } description: {
                        Text("Create a Markdown note or folder with the + button above.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(nodes) { node in
                        row(for: node)
                    }
                } header: {
                    Text("Contents")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .coveListStyle()
    }

    private func folderNode(at folderURL: URL?) -> VaultNode? {
        guard let root = vaultManager.rootNode else { return nil }
        guard let folderURL else { return root }
        return node(at: folderURL.standardizedFileURL, in: root)
    }

    private func node(at targetURL: URL, in node: VaultNode) -> VaultNode? {
        if node.url.standardizedFileURL == targetURL { return node }
        for child in node.children ?? [] where child.isDirectory {
            if let match = self.node(at: targetURL, in: child) { return match }
        }
        return nil
    }

    private func vaultOverview(for folder: VaultNode) -> some View {
        let counts = overviewCounts(for: folder)

        return TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 18) {
                Text(Greeting.text(for: context.date, name: greetingName))
                    .font(.title3.weight(.semibold))

                HStack(spacing: 0) {
                    overviewStat(value: counts.folders,
                                 label: counts.folders == 1 ? "Folder" : "Folders")
                    Divider()
                        .padding(.vertical, 2)
                    overviewStat(value: counts.subfolders,
                                 label: counts.subfolders == 1 ? "Subfolder" : "Subfolders")
                    Divider()
                        .padding(.vertical, 2)
                    overviewStat(value: counts.notes,
                                 label: counts.notes == 1 ? "Note" : "Notes")
                }
                .frame(height: 42)
            }
            .padding(18)
            .background { CoveCardBackground() }
        }
    }

    private func overviewStat(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.title3.weight(.bold))
                .foregroundStyle(CoveTheme.teal)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    /// Direct folders, deeper folders, and all notes within this level.
    private func overviewCounts(for folder: VaultNode) ->
        (folders: Int, subfolders: Int, notes: Int) {
        let children = folder.children ?? []
        let directFolders = children.filter(\.isDirectory).count
        let allFolders = countFolders(in: children)
        return (directFolders,
                max(0, allFolders - directFolders),
                children.flatMap(\.allFiles).count)
    }

    private func countFolders(in nodes: [VaultNode]) -> Int {
        nodes.reduce(0) { count, node in
            count + (node.isDirectory ? 1 : 0) + countFolders(in: node.children ?? [])
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for node: VaultNode) -> some View {
        Group {
            if node.isDirectory {
                NavigationLink(value: node.url) {
                    nodeLabel(node)
                }
            } else {
                NavigationLink(value: node) {
                    nodeLabel(node)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            contextMenu(for: node)
        }
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
    private func toolbarContent(in folder: URL) -> some ToolbarContent {
        ToolbarItem {
            Menu {
                Button {
                    present(NamePrompt(kind: .newNote(in: folder)))
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                Button {
                    present(NamePrompt(kind: .newFolder(in: folder)))
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

    private var trimmedName: String {
        nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func present(_ prompt: NamePrompt) {
        nameInput = prompt.initialText
        namePrompt = prompt
    }

    private func submit(_ prompt: NamePrompt) {
        let name = trimmedName
        guard !name.isEmpty else { return }
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

    /// Names the thing being created or renamed, so the field isn't a bare
    /// "Name" with no hint of what it belongs to.
    var placeholder: String {
        switch kind {
        case .newNote: "Note name"
        case .newFolder: "Folder name"
        case .rename(let node): node.isDirectory ? "Folder name" : "Note name"
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
