import XCTest
@testable import Cove

final class TaskListDocumentTests: XCTestCase {

    private let note = """
        - [ ] Renew passport @due(2026-07-25)

        ## Groceries
        - [ ] Milk
        - [ ] Bread

        ## Subscriptions
        - [ ] Netflix @due(2026-08-01) @repeat(monthly)

        """

    // MARK: - Heading recognition

    func testHeadingNameReadsListHeadings() {
        XCTAssertEqual(TaskListDocument.headingName(in: "## Groceries"), "Groceries")
        XCTAssertNil(TaskListDocument.headingName(in: "###  Deep  "))
    }

    func testTopLevelHeadingClosesTheCurrentListWithoutOpeningOne() {
        XCTAssertEqual(TaskListDocument.headingName(in: "# Tasks"), "")
    }

    func testNonHeadingLinesAreNotHeadings() {
        XCTAssertNil(TaskListDocument.headingName(in: "- [ ] Milk"))
        XCTAssertNil(TaskListDocument.headingName(in: "#NoSpace"))
        XCTAssertNil(TaskListDocument.headingName(in: "## "))
    }

    // MARK: - Section names

    func testSectionNamesAreListedInFileOrder() {
        XCTAssertEqual(
            TaskListDocument.sectionNames(in: note),
            ["Groceries", "Subscriptions"])
    }

    func testSectionNamesSkipsTopLevelHeadingsAndDuplicates() {
        let text = "# Tasks\n## Groceries\n## groceries\n"
        XCTAssertEqual(TaskListDocument.sectionNames(in: text), ["Groceries"])
    }

    // MARK: - Adding

    func testAddingSectionAppendsAHeadingWithABlankLineBefore() {
        let result = TaskListDocument.addingSection(named: "Packing", to: note)
        XCTAssertEqual(result, note + "\n## Packing\n")
    }

    func testAddingSectionToAnEmptyNoteOmitsTheLeadingBlankLine() {
        XCTAssertEqual(
            TaskListDocument.addingSection(named: "Packing", to: ""),
            "## Packing\n")
    }

    func testAddingAnExistingSectionReturnsNil() {
        XCTAssertNil(TaskListDocument.addingSection(named: "groceries", to: note))
    }

    func testDuplicateSectionEditsFailClosedWithTypedError() {
        let duplicate = "## Groceries\n- [ ] Milk\n## groceries\n- [ ] Bread\n"
        XCTAssertEqual(
            TaskListDocument.removingSection(named: "Groceries", from: duplicate),
            duplicate)
        XCTAssertEqual(
            TaskListDocument.removingSectionResult(named: "Groceries", from: duplicate),
            .failure(.duplicateSection("Groceries")))
        XCTAssertEqual(
            TaskListDocument.diagnostics(in: duplicate).map(\.kind),
            [.duplicateSection])
    }

    func testPreservesCRLFAndBOMWhenAddingAndInserting() throws {
        let text = "\u{FEFF}# Tasks\r\n\r\n## Groceries\r\n- [ ] Milk\r\n"
        let inserted = try TaskListDocument.insertingLineResult(
            "- [ ] Bread",
            inSection: "Groceries",
            in: text
        ).get()
        XCTAssertEqual(
            inserted,
            "\u{FEFF}# Tasks\r\n\r\n## Groceries\r\n- [ ] Milk\r\n- [ ] Bread\r\n")
        XCTAssertFalse(inserted.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }

    func testDeeperHeadingStaysInsideListAndLiteralHeadingsAreIgnored() {
        let text = """
            ## Projects
            ### Cove
            - [ ] Ship
            ```
            ## Not a list
            ```
            ## Later
            - [ ] Read
            """
        XCTAssertEqual(TaskListDocument.sectionNames(in: text), ["Projects", "Later"])
        let removed = TaskListDocument.removingSection(named: "Projects", from: text)
        XCTAssertEqual(removed, "## Later\n- [ ] Read")
    }

    // MARK: - Inserting

    func testInsertingLineAppendsToTheEndOfItsSection() {
        let result = TaskListDocument.insertingLine(
            "- [ ] Eggs",
            inSection: "Groceries",
            in: note)
        XCTAssertEqual(
            result,
            """
            - [ ] Renew passport @due(2026-07-25)

            ## Groceries
            - [ ] Milk
            - [ ] Bread
            - [ ] Eggs

            ## Subscriptions
            - [ ] Netflix @due(2026-08-01) @repeat(monthly)

            """)
    }

    func testInsertingLineMatchesTheSectionCaseInsensitively() {
        let result = TaskListDocument.insertingLine(
            "- [ ] Eggs",
            inSection: "groceries",
            in: note)
        XCTAssertTrue(result.contains("- [ ] Bread\n- [ ] Eggs\n"))
    }

    func testInsertingIntoTheLastSectionKeepsTheTrailingNewline() {
        let result = TaskListDocument.insertingLine(
            "- [ ] Spotify",
            inSection: "Subscriptions",
            in: note)
        XCTAssertTrue(result.hasSuffix("@repeat(monthly)\n- [ ] Spotify\n"))
    }

    func testInsertingIntoAMissingSectionCreatesIt() {
        let result = TaskListDocument.insertingLine(
            "- [ ] Sunscreen",
            inSection: "Packing",
            in: note)
        XCTAssertEqual(result, note + "\n## Packing\n- [ ] Sunscreen\n")
    }

    // MARK: - Inserting outside every list

    func testUnlistedLineGoesAboveTheFirstListRatherThanTheEndOfTheNote() {
        let result = TaskListDocument.insertingUnlistedLine(
            "- [ ] Call bank @due(2026-07-19)",
            in: note)
        XCTAssertEqual(
            result,
            """
            - [ ] Renew passport @due(2026-07-25)
            - [ ] Call bank @due(2026-07-19)

            ## Groceries
            - [ ] Milk
            - [ ] Bread

            ## Subscriptions
            - [ ] Netflix @due(2026-08-01) @repeat(monthly)

            """)
    }

    func testUnlistedLineAppendsWhenTheNoteHasNoLists() {
        let plain = "- [ ] Old @due(2026-07-18)\n"
        XCTAssertEqual(
            TaskListDocument.insertingUnlistedLine(
                "- [ ] New @due(2026-07-19)",
                in: plain),
            plain + "- [ ] New @due(2026-07-19)\n")
    }

    func testUnlistedLineStartsANoteThatIsNothingButLists() {
        let listsOnly = "## Groceries\n- [ ] Milk\n"
        XCTAssertEqual(
            TaskListDocument.insertingUnlistedLine(
                "- [ ] New @due(2026-07-19)",
                in: listsOnly),
            "- [ ] New @due(2026-07-19)\n" + listsOnly)
    }

    func testUnlistedLineFollowsFreeSpaceReopenedByATopLevelHeading() {
        let reopened = """
            ## Groceries
            - [ ] Milk

            # Inbox
            - [ ] Old @due(2026-07-18)

            """
        XCTAssertEqual(
            TaskListDocument.insertingUnlistedLine(
                "- [ ] New @due(2026-07-19)",
                in: reopened),
            reopened + "- [ ] New @due(2026-07-19)\n")
    }

    func testUnlistedLineIntoAnEmptyNote() {
        XCTAssertEqual(
            TaskListDocument.insertingUnlistedLine("- [ ] New @due(2026-07-19)", in: ""),
            "- [ ] New @due(2026-07-19)\n")
    }

    // MARK: - Removing

    func testRemovingSectionDropsItsHeadingAndItems() {
        let result = TaskListDocument.removingSection(named: "Groceries", from: note)
        XCTAssertEqual(
            result,
            """
            - [ ] Renew passport @due(2026-07-25)

            ## Subscriptions
            - [ ] Netflix @due(2026-08-01) @repeat(monthly)

            """)
    }

    func testRemovingTheLastSectionLeavesTheRestIntact() {
        // The blank line that separated the two sections belongs to
        // Groceries and stays behind.
        let result = TaskListDocument.removingSection(named: "Subscriptions", from: note)
        XCTAssertEqual(
            result,
            "- [ ] Renew passport @due(2026-07-25)\n\n"
                + "## Groceries\n- [ ] Milk\n- [ ] Bread\n\n")
    }

    func testRemovingAMissingSectionChangesNothing() {
        XCTAssertEqual(TaskListDocument.removingSection(named: "Packing", from: note), note)
    }

    // MARK: - Renaming

    func testRenamingSectionKeepsItsItems() {
        let result = TaskListDocument.renamingSection(
            named: "Groceries",
            to: "Shopping",
            in: note)
        XCTAssertEqual(
            result,
            note.replacingOccurrences(
                of: "## Groceries",
                with: "## Shopping"))
    }

    func testRenamingToAnExistingListNameFails() {
        XCTAssertNil(
            TaskListDocument.renamingSection(
                named: "Groceries",
                to: "subscriptions",
                in: note))
    }

    func testRenamingChangingOnlyCaseIsAllowed() {
        XCTAssertNotNil(
            TaskListDocument.renamingSection(
                named: "Groceries",
                to: "GROCERIES",
                in: note))
    }

    func testRenamingAMissingSectionFails() {
        XCTAssertNil(
            TaskListDocument.renamingSection(
                named: "Packing",
                to: "Trip",
                in: note))
    }
}
