import Foundation
import Observation

/// State for one open note: loads its contents through the coordinator,
/// tracks edits, and autosaves shortly after typing stops.
@MainActor
@Observable
final class NoteDocument {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    static let autosaveDelay: Duration = .seconds(1)

    let fileURL: URL
    private(set) var loadState: LoadState = .loading
    private(set) var saveErrorDescription: String?

    var text: String = "" {
        didSet {
            guard loadState == .loaded, text != lastSavedText else { return }
            scheduleAutosave()
        }
    }

    private var lastSavedText = ""
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    private let fileOperations = VaultFileOperations()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() async {
        guard loadState == .loading else { return }
        let ops = fileOperations
        let url = fileURL
        do {
            let contents = try await Task.detached(priority: .userInitiated) {
                try ops.readNote(at: url)
            }.value
            lastSavedText = contents
            text = contents
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Cancels any pending autosave and writes immediately. Called when the
    /// editor disappears or the app leaves the foreground.
    func saveNow() async {
        autosaveTask?.cancel()
        autosaveTask = nil
        await save()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    private func save() async {
        guard loadState == .loaded, text != lastSavedText else { return }
        let ops = fileOperations
        let url = fileURL
        let contents = text
        do {
            try await Task.detached(priority: .userInitiated) {
                try ops.saveNote(contents, to: url)
            }.value
            lastSavedText = contents
            saveErrorDescription = nil
        } catch {
            saveErrorDescription = error.localizedDescription
        }
    }
}
