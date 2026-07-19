import SwiftUI

/// First-launch empty state: no vault has been selected yet.
struct WelcomeView: View {
    var body: some View {
        ZStack {
            CoveBrandBackground()
            setupCard(
                title: "Welcome to Cove",
                message: "A quiet home for the Markdown notes you already own.",
                detail: "Choose any folder to begin. Cove keeps your files local and saves every edit automatically."
            ) {
                VaultPickerButton(title: "Choose a Notes Folder")
            }
        }
    }

    private func setupCard<Actions: View>(
        title: String,
        message: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 24) {
            Image("LaunchIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: CoveTheme.navy.opacity(0.22), radius: 24, y: 12)
            VStack(spacing: 10) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                Text(message)
                    .font(.title3.weight(.medium))
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            actions()
                .controlSize(.large)
        }
        .frame(maxWidth: 440)
        .padding(40)
        .background { CoveCardBackground(cornerRadius: 28) }
        .padding(24)
    }
}

/// Shown when the saved bookmark is stale or the vault can't be read.
struct VaultRecoveryView: View {
    @Environment(VaultManager.self) private var vaultManager

    var body: some View {
        ZStack {
            CoveBrandBackground()
            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.orange.opacity(0.12))
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(.orange)
                }
                .frame(width: 88, height: 88)
                VStack(spacing: 10) {
                    Text("Let’s Reconnect Your Vault")
                        .font(.title.weight(.bold))
                    Text("The folder may have moved, been renamed, or no longer be available on this device.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                if let message = vaultManager.lastErrorDescription {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VaultPickerButton(title: "Choose Vault Folder")
                    .controlSize(.large)
            }
            .frame(maxWidth: 440)
            .padding(40)
            .background { CoveCardBackground(cornerRadius: 28) }
            .padding(24)
        }
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
        Button {
            isPickerPresented = true
        } label: {
            Label(title, systemImage: "folder.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .sheet(isPresented: $isPickerPresented) {
            FolderPickerView { url in
                Task { await vaultManager.openVault(at: url) }
            }
        }
    }
    #else
    var body: some View {
        Button {
            if let url = FolderPicker.chooseFolder() {
                Task { await vaultManager.openVault(at: url) }
            }
        } label: {
            Label(title, systemImage: "folder.badge.plus")
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
    }
    #endif
}
