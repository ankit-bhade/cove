import SwiftUI
import WidgetKit

/// One rendering of the widget: the snapshot to draw and the moment to draw it
/// as of. Overdue tinting and the empty state both depend on `date`, so the
/// timeline carries several entries rather than one.
struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot
}

/// Feeds the widget from the App Group snapshot the app publishes on every
/// index rebuild. The provider never touches the vault: it has no security
/// scope, and re-reading every note on a widget refresh would be far too
/// expensive besides.
struct TodayProvider: TimelineProvider {
    private let store = WidgetSnapshotStore()

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let now = Date()
        // The gallery has no vault to read, so it previews the sample day
        // rather than an empty widget that looks broken.
        let snapshot = context.isPreview ? .placeholder : store.readSnapshot().valid(at: now)
        completion(TodayEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let snapshot = store.readSnapshot().valid(at: now)
        completion(Timeline(entries: Self.entries(for: snapshot, from: now),
                            policy: .after(Self.nextRefresh(after: now))))
    }

    /// An entry now, one at each future due moment (so a task turns red the
    /// minute it slips), and one at midnight (so the day rolls over even if
    /// the app never runs). Capped well under WidgetKit's per-day budget.
    static func entries(for snapshot: TodaySnapshot,
                        from now: Date,
                        calendar: Calendar = TaskCalendar.gregorian()) -> [TodayEntry] {
        let calendar = TaskCalendar.gregorian(timeZone: calendar.timeZone)
        let dueMoments = snapshot.openTasks
            .compactMap { $0.taskItem.dueDateTime(in: calendar) }
            .filter { $0 > now }
        let midnight = TaskCalendar.nextMidnight(after: now, calendar: calendar)
        let moments = Array(Set([now] + dueMoments))
            .filter { $0 >= now && $0 < midnight }
            .sorted()
            .prefix(23)
        let currentDayEntries = moments.map {
            TodayEntry(date: $0, snapshot: snapshot)
        }
        // Reserve the final budget slot for rollover even on a day with many
        // timed tasks; otherwise prefixing the combined list could drop it.
        return currentDayEntries + [TodayEntry(date: midnight, snapshot: .empty)]
    }

    /// Tomorrow's first refresh once the day is spent, otherwise a periodic
    /// nudge so a snapshot written while the widget slept is picked up.
    static func nextRefresh(after now: Date,
                            calendar: Calendar = TaskCalendar.gregorian()) -> Date {
        let calendar = TaskCalendar.gregorian(timeZone: calendar.timeZone)
        let midnight = TaskCalendar.nextMidnight(after: now, calendar: calendar)
        return min(now.addingTimeInterval(30 * 60), midnight)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CoveSharedContainer.todayWidgetKind,
                            provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("The tasks due today, with a checkbox to tick one off.")
        .supportedFamilies([.systemSmall, .systemMedium])
        // The view applies the design's own insets instead.
        .contentMarginsDisabled()
    }
}

extension TodaySnapshot {
    /// The widget gallery's sample day — the design's own content, so the
    /// picker shows the widget doing its job rather than sitting empty.
    static var placeholder: TodaySnapshot {
        let day = QuickTaskParser.ymdString(from: Date())
        let sample: [(String, String?)] = [("Reply to Maya", "08:30"),
                                           ("Team stand-up", "10:30"),
                                           ("Pharmacy pickup", "15:00"),
                                           ("Water the plants", nil)]
        return TodaySnapshot(
            dayString: day,
            generatedAt: Date(),
            // Distinct line numbers: the row identity is path + line, and a
            // repeated id would collapse the rows in `ForEach`.
            tasks: sample.enumerated().map { line, sample in
                SnapshotTask(filePath: "/Tasks.md",
                             lineNumber: line,
                             text: sample.0,
                             dueDateString: day,
                             dueTimeString: sample.1,
                             recurrenceTag: nil,
                             isCompleted: false)
            })
    }
}
