import SwiftUI

/// One task line as the Tasks and Lists screens both draw it: a checkbox
/// with a 44pt target, the text, and its schedule as a tinted capsule.
/// Shared so the two screens can't drift apart — the whole point of Lists is
/// that a list task is an ordinary task kept somewhere else.
///
/// Tapping the row opens the task's note; swiping (or the context menu)
/// deletes the line. An undated list item simply shows no due capsule.
struct TaskRow: View {
    let task: TaskItem
    let now: Date
    let onToggle: () -> Void
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let overdue = task.isOverdue(at: now)
        return HStack(alignment: .center, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(task.isCompleted ? Color.secondary : CoveTheme.teal)
                    // The glyph alone is a small target; padding brings the
                    // hit area up to the 44pt minimum without moving it.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: -8)
            .padding(.trailing, -8)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete"
                                : task.recurrence == nil ? "Mark complete"
                                : "Complete and reschedule")

            NavigationLink(value: task.fileURL) {
                // The source note is deliberately not shown: tasks nearly
                // always live in the capture note, so the row read as a
                // repeated "Tasks" caption under every task.
                VStack(alignment: .leading, spacing: task.hasDueDate ? 4 : 0) {
                    Text(task.text)
                        .font(.body.weight(.medium))
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    metadata(overdue: overdue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .listRowInsets(CoveTheme.taskRowInsets(hasMetadata: task.hasDueDate))
        // SwiftUI otherwise derives the separator inset from whichever
        // nested label it happens to select. Recurring metadata can make
        // that inferred edge jump as far right as the repeat label.
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
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
        Label(rule.displayName, systemImage: "repeat")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func dueLabel(overdue: Bool) -> some View {
        let tint: Color = overdue ? .red
            : task.isDue(onSameDayAs: now) ? CoveTheme.teal
            : .secondary
        return HStack(spacing: 5) {
            Image(systemName: overdue ? "exclamationmark.circle.fill"
                  : task.dueTimeString != nil ? "clock" : "calendar")
            Text(task.relativeDueDescription(at: now))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10), in: Capsule())
    }
}
