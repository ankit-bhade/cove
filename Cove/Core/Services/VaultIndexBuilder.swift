import Foundation

/// Builds the in-memory vault index from an already-scanned tree: one entry
/// per Markdown file with its title and due tasks. Every file is read with a
/// coordinated read; unreadable files index with no tasks.
///
/// The capture note at the vault root parses `sectioned`, so its `##`
/// headings become lists and the tasks under them may be undated. Every
/// other note parses under the strict, unsectioned rules.
struct VaultIndexBuilder: Sendable {
    private let fileOperations = VaultFileOperations()

    func buildIndex(from root: VaultNode) throws -> VaultIndex {
        try buildCancellableIndex(from: root)
    }

    func buildCancellableIndex(from root: VaultNode,
                               previous: VaultIndex = VaultIndex(),
                               changedURLs: Set<URL>? = nil) throws -> VaultIndex {
        var listNames: [String] = []
        var entries: [NoteIndexEntry] = []
        let previousByURL = Dictionary(uniqueKeysWithValues: previous.entries.map {
            ($0.url.standardizedFileURL, $0)
        })
        let forcedChanges = changedURLs.map {
            Set($0.map(\.standardizedFileURL))
        }
        for node in root.allFiles {
            try Task.checkCancellation()
            let sectioned = VaultManager.isCaptureNote(node.url, vaultRoot: root.url)
            let values = try? node.url.resourceValues(forKeys: [.contentModificationDateKey,
                                                                .fileSizeKey])
            if let cached = previousByURL[node.url.standardizedFileURL],
               forcedChanges?.contains(node.url.standardizedFileURL) != true,
               let modificationDate = values?.contentModificationDate,
               let fileSize = values?.fileSize,
               cached.modificationDate == modificationDate,
               cached.fileSize == fileSize {
                entries.append(cached)
                if sectioned { listNames = cached.listNames }
                continue
            }
            let text: String
            do {
                text = try fileOperations.readNote(at: node.url)
            } catch {
                // One note the app can't read — text that isn't UTF-8, a file
                // iCloud hasn't materialized — must not take the whole vault
                // down with it. The entry is kept with no tasks and no cache
                // key, so the next rebuild tries the file again.
                CoveLog.index.error("Skipped unreadable note \(node.displayName, privacy: .public): \(error.localizedDescription, privacy: .private)")
                entries.append(NoteIndexEntry(url: node.url,
                                              title: node.displayName,
                                              tasks: [],
                                              listNames: [],
                                              modificationDate: nil,
                                              fileSize: nil))
                continue
            }
            var noteListNames: [String] = []
            if sectioned {
                noteListNames = TaskListDocument.sectionNames(in: text)
                listNames = noteListNames
            }
            let tasks = TaskParser.tasks(in: text, sectioned: sectioned)
                .map { parsed in
                    TaskItem(fileURL: node.url,
                             fileTitle: node.displayName,
                             lineNumber: parsed.lineNumber,
                             text: parsed.text,
                             dueDateString: parsed.dueDateString,
                             dueTimeString: parsed.dueTimeString,
                             recurrence: parsed.recurrence,
                             isCompleted: parsed.isCompleted,
                             listName: parsed.listName)
                }
            entries.append(NoteIndexEntry(url: node.url,
                                          title: node.displayName,
                                          tasks: tasks,
                                          listNames: noteListNames,
                                          modificationDate: values?.contentModificationDate,
                                          fileSize: values?.fileSize))
        }
        try Task.checkCancellation()
        return VaultIndex(entries: entries, listNames: listNames)
    }
}
