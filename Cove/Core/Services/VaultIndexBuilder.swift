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

    func buildCancellableIndex(
        from root: VaultNode,
        previous: VaultIndex = VaultIndex(),
        changedURLs: Set<URL>? = nil
    ) throws -> VaultIndex {
        var listNames: [String] = []
        var subscriptionCategoryNames: [String] = []
        var entries: [NoteIndexEntry] = []
        let previousByURL = Dictionary(
            uniqueKeysWithValues: previous.entries.map {
                ($0.url.standardizedFileURL, $0)
            })
        let forcedChanges = changedURLs.map {
            Set($0.map(\.standardizedFileURL))
        }
        for node in root.allFiles {
            try Task.checkCancellation()
            let sectioned = VaultManager.isCaptureNote(node.url, vaultRoot: root.url)
            let tracksSubscriptions = VaultManager.isSubscriptionNote(
                node.url, vaultRoot: root.url)
            let values: URLResourceValues?
            do {
                values = try node.url.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                ])
            } catch {
                values = nil
                CoveLog.index.error(
                    "Note metadata could not be read: \(error.localizedDescription, privacy: .private)")
            }
            // A nil changed set means a catch-all/foreground reconciliation,
            // not "nothing changed." Re-read in that case so a same-size edit
            // whose timestamp was preserved by another tool cannot leave a
            // stale index. Precise observer/app mutation sets may safely reuse
            // every URL they did not name.
            if changedURLs != nil,
                let cached = previousByURL[node.url.standardizedFileURL],
                forcedChanges?.contains(node.url.standardizedFileURL) != true,
                let modificationDate = values?.contentModificationDate,
                let fileSize = values?.fileSize,
                cached.modificationDate == modificationDate,
                cached.fileSize == fileSize
            {
                entries.append(cached)
                if sectioned { listNames = cached.listNames }
                if tracksSubscriptions {
                    subscriptionCategoryNames = cached.subscriptionCategoryNames
                }
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
                CoveLog.index.error(
                    "Could not refresh one note: \(error.localizedDescription, privacy: .private)"
                )
                // A temporary provider/download failure must not silently
                // erase tasks and consequently cancel their reminders. Keep
                // the last-known-good derived state but remove its cache key,
                // which forces another read on the next rebuild.
                if let cached = previousByURL[node.url.standardizedFileURL] {
                    entries.append(
                        NoteIndexEntry(
                            url: cached.url,
                            title: cached.title,
                            tasks: cached.tasks,
                            listNames: cached.listNames,
                            subscriptions: cached.subscriptions,
                            subscriptionCategoryNames: cached.subscriptionCategoryNames,
                            taskDiagnostics: cached.taskDiagnostics,
                            subscriptionDiagnostics: cached.subscriptionDiagnostics,
                            indexingErrorDescription: error.localizedDescription,
                            modificationDate: nil,
                            fileSize: nil))
                    if sectioned { listNames = cached.listNames }
                    if tracksSubscriptions {
                        subscriptionCategoryNames = cached.subscriptionCategoryNames
                    }
                } else {
                    entries.append(
                        NoteIndexEntry(
                            url: node.url,
                            title: node.displayName,
                            tasks: [],
                            listNames: [],
                            indexingErrorDescription: error.localizedDescription,
                            modificationDate: nil,
                            fileSize: nil))
                }
                continue
            }
            var noteListNames: [String] = []
            let isOperationallyExcluded =
                VaultFileOperations.isOperationallyExcludedDocument(node.url)
            if sectioned && !isOperationallyExcluded {
                noteListNames = TaskListDocument.sectionNames(in: text)
                listNames = noteListNames
            }
            // Subscriptions are parsed for the one note at the vault root that
            // tracks them, exactly as `##` headings mean lists in the one
            // capture note. Every other note keeps `- Name @cost(…)` as
            // ordinary text.
            var noteSubscriptions: [Subscription] = []
            var noteSubscriptionCategories: [String] = []
            var noteSubscriptionDiagnostics: [SubscriptionParser.Diagnostic] = []
            if tracksSubscriptions && !isOperationallyExcluded {
                let scan = SubscriptionParser.scan(in: text)
                noteSubscriptionCategories = SubscriptionParser.categoryNames(in: text)
                subscriptionCategoryNames = noteSubscriptionCategories
                noteSubscriptionDiagnostics = scan.diagnostics
                noteSubscriptions = scan.subscriptions.map { parsed in
                    Subscription(
                        fileURL: node.url,
                        lineNumber: parsed.lineNumber,
                        name: parsed.name,
                        cost: parsed.cost,
                        cycle: parsed.cycle,
                        firstChargeDateString: parsed.firstChargeDateString,
                        status: parsed.status,
                        category: parsed.category,
                        sourceLine: parsed.sourceLine)
                }
            }
            let taskScan =
                isOperationallyExcluded
                ? nil : TaskParser.scan(in: text, sectioned: sectioned)
            let parsedTasks = taskScan?.tasks ?? []
            let tasks =
                parsedTasks
                .map { parsed in
                    TaskItem(
                        fileURL: node.url,
                        fileTitle: node.displayName,
                        lineNumber: parsed.lineNumber,
                        text: parsed.text,
                        dueDateString: parsed.dueDateString,
                        dueTimeString: parsed.dueTimeString,
                        recurrence: parsed.recurrence,
                        isCompleted: parsed.isCompleted,
                        listName: parsed.listName,
                        recurrenceAnchorDateString:
                            parsed.recurrenceAnchorDateString,
                        isSectionedDocument: sectioned,
                        sourceLine: parsed.sourceLine)
                }
            entries.append(
                NoteIndexEntry(
                    url: node.url,
                    title: node.displayName,
                    tasks: tasks,
                    listNames: noteListNames,
                    subscriptions: noteSubscriptions,
                    subscriptionCategoryNames: noteSubscriptionCategories,
                    taskDiagnostics: taskScan?.diagnostics ?? [],
                    subscriptionDiagnostics: noteSubscriptionDiagnostics,
                    modificationDate: values?.contentModificationDate,
                    fileSize: values?.fileSize))
        }
        try Task.checkCancellation()
        return VaultIndex(
            entries: entries,
            listNames: listNames,
            subscriptionCategoryNames: subscriptionCategoryNames)
    }
}
