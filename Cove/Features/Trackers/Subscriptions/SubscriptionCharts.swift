import Charts
import SwiftUI

/// The subscriptions screen's one chart.
///
/// **Single-hue ember bars, and not a pie.** The palette allows one accent,
/// moss for containers, and rust for lateness — nothing else gets a colour. A
/// pie needs one hue per slice, so at eight subscriptions it needs eight, and
/// inventing a categorical ramp would be the second bright hue this design
/// system deliberately does without. A bar chart ranked by value says what a
/// pie says and says it better: length is the one encoding people read
/// accurately, where slice angle is the one they read worst.
///
/// Depth is carried by opacity against each bar's own share, which is the same
/// single-hue trick `coveTintedSurface` uses everywhere else.
///
/// A twelve-month projection chart shipped beside this one and was removed:
/// what a month *will* cost is a different question from what a subscription
/// costs, and only the second one was wanted here.
enum SubscriptionChartStyle {
    /// The floor keeps the smallest bar a visible ember rather than a ghost.
    static func opacity(for value: Decimal, of maximum: Decimal) -> Double {
        guard maximum > 0 else { return 1 }
        let share = (value as NSDecimalNumber).doubleValue
            / (maximum as NSDecimalNumber).doubleValue
        return 0.45 + 0.55 * min(max(share, 0), 1)
    }

    static func double(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }

    /// An axis amount with no fraction digits.
    ///
    /// Deliberately not `.notation(.compactName)` — the "$1.5K" form is macOS
    /// 15 and up, and Cove's floor is macOS 14. Whole units in the reader's
    /// own locale are the version that works on every supported target, and at
    /// four axis marks they are short enough anyway.
    static func axisAmount(_ amount: Double, currencyCode: String) -> String {
        amount.formatted(
            .currency(code: currencyCode).precision(.fractionLength(0)))
    }
}

/// What each subscription costs per month, largest first.
struct SubscriptionSpendChart: View {
    let bars: [SubscriptionMath.SpendBar]
    let currencyCode: String

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 28

    private var maximum: Decimal {
        bars.map(\.monthly).max() ?? 0
    }

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Per month", SubscriptionChartStyle.double(bar.monthly)),
                y: .value("Subscription", bar.label)
            )
            .foregroundStyle(
                CoveTheme.accent.opacity(
                    bar.isRemainder
                        ? 0.35
                        : SubscriptionChartStyle.opacity(
                            for: bar.monthly, of: maximum))
            )
            .cornerRadius(4)
            .accessibilityLabel(bar.label)
            .accessibilityValue(
                "\(SubscriptionPresentation.money(bar.monthly, currencyCode: currencyCode)) per month"
            )
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(CoveTheme.hairline)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(
                            SubscriptionChartStyle.axisAmount(
                                amount, currencyCode: currencyCode)
                        )
                        .coveEyebrow()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading) { value in
                AxisValueLabel(horizontalSpacing: 8) {
                    // Plain secondary rather than tracked capitals: these are
                    // names a person chose, and uppercasing "Disney+" turns it
                    // into a label rather than the thing it is.
                    if let name = value.as(String.self) {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(height: rowHeight * CGFloat(max(bars.count, 1)) + 28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Monthly cost by subscription")
    }
}
