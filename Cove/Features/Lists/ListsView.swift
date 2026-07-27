import SwiftUI

/// The lists in the capture note: named groups like Groceries or
/// Subscriptions, each a `##` section of `Tasks.md`. Their items are
/// ordinary Cove tasks — natural-language capture, optional due dates and
/// times, the same notifications — kept out of the Tasks screen so a
/// shopping list doesn't crowd out what's actually due.
struct ListsView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.undoManager) private var undoManager
    @State private var errorMessage: String?
    @State private var newListName = ""
    @State private var showsNewListPrompt = false
    @State private var pendingDeletion: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Lists")
                .navigationDestination(for: String.self) { name in
                    TaskListDetailView(listName: name)
                }
                .navigationDestination(for: NoteDestination.self) { destination in
                    EditorView(destination)
                }
                .toolbar {
                    ToolbarItem {
                        Button {
                            newListName = ""
                            showsNewListPrompt = true
                        } label: {
                            Label("New List", systemImage: "plus")
                        }
                    }
                    ToolbarItem {
                        CoveRefreshButton {
                            await vaultManager.refresh()
                        }
                    }
                }
                .alert("New List", isPresented: $showsNewListPrompt) {
                    TextField("List name", text: $newListName)
                    Button("Cancel", role: .cancel) {}
                    Button("Create") { createList() }
                        .disabled(trimmedNewListName.isEmpty)
                } message: {
                    Text("Lists are sections of Tasks.md, so you can edit them as Markdown too.")
                }
                .coveErrorAlert($errorMessage)
        }
    }

    @ViewBuilder
    private var content: some View {
        let lists = vaultManager.index.lists
        List {
            if lists.isEmpty {
                Section {
                    CoveEmptyState(
                        "No Lists Yet",
                        systemName: "list.bullet.rectangle",
                        description: "Group things that belong together — groceries, subscriptions, or packing."
                    ) {
                        Button("New List") {
                            newListName = ""
                            showsNewListPrompt = true
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: CoveTheme.fieldRadius))
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    listsOverview(lists)
                        .listRowInsets(CoveTheme.headerRowInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    ForEach(lists) { list in
                        NavigationLink(value: list.name) {
                            row(for: list)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDeletion = list.name
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        // The swipe is invisible until it's tried, and macOS has
                        // no swipe at all, so the same action gets a menu.
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDeletion = list.name
                            } label: {
                                Label("Delete List", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    CoveSectionHeader("Collections", count: lists.count)
                }
            }
        }
        .coveListStyle()
        .coveReadableWidth()
        .confirmationDialog(
            "Delete “\(pendingDeletion ?? "")”?",
            isPresented: $pendingDeletion.covePresence(),
            titleVisibility: .visible
        ) {
            Button("Delete List", role: .destructive) {
                if let name = pendingDeletion { deleteList(named: name) }
            }
        } message: {
            Text("This removes the list and every task in it from Tasks.md. You can undo the deletion.")
        }
    }

    private func listsOverview(_ lists: [TaskList]) -> some View {
        let open = lists.reduce(0) { $0 + $1.openTasks.count }
        let completed = lists.reduce(0) { $0 + $1.completedTasks.count }

        // The three figures are the whole point of this card; the slogan over
        // them was decoration that pushed the lists themselves down the screen.
        return CovePanel(eyebrow: "Overview") {
            CoveStatStrip(stats: [
                CoveStat(lists.count, lists.count == 1 ? "List" : "Lists"),
                CoveStat(open, "Open"),
                CoveStat(completed, "Done"),
            ])
        }
    }

    private func row(for list: TaskList) -> some View {
        CoveRow(systemName: "list.bullet", tint: CoveTheme.moss) {
            CoveRowTitle(title: list.name, caption: subtitle(for: list))
            Spacer(minLength: 0)
            if !list.openTasks.isEmpty {
                CoveCountBadge("\(list.openTasks.count)")
            }
        }
    }

    private func subtitle(for list: TaskList) -> String {
        if list.isEmpty { return "Empty" }
        let open = list.openTasks.count
        let done = list.completedTasks.count
        let openText = open == 1 ? "1 open" : "\(open) open"
        return done == 0 ? openText : "\(openText) · \(done) done"
    }

    private func createList() {
        let name = trimmedNewListName
        Task {
            do {
                try await vaultManager.createList(named: name)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var trimmedNewListName: String {
        newListName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deleteList(named name: String) {
        Task {
            do {
                let record = try await vaultManager.deleteList(named: name)
                registerListDeletionUndo(record)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func registerListDeletionUndo(
        _ record: TaskListDocument.SectionRemovalRecord
    ) {
        undoManager?.registerUndo(withTarget: vaultManager) { manager in
            Task {
                do {
                    try await manager.restoreDeletedList(record)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        undoManager?.setActionName("Delete List")
    }
}
