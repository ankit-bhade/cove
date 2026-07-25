import SwiftUI

struct RootView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system
    /// Tasks is the landing screen on every surface: it is the one section
    /// that is *about* right now, and it is where the Today widget's deep
    /// link goes — a launch from the Home Screen and a launch from the icon
    /// should not arrive at different places.
    @State private var selectedSection: AppSection = .tasks

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
                    .safeAreaInset(edge: .top, spacing: 0) {
                        storageAttentionBanner
                    }
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
            } else if newPhase == .background {
                vaultManager.stopObservingExternalChanges()
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
    private var storageAttentionBanner: some View {
        if let summary = storageAttentionSummary {
            Button {
                selectedSection = .settings
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(summary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text("Review")
                        .fontWeight(.semibold)
                }
                .font(.footnote)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .coveTintedSurface(
                    CoveTheme.alert,
                    in: Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Storage Health in Settings")
        }
    }

    private var storageAttentionSummary: String? {
        let health = vaultManager.storageHealth
        if let issue = health.lastIssue { return issue }
        if health.unavailableNoteCount > 0 {
            return
                "\(health.unavailableNoteCount) note\(health.unavailableNoteCount == 1 ? "" : "s") could not be read."
        }
        if health.taskDiagnosticCount > 0 {
            return
                "\(health.taskDiagnosticCount) task line\(health.taskDiagnosticCount == 1 ? " needs" : "s need") review."
        }
        let conflictCount =
            health.unresolvedConflictURLs.count
            + health.conflictReviewURLs.count
        if conflictCount > 0 {
            return
                "\(conflictCount) iCloud conflict item\(conflictCount == 1 ? " needs" : "s need") review."
        }
        return nil
    }

    @ViewBuilder
    private var appNavigation: some View {
        #if os(macOS)
            NavigationSplitView {
                List(AppSection.allCases, selection: $selectedSection) { section in
                    HStack(spacing: CoveTheme.Space.rowGap) {
                        Image(systemName: section.symbol)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(
                                selectedSection == section
                                    ? CoveTheme.accent : .secondary
                            )
                            .frame(width: 20)
                        Text(section.title)
                            .font(.body.weight(selectedSection == section ? .semibold : .regular))
                    }
                    .tag(section)
                    .padding(.vertical, CoveTheme.Space.rowPadding)
                }
                .safeAreaInset(edge: .top) {
                    HStack(spacing: 11) {
                        CoveMark(size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Cove")
                                .font(.coveHeadline)
                            Text("Markdown, at home")
                                .coveEyebrow()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 11)
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(CoveTheme.hairline)
                            .frame(height: 1)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Cove")
                }
                .navigationSplitViewColumnWidth(min: 196, ideal: 224, max: 300)
            } detail: {
                sectionView(selectedSection)
            }
            .navigationSplitViewStyle(.balanced)
        #else
            // The tab bar takes no background override. `toolbarBackground`
            // replaces whatever the running system draws there, which on
            // iOS 26 meant a flat pill in place of the platform's own bar with
            // rows showing through it unblurred — and a tab bar is the one
            // piece of chrome every app on the device shares.
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

/// Declaration order is the order of the iOS tab bar and the macOS sidebar,
/// and Tasks leads both: it is the section the app opens on, so leaving it
/// second put the landing screen under the second target while the first one
/// sat unvisited. Notes follows, then Lists, then Settings — structure, then
/// grouping, then configuration.
private enum AppSection: String, CaseIterable, Identifiable {
    case tasks
    case notes
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

    /// Outline variants. The iOS tab bar substitutes the filled version
    /// itself, so the name only shows through on the macOS sidebar — where
    /// outline is the platform's own convention and the filled glyphs read
    /// as heavier than every other sidebar in the system.
    var symbol: String {
        switch self {
        case .notes: "folder"
        case .tasks: "checkmark.circle"
        case .lists: "list.bullet.rectangle"
        case .settings: "gearshape"
        }
    }
}

private struct CoveLoadingView: View {
    var body: some View {
        ZStack {
            CoveBrandBackground()
            VStack(spacing: CoveTheme.Space.loose) {
                CoveMark(size: 76)
                    .shadow(color: CoveTheme.ink.opacity(0.18), radius: 18, y: 9)
                VStack(spacing: CoveTheme.Space.tight) {
                    Text("Cove")
                        .font(.coveDisplay)
                    Text("Opening your notes…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ProgressView()
                    .controlSize(.small)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Opening your notes")
        }
    }
}
