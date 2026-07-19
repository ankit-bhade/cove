import Foundation

/// Pure display logic for the Tasks screen: how a task's due date reads in
/// plain language, and which section it belongs to. Kept out of the view so
/// it can be unit-tested against a fixed `now`.

extension TaskItem {
    /// Overdue when the due day is past, or when today's due moment is past.
    /// A date-only task is never overdue on its own due day.
    /// An undated list item is never overdue — it has no moment to be late
    /// for.
    func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard !isCompleted, let dueDateString else { return false }
        if let moment = dueDateTime {
            return moment < now
        }
        return dueDateString < QuickTaskParser.ymdString(from: now)
    }

    func isDue(onSameDayAs now: Date) -> Bool {
        dueDateString == QuickTaskParser.ymdString(from: now)
    }

    /// Whole days from `now`'s day to the due day: 0 today, 1 tomorrow,
    /// negative in the past. Nil when the stored date can't be parsed.
    func daysFromToday(at now: Date, calendar: Calendar = .current) -> Int? {
        guard let dueDate else { return nil }
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: dueDate)).day
    }

    /// "Today, 3:00 PM", "Tomorrow", "Friday", "Jul 24", "Jul 24, 2027".
    /// Relative wording for the days a reader thinks in, absolute beyond
    /// that, and the year only when it isn't the current one. Empty for an
    /// undated list item, whose row shows no due label at all.
    func relativeDueDescription(at now: Date, calendar: Calendar = .current) -> String {
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
                     calendar: Calendar = .current) -> String {
        guard let dueDateString,
              let dueDate = date(from: dueDateString, calendar: calendar)
        else { return dueDateString ?? "" }
        let day = dayDescription(dueDate, at: now, calendar: calendar)
        guard let moment = moment(on: dueDate, at: dueTimeString, calendar: calendar)
        else { return day }
        return "\(day), \(moment.formatted(.dateTime.hour().minute()))"
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
            return dueDate.formatted(.dateTime.weekday(.wide))
        default:
            let sameYear = calendar.component(.year, from: dueDate)
                == calendar.component(.year, from: now)
            return sameYear
                ? dueDate.formatted(.dateTime.month(.abbreviated).day())
                : dueDate.formatted(.dateTime.month(.abbreviated).day().year())
        }
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

    var title: String {
        switch kind {
        case .overdue: "Overdue · \(tasks.count)"
        case .today: "Today · \(tasks.count)"
        case .tomorrow: "Tomorrow · \(tasks.count)"
        case .upcoming: "Upcoming · \(tasks.count)"
        }
    }

    var symbol: String {
        switch kind {
        case .overdue: "exclamationmark.circle.fill"
        case .today: "sun.max"
        case .tomorrow: "sunrise"
        case .upcoming: "calendar"
        }
    }

    /// Partitions sorted incomplete tasks into the non-empty sections.
    static func grouping(_ tasks: [TaskItem],
                         now: Date,
                         calendar: Calendar = .current) -> [TaskGroup] {
        var buckets: [Kind: [TaskItem]] = [:]
        for task in tasks {
            buckets[kind(for: task, now: now, calendar: calendar), default: []].append(task)
        }
        return Kind.allCases.compactMap { kind in
            guard let tasks = buckets[kind], !tasks.isEmpty else { return nil }
            return TaskGroup(kind: kind, tasks: tasks)
        }
    }

    static func kind(for task: TaskItem, now: Date, calendar: Calendar = .current) -> Kind {
        if task.isOverdue(at: now, calendar: calendar) { return .overdue }
        switch task.daysFromToday(at: now, calendar: calendar) {
        case 0: return .today
        case 1: return .tomorrow
        default: return .upcoming
        }
    }
}
