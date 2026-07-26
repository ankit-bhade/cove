import SwiftUI

/// The app's in-product mark: a bay cut into the land's edge, the shoreline
/// traced in ember. Drawn rather than set in type, so the mark is centred by
/// construction and carries no serif stress.
///
/// The land silhouette and the shoreline are the same curve, so the fill and
/// the stroke can never drift apart. The shoreline widens optically below
/// ~32pt — a 4-unit hairline is sub-pixel there and would simply disappear.
///
/// The tile carries `CoveTheme.hairline` around its edge, which the app icon
/// deliberately does not. An icon is masked by the system and sits on a
/// wallpaper; this mark sits on Cove's own surfaces, and its ground *is* the
/// canvas — paper on a card in light, night on a card in dark. Without the
/// edge the tile's ground half simply vanishes into what it is drawn on and
/// the mark reads as a bay floating on the page rather than as a tile. The
/// edge only shows along that half, since over the land it composites to the
/// land's own colour, which is the half that never needed it.
struct CoveMark: View {
    var size: CGFloat = 34

    @Environment(\.colorScheme) private var scheme

    private let paperGround = Color(red: 0.965, green: 0.953, blue: 0.933)
    private let nightGround = Color(red: 0.090, green: 0.075, blue: 0.059)
    private let ink = Color(red: 0.141, green: 0.129, blue: 0.114)
    private let paper = Color(red: 0.929, green: 0.902, blue: 0.855)
    private let shore = Color(red: 0.620, green: 0.345, blue: 0.153)

    private var isDark: Bool { scheme == .dark }

    /// 4 design units, never thinner than one point on screen.
    private var shoreWidth: CGFloat { max(size * 0.04, 1) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .fill(isDark ? nightGround : paperGround)
            CoveLand()
                .fill(isDark ? paper : ink)
            CoveShore()
                .stroke(shore, style: StrokeStyle(lineWidth: shoreWidth, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .strokeBorder(CoveTheme.hairline, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// The shoreline: two cubics across the frame, in a 0…100 design space.
/// The bay sits left of centre and the right headland stands higher, so the
/// mark reads as a place rather than a symmetrical diagram.
private func coveShorePath(in rect: CGRect) -> Path {
    let u = { (x: CGFloat, y: CGFloat) in
        CGPoint(x: rect.minX + rect.width * x / 100, y: rect.minY + rect.height * y / 100)
    }
    var path = Path()
    path.move(to: u(0, 42))
    path.addCurve(to: u(44, 74), control1: u(20, 42), control2: u(22, 74))
    path.addCurve(to: u(100, 34), control1: u(70, 74), control2: u(76, 34))
    return path
}

private struct CoveShore: Shape {
    func path(in rect: CGRect) -> Path { coveShorePath(in: rect) }
}

private struct CoveLand: Shape {
    func path(in rect: CGRect) -> Path {
        var path = coveShorePath(in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
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
