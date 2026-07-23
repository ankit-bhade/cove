import SwiftUI

/// Cove's visual system: a small set of tokens every screen is assembled
/// from. Reusable views live beside these tokens in the DesignSystem folder.
///
/// The palette is **ink on warm paper, marked in ember**. A notes app is a
/// page before it is anything else, so the canvas is an unbleached warm
/// off-white rather than a cool system gray, text sits on it as warm ink, and
/// exactly one saturated hue — a burnt ember — carries interaction and
/// emphasis. Moss is the single supporting hue, reserved for containers
/// (folders, destinations), and a warm rust carries lateness.
///
/// Every token is a dynamic color that resolves itself against the current
/// appearance, so nested views cannot disagree about the active appearance.
enum CoveTheme {

    // MARK: - Palette

    static let canvas = dynamic(
        light: Color(red: 0.965, green: 0.953, blue: 0.933),
        dark: Color(red: 0.086, green: 0.082, blue: 0.075)
    )

    static let surface = dynamic(
        light: Color(red: 1.000, green: 0.992, blue: 0.976),
        dark: Color(red: 0.125, green: 0.118, blue: 0.106)
    )

    static let ink = dynamic(
        light: Color(red: 0.141, green: 0.129, blue: 0.114),
        dark: Color(red: 0.949, green: 0.933, blue: 0.906)
    )

    static let accent = dynamic(
        light: Color(red: 0.620, green: 0.345, blue: 0.153),
        dark: Color(red: 0.878, green: 0.635, blue: 0.392)
    )

    static let moss = dynamic(
        light: Color(red: 0.337, green: 0.420, blue: 0.306),
        dark: Color(red: 0.639, green: 0.702, blue: 0.580)
    )

    static let alert = dynamic(
        light: Color(red: 0.698, green: 0.227, blue: 0.169),
        dark: Color(red: 0.910, green: 0.475, blue: 0.416)
    )

    static let hairline = dynamic(
        light: Color(red: 0.141, green: 0.129, blue: 0.114).opacity(0.12),
        dark: .white.opacity(0.10)
    )

    // MARK: - Metrics

    enum Space {
        static let tight: CGFloat = 6
        static let snug: CGFloat = 10
        static let regular: CGFloat = 16
        static let loose: CGFloat = 22
    }

    static let cardRadius: CGFloat = 18
    static let fieldRadius: CGFloat = 12

    static func mastheadRowInsets(bottom: CGFloat = 14) -> EdgeInsets {
        EdgeInsets(top: 8, leading: 0, bottom: bottom, trailing: 0)
    }

    static func taskRowInsets(hasMetadata: Bool) -> EdgeInsets {
        #if os(iOS)
            EdgeInsets(
                top: hasMetadata ? 6 : 5,
                leading: 20,
                bottom: hasMetadata ? 6 : 5,
                trailing: 14
            )
        #else
            EdgeInsets(
                top: hasMetadata ? 4 : 3,
                leading: 10,
                bottom: hasMetadata ? 4 : 3,
                trailing: 8
            )
        #endif
    }

    // MARK: - Dynamic colors

    private static func dynamic(light: Color, dark: Color) -> Color {
        #if os(iOS)
            Color(
                UIColor { traits in
                    traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
                })
        #else
            Color(
                NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                        ? NSColor(dark) : NSColor(light)
                })
        #endif
    }
}

// MARK: - Typography

extension Font {
    static var coveDisplayLarge: Font { .system(.largeTitle, design: .serif).weight(.semibold) }
    static var coveDisplay: Font { .system(.title2, design: .serif).weight(.semibold) }
    static var coveDisplaySmall: Font { .system(.title3, design: .serif).weight(.semibold) }
    static var coveHeadline: Font { .system(.headline, design: .serif) }
}

extension View {
    func coveEyebrow(tint: Color? = nil) -> some View {
        self
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.9)
            .foregroundStyle(tint ?? .secondary)
    }
}

// MARK: - Chrome

private struct CoveScrollBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(CoveTheme.canvas)
    }
}

extension View {
    func coveListStyle() -> some View {
        #if os(iOS)
            self.listStyle(.insetGrouped).modifier(CoveScrollBackground())
        #else
            self.listStyle(.inset).modifier(CoveScrollBackground())
        #endif
    }

    func coveFormStyle() -> some View {
        formStyle(.grouped).modifier(CoveScrollBackground())
    }

    func coveReadableWidth(_ width: CGFloat = 760) -> some View {
        modifier(CoveReadableWidth(maxWidth: width))
    }

    func coveErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Something Went Wrong",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

private struct CoveReadableWidth: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(CoveTheme.canvas)
    }
}
