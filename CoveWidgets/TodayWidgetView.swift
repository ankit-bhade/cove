import SwiftUI
import WidgetKit

/// The Today widget's body: a header, the day's tasks, and the "all clear"
/// state when nothing is left. Small and medium share the row model but lay it
/// out differently — small stacks the time under the title, medium puts it on
/// the trailing edge where there is room for full-width titles.
struct TodayWidgetView: View {
    let entry: TodayEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WidgetPalette { .resolved(for: colorScheme) }
    private var isSmall: Bool { family != .systemMedium }
    /// The empty state is about work, not history: once nothing is open the
    /// widget reads "All clear" even if checked-off rows are still around.
    private var openTasks: [SnapshotTask] { entry.snapshot.openTasks }
    private var visibleTasks: [SnapshotTask] {
        Array(entry.snapshot.tasks.prefix(isSmall ? 3 : 4))
    }

    var body: some View {
        // The header is unconditional: the day and date are the widget's
        // anchor on the Home Screen, and an empty day is still a day. Only
        // what sits under it changes.
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 9)
            if openTasks.isEmpty {
                emptyState
            } else {
                VStack(spacing: isSmall ? 6 : 7) {
                    ForEach(visibleTasks) { task in
                        row(for: task)
                    }
                }
                // Rows hang from the header rather than centering in the
                // leftover space: a single task belongs directly under
                // "Today", where the next one added will sit below it,
                // instead of drifting to the middle of the widget.
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The design's own insets rather than WidgetKit's default content
        // margins, which are wider and would cost the small family a row.
        // Paired with `.contentMarginsDisabled()` on the configuration.
        .padding(.vertical, 14)
        .padding(.horizontal, isSmall ? 15 : 14)
        .containerBackground(palette.background, for: .widget)
        .widgetURL(URL(string: "cove://tasks"))
    }

    // MARK: - Header

    private var headerSize: CGFloat { isSmall ? 13 : 15 }

    private var header: some View {
        HStack(spacing: isSmall ? 6 : 7) {
            Image(systemName: "sun.max")
                .font(.system(size: isSmall ? 15 : 16, weight: .medium))
                .foregroundStyle(palette.accent)
            // "Today" and the date are one phrase, so they share a size and a
            // baseline. At 11pt in a center-aligned row the date read as a
            // caption sitting on its own line rather than part of the title;
            // weight and color still separate them.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Today")
                    .font(.system(size: headerSize, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                if !isSmall {
                    Text(entry.date.formatted(.dateTime.weekday(.abbreviated))
                        + " · "
                        + entry.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: headerSize))
                        .foregroundStyle(palette.secondaryText)
                }
            }
            Spacer(minLength: 4)
            countPill
        }
    }

    private var countPill: some View {
        Text(isSmall ? "\(openTasks.count)" : "\(openTasks.count) left")
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(palette.accent)
            .padding(.vertical, isSmall ? 2 : 3)
            .padding(.horizontal, isSmall ? 7 : 8)
            .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 8,
                                                                 style: .continuous))
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for task: SnapshotTask) -> some View {
        HStack(spacing: 9) {
            checkbox(for: task)
            if isSmall {
                VStack(alignment: .leading, spacing: 1) {
                    title(for: task)
                    if task.dueTimeString != nil {
                        HStack(spacing: 3) {
                            Image(systemName: isOverdue(task)
                                  ? "exclamationmark.circle.fill" : "clock")
                                .font(.system(size: 11, weight: .semibold))
                            timeText(for: task)
                        }
                        .foregroundStyle(dueColor(for: task))
                    }
                }
            } else {
                title(for: task)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if isOverdue(task) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.overdue)
                    }
                    if task.dueTimeString != nil {
                        timeText(for: task)
                            .foregroundStyle(dueColor(for: task))
                    }
                }
            }
        }
        // Without a full-width row the HStack shrinks to its content and
        // centers, which leaves the checkboxes in a ragged column.
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func title(for task: SnapshotTask) -> some View {
        Text(task.text)
            .font(.system(size: isSmall ? 12.5 : 13.5, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .strikethrough(task.isCompleted)
            .foregroundStyle(task.isCompleted ? palette.secondaryText : palette.primaryText)
    }

    private func timeText(for task: SnapshotTask) -> some View {
        Text(task.timeOfDayDescription)
            .font(.system(size: isSmall ? 10.5 : 11, weight: .semibold))
            .monospacedDigit()
    }

    /// The checkbox sits in a 44×44pt hit area — the app's `TaskRow` target —
    /// while the surrounding layout only reserves the glyph, so the generous
    /// target doesn't push the rows apart.
    private func checkbox(for task: SnapshotTask) -> some View {
        Button(intent: ToggleTaskIntent(taskID: task.id)) {
            checkboxGlyph(isCompleted: task.isCompleted)
                .font(.system(size: 21, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 21, height: 21)
        .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Complete")
    }

    /// A checked box is the accent disc with the mark punched out of it in the
    /// widget's own background color, so it stays legible at 21pt.
    @ViewBuilder
    private func checkboxGlyph(isCompleted: Bool) -> some View {
        if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(palette.checkMark, palette.accent)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(palette.accent)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(palette.accent)
            Text("All clear")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.primaryText)
            Text("Nothing due today")
                .font(.system(size: 11.5))
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: - Due state

    private func isOverdue(_ task: SnapshotTask) -> Bool {
        task.taskItem.isOverdue(at: entry.date)
    }

    /// A task due earlier today reads red; anything still ahead reads accent,
    /// matching how the app's own task rows tint a due date.
    private func dueColor(for task: SnapshotTask) -> Color {
        isOverdue(task) ? palette.overdue : palette.accent
    }
}

extension SnapshotTask {
    /// Just the time of day ("8:30 AM"). The widget's rows are all due today,
    /// so the day half of `DueDescription` would say "Today" on every one.
    var timeOfDayDescription: String {
        guard let components = taskItem.timeComponents,
              let moment = Calendar.current.date(bySettingHour: components.hour,
                                                 minute: components.minute,
                                                 second: 0,
                                                 of: Date())
        else { return "" }
        return moment.formatted(.dateTime.hour().minute())
    }
}

#Preview("Small", as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
    TodayEntry(date: .now, snapshot: TodaySnapshot(
        dayString: QuickTaskParser.ymdString(from: .now),
        generatedAt: .now, tasks: []))
}

#Preview("Medium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
}
