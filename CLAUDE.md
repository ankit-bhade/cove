# Cove — Claude Project Guide

Cove is a minimal native Markdown notes app for iOS and macOS built with SwiftUI.
This file is the source of truth for the specification, architecture decisions,
build phases, and current status. Read it fully before making changes.

## Current phase and status

**Current phase: Phase 6 — task parsing and Tasks screen.**

Status: Phase 6 implemented. See CHANGELOG.md for merged work.

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

Before every merge to `main`, additionally sweep `CLAUDE.md`, `README.md`,
and `CHANGELOG.md` end to end for stale statements — not just the sections
touched by the current change. Phase status lines, "comes in Phase N"
forward references, known issues, and the "Current state" paragraph in
`README.md` go stale silently; verify each still matches the code being
merged.

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
* **File operations.** `VaultFileOperations` (stateless, `Sendable`) performs
  every vault mutation and note read/save with per-item `NSFileCoordinator`
  coordination: reads use `coordinate(readingItemAt:)`, saves/creates/deletes
  use `coordinate(writingItemAt:)` with `.forReplacing`/`.forDeleting`, and
  rename/move use the two-item `.forMoving` variant plus
  `item(at:didMoveTo:)`. Name validation rejects empty names, leading dots,
  `/`, and `:`; note names get `.md` appended case-insensitively. Case-only
  renames skip the destination-exists check (APFS is case-insensitive by
  default). `VaultManager` wraps each mutation (`createNote`, `createFolder`,
  `rename`, `move`, `deleteItem`) in `Task.detached` off the main actor and
  rescans the tree afterward.
* **Editor.** `NoteDocument` (`@MainActor @Observable`) owns one open note:
  coordinated load, dirty tracking against the last saved text, debounced
  autosave (1 s after typing stops), and `saveNow()` flushes on view
  disappearance and when the app leaves the foreground. `saveNote` refuses to
  write if the file is gone, so a pending autosave never resurrects a
  renamed/moved/deleted note. `MarkdownTextView` is a plain-text
  `UITextView`/`NSTextView` representable pair (same type name, one per
  platform under `Cove/Platform/`, `#if os(...)`-guarded, distinct file
  basenames — identical basenames in one target collide in the build system).
  Smart quotes/dashes are disabled on both platforms so Markdown syntax
  survives typing.
* **Live Markdown styling.** `MarkdownParser` (pure Foundation, in
  `Cove/Features/Editor/`) scans for ATX headers, `**bold**` spans, and
  `- [ ]` checkboxes, returning UTF-16 `NSRange`s that apply directly to the
  text storage; it is fully unit-tested. `MarkdownStyler` maps a parse to
  attributes — header fonts sized from the body font, dimmed syntax markers,
  bold variants of the in-effect font, strikethrough on checked task text —
  and restyles the whole document after every change. The stored text stays
  plain Markdown; styling is attribute-only, so selection and the undo stack
  are unaffected. Restyling is skipped while IME marked text is active.
  Checkbox toggling: iOS adds a tap recognizer (recognizing simultaneously
  with the text view's own gestures) that hit-tests the tapped character
  index against marker ranges; macOS uses a `CheckboxTogglingTextView`
  subclass (instantiated via `scrollableTextView()`, which honors the
  subclass) whose `mouseDown` routes the flip through
  `shouldChangeText`/`didChangeText` so it is undoable and reaches the
  delegate.
* **Change detection.** `VaultChangeObserver` (`@MainActor`, in
  `Cove/Core/Services/`) wraps one `NSMetadataQuery` with
  `NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope`, which covers
  security-scoped folders reached through the system picker. Update
  notifications are filtered to non-hidden items under the vault (a pure,
  unit-tested static helper) and debounced 600 ms; the initial gathering pass
  is a baseline and never reported. `VaultManager` starts the observer when a
  vault opens, stops it in `endAccess()`, and on each event bumps
  `externalChangeCount` and rescans the tree. `EditorView` observes that
  count (and scene re-activation) to call
  `NoteDocument.reloadAfterExternalChange()`, which adopts the disk contents
  only when there are no unsaved local edits — pending local edits always
  win, and the next autosave writes them out. `RootView` also rescans the
  tree whenever the scene becomes active, as a catch-all for events missed
  while inactive and for non-iCloud vaults.
* **Search.** `NoteSearcher` (`Sendable`, in `Cove/Features/Search/`) runs
  one on-demand pass per query: it flattens the already-scanned tree into its
  files (`VaultNode.allFiles`), reads each with `VaultFileOperations.readNote`
  (coordinated), and matches title and contents case- and
  diacritic-insensitively; the pure matching/flattening helpers are
  unit-tested. `search` is a nonisolated async function, so callers hop off
  the main actor and cancellation stops the file loop between reads.
  `VaultBrowserView` gains a `.searchable` field:
  a non-empty query swaps the tree for `SearchResultsView`, which debounces
  via `.task(id: query)` + 300 ms sleep (a superseding keystroke cancels the
  sleeping task) and navigates through the browser's existing
  `navigationDestination(for: VaultNode.self)` into the editor. Results show
  the trimmed first matching content line as a snippet (nil for title-only
  matches) in tree order. Search does not use the in-memory task index; no
  search index is built or persisted.
* **Tasks and the in-memory index.** `TaskParser` (pure Foundation, in
  `Cove/Features/Tasks/`, fully unit-tested) matches the fixed syntax
  `- [ ] Task text @due(YYYY-MM-DD)` line by line, strictly: no leading
  indentation, exactly one space after `]` and before `@due`, a validated
  Gregorian date, and nothing after the closing parenthesis but trailing
  whitespace. The status char may be ` `/`x`/`X` (matching the editor's
  checkbox parser); when the text itself contains `@due(...)`, the last one
  on the line is the tag. `VaultIndexBuilder` (`Cove/Core/Services/`) walks
  the scanned tree's files with coordinated reads and produces `VaultIndex`
  (`Cove/Core/Models/`): one entry per file with path, title, and
  `TaskItem`s. `VaultManager` rebuilds the index inside every tree load —
  launch, app-created mutations, external changes, and explicit refreshes —
  in the same detached task as the scan. `toggleTask` re-reads the task's
  file, re-finds the task by content (`text` + due date + state, preferring
  the remembered line number among duplicates so duplicate task lines toggle
  correctly), flips the status character, saves coordinated, and rescans;
  if the task can't be re-found it throws `TaskChangedOnDiskError` after
  still refreshing, and `TasksView` shows an alert. Due-date sorting
  compares the zero-padded `YYYY-MM-DD` strings (lexicographic order is
  chronological). `TasksView` sits in a `TabView` beside the browser
  (`RootView`): open tasks sorted by due date with overdue dates in red,
  completed tasks below, checkbox buttons toggle, and rows navigate to the
  editor through a `URL` navigation destination. The tab refreshes the
  vault on each appearance because editor autosaves don't trigger a rescan.
* **Tree scanning.** `VaultTreeScanner` performs one coordinated read
  (`NSFileCoordinator.coordinate(readingItemAt:)`) of the vault root, then
  recursively lists directories with `FileManager`, skipping hidden files
  (dot-prefixed or `isHidden`) and symbolic links, keeping directories and
  case-insensitive `.md` files, sorted folders-first then alphabetically
  (`localizedStandardCompare`). Scans run off the main actor via
  `Task.detached`. Mutations use per-item coordination via
  `VaultFileOperations`.
* **Entitlements.** macOS only (`Cove/Cove.entitlements`, applied via
  `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`): App Sandbox, user-selected
  read-write, app-scope bookmarks. iOS needs no entitlements for
  document-picker folder access. macOS signing stays local/ad-hoc
  (`CODE_SIGN_IDENTITY[sdk=macosx*] = -`); a `DEVELOPMENT_TEAM` is set on the
  app target (added via Xcode) for automatic signing on device builds.
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

* Tree scans still hold one coordinated read for the whole scan (fine for
  reads); all mutations use per-item coordination via `VaultFileOperations`.
* Renaming, moving, or deleting a note while its editor is open on the
  navigation stack leaves the editor pointing at the old URL. Pending edits
  are then dropped rather than saved (`saveNote` throws `fileMissing` instead
  of recreating the file), and the editor shows a save-error banner.
* `UserDefaults`-stored bookmarks are per-device; each device runs the
  folder-selection flow once (expected — there is no custom sync).
* On macOS, `NSOpenPanel` URLs are usable without starting scoped access in the
  same session; `VaultManager` still calls `start`/`stop` and tracks whether
  `start` succeeded so stops stay balanced across both platforms.
* The unit-test bundle runs inside the sandboxed app host on macOS; tests that
  create bookmarks use the app container's temporary directory, which the
  sandbox can bookmark.
* Styling reparses and restyles the whole document on every keystroke. Fine
  for typical notes; very large files would need incremental styling.
* The iOS checkbox toggle edits the text storage directly, so it does not
  land on `UITextView`'s undo stack (the macOS toggle is undoable).
* Clicking anywhere in a `- [ ]` marker toggles it instead of placing the
  insertion point; edit the marker text by moving the caret in from outside.
* Header fonts are computed from the current body font at restyle time, so
  an iOS Dynamic Type change updates header sizes on the next edit, not
  instantly.
* `NSMetadataQuery` only reports iCloud-backed items, so external edits to a
  non-iCloud vault are picked up only by the scene-activation rescan, not
  live.
* An external change to a note with unsaved local edits is not adopted: the
  local text wins and the next autosave overwrites the external version.
  When both sides really changed, iCloud creates a conflict copy, which
  appears as a separate file (per spec, never auto-resolved).
* Every external change event makes each open editor re-read its own file
  (one coordinated read), even when the changed items don't include it —
  metadata URLs aren't reliably comparable to picker URLs, so the reload is
  unconditional and cheap.
* External change detection is untestable in unit tests (no iCloud in the
  test host); only the URL-filtering helper and the editor reload logic are
  covered. Verify live behavior manually with a vault in iCloud Drive.
* Every debounced query re-reads every Markdown file from disk (per spec:
  no persisted index). Fine for typical vaults; very large vaults would feel
  it. Search results don't live-update if files change while the query is
  showing — edit the query (or reopen search) to re-run it.
* Search matches are line-based: the snippet is the first matching line, and
  a query spanning a line break won't match.
* Every index rebuild reads every Markdown file (launch, each mutation, each
  external change event, each Tasks-tab appearance). Fine for typical
  vaults; very large vaults would want incremental indexing.
* The Tasks tab can lag reality between rebuilds: a task typed in the editor
  appears only after the tab is revisited (its appearance triggers a
  refresh) or another rescan fires. Toggling a task that meanwhile changed
  on disk shows a "changed on disk" alert and refreshes the list instead of
  writing.
* The task syntax is enforced strictly (per spec): an indented task line, a
  double space after the marker, or an invalid calendar date silently keeps
  the line out of the Tasks screen even though the editor still styles its
  checkbox.
* Phase 7+ features (notifications) are intentionally absent.
