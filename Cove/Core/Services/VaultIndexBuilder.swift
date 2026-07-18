import Foundation

/// Builds the in-memory vault index from an already-scanned tree: one entry
/// per Markdown file with its title and due tasks. Every file is read with a
/// coordinated read; unreadable files index with no tasks.
struct VaultIndexBuilder: Sendable {
    private let fileOperations = VaultFileOperations()

    func buildIndex(from root: VaultNode) -> VaultIndex {
        let entries = root.allFiles.map { node in
            let tasks = ((try? fileOperations.readNote(at: node.url))
                .map(TaskParser.tasks(in:)) ?? [])
                .map { parsed in
                    TaskItem(fileURL: node.url,
                             fileTitle: node.displayName,
                             lineNumber: parsed.lineNumber,
                             text: parsed.text,
                             dueDateString: parsed.dueDateString,
                             dueTimeString: parsed.dueTimeString,
                             recurrence: parsed.recurrence,
                             isCompleted: parsed.isCompleted)
                }
            return NoteIndexEntry(url: node.url, title: node.displayName, tasks: tasks)
        }
        return VaultIndex(entries: entries)
    }
}
