import Charts
import SwiftUI

/// The two charts on the subscriptions screen.
///
/// **Both are single-hue ember bars, and neither is a pie.** The palette
/// allows one accent, moss for containers, and rust for lateness — nothing
/// else gets a colour. A pie needs one hue per slice, so at eight
/// subscriptions it needs eight, and inventing a categorical ramp would be the
/// second bright hue this design system deliberately does without. A bar chart
/// ranked by value says what a pie says and says it better: length is the one
/// encoding people read accurately, where slice angle is the one they read
/// worst.
///
/// Depth is carried by opacity against each bar's own share, which is the same
/// single-hue trick `coveTintedSurface` uses everywhere else.
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

/// What each of the next twelve months actually costs.
///
/// This is the chart that earns its place. A flat "per month" average hides
/// that a yearly charge contributes nothing to eleven months and its whole
/// price to one — so the month the annual renewals land in is invisible in
/// every other figure on the screen, and it is the one worth knowing about.
struct SubscriptionProjectionChart: View {
    let buckets: [SubscriptionMath.MonthBucket]
    let currencyCode: String
    let timeZone: TimeZone

    private var maximum: Decimal {
        buckets.map(\.total).max() ?? 0
    }

    private func date(for bucket: SubscriptionMath.MonthBucket) -> Date? {
        SubscriptionMath.date(
            from: bucket.monthStartDateString, timeZone: timeZone)
    }

    var body: some View {
        Chart(buckets) { bucket in
            if let date = date(for: bucket) {
                BarMark(
                    x: .value("Month", date, unit: .month),
                    y: .value("Charged", SubscriptionChartStyle.double(bucket.total))
                )
                .foregroundStyle(
                    CoveTheme.accent.opacity(
                        SubscriptionChartStyle.opacity(
                            for: bucket.total, of: maximum))
                )
                .cornerRadius(3)
                .accessibilityLabel(
                    date.formatted(.dateTime.month(.wide).year()))
                .accessibilityValue(
                    SubscriptionPresentation.money(
                        bucket.total, currencyCode: currencyCode))
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month, count: 3)) { value in
                AxisGridLine().foregroundStyle(CoveTheme.hairline)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(.dateTime.month(.abbreviated)))
                            .coveEyebrow()
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
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
        .frame(height: 170)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Charges over the next twelve months")
    }
}
