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

    func buildIndex(from root: VaultNode) -> VaultIndex {
        var listNames: [String] = []
        let entries = root.allFiles.map { node in
            let sectioned = VaultManager.isCaptureNote(node.url, vaultRoot: root.url)
            let text = try? fileOperations.readNote(at: node.url)
            if sectioned, let text {
                listNames = TaskListDocument.sectionNames(in: text)
            }
            let tasks = (text.map { TaskParser.tasks(in: $0, sectioned: sectioned) } ?? [])
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
            return NoteIndexEntry(url: node.url, title: node.displayName, tasks: tasks)
        }
        return VaultIndex(entries: entries, listNames: listNames)
    }
}
