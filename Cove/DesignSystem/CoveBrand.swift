import SwiftUI

/// The app's in-product mark: two concentric arcs on one axis — an ink C with
/// an ember arc echoing it. Drawn rather than set in type, so the mark is
/// centred by construction and carries no serif stress.
struct CoveMark: View {
    var size: CGFloat = 34

    @Environment(\.colorScheme) private var scheme

    private let paperGround = Color(red: 0.965, green: 0.953, blue: 0.933)
    private let nightTop = Color(red: 0.133, green: 0.114, blue: 0.094)
    private let nightBottom = Color(red: 0.078, green: 0.067, blue: 0.055)
    private let ink = Color(red: 0.141, green: 0.129, blue: 0.114)
    private let paper = Color(red: 0.976, green: 0.961, blue: 0.933)

    private var isDark: Bool { scheme == .dark }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .fill(ground)
            CoveArc(radius: 0.20, halfGap: 30)
                .stroke(
                    isDark ? paper : ink,
                    style: StrokeStyle(lineWidth: size * 0.16, lineCap: .butt)
                )
            CoveArc(radius: 0.36, halfGap: 22)
                .stroke(
                    CoveTheme.accent,
                    style: StrokeStyle(lineWidth: max(size * 0.07, 1.5), lineCap: .butt)
                )
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

/// One arc of the mark: a circle of the given radius (a fraction of the frame)
/// opened by halfGap degrees either side of the trailing axis.
private struct CoveArc: Shape {
    let radius: CGFloat
    let halfGap: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height)
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: side * radius,
            startAngle: .degrees(halfGap),
            endAngle: .degrees(360 - halfGap),
            clockwise: false
        )
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
