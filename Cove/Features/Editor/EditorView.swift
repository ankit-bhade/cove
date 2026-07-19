import SwiftUI

/// Single-pane editor for one Markdown note. Loads the file on appearance,
/// autosaves while typing, flushes pending edits when the view goes away or
/// the app leaves the foreground, and reloads from disk after external
/// (iCloud) changes as long as there are no unsaved local edits.
struct EditorView: View {
    @State private var document: NoteDocument
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    init(fileURL: URL) {
        _document = State(initialValue: NoteDocument(fileURL: fileURL))
    }

    var body: some View {
        Group {
            switch document.loadState {
            case .loading:
                ProgressView()
            case .failed(let message):
                ContentUnavailableView(
                    "Can’t Open Note",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            case .loaded:
                MarkdownTextView(text: $document.text)
                    .background(CoveTheme.canvas(for: colorScheme))
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = document.saveErrorDescription {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .background(.orange.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
        }
        .navigationTitle(document.fileURL.deletingPathExtension().lastPathComponent)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                saveStatusIndicator
            }
            #if os(iOS)
            // A UITextView has no return key to dismiss with, so without an
            // explicit action the keyboard covers the note with no way out.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
                    .fontWeight(.semibold)
            }
            #endif
        }
        .task {
            await document.load()
        }
        .onDisappear {
            let document = document
            Task { await document.saveNow() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await document.reloadAfterExternalChange() }
            } else {
                Task { await document.saveNow() }
            }
        }
        .onChange(of: vaultManager.externalChangeCount) { _, _ in
            Task { await document.reloadAfterExternalChange() }
        }
    }

    /// Reflects the document's real state rather than asserting that saving
    /// happens. Silent once everything is on disk: a permanent "Saved" chip
    /// is chrome that also reads as a button it isn't, and the failure case
    /// already has the banner above.
    @ViewBuilder
    private var saveStatusIndicator: some View {
        let status = document.saveStatus
        if document.loadState == .loaded, status != .saved, status != .failed {
            Label(status.label, systemImage: status.symbol)
                // The toolbar collapses a Label to its icon by default,
                // which loses the only part that carries the meaning.
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(status.accessibilityLabel)
        }
    }

    #if os(iOS)
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
    #endif
}

private extension NoteDocument.SaveStatus {
    var label: String {
        switch self {
        case .saved: "Saved"
        case .pending: "Editing…"
        case .saving: "Saving…"
        case .failed: "Not Saved"
        }
    }

    var symbol: String {
        switch self {
        case .saved: "checkmark.circle.fill"
        case .pending: "pencil.circle"
        case .saving: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .saved: "All changes saved"
        case .pending: "Unsaved changes, saving shortly"
        case .saving: "Saving"
        case .failed: "Save failed"
        }
    }
}
