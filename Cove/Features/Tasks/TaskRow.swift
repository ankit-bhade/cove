import SwiftUI

/// One task line as the Tasks and Lists screens both draw it: a checkbox
/// with a 44pt target, the text, and its schedule as a tinted capsule.
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
/// deletes the line. An undated list item simply shows no due capsule.
struct TaskRow: View {
    let task: TaskItem
    let now: Date
    let onToggle: () -> Void
    let onDelete: () -> Void
    var isProcessing = false

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

            NavigationLink(value: task.fileURL) {
                // The source note is deliberately not shown: tasks nearly
                // always live in the capture note, so the row read as a
                // repeated "Tasks" caption under every task.
                // The title-to-caption gap `CoveRowTitle` uses, and zero when
                // an undated item's row is nothing but its title.
                VStack(alignment: .leading, spacing: task.hasDueDate ? 3 : 0) {
                    Text(task.text)
                        .font(.body.weight(.medium))
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

    @ViewBuilder
    private func metadata(overdue: Bool) -> some View {
        if !task.hasDueDate {
            // Nothing to say: an undated item's row is just its text.
            EmptyView()
        } else if let rule = task.recurrence, !dynamicTypeSize.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    dueLabel(overdue: overdue)
                    recurrenceLabel(rule)
                }
                VStack(alignment: .leading, spacing: 3) {
                    dueLabel(overdue: overdue)
                    recurrenceLabel(rule)
                }
            }
        } else if let rule = task.recurrence {
            VStack(alignment: .leading, spacing: 3) {
                dueLabel(overdue: overdue)
                recurrenceLabel(rule)
            }
        } else {
            dueLabel(overdue: overdue)
        }
    }

    private func recurrenceLabel(_ rule: RecurrenceRule) -> some View {
        CoveRecurrenceLabel(rule.displayName)
    }

    private func dueLabel(overdue: Bool) -> some View {
        CoveDueCapsule(
            text: task.relativeDueDescription(at: now),
            hasTime: task.dueTimeString != nil,
            isOverdue: overdue,
            tint: dueTint(overdue: overdue))
    }

    /// A completed task's capsule goes quiet with the rest of its row.
    /// Struck-through grey text under a full-strength ember capsule left the
    /// loudest thing in the row attached to the one task that no longer wants
    /// attention — finishing something should quiet a row, not light it up.
    private func dueTint(overdue: Bool) -> Color {
        if task.isCompleted { return .secondary }
        if overdue { return CoveTheme.alert }
        return task.isDue(onSameDayAs: now) ? CoveTheme.accent : .secondary
    }
}
