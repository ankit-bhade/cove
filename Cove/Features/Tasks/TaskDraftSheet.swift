import SwiftUI

/// Confirmation sheet for a quick-added task: shows how the sentence was
/// interpreted and lets the user adjust the title, date, time, and
/// recurrence before the Markdown line is written. Editing the sentence
/// re-interprets everything; editing the fields below tweaks the current
/// draft directly.
struct TaskDraftSheet: View {
    @State var sentence: String
    @State var draft: TaskDraft
    /// The list this task is bound for, when it came from the Lists screen.
    /// Its items may be undated, so the date becomes a toggle and the sheet
    /// says where the task is going.
    var listName: String?
    let onConfirm: (TaskDraft) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var didEditDetails = false

    private var allowsUndated: Bool { listName != nil }

    /// The sheet is the place a blocking diagnostic gets resolved, so once
    /// the details have been touched even an unwritable sentence can be
    /// added — the fields, not the sentence, are what gets saved by then.
    /// Advisory diagnostics never gate the button here either.
    private var canAdd: Bool {
        draft.validationIssues.isEmpty
            && (didEditDetails || !parseDiagnostics.contains(where: \.blocksCapture))
    }

    private var parseDiagnostics: [QuickTaskParser.Diagnostic] {
        QuickTaskParser.parseWithDiagnostics(
            sentence,
            now: .now,
            defaultingToToday: !allowsUndated
        ).diagnostics
    }

    var body: some View {
        NavigationStack {
            Form {
                // No masthead: a sheet already announces itself in its own
                // title bar, and "Check the details" under "New Task" was a
                // second heading that pushed the fields being checked below
                // the fold on a phone.
                Section {
                    CoveRow(systemName: "quote.bubble.fill") {
                        TextField("Try “get bread 3p tmr”", text: $sentence)
                            .autocorrectionDisabled()
                            .onChange(of: sentence) { _, newValue in
                                draft =
                                    QuickTaskParser.parseWithDiagnostics(
                                        newValue, now: .now,
                                        defaultingToToday: !allowsUndated
                                    ).draft
                                didEditDetails = false
                            }
                    }
                    if let diagnostic = parseDiagnostics.first {
                        Label(
                            diagnostic.message,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(CoveTheme.alert)
                    }
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
                } footer: {
                    Text(
                        "Dates, times, and repeats at the end of the sentence are understood — e.g. “tmr”, “next fri”, “6pm”, “every sun”."
                    )
                }

                Section {
                    TaskScheduleFields(
                        draft: $draft,
                        allowsUndated: allowsUndated
                    ) {
                        didEditDetails = true
                    }
                } header: {
                    CoveSectionHeader("Details")
                }

                Section {
                    TaskNotificationNote(draft: draft)
                } footer: {
                    // Where the line lands: the removed header used to carry
                    // this, and it is the one thing about the sheet a person
                    // can't see from the fields.
                    Text(
                        listName.map { "Added to the “\($0)” list in Tasks.md." }
                            ?? "Added to Tasks.md at the top of your vault.")
                }
            }
            .disabled(isAdding)
            .coveFormStyle()
            .coveReadableWidth(680)
            .navigationTitle("New Task")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isAdding)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        addTask()
                    } label: {
                        if isAdding {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Add")
                        }
                    }
                    .disabled(!canAdd || isAdding)
                    .accessibilityLabel(isAdding ? "Adding task" : "Add task")
                }
            }
            .coveErrorAlert($errorMessage)
        }
        .interactiveDismissDisabled(isAdding)
        #if os(macOS)
            .frame(minWidth: 380, minHeight: 440)
        #endif
    }

    private func addTask() {
        guard canAdd, !isAdding else { return }
        do {
            _ = try draft.validatedMarkdownLine()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        isAdding = true
        Task {
            do {
                try await onConfirm(draft)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isAdding = false
            }
        }
    }

}
