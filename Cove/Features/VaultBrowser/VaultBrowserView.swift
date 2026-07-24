import SwiftUI
import OSLog

/// Level-by-level vault browser with mutations and editor navigation. Each
/// folder is pushed onto the navigation stack and shows a scoped overview of
/// the content beneath it.
struct VaultBrowserView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.undoManager) private var undoManager
    /// Set in Settings; empty means the greetings stay impersonal.
    @AppStorage(Greeting.nameStorageKey) private var greetingName = ""

    @State private var namePrompt: NamePrompt?
    @State private var nameInput = ""
    @State private var nodeToMove: VaultNode?
    @State private var nodeToDelete: VaultNode?
    @State private var recoveryNeedingName: RecoveryRecord?
    @State private var errorMessage: String?
    @State private var searchText = ""
    /// Drives the navigation stack directly: each folder is a real push, so
    /// the system back button, its parent-folder title, and the iOS
    /// swipe-back gesture all work the way they do everywhere else.
    @State private var folderPath: [URL] = []

    var body: some View {
        NavigationStack(path: $folderPath) {
            browserLevel(folderURL: nil)
                .navigationDestination(for: URL.self) { url in
                    destination(for: url)
                }
        }
        .onChange(of: vaultManager.vaultURL) { _, _ in
            folderPath.removeAll()
            searchText = ""
        }
        .onChange(of: vaultManager.rootNode) { _, _ in
            // External moves or deletes can invalidate the current URL.
            // Return to the closest ancestor that still exists. Notes are on
            // this path too, so an open editor whose file is gone pops as well.
            while let currentURL = folderPath.last,
                node(at: currentURL) == nil
            {
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
                delete(node)
            }
        } message: { node in
            Text(
                node.isDirectory
                    ? "The folder and everything inside it will move to Cove Recovery."
                    : "The note will move to Cove Recovery.")
        }
        .alert(
            "Original Name In Use",
            isPresented: dismissBinding($recoveryNeedingName),
            presenting: recoveryNeedingName
        ) { record in
            TextField("New name", text: $nameInput)
                #if os(iOS)
                    .textInputAutocapitalization(.words)
                #endif
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Restore") { restore(record, as: trimmedName) }
                .disabled(trimmedName.isEmpty)
        } message: { record in
            Text("“\(record.originalURL.lastPathComponent)” now exists. Choose a new name for the recovered item.")
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

    private func delete(_ node: VaultNode) {
        Task {
            do {
                let record = try await vaultManager.deleteItem(at: node.url)
                undoManager?.registerUndo(withTarget: vaultManager) { manager in
                    Task { @MainActor in
                        do {
                            try await manager.restoreDeletedItem(record)
                        } catch VaultFileOperations.OperationError.itemAlreadyExists(_) {
                            nameInput = record.originalURL.deletingPathExtension().lastPathComponent
                            recoveryNeedingName = record
                        } catch {
                            CoveLog.vault.error(
                                "Recovery restore failed: \(error.localizedDescription, privacy: .private)")
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                undoManager?.setActionName(node.isDirectory ? "Delete Folder" : "Delete Note")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore(_ record: RecoveryRecord, as name: String) {
        Task {
            do {
                try await vaultManager.restoreDeletedItem(record, as: name)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Folder levels

    /// Folders and notes share one `[URL]` navigation path. The stack's path
    /// is typed, so a link carrying any other value type would silently do
    /// nothing — pushing URLs for both and branching here is what keeps note
    /// rows (and search results) working.
    @ViewBuilder
    private func destination(for url: URL) -> some View {
        if isNote(at: url) {
            EditorView(fileURL: url)
        } else {
            browserLevel(folderURL: url)
        }
    }

    /// Prefers the scanned tree, falling back to the extension when the URL
    /// isn't in it — during a rescan a note can briefly go missing, and
    /// re-routing it to an empty folder level would flicker the editor away.
    private func isNote(at url: URL) -> Bool {
        if let node = node(at: url) { return !node.isDirectory }
        return url.pathExtension.lowercased() == "md"
    }

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
                    overview(for: folder, isRoot: folder.url == vaultManager.vaultURL)
                        .listRowInsets(CoveTheme.mastheadRowInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if nodes.isEmpty {
                Section {
                    CoveEmptyState(
                        "Nothing Here Yet",
                        systemName: "square.and.pencil",
                        description: "Create a Markdown note or folder with the + button above."
                    )
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(nodes) { node in
                        row(for: node)
                    }
                } header: {
                    CoveSectionHeader("Contents", count: nodes.count)
                }
            }
        }
        .coveListStyle()
        .coveReadableWidth()
    }

    private func folderNode(at folderURL: URL?) -> VaultNode? {
        guard let folderURL else { return vaultManager.rootNode }
        return node(at: folderURL)
    }

    /// Any node in the scanned tree — folder or note — at this URL.
    private func node(at url: URL) -> VaultNode? {
        guard let root = vaultManager.rootNode else { return nil }
        return node(at: url.standardizedFileURL, in: root)
    }

    private func node(at targetURL: URL, in node: VaultNode) -> VaultNode? {
        if node.url.standardizedFileURL == targetURL { return node }
        // Notes are searched too: they sit on the navigation path alongside
        // folders, so the path-pruning check has to be able to find them.
        for child in node.children ?? [] {
            if let match = self.node(at: targetURL, in: child) { return match }
        }
        return nil
    }

    /// The masthead over a folder level. At the root it is a greeting — the
    /// one place in the app that addresses the reader. Deeper in, the greeting
    /// would be a second hello inside the same session, so the folder names
    /// itself instead and the eyebrow says where it sits.
    private func overview(for folder: VaultNode, isRoot: Bool) -> some View {
        let counts = overviewCounts(for: folder)
        let stats = [
            CoveStat(counts.folders, counts.folders == 1 ? "Folder" : "Folders"),
            CoveStat(counts.subfolders, counts.subfolders == 1 ? "Subfolder" : "Subfolders"),
            CoveStat(counts.notes, counts.notes == 1 ? "Note" : "Notes"),
        ]

        return TimelineView(.periodic(from: .now, by: 60)) { context in
            // The eyebrow never repeats the navigation title above it: at the
            // root it names the open vault — the one thing on screen that
            // nothing else says — and deeper in it labels the kind of thing
            // the bar is already naming.
            CoveMasthead(
                eyebrow: isRoot ? folder.displayName : "Folder",
                title: isRoot
                    ? Greeting.text(for: context.date, name: greetingName)
                    : folder.displayName,
                subtitle: isRoot
                    ? "Plain Markdown files, exactly where you left them."
                    : nil
            ) {
                CoveStatStrip(stats: stats)
            }
        }
    }

    /// Direct folders, deeper folders, and all notes within this level.
    private func overviewCounts(for folder: VaultNode) -> (folders: Int, subfolders: Int, notes: Int) {
        let children = folder.children ?? []
        let directFolders = children.filter(\.isDirectory).count
        let allFolders = countFolders(in: children)
        return (
            directFolders,
            max(0, allFolders - directFolders),
            children.flatMap(\.allFiles).count
        )
    }

    private func countFolders(in nodes: [VaultNode]) -> Int {
        nodes.reduce(0) { count, node in
            count + (node.isDirectory ? 1 : 0) + countFolders(in: node.children ?? [])
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for node: VaultNode) -> some View {
        // Folders and notes both push their URL; `destination(for:)` decides
        // which screen that URL opens.
        NavigationLink(value: node.url) {
            nodeLabel(node)
        }
        .contextMenu {
            contextMenu(for: node)
        }
    }

    /// Folders take the supporting hue and notes the accent: the two kinds of
    /// row are told apart by color before the glyph inside them is read.
    private func nodeLabel(_ node: VaultNode) -> some View {
        CoveRow(
            systemName: node.isDirectory ? "folder.fill" : "doc.text.fill",
            tint: node.isDirectory ? CoveTheme.moss : CoveTheme.accent
        ) {
            CoveRowTitle(title: node.displayName, caption: itemCountCaption(for: node))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func itemCountCaption(for node: VaultNode) -> String? {
        guard node.isDirectory else { return nil }
        let itemCount = node.children?.count ?? 0
        return "\(itemCount) \(itemCount == 1 ? "item" : "items")"
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
                .keyboardShortcut("n", modifiers: .command)
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
            CoveRefreshButton {
                await vaultManager.refresh()
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
