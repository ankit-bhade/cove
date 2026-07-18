# Cove

Cove is a minimal native Markdown notes app for iPhone, iPad, and Mac. You
point it at a folder of Markdown files — typically in iCloud Drive — and that
folder is the single source of truth. There is no backend, no account, no
database, and no custom sync.

Current state (Phase 5): select a vault folder, browse its nested folders and
Markdown files, and open any note in a live-styled Markdown editor that saves
automatically as you type. Headers and `**bold**` spans are styled in place
(the text stays plain Markdown), and `- [ ]` checkboxes toggle with a tap or
click. Notes and folders can be created, renamed, moved, and deleted from the
browser (long-press or right-click a row, or use the + toolbar menu). For a
vault in iCloud Drive, changes made outside the app — edits syncing in from
another device, or files added or removed in Finder or the Files app — are
detected while the app runs: the folder tree refreshes itself, and an open
note reloads the new contents as long as you have no unsaved edits (your
typing is never discarded; iCloud shows a true both-sides conflict as a
separate conflict copy). Vaults outside iCloud Drive refresh whenever the
app returns to the foreground. The search field in the browser searches every
note's title and contents as you type (case-insensitively, with no stored
index — files are read on demand), and selecting a result opens that note in
the editor. The vault selection persists across launches, and the app
recovers gracefully when the saved folder access goes stale. Tasks and
notifications arrive in later phases (see [CLAUDE.md](CLAUDE.md) for the
roadmap).

## Supported platforms

- iOS / iPadOS 17 or later
- macOS 14 (Sonoma) or later

Built with SwiftUI and Apple frameworks only — no third-party dependencies.

## Building

Requirements: Xcode 16 or later (the project uses buildable folders).

Open `Cove.xcodeproj` in Xcode, pick the **Cove** scheme, choose a Mac or an
iOS Simulator destination, and run.

From the command line:

```sh
# macOS
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'platform=macOS' build

# iOS Simulator
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'generic/platform=iOS Simulator' build

# Run the tests
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'platform=macOS' test
```

## Creating and selecting a development vault

A vault is just a folder of Markdown files. To make one for local development:

```sh
mkdir -p ~/CoveDevVault/Projects
printf '# Hello\n' > ~/CoveDevVault/Welcome.md
printf '# Plan\n' > ~/CoveDevVault/Projects/Plan.md
```

Then launch Cove and use **Select Vault Folder**:

- **macOS** — a standard open panel appears; choose the folder.
- **iOS Simulator** — the Files document picker appears. The simulator's
  filesystem is separate from your Mac's, so first put some files where the
  simulator can see them, e.g. drag a folder onto the simulator window, or:

  ```sh
  xcrun simctl booted addmedia  # (for media) — for folders, use the Files app share sheet
  ```

  Easiest path: in the booted simulator open **Files › On My iPhone**, create
  a folder, then select it from Cove. Any writable folder offered by the
  picker works.

The selected folder is remembered per device via a security-scoped bookmark.
If the folder is later moved or deleted, Cove shows a recovery screen where
you can reselect a vault.
