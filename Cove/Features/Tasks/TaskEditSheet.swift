import SwiftUI

/// One existing task's details: what it says, when it is due, and how often it
/// comes back — editable without opening the Markdown behind it.
///
/// Tapping a row used to push the editor with the caret on the task's line.
/// That is the right escape hatch and it is still one item away, but it was the
/// wrong default: every other action on a row is a gesture, while moving a task
/// to next Tuesday meant retyping a `@due(...)` tag by hand. The fields here
/// are the capture sheet's own, so a date set on either screen means the same
/// thing.
struct TaskEditSheet: View {
    let task: TaskItem
    let onSave: (TaskDraft) async throws -> Void
    let onOpenInNote: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: TaskDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        task: TaskItem,
        onSave: @escaping (TaskDraft) async throws -> Void,
        onOpenInNote: @escaping () -> Void
    ) {
        self.task = task
        self.onSave = onSave
        self.onOpenInNote = onOpenInNote
        _draft = State(initialValue: TaskDraft(task))
    }

    /// A list item may go undated — "milk" is a thing to buy, not a thing due
    /// today. A task outside a list cannot: `@due` is what makes it a task
    /// anywhere else in the vault.
    private var allowsUndated: Bool { task.listName != nil }

    private var canSave: Bool {
        draft.validationIssues.isEmpty && draft != TaskDraft(task)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TaskScheduleFields(draft: $draft, allowsUndated: allowsUndated)
                    if let issue = draft.validationIssues.first {
                        Label(
                            issue.message,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(CoveTheme.alert)
                    }
                } header: {
                    CoveSectionHeader("Task")
                }

                Section {
                    TaskNotificationNote(draft: draft)
                    // Completion is not a field here. The checkbox on the row
                    // is what sets it, and it carries recurrence semantics a
                    // toggle in a form would quietly bypass.
                    Button {
                        dismiss()
                        onOpenInNote()
                    } label: {
                        CoveRow(systemName: "doc.text", tint: CoveTheme.moss) {
                            CoveRowTitle(
                                title: "Open in Note",
                                caption: noteCaption)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isSaving)
                } footer: {
                    Text(
                        task.listName.map {
                            "This task lives under “\($0)” in \(task.fileTitle).md."
                        } ?? "This task lives in \(task.fileTitle).md."
                    )
                }
            }
            .disabled(isSaving)
            .coveFormStyle()
            .coveReadableWidth(680)
            .navigationTitle("Task Details")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityLabel(isSaving ? "Saving task" : "Save task")
                }
            }
            .coveErrorAlert($errorMessage)
        }
        .interactiveDismissDisabled(isSaving)
        #if os(macOS)
            .frame(minWidth: 380, minHeight: 420)
        #endif
    }

    private var noteCaption: String {
        "\(task.fileTitle).md, line \(task.lineNumber + 1)"
    }

    /// The sheet stays open when the write is refused — an ambiguous line, or
    /// one another device changed meanwhile — because the fields are the only
    /// place the edit exists.
    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await onSave(draft)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
