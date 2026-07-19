import SwiftUI

/// The Today widget's colors, straight from the design handoff's token table.
///
/// These are deliberately literal rather than a reference to `CoveTheme`: the
/// widget's accent is a slightly deeper teal than the app's (`#1F7D92` against
/// `CoveTheme.teal`), and the handoff specifies an overdue red the app's
/// palette has no name for. Keeping them here means the widget target stays
/// self-contained — no shared asset catalog — and the widget reads correctly
/// on a Home Screen next to other apps rather than inside Cove's own canvas.
struct WidgetPalette {
    let background: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let accentSoft: Color
    let overdue: Color
    /// The check glyph drawn inside a filled checkbox: the widget's own
    /// background, so the mark reads as a hole punched in the accent fill.
    let checkMark: Color

    static let light = WidgetPalette(
        background: .white,
        primaryText: Color(red: 0.082, green: 0.114, blue: 0.141),
        secondaryText: Color(red: 0.082, green: 0.114, blue: 0.141).opacity(0.50),
        accent: Color(red: 0.122, green: 0.490, blue: 0.573),
        accentSoft: Color(red: 0.122, green: 0.490, blue: 0.573).opacity(0.12),
        overdue: Color(red: 0.847, green: 0.263, blue: 0.290),
        checkMark: .white)

    static let dark = WidgetPalette(
        background: Color(red: 0.075, green: 0.102, blue: 0.114),
        primaryText: Color(red: 0.933, green: 0.957, blue: 0.961),
        secondaryText: Color(red: 0.933, green: 0.957, blue: 0.961).opacity(0.55),
        accent: Color(red: 0.302, green: 0.702, blue: 0.784),
        accentSoft: Color(red: 0.302, green: 0.702, blue: 0.784).opacity(0.16),
        overdue: Color(red: 1.0, green: 0.420, blue: 0.420),
        checkMark: Color(red: 0.043, green: 0.078, blue: 0.090))

    static func resolved(for scheme: ColorScheme) -> WidgetPalette {
        scheme == .dark ? .dark : .light
    }
}
