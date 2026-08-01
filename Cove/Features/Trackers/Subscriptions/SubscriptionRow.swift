import SwiftUI

/// One recurring charge, on the app's shared row grid.
///
/// It follows `TaskRow`'s split rather than `CoveRowTitle`'s, and for the same
/// reason: this is a name with a line *about* it, not a label with a tag under
/// it. So the name is regular where a folder or list title is medium, which is
/// what keeps the summary under it reading as a subtitle instead of clumping
/// into one block with it.
struct SubscriptionRow: View {
    let subscription: Subscription
    let now: Date
    /// Off inside a category's own section, where the heading already says it.
    var showsCategory = false

    @ScaledMetric(relativeTo: .body) private var glyphColumn: CGFloat =
        CoveTheme.Space.rowGlyph

    var body: some View {
        HStack(alignment: .top, spacing: CoveTheme.Space.rowGap) {
            CoveIconTile(systemName: glyph, tint: tint)
                .frame(width: glyphColumn)
            VStack(alignment: .leading, spacing: 4) {
                Text(subscription.name)
                    .font(.body)
                    .lineLimit(2)
                    .strikethrough(subscription.status == .cancelled)
                    .foregroundStyle(
                        subscription.countsTowardSpending ? .primary : .secondary)
                CoveDueLabel(
                    text: summary.details,
                    clause: summary.clause,
                    clauseTint: clauseTint)
                if showsCategory, let category = subscription.category {
                    CoveListLabel(category)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer(minLength: CoveTheme.Space.tight)
            monthlyEquivalent
        }
        .padding(.vertical, CoveTheme.Space.rowPadding)
        .accessibilityElement(children: .combine)
    }

    /// The per-month figure every row is comparable on, which is the whole
    /// reason a yearly charge and a monthly one can sit in one list. It is
    /// quiet: it is context for the cost in the line above, not a second
    /// headline.
    private var monthlyEquivalent: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(
                SubscriptionPresentation.money(
                    SubscriptionMath.monthlyEquivalent(subscription),
                    currencyCode: subscription.cost.currencyCode)
            )
            .font(.subheadline.weight(.medium).monospacedDigit())
            .foregroundStyle(
                subscription.countsTowardSpending ? .primary : .secondary)
            Text("/mo")
                .coveMetaLabel()
        }
        .lineLimit(1)
        .opacity(subscription.countsTowardSpending ? 1 : 0.6)
        .accessibilityLabel(
            "\(SubscriptionPresentation.money(SubscriptionMath.monthlyEquivalent(subscription), currencyCode: subscription.cost.currencyCode)) per month"
        )
    }

    private var summary: (details: String, clause: String?) {
        SubscriptionPresentation.summaryParts(for: subscription, on: now)
    }

    /// Lateness is the one thing a task row raises its voice for; here it is a
    /// charge landing today or tomorrow — the same idea pointed forward, and
    /// narrowed to what a reader can still do something about.
    ///
    /// Nil leaves the clause at the line's own tint, which is the ordinary
    /// case: most of the list is not about to be charged.
    private var clauseTint: Color? {
        guard subscription.countsTowardSpending,
            let next = SubscriptionMath.nextChargeDateString(
                for: subscription, on: now),
            SubscriptionPresentation.isRenewingNow(next, today: now)
        else { return nil }
        return CoveTheme.accent
    }

    private var glyph: String {
        switch subscription.status {
        case .active: "creditcard"
        case .paused: "pause"
        case .cancelled: "xmark"
        }
    }

    private var tint: Color {
        subscription.countsTowardSpending ? CoveTheme.accent : .secondary
    }
}
