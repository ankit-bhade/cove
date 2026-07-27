import SwiftUI

/// A raised surface: warm fill, hairline edge, and a shadow soft enough to
/// suggest paper rather than a floating panel.
struct CoveCardBackground: View {
    var cornerRadius: CGFloat = CoveTheme.cardRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CoveTheme.surface)
            .shadow(color: CoveTheme.ink.opacity(0.06), radius: 14, y: 6)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CoveTheme.hairline, lineWidth: 1)
            }
    }
}

/// The warm card a panel sits on: surface, a wash of ember off the top
/// corner, a hairline, and a shadow.
private struct CovePanelBackground: View {
    var cornerRadius: CGFloat = CoveTheme.cardRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CoveTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                CoveTheme.accent.opacity(0.10),
                                CoveTheme.accent.opacity(0.02),
                                .clear,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CoveTheme.hairline, lineWidth: 1)
            }
            .shadow(color: CoveTheme.ink.opacity(0.07), radius: 16, y: 7)
    }
}

/// The header every main screen opens with: one label line and the thing the
/// screen is actually for.
///
/// This replaced a taller masthead — accent rule, eyebrow, serif title, and a
/// sentence of prose — that every screen carried. None of the titles said
/// anything the screen didn't: a slogan ("Write it, naturally") is read once
/// and then paid for on every launch, and a greeting is about the reader
/// rather than about the folder they came to look at. Below them the syntax
/// hints and reassurances repeated what the field's own placeholder said. On
/// the landing screen that stack pushed the first real task most of the way
/// down the display.
///
/// What survives is what a header can carry that nothing else on the screen
/// does: the label of the card, a count badge, and the app's one ornament.
struct CovePanel<Trailing: View, Content: View>: View {
    let eyebrow: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: CoveTheme.Space.snug) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CoveTheme.Space.snug) {
                    label
                    trailing()
                }
            } else {
                HStack(spacing: CoveTheme.Space.snug) {
                    label
                    Spacer(minLength: 0)
                    trailing()
                }
            }
            content()
        }
        // A point tighter than the app's regular inset. The panel is the one
        // card that sits above every screen's content rather than in it, so
        // its padding is paid on every launch and on every tab switch — and on
        // the landing screen it is the difference between the fifth task being
        // visible and being implied.
        .padding(CoveTheme.Space.regular - 3)
        .background { CovePanelBackground() }
    }

    /// The app's one repeated ornament, kept inline here rather than stacked
    /// above the label: a compact card has no room for a rule on its own line.
    private var label: some View {
        HStack(spacing: CoveTheme.Space.snug - 2) {
            Capsule()
                .fill(CoveTheme.accent)
                .frame(width: 14, height: 2)
                .accessibilityHidden(true)
            Text(eyebrow)
                .coveEyebrow()
        }
    }
}

extension CovePanel where Trailing == EmptyView {
    init(eyebrow: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(eyebrow: eyebrow, trailing: { EmptyView() }, content: content)
    }
}

struct CoveStat: Identifiable {
    /// Already-formatted, because not every figure a panel reports is a
    /// count: a currency total carries its own symbol and fraction digits and
    /// has to be formatted in the reader's locale before it gets here.
    let text: String
    let label: String
    /// Counts animate between values; a formatted string does too, and the
    /// transition is the same one either way.
    let value: Int?

    var id: String { label }

    init(_ value: Int, _ label: String) {
        self.text = value.formatted(.number)
        self.label = label
        self.value = value
    }

    init(_ text: String, _ label: String) {
        self.text = text
        self.label = label
        self.value = nil
    }
}

struct CoveStatStrip: View {
    let stats: [CoveStat]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: CoveTheme.Space.regular) {
            Rectangle()
                .fill(CoveTheme.hairline)
                .frame(height: 1)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CoveTheme.Space.snug) {
                    ForEach(stats) { stat in figure(stat) }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        ForEach(stats) { stat in figure(stat) }
                    }
                    VStack(alignment: .leading, spacing: CoveTheme.Space.snug) {
                        ForEach(stats) { stat in figure(stat) }
                    }
                }
            }
        }
    }

    private func figure(_ stat: CoveStat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stat.text)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(stat.label)
                .coveMetaLabel()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stat.text) \(stat.label)")
    }
}

struct CoveSectionHeader<Trailing: View>: View {
    let title: String
    var count: Int?
    var tint: Color?
    /// When present, the header *is* the control that folds its section away,
    /// and it carries a chevron saying so.
    ///
    /// SwiftUI's own `Section(isExpanded:)` is the obvious way to do this and
    /// is the wrong one here: outside `.sidebar` list style it draws no
    /// disclosure control and takes no taps, so an inset-grouped section built
    /// that way starts collapsed and can never be opened. The header owns the
    /// affordance instead, which also means the behavior is identical on
    /// macOS rather than iOS-only.
    var isExpanded: Binding<Bool>?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: CoveTheme.Space.tight) {
            if let isExpanded {
                // The whole header is the control — label, the space after it,
                // and the chevron at the trailing edge. A collapsible section
                // carries no other action, which is what lets this be one
                // button rather than a pair with something wedged between
                // them: a caption-sized chevron is a poor thing to aim at on
                // its own.
                Button {
                    toggle(isExpanded)
                } label: {
                    HStack(spacing: CoveTheme.Space.tight) {
                        label
                        Spacer(minLength: 0)
                        chevron(isExpanded: isExpanded.wrappedValue)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .padding(.vertical, -10)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
                .accessibilityHint(
                    isExpanded.wrappedValue ? "Hides these rows" : "Shows these rows")
                trailing()
            } else {
                label
                Spacer(minLength: 0)
                trailing()
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// A header's text is a few points tall and the gap around it belongs to
    /// the section, so the target above is grown into that gap and the growth
    /// then given back to the layout — the row keeps the height an ordinary
    /// header has, which is the whole point of there being one header.
    private func toggle(_ isExpanded: Binding<Bool>) {
        withAnimation(.snappy) { isExpanded.wrappedValue.toggle() }
    }

    private var label: some View {
        HStack(spacing: CoveTheme.Space.tight) {
            Text(title)
                .coveEyebrow(tint: tint)
            if let count {
                Text(count, format: .number)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint ?? .secondary)
                    .opacity(0.65)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Points right when the section is closed and down when it is open, the
    /// way a disclosure does everywhere else on the platform.
    private func chevron(isExpanded: Bool) -> some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint ?? .secondary)
            .opacity(0.65)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .accessibilityHidden(true)
    }
}

extension View {
    /// Places a section heading as a **row inside** one continuous list
    /// surface, rather than above a card of its own.
    ///
    /// An inset-grouped `Section` draws its own rounded card, so a screen with
    /// four groups is four soft capsules stacked inside the platform's own
    /// rounded chrome — card inside card — and each gap between them costs a
    /// row of what fits above the fold. Where a screen's groups are all the
    /// same kind of thing partitioned by one rule (task rows split by day),
    /// they belong on one surface with the headings dividing it. Where they
    /// are genuinely different things (a chart, then upcoming charges, then
    /// categories), separate sections are still right.
    func coveGroupHeaderRow(isFirst: Bool = false, isLast: Bool = false) -> some View {
        self
            .listRowInsets(CoveTheme.groupHeaderRowInsets(isFirst: isFirst, isLast: isLast))
            // The space above the heading is what divides one group from the
            // next; a hairline as well would put a rule through a surface
            // whose whole point is that it is continuous.
            .listRowSeparator(.hidden)
    }
}

extension CoveSectionHeader where Trailing == EmptyView {
    init(
        _ title: String,
        count: Int? = nil,
        tint: Color? = nil,
        isExpanded: Binding<Bool>? = nil
    ) {
        self.init(title: title, count: count, tint: tint, isExpanded: isExpanded) {
            EmptyView()
        }
    }
}
