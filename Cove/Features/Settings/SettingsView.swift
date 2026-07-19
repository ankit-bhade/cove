import SwiftUI
import UserNotifications

/// The Settings tab: vault selection, appearance, and notification
/// permission. The vault picker here is the same flow as the welcome and
/// recovery screens, so a stale bookmark can also be fixed from Settings.
struct SettingsView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system

    /// Loaded on appearance and whenever the scene re-activates, so a trip
    /// to the system settings is reflected on return.
    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        NavigationStack {
            Form {
                settingsHeader
                vaultSection
                appearanceSection
                notificationsSection
                aboutSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(CoveTheme.canvas(for: colorScheme))
            .navigationTitle("Settings")
        }
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refreshNotificationStatus() }
            }
        }
    }

    // MARK: - Vault

    private var settingsHeader: some View {
        Section {
            HStack(spacing: 15) {
                Image("LaunchIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Make Cove Yours")
                        .font(.title3.weight(.bold))
                    Text("A focused, private space for your notes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background { CoveCardBackground() }
            .listRowInsets(CoveTheme.dashboardRowInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var vaultSection: some View {
        Section {
            if let vaultURL = vaultManager.vaultURL {
                HStack(alignment: .top, spacing: 12) {
                    CoveIconTile(systemName: "folder.fill", tint: CoveTheme.seaGlass)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vaultURL.lastPathComponent)
                            .font(.body.weight(.semibold))
                        Text(vaultURL.path(percentEncoded: false))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
            }
            VaultPickerButton(title: "Choose a Different Vault…")
                .controlSize(.regular)
        } header: {
            Text("Vault")
        } footer: {
            Text("Selecting a new folder replaces the current vault. Your files are never moved or deleted.")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Color Theme")
                        .font(.body.weight(.medium))
                } icon: {
                    CoveIconTile(systemName: "circle.lefthalf.filled")
                }
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceSetting.allCases) { setting in
                        Text(setting.label).tag(setting)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            HStack(spacing: 12) {
                CoveIconTile(systemName: notificationStatusIcon,
                             tint: notificationsEnabled ? CoveTheme.teal : .secondary)
                Text("Task Reminders")
                    .font(.body.weight(.medium))
                Spacer()
                Text(notificationStatusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(notificationsEnabled ? CoveTheme.teal : .secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((notificationsEnabled ? CoveTheme.teal : Color.secondary)
                        .opacity(0.10), in: Capsule())
            }
            switch notificationStatus {
            case .notDetermined:
                Button {
                    Task { await requestNotificationPermission() }
                } label: {
                    Label("Enable Notifications", systemImage: "bell.badge")
                }
            case .denied:
                Button(action: openNotificationSettings) {
                    Label("Open System Settings", systemImage: "arrow.up.forward.app")
                }
            default:
                EmptyView()
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Tasks with a due time get a reminder at that moment. Tasks with only a date don’t notify.")
        }
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: "Enabled"
        case .denied: "Off"
        case .notDetermined: "Not Requested"
        case nil: "…"
        @unknown default: "Unknown"
        }
    }

    private var notificationsEnabled: Bool {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    private var notificationStatusIcon: String {
        notificationsEnabled ? "bell.fill" : "bell.slash.fill"
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current()
            .notificationSettings().authorizationStatus
    }

    private func requestNotificationPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        await refreshNotificationStatus()
        // Newly granted permission takes effect on the next rebuild.
        await vaultManager.refresh()
    }

    private func openNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
        #else
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            openURL(url)
        }
        #endif
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack(spacing: 12) {
                CoveIconTile(systemName: "info.circle.fill", tint: CoveTheme.seaGlass)
                Text("Cove for Markdown")
                    .font(.body.weight(.medium))
                Spacer()
                Text(appVersion)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
