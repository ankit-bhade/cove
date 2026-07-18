import SwiftUI

struct RootView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.scenePhase) private var scenePhase

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
                TabView {
                    VaultBrowserView()
                        .tabItem { Label("Notes", systemImage: "folder") }
                    TasksView()
                        .tabItem { Label("Tasks", systemImage: "checklist") }
                }
            }
        }
        .task {
            await vaultManager.restore()
        }
        // Metadata updates can be missed while the app is inactive, so a
        // return to the foreground rescans the tree as a catch-all.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, vaultManager.state == .open {
                Task { await vaultManager.refresh() }
            }
        }
    }
}
