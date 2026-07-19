import XCTest
@testable import Cove

final class TaskParserTests: XCTestCase {

    // MARK: - Matching lines

    func testParsesIncompleteTaskLine() {
        let tasks = TaskParser.tasks(in: "- [ ] Buy milk @due(2026-07-20)\n")
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.text, "Buy milk")
        XCTAssertEqual(tasks.first?.dueDateString, "2026-07-20")
        XCTAssertEqual(tasks.first?.lineNumber, 0)
        XCTAssertEqual(tasks.first?.isCompleted, false)
    }

    func testParsesCompletedTaskWithEitherCase() {
        let tasks = TaskParser.tasks(in: """
            - [x] Done low @due(2026-01-01)
            - [X] Done high @due(2026-01-02)
            """)
        XCTAssertEqual(tasks.map(\.isCompleted), [true, true])
        XCTAssertEqual(tasks.map(\.lineNumber), [0, 1])
    }

    func testTaskLinesMixedWithOtherContent() {
        let text = """
            # Groceries
            Some intro text.
            - [ ] Milk @due(2026-07-19)
            - [ ] No due date here
            - [x] Eggs @due(2026-07-18)
            """
        let tasks = TaskParser.tasks(in: text)
        XCTAssertEqual(tasks.map(\.text), ["Milk", "Eggs"])
        XCTAssertEqual(tasks.map(\.lineNumber), [2, 4])
    }

    func testLastDueTagOnLineWinsAndTextKeepsEarlierOnes() {
        let tasks = TaskParser.tasks(in: "- [ ] Move @due(2026-01-01) party @due(2026-02-02)\n")
        XCTAssertEqual(tasks.first?.text, "Move @due(2026-01-01) party")
        XCTAssertEqual(tasks.first?.dueDateString, "2026-02-02")
    }

    func testAllowsTrailingWhitespace() {
        let tasks = TaskParser.tasks(in: "- [ ] Water plants @due(2026-07-19)  \n")
        XCTAssertEqual(tasks.count, 1)
    }

    // MARK: - Non-matching lines

    func testRejectsAlternateSyntax() {
        let text = """
            - [ ] Missing due tag
            - [ ]Tight marker @due(2026-07-19)
            - [ ]  Two spaces after marker @due(2026-07-19)
            - [ ] @due(2026-07-19)
            - [ ] Trailing text @due(2026-07-19) extra
            * [ ] Star bullet @due(2026-07-19)
            -[ ] No space @due(2026-07-19)
            """
        XCTAssertTrue(TaskParser.tasks(in: text).isEmpty)
    }

    func testRejectsIndentedTaskLine() {
        XCTAssertTrue(TaskParser.tasks(in: "  - [ ] Indented @due(2026-07-19)\n").isEmpty)
    }

    func testRejectsInvalidOrMalformedDates() {
        let text = """
            - [ ] Bad day @due(2026-02-30)
            - [ ] Bad month @due(2026-13-01)
            - [ ] Not padded @due(2026-7-9)
            - [ ] Not a date @due(soon)
            """
        XCTAssertTrue(TaskParser.tasks(in: text).isEmpty)
    }

    func testAcceptsLeapDayOnlyInLeapYears() {
        XCTAssertEqual(TaskParser.tasks(in: "- [ ] Leap @due(2028-02-29)").count, 1)
        XCTAssertTrue(TaskParser.tasks(in: "- [ ] No leap @due(2026-02-29)").isEmpty)
    }

    // MARK: - Times

    func testParsesDueTime() {
        let tasks = TaskParser.tasks(in: "- [ ] Get bread @due(2026-07-19 15:00)\n")
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.dueDateString, "2026-07-19")
        XCTAssertEqual(tasks.first?.dueTimeString, "15:00")
    }

    func testDateOnlyTaskHasNilTime() {
        let tasks = TaskParser.tasks(in: "- [ ] Tennis @due(2026-07-24)\n")
        XCTAssertEqual(tasks.first?.dueTimeString, nil)
    }

    func testRejectsInvalidTimes() {
        let text = """
            - [ ] Bad hour @due(2026-07-19 24:00)
            - [ ] Bad minute @due(2026-07-19 12:60)
            - [ ] Not padded @due(2026-07-19 9:00)
            - [ ] Two spaces @due(2026-07-19  09:00)
            """
        XCTAssertTrue(TaskParser.tasks(in: text).isEmpty)
    }

    // MARK: - Recurrence

    func testParsesRepeatTags() {
        let text = """
            - [ ] Laundry @due(2026-07-19 18:00) @repeat(every sunday)
            - [ ] Standup @due(2026-07-20 09:00) @repeat(every weekday)
            - [ ] Stretch @due(2026-07-19) @repeat(daily)
            - [ ] Doctor @due(2026-07-21 10:00) @repeat(every 2 weeks)
            """
        let tasks = TaskParser.tasks(in: text)
        XCTAssertEqual(tasks.map(\.recurrence), [
            RecurrenceRule(frequency: .weekly, byWeekday: [1]),
            .everyWeekday,
            RecurrenceRule(frequency: .daily),
            RecurrenceRule(frequency: .weekly, interval: 2),
        ])
    }

    func testRejectsUnknownRepeatRuleOrTrailingText() {
        let text = """
            - [ ] Unknown rule @due(2026-07-19) @repeat(sometimes)
            - [ ] Trailing text @due(2026-07-19) @repeat(daily) extra
            """
        XCTAssertTrue(TaskParser.tasks(in: text).isEmpty)
    }

    func testRepeatTagBeforeDueTagIsJustText() {
        let tasks = TaskParser.tasks(
            in: "- [ ] Fix the @repeat(daily) docs @due(2026-07-19)\n")
        XCTAssertEqual(tasks.first?.text, "Fix the @repeat(daily) docs")
        XCTAssertNil(tasks.first?.recurrence)
    }

    // MARK: - Toggling

    private func toggling(_ text: String,
                          taskText: String = "Buy milk",
                          due: String = "2026-07-20",
                          time: String? = nil,
                          recurrence: RecurrenceRule? = nil,
                          isCompleted: Bool = false,
                          line: Int = 0,
                          today: String = "2026-07-18") -> String? {
        TaskParser.togglingTask(
            withText: taskText, dueDateString: due, dueTimeString: time,
            recurrence: recurrence, isCompleted: isCompleted,
            preferredLineNumber: line, todayDateString: today, in: text)
    }

    func testTogglingIncompleteTaskChecksIt() {
        let text = "Intro\n- [ ] Buy milk @due(2026-07-20)\n"
        XCTAssertEqual(toggling(text, line: 1),
                       "Intro\n- [x] Buy milk @due(2026-07-20)\n")
    }

    func testTogglingCompletedTaskUnchecksIt() {
        let text = "- [X] Buy milk @due(2026-07-20)\n"
        XCTAssertEqual(toggling(text, isCompleted: true),
                       "- [ ] Buy milk @due(2026-07-20)\n")
    }

    func testTogglingPrefersRememberedLineAmongDuplicates() {
        let text = """
            - [ ] Call mom @due(2026-07-20)
            - [ ] Call mom @due(2026-07-20)
            """
        XCTAssertEqual(toggling(text, taskText: "Call mom", line: 1), """
            - [ ] Call mom @due(2026-07-20)
            - [x] Call mom @due(2026-07-20)
            """)
    }

    func testTogglingFallsBackWhenLinesShifted() {
        let text = "New first line\n- [ ] Buy milk @due(2026-07-20)\n"
        XCTAssertEqual(toggling(text, line: 0),
                       "New first line\n- [x] Buy milk @due(2026-07-20)\n")
    }

    func testTogglingReturnsNilWhenTaskIsGone() {
        XCTAssertNil(toggling("Nothing here\n"))
        // Same text but the state on disk no longer matches.
        XCTAssertNil(toggling("- [x] Buy milk @due(2026-07-20)\n"))
        // Same text but the schedule on disk no longer matches.
        XCTAssertNil(toggling("- [ ] Buy milk @due(2026-07-20 09:00)\n"))
    }

    func testCompletingRecurringTaskAdvancesDueDateInstead() {
        // Sunday 2026-07-19 → next Sunday, checkbox stays open.
        let text = "- [ ] Laundry @due(2026-07-19 18:00) @repeat(every sunday)\n"
        XCTAssertEqual(
            toggling(text, taskText: "Laundry", due: "2026-07-19", time: "18:00",
                     recurrence: RecurrenceRule(frequency: .weekly, byWeekday: [1]),
                     today: "2026-07-18"),
            "- [ ] Laundry @due(2026-07-26 18:00) @repeat(every sunday)\n")
    }

    func testOverdueRecurringTaskAdvancesPastToday() {
        // Weeks overdue: the next occurrence lands after today, not one
        // period after the stale due date.
        let text = "- [ ] Stretch @due(2026-06-01) @repeat(daily)\n"
        XCTAssertEqual(
            toggling(text, taskText: "Stretch", due: "2026-06-01",
                     recurrence: RecurrenceRule(frequency: .daily),
                     today: "2026-07-18"),
            "- [ ] Stretch @due(2026-07-19) @repeat(daily)\n")
    }

    // MARK: - Clearing completed tasks

    func testClearingCompletedTasksRemovesOnlyStrictCompletedTaskLines() {
        let text = """
            # Tasks
            - [x] Finished @due(2026-07-18)
            - [ ] Still open @due(2026-07-19)
            - [X] Also finished @due(2026-07-20 08:30)
            - [x] Plain Markdown checkbox
            """
        XCTAssertEqual(TaskParser.clearingCompletedTasks(in: text), """
            # Tasks
            - [ ] Still open @due(2026-07-19)
            - [x] Plain Markdown checkbox
            """)
    }

    func testClearingCompletedTasksPreservesLineEndingsAndFinalLine() {
        let text = "Intro\r\n- [x] Done @due(2026-07-18)\r\nOutro"
        XCTAssertEqual(TaskParser.clearingCompletedTasks(in: text), "Intro\r\nOutro")

        let finalTask = "Intro\n- [x] Done @due(2026-07-18)"
        XCTAssertEqual(TaskParser.clearingCompletedTasks(in: finalTask), "Intro\n")
    }

    func testClearingCompletedTasksWithoutMatchesIsNoOp() {
        let text = "- [ ] Open @due(2026-07-18)\nSome prose\n"
        XCTAssertEqual(TaskParser.clearingCompletedTasks(in: text), text)
    }
}
