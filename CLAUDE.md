# Cove — Claude Project Guide

Cove is a minimal native Markdown notes app for iOS and macOS built with SwiftUI.
This file is the source of truth for the specification, architecture decisions,
build phases, and current status. Read it fully before making changes.

## Current phase and status

**Current phase: Phase 9 — appearance polish, app icon, and launch screen.**

Status: Phase 9 implemented and visually refined. All build phases are
complete. See CHANGELOG.md for merged work.

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
- [ ] Task text @due(YYYY-MM-DD HH:MM)
- [ ] Task text @due(YYYY-MM-DD HH:MM) @repeat(<rule>)
```

Rules:

* This syntax family is fixed; the time and `@repeat` tag are optional,
  and `@repeat` rules are `daily`/`weekly`/`monthly`/`yearly`,
  `every N <days|weeks|months|years>`, `every weekday`, or
  `every <weekday names>` (the `@repeat` tag follows the `@due` tag)
* Sort incomplete tasks by due date, then time (date-only tasks first
  within a day)
* Checking a task updates its original Markdown file; checking an
  incomplete recurring task advances its due date to the rule's next
  occurrence instead of marking it complete
* Do not support alternate task syntax

The Tasks screen has a quick-entry field whose interpreter is a port of
the grove-app capture parser: tokens are recognized anywhere in the
sentence and the title is what remains. It understands relative dates
(`tdy`/`today`, `tmr`/`tmrw`/`tom`/`tomorrow`, `day after tomorrow`,
`tonight` — 8 PM default, `next week`, weekday names and abbreviations,
`next <weekday>`, `in 3 days`/`in 2w`/`in 1 month`), explicit dates
(`sep 12`, `feb 3rd`, `2/3`, `4/15/27`), times (`3p`, `6pm`, `3:30pm`,
`940p`, `noon`, `midnight`, 24-hour `15:00`, bare `5:30` reading small
hours as afternoon, ranges like `7-9pm` keeping the start), and
recurrences (`daily`/`weekly`/`monthly`/`yearly`/`annually`,
`every day`/`week`/`month`/`year`, `every N <units>`, `every weekday`,
`every mon wed fri` with comma/`and` lists). A bare time means today,
even when that moment has passed. Before saving, the interpreted title,
date, time, recurrence, and notification are shown for confirmation and
editing. Confirmed tasks are appended to `Tasks.md` at the vault root,
created on demand.

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

* Schedule notifications only for incomplete tasks that have both a due
  date and a due time; a task with a bare date gets no notification
* Every notification is a one-shot at the task's due moment; recurring
  tasks are never scheduled ahead — completing an occurrence rolls the
  line to the next date, and the rebuild schedules that occurrence
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
8. Natural-language quick task entry with times and recurrence
9. Appearance polish, app icon, and launch screen

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
  renamed/moved/deleted note. `saveStatus` derives
  `saved`/`pending`/`saving`/`failed` from the live text versus what reached
  disk, so the editor's toolbar indicator cannot disagree with reality; it
  renders only while `pending`/`saving` (a permanent "Saved" chip is chrome
  that also reads as a button it isn't, and the failure case already has the
  banner), and forces `.labelStyle(.titleAndIcon)` because the toolbar
  otherwise collapses the label to its icon and drops the meaning. On iOS a
  `.keyboard`-placement Done button dismisses the keyboard, which a
  `UITextView` has no return key to do. `MarkdownTextView` is a plain-text
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
  matches) in tree order. A spinner covers the debounce and the full-vault
  read, since a blank list otherwise reads as "no matches" rather than
  "working"; a cancelled run leaves the flag to the newer query that
  superseded it. Search does not use the in-memory task index; no
  search index is built or persisted.
* **Tasks and the in-memory index.** `TaskParser` (pure Foundation, in
  `Cove/Features/Tasks/`, fully unit-tested) matches the fixed syntax
  `- [ ] Task text @due(YYYY-MM-DD[ HH:MM])[ @repeat(rule)]` line by line,
  strictly: no leading indentation, exactly one space after `]` and before
  `@due`, a validated Gregorian date, a validated zero-padded 24-hour time
  when present, a recognized `@repeat` tag when present (parsed by
  `RecurrenceRule` in `Cove/Core/Models/` — grove-app's recurrence model:
  a frequency `daily`/`weekly`/`monthly`/`yearly`, an interval, and an
  optional weekday set for weekly rules, with normalized tags like
  `daily`, `every 2 weeks`, `every weekday`, `every monday wednesday`),
  and nothing after the last closing parenthesis but trailing whitespace. The status char may be ` `/`x`/`X` (matching the
  editor's checkbox parser); when the text itself contains `@due(...)`, the
  last one on the line is the tag, and an `@repeat(...)` before the `@due`
  tag is just text. `VaultIndexBuilder` (`Cove/Core/Services/`) walks
  the scanned tree's files with coordinated reads and produces `VaultIndex`
  (`Cove/Core/Models/`): one entry per file with path, title, and
  `TaskItem`s (now carrying optional `dueTimeString` and `recurrence`).
  `VaultManager` rebuilds the index inside every tree load —
  launch, app-created mutations, external changes, and explicit refreshes —
  in the same detached task as the scan. `toggleTask` re-reads the task's
  file, re-finds the task by content (`text` + full schedule + state,
  preferring the remembered line number among duplicates so duplicate task
  lines toggle correctly), rewrites the line, saves coordinated, and
  rescans; completing an incomplete recurring task advances its due date
  in place to the rule's next occurrence after the later of the stale due
  date and today (the checkbox stays open — the line is the task's single
  home), while every other toggle flips the status character. If the task
  can't be re-found it throws `TaskChangedOnDiskError` after still
  refreshing, and `TasksView` shows an alert. `deleteTask` follows the same
  re-find-then-rewrite path (`TaskParser.removingTask`, sharing the private
  `matchingTask` matcher with `togglingTask`) but drops the whole
  `lineRange`, so a line that changed on disk raises
  `TaskChangedOnDiskError` instead of deleting the wrong task; it is
  reachable from a row's trailing swipe action and its context menu, and is
  deliberately unconfirmed (the gesture is already deliberate; the bulk
  Clear All is the action that warrants a dialog). `clearCompletedTasks` groups
  the indexed completed tasks by source note, re-reads each note, removes
  every currently completed strict task line while preserving all other
  Markdown and line endings, saves through `VaultFileOperations`, and
  refreshes the tree/index afterward. Sorting compares
  `(dueDateString, dueTimeString ?? "", fileTitle, lineNumber)` — the
  zero-padded strings order chronologically, with date-only tasks first
  within a day. `TasksView` sits in a `TabView` beside the browser
  (`RootView`): open tasks sorted by due date, completed tasks below,
  checkbox buttons
  toggle, recurrence shown as a `repeat`-icon label, and rows navigate to
  the editor through a `URL` navigation destination. A row shows only its
  text and schedule: the source note's title is deliberately omitted, since
  tasks nearly all live in the capture note and the caption repeated
  "Tasks" under every row. Display logic lives in
  `TaskPresentation.swift` (pure, unit-tested against a fixed `now`):
  `TaskGroup.grouping` partitions the already-sorted open tasks into
  Overdue/Today/Tomorrow/Upcoming — partitioning only, so the spec's
  ordering is untouched and empty sections vanish — and
  `relativeDueDescription` writes dates as "Today, 3:00 PM", "Tomorrow",
  a weekday name inside the coming week, then "Jul 24", adding the year
  only when it differs from the current one. `TasksView` holds a `now`
  that a `.task` loop ticks each minute, so overdue and Today stay true
  while the tab sits open across a due moment or midnight. The completed-section
  header includes a destructive Clear All button with a confirmation dialog.
  The tab refreshes the
  vault on each appearance because editor autosaves don't trigger a rescan.
* **Quick task entry.** `QuickTaskParser` (pure, in
  `Cove/Features/Tasks/`, fully unit-tested against a fixed `now`) is a
  Swift port of the grove-app capture parser
  (`grove-app/src/lib/parser/parse.ts`), matching its grammar and
  resolution rules; its test suite ports grove's `parse.test.ts`. It
  interprets one sentence into a `TaskDraft` (title + resolved
  `YYYY-MM-DD` + optional `HH:MM` + optional `RecurrenceRule`, plus the
  `markdownLine` it saves as). Each extractor regex claims the character
  span it consumed (overlaps lose); the title is the input minus claimed
  spans, with dangling connectors ("at"/"on"/"due"/"by"/"from") tidied
  and the first letter capitalized. Grove semantics: tokens match
  anywhere in the sentence, plain weekdays include today, `next
  <weekday>` is strictly future, a bare time means today even if the
  moment has passed, `tonight` defaults to 20:00, and a weekday-set
  recurrence starts on the soonest listed day. Bare numbers are never
  times (`buy 6 eggs` keeps its 6; `hw4` is not 4:00). Documented
  divergences, forced by Cove's fixed rules: no hashtag lists (tags stay
  in the title), undated input resolves to today (`@due` is mandatory),
  and a time range (`7-9pm`) keeps only its start time (no calendar
  events). `TasksView` hosts the entry field; submitting opens `TaskDraftSheet`,
  which shows the interpretation for confirmation — editing the sentence
  re-interprets everything, editing the field controls (title, date, time
  toggle + picker, recurrence picker — presets plus the parsed rule when
  it isn't one) tweaks the draft directly, and a
  footer row states whether a notification will fire. Confirming calls
  `VaultManager.captureTask`, which appends `draft.markdownLine` to
  `Tasks.md` at the vault root via `VaultFileOperations.appendLine` (a
  single coordinated read-modify-write that creates the note on first
  use), then rescans.
* **Task notifications.** Split into a pure, unit-tested planner and a thin
  scheduler (both in `Cove/Core/Services/`). `TaskNotificationPlanner` turns
  the task list into `TaskNotificationPlan`s for incomplete tasks *with a
  due time* only (date-only tasks get none): every plan is a one-shot at
  the task's due moment, skipped once it has passed. Recurring tasks are
  not scheduled ahead — mirroring grove-app, completing an occurrence
  rolls the line to the next date and the rebuild that follows schedules
  that occurrence's notification. Plans are ordered soonest-due first and
  capped at 60 (the system holds at most 64 pending local notifications
  per app). Notification titles are the task text; bodies use a compact
  English month, day, and 12-hour time (for example, `Jul 18, 8:00pm.`),
  without exposing the year, Markdown filename, or recurrence metadata.
  Identifiers carry the `cove-task:` prefix.
  `TaskNotificationScheduler` (an actor) wraps `UNUserNotificationCenter`:
  each rebuild removes every pending request with that prefix, then — only
  when there is something to schedule — ensures authorization (prompting on
  first use; a denial silently skips scheduling) and adds one one-shot
  `UNCalendarNotificationTrigger` request per plan. Rebuilds are chained through a stored `Task` so overlapping calls
  never interleave their remove/add steps. `VaultManager` enqueues a
  rebuild at the end of every successful tree load, which covers launch,
  app-created mutations, external changes, and the scene-activation
  refresh (the spec's "foreground or files change"). No push
  notifications and no background scheduling.
* **Settings and appearance.** `SettingsView` (`Cove/Features/Settings/`)
  is a third tab beside Notes and Tasks, shown when a vault is open: the
  current vault's name and path with the shared `VaultPickerButton`
  reselect flow (the same recovery path as the welcome/stale screens), a
  greeting-name field, a
  system/light/dark segmented picker, and notification permission status
  (refreshed on appearance and scene re-activation) with an
  Enable-Notifications request or an Open-System-Settings shortcut. There
  is no About section: the app's identity and version are visible from the
  system, and a personal-use app doesn't need the row.
  `AppearanceSetting` (a `String` enum persisted under
  the `@AppStorage` key `appearanceSetting`, unit-tested) maps to an
  optional `ColorScheme`; `RootView` applies `preferredColorScheme`
  around every vault state, so the preference also covers the welcome and
  recovery screens, and an unrecognized stored value falls back to
  `system`.
* **Icon, accent, and launch screen.** The asset catalog carries generated
  `cove` wordmark artwork — the word set in Cormorant Garamond semibold over
  layered waves, with the `o` replaced by a sun (light) or a cratered full
  moon (dark). The vector source is the `Cove Icon Final.dc.html` design
  document; the PNGs are rendered from that SVG and derived into every size
  by the pipeline described under "Regenerating the app icon" below. The set
  is a full-bleed 1024 iOS icon plus a dark-appearance 1024 variant,
  icon-grid rounded-rect PNGs for every mac size, and a `LaunchIcon`
  imageset (light and dark rounded tiles, also reused in-app by the loading,
  setup, and Settings headers) plus a `LaunchBackground` colorset
  (white/black) used by the iOS `UILaunchScreen` dictionary. That
  dictionary lives in a root-level partial `Info.plist` merged into the
  generated one via `INFOPLIST_FILE` alongside `GENERATE_INFOPLIST_FILE`
  (kept outside the synchronized `Cove/` folder so it isn't swept up as a
  resource). `AccentColor` is a cove teal with a lighter dark-mode
  variant.
* **Visual system.** `CoveTheme` (`Cove/App/`) centralizes the icon-derived
  navy/teal/sea-glass palette, adaptive light/dark canvas and surface colors,
  brand gradient, card treatment, grouped-row card insets, and compact icon
  tiles. `.coveListStyle()` / `.coveFormStyle()` carry the platform-grouped
  style plus the canvas background, so every scrolling screen shares one
  definition instead of repeating the `#if os(iOS)` block. `CoveIconTile` is
  decorative: it is `accessibilityHidden` (the surrounding row carries the
  label) and sized with `@ScaledMetric` so it tracks Dynamic Type. Setup,
  loading,
  Notes, search, Tasks, task confirmation, move, editor, and Settings screens
  share those primitives. The richer presentation remains standard SwiftUI
  and platform text views only; it adds no assets beyond the existing
  `LaunchIcon`, no dependencies, and no persistence changes.
* **Level-aware Notes browser.** `VaultBrowserView` presents one folder level
  at a time rather than an inline recursive outline. `folderPath` is bound
  directly to `NavigationStack(path:)`, so a folder row is a real push
  (`navigationDestination(for: URL.self)` re-entering `browserLevel`) and the
  system back button, its parent-folder title, and the iOS swipe-back gesture
  all work — the earlier in-place swap had none of those and needed a custom
  back button. File
  rows push the editor, and global search still resolves through the shared
  `VaultNode` navigation destination. Every level has the same
  create/refresh tools and a compact card with a time-of-day greeting set in
  a restrained title-3 semibold style. `Greeting`
  (`Cove/Features/VaultBrowser/Greeting.swift`, pure and unit-tested) owns
  the text: seven stretches of the day (late night, early morning, morning,
  midday, afternoon, evening, night), each with several phrases in a named
  (`%@`) and a plain form, so an unset name never leaves a dangling comma.
  The pick is seeded by the day ordinal plus the stretch index, so the
  browser's once-a-minute `TimelineView` tick can't reshuffle the phrase
  mid-read while a new day or stretch still changes it. The name is an
  `@AppStorage` string under `greetingName`, set in Settings and
  whitespace-trimmed. Its counts are scoped
  to that folder: direct child folders,
  deeper descendant folders, and all Markdown notes in the subtree. The card
  intentionally omits the app icon and the old “Your Markdown workspace”
  treatment.
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
* Task syntax `- [ ] Task text @due(YYYY-MM-DD[ HH:MM])[ @repeat(rule)]`
  is fixed; no alternates.
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

## Regenerating the app icon

The icon's source of truth is the `Cove Icon Final.dc.html` design document
(two `<symbol>` elements, `coveLight` and `coveDark`, each a 1024×1024 SVG).
The checked-in PNGs are produced from it in two steps, neither of which is
part of the app or its build:

1. Render each symbol standalone at 1024×1024 with headless Chrome. The
   wordmark needs Cormorant Garamond, which is not installed on macOS — the
   page must pull it from Google Fonts, and the render needs network access
   and a `--virtual-time-budget` long enough for the webfont to land.
   Confirm the result is Cormorant and not the Georgia fallback.
2. Derive every catalog size from those two base renders with CoreGraphics:
   full-bleed for the iOS icons, an 824/1024 rounded-rect body with a soft
   drop shadow for the macOS icon grid, and full-bleed rounded tiles for
   `LaunchIcon`.

Verify with a macOS and an iOS build afterwards — `actool` reports icon
problems as build warnings, not errors.

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
  writing (deleting one behaves the same way).
* Deleting a task is immediate and unconfirmed, and there is no undo — the
  line is gone from the note as soon as the swipe completes. Deliberate
  (a swipe is already an intentional gesture), but worth knowing.
* A task row no longer names its source note, so tasks kept in notes other
  than `Tasks.md` are indistinguishable in the list until opened. Fine for
  the intended single-capture-note workflow; a vault that scatters tasks
  across many notes would want the caption back.
* The task syntax is enforced strictly (per spec): an indented task line, a
  double space after the marker, an invalid calendar date or time, or an
  unknown `@repeat` rule silently keeps the line out of the Tasks screen
  even though the editor still styles its checkbox.
* Only tasks with a due time get notifications (per design); a date-only
  task never notifies, and a timed non-recurring task whose moment has
  passed gets none.
* At most 60 notification requests are scheduled (soonest due dates win)
  to stay under the system's 64-pending cap.
* Recurring tasks are never scheduled ahead (grove-app semantics): only
  the current occurrence has a pending notification, and the next one is
  scheduled only after this device rebuilds following the completion that
  rolled the line forward. Ignore a recurring task's notification without
  completing it and no further reminders arrive; the overdue occurrence
  itself also gets nothing once its moment passes.
* Advancing an overdue recurring task on completion anchors on the later
  of the due date and today — a deliberate divergence from grove, which
  anchors strictly on the completed occurrence's date; Cove's single-line
  model has no occurrence history to catch up through.
* Recurrence-aware completion lives only in the Tasks tab. Tapping the
  same line's checkbox in the editor flips it to `[x]` like any checkbox;
  the Tasks tab then shows it as completed rather than rolled forward
  (toggling there flips it back).
* The quick-entry interpreter is English-only. Grove parity means tokens
  are consumed anywhere in the sentence: "plan friday party tmr" is due
  tomorrow and titled "Plan party" — the losing date word still leaves
  the title. Hashtags are not lists (Cove has no tag feature) and stay in
  the title; ISO dates ("2026-07-21") aren't in grove's grammar — use
  slash or month-name dates, or the sheet's date picker.
* A bare time stays on today even when that moment has passed (grove
  parity): "standup 9a" typed at 10:00 lands today, already overdue, and
  gets no notification. Add a date word if tomorrow was meant.
* Time ranges ("dinner 7-9pm") keep only the start time; Cove has no
  calendar events, so the end time is dropped.
* Quick-added tasks always land in `Tasks.md` at the vault root; the
  capture note isn't configurable. If iCloud syncs in a folder named
  `Tasks.md`, capture fails with an error alert.
* The notification permission prompt appears the first time a rebuild has a
  task to schedule, not at launch. A denial silently disables scheduling;
  the Settings tab then shows the status as Off with an Open System
  Settings shortcut (permission can only be re-granted there).
* A notification is a reminder, not a live view: tapping it opens the app
  but not the specific task, and a task completed on another device keeps
  its scheduled notification here until this device next rebuilds (launch,
  foreground, or a detected iCloud change).
* `TaskNotificationScheduler` is untestable in unit tests (scheduling would
  prompt for permission in the test host); only the planner is unit-tested.
  Verify delivery manually.
* The Settings tab's notification status is polled on appearance and scene
  re-activation, not live; granting permission in the system settings shows
  up when the app returns to the foreground.
* The editor's save indicator is present only while edits are unwritten, so
  it appears on the first keystroke and disappears about a second after
  typing stops. That is intentional (a permanent "Saved" chip is noise), but
  it does mean the toolbar's trailing item comes and goes while typing.
* The Tasks tab's minute tick re-evaluates the list body, which re-groups and
  re-formats every row. Cheap at typical task counts; a very large task list
  would want the tick narrowed to the rows that can actually change.
* `TaskItem.dueDate` resolves through `Calendar.current`, so
  `TaskPresentation`'s day arithmetic is local-calendar bound.
  `TaskPresentationTests` therefore builds its fixed `now` values with
  `Calendar.current` rather than the UTC calendar the notification-planner
  tests use.
* On iOS 26 a pushed folder level collapses the `.searchable` field into the
  toolbar rather than showing it under the title as the root level does.
  That is the system's own behavior for pushed levels, not a Cove layout bug.
* The launch screen is iOS-only (`UILaunchScreen` has no macOS equivalent);
  macOS windows simply open with the app's content.
* The app icon PNGs are generated artwork checked into the asset catalog.
  The vector source lives in the Claude Design project, not in the repo, so
  an icon change means editing there and regenerating the full size set (see
  "Regenerating the app icon").
* The icon is a wordmark, so the 16pt and 32pt macOS sizes reduce `cove` to
  an illegible smudge. That is inherent to the design; the waves and the
  sun/moon still read as the app's silhouette in the Dock and Finder.
* The dark iOS app icon variant is opaque rather than transparent. Apple's
  iOS 18 guidance prefers a transparent dark icon composited over a
  system-drawn backdrop; the design supplies its own night sky, so it ships
  as-is. iOS 17 ignores the variant entirely.
