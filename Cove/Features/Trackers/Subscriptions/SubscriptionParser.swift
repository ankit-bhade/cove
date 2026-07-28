import Foundation

/// Context-aware scanner and mutation helpers for Cove subscription lines.
///
/// The line Cove **writes** is fixed — one space between parts, `-` bullet, no
/// indentation:
///
/// ```text
/// - Netflix @cost(15.49 USD) @every(month) @since(2024-03-04)[ @status(paused)]
/// ```
///
/// What it **reads** is deliberately wider, and only in ways that cannot change
/// a line's meaning: leading indentation, `*` and `+` bullets, runs of spaces
/// or tabs where the canonical form has one, a lower-case currency code, and
/// any cycle wording `BillingCycle` understands. That is the difference between
/// a line typed by hand in Obsidian quietly vanishing from the tracker and
/// being understood. An amount that is not an amount and a date that is not a
/// date are still rejected — and rejection is *reported* through a diagnostic
/// rather than being silent, which is the rule the task parser already
/// settled.
///
/// `##` headings are categories, read through `TaskListDocument` so the
/// tracker and the Lists feature cannot disagree about where a section starts
/// and ends. Text inside YAML front matter, a fenced code block, or an HTML
/// comment is never indexed and never edited, inherited from
/// `MarkdownContextScanner`.
enum SubscriptionParser {
    struct ParsedSubscription: Equatable, Sendable {
        let lineNumber: Int
        /// Whole source line including its terminator, excluding a leading
        /// BOM, so delete and restore are lossless.
        let sourceLine: String
        /// The line's content, without its terminator.
        let lineRange: NSRange
        /// The line including its terminator, which is what a removal takes.
        let enclosingRange: NSRange
        let name: String
        let cost: Money
        let cycle: BillingCycle
        let firstChargeDateString: String
        let status: SubscriptionStatus
        let category: String?
    }

    struct Diagnostic: Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case malformedSubscription
            case impossibleDate
            case unsupportedCycle
            case unsupportedStatus
            case duplicateSubscription
        }

        let kind: Kind
        let lineNumber: Int
        let message: String
    }

    struct ScanResult: Equatable, Sendable {
        let subscriptions: [ParsedSubscription]
        let diagnostics: [Diagnostic]
    }

    enum MatchResult: Equatable, Sendable {
        case matched(ParsedSubscription)
        case missing
        case ambiguous([ParsedSubscription])
    }

    enum MutationError: LocalizedError, Equatable, Sendable {
        case subscriptionMissing
        case ambiguousSubscription([Int])
        case invalidLine
        /// The line still matches, but its status moved under the edit. Status
        /// is outside the semantic key so that setting one is idempotent, which
        /// leaves it the one field a whole-line rewrite could silently revert.
        case statusChangedOnDisk(SubscriptionStatus)

        var errorDescription: String? {
            switch self {
            case .subscriptionMissing:
                return "The subscription changed or was removed in another editor."
            case .statusChangedOnDisk(let status):
                return
                    "This subscription was set to \(status.displayName.lowercased()) in another editor. Reopen it to edit the current version."
            case .ambiguousSubscription(let lines):
                let shown = lines.map { String($0 + 1) }.joined(separator: ", ")
                return
                    "More than one matching subscription exists on lines \(shown). Resolve the duplicates before editing."
            case .invalidLine:
                return "A subscription must be one line and cannot contain control characters."
            }
        }
    }

    /// What makes two lines the same subscription. Status is excluded for the
    /// reason it is excluded from `SubscriptionIdentity`: a semantic "set this
    /// to paused" must still find its line once it is already paused.
    private struct SemanticKey: Hashable {
        let name: String
        let amount: Decimal
        let currencyCode: String
        let cycleTag: String
        let firstChargeDateString: String
        let category: String?
    }

    /// The canonical form, and the only one Cove writes.
    ///
    /// The name is greedy, so a name that itself contains `@cost(` yields to
    /// the *last* one on the line — the same tie-break the task parser makes
    /// for `@due(`.
    private static let subscriptionLineRegex = try! NSRegularExpression(
        pattern:
            #"^[ \t]*[-+*][ \t]+(\S(?:.*\S)?)[ \t]+@cost\([ \t]*(\d{1,12}(?:\.\d{1,2})?)[ \t]+([A-Za-z]{3})[ \t]*\)[ \t]+@every\([ \t]*([A-Za-z0-9][A-Za-z0-9 \t]*?)[ \t]*\)[ \t]+@since\((\d{4})-(\d{2})-(\d{2})\)(?:[ \t]+@status\([ \t]*([A-Za-z]+)[ \t]*\))?[ \t]*$"#
    )

    /// A bullet line that was *trying* to be a subscription. Case-insensitive
    /// on the tag so `@Cost(...)` is reported as malformed rather than
    /// silently ignored — a typo the reader cannot see is the failure mode
    /// this whole diagnostic path exists to prevent.
    ///
    /// It requires `@cost(`, so ordinary prose bullets in the note produce
    /// nothing at all.
    private static let candidateRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:>[ \t]*)*(?:[-+*]|\d+[.)])[ \t]+.*@cost\("#,
        options: [.caseInsensitive])

    /// Dates in the file are Gregorian regardless of the reader's calendar, so
    /// validity is checked in a fixed zone rather than the current one.
    private static let gregorian = TaskCalendar.gregorian(
        timeZone: TimeZone(secondsFromGMT: 0)!)

    /// Same ceiling the task parser uses, for the same reason: diagnostics
    /// live in the index for as long as the note does and each carries a
    /// sentence, so a pathological file must not keep one per line in memory
    /// for the whole session.
    static let maximumDiagnosticsPerNote = 20

    // MARK: - Scanning

    static func subscriptions(in text: String) -> [ParsedSubscription] {
        scan(in: text).subscriptions
    }

    static func scan(in text: String) -> ScanResult {
        let document = MarkdownContextScanner.scan(text)
        var subscriptions: [ParsedSubscription] = []
        var diagnostics: [Diagnostic] = []
        var category: String?

        for line in document.lines {
            guard !line.isLiteral else { continue }

            if let heading = TaskListDocument.headingName(in: line.text) {
                category = heading.isEmpty ? nil : heading
                continue
            }

            let ns = line.text as NSString
            let wholeLine = NSRange(location: 0, length: ns.length)
            if let match = subscriptionLineRegex.firstMatch(
                in: line.text, range: wholeLine)
            {
                if let parsed = parsed(
                    match,
                    line: line,
                    category: category,
                    diagnostics: &diagnostics)
                {
                    subscriptions.append(parsed)
                }
                continue
            }

            if candidateRegex.firstMatch(in: line.text, range: wholeLine) != nil {
                append(
                    Diagnostic(
                        kind: .malformedSubscription,
                        lineNumber: line.number,
                        message:
                            "This looks like a subscription but Cove could not read it. Expected “- Name @cost(0.00 USD) @every(month) @since(2026-01-01)”."
                    ),
                    to: &diagnostics)
            }
        }

        var firstByKey: [SemanticKey: ParsedSubscription] = [:]
        for subscription in subscriptions {
            let key = semanticKey(for: subscription)
            if firstByKey[key] != nil {
                append(
                    Diagnostic(
                        kind: .duplicateSubscription,
                        lineNumber: subscription.lineNumber,
                        message:
                            "This subscription has the same name, cost, cycle, and start date as another, so edits are disabled until one is made distinct."
                    ),
                    to: &diagnostics)
            } else {
                firstByKey[key] = subscription
            }
        }

        return ScanResult(
            subscriptions: subscriptions,
            diagnostics: Array(diagnostics.prefix(maximumDiagnosticsPerNote)))
    }

    /// Every `##` heading in the note, in file order — the categories, whether
    /// or not anything sits under them yet.
    static func categoryNames(in text: String) -> [String] {
        TaskListDocument.sectionNames(in: text)
    }

    private static func parsed(
        _ match: NSTextCheckingResult,
        line: MarkdownContextScanner.Line,
        category: String?,
        diagnostics: inout [Diagnostic]
    ) -> ParsedSubscription? {
        let ns = line.text as NSString
        let name = ns.substring(with: match.range(at: 1))

        guard
            let amount = Decimal(
                string: ns.substring(with: match.range(at: 2)),
                locale: Locale(identifier: "en_US_POSIX"))
        else {
            append(
                Diagnostic(
                    kind: .malformedSubscription,
                    lineNumber: line.number,
                    message: "This subscription's cost could not be read."),
                to: &diagnostics)
            return nil
        }
        let cost = Money(
            amount: amount,
            currencyCode: ns.substring(with: match.range(at: 3)))

        let cycleText = ns.substring(with: match.range(at: 4))
        guard let cycle = BillingCycle(tagText: cycleText) else {
            append(
                Diagnostic(
                    kind: .unsupportedCycle,
                    lineNumber: line.number,
                    message:
                        "“\(cycleText)” is not a billing cycle. Use month, year, week, day, or “3 months”."
                ),
                to: &diagnostics)
            return nil
        }

        let year = Int(ns.substring(with: match.range(at: 5)))!
        let month = Int(ns.substring(with: match.range(at: 6)))!
        let day = Int(ns.substring(with: match.range(at: 7)))!
        let firstChargeDateString = String(
            format: "%04d-%02d-%02d", year, month, day)
        guard
            DateComponents(year: year, month: month, day: day)
                .isValidDate(in: gregorian)
        else {
            append(
                Diagnostic(
                    kind: .impossibleDate,
                    lineNumber: line.number,
                    message: "\(firstChargeDateString) is not a real date."),
                to: &diagnostics)
            return nil
        }

        var status = SubscriptionStatus.active
        let statusRange = match.range(at: 8)
        if statusRange.location != NSNotFound {
            let raw = ns.substring(with: statusRange).lowercased()
            guard let parsedStatus = SubscriptionStatus(rawValue: raw) else {
                append(
                    Diagnostic(
                        kind: .unsupportedStatus,
                        lineNumber: line.number,
                        message:
                            "“\(ns.substring(with: statusRange))” is not a status. Use paused or cancelled, or remove the tag."
                    ),
                    to: &diagnostics)
                return nil
            }
            status = parsedStatus
        }

        return ParsedSubscription(
            lineNumber: line.number,
            sourceLine: line.text + line.lineEnding,
            lineRange: line.range,
            enclosingRange: line.enclosingRange,
            name: name,
            cost: cost,
            cycle: cycle,
            firstChargeDateString: firstChargeDateString,
            status: status,
            category: category)
    }

    private static func append(_ diagnostic: Diagnostic, to diagnostics: inout [Diagnostic]) {
        guard diagnostics.count < maximumDiagnosticsPerNote else { return }
        diagnostics.append(diagnostic)
    }

    private static func semanticKey(for parsed: ParsedSubscription) -> SemanticKey {
        SemanticKey(
            name: parsed.name,
            amount: parsed.cost.amount,
            currencyCode: parsed.cost.currencyCode,
            cycleTag: parsed.cycle.tagText,
            firstChargeDateString: parsed.firstChargeDateString,
            category: parsed.category.map(TaskListDocument.canonicalName))
    }

    private static func semanticKey(for identity: SubscriptionIdentity) -> SemanticKey {
        SemanticKey(
            name: identity.name,
            amount: identity.costAmount,
            currencyCode: identity.currencyCode,
            cycleTag: identity.cycleTag,
            firstChargeDateString: identity.firstChargeDateString,
            category: identity.canonicalCategory)
    }

    // MARK: - Identity and mutation

    /// Re-finds a subscription by meaning rather than by line number, and
    /// reports ambiguity rather than resolving it.
    ///
    /// Falling back to "the first line that looks like this" is the one place
    /// being helpful is wrong: after an external edit shifts the lines, the
    /// first match is not necessarily the row the user tapped.
    static func matchResult(
        for identity: SubscriptionIdentity,
        in fileText: String
    ) -> MatchResult {
        let key = semanticKey(for: identity)
        let candidates = subscriptions(in: fileText).filter {
            semanticKey(for: $0) == key
        }
        switch candidates.count {
        case 0: return .missing
        case 1: return .matched(candidates[0])
        default: return .ambiguous(candidates)
        }
    }

    static func matching(
        _ identity: SubscriptionIdentity,
        in fileText: String
    ) throws -> ParsedSubscription {
        switch matchResult(for: identity, in: fileText) {
        case .matched(let parsed):
            return parsed
        case .missing:
            throw MutationError.subscriptionMissing
        case .ambiguous(let candidates):
            throw MutationError.ambiguousSubscription(candidates.map(\.lineNumber))
        }
    }

    /// Replaces one subscription's line with `line`, which the caller has
    /// already round-tripped through `SubscriptionDraft.validatedMarkdownLine`.
    static func replacingSubscriptionResult(
        _ identity: SubscriptionIdentity,
        with line: String,
        in fileText: String
    ) throws -> String {
        guard isValidSingleLine(line) else { throw MutationError.invalidLine }
        let parsed = try matching(identity, in: fileText)
        return (fileText as NSString)
            .replacingCharacters(in: parsed.lineRange, with: line)
    }

    /// One removal: the text left behind and the line that left it.
    struct SubscriptionRemoval: Equatable, Sendable {
        let text: String
        let removed: ParsedSubscription
    }

    /// Removes one subscription's whole line and reports what was removed.
    ///
    /// Status, the bullet character, and interior spacing are all outside the
    /// semantic key, so the line a removal finds is not necessarily the one
    /// the index last saw. Undo restores bytes, so the bytes have to come from
    /// the same coordinated read the removal was computed against.
    static func removingSubscriptionWithRecordResult(
        _ identity: SubscriptionIdentity,
        in fileText: String
    ) throws -> SubscriptionRemoval {
        let parsed = try matching(identity, in: fileText)
        return SubscriptionRemoval(
            text: (fileText as NSString)
                .replacingCharacters(in: parsed.enclosingRange, with: ""),
            removed: parsed)
    }

    /// Removes one subscription's whole line, terminator included.
    static func removingSubscriptionResult(
        _ identity: SubscriptionIdentity,
        in fileText: String
    ) throws -> String {
        try removingSubscriptionWithRecordResult(identity, in: fileText).text
    }

    static func isValidSingleLine(_ line: String) -> Bool {
        !line.isEmpty
            && line.rangeOfCharacter(from: .newlines) == nil
            && line.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
    }
}
