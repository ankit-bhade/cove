# Cove — Claude Project Guide

Cove is a minimal native Markdown notes app for iOS and macOS built with
SwiftUI. This file holds the specification, the decisions behind the code, and
the constraints that aren't visible from reading it.

It deliberately does **not** describe what the code does — the code says that,
and says it accurately. What lives here is the part source can't carry: why a
decision went one way, what the alternative cost, and which traps have already
been paid for.

---

## Status

All eleven build phases are complete; work since then is reliability
hardening and, most recently, a new visual direction — ink on warm paper,
marked in ember, replacing the coastal palette the app shipped with. See
`CHANGELOG.md` for what has shipped and "The visual system" below for what the
direction commits to.

The phases were: folder picker and bookmarks (1), editor and file operations
(2), live Markdown styling (3), iCloud change detection (4), search (5), tasks
(6), notifications (7), quick capture (8), appearance and icon (9), task lists
(10), Today widget (11).

---

## Fixed rules

These are non-negotiable. A change that breaks one is wrong even if it works.

* The filesystem is the source of truth; no database, no backend, no accounts,
  no plugins, no custom sync.
* No third-party dependencies (app or build tooling).
* Never hardcode a vault folder name or location.
* All vault filesystem access goes through `NSFileCoordinator`.
* Hidden files and symlinks are always ignored.
* Task syntax `- [ ] Task text @due(YYYY-MM-DD[ HH:MM])[ @repeat(rule)]` is
  fixed; no alternates. The one relaxation is `@due`-less lines inside a `##`
  list section of the capture note, and it applies nowhere else.
* No persisted search index; search is on demand.
* No push notifications; no custom background sync.
* iCloud conflict copies are shown as separate files, never auto-resolved.
* Only SwiftUI, Foundation, UIKit, AppKit, and Apple frameworks.
* Minimum targets: iOS 17 and macOS 14.

---

## Specification

### Vault

The user selects a folder with `NSOpenPanel` (macOS) or
`UIDocumentPickerViewController` (iOS). Access persists as a security-scoped
bookmark in `UserDefaults`.

All vault access must start and stop security-scoped access correctly,
coordinate through `NSFileCoordinator`, ignore hidden files and symlinks,
support UTF-8 Markdown with a case-insensitive `.md` extension, and show
folders first, then files, alphabetically.

The app is intended for folders in iCloud Drive, but any writable folder from
the system picker may be used. `NSMetadataQueryAccessibleUbiquitousExternal‐
DocumentsScope` detects iCloud changes; change events are signals to refresh
the affected files and rebuild the index.

### Screens

**Vault Browser** — the folder tree, with create note, create folder, rename,
move, and delete.

**Editor** — a single-pane live-styled Markdown editor: `UITextView` on iOS,
`NSTextView` on macOS, both through representables. Supports bold, headers,
tappable checkboxes, and automatic saving. Shared code handles parsing,
styling ranges, checkbox detection, autosaving, and document state. **No
split-pane preview.**

**Search** — searches all Markdown files on demand, debounced while typing,
opening the selected file. No persisted index.

**Tasks** — collects lines matching exactly:

```text
- [ ] Task text @due(YYYY-MM-DD)
- [ ] Task text @due(YYYY-MM-DD HH:MM)
- [ ] Task text @due(YYYY-MM-DD HH:MM) @repeat(<rule>)
```

The time and `@repeat` tag are optional; `@due` is optional *only* inside a
list section of the capture note. `@repeat` rules are
`daily`/`weekly`/`monthly`/`yearly`, `every N <days|weeks|months|years>`,
`every weekday`, or `every <weekday names>`, and the tag follows `@due`.

Incomplete tasks sort by due date, then time (date-only first within a day).
Checking a task updates its original file; checking an incomplete recurring
task advances its due date to the next occurrence instead of completing it.

The screen has a quick-entry field whose interpreter is a port of the
grove-app capture parser: tokens are recognized anywhere in the sentence and
the title is what remains. It understands relative dates (`tdy`/`today`,
`tmr`/`tmrw`/`tom`/`tomorrow`, `day after tomorrow`, `tonight` — 8 PM default,
`next week`, weekday names and abbreviations, `next <weekday>`, `in 3 days`/
`in 2w`/`in 1 month`), explicit dates (`sep 12`, `feb 3rd`, `2/3`, `4/15/27`),
times (`3p`, `6pm`, `3:30pm`, `940p`, `noon`, `midnight`, 24-hour `15:00`,
bare `5:30` reading small hours as afternoon, ranges like `7-9pm` keeping the
start), and recurrences (`daily`/`weekly`/`monthly`/`yearly`/`annually`,
`every day`/`week`/`month`/`year`, `every N <units>`, `every weekday`,
`every mon wed fri` with comma/`and` lists). A bare time means today, even
when that moment has passed.

The interpretation shows live under the field as the sentence is typed, and
return adds the task straight away; a details sheet is one tap away for
adjusting it instead of rewording. Added tasks go into `Tasks.md` at the vault
root, created on demand.

**Lists** — groups related tasks (groceries, subscriptions, packing) and keeps
them visually separate from the Tasks screen.

* A list is a `##` heading inside the capture note; its items are the task
  lines beneath it, up to the next heading
* A `#` heading closes the open list; headings mean nothing in any other note,
  where `@due` remains mandatory
* List items use the same interpreter and may carry a due date, time, and
  `@repeat` rule — but `@due` is optional, and an undated item gets no
  notification
* Dated items sort before undated ones; undated items keep insertion order
* List items never appear on the Tasks screen, and its Clear All never removes
  them
* Lists can be created, renamed, and deleted; deleting one removes its heading
  and every task under it

**Settings** — select or reselect vault, recover from stale bookmarks,
system/light/dark appearance, notification permission.

### In-memory index

One entry per note: file path, file title, due tasks. Rebuilt on launch, after
detected file changes, and after app-created changes. Do not add tags unless a
tag feature is added later.

### Notifications

Through `UNUserNotificationCenter`:

* Only for incomplete tasks with **both** a due date and a due time
* Every notification is a one-shot at the due moment; recurring tasks are
  never scheduled ahead — completing an occurrence rolls the line forward and
  the rebuild schedules the next one
* Reconcile when the app foregrounds or files change
* Diff only Cove-owned requests; don't remove and recreate unchanged ones
* Never request permission from a rebuild — permission UI belongs in Settings

### Conflict behavior

Never auto-resolve iCloud conflicts. A conflict copy is displayed as a
separate file.

### Project structure

The spec's layout lives under `Cove/` (the app target's synchronized folder):
`App/`, `Core/Models/`, `Core/Services/`, `Features/{VaultBrowser, Editor,
Search, Tasks, Lists, Settings}/`, `Platform/{iOS, macOS}/`. Tests are in
top-level `Tests/`. The widget extension is in top-level `CoveWidgets/`,
outside `Cove/`, because it is a separate build target.

---

## Architecture decisions

### Project and targets

**Hand-written Xcode project.** `Cove.xcodeproj` uses `objectVersion 77` with
`PBXFileSystemSynchronizedRootGroup` (Xcode 16+ buildable folders), so files
added on disk under `Cove/` or `Tests/` are picked up with no pbxproj edit. No
project generators.

**One multiplatform app target** (`SDKROOT = auto`, `iphoneos
iphonesimulator macosx`); platform differences live in `Cove/Platform/` behind
`#if os(...)`. Swift language mode 6 with complete strict concurrency, and
`@Observable` for app state.

**Entitlements are macOS-only** (`Cove/Cove.entitlements`, applied via
`CODE_SIGN_ENTITLEMENTS[sdk=macosx*]`): App Sandbox, user-selected read-write,
app-scope bookmarks. iOS needs none for document-picker folder access. macOS
signing stays ad-hoc (`CODE_SIGN_IDENTITY[sdk=macosx*] = -`); a
`DEVELOPMENT_TEAM` is set for device builds.

Bundle identifiers: `com.ankitbhade.Cove` / `com.ankitbhade.CoveTests` /
`com.ankitbhade.Cove.CoveWidgets`.

### Vault lifecycle

`VaultManager` (`@MainActor @Observable`) owns the lifecycle — `restoring →
needsVault | recoveryNeeded | open` — created in `CoveApp`, injected via
`.environment`.

**Bookmark options differ by platform.** macOS uses `.withSecurityScope` for
creation and resolution; iOS passes empty options, because document-picker
bookmarks there are implicitly security-scoped. A stale resolution re-creates
the bookmark best-effort inside a temporary scope; failure surfaces the
reselect-vault flow.

**Scope balance is tracked, not assumed.** The URL is recorded only when
`startAccessingSecurityScopedResource()` returned `true`, so every stop
matches a successful start. On macOS `NSOpenPanel` URLs work without starting
scope at all, but the calls stay symmetrical across both platforms rather than
branching.

**Loads are latest-wins.** Every load carries a generation and a requested
vault URL, cancels its predecessor, and commits only when both still match —
otherwise an older completion could restore a previous vault's tree, index, or
error state.

**An app-created content change rebuilds the index over the tree already in
memory.** Capture, toggle, delete, clear, and list edits write inside a file
the tree already lists, so re-enumerating every folder to learn that nothing
moved is work whose answer is known — and in an iCloud vault it is the
expensive half of a checkbox tap. The mutated note goes in as a changed URL so
it is re-read; every other note reuses its index entry. Reuse is gated on a
`treeIsCurrent` flag rather than on a tree merely existing: an index-only
refresh cancels whatever load is in flight, so without the flag it could
cancel a pending scan and then commit the very tree that scan was about to
replace. Everything structural — create, rename, move, delete, and the write
that *creates* the capture note — stays on the full rescan.

### Files and coordination

`VaultFileOperations` (stateless, `Sendable`) performs every mutation and note
read/save under per-item `NSFileCoordinator` coordination. Mutations run off
the main actor via `Task.detached` and rescan afterward.

**`VaultRepository` is the atomic-mutation boundary.** It coordinates one
write, reads the latest text *inside* that coordination, applies a throwing
semantic transform, and replaces only changed content. Every task, capture,
list, and widget path uses this rather than a public read followed by a save,
so no stale caller-side read can slip between the two.

**Case-only renames skip the destination-exists check**, because APFS is
case-insensitive by default and the destination is the source.

**Deletion is recoverable, and the recovery area is swept.** Items move under
`.cove-recovery` as `<timestamp>--<uuid>--<encoded path>--<name>`; Undo
restores them without overwriting a newly occupied path, prompting for a
replacement name when needed. `purgeRecovery` sweeps entries older than a
week — without it a delete never frees anything, and in an iCloud vault every
note ever deleted would sync and consume storage forever. The timestamp has to
be in the *name*: an item's own dates travel with it through the move and say
nothing about when it left the vault. The sweep runs detached once per vault
open (not per refresh — the area only grows through deletion), so it can
neither race an Undo, which only points at this session's entries, nor block
the vault from opening.

**Tree scans** take one coordinated read of the root, then list recursively
with `FileManager`, skipping hidden and symlinked items, sorting folders-first
then `localizedStandardCompare`.

### Editor

`NoteDocument` (`@MainActor @Observable`) owns one open note. Autosave is
debounced 1 s after typing stops, with explicit flushes on navigation and
scene transitions.

**Writes are serialized per document.** A `NoteWriter` actor coalesces pending
revisions so an old save cannot finish last and silently revert typing.

**A save never resurrects a dead file.** `saveNote` refuses to write when the
file is gone, so a pending autosave can't recreate a note that was renamed,
moved, or deleted.

**Neither version of a conflict is discarded.** Before replacing an externally
changed file, the writer preserves the disk text in a deterministic sibling
`cove-conflict` note and reports it. Local edits win the live buffer; the disk
version survives on disk.

**The save indicator derives from state rather than tracking it.**
`saveStatus` compares live text against what reached disk, so the toolbar
can't disagree with reality. It renders only while pending or saving — a
permanent "Saved" chip is chrome that also reads as a button it isn't — and
forces `.labelStyle(.titleAndIcon)`, since the toolbar otherwise collapses the
label to its icon and drops the meaning.

**`MarkdownTextView` is one type name with two platform files, whose basenames
must differ** — identical basenames in one target collide in the build system.
Smart quotes and dashes are disabled on both so Markdown syntax survives
typing. On iOS a `.keyboard`-placement Done button dismisses the keyboard,
which a `UITextView` has no return key to do.

### Markdown styling

`MarkdownParser` (pure Foundation) returns UTF-16 `NSRange`s that apply
directly to text storage. `MarkdownStyler` restyles the edited paragraph plus
its neighbors; whole-document styling is reserved for load and global style
changes. **Styling is attribute-only** — the stored text stays plain Markdown,
so selection and the undo stack are untouched. Restyling is skipped while IME
marked text is active.

**Checkbox toggling differs by platform.** iOS uses a tap recognizer set to
recognize simultaneously with the text view's own gestures, hit-testing the
character index against marker ranges. macOS subclasses into
`CheckboxTogglingTextView`, instantiated via `scrollableTextView()` — which,
unlike the alternatives, honors the subclass — and routes the flip through
`shouldChangeText`/`didChangeText` so it is undoable and reaches the delegate.
Both expose the toggle as an accessibility action and Command-Shift-Space.

### Change detection

`VaultChangeObserver` wraps one `NSMetadataQuery` with
`NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope`, which is the
scope that covers security-scoped folders reached through the system picker.
Updates are filtered to non-hidden items under the vault and debounced 600 ms;
the initial gathering pass is a baseline and never reported. Notifications are
reduced to `Sendable` URL values before entering the main actor, and observer
tokens are never touched from `deinit`.

`RootView` also rescans whenever the scene becomes active — a catch-all for
events missed while inactive and for non-iCloud vaults, which the metadata
query cannot see at all.

### Search

`NoteSearcher` runs one on-demand pass per query, reading each file through a
coordinated read and matching title and contents case- and
diacritic-insensitively. `search` is `nonisolated async`, so callers hop off
the main actor and cancellation stops the file loop between reads.

The browser's `.searchable` field swaps the tree for results on a non-empty
query, debounced by `.task(id: query)` plus a 300 ms sleep that a superseding
keystroke cancels. A spinner covers the debounce and the full-vault read,
since a blank list otherwise reads as "no matches" rather than "working".
Search does not touch the task index, and no search index is built or
persisted.

### Tasks and the index

`TaskParser` enforces the spec's syntax strictly, with two tie-breaks worth
knowing: the status character may be ` `/`x`/`X`, and when the text itself
contains `@due(...)`, the *last* one on the line is the tag (so an
`@repeat(...)` before it is just text).

**The index holds no note contents** — path, title, tasks, list headings,
modification date, size. Search re-reads from disk by design, so a copy here
would be a full in-memory duplicate of the vault that nothing reads. The date
and size are what let an unchanged note reuse its entry across a rebuild.
Scanning and indexing check cancellation throughout.

**A note that can't be read costs its own tasks, not the vault.** Invalid
UTF-8, or a file iCloud hasn't materialized, used to throw out of the index
build and into `VaultManager`'s catch-all, which closes the vault and shows
the recovery screen — one bad file denied access to every good one. The note
is now indexed with no tasks and, deliberately, no cache key, so the next
rebuild reads it again instead of trusting the failure forever.

**Recurrence intervals are clamped in the one initializer everything routes
through** (`RecurrenceRule.maximumInterval`), and quick entry clamps the count
in `in N days/weeks/months` the same way. The weekly arithmetic multiplies the
interval by seven: unclamped, a number a person can type — or leave sitting in
a note's `@repeat` tag — overflows and traps the process, in the parser's case
while the sentence is still being typed, since the preview re-parses on every
keystroke.

**Every task mutation re-finds its line semantically**, matching text plus
full schedule and preferring the remembered line number among duplicates. A
line that changed meanwhile raises `TaskChangedOnDiskError` and still
refreshes, so the list corrects itself rather than rewriting the wrong task.
Completing a recurring task advances its due date in place and leaves the
checkbox open, because the line is the task's single home.

**Deleting one task is unconfirmed but undoable.** The swipe is already
deliberate; the bulk Clear All is what warrants a dialog. Undo reinserts the
line near stable neighboring task identities rather than restoring a whole old
document, so unrelated later edits survive.

**Sorting compares `(dueDateString ?? "9999-99-99", dueTimeString ?? "",
fileTitle, lineNumber)`** — zero-padded strings order chronologically for
free, and the sentinel puts undated list items last.

**Dates are always Gregorian** (`TaskCalendar`), regardless of the user's
system calendar: the stored `YYYY-MM-DD` is a file format, not a display.
Presentation keeps the user's locale and zone.

**A task row omits its source note** — tasks nearly all live in the capture
note, so the caption repeated "Tasks" under every row.

Display logic is pure and tested against a fixed `now` (`TaskPresentation`).
Grouping into Overdue/Today/Tomorrow/Upcoming only *partitions* the sorted
list, leaving the spec's ordering untouched. A minute tick keeps those groups
true across a due moment or midnight, and the tab refreshes on appearance
because editor autosaves don't trigger a rescan.

### Quick capture

`QuickTaskParser` is a Swift port of grove-app's capture parser
(`grove-app/src/lib/parser/parse.ts`), matching its grammar and resolution
rules; its test suite ports grove's `parse.test.ts`. Each extractor claims the
span it consumed (overlaps lose), and the title is what's left.

Grove semantics kept verbatim: plain weekdays include today, `next <weekday>`
is strictly future, a bare time means today even if passed, `tonight` is
20:00, a weekday-set recurrence starts on the soonest listed day, and bare
numbers are never times (`buy 6 eggs` keeps its 6).

Divergences, each forced by a fixed rule: no hashtag lists (no tag feature),
undated input resolves to today on the Tasks screen (`@due` is mandatory
there), and a time range keeps only its start (no calendar events).

**The live preview is why there's no confirmation step.** It already answers
"did it understand me?", so a modal in front of every capture was pure
friction. `QuickCaptureField` is shared by the Tasks screen and every list
detail so the two entry points can't drift, and both await the write before
clearing so a failure keeps the sentence.

**`DueDescription` formats from the raw strings**, so a preview and the task
row it becomes cannot word the same date differently.

**A listless capture anchors on the end of the last *unlisted* stretch**, not
the end of the file. Appending blindly would drop the line under whichever
`##` list sits last, stamping it with that list and hiding it from the Tasks
screen entirely.

### Task lists

A list is a `##` section of the capture note, so the feature adds no new file,
no new syntax, and nothing to migrate — `Tasks.md` stays a note a person can
edit by hand.

`TaskParser.tasks` takes a `sectioned` flag: it tracks the nearest preceding
heading (`#` closes, `##`+ opens), stamps each task with a list name, and
*only then* accepts a `@due`-less line. **The builder passes `sectioned: true`
for exactly one file** — the root `Tasks.md` — so every other note keeps the
strict rules and no stray checkbox anywhere in the vault becomes a task.

Undated items therefore exist: they sort after dated ones, are never overdue,
render no due capsule, and can't be scheduled a notification.

**Lists build from the note's headings, not from its tasks**, so a list
created but not yet filled still exists.

**Each screen clears exactly what it shows.** `clearingCompletedTasks` takes
the same `sectioned` flag plus an optional list name: the Tasks screen's Clear
All must not delete completed items out of lists it never showed, and a list's
own Clear All touches only that heading's items.

Section surgery lives in `TaskListDocument` (pure, unit-tested) and runs
inside one coordinated read-modify-write, the same guarantee every capture
gets. Names match case-insensitively but display as the heading spells them.
`TaskRow` is shared by both screens so a list task and an ordinary task can't
drift apart. Renaming *or* deleting a list dismisses its detail view, since
the navigation value is the name. Deletion is offered from the overview swipe,
the row's context menu (macOS has no swipe, and the swipe is invisible until
tried), and the detail view's Options menu — all one path, one dialog.

### Notifications

Split into a pure, unit-tested planner and a thin actor scheduler.

The planner emits one-shot plans only for incomplete tasks *with a due time*,
skipping moments that have passed. **Recurring tasks are never scheduled
ahead** (grove parity): completing an occurrence rolls the line forward, and
the rebuild that follows schedules the next one.

**Plans are capped at 60**, soonest first, to stay under the system's 64
pending local notifications per app.

Bodies use a compact locale-sensitive month/day/time and expose no year,
filename, or recurrence metadata. Identifiers carry a `cove-task:` prefix so
the scheduler can diff Cove-owned requests and add only what changed.

**The scheduler never presents a permission prompt** — it schedules only when
authorization is already granted, and Settings owns the request. A rebuild
runs at the end of every successful tree load, which covers launch, mutations,
external changes, and scene activation.

### Navigation and presentation

`RootView` keeps a four-section tab bar on iOS and the same destinations in a
branded `NavigationSplitView` sidebar on macOS, sharing one selection model so
no behavior diverges.

**The browser shows one folder level at a time, bound directly to
`NavigationStack(path:)`.** A folder row is a real push, so the system back
button, its parent-folder title, and iOS swipe-back all work — the earlier
in-place swap had none of those and needed a custom back button.

**Folders and notes must share one path value type.** A typed `[URL]` path
silently ignores a `NavigationLink` carrying anything else, which is exactly
how note rows and search results were once dead. Because notes sit on the path
too, stale-path pruning looks up files as well as folders, so an open editor
survives rescans and pops only when its file really is gone.

`Greeting` (pure, unit-tested) owns the greeting text: seven stretches of the
day, each with phrases in a named and a plain form so an unset name never
leaves a dangling comma. **The pick is seeded by day ordinal plus stretch
index**, so the once-a-minute tick can't reshuffle the phrase mid-read while a
new day or stretch still changes it.

### The visual system

`CoveTheme` is the whole design system: tokens, type, and the handful of
components every screen is assembled from. It is **ink on warm paper, marked
in ember** — an unbleached warm canvas, warm ink, one saturated hue (a burnt
ember) for interaction and emphasis, moss for things that *contain* other
things, and a warm rust for lateness. Nothing else gets a color. The
deliberate absence is a second bright hue: a palette with two accents has to
explain which one means what on every screen it appears.

**Every token is a dynamic color, not a `(for: scheme)` function.** They are
built with `UIColor`/`NSColor` dynamic providers, so a token resolves itself
against the appearance it renders in and no view threads a `ColorScheme`
through to pick a shade. That also removes the failure the old form invited —
a nested component reading a different `colorScheme` than its container. The
resolution is what `CoveThemeTests` pins down (macOS only, where
`performAsCurrentDrawingAppearance` can fix the appearance): a provider that
quietly returned one shade for both appearances would look right in light
mode and wrong in dark with nothing failing, and the same tests hold ink,
accent, and alert to their WCAG contrast floors on the canvas.

**Serif type is the identity, and it is only ever a voice.** Titles a person
reads once — screen titles, mastheads, empty states, the brand mark — are set
in the system serif; data, labels, and anything scanned stay in the system
sans. It scales with Dynamic Type and needs no font asset. Labels are tracked
capitals (`coveEyebrow`) and every count is monospaced, so a badge doesn't
resize as its number changes.

**`NavigationBarAppearance` is the one UIKit appearance-proxy call in the
app.** SwiftUI has no modifier for a `navigationTitle`'s font, and that title
is the largest text on every screen — left as the system's bold sans it was
the one part of the app still reading as a default next to the serif masthead
directly beneath it. Touching `standardAppearance` replaces the whole
appearance object, so the transparent scroll-edge bar has to be restated or
every screen gains a material behind its title.

**`CoveMasthead` is one component, not three cards.** Notes, Tasks, and Lists
sit one tab apart and their headers get compared; three hand-built cards drift
by definition. It carries a short accent rule (the app's one repeated
ornament), an eyebrow, a serif title, an optional subtitle, an optional
trailing accessory, and whatever the screen puts underneath — a `CoveStatStrip`,
a `QuickCaptureField`, nothing. **An eyebrow never repeats the navigation
title above it**: at the vault root it names the open vault, which nothing
else on screen says; on a capture card it names the card.

Only two of the three convenience inits exist. A `Trailing == EmptyView` and a
`Content == EmptyView` init are both candidates for a single unlabeled
trailing closure, so the pair is ambiguous at every call site — the
accessory-carrying form is spelled out instead.

`CoveSectionHeader` is the one list-section header, `CoveIconTile` the one
row glyph (decorative, so `accessibilityHidden` — the row carries the label —
and `@ScaledMetric`-sized), and `CoveCountBadge` the one shape for "how many".
**Section headers are text, never `Label`s.** Caption-size SF Symbols with
fine detail — a sunrise, a calendar grid — render as smudges, and a header
that already says "Tomorrow · 1" has nothing left for a glyph to add.

**`CoveMark` is drawn, not loaded.** A serif `c` cupping an ember dot — the
shape of a sheltered inlet said abstractly, with no water in it. Drawing it
means it inherits the appearance, scales to any size without a new export, and
matches the serif titles beside it. The stamp inverts with appearance — ink on
warm paper in light, paper on night-black in dark, the ember dot and every
offset held constant — so it reads as the two faces of the same app icon
rather than two different marks. (It deliberately did *not* invert before the
icon adopted the same stamp; matching the icon's light face is what changed
the call.)

**Tab and sidebar symbols are outline names.** The iOS tab bar substitutes
the filled variant itself, so the choice only shows through on the macOS
sidebar, where outline is the platform convention.
The visual system is standard SwiftUI throughout — no assets beyond
`LaunchIcon`, no dependencies, no persistence changes.

`SettingsView` has no About section: the app's identity and version are
visible from the system. `AppearanceSetting` is applied by `RootView` around
*every* vault state, so the preference also covers the welcome and recovery
screens; an unrecognized stored value falls back to `system`.

### Icon and launch screen

The asset catalog carries generated `CoveMark` artwork — the serif `c` cupping
an ember dot, the same mark the interface draws. The set is a full-bleed 1024
iOS icon plus a dark variant, icon-grid rounded rects for every mac size, and a
`LaunchIcon` imageset used by the iOS launch screen. The mark is identical in
both appearances; only the ground changes — warm paper in light, a night-black
gradient in dark — and the serif `c` inverts with it so it reads on both.

**The icon and the in-app mark are now one shape.** The catalog art is
`CoveMark` rendered to PNG, the interface draws the live `CoveMark`, and both
carry the ink-and-ember palette — so the springboard icon, the launch screen,
and the loading/setup mark all agree. The coastal wordmark is retired.

**The `UILaunchScreen` dictionary lives in a root-level partial `Info.plist`**
merged via `INFOPLIST_FILE` alongside `GENERATE_INFOPLIST_FILE`, kept outside
`Cove/` so the synchronized folder doesn't sweep it up as a resource.

### Today widget (iOS)

`CoveWidgets` is a second target, an iOS-only WidgetKit app extension embedded
through an "Embed Foundation Extensions" copy phase.

**Both the copy phase's build file and the target dependency carry
`platformFilters = (ios)`.** Without them a macOS build fails outright:
"contains embedded content built for iOS".

**`NSExtensionPointIdentifier` must come from a real partial `Info.plist`**
(`CoveWidgets-Info.plist` at the repo root). `NSExtension` is a nested
dictionary and `INFOPLIST_KEY_*` settings only write top-level scalars — get
this wrong and the target builds cleanly, then fails to *install* with "Failed
to create app extension placeholder".

**The widget's shared sources are explicit pbxproj entries.** `Cove/` is a
synchronized root group belonging to the app target alone, so the nine pure
files the widget reuses get `PBXFileReference`/`PBXBuildFile` entries in its
Sources phase under "Shared with CoveWidgets". Nothing moved on disk.

The widget applies the design's own 14/15pt insets with
`.contentMarginsDisabled()`, since WidgetKit's wider defaults would cost the
small family a row. `WidgetPalette` restates the app's tokens as literals
rather than referencing `CoveTheme`, which lives in the app's view layer the
widget target doesn't compile — keeping them local means the extension needs
no shared asset catalog. The values differ on purpose: a widget sits on a Home
Screen beside other apps rather than inside Cove's canvas, so its background
is plain warm paper and its accent runs a shade deeper for legibility at
widget text sizes. It does reuse `DueDescription`, so a date can't be worded
one way here and another in the row it mirrors.

**The date is the header, and the word "Today" isn't in it.** A widget that
only ever shows today's tasks doesn't need to say so — the word took the
title and left the one fact worth glancing at as a caption beside it. The
weekday is wide on the medium family and abbreviated on the small one, with
the month and day secondary. "Today" survives as the widget's name in the
gallery, which is how it gets found.

**Checkboxes are drawn in `checkboxRest`, a muted accent, not the full one.**
The boxes repeat down the widget while the count and the times appear once
each, so at full saturation the rings were the loudest thing on a surface
whose job is to be glanced at. A completed row fills the same soft tone, so
finishing something quiets the row rather than lighting it up.

**Deep link:** `.widgetURL` is `cove://tasks`, handled in `RootView.onOpenURL`;
the scheme is registered in the root `Info.plist` under `CFBundleURLTypes`.

### Widget data channel

The widget is a separate process and can reach neither the app's
`UserDefaults` nor its vault, so everything shared goes through the App Group
`group.com.ankitbhade.Cove`. `WidgetSnapshot.swift`, compiled into both
targets, owns the whole channel — snapshot, bookmark, and pending-operation
queue — so the file names and JSON shapes can't drift apart.

**The snapshot is derived state, never a source of truth**; the Markdown files
remain that. It is written on every index rebuild, and one built for another
day reads as empty, so a widget that hasn't refreshed since yesterday can't
present yesterday's list as today's.

**The toggle intent carries only the row's id** — everything else is looked up
in the snapshot, which is by definition what the widget was drawing.

**A recorded path is validated against the vault, never trusted.** A
`TaskIdentity` is persisted state that crosses the App Group and can outlive
the vault it was written for — a queued toggle survives the user picking a
different folder. Both the extension and the app's drain resolve the path
against the vault they just opened (`fileURL(within:)`), holding it to the
scanner's own rules — inside the vault, a Markdown file, nothing hidden or
symlinked on the way in — and drop an operation that fails rather than
retrying it, since no retry can make it apply.

**Operations record desired state, not an instruction to toggle**, so
replaying one cannot undo a successful first attempt. Each is queued *before*
the write is attempted and acknowledged only after success, because whether an
extension can resolve a bookmark its host app created is not guaranteed on
iOS. The app drains the queue at the start of the next tree load, before the
scan, so the index is still built once. The snapshot updates optimistically
either way, which is what makes the tap feel instant.

**Retries are bounded at five**, counted by the app's drain only — the
widget's own write failing is the expected case the queue exists for. The
queue is durable, so without a ceiling an operation that can never apply would
be retried every launch for the life of the vault.

**Legacy queue migration is persisted on first read**, before being returned:
conversion mints fresh ids, so left in the legacy file it would hand out
different ids every read, and acknowledging one would address an operation the
file doesn't contain.

---

## Working on Cove

### PR naming

Format: `[Phase N] type: short description`, types `feat`, `fix`, `refactor`,
`docs`, `chore`. Phase 0 is scaffolding and documentation-only work; post-
Phase-11 hardening keeps the `[Phase 11]` tag. Branch names mirror the title
in kebab-case. Changelog text closely matches the title without the phase tag
and type prefix.

### Building and testing

```sh
# macOS build
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'platform=macOS' build

# iOS Simulator build
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'generic/platform=iOS Simulator' build

# Tests (macOS host)
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'platform=macOS' test
```

Current verified suite: **324 tests** (macOS host), plus clean macOS and
generic iOS Simulator builds, all with zero warnings.

### Documentation rule

Before any PR is complete, update `CHANGELOG.md`; update `README.md` when
user-facing behavior changes; update this file when a decision, constraint, or
limitation changes.

Then check these four, which go stale silently and are not usually in the
diff you just wrote:

1. The test count above
2. The Status section, if a phase or the current focus moved
3. Known limitations that your change fixed — delete them, don't leave them
4. `README.md`'s "Current state" paragraph

Add a limitation below when you ship a known rough edge. Don't restate a
decision that's already in Architecture; a limitation is what would *surprise*
someone, not what the design says.

### Regenerating the app icon

The mark is the `CoveMark` stamp — a serif `c` cupping an ember dot — and it
uses the **system serif** (New York), so unlike the old Cormorant wordmark it
needs no webfont, no headless Chrome, and no network. Every PNG is rendered
straight from SwiftUI with `ImageRenderer` on a macOS host. The spec (colors,
the geometry as fractions of the tile edge, and a drop-in `CoveIconArtwork`
view plus exporter) is the Claude Design handoff `Cove Icon - Claude Code
Handoff.md`; the design doc is `Cove App Icon.dc.html`. Both live in the Claude
Design project, not this repo.

The generator is throwaway — a standalone `swift` script (or a small `@main`
target) that instantiates `CoveIconArtwork` at each size and writes the PNGs
into `Cove/Assets.xcassets/`, then is deleted. It never ships. Three shapes:
full-bleed square for iOS (no baked corners — iOS masks it), an 824/1024
rounded-rect body inset into the macOS icon grid, and full-bleed rounded tiles
(radius `0.2237·S`) for `LaunchIcon`. iOS carries a light and a dark ground;
macOS exports the light ground at every size (its slot has no dark entry); the
launch tiles carry both (`.png` light, `-dark.png` dark). `Contents.json` for
both sets already names these exact filenames, so no manifest edit is needed.

Verify with a macOS and an iOS build afterwards — `actool` reports icon
problems as build *warnings*, not errors — and eyeball the renders, since the
serif `c`'s ball terminal and the dot placement are the whole mark.

---

## Known limitations

Rough edges and surprises, not restatements of the design above.

### Vault and files

* An open editor whose note is renamed, moved, or deleted keeps pointing at
  the old URL; pending edits are dropped and a save-error banner appears. The
  Notes tab's next rescan pops that editor off the path, but the Tasks tab's
  stack has no such pruning, so one opened from there stays on the dead URL.
* The recovery sweep is silent and has no UI: a deleted note is gone for good
  a week later, and nothing in the app lists or restores what's still in
  `.cove-recovery`. Recovering by hand means decoding the base64 path
  component of the entry's name.
* The sweep runs once per vault open, so a session left running for weeks
  keeps accumulating; reopening clears the backlog. Entries predating the
  sweep carry no timestamp and go on the first launch that includes it,
  regardless of age.
* Bookmarks are per-device, so each device runs folder selection once
  (expected — there is no custom sync).
* A tree scan holds one coordinated read for its whole duration. Fine for
  reads; all mutations use per-item coordination.
* A note the app can't read is silently indexed with no tasks: it still
  appears in the browser and still opens (the editor reports its own error),
  but any tasks in it are missing from the Tasks screen with nothing on screen
  saying why. The failure is in the log only.

### Editor and styling

* Clicking anywhere in a `- [ ]` marker toggles it instead of placing the
  insertion point. Edit the marker by moving the caret in from outside.
* Header fonts are computed from the body font at restyle time, so an iOS
  Dynamic Type change updates header sizes on the next edit, not instantly.
* The save indicator comes and goes while typing — it appears on the first
  keystroke and leaves about a second after typing stops.

### Change detection

* `NSMetadataQuery` only reports iCloud-backed items, so external edits to a
  non-iCloud vault are picked up by the scene-activation rescan only, not
  live.
* Every external change event makes each open editor re-read its own file,
  even when the changed items don't include it — metadata URLs aren't reliably
  comparable to picker URLs, so the reload is unconditional and cheap.

### Search

* Every debounced query re-reads every Markdown file (per spec: no persisted
  index). Fine for typical vaults; very large ones would feel it.
* Results don't live-update while showing — edit the query to re-run it.
* Matches are line-based: the snippet is the first matching line, and a query
  spanning a line break won't match.
* On iOS 26 a pushed folder level collapses the `.searchable` field into the
  toolbar rather than showing it under the title. That's the system's behavior
  for pushed levels, not a Cove layout bug.

### Tasks

* The Tasks tab lags reality between rebuilds: a task typed in the editor
  appears only after another refresh or rescan.
* The strict syntax fails silently. An indented line, a double space after the
  marker, an invalid date or time, or an unknown `@repeat` rule keeps a line
  out of the Tasks screen even though the editor still styles its checkbox.
* Tasks kept outside `Tasks.md` are indistinguishable in the list until
  opened, since a row doesn't name its note. Fine for the intended
  single-capture-note workflow.
* Recurrence-aware completion lives only in the Tasks tab. Tapping the same
  line's checkbox in the editor flips it to `[x]` like any checkbox, and the
  Tasks tab then shows it completed rather than rolled forward.
* Advancing an overdue recurring task anchors on the later of its due date and
  today — a deliberate divergence from grove, which anchors on the completed
  occurrence's date. Cove's single-line model has no occurrence history to
  catch up through.
* The minute tick re-evaluates the whole list body. Cheap at typical counts; a
  very large list would want it narrowed to rows that can actually change.

### Quick capture

* English-only. Tokens are consumed anywhere in the sentence, so "plan friday
  party tmr" is due tomorrow and titled "Plan party" — the losing date word
  still leaves the title.
* Hashtags stay in the title (no tag feature), and ISO dates ("2026-07-21")
  aren't in grove's grammar — use slash or month-name dates, or the picker.
* Capture writes on return with no confirmation and no undo. A mis-parsed task
  is just a line in `Tasks.md`: swipe the row away and retype. The live
  preview is the only thing between a typo and the note, which is why it isn't
  optional chrome.
* A bare time stays on today even when that moment has passed: "standup 9a"
  typed at 10:00 lands today, already overdue, and gets no notification.
* Time ranges keep only the start; Cove has no calendar events.
* An empty title can't be captured, so a sentence that is nothing but a date
  leaves the add button disabled.
* Absurd counts are clamped silently: "in 99999 weeks" is read as the maximum
  relative count, and a repeat interval above `RecurrenceRule.maximumInterval`
  becomes that maximum. The preview shows the clamped date, which is the only
  signal.
* The preview re-parses the whole sentence on every keystroke — cheap, but a
  regex sweep rather than an incremental parse.
* Captures always land in `Tasks.md` at the vault root; the capture note isn't
  configurable. If iCloud syncs in a *folder* of that name, capture fails with
  an error alert.
* A listless capture lands at the end of the note's free space, so in a note
  whose lists sit at the bottom it goes above the first `##` heading, not at
  the end of the file. A note that is nothing but lists takes it at the top.

### Lists

* Lists live only in the capture note. A `##` heading in any other note is
  just a heading.
* A list's identity is its heading text, so renaming one by hand in the editor
  is indistinguishable from deleting one list and creating another. Nothing is
  lost, but the Lists tab has no memory of the old name.
* Deleting a list deletes its tasks with it — confirmed by dialog, but with no
  undo beyond the editor's.
* An undated list item can never gain a time or repeat rule, since both live
  inside or after the `@due` tag. The draft sheet's date toggle drops all three
  together, so turning the date back on starts from today with no time.
* Completed list items stay under a Done header until that list's own Clear
  All sweeps them.
* An item captured into a list deleted meanwhile recreates the heading at the
  end of the note rather than failing.

### Notifications

* Only timed tasks notify. A date-only task never does, and a timed
  non-recurring task whose moment has passed gets nothing.
* At most 60 requests are scheduled (soonest first).
* A recurring task has only its current occurrence pending; the next is
  scheduled only after this device rebuilds following the completion that
  rolled the line forward. Ignore a recurring notification without completing
  it and no further reminders arrive.
* A notification is a reminder, not a live view: tapping it opens the app but
  not the task, and a task completed on another device keeps its scheduled
  notification here until this device next rebuilds.
* Settings polls permission status on appearance and scene re-activation, not
  live, so granting it in System Settings shows up when the app returns.

### Widget

* iOS-only. WidgetKit has a macOS equivalent, but the App Group needs real
  signing there and the macOS app signs ad-hoc.
* The App Group works in the simulator with no portal setup, but a **device**
  build needs `group.com.ankitbhade.Cove` registered for the team. Until it
  is, the widget renders its empty state rather than failing loudly.
* The widget never reads the vault, only the last published snapshot, so a
  task added on another device appears only after this device's app next runs
  — the Tasks tab's staleness, one step further removed.
* When the extension can't resolve the bookmark, the checkbox still looks
  right but the line isn't rewritten until the app next drains the queue.
* An attempt goes uncounted when the bookkeeping write itself fails, so a
  queue that can't be written also can't be pruned. Deliberate — the
  alternative is dropping an operation on a failure we couldn't record — but
  an unwritable container leaves retries unbounded.
* The 44×44pt checkbox targets are larger than the row pitch, so a tap in the
  ~8pt band between two rows may hit the neighbour.

### Visual system

* Serif navigation titles are iOS-only. `NavigationBarAppearance` has no
  AppKit counterpart, so on macOS the window title and sidebar labels stay in
  the system sans while the mastheads under them are serif.
* Destructive buttons (`Clear All`, swipe-to-delete) keep the system red
  rather than `CoveTheme.alert`, so a swipe action's red fill sits a shade off
  the rust an overdue task uses. Deliberate — the role also carries VoiceOver
  and confirmation semantics that a tinted plain button would drop.
* The eyebrow is uppercased by `textCase`, so a vault or list name that is
  already an acronym or deliberately lowercase is restyled in the masthead.

### Icon and platform

* The icon PNGs are generated artwork checked into the catalog, and the spec
  (the handoff and design doc) lives in the Claude Design project, not the
  repo — an icon change means re-rendering the full size set from
  `CoveIconArtwork` (see "Regenerating the app icon"). The generator itself
  is throwaway and not kept in the repo.
* The dark iOS icon variant is opaque rather than transparent. Apple's iOS 18
  guidance prefers a transparent dark icon over a system backdrop, but the mark
  supplies its own night-black ground. iOS 17 ignores the variant entirely.
* The launch screen is iOS-only; macOS windows open with the app's content.

### Testing

* The unit-test bundle runs inside the sandboxed app host on macOS, so tests
  that create bookmarks use the app container's temporary directory, which the
  sandbox can bookmark.
* External change detection isn't unit-testable (no iCloud in the test host) —
  only the URL filter and the editor reload logic are covered. Verify live
  behavior manually with a vault in iCloud Drive.
* `TaskNotificationScheduler` needs manual delivery verification; the planner
  and diff inputs are deterministic, but the system center isn't exercised.
* The visual system was verified by screenshotting every screen on the iOS
  Simulator in both appearances; the Mac build is checked by launching it,
  since GUI capture needs Screen Recording permission the shell doesn't have.
  `CoveThemeTests` is what covers the macOS side of the palette — appearance
  resolution and contrast — and it is the only automated evidence that dark
  mode is right there.
* The Today widget is verified on a real simulator Home Screen: added through
  the widget gallery at both sizes in light and dark, showing a live vault's
  tasks, and its interactive checkbox was tapped and confirmed to rewrite the
  `- [ ]` line in `Tasks.md`. That last part means the extension *can* resolve
  a bookmark the host app created, at least in the simulator — the pending-
  operation queue is still the fallback for when it can't. Adding a widget
  needs tap injection (long-press the Home Screen → Edit → Add Widget), not
  `simctl` alone.
* Date handling is tested against non-Gregorian system calendars, UTC-ahead
  and -behind zones, New York DST transitions, and midnight.
