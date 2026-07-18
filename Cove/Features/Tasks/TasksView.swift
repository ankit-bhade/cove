import SwiftUI

/// All due tasks collected by the in-memory index: incomplete tasks sorted
/// by due date, completed ones below. Toggling a checkbox rewrites the line
/// in the task's original Markdown file; tapping the row opens the note.
struct TasksView: View {
    @Environment(VaultManager.self) private var vaultManager
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Tasks")
                .navigationDestination(for: URL.self) { url in
                    EditorView(fileURL: url)
                }
                .toolbar {
                    ToolbarItem {
                        Button {
                            Task { await vaultManager.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
                .alert(
                    "Something Went Wrong",
                    isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { if !$0 { errorMessage = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(errorMessage ?? "")
                }
                // Editor autosaves don't rescan the vault, so returning to
                // this tab rebuilds the index to pick up freshly typed tasks.
                .task {
                    await vaultManager.refresh()
                }
        }
    }

    private var list: some View {
        let incomplete = vaultManager.index.incompleteTasks
        let completed = vaultManager.index.completedTasks
        return List {
            if !incomplete.isEmpty {
                Section("Due") {
                    ForEach(incomplete) { task in
                        row(for: task)
                    }
                }
            }
            if !completed.isEmpty {
                Section("Completed") {
                    ForEach(completed) { task in
                        row(for: task)
                    }
                }
            }
        }
        .overlay {
            if incomplete.isEmpty, completed.isEmpty {
                ContentUnavailableView(
                    "No Tasks",
                    systemImage: "checklist",
                    description: Text("Add a line like “- [ ] Task text @due(2026-01-31)” to any note.")
                )
            }
        }
    }

    private func row(for task: TaskItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                toggle(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.square" : "square")
                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")

            NavigationLink(value: task.fileURL) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.text)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    HStack(spacing: 4) {
                        dueLabel(for: task)
                        Text("·")
                        Text(task.fileTitle)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func dueLabel(for task: TaskItem) -> some View {
        let isOverdue = !task.isCompleted && task.dueDateString < Self.todayString()
        Group {
            if let date = task.dueDate {
                Text(date, format: .dateTime.day().month(.abbreviated).year())
            } else {
                Text(task.dueDateString)
            }
        }
        .foregroundStyle(isOverdue ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
    }

    /// Today as zero-padded `YYYY-MM-DD`, comparable to task due strings.
    private static func todayString(now: Date = .now) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
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
}
