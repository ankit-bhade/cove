import SwiftUI
import UserNotifications

/// The Settings tab: vault selection, appearance, and notification
/// permission. The vault picker here is the same flow as the welcome and
/// recovery screens, so a stale bookmark can also be fixed from Settings.
struct SettingsView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system

    /// Loaded on appearance and whenever the scene re-activates, so a trip
    /// to the system settings is reflected on return.
    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        NavigationStack {
            Form {
                vaultSection
                appearanceSection
                notificationsSection
                aboutSection
            }
            .formStyle(.grouped)
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

    private var vaultSection: some View {
        Section {
            if let vaultURL = vaultManager.vaultURL {
                LabeledContent("Vault", value: vaultURL.lastPathComponent)
                Text(vaultURL.path(percentEncoded: false))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            VaultPickerButton(title: "Choose a Different Vault…")
                .buttonStyle(.borderless)
        } header: {
            Text("Vault")
        } footer: {
            Text("Selecting a new folder replaces the current vault. Your files are never moved or deleted.")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceSetting.allCases) { setting in
                    Text(setting.label).tag(setting)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            LabeledContent("Task Reminders", value: notificationStatusLabel)
            switch notificationStatus {
            case .notDetermined:
                Button("Enable Notifications") {
                    Task { await requestNotificationPermission() }
                }
            case .denied:
                Button("Open System Settings") { openNotificationSettings() }
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
        Section("About") {
            LabeledContent("Version", value: appVersion)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
