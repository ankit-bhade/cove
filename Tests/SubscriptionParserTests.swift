import XCTest

@testable import Cove

/// The subscription line grammar: the canonical form Cove writes, the wider
/// set it reads, and the rejections it reports rather than swallowing.
final class SubscriptionParserTests: XCTestCase {

    private let note = """
        - Rent @cost(1450.00 GBP) @every(month) @since(2021-06-01)

        ## Streaming
        - Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)
        - Spotify @cost(11.99 USD) @every(month) @since(2023-08-19) @status(paused)

        ## Infrastructure
        - Domain @cost(14.00 USD) @every(year) @since(2022-11-02)
        """

    // MARK: - Canonical parsing

    func testParsesEveryLine() {
        let parsed = SubscriptionParser.subscriptions(in: note)
        XCTAssertEqual(
            parsed.map(\.name), ["Rent", "Netflix", "Spotify", "Domain"])
    }

    func testReadsCostAsDecimal() {
        let netflix = SubscriptionParser.subscriptions(in: note)[1]
        XCTAssertEqual(netflix.cost.amount, Decimal(string: "15.49"))
        XCTAssertEqual(netflix.cost.currencyCode, "USD")
    }

    func testReadsCycleAndAnchor() {
        let domain = SubscriptionParser.subscriptions(in: note)[3]
        XCTAssertEqual(domain.cycle, .yearly)
        XCTAssertEqual(domain.firstChargeDateString, "2022-11-02")
    }

    func testHeadingsBecomeCategories() {
        let parsed = SubscriptionParser.subscriptions(in: note)
        XCTAssertEqual(
            parsed.map(\.category),
            [nil, "Streaming", "Streaming", "Infrastructure"])
    }

    func testCategoryNamesIncludeEmptySections() {
        let names = SubscriptionParser.categoryNames(
            in: "## Streaming\n\n## Empty\n")
        XCTAssertEqual(names, ["Streaming", "Empty"])
    }

    func testAbsentStatusTagMeansActive() {
        XCTAssertEqual(SubscriptionParser.subscriptions(in: note)[1].status, .active)
    }

    func testStatusTagIsRead() {
        XCTAssertEqual(SubscriptionParser.subscriptions(in: note)[2].status, .paused)
    }

    /// A `#` heading closes an open category, exactly as it closes a list.
    func testTopLevelHeadingClosesACategory() {
        let text = """
            ## Streaming
            - Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)

            # Notes
            - Rent @cost(1450.00 GBP) @every(month) @since(2021-06-01)
            """
        XCTAssertEqual(
            SubscriptionParser.subscriptions(in: text).map(\.category),
            ["Streaming", nil])
    }

    // MARK: - The wider read

    func testAcceptsIndentationAlternateBulletsAndExtraWhitespace() {
        let text = "   *  Netflix   @cost( 15.49  usd )   @every( Month )  @since(2024-03-04)"
        let parsed = SubscriptionParser.subscriptions(in: text)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.name, "Netflix")
        XCTAssertEqual(parsed.first?.cost.currencyCode, "USD")
        XCTAssertEqual(parsed.first?.cycle, .monthly)
    }

    func testAcceptsPlusBullet() {
        let text = "+ Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)"
        XCTAssertEqual(SubscriptionParser.subscriptions(in: text).count, 1)
    }

    func testAcceptsCostWithFewerFractionDigits() {
        let text = "- Domain @cost(14 USD) @every(year) @since(2022-11-02)"
        XCTAssertEqual(
            SubscriptionParser.subscriptions(in: text).first?.cost.amount,
            Decimal(14))
    }

    /// Every wording `BillingCycle` understands reads to the same cycle, so a
    /// hand-typed file is not rejected over phrasing.
    func testEquivalentCycleWordings() {
        for wording in ["month", "monthly", "every month", "every 1 month"] {
            let text = "- X @cost(1.00 USD) @every(\(wording)) @since(2024-01-01)"
            XCTAssertEqual(
                SubscriptionParser.subscriptions(in: text).first?.cycle,
                .monthly,
                "wording: \(wording)")
        }
    }

    func testMultiIntervalCycle() {
        let text = "- X @cost(30.00 USD) @every(3 months) @since(2024-01-01)"
        XCTAssertEqual(
            SubscriptionParser.subscriptions(in: text).first?.cycle,
            .quarterly)
    }

    // MARK: - Rejections, and the diagnostics that report them

    func testMalformedLineIsReportedNotDropped() {
        let text = "- Netflix @cost(abc USD) @every(month) @since(2024-03-04)"
        let scan = SubscriptionParser.scan(in: text)
        XCTAssertTrue(scan.subscriptions.isEmpty)
        XCTAssertEqual(scan.diagnostics.map(\.kind), [.malformedSubscription])
    }

    /// A case slip in the tag would otherwise be invisible: the line simply
    /// would not appear, with nothing saying why.
    func testWrongCaseTagIsReported() {
        let text = "- Netflix @Cost(15.49 USD) @every(month) @since(2024-03-04)"
        let scan = SubscriptionParser.scan(in: text)
        XCTAssertTrue(scan.subscriptions.isEmpty)
        XCTAssertEqual(scan.diagnostics.map(\.kind), [.malformedSubscription])
    }

    func testImpossibleDateIsReported() {
        let text = "- Netflix @cost(15.49 USD) @every(month) @since(2024-02-30)"
        let scan = SubscriptionParser.scan(in: text)
        XCTAssertTrue(scan.subscriptions.isEmpty)
        XCTAssertEqual(scan.diagnostics.map(\.kind), [.impossibleDate])
    }

    /// A weekday set is a valid task recurrence and is not a billing cycle.
    func testWeekdaySetCycleIsRejected() {
        let text = "- Gym @cost(9.00 USD) @every(mon wed) @since(2024-01-01)"
        let scan = SubscriptionParser.scan(in: text)
        XCTAssertTrue(scan.subscriptions.isEmpty)
        XCTAssertEqual(scan.diagnostics.map(\.kind), [.unsupportedCycle])
    }

    func testUnknownStatusIsRejectedRatherThanTreatedAsActive() {
        let text =
            "- Netflix @cost(15.49 USD) @every(month) @since(2024-03-04) @status(archived)"
        let scan = SubscriptionParser.scan(in: text)
        XCTAssertTrue(scan.subscriptions.isEmpty)
        XCTAssertEqual(scan.diagnostics.map(\.kind), [.unsupportedStatus])
    }

    /// A bullet with no `@cost(` is ordinary prose and must produce nothing —
    /// otherwise a note with a few notes in it becomes a wall of warnings.
    func testOrdinaryBulletsProduceNoDiagnostics() {
        let text = """
            - Remember to review these each January
            - [ ] Cancel the gym @due(2026-01-05)
            """
        let scan = SubscriptionParser.scan(in: text)
        XCTAssertTrue(scan.subscriptions.isEmpty)
        XCTAssertTrue(scan.diagnostics.isEmpty)
    }

    func testDiagnosticsAreCapped() {
        let line = "- X @cost(bad) @every(month) @since(2024-01-01)\n"
        let scan = SubscriptionParser.scan(
            in: String(repeating: line, count: 40))
        XCTAssertEqual(
            scan.diagnostics.count,
            SubscriptionParser.maximumDiagnosticsPerNote)
    }

    // MARK: - Literal context

    func testFrontMatterFencesAndCommentsAreNeverIndexed() {
        let text = """
            ---
            - Front @cost(1.00 USD) @every(month) @since(2024-01-01)
            ---

            ```
            - Fenced @cost(2.00 USD) @every(month) @since(2024-01-01)
            ```

            <!--
            - Commented @cost(3.00 USD) @every(month) @since(2024-01-01)
            -->

            - Real @cost(4.00 USD) @every(month) @since(2024-01-01)
            """
        XCTAssertEqual(
            SubscriptionParser.subscriptions(in: text).map(\.name), ["Real"])
    }

    /// A heading inside a fence must not open a category either.
    func testFencedHeadingDoesNotOpenACategory() {
        let text = """
            ```
            ## Fenced
            ```
            - Real @cost(4.00 USD) @every(month) @since(2024-01-01)
            """
        XCTAssertNil(SubscriptionParser.subscriptions(in: text).first?.category)
    }

    // MARK: - Ambiguity

    func testIdenticalLinesAreReportedAsDuplicates() {
        let line = "- Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)"
        let scan = SubscriptionParser.scan(in: "\(line)\n\(line)\n")
        XCTAssertEqual(scan.subscriptions.count, 2)
        XCTAssertEqual(scan.diagnostics.map(\.kind), [.duplicateSubscription])
    }

    /// Status is not identity, so two lines differing only by status are not
    /// duplicates of each other.
    func testStatusAloneDoesNotMakeLinesDistinct() {
        let text = """
            - Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)
            - Netflix @cost(15.49 USD) @every(month) @since(2024-03-04) @status(paused)
            """
        XCTAssertEqual(
            SubscriptionParser.scan(in: text).diagnostics.map(\.kind),
            [.duplicateSubscription])
    }

    func testAmbiguousMatchRefusesRatherThanTakingTheFirst() {
        let line = "- Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)"
        let text = "\(line)\n\(line)\n"
        let first = SubscriptionParser.subscriptions(in: text)[0]
        let target = SubscriptionIdentity(
            filePath: "/vault/Subscriptions.md",
            lineNumber: first.lineNumber,
            name: first.name,
            costAmount: first.cost.amount,
            currencyCode: first.cost.currencyCode,
            cycleTag: first.cycle.tagText,
            firstChargeDateString: first.firstChargeDateString,
            category: first.category)
        XCTAssertEqual(
            SubscriptionParser.matchResult(for: target, in: text),
            .ambiguous(SubscriptionParser.subscriptions(in: text)))
    }

    // MARK: - Mutation

    private func identity(
        of subscription: SubscriptionParser.ParsedSubscription
    ) -> SubscriptionIdentity {
        SubscriptionIdentity(
            filePath: "/vault/Subscriptions.md",
            lineNumber: subscription.lineNumber,
            name: subscription.name,
            costAmount: subscription.cost.amount,
            currencyCode: subscription.cost.currencyCode,
            cycleTag: subscription.cycle.tagText,
            firstChargeDateString: subscription.firstChargeDateString,
            category: subscription.category)
    }

    func testReplacingRewritesOnlyItsOwnLine() throws {
        let target = SubscriptionParser.subscriptions(in: note)[1]
        let updated = try SubscriptionParser.replacingSubscriptionResult(
            identity(of: target),
            with: "- Netflix @cost(17.99 USD) @every(month) @since(2024-03-04)",
            in: note)
        let parsed = SubscriptionParser.subscriptions(in: updated)
        XCTAssertEqual(parsed.map(\.name), ["Rent", "Netflix", "Spotify", "Domain"])
        XCTAssertEqual(parsed[1].cost.amount, Decimal(string: "17.99"))
        XCTAssertEqual(parsed[1].category, "Streaming")
    }

    func testRemovingTakesTheWholeLineIncludingItsTerminator() throws {
        let target = SubscriptionParser.subscriptions(in: note)[2]
        let updated = try SubscriptionParser.removingSubscriptionResult(
            identity(of: target), in: note)
        XCTAssertEqual(
            SubscriptionParser.subscriptions(in: updated).map(\.name),
            ["Rent", "Netflix", "Domain"])
        XCTAssertFalse(updated.contains("Spotify"))
        XCTAssertFalse(updated.contains("\n\n\n"))
    }

    func testMutatingAMissingSubscriptionThrows() {
        let target = SubscriptionIdentity(
            filePath: "/vault/Subscriptions.md",
            lineNumber: 0,
            name: "Gone",
            costAmount: 1,
            currencyCode: "USD",
            cycleTag: "month",
            firstChargeDateString: "2024-01-01",
            category: nil)
        XCTAssertThrowsError(
            try SubscriptionParser.removingSubscriptionResult(target, in: note)
        ) { error in
            XCTAssertEqual(
                error as? SubscriptionParser.MutationError, .subscriptionMissing)
        }
    }

    /// A category renamed only in case must not make its lines unfindable.
    func testCategoryMatchingIsCaseInsensitive() throws {
        let target = SubscriptionParser.subscriptions(in: note)[3]
        let shouted = SubscriptionIdentity(
            filePath: "/vault/Subscriptions.md",
            lineNumber: target.lineNumber,
            name: target.name,
            costAmount: target.cost.amount,
            currencyCode: target.cost.currencyCode,
            cycleTag: target.cycle.tagText,
            firstChargeDateString: target.firstChargeDateString,
            category: "INFRASTRUCTURE")
        XCTAssertNoThrow(try SubscriptionParser.matching(shouted, in: note))
    }

    // MARK: - Round trip

    func testEveryParsedLineRewritesToItself() throws {
        for parsed in SubscriptionParser.subscriptions(in: note) {
            let draft = SubscriptionDraft(
                name: parsed.name,
                amount: parsed.cost.amount,
                currencyCode: parsed.cost.currencyCode,
                cycle: parsed.cycle,
                firstChargeDateString: parsed.firstChargeDateString,
                status: parsed.status)
            let line = try draft.validatedMarkdownLine()
            let reparsed = SubscriptionParser.subscriptions(in: line)
            XCTAssertEqual(reparsed.count, 1)
            XCTAssertEqual(reparsed.first?.name, parsed.name)
            XCTAssertEqual(reparsed.first?.cost, parsed.cost)
            XCTAssertEqual(reparsed.first?.cycle, parsed.cycle)
            XCTAssertEqual(
                reparsed.first?.firstChargeDateString,
                parsed.firstChargeDateString)
            XCTAssertEqual(reparsed.first?.status, parsed.status)
        }
    }
}
