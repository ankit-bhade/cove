#if os(macOS)
    import AppKit
    import SwiftUI

    /// The Mac's dark app icon, applied at runtime because the asset catalog has
    /// nowhere to put it.
    ///
    /// An `appiconset` honours a `luminosity` appearance for the iOS idiom only.
    /// `actool` *parses* `mac` idiom entries that carry one and then assigns them
    /// to nothing — reporting "the app icon set has N unassigned children", a
    /// warning rather than an error — so a catalog that looks complete in Xcode's
    /// inspector quietly ships the light tile to both appearances. macOS 26's
    /// `.icon` format is where a real dark Mac icon comes from, and it needs Icon
    /// Composer plus a macOS 26 floor; Cove targets macOS 14.
    ///
    /// `applicationIconImage` is the Dock's own copy of the icon and is writable
    /// on every version Cove supports, so the dark tile goes there instead.
    /// Setting it back to `nil` restores the bundle's icon rather than assigning a
    /// second copy of the light artwork — the catalog stays the one home of the
    /// light tile.
    ///
    /// This reaches the Dock and the app switcher, and only while Cove is
    /// running. Finder, Spotlight, and Launchpad read the bundle and keep showing
    /// the light tile; nothing short of `.icon` changes that.
    @MainActor
    enum DockIcon {

        /// The name of the dark tile in the asset catalog. `DockIconTests` holds
        /// this to an image that actually loads, since a renamed or dropped
        /// imageset would otherwise fail silently — `NSImage(named:)` returning
        /// nil just leaves the light icon in place, which is what a working app
        /// looks like in light mode.
        static let darkImageName = "DockIconDark"

        /// Point the Dock at the tile matching `scheme`.
        ///
        /// Takes the resolved scheme rather than the stored `AppearanceSetting`,
        /// so the caller hands over SwiftUI's own `colorScheme` and the two cannot
        /// disagree about what `.system` resolved to.
        static func apply(_ scheme: ColorScheme) {
            NSApp?.applicationIconImage =
                scheme == .dark ? NSImage(named: darkImageName) : nil
        }
    }

    private struct DockIconModifier: ViewModifier {
        @Environment(\.colorScheme) private var scheme

        func body(content: Content) -> some View {
            content
                .onAppear { DockIcon.apply(scheme) }
                .onChange(of: scheme) { _, newScheme in
                    DockIcon.apply(newScheme)
                }
        }
    }

    extension View {
        /// Keeps the Dock icon in step with the appearance the app is drawn in.
        ///
        /// Apply this *before* `preferredColorScheme` in the modifier chain, so
        /// the modifier sits below that setting in the view tree and the
        /// `colorScheme` it reads is the one the setting resolved to.
        func coveDockIcon() -> some View {
            modifier(DockIconModifier())
        }
    }
#endif
