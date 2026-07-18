import SwiftUI

/// Single-pane editor for one Markdown note. Loads the file on appearance,
/// autosaves while typing, flushes pending edits when the view goes away or
/// the app leaves the foreground, and reloads from disk after external
/// (iCloud) changes as long as there are no unsaved local edits.
struct EditorView: View {
    @State private var document: NoteDocument
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.scenePhase) private var scenePhase

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
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = document.saveErrorDescription {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(.orange)
            }
        }
        .navigationTitle(document.fileURL.deletingPathExtension().lastPathComponent)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
}
