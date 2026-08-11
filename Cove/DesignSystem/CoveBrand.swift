import SwiftUI

/// The app's in-product mark: one disc, cut once. A single vertical kerf left
/// of centre splits the circle into a large piece and a small one, both on the
/// centreline. Drawn rather than set in type, so the mark is centred by
/// construction and carries no serif stress.
///
/// It replaces the bay-and-shoreline stamp, whose silhouette was a horizon
/// line: below about 40pt a 4-unit shoreline is sub-pixel, and what was left
/// read as texture rather than as a mark. Here the smallest feature is the
/// kerf at 6% of the tile — about a point at the 16pt Dock size — and the two
/// pieces differ in value rather than in outline, so the mark survives being
/// small, being tinted, and sitting on someone's wallpaper.
///
/// The tile carries `CoveTheme.hairline` around its edge, which the app icon
/// deliberately does not. An icon is masked by the system and sits on a
/// wallpaper; this mark sits on Cove's own surfaces, and its ground *is* the
/// canvas — paper on a card in light, night on a card in dark. Without the
/// edge the tile's ground simply vanishes into what it is drawn on and the
/// mark reads as two shapes floating on the page rather than as a tile.
struct CoveMark: View {
    var size: CGFloat = 34

    @Environment(\.colorScheme) private var scheme

    private let paperGround = Color(red: 0.965, green: 0.953, blue: 0.933)
    private let nightGround = Color(red: 0.090, green: 0.075, blue: 0.059)
    private let ink = Color(red: 0.141, green: 0.129, blue: 0.114)
    private let paper = Color(red: 0.929, green: 0.902, blue: 0.855)
    private let ember = Color(red: 0.620, green: 0.345, blue: 0.153)
    private let emberDark = Color(red: 0.878, green: 0.635, blue: 0.392)

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .fill(isDark ? nightGround : paperGround)
            CoveDiscPiece(side: .major)
                .fill(isDark ? paper : ink)
            CoveDiscPiece(side: .minor)
                .fill(isDark ? emberDark : ember)
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

/// One side of the cut, in a 0…100 design space: a disc of radius 36 centred
/// in the tile, clipped by a vertical band. The kerf is 6 wide and centred at
/// x = 60, so the pieces are 57/43 by width and neither is ever a hairline.
///
/// Both pieces come from the same circle and the same two clip edges, so the
/// cut can never drift open or overlap the way two independently placed
/// shapes would.
private struct CoveDiscPiece: Shape {
    enum Side { case major, minor }

    let side: Side

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 100
        let disc = Path(
            ellipseIn: CGRect(
                x: rect.minX + 14 * unit,
                y: rect.minY + 14 * unit,
                width: 72 * unit,
                height: 72 * unit))

        let band: CGRect
        switch side {
        case .major:
            band = CGRect(
                x: rect.minX, y: rect.minY,
                width: 57 * unit, height: rect.height)
        case .minor:
            band = CGRect(
                x: rect.minX + 63 * unit, y: rect.minY,
                width: 37 * unit, height: rect.height)
        }

        return disc.intersection(Path(band))
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
