import SwiftUI

/// One task line as the Tasks and Lists screens both draw it: a checkbox
/// with a 44pt target, the text, and its schedule on the line beneath it.
/// Shared so the two screens can't drift apart — the whole point of Lists is
/// that a list task is an ordinary task kept somewhere else.
///
/// It is laid out on `CoveRow`'s grid rather than its own. This row used to
/// carry hand-tuned `listRowInsets` — a tighter leading edge, a trailing edge
/// 6pt short of every other row's, and vertical padding cut to 5pt so a
/// two-line task sat shorter than a one-line folder row — which made the
/// landing screen read as cramped the moment it was compared with the tab
/// beside it. The glyph column, the gap after it, the padding around it, and
/// the system's own row insets are now the ones a note row and a list row use,
/// so the text column lines up across all four screens.
///
/// Tapping the row opens the task's note; swiping (or the context menu)
/// deletes the line. An undated list item simply shows no due line.
struct TaskRow: View {
    let task: TaskItem
    let now: Date
    let onToggle: () -> Void
    let onDelete: () -> Void
    var isProcessing = false
    /// Whether a list item names its list under its title. True on the Tasks
    /// screen, where a dated list item sits among unlisted ones and would
    /// otherwise be indistinguishable from them; false inside a list, where
    /// the navigation title already says which list this is.
    var showsListName = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The same column `CoveIconTile` occupies, scaled the same way, so the
    /// checkbox and a folder tile put their text at the identical inset.
    @ScaledMetric(relativeTo: .body) private var column: CGFloat = CoveTheme.Space.rowGlyph

    var body: some View {
        let overdue = task.isOverdue(at: now)
        return HStack(alignment: .center, spacing: CoveTheme.Space.rowGap) {
            Button(action: onToggle) {
                Group {
                    if isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 21, weight: .medium))
                            .foregroundStyle(
                                task.isCompleted
                                    ? AnyShapeStyle(.tertiary)
                                    : AnyShapeStyle(
                                        overdue
                                            ? CoveTheme.alert
                                            : CoveTheme.accent)
                            )
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                // The glyph alone is a small target, so the hit area is the
                // 44pt minimum — but it is then laid out in the row's glyph
                // column, letting the target overflow into the padding on
                // either side rather than widening the column and pushing
                // this row's text past every other row's.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .frame(width: column, height: column)
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .accessibilityLabel(
                isProcessing
                    ? "Updating task"
                    : task.isCompleted
                        ? "Mark incomplete"
                        : task.recurrence == nil
                            ? "Mark complete"
                            : "Complete and reschedule")

            // The line travels with the note, so tapping a task opens its own
            // line rather than the top of a capture note that may hold a
            // hundred of them.
            NavigationLink(value: NoteDestination(task.fileURL, line: task.lineNumber)) {
                // The source note is deliberately not shown: tasks nearly
                // always live in the capture note, so the row read as a
                // repeated "Tasks" caption under every task.
                // A point over `CoveRowTitle`'s title-to-caption gap, which
                // puts the date the same distance under the title that
                // Reminders puts it. Zero when an undated item's row is
                // nothing but its title.
                VStack(alignment: .leading, spacing: showsMetadata ? 4 : 0) {
                    // Regular, where every other row title in the app is
                    // medium. A task row is the one row that is a sentence
                    // with a second line under it rather than a label with a
                    // tag: at medium the title had enough ink that the date
                    // read as attached to it, and the pair clumped into a
                    // block no matter what the gap was set to. Lightening the
                    // title is what separates them — the same pairing
                    // Reminders uses, and the reason its rows breathe.
                    Text(task.text)
                        .font(.body)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    metadata(overdue: overdue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Pinned to the text column for the same reason `CoveRow` pins
            // it there: left to itself SwiftUI derives the inset from
            // whichever nested label it selects, and recurring metadata can
            // push that inferred edge as far right as the repeat label.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .padding(.vertical, CoveTheme.Space.rowPadding)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Task", systemImage: "trash")
            }
        }
    }

    /// The list to name under the title, or nil when there is nothing to
    /// name or the screen is already naming it.
    private var shownListName: String? {
        showsListName ? task.listName : nil
    }

    private var showsMetadata: Bool {
        task.hasDueDate || shownListName != nil
    }

    @ViewBuilder
    private func metadata(overdue: Bool) -> some View {
        if !showsMetadata {
            // Nothing to say: an undated item's row is just its text.
            EmptyView()
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                metadataParts(overdue: overdue)
            }
        } else {
            // One line while it fits, stacked when it doesn't — a date, how
            // often it comes back, and where it was filed are one statement
            // about the task, not three captions.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: CoveTheme.Space.tight) {
                    metadataParts(overdue: overdue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    metadataParts(overdue: overdue)
                }
            }
        }
    }

    @ViewBuilder
    private func metadataParts(overdue: Bool) -> some View {
        if task.hasDueDate {
            dueLabel(overdue: overdue)
            if let rule = task.recurrence {
                recurrenceLabel(rule)
            }
        }
        if let listName = shownListName {
            CoveListLabel(listName)
        }
    }

    private func recurrenceLabel(_ rule: RecurrenceRule) -> some View {
        CoveRecurrenceLabel(rule.displayName)
    }

    private func dueLabel(overdue: Bool) -> some View {
        CoveDueLabel(
            text: task.relativeDueDescription(at: now),
            isOverdue: overdue,
            tint: dueTint(overdue: overdue))
    }

    /// Lateness is the only state a due line raises its voice for.
    ///
    /// Today used to take the accent, which meant that on the landing screen —
    /// where nearly everything is due today or overdue — almost every row
    /// carried a saturated second line. A subtitle at the title's own strength
    /// stops reading as a subtitle: the pair clumps, and a list where every
    /// date is coloured says nothing about which one to read first. It was
    /// also redundant twice over, since a row saying "Today" sits under a
    /// header saying TODAY, and its checkbox is already ember.
    ///
    /// A completed task's line goes quiet with the rest of its row for the
    /// same reason it always did: finishing something should settle a row
    /// rather than light it up.
    private func dueTint(overdue: Bool) -> Color {
        overdue && !task.isCompleted ? CoveTheme.alert : .secondary
    }
}
