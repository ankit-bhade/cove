import SwiftUI

/// Cove's small, dependency-free visual system. The palette is derived from
/// the moon-and-waves app icon so every screen feels part of the same product.
enum CoveTheme {
    static let navy = Color(red: 0.055, green: 0.207, blue: 0.320)
    static let deepTeal = Color(red: 0.055, green: 0.365, blue: 0.430)
    static let teal = Color(red: 0.129, green: 0.529, blue: 0.612)
    static let seaGlass = Color(red: 0.510, green: 0.710, blue: 0.750)

    static let brandGradient = LinearGradient(
        colors: [navy, deepTeal, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.035, green: 0.055, blue: 0.070)
            : Color(red: 0.955, green: 0.975, blue: 0.975)
    }

    static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.075, green: 0.100, blue: 0.115)
            : .white
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.09) : navy.opacity(0.10)
    }
}

/// A reusable raised surface used for dashboard-style cards.
struct CoveCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CoveTheme.surface(for: colorScheme))
            .shadow(color: CoveTheme.navy.opacity(colorScheme == .dark ? 0.14 : 0.08),
                    radius: 18, y: 8)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CoveTheme.border(for: colorScheme), lineWidth: 1)
            }
    }
}

/// Compact branded icon treatment shared by rows and settings sections.
struct CoveIconTile: View {
    let systemName: String
    var tint: Color = CoveTheme.teal

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9,
                                                                 style: .continuous))
    }
}

/// Branded backdrop for first-launch, recovery, and loading states.
struct CoveBrandBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            CoveTheme.canvas(for: colorScheme)
            Circle()
                .fill(CoveTheme.seaGlass.opacity(colorScheme == .dark ? 0.08 : 0.16))
                .frame(width: 420, height: 420)
                .offset(x: -190, y: -260)
            Circle()
                .fill(CoveTheme.teal.opacity(colorScheme == .dark ? 0.08 : 0.12))
                .frame(width: 340, height: 340)
                .offset(x: 210, y: 300)
        }
        .ignoresSafeArea()
    }
}
