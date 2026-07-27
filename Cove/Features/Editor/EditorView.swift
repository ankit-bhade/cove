import SwiftUI

/// Single-pane editor for one Markdown note. Loads the file on appearance,
/// autosaves while typing, flushes pending edits when the view goes away or
/// the app leaves the foreground, and reloads from disk after external
/// (iCloud) changes as long as there are no unsaved local edits.
struct EditorView: View {
    @State private var document: NoteDocument
    @State private var checkboxErrorMessage: String?
    @State private var isConfirmingRecoveredDraftDiscard = false
    /// Handed to the text view once the note has loaded, and cleared there.
    /// It cannot be applied before the load: there is no text to find a line
    /// in until then, and the text view does not exist until `.loaded`.
    @State private var focusLine: Int?
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.scenePhase) private var scenePhase

    /// The line this note was opened at, if the caller knew one. Zero-based.
    private let requestedLine: Int?

    init(fileURL: URL, line: Int? = nil) {
        _document = State(initialValue: NoteDocument(fileURL: fileURL))
        requestedLine = line
    }

    init(_ destination: NoteDestination) {
        self.init(fileURL: destination.url, line: destination.line)
    }

    var body: some View {
        Group {
            switch document.loadState {
            case .loading:
                ProgressView()
            case .failed(let message):
                CoveEmptyState(
                    "Can’t Open Note",
                    systemName: "exclamationmark.triangle",
                    description: message
                )
            case .loaded:
                // The measure a person can actually read a line at. Left
                // unbounded, a maximized Mac window sets Markdown across
                // two feet of screen.
                MarkdownTextView(
                    text: $document.text,
                    sectionedTaskDocument:
                        vaultManager.vaultURL.map {
                            VaultManager.isCaptureNote(
                                document.fileURL,
                                vaultRoot: $0)
                        } ?? false,
                    checkboxError: $checkboxErrorMessage,
                    focusLine: $focusLine
                )
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(CoveTheme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            if document.saveErrorDescription != nil || document.conflictDescription != nil
                || document.recoveredDraftDescription != nil
                || checkboxErrorMessage != nil
            {
                VStack(spacing: 8) {
                    if let checkboxErrorMessage {
                        Label(
                            checkboxErrorMessage,
                            systemImage: "exclamationmark.triangle"
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .modifier(EditorBanner(tint: CoveTheme.alert))
                    }
                    if let message = document.recoveredDraftDescription {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(message, systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack {
                                Button("Discard Draft", role: .destructive) {
                                    isConfirmingRecoveredDraftDiscard = true
                                }
                                Spacer()
                                if document.saveErrorDescription != nil,
                                    let vaultRoot = vaultManager.vaultURL
                                {
                                    Button("Save Recovery Copy") {
                                        Task {
                                            await document.saveRecoveryCopy(
                                                in: vaultRoot)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                } else {
                                    Button("Save Recovered Edits") {
                                        Task { await document.acceptRecoveredDraft() }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        }
                        .modifier(EditorBanner(tint: CoveTheme.moss))
                    }
                    if let message = document.saveErrorDescription {
                        HStack {
                            Label(message, systemImage: "exclamationmark.triangle")
                            Spacer()
                            Button("Retry") {
                                Task { await document.retrySave() }
                            }
                            .buttonStyle(.bordered)
                            if document.isDirty,
                                let vaultRoot = vaultManager.vaultURL
                            {
                                Button("Save Copy") {
                                    Task {
                                        await document.saveRecoveryCopy(
                                            in: vaultRoot)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .modifier(EditorBanner(tint: CoveTheme.alert))
                    }
                    if let message = document.conflictDescription {
                        HStack {
                            Label(message, systemImage: "doc.on.doc")
                            Spacer(minLength: 8)
                            // A banner that names a file and offers no way to
                            // reach it makes the reader go and find it in the
                            // browser. It is a note like any other, so the
                            // same push that opens one opens this.
                            if let copyURL = document.preservedCopyURL {
                                NavigationLink(value: NoteDestination(copyURL)) {
                                    Text("Open Copy")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(EditorBanner(tint: CoveTheme.accent))
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
        .navigationTitle(document.fileURL.deletingPathExtension().lastPathComponent)
        .confirmationDialog(
            "Discard Recovered Draft?",
            isPresented: $isConfirmingRecoveredDraftDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Recovered Draft", role: .destructive) {
                Task { await document.discardRecoveredDraft() }
            }
            Button("Keep Draft", role: .cancel) {}
        } message: {
            Text(
                "This permanently removes the recovered edits and reloads the last saved version of the note."
            )
        }
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
            document.onPersisted = { url in
                Task { await vaultManager.noteDidPersist(at: url) }
            }
            await document.load()
            updateEditorProtection()
            // After the load, not before: the text view only exists in the
            // loaded state, and there is nothing to count lines in until the
            // file has been read.
            focusLine = requestedLine
        }
        .onDisappear {
            let document = document
            document.prepareForSuspension()
            Task {
                await document.flush()
                vaultManager.setEditorProtection(false, for: document.fileURL)
                if let error = document.saveErrorDescription {
                    vaultManager.reportStorageIssue(error)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await document.reloadAfterExternalChange() }
            } else {
                document.prepareForSuspension()
                Task { await document.flush() }
            }
        }
        .onChange(of: document.protectsAgainstNavigationPruning) { _, _ in
            updateEditorProtection()
        }
        .onChange(of: document.saveErrorDescription) { _, message in
            if let message {
                vaultManager.reportStorageIssue(message)
            }
        }
        .onChange(of: vaultManager.externalChangeCount) { _, _ in
            Task { await document.reloadAfterExternalChange() }
        }
    }

    private func updateEditorProtection() {
        vaultManager.setEditorProtection(
            document.protectsAgainstNavigationPruning,
            for: document.fileURL)
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
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil)
        }
    #endif
}

/// The editor's two notices — a failed save and a preserved conflict — drawn
/// the same way so one doesn't read as more serious than its tint says.
private struct EditorBanner: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .font(.footnote)
            .foregroundStyle(.primary)
            .padding(11)
            .coveTintedSurface(
                tint,
                in: RoundedRectangle(
                    cornerRadius: CoveTheme.fieldRadius,
                    style: .continuous)
            )
    }
}

private extension NoteDocument.SaveStatus {
    var label: String {
        switch self {
        case .saved: "Saved"
        case .pending: "Editing…"
        case .saving: "Saving…"
        case .failed: "Not Saved"
        case .awaitingReview: "Held for Review"
        }
    }

    var symbol: String {
        switch self {
        case .saved: "checkmark.circle.fill"
        case .pending: "pencil.circle"
        case .saving: "arrow.triangle.2.circlepath"
        case .awaitingReview: "clock.arrow.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .saved: "All changes saved"
        case .pending: "Unsaved changes, saving shortly"
        case .saving: "Saving"
        case .failed: "Save failed"
        case .awaitingReview:
            "Recovered edits are held until you save or discard them"
        }
    }
}
