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
    /// Explicit and type-erased: a list name pushes a detail view and a task
    /// row inside that view pushes a note, and the detail view can only ask
    /// for the second because the stack lives here.
    @State private var path = NavigationPath()
    /// Deleting a list takes its tasks with it and is a text edit rather than
    /// a file move, so nothing lands in Cove Recovery — the Undo *is* the
    /// recovery. It is owned here rather than in the detail view because
    /// deleting from there pops back to this screen, and a bar belonging to a
    /// view that just went away is a bar nobody sees.
    @State private var undo = CoveUndoCenter()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Lists")
                .navigationDestination(for: String.self) { name in
                    TaskListDetailView(listName: name, undo: undo) {
                        path.append($0)
                    }
                }
                .navigationDestination(for: NoteDestination.self) { destination in
                    EditorView(destination)
                }
                .coveRefreshable { await vaultManager.refresh() }
                .toolbar {
                    ToolbarItem {
                        Button {
                            newListName = ""
                            showsNewListPrompt = true
                        } label: {
                            Label("New List", systemImage: "plus")
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
                .coveUndoBar(undo)
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
                // A summary of one thing is not a summary. With a single list
                // the panel said "1 list · 3 open · 1 done" directly above a
                // row saying "3 open · 1 done", which is the screen stating
                // itself twice and the reason overview cards started reading
                // as a template rather than as information. Summing means
                // something once there is more than one thing to sum — the
                // same call the subscriptions chart makes at one bar.
                if lists.count > 1 {
                    Section {
                        listsOverview(lists)
                            .listRowInsets(CoveTheme.headerRowInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
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
        undo.register(
            named: "Delete List",
            announcing: "List deleted.",
            withTarget: vaultManager,
            undoManager: undoManager
        ) {
            Task {
                do {
                    try await vaultManager.restoreDeletedList(record)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
