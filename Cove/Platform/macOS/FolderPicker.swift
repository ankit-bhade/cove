#if os(macOS)
    import AppKit

    enum FolderPicker {
        /// Presents `NSOpenPanel` configured for choosing a single folder.
        @MainActor
        static func chooseFolder() -> URL? {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "Select Vault"
            panel.message = "Choose the folder that holds your Markdown notes."
            return panel.runModal() == .OK ? panel.url : nil
        }
    }
#endif
