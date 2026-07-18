import SwiftUI

/// First-launch empty state: no vault has been selected yet.
struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Welcome to Cove")
                .font(.title2.bold())
            Text("Choose a folder of Markdown files to use as your vault.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VaultPickerButton(title: "Select Vault Folder")
        }
        .padding(32)
    }
}

/// Shown when the saved bookmark is stale or the vault can't be read.
struct VaultRecoveryView: View {
    @Environment(VaultManager.self) private var vaultManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("Vault Unavailable")
                .font(.title2.bold())
            Text("Cove can no longer access the previously selected vault. It may have been moved, renamed, or deleted.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let message = vaultManager.lastErrorDescription {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VaultPickerButton(title: "Reselect Vault")
        }
        .padding(32)
    }
}

/// Button that presents the platform folder picker and opens the picked
/// folder as the vault.
struct VaultPickerButton: View {
    @Environment(VaultManager.self) private var vaultManager
    let title: String

    #if os(iOS)
    @State private var isPickerPresented = false

    var body: some View {
        Button(title) {
            isPickerPresented = true
        }
        .buttonStyle(.borderedProminent)
        .sheet(isPresented: $isPickerPresented) {
            FolderPickerView { url in
                Task { await vaultManager.openVault(at: url) }
            }
        }
    }
    #else
    var body: some View {
        Button(title) {
            if let url = FolderPicker.chooseFolder() {
                Task { await vaultManager.openVault(at: url) }
            }
        }
        .buttonStyle(.borderedProminent)
    }
    #endif
}
