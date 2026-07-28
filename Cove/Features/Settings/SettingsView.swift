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
    @State private var showsStorageDiagnostics = false
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
                advancedSection
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
        let attention = health.attention
        return Section {
            CoveRow(
                systemName: attention.symbol,
                tint: attention.tint
            ) {
                Text("Vault Safety")
                    .font(.body.weight(.medium))
                Spacer(minLength: 0)
                CoveCountBadge(attention.label, tint: attention.tint)
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
                DiagnosticDisclosure(
                    title:
                        "\(health.unavailableNoteCount) note\(health.unavailableNoteCount == 1 ? "" : "s") could not be read",
                    noun: "note",
                    items: vaultManager.index.indexingFailures,
                    destination: { NoteDestination($0.fileURL) }
                ) { failure in
                    Text(failure.fileURL.lastPathComponent)
                    Text(failure.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if health.taskDiagnosticCount > 0 {
                DiagnosticDisclosure(
                    title:
                        "\(health.taskDiagnosticCount) task format warning\(health.taskDiagnosticCount == 1 ? "" : "s")",
                    noun: "warning",
                    items: vaultManager.index.taskDiagnostics,
                    // The row prints a line number, so the editor opens at it.
                    // Naming a line and then landing at the top of the file is
                    // the reader doing the app's arithmetic by hand.
                    destination: {
                        NoteDestination($0.fileURL, line: $0.diagnostic.lineNumber)
                    }
                ) { item in
                    Text(
                        "\(item.fileURL.lastPathComponent), line \(item.diagnostic.lineNumber + 1)"
                    )
                    Text(item.diagnostic.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            if health.subscriptionDiagnosticCount > 0 {
                DiagnosticDisclosure(
                    title:
                        "\(health.subscriptionDiagnosticCount) subscription format warning\(health.subscriptionDiagnosticCount == 1 ? "" : "s")",
                    noun: "warning",
                    items: vaultManager.index.subscriptionDiagnostics,
                    destination: {
                        NoteDestination($0.fileURL, line: $0.diagnostic.lineNumber)
                    }
                ) { item in
                    Text(
                        "\(item.fileURL.lastPathComponent), line \(item.diagnostic.lineNumber + 1)"
                    )
                    Text(item.diagnostic.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            if !conflictURLs.isEmpty {
                DiagnosticDisclosure(
                    title:
                        "\(conflictURLs.count) conflict item\(conflictURLs.count == 1 ? "" : "s") to review",
                    noun: "item",
                    items: conflictURLs,
                    destination: { NoteDestination($0) }
                ) { url in
                    Text(url.lastPathComponent)
                }
            }

        } header: {
            CoveSectionHeader("Storage Health")
        } footer: {
            Text(
                "Format warnings never rewrite Markdown automatically. Conflict and recovery copies remain ordinary files for you to review."
            )
        }
    }

    private var conflictURLs: [URL] {
        let health = vaultManager.storageHealth
        return Array(
            Set(health.unresolvedConflictURLs + health.conflictReviewURLs)
        ).sorted { $0.path < $1.path }
    }

    private func recoveryCaption(_ health: CoveStorageHealth) -> String? {
        var parts: [String] = []
        if health.recoveryDraftCount > 0 {
            parts.append(
                "\(health.recoveryDraftCount) recovered draft\(health.recoveryDraftCount == 1 ? "" : "s")"
            )
        }
        if health.recoveryItemCount > 0 {
            parts.append(
                "\(health.recoveryItemCount) deleted item\(health.recoveryItemCount == 1 ? "" : "s")"
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Advanced

    /// Everything a healthy vault never has to be told.
    ///
    /// Settings is read for four things — which folder, which appearance,
    /// whether reminders are on, and whether anything is wrong — and it had
    /// grown to answer those beside a recovery count, a widget status, a
    /// folder-access mode, and a bookmark state, none of which a reader chose
    /// or can act on while they are healthy. They are here rather than gone
    /// because each one is the whole explanation for something that *does* go
    /// wrong: a bookmark that isn't saved is why a vault keeps asking to be
    /// reselected, a widget that can't reach its container is why a checkbox
    /// on the Home Screen did nothing. So the group opens itself in exactly
    /// those cases, and stays shut the rest of the time.
    ///
    /// A recovery *draft* opens it too, since that is unsaved work waiting for
    /// a decision. A deleted item does not: the recovery area holds them for a
    /// week by design, so any vault where something was recently deleted would
    /// sit permanently open — the same reason `CoveStorageHealth.attention`
    /// refuses to count them.
    private var advancedSection: some View {
        let health = vaultManager.storageHealth
        return Section {
            DisclosureGroup(
                "Advanced",
                isExpanded: Binding(
                    get: { showsStorageDiagnostics || needsAdvancedAttention },
                    set: { showsStorageDiagnostics = $0 })
            ) {
                recoveryRow(health)
                #if os(iOS)
                    widgetRows
                #endif
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
            }
        } footer: {
            Text(
                "Deleted items stay recoverable for a week, and drafts saved from a crash wait here for review. Markdown remains the source of truth for the widget."
            )
        }
    }

    private var needsAdvancedAttention: Bool {
        let health = vaultManager.storageHealth
        if !health.bookmarkIsPersisted { return true }
        if health.recoveryDraftCount > 0 { return true }
        #if os(iOS)
            if widgetNeedsAttention { return true }
            if let widgetHealth,
                widgetHealth.failedOperationCount
                    + widgetHealth.discardedFailureReceiptCount > 0
            {
                return true
            }
        #endif
        return false
    }

    private func recoveryRow(_ health: CoveStorageHealth) -> some View {
        NavigationLink {
            RecoveryReviewView()
        } label: {
            CoveRow(
                systemName: "clock.arrow.circlepath",
                tint:
                    health.recoveryItemCount + health.recoveryDraftCount > 0
                    ? CoveTheme.accent : .secondary
            ) {
                CoveRowTitle(
                    title: "Cove Recovery",
                    caption: recoveryCaption(health))
                Spacer(minLength: 0)
                CoveCountBadge(
                    "\(health.recoveryItemCount + health.recoveryDraftCount)",
                    tint: CoveTheme.accent)
            }
        }
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
                        await vaultManager.rescheduleDerivedState()
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
        // Newly granted permission takes effect on the next reconcile — and
        // it has to be forced, since the task set has not changed and the
        // fingerprint would otherwise skip the one rebuild that matters.
        await vaultManager.rescheduleDerivedState()
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
        /// The Today widget's own health, as rows rather than a section of
        /// their own: when it is working there is one word to say about it,
        /// and it sat under its own header at the bottom of Settings saying
        /// "Ready" to a reader who had not asked.
        @ViewBuilder
        private var widgetRows: some View {
            Group {
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

/// The Vault Safety row's three states, worded and tinted in one place so the
/// row and anything else reporting them cannot disagree.
private extension CoveStorageHealth.Attention {
    var label: String {
        switch self {
        case .ready: "Ready"
        case .recovery: "Recovery"
        case .needsAttention: "Attention"
        }
    }

    var symbol: String {
        switch self {
        case .ready: "checkmark.shield.fill"
        case .recovery: "clock.arrow.circlepath"
        case .needsAttention: "exclamationmark.triangle.fill"
        }
    }

    /// Recovery takes the accent, not the alert: nothing is wrong, there is
    /// simply something waiting. Alert is reserved for a fault.
    var tint: Color {
        switch self {
        case .ready: CoveTheme.moss
        case .recovery: CoveTheme.accent
        case .needsAttention: CoveTheme.alert
        }
    }
}

/// One capped, expandable list of things that are wrong, each row opening the
/// note it is about — at the line, when the diagnostic named one.
///
/// The cap exists so a vault with a thousand bad lines doesn't build a
/// thousand rows into a Settings form. What it used to do was truncate
/// silently, which told the reader they had seen everything when the header
/// directly above said otherwise: "20 task format warnings" over exactly 20
/// rows out of 200. The count of what is hidden, and a way to see it, is the
/// difference between a cap and a lie.
private struct DiagnosticDisclosure<Item, Row: View>: View {
    let title: String
    /// What one item is, for the "Show All N <noun>s" button.
    let noun: String
    let items: [Item]
    let destination: (Item) -> NoteDestination
    @ViewBuilder let row: (Item) -> Row

    @State private var showsAll = false

    private static var limit: Int { 20 }

    private var visible: [Item] {
        showsAll ? items : Array(items.prefix(Self.limit))
    }

    var body: some View {
        DisclosureGroup(title) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, item in
                NavigationLink {
                    EditorView(destination(item))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        row(item)
                    }
                }
            }
            if items.count > Self.limit {
                let hidden = items.count - visible.count
                Button {
                    showsAll.toggle()
                } label: {
                    Text(
                        showsAll
                            ? "Show Fewer"
                            : "Show All \(items.count) \(noun)s (\(hidden) more)"
                    )
                    .font(.footnote.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
        }
        .foregroundStyle(CoveTheme.alert)
    }
}
