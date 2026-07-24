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

/// The warm card every header sits on: surface, a wash of ember off the top
/// corner, a hairline, and a shadow. Shared by `CoveMasthead` and `CovePanel`
/// so an introducing header and a working one read as the same material.
struct CoveMastheadBackground: View {
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

/// The introducing header: the card the vault browser opens with, carrying a
/// title that says something a person can't read anywhere else on the screen —
/// the greeting at the root, the folder's own name a level down.
///
/// It no longer takes a trailing accessory. The two screens that passed one
/// were the capture screens, and they moved to `CovePanel`, where a count
/// badge sits beside a one-line label instead of beside a serif title.
struct CoveMasthead<Content: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: CoveTheme.Space.regular) {
            heading
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

/// The working header: one label line and the thing the screen is actually
/// for, on the same card as a masthead but without the serif title and the
/// sentence under it.
///
/// A masthead earns its height when its title says something that *changes* —
/// the greeting at the vault root, the name of the folder you pushed into. A
/// fixed slogan does not: "Write it, naturally" and the syntax hint below it
/// were read once and then paid for on every launch, and on the app's landing
/// screen they pushed the first real task most of the way down the display.
/// Quick capture and the lists overview use this instead, so the field and the
/// figures start near the top where they belong.
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
        .background { CoveMastheadBackground() }
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
