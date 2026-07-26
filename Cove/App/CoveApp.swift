import SwiftUI

@main
struct CoveApp: App {
    @State private var vaultManager: VaultManager

    init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            // Hosted unit tests launch Cove.app before the selected test
            // bundle. Give that host an empty bookmark domain and inert
            // system-service boundaries so merely running tests can never
            // open the developer's vault, reconcile real notifications, or
            // mutate the signed App Group container.
            let defaults =
                UserDefaults(
                    suiteName:
                        "com.ankitbhade.Cove.TestHost.\(ProcessInfo.processInfo.processIdentifier)"
                ) ?? .standard
            let widgetContainer = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "cove-test-host-widget-\(ProcessInfo.processInfo.processIdentifier)",
                    isDirectory: true)
            try? FileManager.default.createDirectory(
                at: widgetContainer,
                withIntermediateDirectories: true)
            _vaultManager = State(
                initialValue: VaultManager(
                    bookmarkStore: VaultBookmarkStore(
                        defaults: defaults,
                        creationOptions: [],
                        resolutionOptions: []),
                    notificationRebuild: { _ in .superseded() },
                    notificationCancel: { .superseded() },
                    widgetStore: WidgetSnapshotStore(containerURL: widgetContainer),
                    reloadWidgetTimelines: {}))
        } else {
            _vaultManager = State(initialValue: VaultManager())
        }
        #if os(iOS)
            NavigationBarAppearance.apply()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(vaultManager)
                .tint(CoveTheme.accent)
        }
        #if os(macOS)
            .defaultSize(width: 980, height: 700)
        #endif
    }
}
