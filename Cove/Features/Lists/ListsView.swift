import SwiftUI

/// The lists in the capture note: named groups like Groceries or
/// Subscriptions, each a `##` section of `Tasks.md`. Their items are
/// ordinary Cove tasks — natural-language capture, optional due dates and
/// times, the same notifications — kept out of the Tasks screen so a
/// shopping list doesn't crowd out what's actually due.
struct ListsView: View {
    @Environment(VaultManager.self) private var vaultManager
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
                .navigationDestination(for: URL.self) { url in
                    EditorView(fileURL: url)
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
                // Editor autosaves don't rescan the vault, so returning to
                // this tab picks up lists edited by hand.
                .task {
                    await vaultManager.refresh()
                }
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
                        .tint(CoveTheme.teal)
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    listsOverview(lists)
                        .listRowInsets(CoveTheme.dashboardRowInsets())
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
                    Text("Collections")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .coveListStyle()
        .coveReadableWidth()
        .confirmationDialog(
            "Delete “\(pendingDeletion ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil },
                                 set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete List", role: .destructive) {
                if let name = pendingDeletion { deleteList(named: name) }
            }
        } message: {
            Text("This removes the list and every task in it from Tasks.md.")
        }
    }

    private func listsOverview(_ lists: [TaskList]) -> some View {
        let open = lists.reduce(0) { $0 + $1.openTasks.count }
        let completed = lists.reduce(0) { $0 + $1.completedTasks.count }

        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                CoveHeroIcon(systemName: "list.bullet.rectangle.fill", size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Everything in its place")
                        .font(.title3.weight(.semibold))
                    Text("Reusable lists for the things you keep track of")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    listMetric(lists.count, label: lists.count == 1 ? "List" : "Lists")
                    Divider().padding(.vertical, 2)
                    listMetric(open, label: "Open")
                    Divider().padding(.vertical, 2)
                    listMetric(completed, label: "Done")
                }
                VStack(spacing: 10) {
                    listMetric(lists.count, label: lists.count == 1 ? "List" : "Lists")
                    listMetric(open, label: "Open")
                    listMetric(completed, label: "Done")
                }
            }
            .frame(minHeight: 42)
        }
        .padding(20)
        .background { CoveHeroCardBackground() }
    }

    private func listMetric(_ value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.title3.weight(.bold))
                .foregroundStyle(CoveTheme.teal)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }

    private func row(for list: TaskList) -> some View {
        HStack(spacing: 12) {
            CoveIconTile(systemName: "list.bullet")
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name)
                    .font(.body.weight(.medium))
                Text(subtitle(for: list))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !list.openTasks.isEmpty {
                Text("\(list.openTasks.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CoveTheme.teal)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(CoveTheme.teal.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 3)
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
                try await vaultManager.deleteList(named: name)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
