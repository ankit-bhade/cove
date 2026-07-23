import SwiftUI

@main
struct CoveApp: App {
    @State private var vaultManager = VaultManager()

    init() {
        #if os(iOS)
            NavigationBarAppearance.apply()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vaultManager)
                .tint(CoveTheme.accent)
        }
        #if os(macOS)
            .defaultSize(width: 980, height: 700)
        #endif
    }
}
