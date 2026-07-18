import SwiftUI

@main
struct CoveApp: App {
    @State private var vaultManager = VaultManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vaultManager)
        }
    }
}
