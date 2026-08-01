import Foundation

enum SubscriptionDraftValidationIssue: Equatable, Sendable {
    case emptyName
    case unsafeName
    case negativeAmount
    case unwritableAmount(String)
    case invalidCurrencyCode(String)
    case invalidDate(String)
    case unwritableLine

    var message: String {
        switch self {
        case .emptyName:
            return "A subscription needs a name."
        case .unsafeName:
            return
                "This name has spacing Cove would have to change to write it down. Adjust it first."
        case .negativeAmount:
            return "A cost cannot be negative."
        case .unwritableAmount(let amount):
            return
                "A cost is stored with at most two decimal places, so \(amount) cannot be recorded exactly. Round it first."
        case .invalidCurrencyCode(let code):
            return "“\(code)” is not a three-letter currency code."
        case .invalidDate(let date):
            return "\(date) is not a real date."
        case .unwritableLine:
            return
                "Cove could not write this subscription as a line it can read back. Adjust the name."
        }
    }
}

struct SubscriptionDraftValidationError: LocalizedError, Equatable, Sendable {
    let issues: [SubscriptionDraftValidationIssue]

    var errorDescription: String? {
        issues.first?.message ?? "This subscription could not be written down."
    }
}

/// What the form sheet edits, and the one place a subscription's Markdown line
/// is generated.
///
/// It mirrors `TaskDraft`: the fields, the validation issues a UI can show
/// before anything is written, and a throwing `validatedMarkdownLine()` that
/// every storage boundary calls. The generated line is parsed back before it is
/// returned, so a line that Cove could not read is never a line Cove writes.
struct SubscriptionDraft: Equatable, Sendable {
    var name: String
    var amount: Decimal
    var currencyCode: String
    var cycle: BillingCycle
    /// The first charge date, `YYYY-MM-DD` — the series anchor.
    var firstChargeDateString: String
    var status: SubscriptionStatus

    init(
        name: String = "",
        amount: Decimal = 0,
        currencyCode: String = SubscriptionDraft.defaultCurrencyCode,
        cycle: BillingCycle = .monthly,
        firstChargeDateString: String,
        status: SubscriptionStatus = .active
    ) {
        self.name = name
        self.amount = amount
        self.currencyCode = currencyCode
        self.cycle = cycle
        self.firstChargeDateString = firstChargeDateString
        self.status = status
    }

    /// The reader's own currency where the system knows it. A guess the user
    /// can change, not a constraint — every amount carries its code.
    static var defaultCurrencyCode: String {
        Locale.current.currency?.identifier.uppercased() ?? "USD"
    }

    init(_ subscription: Subscription) {
        self.init(
            name: subscription.name,
            amount: subscription.cost.amount,
            currencyCode: subscription.cost.currencyCode,
            cycle: subscription.cycle,
            firstChargeDateString: subscription.firstChargeDateString,
            status: subscription.status)
    }

    /// A one-line name safe to place before Cove's reserved tags. Control
    /// characters become spaces and a literal tag opener gains a space before
    /// its `(`, so it stays name text on the next parse rather than being read
    /// as the tag it imitates.
    var sanitizedName: String {
        var result = ""
        let space = Unicode.Scalar(0x20)!
        for scalar in name.unicodeScalars {
            result.unicodeScalars.append(
                CharacterSet.controlCharacters.contains(scalar) ? space : scalar)
        }
        for tag in ["@cost(", "@every(", "@since(", "@status("] {
            result = result.replacingOccurrences(
                of: tag,
                with: String(tag.dropLast()) + " (",
                options: .caseInsensitive)
        }
        return
            result
            .replacingOccurrences(
                of: #"[ \t]+"#, with: " ", options: .regularExpression
            )
            .trimmingCharacters(in: .whitespaces)
    }

    var normalizedCurrencyCode: String { currencyCode.uppercased() }

    var cost: Money {
        Money(amount: amount, currencyCode: normalizedCurrencyCode)
    }

    var validationIssues: [SubscriptionDraftValidationIssue] {
        var issues: [SubscriptionDraftValidationIssue] = []
        if sanitizedName.isEmpty { issues.append(.emptyName) }
        if name.trimmingCharacters(in: .whitespaces) != sanitizedName {
            issues.append(.unsafeName)
        }
        if amount < 0 {
            issues.append(.negativeAmount)
        } else if !Self.isWritableAmount(amount) {
            issues.append(.unwritableAmount("\(amount)"))
        }
        if !Self.isValidCurrencyCode(normalizedCurrencyCode) {
            issues.append(.invalidCurrencyCode(currencyCode))
        }
        if TaskCalendar.dateComponents(from: firstChargeDateString)?
            .isValidDate(in: Self.gregorian) != true
        {
            issues.append(.invalidDate(firstChargeDateString))
        }
        return issues
    }

    /// The canonical line, or the reason it cannot be written.
    ///
    /// The result is parsed back before it is returned. That is not belt and
    /// braces — it is the project's fixed rule that every generated line
    /// round-trips through the parser, and it is what makes the writer and the
    /// reader impossible to drift apart.
    func validatedMarkdownLine() throws -> String {
        let issues = validationIssues
        guard issues.isEmpty else {
            throw SubscriptionDraftValidationError(issues: issues)
        }

        var line = "- \(sanitizedName)"
        line += " @cost(\(cost.tagValue))"
        line += " @every(\(cycle.tagText))"
        line += " @since(\(firstChargeDateString))"
        if let statusTag = status.tagValue {
            line += " @status(\(statusTag))"
        }

        let parsed = SubscriptionParser.subscriptions(in: line)
        guard parsed.count == 1,
            parsed[0].name == sanitizedName,
            parsed[0].cost == cost,
            parsed[0].cycle == cycle,
            parsed[0].firstChargeDateString == firstChargeDateString,
            parsed[0].status == status
        else {
            throw SubscriptionDraftValidationError(issues: [.unwritableLine])
        }
        return line
    }

    // MARK: - Validation helpers

    private static let gregorian = TaskCalendar.gregorian(
        timeZone: TimeZone(secondsFromGMT: 0)!)

    private static let writableAmountRegex = try! NSRegularExpression(
        pattern: #"^\d{1,12}(?:\.\d{1,2})?$"#)

    /// Whether the canonical two-decimal rendering of `amount` is a value the
    /// line grammar accepts *and* reads back unchanged. Anything with more
    /// precision than the currency can hold, or more digits than the format
    /// allows, is refused rather than silently rounded — a cost quietly
    /// changing by a cent on save is worse than being told to fix it.
    static func isWritableAmount(_ amount: Decimal) -> Bool {
        let rendered = Money.canonicalAmountString(amount)
        let range = NSRange(location: 0, length: (rendered as NSString).length)
        guard
            writableAmountRegex.firstMatch(in: rendered, range: range) != nil,
            let roundTripped = Decimal(
                string: rendered, locale: Locale(identifier: "en_US_POSIX"))
        else { return false }
        return roundTripped == amount
    }

    static func isValidCurrencyCode(_ code: String) -> Bool {
        code.count == 3
            && code.unicodeScalars.allSatisfy {
                ("A"..."Z").contains(Character($0))
            }
    }
}
