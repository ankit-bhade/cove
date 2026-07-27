import XCTest

@testable import Cove

/// Category surgery on the subscription note.
///
/// The section primitives themselves are `TaskListDocument`'s and are covered
/// by `TaskListDocumentTests`; what these pin down is that they do the right
/// thing to *subscription* lines — which is the half that would break silently,
/// since a rename that dropped a charge still leaves a valid Markdown file.
final class SubscriptionCategoryTests: XCTestCase {

    private let note = """
        - Loose @cost(1.00 USD) @every(month) @since(2024-01-01)

        ## Streaming

        - Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)
        - Spotify @cost(11.99 USD) @every(month) @since(2023-08-19)

        ## Infrastructure

        - Domain @cost(14.00 USD) @every(year) @since(2022-11-02)
        """

    // MARK: - Rename

    func testRenamingACategoryKeepsEveryChargeUnderIt() throws {
        let renamed = try TaskListDocument.renamingSectionResult(
            named: "Streaming", to: "Video", in: note
        ).get()
        let parsed = SubscriptionParser.subscriptions(in: renamed)
        XCTAssertEqual(
            parsed.map(\.name), ["Loose", "Netflix", "Spotify", "Domain"])
        XCTAssertEqual(
            parsed.filter { $0.category == "Video" }.map(\.name),
            ["Netflix", "Spotify"])
        XCTAssertEqual(
            SubscriptionParser.categoryNames(in: renamed),
            ["Video", "Infrastructure"])
    }

    func testRenamingLeavesCostsAndCyclesUntouched() throws {
        let renamed = try TaskListDocument.renamingSectionResult(
            named: "Streaming", to: "Video", in: note
        ).get()
        let netflix = SubscriptionParser.subscriptions(in: renamed)
            .first { $0.name == "Netflix" }
        XCTAssertEqual(netflix?.cost.amount, Decimal(string: "15.49"))
        XCTAssertEqual(netflix?.cycle, .monthly)
        XCTAssertEqual(netflix?.firstChargeDateString, "2024-03-04")
    }

    func testRenamingToAnExistingCategoryIsRefused() {
        XCTAssertThrowsError(
            try TaskListDocument.renamingSectionResult(
                named: "Streaming", to: "Infrastructure", in: note
            ).get())
    }

    /// A case-only rename is a rename, not a collision with itself.
    func testCaseOnlyRenameIsAllowed() throws {
        let renamed = try TaskListDocument.renamingSectionResult(
            named: "Streaming", to: "STREAMING", in: note
        ).get()
        XCTAssertEqual(
            SubscriptionParser.categoryNames(in: renamed),
            ["STREAMING", "Infrastructure"])
    }

    // MARK: - Delete

    func testDeletingACategoryTakesItsChargesWithIt() throws {
        let removed = try TaskListDocument.removingSectionResult(
            named: "Streaming", from: note
        ).get()
        XCTAssertEqual(
            SubscriptionParser.subscriptions(in: removed).map(\.name),
            ["Loose", "Domain"])
        XCTAssertEqual(
            SubscriptionParser.categoryNames(in: removed), ["Infrastructure"])
    }

    /// The charges outside the deleted section — both unfiled and in another
    /// category — have to survive untouched.
    func testDeletingACategoryLeavesEveryOtherChargeAlone() throws {
        let removed = try TaskListDocument.removingSectionResult(
            named: "Streaming", from: note
        ).get()
        let parsed = SubscriptionParser.subscriptions(in: removed)
        XCTAssertNil(parsed.first { $0.name == "Loose" }?.category)
        XCTAssertEqual(
            parsed.first { $0.name == "Domain" }?.category, "Infrastructure")
    }

    func testDeletingAnEmptyCategoryRemovesOnlyItsHeading() throws {
        let withEmpty = try TaskListDocument.addingSectionResult(
            named: "Unused", to: note
        ).get()
        XCTAssertEqual(
            SubscriptionParser.categoryNames(in: withEmpty),
            ["Streaming", "Infrastructure", "Unused"])
        let removed = try TaskListDocument.removingSectionResult(
            named: "Unused", from: withEmpty
        ).get()
        XCTAssertEqual(
            SubscriptionParser.subscriptions(in: removed).count, 4)
        XCTAssertEqual(
            SubscriptionParser.categoryNames(in: removed),
            ["Streaming", "Infrastructure"])
    }

    // MARK: - Undo

    func testRestoringADeletedCategoryBringsItsChargesBack() throws {
        let removal = try TaskListDocument.removingSectionWithRecordResult(
            named: "Streaming", from: note
        ).get()
        let restored = try TaskListDocument.restoringSectionResult(
            removal.record, in: removal.text
        ).get()
        let parsed = SubscriptionParser.subscriptions(in: restored)
        XCTAssertEqual(
            parsed.map(\.name), ["Loose", "Netflix", "Spotify", "Domain"])
        XCTAssertEqual(
            parsed.filter { $0.category == "Streaming" }.map(\.name),
            ["Netflix", "Spotify"])
    }

    /// Undo fails closed rather than merging into a category that has since
    /// been recreated under the same name.
    func testRestoringRefusesWhenTheNameHasBeenReused() throws {
        let removal = try TaskListDocument.removingSectionWithRecordResult(
            named: "Streaming", from: note
        ).get()
        let reused = try TaskListDocument.insertingLineResult(
            "- Hulu @cost(9.99 USD) @every(month) @since(2025-05-05)",
            inSection: "Streaming",
            in: removal.text
        ).get()
        XCTAssertThrowsError(
            try TaskListDocument.restoringSectionResult(
                removal.record, in: reused
            ).get())
    }

    // MARK: - Creation

    func testAddingACategoryCreatesAnEmptyHeading() throws {
        let added = try TaskListDocument.addingSectionResult(
            named: "Health", to: note
        ).get()
        XCTAssertEqual(
            SubscriptionParser.categoryNames(in: added),
            ["Streaming", "Infrastructure", "Health"])
        XCTAssertEqual(SubscriptionParser.subscriptions(in: added).count, 4)
    }

    func testAddingADuplicateCategoryIsRefused() {
        XCTAssertThrowsError(
            try TaskListDocument.addingSectionResult(
                named: "streaming", to: note
            ).get())
    }

    /// Filing a charge into a category that does not exist yet creates the
    /// heading, which is what the draft sheet's "New Category…" relies on.
    func testFilingIntoANewCategoryCreatesIt() throws {
        let updated = try TaskListDocument.insertingLineResult(
            "- Gym @cost(42.00 USD) @every(month) @since(2025-01-06)",
            inSection: "Health",
            in: note
        ).get()
        let gym = SubscriptionParser.subscriptions(in: updated)
            .first { $0.name == "Gym" }
        XCTAssertEqual(gym?.category, "Health")
        XCTAssertEqual(
            SubscriptionParser.categoryNames(in: updated),
            ["Streaming", "Infrastructure", "Health"])
    }
}
