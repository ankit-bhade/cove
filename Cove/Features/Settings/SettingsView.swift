import SwiftUI
import UserNotifications

/// The Settings tab: vault selection, appearance, and notification
/// permission. The vault picker here is the same flow as the welcome and
/// recovery screens, so a stale bookmark can also be fixed from Settings.
struct SettingsView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            }
            .coveFormStyle()
            .coveReadableWidth(680)
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
                // The path wraps, so the tile pins to the top rather than
                // drifting to the middle of a two-line block.
                CoveRow(systemName: "folder.fill", tint: CoveTheme.moss, alignment: .top) {
                    CoveRowTitle(
                        title: vaultURL.lastPathComponent,
                        caption: vaultURL.path(percentEncoded: false),
                        captionIsLabel: false,
                        lineLimit: 1)
                    Spacer(minLength: 0)
                }
                .textSelection(.enabled)
            }
            VaultPickerButton(title: "Choose a Different Vault…", prominent: false)
                .controlSize(.regular)
        } header: {
            CoveSectionHeader("Vault")
        } footer: {
            Text("Selecting a new folder replaces the current vault. Your files are never moved or deleted.")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: CoveTheme.Space.snug) {
                CoveRow(systemName: "circle.lefthalf.filled") {
                    Text("Color Theme")
                        .font(.body.weight(.medium))
                    Spacer(minLength: 0)
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
            CoveSectionHeader("Appearance")
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            CoveRow(
                systemName: notificationStatusIcon,
                tint: notificationsEnabled ? CoveTheme.accent : .secondary
            ) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: CoveTheme.Space.snug) {
                        notificationTitle
                        notificationBadge
                    }
                } else {
                    notificationTitle
                    Spacer(minLength: 0)
                    notificationBadge
                }
            }
            // Built from `CoveRow` like the vault-reselect button and every
            // row above them: a `Label` here puts its glyph in the system's
            // own icon column, a few points left of the tiles it sits under.
            switch notificationStatus {
            case .notDetermined:
                actionRow("Enable Notifications", systemName: "bell.badge") {
                    Task { await requestNotificationPermission() }
                }
            case .denied:
                actionRow("Open System Settings", systemName: "arrow.up.forward.app") {
                    openNotificationSettings()
                }
            default:
                EmptyView()
            }
        } header: {
            CoveSectionHeader("Notifications")
        } footer: {
            Text("Tasks with a due time get a reminder at that moment. Tasks with only a date don’t notify.")
        }
    }

    private func actionRow(
        _ title: String,
        systemName: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            CoveRow(systemName: systemName) {
                Text(title)
                    .font(.body.weight(.medium))
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.borderless)
    }

    private var notificationTitle: some View {
        Text("Task Reminders")
            .font(.body.weight(.medium))
    }

    private var notificationBadge: some View {
        CoveCountBadge(
            notificationStatusLabel,
            tint: notificationsEnabled ? CoveTheme.accent : .secondary)
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

}
