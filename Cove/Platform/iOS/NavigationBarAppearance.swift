#if os(iOS)
    import UIKit

    /// Sets the navigation bar's title type to the serif face the app's mastheads
    /// and empty states use.
    ///
    /// SwiftUI has no modifier for the font of a `navigationTitle`, and the title
    /// is the largest text on every screen — left as the system's bold sans it was
    /// the one piece of the app that still looked like a default. The UIKit
    /// appearance proxy is the only way to reach it, so it is used here and
    /// nowhere else.
    ///
    /// The backgrounds are configured explicitly rather than inherited: touching
    /// `standardAppearance` at all replaces the whole appearance object, so the
    /// transparent scroll-edge bar has to be restated or every screen gains a
    /// material behind its title.
    @MainActor
    enum NavigationBarAppearance {
        static func apply() {
            let standard = UINavigationBarAppearance()
            standard.configureWithDefaultBackground()
            applyTitleFonts(to: standard)

            let scrollEdge = UINavigationBarAppearance()
            scrollEdge.configureWithTransparentBackground()
            applyTitleFonts(to: scrollEdge)

            let proxy = UINavigationBar.appearance()
            proxy.standardAppearance = standard
            proxy.compactAppearance = standard
            proxy.scrollEdgeAppearance = scrollEdge
            proxy.compactScrollEdgeAppearance = scrollEdge
        }

        private static func applyTitleFonts(to appearance: UINavigationBarAppearance) {
            appearance.largeTitleTextAttributes = [
                .font: serifFont(textStyle: .largeTitle, weight: .semibold)
            ]
            appearance.titleTextAttributes = [
                .font: serifFont(textStyle: .headline, weight: .semibold)
            ]
        }

        /// The serif system face at a text style's size, still scaled by
        /// `UIFontMetrics` so a title tracks Dynamic Type like every other label.
        private static func serifFont(
            textStyle: UIFont.TextStyle,
            weight: UIFont.Weight
        ) -> UIFont {
            let size = UIFont.preferredFont(forTextStyle: textStyle).pointSize
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = base.fontDescriptor.withDesign(.serif) else {
                return base
            }
            return UIFontMetrics(forTextStyle: textStyle)
                .scaledFont(for: UIFont(descriptor: descriptor, size: size))
        }
    }
#endif
