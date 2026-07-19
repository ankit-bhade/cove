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
    let onCapture: (TaskDraft) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var text = ""
    @State private var pendingDraft: PendingDraft?

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
                Divider().overlay(CoveTheme.border(for: colorScheme))
                preview(draft)
            }
        }
        .background(CoveTheme.canvas(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(CoveTheme.border(for: colorScheme), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.15), value: draft)
        .sheet(item: $pendingDraft) { pending in
            TaskDraftSheet(sentence: pending.sentence,
                           draft: pending.draft,
                           listName: listName) { draft in
                capture(draft)
            }
        }
    }

    private var entryRow: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onSubmit { capture(draft) }
                .submitLabel(.done)
                .accessibilityHint(accessibilityHint)
            Button { capture(draft) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(canCapture ? AnyShapeStyle(CoveTheme.brandGradient)
                                : AnyShapeStyle(Color.secondary.opacity(0.4)),
                                in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canCapture)
            .animation(.easeInOut(duration: 0.15), value: canCapture)
            .accessibilityLabel("Add task")
        }
        .padding(9)
    }

    /// What the sentence currently means. Recomputed per keystroke — the
    /// parser is pure and the sentence is a few words long.
    private var draft: TaskDraft? {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return nil }
        return QuickTaskParser.parse(sentence, now: .now,
                                     defaultingToToday: listName == nil)
    }

    /// A sentence that was nothing but a date leaves an empty title, and an
    /// untitled task is not a task.
    private var canCapture: Bool {
        guard let draft else { return false }
        return !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func preview(_ draft: TaskDraft) -> some View {
        let due = DueDescription.text(dueDateString: draft.dueDateString,
                                      dueTimeString: draft.dueTimeString,
                                      at: .now)
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CoveTheme.teal)
                // Pins the glyph to the title's line rather than letting it
                // drift to the middle of a two-line block.
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title.isEmpty ? placeholder : draft.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(draft.title.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
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
                    .foregroundStyle(CoveTheme.teal)
                    .frame(width: 32, height: 32)
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
            dueCapsule(due, hasTime: draft.dueTimeString != nil)
        }
        if let rule = draft.recurrence {
            Label(rule.displayName, systemImage: "repeat")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func dueCapsule(_ due: String, hasTime: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: hasTime ? "clock" : "calendar")
            Text(due)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(CoveTheme.teal)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(CoveTheme.teal.opacity(0.10), in: Capsule())
    }

    /// Hands the draft up and clears the field. A draft with an empty title
    /// (a sentence that was nothing but a date) is not a task.
    private func capture(_ draft: TaskDraft?) {
        guard let draft,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        text = ""
        onCapture(draft)
    }
}
