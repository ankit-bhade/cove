import SwiftUI

struct RootView: View {
    @Environment(VaultManager.self) private var vaultManager

    var body: some View {
        Group {
            switch vaultManager.state {
            case .restoring:
                ProgressView()
            case .needsVault:
                WelcomeView()
            case .recoveryNeeded:
                VaultRecoveryView()
            case .open:
                VaultBrowserView()
            }
        }
        .task {
            await vaultManager.restore()
        }
    }
}
