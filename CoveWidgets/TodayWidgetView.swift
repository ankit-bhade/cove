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
    private var isAvailable: Bool { entry.snapshot.availability == .available }
    /// The empty state is about work, not history: once nothing is open the
    /// widget reads "All clear" even if checked-off rows are still around.
    private var openTasks: [SnapshotTask] { entry.snapshot.openTasks }
    private var actionableTasks: [SnapshotTask] {
        entry.snapshot.tasks.filter {
            !$0.isCompleted || $0.pendingCompletion != nil
        }
    }
    private var visibleTasks: [SnapshotTask] {
        Array(actionableTasks.prefix(isSmall ? 2 : 3))
    }

    var body: some View {
        // The header is unconditional: the day and date are the widget's
        // anchor on the Home Screen, and an empty day is still a day. Only
        // what sits under it changes.
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 9)
            if !isAvailable {
                unavailableState
            } else if actionableTasks.isEmpty {
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

    /// The date is the header. A widget that only ever shows today's tasks
    /// doesn't need to say "Today" — the word spent the title on something the
    /// reader already knows, and left the one fact worth glancing at as a
    /// caption beside it.
    private var header: some View {
        HStack(spacing: isSmall ? 7 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(
                    entry.date.formatted(
                        .dateTime.weekday(isSmall ? .abbreviated : .wide))
                )
                .font(
                    .system(
                        size: headerSize + 1, weight: .semibold,
                        design: .serif)
                )
                .foregroundStyle(palette.primaryText)
                Text(entry.date.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: headerSize))
                    .foregroundStyle(palette.secondaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            countPill
        }
    }

    private var countPill: some View {
        Group {
            if isAvailable {
                Text(
                    isSmall
                        ? "\(entry.snapshot.totalOpenTaskCount)"
                        : "\(entry.snapshot.totalOpenTaskCount) left"
                )
                .monospacedDigit()
            } else {
                Image(systemName: "exclamationmark")
                    .accessibilityLabel("Needs attention")
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(palette.accent)
        .padding(.vertical, isSmall ? 2 : 3)
        .padding(.horizontal, isSmall ? 7 : 8)
        .background(
            palette.accentSoft,
            in: RoundedRectangle(
                cornerRadius: 8,
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
                            Image(
                                systemName: isOverdue(task)
                                    ? "exclamationmark.circle.fill" : "clock"
                            )
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
        .frame(minHeight: 32)
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

    /// The checkbox's full hit area is reserved by the row. Widget rows are
    /// necessarily denser than the app's 44pt controls, but hit regions must
    /// never overflow into an adjacent App Intent button.
    private func checkbox(for task: SnapshotTask) -> some View {
        Button(
            intent: ToggleTaskIntent(
                taskID: task.id,
                desiredCompletion: !task.isCompleted)
        ) {
            checkboxGlyph(for: task)
                .font(.system(size: 20, weight: .regular))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The layout reserves exactly the button's hit region; it cannot
        // overlap the next row and dispatch the wrong App Intent.
        .frame(width: 32, height: 32)
        .disabled(task.pendingCompletion != nil)
        .accessibilityLabel(
            task.pendingCompletion != nil
                ? "Change pending"
                : (task.isCompleted ? "Mark incomplete" : "Complete"))
    }

    /// An empty box is drawn in the soft accent, not the full one. Four rings
    /// at full saturation running down a small widget shouted over the task
    /// text they belong to — the row's job is to be read, and the box's is to
    /// be findable. A checked box is a filled disc in the same soft tone with
    /// the mark punched out of it in the widget's own background color, so
    /// finishing something quiets the row rather than lighting it up.
    @ViewBuilder
    private func checkboxGlyph(for task: SnapshotTask) -> some View {
        if task.pendingCompletion != nil {
            Image(systemName: "hourglass.circle")
                .foregroundStyle(palette.accent)
        } else if task.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(palette.checkMark, palette.checkboxRest)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(palette.checkboxRest)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(palette.accent)
            Text("All clear")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(palette.primaryText)
            Text("Nothing due today")
                .font(.system(size: 11.5))
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }

    private var unavailableState: some View {
        VStack(spacing: 7) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(palette.accent)
            Text(unavailableTitle)
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(palette.primaryText)
            Text("Open Cove to refresh")
                .font(.system(size: 11.5))
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private var unavailableTitle: String {
        switch entry.snapshot.availability {
        case .vaultUnavailable:
            "Reconnect your vault"
        case .sharedContainerUnavailable, .unreadable:
            "Widget unavailable"
        case .notPublished:
            "Finish widget setup"
        case .stale:
            "Refresh Cove"
        case .available:
            ""
        }
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
            let moment = TaskCalendar.gregorian().date(
                bySettingHour: components.hour,
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
    TodayEntry(
        date: .now,
        snapshot: TodaySnapshot(
            dayString: QuickTaskParser.ymdString(from: .now),
            generatedAt: .now, tasks: []))
}

#Preview("Medium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
}
