import SwiftUI

/// One list's items, with the same quick-entry field the Tasks screen uses.
/// The only difference is that an item here may stay undated — "milk" is a
/// thing to buy, not a thing due today.
struct TaskListDetailView: View {
    let listName: String

    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var showsRenamePrompt = false
    @State private var renameText = ""
    @State private var showsClearCompletedConfirmation = false
    @State private var isClearingCompleted = false
    /// Ticks each minute so a dated item's "Today" stays true while the
    /// list sits open across a due moment or across midnight.
    @State private var now = Date()

    /// The list as the current index sees it. Nil once it's been deleted,
    /// which is what pops this view.
    private var list: TaskList? {
        vaultManager.index.lists.first { $0.name == listName }
    }

    var body: some View {
        List {
            Section {
                captureCard
                    .listRowInsets(CoveTheme.dashboardRowInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if let list {
                if !list.openTasks.isEmpty {
                    Section {
                        ForEach(list.openTasks) { task in
                            TaskRow(task: task, now: now,
                                    onToggle: { toggle(task) },
                                    onDelete: { delete(task) })
                        }
                    } header: {
                        Text("To Do · \(list.openTasks.count)")
                            .font(.caption.weight(.semibold))
                    }
                }
                if !list.completedTasks.isEmpty {
                    Section {
                        ForEach(list.completedTasks) { task in
                            TaskRow(task: task, now: now,
                                    onToggle: { toggle(task) },
                                    onDelete: { delete(task) })
                        }
                    } header: {
                        HStack {
                            Text("Done · \(list.completedTasks.count)")
                            Spacer()
                            Button("Clear All", role: .destructive) {
                                showsClearCompletedConfirmation = true
                            }
                            .buttonStyle(.borderless)
                            .disabled(isClearingCompleted)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                if list.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("Nothing Here Yet", systemImage: "tray")
                        } description: {
                            Text("Add an item above. A date is optional — “milk” is fine, and so is “order cake fri 3pm”.")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .coveListStyle()
        #if os(iOS)
        .listSectionSpacing(.compact)
        #endif
        .coveReadableWidth()
        .navigationTitle(listName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Menu {
                    Button {
                        renameText = listName
                        showsRenamePrompt = true
                    } label: {
                        Label("Rename List", systemImage: "pencil")
                    }
                } label: {
                    Label("List Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Clear Completed Items?",
            isPresented: $showsClearCompletedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                clearCompletedTasks()
            }
        } message: {
            Text("This permanently removes every completed item from “\(listName)”. Its open items stay.")
        }
        .alert("Rename List", isPresented: $showsRenamePrompt) {
            TextField("List name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
        }
        .coveErrorAlert($errorMessage)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
            }
        }
    }

    /// List items stay undated unless the sentence actually names a date,
    /// which passing `listName` through to the field takes care of.
    private var captureCard: some View {
        QuickCaptureField(
            placeholder: "Add to \(listName)",
            accessibilityHint: "Enter an item, optionally with a date, time, or repeat rule",
            listName: listName
        ) { draft in
            capture(draft)
        }
        .padding(14)
        .background { CoveCardBackground() }
    }

    private func capture(_ draft: TaskDraft) {
        Task {
            do {
                try await vaultManager.captureTask(draft, into: listName)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// The navigation value is the list's name, so a rename makes this view
    /// point at a list that no longer exists — pop back to the overview,
    /// where the new name is already showing.
    private func rename() {
        let newName = renameText
        Task {
            do {
                try await vaultManager.renameList(named: listName, to: newName)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func toggle(_ task: TaskItem) {
        Task {
            do {
                try await vaultManager.toggleTask(task)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearCompletedTasks() {
        isClearingCompleted = true
        Task {
            defer { isClearingCompleted = false }
            do {
                try await vaultManager.clearCompletedTasks(inList: listName)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ task: TaskItem) {
        Task {
            do {
                try await vaultManager.deleteTask(task)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
