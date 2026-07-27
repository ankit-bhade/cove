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
    private var actionableTasks: [SnapshotTask] {
        entry.snapshot.tasks.filter {
            !$0.isCompleted || $0.pendingCompletion != nil
        }
    }

    var body: some View {
        // The header is unconditional: the day and date are the widget's
        // anchor on the Home Screen, and an empty day is still a day. Only
        // what sits under it changes.
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 7)
            if !isAvailable {
                unavailableState
            } else if actionableTasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The design's own insets rather than WidgetKit's default content
        // margins, which are wider and would cost the small family a row.
        // Paired with `.contentMarginsDisabled()` on the configuration.
        .padding(.vertical, 13)
        .padding(.horizontal, isSmall ? 15 : 14)
        .containerBackground(palette.background, for: .widget)
        .widgetURL(URL(string: "cove://tasks"))
    }

    // MARK: - Task list

    /// How many rows fit is a property of the device, not of the family: a
    /// small widget is 148pt tall on one iPhone and 170pt on another, and a
    /// fixed count either overflows the short one or — as it did — leaves the
    /// tall one two thirds empty with tasks it had in hand and did not draw.
    /// So the candidates are offered longest first and the layout takes the
    /// tallest that fits the space actually left under the header.
    ///
    /// The candidates are spelled out rather than generated: `ViewThatFits`
    /// reads its content as a list of alternatives, and a `ForEach` inside it
    /// is one child, not four.
    private var taskList: some View {
        ViewThatFits(in: .vertical) {
            rows(limitedTo: 4)
            rows(limitedTo: 3)
            rows(limitedTo: 2)
            rows(limitedTo: 1)
        }
        // Rows hang from the header rather than centering in the leftover
        // space: a single task belongs directly under the date, where the
        // next one added will sit below it, instead of drifting to the
        // middle of the widget.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func rows(limitedTo count: Int) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(actionableTasks.prefix(count)) { task in
                row(for: task)
            }
        }
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

    /// A zero carries nothing the empty state under it doesn't already say,
    /// and a badge is a shape that asks to be read — so on a clear day there
    /// is nothing in the corner at all.
    @ViewBuilder
    private var countPill: some View {
        if !isAvailable {
            pillShape {
                Image(systemName: "exclamationmark")
                    .accessibilityLabel("Needs attention")
            }
        } else if entry.snapshot.totalOpenTaskCount > 0 {
            pillShape {
                Text(
                    isSmall
                        ? "\(entry.snapshot.totalOpenTaskCount)"
                        : "\(entry.snapshot.totalOpenTaskCount) left"
                )
                .monospacedDigit()
            }
        }
    }

    private func pillShape(@ViewBuilder _ content: () -> some View) -> some View {
        content()
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

    private var rowHeight: CGFloat { 28 }
    private var rowSpacing: CGFloat { 4 }
    /// The column the checkbox is laid out in — as wide as the ring itself, so
    /// the ring's leading edge lines up with the date above it. The control's
    /// larger hit area overflows this column into the widget's own padding.
    private var glyphSize: CGFloat { 18 }
    private var hitWidth: CGFloat { 30 }

    @ViewBuilder
    private func row(for task: SnapshotTask) -> some View {
        HStack(spacing: 8) {
            checkbox(for: task)
            if isSmall {
                VStack(alignment: .leading, spacing: 1) {
                    title(for: task)
                    if task.dueTimeString != nil {
                        timeText(for: task)
                            .foregroundStyle(dueColor(for: task))
                    }
                }
            } else {
                title(for: task)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if task.dueTimeString != nil {
                    timeText(for: task)
                        .foregroundStyle(dueColor(for: task))
                }
            }
        }
        // Without a full-width row the HStack shrinks to its content and
        // centers, which leaves the checkboxes in a ragged column.
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: rowHeight)
        .accessibilityElement(children: .combine)
    }

    private func title(for task: SnapshotTask) -> some View {
        Text(task.text)
            .font(.system(size: isSmall ? 13 : 13.5))
            .lineLimit(1)
            .truncationMode(.tail)
            .strikethrough(task.isCompleted)
            .foregroundStyle(task.isCompleted ? palette.secondaryText : palette.primaryText)
    }

    /// The time is a subtitle, not a badge — no clock beside it and no
    /// exclamation mark when it has passed. The app made the same call for its
    /// own due lines: the glyph only restated the text next to it, and one on
    /// every row was the loudest thing in a list whose job is to be scanned.
    /// Lateness is carried by the tint, exactly as it is in the app.
    private func timeText(for task: SnapshotTask) -> some View {
        Text(task.timeOfDayDescription)
            .font(.system(size: isSmall ? 11 : 11.5, weight: .medium))
            .monospacedDigit()
    }

    /// Widget rows are necessarily denser than the app's 44pt controls, and a
    /// hit region must never overflow *vertically* into an adjacent App Intent
    /// button — so the target is exactly a row tall. It is wider than its
    /// column, which is free: the slack falls into the widget's own padding on
    /// one side and the gap before the title on the other.
    private func checkbox(for task: SnapshotTask) -> some View {
        Button(
            intent: ToggleTaskIntent(
                taskID: task.id,
                desiredCompletion: !task.isCompleted)
        ) {
            checkboxGlyph(for: task)
                .font(.system(size: glyphSize, weight: .regular))
                .frame(width: hitWidth, height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: hitWidth, height: rowHeight)
        .frame(width: glyphSize)
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

    /// Quieter than it was. A 34pt glyph over two lines of centred text was
    /// the largest thing the widget ever drew, which put the most emphasis on
    /// the state that has the least to say.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(palette.accent)
            Text("All clear")
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .foregroundStyle(palette.primaryText)
            Text("Nothing due today")
                .font(.system(size: 11))
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
