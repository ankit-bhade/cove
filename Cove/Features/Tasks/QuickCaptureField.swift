import SwiftUI

/// The quick-entry field shared by the Tasks screen and every list: type a
/// sentence, watch Cove interpret it as you go, press return to add it
/// straight to the note.
///
/// The interpretation used to arrive as a confirmation sheet, which put a
/// modal between the user and every single capture. Showing the same
/// information live under the field answers the question the sheet existed
/// to answer — "did it understand me?" — before return is pressed, so the
/// common case costs one keystroke. The sheet is still one tap away for a
/// sentence that came out wrong, where picking a date beats rewording.
struct QuickCaptureField: View {
    let placeholder: String
    let accessibilityHint: String
    /// The list this field captures into, when it belongs to a list screen.
    /// List items may stay undated; a task bound for the Tasks screen
    /// resolves to today, since `@due` is required outside a list.
    var listName: String?
    /// Whether ⌘L focuses this field. Only the Tasks screen sets it: on iOS
    /// every tab stays alive, so a list's own field carrying the same
    /// shortcut would put two claims on one key and let the system decide
    /// which one wins. One field owns it; the rest are a click away.
    var bindsFocusShortcut = false
    let onCapture: (TaskDraft) async throws -> Void

    @State private var text = ""
    @FocusState private var isFieldFocused: Bool
    @State private var pendingDraft: PendingDraft?
    @State private var isCapturing = false
    @State private var errorMessage: String?

    /// The sentence and its interpretation, handed to the editing sheet
    /// together so the sheet always matches what the field showed.
    private struct PendingDraft: Identifiable {
        let sentence: String
        let draft: TaskDraft
        var id: String { sentence }
    }

    var body: some View {
        VStack(spacing: 0) {
            entryRow
            if let draft {
                Rectangle()
                    .fill(CoveTheme.hairline)
                    .frame(height: 1)
                preview(draft)
            }
        }
        // Inset into the masthead rather than raised out of it: the field is
        // a place to put something, so it reads as a well, not a button.
        .background(
            CoveTheme.canvas,
            in: RoundedRectangle(
                cornerRadius: CoveTheme.fieldRadius,
                style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CoveTheme.fieldRadius, style: .continuous)
                .stroke(CoveTheme.hairline, lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.15), value: draft)
        .background {
            if bindsFocusShortcut {
                Button("Capture Task") { isFieldFocused = true }
                    .keyboardShortcut("l", modifiers: .command)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .sheet(item: $pendingDraft) { pending in
            TaskDraftSheet(
                sentence: pending.sentence,
                draft: pending.draft,
                listName: listName
            ) { draft in
                try await onCapture(draft)
                if trimmedText == pending.sentence {
                    text = ""
                }
            }
        }
        .coveErrorAlert($errorMessage)
    }

    private var entryRow: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .autocorrectionDisabled()
                .onSubmit { startCapture(draft) }
                .submitLabel(.done)
                .accessibilityHint(accessibilityHint)
                .disabled(isCapturing)
            Button {
                startCapture(draft)
            } label: {
                Group {
                    if isCapturing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(CoveTheme.canvas)
                    } else {
                        // The canvas, not white: in dark mode the ember fill
                        // is the lighter of the two, so a white glyph on it
                        // would all but disappear.
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(CoveTheme.canvas)
                    }
                }
                .frame(width: 30, height: 30)
                .background(
                    canCapture
                        ? AnyShapeStyle(CoveTheme.accent)
                        : AnyShapeStyle(Color.secondary.opacity(0.35)),
                    in: Circle()
                )
                // The visible control stays compact while the outer
                // frame provides a full-size touch target.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCapture || isCapturing)
            .animation(.easeInOut(duration: 0.15), value: canCapture)
            .accessibilityLabel(isCapturing ? "Adding task" : "Add task")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
    }

    /// What the sentence currently means. Recomputed per keystroke — the
    /// parser is pure and the sentence is a few words long.
    private var draft: TaskDraft? {
        parseResult?.draft
    }

    private var parseResult: QuickTaskParser.ParseResult? {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return nil }
        return QuickTaskParser.parseWithDiagnostics(
            sentence, now: .now,
            defaultingToToday: listName == nil)
    }

    /// A sentence that was nothing but a date leaves an empty title, and an
    /// untitled task is not a task.
    private var canCapture: Bool {
        parseResult?.canCapture == true
    }

    private func preview(_ draft: TaskDraft) -> some View {
        let due = DueDescription.text(
            dueDateString: draft.dueDateString,
            dueTimeString: draft.dueTimeString,
            at: .now)
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CoveTheme.accent)
                // Pins the glyph to the title's line rather than letting it
                // drift to the middle of a two-line block.
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title.isEmpty ? placeholder : draft.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(draft.title.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                if let warning =
                    parseResult?.diagnostics.first?.message
                    ?? draft.validationIssues.first?.message
                {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(CoveTheme.alert)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The edit button takes the trailing edge, so a date and a
                // repeat rule side by side would squeeze both into wrapped
                // or truncated text. One per line, always.
                if !due.isEmpty, draft.recurrence != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        metadata(due: due, draft: draft)
                    }
                } else if !due.isEmpty || draft.recurrence != nil {
                    metadata(due: due, draft: draft)
                }
            }
            Spacer(minLength: 0)
            // The escape hatch the confirmation sheet used to be: for a
            // sentence Cove read wrong, picking the date beats rewording it.
            Button {
                let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
                pendingDraft = PendingDraft(sentence: sentence, draft: draft)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(CoveTheme.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit details before adding")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func metadata(due: String, draft: TaskDraft) -> some View {
        if !due.isEmpty {
            CoveDueLabel(text: due)
        }
        if let rule = draft.recurrence {
            CoveRecurrenceLabel(rule.displayName)
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Saves before clearing the sentence. A failed filesystem write leaves
    /// the user's input intact so they can retry instead of reconstructing it.
    private func startCapture(_ draft: TaskDraft?) {
        guard let draft,
            parseResult?.canCapture == true,
            !isCapturing
        else { return }
        let submittedText = trimmedText
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                try await onCapture(draft)
                if trimmedText == submittedText {
                    text = ""
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
