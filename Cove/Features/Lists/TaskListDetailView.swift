import OSLog
import SwiftUI

/// One list's items, with the same quick-entry field the Tasks screen uses.
/// The only difference is that an item here may stay undated — "milk" is a
/// thing to buy, not a thing due today.
struct TaskListDetailView: View {
    let listName: String
    /// The Lists overview's undo bar, for the one action that outlives this
    /// screen: deleting the list pops back there, so a notice raised on this
    /// view's own `actions` would be dismissed along with the view.
    let undo: CoveUndoCenter
    /// How a row here pushes its note. The navigation stack belongs to the
    /// Lists overview, one level up.
    let openNote: (NoteDestination) -> Void

    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var actions = TaskActions()
    @State private var showsRenamePrompt = false
    @State private var renameText = ""
    @State private var showsClearCompletedConfirmation = false
    @State private var showsDeleteConfirmation = false
    /// Done arrives closed, exactly as Completed does on the Tasks screen —
    /// the two headers are one component and a fold that happened on only one
    /// of them is the drift that component exists to prevent.
    @State private var isDoneExpanded = false
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
                    .listRowInsets(CoveTheme.headerRowInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if let list {
                // To Do and Done are one list split in two, so they take one
                // surface with the headings inside it — the same arrangement
                // the Tasks screen uses, because a list's items are ordinary
                // tasks and the two screens are not allowed to drift.
                if !list.isEmpty {
                    Section {
                        if !list.openTasks.isEmpty {
                            CoveSectionHeader("To Do", count: list.openTasks.count)
                                .coveGroupHeaderRow(isFirst: true)
                            TaskRows(tasks: list.openTasks, now: now, actions: actions)
                        }
                        if !list.completedTasks.isEmpty {
                            CompletedTasksHeader(
                                title: "Done",
                                count: list.completedTasks.count,
                                isExpanded: $isDoneExpanded
                            )
                            .coveGroupHeaderRow(
                                isFirst: list.openTasks.isEmpty,
                                isLast: !isDoneExpanded)
                            if isDoneExpanded {
                                TaskRows(tasks: list.completedTasks, now: now, actions: actions)
                                ClearCompletedTasksRow(
                                    isClearing: actions.isClearingCompleted
                                ) {
                                    showsClearCompletedConfirmation = true
                                }
                            }
                        }
                    }
                }
                if list.isEmpty {
                    Section {
                        CoveEmptyState(
                            "Nothing Here Yet",
                            systemName: "tray",
                            description:
                                "Add an item above. A date is optional — “milk” is fine, and so is “order cake fri 3pm”."
                        )
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .coveListStyle()
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
                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Label("Delete List", systemImage: "trash")
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
                actions.clearCompleted(
                    in: vaultManager,
                    undoManager: undoManager
                ) {
                    try await vaultManager.clearCompletedTasks(inList: listName)
                }
            }
        } message: {
            Text(
                "This removes every completed item from “\(listName)”. Its open items stay, and you can undo the clear."
            )
        }
        .confirmationDialog(
            "Delete “\(listName)”?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete List", role: .destructive) {
                delete()
            }
        } message: {
            Text("This removes the list and every task in it from Tasks.md. You can undo the deletion.")
        }
        .alert("Rename List", isPresented: $showsRenamePrompt) {
            TextField("List name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { rename() }
                .disabled(trimmedRenameText.isEmpty)
        }
        .coveTaskScreen(actions, openNote: openNote)
        .coveErrorAlert($actions.errorMessage)
        .coveMinuteTick($now)
    }

    /// List items stay undated unless the sentence actually names a date,
    /// which passing `listName` through to the field takes care of.
    private var captureCard: some View {
        // The navigation bar carries the list's name and the field's
        // placeholder repeats it, so the card itself only has to say what it
        // is — the same compact panel the Tasks screen captures through.
        CovePanel(eyebrow: "Quick Capture") {
            if let list, !list.isEmpty {
                CoveCountBadge("\(list.openTasks.count) open")
                    .accessibilityLabel("\(list.openTasks.count) open items")
            }
        } content: {
            QuickCaptureField(
                placeholder: "Add to \(listName)",
                accessibilityHint: "Enter an item, optionally with a date, time, or repeat rule",
                listName: listName
            ) { draft in
                try await actions.capture(
                    in: vaultManager, undoManager: undoManager
                ) {
                    try await vaultManager.captureTask(draft, into: listName)
                }
            }
        }
    }

    /// The navigation value is the list's name, so a rename makes this view
    /// point at a list that no longer exists — pop back to the overview,
    /// where the new name is already showing.
    private func rename() {
        let newName = trimmedRenameText
        Task {
            do {
                try await vaultManager.renameList(named: listName, to: newName)
                dismiss()
            } catch {
                actions.errorMessage = error.localizedDescription
            }
        }
    }

    private var trimmedRenameText: String {
        renameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Like a rename, this leaves the navigation value pointing at a list
    /// that no longer exists — pop back to the overview rather than sit on
    /// an empty detail view.
    private func delete() {
        Task {
            do {
                let record = try await vaultManager.deleteList(
                    named: listName)
                registerListDeletionUndo(record)
                dismiss()
            } catch {
                actions.errorMessage = error.localizedDescription
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
        ) { [vaultManager] in
            Task {
                do {
                    try await vaultManager.restoreDeletedList(record)
                } catch {
                    CoveLog.vault.error(
                        "Delete List undo failed: \(error.localizedDescription, privacy: .private)"
                    )
                }
            }
        }
    }
}
