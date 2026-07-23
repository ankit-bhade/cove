import SwiftUI

/// First-launch empty state: no vault has been selected yet.
struct WelcomeView: View {
    var body: some View {
        ZStack {
            CoveBrandBackground()
            GeometryReader { proxy in
                ScrollView {
                    setupCard(
                        title: "Welcome to Cove",
                        message: "A quiet home for the Markdown notes you already own.",
                        detail: "Choose any folder to begin. Cove keeps your files local and saves every edit automatically."
                    ) {
                        VaultPickerButton(title: "Choose a Notes Folder")
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func setupCard<Actions: View>(
        title: String,
        message: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: CoveTheme.Space.loose) {
            CoveMark(size: 88)
                .shadow(color: CoveTheme.ink.opacity(0.20), radius: 22, y: 11)
            VStack(spacing: CoveTheme.Space.snug) {
                Text(title)
                    .font(.coveDisplayLarge)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
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
        .padding(.horizontal, 28)
        .padding(.vertical, 34)
        .background { CoveCardBackground(cornerRadius: 26) }
        .padding(24)
    }
}

/// Shown when the saved bookmark is stale or the vault can't be read.
struct VaultRecoveryView: View {
    @Environment(VaultManager.self) private var vaultManager

    var body: some View {
        ZStack {
            CoveBrandBackground()
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: CoveTheme.Space.loose) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(CoveTheme.alert.opacity(0.12))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(CoveTheme.alert.opacity(0.18), lineWidth: 1)
                                }
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 34, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(CoveTheme.alert)
                        }
                        .frame(width: 84, height: 84)
                        .accessibilityHidden(true)
                        VStack(spacing: CoveTheme.Space.snug) {
                            Text("Let’s Reconnect Your Vault")
                                .font(.coveDisplay)
                                .multilineTextAlignment(.center)
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
                                .background(CoveTheme.canvas,
                                            in: RoundedRectangle(cornerRadius: CoveTheme.fieldRadius,
                                                                 style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: CoveTheme.fieldRadius,
                                                     style: .continuous)
                                        .stroke(CoveTheme.hairline, lineWidth: 1)
                                }
                        }
                        VaultPickerButton(title: "Choose Vault Folder")
                            .controlSize(.large)
                    }
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 34)
                    .background { CoveCardBackground(cornerRadius: 26) }
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

/// Button that presents the platform folder picker and opens the picked
/// folder as the vault.
struct VaultPickerButton: View {
    @Environment(VaultManager.self) private var vaultManager
    let title: String
    var prominent = true

    #if os(iOS)
    @State private var isPickerPresented = false

    var body: some View {
        pickerButton {
            isPickerPresented = true
        }
        .sheet(isPresented: $isPickerPresented) {
            FolderPickerView { url in
                Task { await vaultManager.openVault(at: url) }
            }
        }
    }
    #else
    var body: some View {
        pickerButton {
            if let url = FolderPicker.chooseFolder() {
                Task { await vaultManager.openVault(at: url) }
            }
        }
    }
    #endif

    @ViewBuilder
    private func pickerButton(action: @escaping () -> Void) -> some View {
        if prominent {
            Button(action: action) {
                Label(title, systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: CoveTheme.fieldRadius))
        } else {
            // Inside Settings this button is one row among several, all of
            // which lead with a `CoveIconTile`. A bare symbol here rendered
            // at body size — larger and heavier than every tile above it,
            // and starting at a different leading edge.
            Button(action: action) {
                Label {
                    Text(title)
                } icon: {
                    CoveIconTile(systemName: "folder.badge.plus")
                }
            }
            .buttonStyle(.borderless)
        }
    }
}
