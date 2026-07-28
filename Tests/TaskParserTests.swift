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
        let tasks = TaskParser.tasks(
            in: """
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

    func testIgnoresTasksAndHeadingsInLiteralMarkdownContexts() {
        let text = """
            ---
            sample: "- [ ] Front @due(2026-07-19)"
            ---
            ```md <!-- this must remain a fence, not open an HTML comment
            - [ ] Fenced @due(2026-07-20)
            ```
            <!--
            - [ ] Commented @due(2026-07-21)
            -->
            - [ ] Live @due(2026-07-22)
            """
        XCTAssertEqual(TaskParser.tasks(in: text).map(\.text), ["Live"])
    }

    /// An opening `---` that is never closed is a thematic break, not front
    /// matter. Reading it as an unterminated block made every task in the
    /// note disappear from the Tasks screen with nothing on screen saying so.
    func testLeadingThematicBreakIsNotUnterminatedFrontMatter() {
        let text = """
            ---
            # Notes

            - [ ] Live @due(2026-07-22)
            """
        XCTAssertEqual(TaskParser.tasks(in: text).map(\.text), ["Live"])
    }

    func testFrontMatterClosedByThreeDotsIsStillLiteral() {
        let text = """
            ---
            sample: "- [ ] Front @due(2026-07-19)"
            ...
            - [ ] Live @due(2026-07-22)
            """
        XCTAssertEqual(TaskParser.tasks(in: text).map(\.text), ["Live"])
    }

    func testFrontMatterDelimiterAloneDoesNotHideTheRestOfTheNote() {
        XCTAssertEqual(
            TaskParser.tasks(in: "---\n- [ ] Live @due(2026-07-22)\n").map(\.text),
            ["Live"])
    }

    func testUnsupportedObsidianStatusesAndOrderedFormsAreDiagnosed() {
        let text = """
            - [/] In progress @due(2026-07-19)
            1. [ ] Ordered @due(2026-07-20)
            > - [ ] Quoted @due(2026-07-21)
            """
        XCTAssertEqual(
            TaskParser.scan(in: text).diagnostics.map(\.kind),
            [
                .unsupportedCheckboxStatus,
                .malformedTask,
                .malformedTask,
            ])
    }

    // MARK: - Non-matching lines

    func testRejectsAlternateSyntax() {
        let text = """
            - [ ] Missing due tag
            - [ ]Tight marker @due(2026-07-19)
            - [ ] @due(2026-07-19)
            - [ ] Trailing text @due(2026-07-19) extra
            -[ ] No space @due(2026-07-19)
            """
        XCTAssertTrue(TaskParser.tasks(in: text).isEmpty)
    }

    func testAcceptsNestedAndCommonUnorderedBulletForms() {
        let text = """
              - [ ] Indented @due(2026-07-19)
            * [x] Star @due(2026-07-20)
            + [ ] Plus @due(2026-07-21)
            """
        XCTAssertEqual(
            TaskParser.tasks(in: text).map(\.text),
            ["Indented", "Star", "Plus"])
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
            """
        XCTAssertTrue(TaskParser.tasks(in: text).isEmpty)
    }

    /// Reading is lenient about run-length whitespace; a time is still a time
    /// or it is nothing. Cove itself only ever writes the canonical spacing.
    func testAcceptsRunsOfWhitespaceAroundTags() {
        let tasks = TaskParser.tasks(
            in: "-  [ ]  Two spaces  @due(2026-07-19  09:00)\n")
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.text, "Two spaces")
        XCTAssertEqual(tasks.first?.dueDateString, "2026-07-19")
        XCTAssertEqual(tasks.first?.dueTimeString, "09:00")
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
        XCTAssertEqual(
            tasks.map(\.recurrence),
            [
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

    /// Toggling is `settingTaskCompleted` to the opposite of the state the
    /// index last saw, which is the call the app and the widget both make.
    private func toggling(
        _ text: String,
        taskText: String = "Buy milk",
        due: String? = "2026-07-20",
        time: String? = nil,
        recurrence: RecurrenceRule? = nil,
        isCompleted: Bool = false,
        list: String? = nil,
        line: Int = 0,
        today: String = "2026-07-18"
    ) -> String? {
        TaskParser.settingTaskCompleted(
            identity(
                taskText, due: due, time: time,
                recurrence: recurrence, list: list, line: line),
            to: !isCompleted, todayDateString: today, in: text)
    }

    private func identity(
        _ taskText: String,
        due: String?,
        time: String?,
        recurrence: RecurrenceRule?,
        list: String?,
        line: Int
    ) -> TaskIdentity {
        TaskIdentity(
            filePath: "/vault/Tasks.md",
            lineNumber: line,
            text: taskText,
            dueDateString: due,
            dueTimeString: time,
            recurrenceTag: recurrence?.tagText,
            listName: list)
    }

    func testTogglingIncompleteTaskChecksIt() {
        let text = "Intro\n- [ ] Buy milk @due(2026-07-20)\n"
        XCTAssertEqual(
            toggling(text, line: 1),
            "Intro\n- [x] Buy milk @due(2026-07-20)\n")
    }

    func testTogglingCompletedTaskUnchecksIt() {
        let text = "- [X] Buy milk @due(2026-07-20)\n"
        XCTAssertEqual(
            toggling(text, isCompleted: true),
            "- [ ] Buy milk @due(2026-07-20)\n")
    }

    func testTogglingRefusesAmbiguousDuplicates() {
        let text = """
            - [ ] Call mom @due(2026-07-20)
            - [ ] Call mom @due(2026-07-20)
            """
        XCTAssertNil(toggling(text, taskText: "Call mom", line: 1))
        XCTAssertEqual(
            TaskParser.scan(in: text).diagnostics.map(\.kind),
            [.duplicateTask])
    }

    func testTogglingFallsBackWhenLinesShifted() {
        let text = "New first line\n- [ ] Buy milk @due(2026-07-20)\n"
        XCTAssertEqual(
            toggling(text, line: 0),
            "New first line\n- [x] Buy milk @due(2026-07-20)\n")
    }

    func testUnlistedCaptureTaskNeverMatchesIdenticalTaskInsideAList() {
        let text = """
            - [ ] Buy milk @due(2026-07-20)
            ## Groceries
            - [ ] Buy milk @due(2026-07-20)
            """
        let identity = TaskIdentity(
            filePath: "/vault/Tasks.md",
            lineNumber: 0,
            text: "Buy milk",
            dueDateString: "2026-07-20",
            dueTimeString: nil,
            recurrenceTag: nil,
            listName: nil,
            isSectionedDocument: true)
        XCTAssertEqual(
            TaskParser.settingTaskCompleted(
                identity,
                to: true,
                todayDateString: "2026-07-19",
                in: text),
            """
            - [x] Buy milk @due(2026-07-20)
            ## Groceries
            - [ ] Buy milk @due(2026-07-20)
            """)
    }

    func testTogglingReturnsNilWhenTaskIsGone() {
        XCTAssertNil(toggling("Nothing here\n"))
        // Same text but the schedule on disk no longer matches.
        XCTAssertNil(toggling("- [ ] Buy milk @due(2026-07-20 09:00)\n"))
        // A task already in the desired state is *not* gone: completion is
        // not part of identity, so this is the idempotent no-op covered by
        // testSetCompletedIsIdempotentWhenAlreadyInDesiredState.
    }

    func testCompletingRecurringTaskAdvancesDueDateInstead() {
        // Sunday 2026-07-19 → next Sunday, checkbox stays open.
        let text = "- [ ] Laundry @due(2026-07-19 18:00) @repeat(every sunday)\n"
        XCTAssertEqual(
            toggling(
                text, taskText: "Laundry", due: "2026-07-19", time: "18:00",
                recurrence: RecurrenceRule(frequency: .weekly, byWeekday: [1]),
                today: "2026-07-18"),
            "- [ ] Laundry @due(2026-07-26 18:00) @repeat(every sunday) @anchor(2026-07-19)\n")
    }

    func testOverdueRecurringTaskAdvancesPastToday() {
        // Weeks overdue: the next occurrence lands after today, not one
        // period after the stale due date.
        let text = "- [ ] Stretch @due(2026-06-01) @repeat(daily)\n"
        XCTAssertEqual(
            toggling(
                text, taskText: "Stretch", due: "2026-06-01",
                recurrence: RecurrenceRule(frequency: .daily),
                today: "2026-07-18"),
            "- [ ] Stretch @due(2026-07-19) @repeat(daily) @anchor(2026-06-01)\n")
    }

    func testSetCompletedIsIdempotentWhenAlreadyInDesiredState() throws {
        let text = "- [x] Buy milk @due(2026-07-20)\n"
        let parsed = try XCTUnwrap(TaskParser.tasks(in: text).first)
        let identity = taskIdentity(parsed)

        XCTAssertEqual(
            TaskParser.settingTaskCompleted(
                identity, to: true, todayDateString: "2026-07-19", in: text), text)
    }

    func testSetCompletedReturnsNilAfterTargetWasDeleted() throws {
        let text = "- [ ] Buy milk @due(2026-07-20)\n"
        let parsed = try XCTUnwrap(TaskParser.tasks(in: text).first)

        XCTAssertNil(
            TaskParser.settingTaskCompleted(
                taskIdentity(parsed), to: true,
                todayDateString: "2026-07-19", in: "Nothing here\n"))
    }

    func testRecurringDesiredCompletionRetryDoesNotAdvanceTwice() throws {
        let text = "- [ ] Stretch @due(2026-07-19) @repeat(daily)\n"
        let parsed = try XCTUnwrap(TaskParser.tasks(in: text).first)
        let identity = taskIdentity(parsed)
        let once = try XCTUnwrap(
            TaskParser.settingTaskCompleted(
                identity, to: true, todayDateString: "2026-07-19", in: text))

        XCTAssertEqual(
            once,
            "- [ ] Stretch @due(2026-07-20) @repeat(daily) @anchor(2026-07-19)\n")
        XCTAssertNil(
            TaskParser.settingTaskCompleted(
                identity, to: true, todayDateString: "2026-07-19", in: once))
    }

    // MARK: - Removing one task

    private func removing(
        _ text: String,
        taskText: String = "Buy milk",
        due: String? = "2026-07-20",
        time: String? = nil,
        recurrence: RecurrenceRule? = nil,
        list: String? = nil,
        line: Int = 0
    ) -> String? {
        TaskParser.removingTask(
            identity(
                taskText, due: due, time: time,
                recurrence: recurrence, list: list, line: line),
            in: text)
    }

    private func taskIdentity(_ task: TaskParser.ParsedTask) -> TaskIdentity {
        TaskIdentity(
            filePath: "/vault/Tasks.md",
            lineNumber: task.lineNumber,
            text: task.text,
            dueDateString: task.dueDateString,
            dueTimeString: task.dueTimeString,
            recurrenceTag: task.recurrence?.tagText,
            listName: task.listName,
            recurrenceAnchorDateString: task.recurrenceAnchorDateString)
    }

    func testPersistedAnchorKeepsMonthlyCadenceAcrossRefreshes() throws {
        let original = "- [ ] Billing @due(2026-01-30) @repeat(monthly)\n"
        let firstTask = try XCTUnwrap(TaskParser.tasks(in: original).first)
        let february = try TaskParser.settingTaskCompletedResult(
            taskIdentity(firstTask),
            to: true,
            todayDateString: "2026-01-30",
            in: original,
            timeZone: TimeZone(secondsFromGMT: 0)!
        ).get()
        XCTAssertEqual(
            february,
            "- [ ] Billing @due(2026-02-28) @repeat(monthly) @anchor(2026-01-30)\n")

        let refreshed = try XCTUnwrap(TaskParser.tasks(in: february).first)
        let march = try TaskParser.settingTaskCompletedResult(
            taskIdentity(refreshed),
            to: true,
            todayDateString: "2026-02-28",
            in: february,
            timeZone: TimeZone(secondsFromGMT: 0)!
        ).get()
        XCTAssertEqual(
            march,
            "- [ ] Billing @due(2026-03-30) @repeat(monthly) @anchor(2026-01-30)\n")
    }

    func testRecurringCompletionUndoRestoresDateAndIntroducedAnchor() throws {
        let original = "- [ ] Billing @due(2026-01-30) @repeat(monthly)\r\n"
        let task = try XCTUnwrap(TaskParser.tasks(in: original).first)
        let identity = taskIdentity(task)
        let advanced = try TaskParser.settingTaskCompletedResult(
            identity,
            to: true,
            todayDateString: "2026-01-30",
            in: original,
            timeZone: TimeZone(secondsFromGMT: 0)!
        ).get()
        let restored = try TaskParser.revertingRecurringCompletionResult(
            identity,
            completedOn: "2026-01-30",
            in: advanced,
            timeZone: TimeZone(secondsFromGMT: 0)!
        ).get()
        XCTAssertEqual(restored, original)
    }

    func testRestoringCheckboxStateDoesNotApplyRecurrenceSemantics() throws {
        let checked =
            "- [x] Billing @due(2026-02-28) @repeat(monthly) @anchor(2026-01-30)\r\n"
        let task = try XCTUnwrap(TaskParser.tasks(in: checked).first)
        let identity = taskIdentity(task)

        let restored = try TaskParser.restoringCheckboxStateResult(
            identity,
            to: false,
            in: checked
        ).get()

        XCTAssertEqual(
            restored,
            "- [ ] Billing @due(2026-02-28) @repeat(monthly) @anchor(2026-01-30)\r\n")
        XCTAssertEqual(
            try TaskParser.restoringCheckboxStateResult(
                identity,
                to: true,
                in: checked
            ).get(),
            checked)
    }

    func testRestoringCheckboxStateRefusesAmbiguousDuplicates() throws {
        let text = """
            - [x] Billing @due(2026-02-28) @repeat(monthly) @anchor(2026-01-30)
            - [ ] Billing @due(2026-02-28) @repeat(monthly) @anchor(2026-01-30)
            """
        let task = try XCTUnwrap(TaskParser.tasks(in: text).first)

        XCTAssertEqual(
            TaskParser.restoringCheckboxStateResult(
                taskIdentity(task),
                to: false,
                in: text),
            .failure(.ambiguousTask([0, 1])))
    }

    func testRemovingTaskDropsItsWholeLine() {
        let text = "Intro\n- [ ] Buy milk @due(2026-07-20)\nOutro\n"
        XCTAssertEqual(removing(text, line: 1), "Intro\nOutro\n")
    }

    /// The removal reports the line it actually took, completion and bullet
    /// included — neither is part of the semantic key, so the line found is
    /// not necessarily the one the index last saw, and Undo restores bytes.
    func testRemovingTaskReportsTheLineItTook() throws {
        let text = "Intro\n* [x] Buy milk @due(2026-07-20)\nOutro\n"
        let removal = try TaskParser.removingTaskWithLineResult(
            identity(
                "Buy milk", due: "2026-07-20", time: nil,
                recurrence: nil, list: nil, line: 1),
            in: text
        ).get()
        XCTAssertEqual(removal.removedLine, "* [x] Buy milk @due(2026-07-20)\n")
        XCTAssertEqual(removal.text, "Intro\nOutro\n")
    }

    func testRemovingTaskKeepsSurroundingMarkdownVerbatim() {
        let text = """
            # Tasks
            - [ ] Buy milk @due(2026-07-20)
            - [ ] Call mom @due(2026-07-21)
            Some prose.
            """
        XCTAssertEqual(
            removing(text, line: 1),
            """
            # Tasks
            - [ ] Call mom @due(2026-07-21)
            Some prose.
            """)
    }

    func testRemovingTaskWithoutTrailingNewlineAtEndOfFile() {
        let text = "Intro\n- [ ] Buy milk @due(2026-07-20)"
        XCTAssertEqual(removing(text, line: 1), "Intro\n")
    }

    func testRemovingRefusesAmbiguousDuplicates() {
        let text = """
            - [ ] Call mom @due(2026-07-20)
            - [ ] Call mom @due(2026-07-20)
            Tail
            """
        XCTAssertNil(removing(text, taskText: "Call mom", line: 1))
    }

    func testRemovingCompletedTask() {
        let text = "- [x] Buy milk @due(2026-07-20)\nTail\n"
        XCTAssertEqual(removing(text), "Tail\n")
    }

    /// Completion is not part of identity, so a task completed between the
    /// index build and the swipe is still the task the user meant to delete.
    func testRemovingIgnoresAConcurrentCompletion() {
        XCTAssertEqual(removing("- [x] Buy milk @due(2026-07-20)\nTail\n"), "Tail\n")
    }

    func testRemovingRecurringTaskMatchesOnItsRule() {
        let text = "- [ ] Stretch @due(2026-07-20) @repeat(daily)\n"
        XCTAssertEqual(
            removing(
                text, taskText: "Stretch",
                recurrence: RecurrenceRule(frequency: .daily)), "")
        // A task whose rule differs on disk is not the indexed one.
        XCTAssertNil(removing(text, taskText: "Stretch"))
    }

    func testRemovingReturnsNilWhenTaskIsGone() {
        XCTAssertNil(removing("Nothing here\n"))
        // Same text but the due date moved.
        XCTAssertNil(removing("- [ ] Buy milk @due(2026-07-25)\n"))
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
        XCTAssertEqual(
            TaskParser.clearingCompletedTasks(in: text),
            """
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
