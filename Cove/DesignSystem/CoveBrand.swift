import SwiftUI

/// The app's in-product mark: a serif `c` cupping a single ember dot.
struct CoveMark: View {
    var size: CGFloat = 34

    @Environment(\.colorScheme) private var scheme

    private let paperGround = Color(red: 0.965, green: 0.953, blue: 0.933)
    private let nightTop = Color(red: 0.133, green: 0.114, blue: 0.094)
    private let nightBottom = Color(red: 0.078, green: 0.067, blue: 0.055)
    private let ink = Color(red: 0.141, green: 0.129, blue: 0.114)
    private let paper = Color(red: 0.976, green: 0.961, blue: 0.933)
    private let emberTop = Color(red: 0.910, green: 0.659, blue: 0.408)
    private let emberBottom = Color(red: 0.788, green: 0.478, blue: 0.204)
    private let markScale: CGFloat = 1.08

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .fill(ground)
            Text(verbatim: "c")
                .font(.system(size: size * 0.74 * markScale, weight: .bold, design: .serif))
                .foregroundStyle(isDark ? paper : ink)
                .offset(x: -size * 0.085 * markScale, y: -size * 0.10 * markScale)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [emberTop, emberBottom],
                        center: .init(x: 0.38, y: 0.34),
                        startRadius: 0,
                        endRadius: size * 0.16 * markScale * 0.62
                    )
                )
                .frame(width: size * 0.16 * markScale, height: size * 0.16 * markScale)
                .offset(x: size * 0.13 * markScale, y: size * 0.05 * markScale)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var ground: AnyShapeStyle {
        isDark
            ? AnyShapeStyle(
                LinearGradient(
                    colors: [nightTop, nightBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            : AnyShapeStyle(paperGround)
    }
}

/// Branded backdrop for first-launch, recovery, and loading states.
struct CoveBrandBackground: View {
    var body: some View {
        ZStack {
            CoveTheme.canvas
            RadialGradient(
                colors: [CoveTheme.accent.opacity(0.16), .clear],
                center: .init(x: 0.14, y: 0.04),
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [CoveTheme.moss.opacity(0.10), .clear],
                center: .init(x: 0.92, y: 1.02),
                startRadius: 0,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}
