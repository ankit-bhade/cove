import SwiftUI

struct RootView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system

    var body: some View {
        Group {
            switch vaultManager.state {
            case .restoring:
                CoveLoadingView()
            case .needsVault:
                WelcomeView()
            case .recoveryNeeded:
                VaultRecoveryView()
            case .open:
                TabView {
                    VaultBrowserView()
                        .tabItem { Label("Notes", systemImage: "folder.fill") }
                    TasksView()
                        .tabItem { Label("Tasks", systemImage: "checkmark.circle.fill") }
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                }
                .tint(CoveTheme.teal)
            }
        }
        .preferredColorScheme(appearance.colorScheme)
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

private struct CoveLoadingView: View {
    var body: some View {
        ZStack {
            CoveBrandBackground()
            VStack(spacing: 18) {
                Image("LaunchIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: CoveTheme.navy.opacity(0.20), radius: 20, y: 10)
                VStack(spacing: 6) {
                    Text("Cove")
                        .font(.title2.weight(.bold))
                    Text("Opening your notes…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ProgressView()
                    .tint(CoveTheme.teal)
            }
        }
    }
}
