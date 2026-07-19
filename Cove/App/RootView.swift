import SwiftUI

struct RootView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system
    @State private var selectedSection: AppSection = .notes

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
                appNavigation
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
        // Tapping the Today widget lands on the Tasks screen, which is the
        // full version of what the widget was showing.
        .onOpenURL { url in
            if url.scheme == "cove", url.host == "tasks" {
                selectedSection = .tasks
            }
        }
    }

    @ViewBuilder
    private var appNavigation: some View {
        #if os(macOS)
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
                    .padding(.vertical, 3)
            }
            .safeAreaInset(edge: .top) {
                HStack(spacing: 10) {
                    Image("LaunchIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Cove")
                            .font(.headline)
                        Text("Markdown, at home")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            sectionView(selectedSection)
        }
        .navigationSplitViewStyle(.balanced)
        #else
        TabView(selection: $selectedSection) {
            ForEach(AppSection.allCases) { section in
                sectionView(section)
                    .tabItem { Label(section.title, systemImage: section.symbol) }
                    .tag(section)
            }
        }
        #endif
    }

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .notes: VaultBrowserView()
        case .tasks: TasksView()
        case .lists: ListsView()
        case .settings: SettingsView()
        }
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case notes
    case tasks
    case lists
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .notes: "Notes"
        case .tasks: "Tasks"
        case .lists: "Lists"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .notes: "folder.fill"
        case .tasks: "checkmark.circle.fill"
        case .lists: "list.bullet.rectangle.fill"
        case .settings: "gearshape.fill"
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Opening your notes")
        }
    }
}
