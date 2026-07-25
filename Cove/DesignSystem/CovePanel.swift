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
        VStack(alignment: .leading, spacing: CoveTheme.Space.snug + 2) {
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
        .padding(CoveTheme.Space.regular)
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
    let value: Int
    let label: String

    var id: String { label }

    init(_ value: Int, _ label: String) {
        self.value = value
        self.label = label
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
            Text(stat.value, format: .number)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(stat.label)
                .coveEyebrow()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stat.value) \(stat.label)")
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
