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
    /// Read straight from `VaultManager` rather than cached here. It records
    /// the same value on every reconcile and is `@Observable`, so this
    /// updates live instead of only when the screen appears — and there is
    /// one place the scheduler's last result lives rather than two that can
    /// disagree.
    private var notificationHealth: TaskNotificationHealth? {
        vaultManager.notificationHealth
    }
    @State private var pendingReminderCount = 0
    @State private var notificationErrorMessage: String?
    @State private var notificationPlanInventory = TaskNotificationPlanInventory(
        plans: [],
        eligibleCount: 0,
        omittedBySystemLimit: 0,
        invalidDateCount: 0)
    #if os(iOS)
        @State private var widgetHealth: WidgetChannelHealth?
        @State private var widgetActionErrorMessage: String?
    #endif

    var body: some View {
        NavigationStack {
            Form {
                vaultSection
                storageHealthSection
                appearanceSection
                notificationsSection
                #if os(iOS)
                    widgetSection
                #endif
            }
            .coveFormStyle()
            .coveReadableWidth(680)
            .navigationTitle("Settings")
        }
        .task { await refreshRuntimeHealth() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refreshRuntimeHealth() }
            }
        }
    }

    // MARK: - Storage health

    private var storageHealthSection: some View {
        let health = vaultManager.storageHealth
        return Section {
            CoveRow(
                systemName: storageNeedsAttention
                    ? "exclamationmark.triangle.fill"
                    : "checkmark.shield.fill",
                tint: storageNeedsAttention
                    ? CoveTheme.alert : CoveTheme.moss
            ) {
                Text("Vault Safety")
                    .font(.body.weight(.medium))
                Spacer(minLength: 0)
                CoveCountBadge(
                    storageNeedsAttention ? "Attention" : "Ready",
                    tint: storageNeedsAttention
                        ? CoveTheme.alert : CoveTheme.moss)
            }

            LabeledContent("Folder Access") {
                Text(storageAccessLabel(health.accessState))
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Bookmark") {
                Text(health.bookmarkIsPersisted ? "Saved" : "Not Saved")
                    .foregroundStyle(
                        health.bookmarkIsPersisted
                            ? .secondary : CoveTheme.alert)
            }

            if let issue = health.lastIssue {
                Label(
                    issue,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(CoveTheme.alert)
                actionRow("Retry Vault Refresh", systemName: "arrow.clockwise") {
                    Task {
                        await vaultManager.refresh()
                        await refreshRuntimeHealth()
                    }
                }
            }

            if health.unavailableNoteCount > 0 {
                DisclosureGroup(
                    "\(health.unavailableNoteCount) note\(health.unavailableNoteCount == 1 ? "" : "s") could not be read"
                ) {
                    ForEach(
                        Array(vaultManager.index.indexingFailures.prefix(12).enumerated()),
                        id: \.offset
                    ) { _, failure in
                        NavigationLink {
                            EditorView(fileURL: failure.fileURL)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(failure.fileURL.lastPathComponent)
                                Text(failure.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .foregroundStyle(CoveTheme.alert)
            }

            if health.taskDiagnosticCount > 0 {
                DisclosureGroup(
                    "\(health.taskDiagnosticCount) task format warning\(health.taskDiagnosticCount == 1 ? "" : "s")"
                ) {
                    ForEach(
                        Array(vaultManager.index.taskDiagnostics.prefix(20).enumerated()),
                        id: \.offset
                    ) { _, item in
                        NavigationLink {
                            EditorView(fileURL: item.fileURL)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(
                                    "\(item.fileURL.lastPathComponent), line \(item.diagnostic.lineNumber + 1)"
                                )
                                Text(item.diagnostic.message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                }
                .foregroundStyle(CoveTheme.alert)
            }

            if !health.unresolvedConflictURLs.isEmpty
                || !health.conflictReviewURLs.isEmpty
            {
                DisclosureGroup(
                    "\(health.unresolvedConflictURLs.count + health.conflictReviewURLs.count) conflict item\(health.unresolvedConflictURLs.count + health.conflictReviewURLs.count == 1 ? "" : "s") to review"
                ) {
                    ForEach(
                        Array(
                            Set(
                                health.unresolvedConflictURLs
                                    + health.conflictReviewURLs)
                        ).sorted { $0.path < $1.path },
                        id: \.self
                    ) { url in
                        NavigationLink {
                            EditorView(fileURL: url)
                        } label: {
                            Text(url.lastPathComponent)
                        }
                    }
                }
                .foregroundStyle(CoveTheme.alert)
            }

            NavigationLink {
                RecoveryReviewView()
            } label: {
                CoveRow(
                    systemName: "clock.arrow.circlepath",
                    tint:
                        health.recoveryItemCount + health.recoveryDraftCount > 0
                        ? CoveTheme.accent : .secondary
                ) {
                    Text("Cove Recovery")
                        .font(.body.weight(.medium))
                    Spacer(minLength: 0)
                    CoveCountBadge(
                        "\(health.recoveryItemCount + health.recoveryDraftCount)",
                        tint: CoveTheme.accent)
                }
            }
        } header: {
            CoveSectionHeader("Storage Health")
        } footer: {
            Text(
                "Task warnings never rewrite Markdown automatically. Conflict and recovery copies remain ordinary files for you to review."
            )
        }
    }

    private var storageNeedsAttention: Bool {
        let health = vaultManager.storageHealth
        return health.lastIssue != nil
            || health.unavailableNoteCount > 0
            || health.taskDiagnosticCount > 0
            || !health.unresolvedConflictURLs.isEmpty
            || !health.conflictReviewURLs.isEmpty
            || !health.bookmarkIsPersisted
    }

    private func storageAccessLabel(
        _ access: CoveStorageHealth.AccessState
    ) -> String {
        switch access {
        case .securityScoped:
            "Security Scoped"
        case .directlyAccessible:
            "Direct"
        case .unavailable:
            "Unavailable"
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
            if notificationsEnabled {
                CoveRow(
                    systemName: notificationHealth?.isHealthy == false
                        ? "exclamationmark.triangle.fill" : "clock.badge.checkmark",
                    tint: notificationHealth?.isHealthy == false
                        ? CoveTheme.alert : CoveTheme.moss
                ) {
                    Text("Scheduled Reminders")
                        .font(.body.weight(.medium))
                    Spacer(minLength: 0)
                    CoveCountBadge(
                        "\(pendingReminderCount)",
                        tint: notificationHealth?.isHealthy == false
                            ? CoveTheme.alert : CoveTheme.moss)
                }
            }
            if let notificationErrorMessage {
                Text(notificationErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(CoveTheme.alert)
            }
            if notificationHealth?.state == .failed {
                Text("One or more reminders could not be scheduled.")
                    .font(.footnote)
                    .foregroundStyle(CoveTheme.alert)
                actionRow("Retry Reminder Scheduling", systemName: "arrow.clockwise") {
                    Task {
                        await vaultManager.refresh()
                        await refreshRuntimeHealth()
                    }
                }
            }
            if notificationPlanInventory.omittedBySystemLimit > 0 {
                Text(
                    "\(notificationPlanInventory.omittedBySystemLimit) later reminders are waiting for space in the system limit."
                )
                .font(.footnote)
                .foregroundStyle(CoveTheme.alert)
            }
            if notificationPlanInventory.invalidDateCount > 0 {
                Text(
                    "\(notificationPlanInventory.invalidDateCount) reminder time falls in an invalid local clock moment and was skipped."
                )
                .font(.footnote)
                .foregroundStyle(CoveTheme.alert)
            }
        } header: {
            CoveSectionHeader("Notifications")
        } footer: {
            Text(
                "Tasks with a due time get a reminder at that moment in the current time zone. Cove keeps the next \(TaskNotificationPlanner.maximumPlans) pending; tasks with only a date don’t notify."
            )
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
        let center = UNUserNotificationCenter.current()
        notificationStatus = await center.notificationSettings().authorizationStatus
        pendingReminderCount = await center.pendingNotificationRequests().filter {
            $0.identifier.hasPrefix(TaskNotificationPlanner.identifierPrefix)
        }.count
        notificationPlanInventory = TaskNotificationPlanner.inventory(
            for: vaultManager.index.allTasks,
            now: Date())
    }

    private func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            notificationErrorMessage =
                granted ? nil : "Notification permission was not granted."
        } catch {
            notificationErrorMessage =
                "Cove could not request notification permission. Try again or open System Settings."
        }
        await refreshNotificationStatus()
        // Newly granted permission takes effect on the next rebuild.
        await vaultManager.refresh()
        await refreshNotificationStatus()
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

    private func refreshRuntimeHealth() async {
        await refreshNotificationStatus()
        #if os(iOS)
            widgetHealth = WidgetSnapshotStore().health()
        #endif
    }

    #if os(iOS)
        private var widgetSection: some View {
            Section {
                CoveRow(
                    systemName: widgetStatusIcon,
                    tint: widgetNeedsAttention ? CoveTheme.alert : CoveTheme.moss
                ) {
                    Text("Today Widget")
                        .font(.body.weight(.medium))
                    Spacer(minLength: 0)
                    CoveCountBadge(
                        widgetStatusLabel,
                        tint: widgetNeedsAttention ? CoveTheme.alert : CoveTheme.moss)
                }
                if let health = widgetHealth, health.pendingOperationCount > 0 {
                    Text(
                        "\(health.pendingOperationCount) widget change\(health.pendingOperationCount == 1 ? " is" : "s are") waiting to sync to the vault."
                    )
                    .font(.footnote)
                }
                if let health = widgetHealth,
                    health.failedOperationCount + health.discardedFailureReceiptCount > 0
                {
                    let failureCount =
                        health.failedOperationCount
                        + health.discardedFailureReceiptCount
                    Text(
                        "\(failureCount) widget change\(failureCount == 1 ? " could" : "s could") not be applied. Check the corresponding task in your vault."
                    )
                    .font(.footnote)
                    .foregroundStyle(CoveTheme.alert)
                    actionRow("Dismiss Widget Warning", systemName: "checkmark") {
                        do {
                            try WidgetSnapshotStore().acknowledgeAllFailureHistory()
                            widgetActionErrorMessage = nil
                            widgetHealth = WidgetSnapshotStore().health()
                        } catch {
                            widgetActionErrorMessage =
                                "Cove could not update widget health. Try again after opening the app."
                        }
                    }
                }
                if widgetHealth?.pendingQueueAtCapacity == true {
                    Text("The widget change queue is full. Keep Cove open until pending changes finish syncing.")
                        .font(.footnote)
                        .foregroundStyle(CoveTheme.alert)
                }
                if widgetHealth?.legacyMigrationCleanupPending == true {
                    Text("Cove is still cleaning up an older widget queue.")
                        .font(.footnote)
                        .foregroundStyle(CoveTheme.alert)
                }
                if let availability = widgetHealth?.snapshotAvailability,
                    availability != .available
                {
                    Text(widgetAvailabilityMessage(availability))
                        .font(.footnote)
                        .foregroundStyle(CoveTheme.alert)
                }
                if let error = widgetHealth?.error {
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(CoveTheme.alert)
                }
                if let widgetActionErrorMessage {
                    Text(widgetActionErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(CoveTheme.alert)
                }
            } header: {
                CoveSectionHeader("Widget")
            } footer: {
                Text(
                    "The widget stores a protected, capped snapshot in Cove’s App Group. Markdown remains the source of truth."
                )
            }
        }

        private var widgetNeedsAttention: Bool {
            switch widgetHealth?.state {
            case .unavailable, .needsAttention:
                true
            default:
                false
            }
        }

        private var widgetStatusLabel: String {
            switch widgetHealth?.state {
            case .ready:
                "Ready"
            case .notPublished:
                "Open Cove"
            case .unavailable:
                "Unavailable"
            case .needsAttention:
                "Attention"
            case nil:
                "…"
            }
        }

        private var widgetStatusIcon: String {
            widgetNeedsAttention ? "exclamationmark.triangle.fill" : "rectangle.3.group.fill"
        }

        private func widgetAvailabilityMessage(
            _ availability: TodaySnapshotAvailability
        ) -> String {
            switch availability {
            case .available:
                ""
            case .vaultUnavailable:
                "Reconnect the vault to refresh the Today widget."
            case .sharedContainerUnavailable:
                "The App Group container is unavailable."
            case .unreadable:
                "The widget snapshot could not be read."
            case .notPublished, .stale:
                "Open Cove to refresh the Today widget."
            }
        }
    #endif

}
