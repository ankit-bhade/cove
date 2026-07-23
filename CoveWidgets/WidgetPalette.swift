import SwiftUI

/// The Today widget's colors: the app's ink-on-warm-paper palette, restated
/// for a surface Cove doesn't control.
///
/// These stay literal rather than referencing `CoveTheme` — the widget target
/// compiles a handful of pure files, not the app's view layer, and keeping the
/// tokens here means the extension needs no shared asset catalog. The values
/// differ deliberately: a widget sits on a Home Screen next to other apps
/// rather than inside Cove's own canvas, so its background is a plain warm
/// paper and its accent runs a shade deeper than the app's for legibility at
/// widget text sizes.
struct WidgetPalette {
    let background: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let accentSoft: Color
    let overdue: Color
    /// The checkbox at rest — a muted accent rather than the full one. The
    /// boxes repeat down the widget while the count and the times appear
    /// once each, so at full saturation they were the loudest thing on it.
    let checkboxRest: Color
    /// The check glyph drawn inside a filled checkbox: the widget's own
    /// background, so the mark reads as a hole punched in the fill.
    let checkMark: Color

    static let light = WidgetPalette(
        background: Color(red: 0.988, green: 0.976, blue: 0.957),
        primaryText: Color(red: 0.141, green: 0.129, blue: 0.114),
        secondaryText: Color(red: 0.141, green: 0.129, blue: 0.114).opacity(0.52),
        accent: Color(red: 0.573, green: 0.318, blue: 0.141),
        accentSoft: Color(red: 0.573, green: 0.318, blue: 0.141).opacity(0.13),
        overdue: Color(red: 0.698, green: 0.227, blue: 0.169),
        checkboxRest: Color(red: 0.573, green: 0.318, blue: 0.141).opacity(0.38),
        checkMark: Color(red: 0.988, green: 0.976, blue: 0.957))

    static let dark = WidgetPalette(
        background: Color(red: 0.098, green: 0.090, blue: 0.082),
        primaryText: Color(red: 0.949, green: 0.933, blue: 0.906),
        secondaryText: Color(red: 0.949, green: 0.933, blue: 0.906).opacity(0.55),
        accent: Color(red: 0.878, green: 0.635, blue: 0.392),
        accentSoft: Color(red: 0.878, green: 0.635, blue: 0.392).opacity(0.17),
        overdue: Color(red: 0.910, green: 0.475, blue: 0.416),
        checkboxRest: Color(red: 0.878, green: 0.635, blue: 0.392).opacity(0.42),
        checkMark: Color(red: 0.098, green: 0.090, blue: 0.082))

    static func resolved(for scheme: ColorScheme) -> WidgetPalette {
        scheme == .dark ? .dark : .light
    }
}
