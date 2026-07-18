import SwiftUI

@main
struct CoveApp: App {
    @State private var vaultManager = VaultManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vaultManager)
                .tint(CoveTheme.teal)
        }
        #if os(macOS)
        .defaultSize(width: 980, height: 700)
        #endif
    }
}
