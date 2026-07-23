import Foundation

/// Pure display logic for the Tasks screen: how a task's due date reads in
/// plain language, and which section it belongs to. Kept out of the view so
/// it can be unit-tested against a fixed `now`.

extension TaskItem {
    /// Overdue when the due day is past, or when today's due moment is past.
    /// A date-only task is never overdue on its own due day.
    /// An undated list item is never overdue — it has no moment to be late
    /// for.
    func isOverdue(at now: Date,
                   calendar: Calendar = TaskCalendar.gregorian()) -> Bool {
        let calendar = TaskCalendar.gregorian(timeZone: calendar.timeZone)
        guard !isCompleted, let dueDateString else { return false }
        if let moment = dueDateTime(in: calendar) {
            return moment < now
        }
        return dueDateString < QuickTaskParser.ymdString(from: now, calendar: calendar)
    }

    func isDue(onSameDayAs now: Date,
               calendar: Calendar = TaskCalendar.gregorian()) -> Bool {
        dueDateString == QuickTaskParser.ymdString(from: now, calendar: calendar)
    }

    /// Whole days from `now`'s day to the due day: 0 today, 1 tomorrow,
    /// negative in the past. Nil when the stored date can't be parsed.
    func daysFromToday(at now: Date,
                       calendar: Calendar = TaskCalendar.gregorian()) -> Int? {
        let calendar = TaskCalendar.gregorian(timeZone: calendar.timeZone)
        guard let dueDate = dueDate(in: calendar) else { return nil }
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: dueDate)).day
    }

    /// "Today, 3:00 PM", "Tomorrow", "Friday", "Jul 24", "Jul 24, 2027".
    /// Relative wording for the days a reader thinks in, absolute beyond
    /// that, and the year only when it isn't the current one. Empty for an
    /// undated list item, whose row shows no due label at all.
    func relativeDueDescription(at now: Date,
                                calendar: Calendar = TaskCalendar.gregorian()) -> String {
        DueDescription.text(dueDateString: dueDateString,
                            dueTimeString: dueTimeString,
                            at: now,
                            calendar: calendar)
    }
}

/// Plain-language wording for a due date and optional time, over the raw
/// `YYYY-MM-DD` / `HH:MM` strings rather than a `TaskItem`. Shared so a task
/// reads identically in the quick-capture preview and in the row it becomes.
enum DueDescription {
    /// "Today, 3:00 PM", "Tomorrow", "Friday", "Jul 24", "Jul 24, 2027".
    /// Empty when there is no date, which is what an undated list item shows.
    static func text(dueDateString: String?,
                     dueTimeString: String?,
                     at now: Date,
                     calendar: Calendar = TaskCalendar.gregorian()) -> String {
        let calendar = TaskCalendar.gregorian(timeZone: calendar.timeZone)
        guard let dueDateString,
              let dueDate = date(from: dueDateString, calendar: calendar)
        else { return dueDateString ?? "" }
        let day = dayDescription(dueDate, at: now, calendar: calendar)
        guard let moment = moment(on: dueDate, at: dueTimeString, calendar: calendar)
        else { return day }
        return "\(day), \(formatted(moment, template: "j:mm", calendar: calendar))"
    }

    private static func date(from dueDateString: String, calendar: Calendar) -> Date? {
        let parts = dueDateString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0],
                                                  month: parts[1],
                                                  day: parts[2]))
    }

    private static func moment(on dueDate: Date,
                               at dueTimeString: String?,
                               calendar: Calendar) -> Date? {
        guard let dueTimeString else { return nil }
        let parts = dueTimeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1],
                             second: 0, of: dueDate)
    }

    private static func dayDescription(_ dueDate: Date,
                                       at now: Date,
                                       calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: dueDate)).day
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case let days? where days > 1 && days < 7:
            // Inside the coming week a weekday name is easier to place than
            // a numeric date.
            return formatted(dueDate, template: "EEEE", calendar: calendar)
        default:
            let sameYear = calendar.component(.year, from: dueDate)
                == calendar.component(.year, from: now)
            return formatted(dueDate,
                             template: sameYear ? "MMM d" : "MMM d y",
                             calendar: calendar)
        }
    }

    private static func formatted(_ date: Date,
                                  template: String,
                                  calendar: Calendar) -> String {
        TemplateDateFormatters.shared.string(from: date,
                                             template: template,
                                             calendar: calendar)
    }
}

/// Locale-aware template formatters, built once per distinct template, locale,
/// time zone, and calendar, then reused.
///
/// `DateFormatter` is expensive to construct and these sit on hot paths: a
/// visible task row formats its due date on every render, including the
/// minute tick that keeps the Overdue/Today groups honest. Keying on the
/// locale identifier is what keeps the reuse safe —
/// `setLocalizedDateFormatFromTemplate` resolves the template once, so a
/// changed locale has to miss the cache rather than keep the old wording.
final class TemplateDateFormatters: @unchecked Sendable {
    static let shared = TemplateDateFormatters()

    private struct Key: Hashable {
        let template: String
        let locale: String
        let timeZone: String
        let calendar: Calendar.Identifier
    }

    private let lock = NSLock()
    private var formatters: [Key: DateFormatter] = [:]

    func string(from date: Date, template: String, calendar: Calendar) -> String {
        let key = Key(template: template,
                      locale: Locale.autoupdatingCurrent.identifier,
                      timeZone: calendar.timeZone.identifier,
                      calendar: calendar.identifier)
        lock.lock()
        defer { lock.unlock() }
        if let formatter = formatters[key] {
            return formatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = formatter
        return formatter.string(from: date)
    }
}

/// One section of the open-tasks list. Grouping only partitions an
/// already-sorted list, so the spec's due-date ordering is preserved and
/// the sections themselves run chronologically.
struct TaskGroup: Identifiable {
    enum Kind: Int, CaseIterable {
        case overdue, today, tomorrow, upcoming
    }

    let kind: Kind
    let tasks: [TaskItem]

    var id: Int { kind.rawValue }
    var isOverdue: Bool { kind == .overdue }

    /// The section's name on its own: the header sets the count beside it in
    /// its own weight rather than running the two into one string.
    var name: String {
        switch kind {
        case .overdue: "Overdue"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .upcoming: "Upcoming"
        }
    }

    /// Partitions sorted incomplete tasks into the non-empty sections.
    static func grouping(_ tasks: [TaskItem],
                         now: Date,
                         calendar: Calendar = TaskCalendar.gregorian()) -> [TaskGroup] {
        let calendar = TaskCalendar.gregorian(timeZone: calendar.timeZone)
        var buckets: [Kind: [TaskItem]] = [:]
        for task in tasks {
            buckets[kind(for: task, now: now, calendar: calendar), default: []].append(task)
        }
        return Kind.allCases.compactMap { kind in
            guard let tasks = buckets[kind], !tasks.isEmpty else { return nil }
            return TaskGroup(kind: kind, tasks: tasks)
        }
    }

    static func kind(for task: TaskItem, now: Date,
                     calendar: Calendar = TaskCalendar.gregorian()) -> Kind {
        let calendar = TaskCalendar.gregorian(timeZone: calendar.timeZone)
        if task.isOverdue(at: now, calendar: calendar) { return .overdue }
        switch task.daysFromToday(at: now, calendar: calendar) {
        case 0: return .today
        case 1: return .tomorrow
        default: return .upcoming
        }
    }
}
