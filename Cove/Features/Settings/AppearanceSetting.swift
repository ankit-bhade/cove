import SwiftUI

/// The user's appearance preference, persisted in `UserDefaults` through
/// `@AppStorage`. `system` follows the platform appearance; the other two
/// force a color scheme app-wide.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearanceSetting"

    var id: String { rawValue }

    /// The scheme to force via `preferredColorScheme`, or nil to follow
    /// the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
