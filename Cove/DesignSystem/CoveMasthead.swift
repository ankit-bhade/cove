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

private struct CoveMastheadBackground: View {
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

/// The shared header card at the top of every main screen.
struct CoveMasthead<Trailing: View, Content: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: CoveTheme.Space.regular) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CoveTheme.Space.snug) {
                    heading
                    trailing()
                }
            } else {
                HStack(alignment: .top, spacing: CoveTheme.Space.snug) {
                    heading
                    Spacer(minLength: 0)
                    trailing()
                }
            }
            content()
        }
        .padding(CoveTheme.Space.loose - 2)
        .background { CoveMastheadBackground() }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule()
                .fill(CoveTheme.accent)
                .frame(width: 24, height: 2)
                .padding(.bottom, 3)
                .accessibilityHidden(true)
            Text(eyebrow)
                .coveEyebrow()
            Text(title)
                .font(.coveDisplay)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension CoveMasthead where Trailing == EmptyView {
    init(
        eyebrow: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            trailing: { EmptyView() },
            content: content
        )
    }
}

extension CoveMasthead where Trailing == EmptyView, Content == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
            trailing: { EmptyView() },
            content: { EmptyView() }
        )
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
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: CoveTheme.Space.tight) {
            Text(title)
                .coveEyebrow(tint: tint)
            if let count {
                Text(count, format: .number)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint ?? .secondary)
                    .opacity(0.65)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .accessibilityElement(children: .combine)
    }
}

extension CoveSectionHeader where Trailing == EmptyView {
    init(_ title: String, count: Int? = nil, tint: Color? = nil) {
        self.init(title: title, count: count, tint: tint) { EmptyView() }
    }
}
