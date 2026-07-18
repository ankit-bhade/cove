# Cove — Claude Project Guide

Cove is a minimal native Markdown notes app for iOS and macOS built with SwiftUI.
This file is the source of truth for the specification, architecture decisions,
build phases, and current status. Read it fully before making changes.

## Current phase and status

**Current phase: Phase 1 — Folder picker, bookmark persistence, stale-bookmark recovery, read-only tree browser.**

Status: Phase 1 implemented. See CHANGELOG.md for merged work.

Do not work ahead into a later phase unless explicitly asked.

---

## Full specification

### Core rules

* SwiftUI multiplatform app
* Minimum targets: iOS 17 and macOS 14
* No backend, accounts, database, plugins, or custom sync
* No third-party dependencies
* Use only SwiftUI, Foundation, UIKit, AppKit, and Apple frameworks
* The filesystem is the source of truth
* Do not hardcode a vault folder name or location

### Vault

The user selects a folder using:

* `NSOpenPanel` on macOS
* `UIDocumentPickerViewController` on iOS

Persist access using a security-scoped bookmark stored in `UserDefaults`.

All vault access must:

* Start and stop security-scoped access correctly
* Use `NSFileCoordinator` for reads, writes, renames, moves, and deletes
* Ignore hidden files and symbolic links
* Support UTF-8 Markdown files with a case-insensitive `.md` extension
* Show folders first, then files, alphabetically

The app is intended for folders in iCloud Drive, but any writable folder
returned by the system picker may be used.

Use `NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope` to detect
iCloud changes. Treat change events as signals to refresh the affected files
and rebuild the in-memory index.

### Screens

#### Vault Browser

Display the vault folder tree.

Support:

* Create note
* Create folder
* Rename
* Move
* Delete

#### Editor

Create a single-pane live-styled Markdown editor.

Use:

* `UITextView` with `UIViewRepresentable` on iOS
* `NSTextView` with `NSViewRepresentable` on macOS

Shared code should handle Markdown parsing, styling ranges, checkbox
detection, autosaving, and document state.

Support:

* Bold text
* Headers
* Tappable checkboxes
* Automatic saving to disk

Do not build a split-pane preview.

#### Search

* Search all Markdown files on demand
* Do not create a persisted search index
* Debounce searches while typing
* Open the selected matching file

#### Tasks

Collect task lines matching exactly:

```text
- [ ] Task text @due(YYYY-MM-DD)
```

Rules:

* This syntax is fixed
* Sort incomplete tasks by due date
* Checking a task updates its original Markdown file
* Do not support alternate task syntax

#### Settings

Include:

* Select or reselect vault
* Recover from stale bookmarks
* System, light, and dark appearance
* Notification permission

### In-memory index

Build an in-memory index containing:

* File path
* File title
* Due tasks

Rebuild it:

* On launch
* After detected file changes
* After app-created file changes

Do not add tags unless a tag feature is added later.

### Notifications

Use `UNUserNotificationCenter`.

* Schedule notifications only for incomplete tasks with due dates
* Rebuild task notifications when the app enters the foreground or files change
* Remove previously generated task notifications before rebuilding
* Do not use push notifications
* Do not implement custom background sync

### Conflict behavior

Do not automatically resolve iCloud conflicts.
If iCloud creates a conflict copy, display it as a separate file.

### Build order

Complete and validate each phase before starting the next.

1. Folder picker, bookmark persistence, stale-bookmark recovery, read-only tree browser
2. Editor, saving, file and folder creation, rename, move, and delete
3. Live Markdown styling
4. iCloud change detection and external-edit refreshing
5. Full-text search
6. Task parsing and Tasks screen
7. Local task notifications
8. Appearance polish, app icon, and launch screen

Do not work ahead into a later phase unless explicitly asked.

### Project structure

```text
App/
Core/
  Models/
  Services/
Features/
  VaultBrowser/
  Editor/
  Search/
  Tasks/
  Settings/
Platform/
  iOS/
  macOS/
Tests/
```

Only create files that are needed for the current phase.

### Documentation rule

Before considering any task or PR complete:

* Update `CHANGELOG.md`
* Update `README.md` when user-facing behavior changes
* Update `CLAUDE.md` when architecture, decisions, known issues, or the current phase changes

---

## Architecture decisions

* **Hand-written Xcode project.** `Cove.xcodeproj` is written by hand using
  `objectVersion 77` with `PBXFileSystemSynchronizedRootGroup` (Xcode 16+
  buildable folders). Files added on disk under `Cove/` or `Tests/` are picked
  up automatically — no pbxproj edits needed when adding source files. No
  third-party project generators are used.
* **Source layout.** The spec's structure lives under `Cove/` (the app's
  synchronized folder): `Cove/App`, `Cove/Core/Models`, `Cove/Core/Services`,
  `Cove/Features/...`, `Cove/Platform/iOS`, `Cove/Platform/macOS`. Tests live
  in top-level `Tests/` (the `CoveTests` target's synchronized folder).
* **Single multiplatform target.** One `Cove` app target supports
  `iphoneos iphonesimulator macosx` (`SDKROOT = auto`). Platform differences
  are handled with `#if os(...)` in `Cove/Platform/`.
* **Swift language mode 5** with `@Observable` (Observation framework,
  iOS 17/macOS 14) for app state.
* **State model.** `VaultManager` (`@MainActor @Observable`) owns the vault
  lifecycle: `restoring → needsVault | recoveryNeeded | open`. It is created in
  `CoveApp` and injected via `.environment`.
* **Bookmarks.** `VaultBookmarkStore` persists a security-scoped bookmark in
  `UserDefaults`. macOS uses `.withSecurityScope` creation/resolution options;
  iOS uses empty options (iOS document-picker bookmarks are implicitly
  security-scoped). If resolution reports stale, the store re-creates the
  bookmark best-effort inside a temporary security scope. Resolution failure or
  an unreadable folder surfaces the reselect-vault recovery flow.
* **Security-scope balance.** `VaultManager` starts scoped access when a vault
  is opened/restored and records the URL only when `start` returned `true`;
  it stops access when the vault is replaced, when opening fails, and in
  `deinit`. `VaultBookmarkStore.refreshBookmark` uses a start/defer-stop pair.
* **Tree scanning.** `VaultTreeScanner` performs one coordinated read
  (`NSFileCoordinator.coordinate(readingItemAt:)`) of the vault root, then
  recursively lists directories with `FileManager`, skipping hidden files
  (dot-prefixed or `isHidden`) and symbolic links, keeping directories and
  case-insensitive `.md` files, sorted folders-first then alphabetically
  (`localizedStandardCompare`). Scans run off the main actor via
  `Task.detached`. Per-file coordination for writes comes in Phase 2.
* **Entitlements.** macOS only (`Cove/Cove.entitlements`, applied via
  `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`): App Sandbox, user-selected
  read-write, app-scope bookmarks. iOS needs no entitlements for
  document-picker folder access. Signing is local/ad-hoc (`-`) so the project
  builds without a team.
* **Bundle identifiers.** `com.ankitbhade.Cove` / `com.ankitbhade.CoveTests`.

## Fixed rules

* Filesystem is the source of truth; no database, no backend, no accounts.
* No third-party dependencies (app or build tooling).
* Never hardcode a vault folder name or location.
* All vault filesystem access goes through `NSFileCoordinator`.
* Hidden files and symlinks are always ignored.
* Task syntax `- [ ] Task text @due(YYYY-MM-DD)` is fixed; no alternates.
* No persisted search index; search is on demand.
* No push notifications; no custom background sync.
* iCloud conflict copies are shown as separate files, never auto-resolved.

## PR naming rules

Format: `[Phase N] type: short description`

Allowed types: `feat`, `fix`, `refactor`, `docs`, `chore`.
Use Phase 0 for scaffolding and documentation-only work.
Branch names mirror the PR title in kebab-case, e.g. `phase-1-folder-picker`.
Changelog text closely matches the PR title without the phase tag and type
prefix.

## Building and testing

```sh
# macOS build
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'platform=macOS' build

# iOS Simulator build
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'generic/platform=iOS Simulator' build

# Tests (macOS host)
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'platform=macOS' test
```

## Known issues and gotchas

* The read-only browser holds one coordinated read for the whole scan; Phase 2
  must move to per-item coordination for mutations.
* `UserDefaults`-stored bookmarks are per-device; each device runs the
  folder-selection flow once (expected — there is no custom sync).
* On macOS, `NSOpenPanel` URLs are usable without starting scoped access in the
  same session; `VaultManager` still calls `start`/`stop` and tracks whether
  `start` succeeded so stops stay balanced across both platforms.
* The unit-test bundle runs inside the sandboxed app host on macOS; tests that
  create bookmarks use the app container's temporary directory, which the
  sandbox can bookmark.
* Phase 2+ features (editing, creating, renaming, moving, deleting, search,
  tasks, notifications, iCloud change detection) are intentionally absent.
