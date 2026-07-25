import SwiftUI

/// Review surface for Cove's two recovery channels: deleted vault items and
/// crash-journaled editor drafts. Nothing is restored over an existing file,
/// and discarding the only draft copy always requires confirmation.
struct RecoveryReviewView: View {
    @Environment(VaultManager.self) private var vaultManager

    @State private var records: [RecoveryRecord] = []
    @State private var drafts: [EditorRecoveryDraftSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var noticeMessage: String?
    @State private var recoveryNeedingName: RecoveryRecord?
    @State private var draftToDiscard: EditorRecoveryDraftSummary?
    @State private var nameInput = ""

    var body: some View {
        List {
            if records.isEmpty, drafts.isEmpty, !isLoading {
                CoveEmptyState(
                    "Nothing to Recover",
                    systemName: "checkmark.circle",
                    description:
                        "Deleted items and unsaved editor drafts will appear here."
                )
                .listRowBackground(Color.clear)
            }
            if !records.isEmpty {
                Section {
                    ForEach(records, id: \.identifier) { record in
                        recoveryRow(record)
                    }
                } header: {
                    CoveSectionHeader(
                        "Deleted Items",
                        count: records.count)
                } footer: {
                    Text(
                        "Deleted items remain in the vault’s hidden recovery area for seven days."
                    )
                }
            }
            if !drafts.isEmpty {
                Section {
                    ForEach(drafts, id: \.originalURL) { draft in
                        draftRow(draft)
                    }
                } header: {
                    CoveSectionHeader(
                        "Unsaved Drafts",
                        count: drafts.count)
                } footer: {
                    Text(
                        "Save Copy creates a review-only Markdown note at the vault root. Rename it after checking the contents to make its tasks active."
                    )
                }
            }
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Cove Recovery")
        .task { await load() }
        .refreshable { await load() }
        .alert(
            "Original Name In Use",
            isPresented: $recoveryNeedingName.covePresence(),
            presenting: recoveryNeedingName
        ) { record in
            TextField("New name", text: $nameInput)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Restore") {
                restore(record, as: trimmedName)
            }
            .disabled(trimmedName.isEmpty)
        } message: { record in
            Text(
                "“\(record.originalURL.lastPathComponent)” now exists. Choose a new name for the recovered item."
            )
        }
        .confirmationDialog(
            "Discard this recovery draft?",
            isPresented: $draftToDiscard.covePresence(),
            presenting: draftToDiscard
        ) { draft in
            Button("Discard Draft", role: .destructive) {
                discard(draft)
            }
        } message: { draft in
            Text(
                "The unsaved edits for “\(draft.originalURL.lastPathComponent)” will be permanently removed."
            )
        }
        .alert(
            "Recovery Complete",
            isPresented: $noticeMessage.covePresence()
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noticeMessage ?? "")
        }
        .coveErrorAlert($errorMessage)
    }

    private func recoveryRow(_ record: RecoveryRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(record.originalURL.lastPathComponent)
                .font(.body.weight(.medium))
            Text(
                "Deleted \(record.deletedAt.formatted(date: .abbreviated, time: .shortened))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(
                record.originalURL.deletingLastPathComponent()
                    .path(percentEncoded: false)
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .textSelection(.enabled)
            Button("Restore") {
                restore(record)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private func draftRow(_ draft: EditorRecoveryDraftSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(draft.originalURL.lastPathComponent)
                .font(.body.weight(.medium))
            Text(
                "Last preserved \(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(draft.originalURL.path(percentEncoded: false))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
            HStack {
                Button("Discard", role: .destructive) {
                    draftToDiscard = draft
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Save Copy") {
                    export(draft)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }

    private var trimmedName: String {
        nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let loadedRecords = vaultManager.recoveryRecords()
            async let loadedDrafts = vaultManager.recoveryDrafts()
            records = try await loadedRecords
            drafts = try await loadedDrafts
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ record: RecoveryRecord) {
        Task {
            do {
                try await vaultManager.restoreDeletedItem(record)
                await load()
            } catch VaultFileOperations.OperationError.itemAlreadyExists(_) {
                nameInput =
                    record.originalURL.deletingPathExtension()
                    .lastPathComponent + " Recovered"
                recoveryNeedingName = record
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore(_ record: RecoveryRecord, as name: String) {
        Task {
            do {
                try await vaultManager.restoreDeletedItem(
                    record,
                    as: name)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func export(_ draft: EditorRecoveryDraftSummary) {
        Task {
            do {
                let url = try await vaultManager.exportRecoveryDraft(draft)
                noticeMessage =
                    "Saved \(url.lastPathComponent) at the vault root."
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func discard(_ draft: EditorRecoveryDraftSummary) {
        Task {
            do {
                try await vaultManager.discardRecoveryDraft(draft)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
