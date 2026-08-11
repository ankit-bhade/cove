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
hardening and a new visual direction — ink on warm paper, marked in ember,
replacing the coastal palette the app shipped with. That direction was pushed
down into the grid — one `CoveRow` behind every list row and one pair of tint
tokens behind every tinted surface — and Tasks became the section the app
opens on. Then the same consolidation was applied to behavior rather
than appearance: one `TaskActions` behind both task screens, one
`FileCoordination` behind every coordinated access, one `covePresence()`
behind every optional-driven presentation, and a time zone rather than a
discarded `Calendar` in every date API. Then the headers were
weighed against what they cost, and none of them survived: the tall masthead
with its serif title, its slogan, and the day-part greeting is replaced
everywhere by a compact `CovePanel`, so every screen opens on its own content
rather than on a sentence about itself. Then the one row that had
stayed off the shared grid — the task row, with its own insets, its own
padding, and its own separator inset — was put on it, so the text column and
the row rhythm are the same on every screen. Most recently the mark
itself was redrawn twice: the serif `c` and its ember dot — the last piece of
the identity still set in type, and the one that leaned right because a serif
face has a diagonal stress — became two concentric arcs on a single axis, and
those arcs in turn became a coastline, a bay cut into the land's edge with its
shoreline traced in ember. The arcs fixed the lean and were centred by
construction, but they said nothing about what the app is; the coastline did,
and it made the tile itself the mark rather than a ground the mark sits on —
until it was found to be a horizon line that dissolves at small sizes (below).
Then the wall between Lists and Tasks was moved from the heading to
the date: a list item that carries a `@due` date now appears on the Tasks
screen too, naming its list under its title, while an undated one stays in
its list alone — which is the distinction the feature was always about.
Most recently, Phase 12 opened on the first thing Cove tracks that is not a
task: **subscriptions**, recorded as one line per recurring charge in
`Trackers/Subscriptions.md`, with `@since` as a fixed anchor so the next charge is
derived and the file is never rewritten by the passage of time. It arrived
under a fifth tab, **Trackers** — a hub holding one row today, so a later
tracker is a row rather than a navigation rework — with monthly and yearly
totals, the charges landing in the next thirty days, the charges themselves
grouped by `##` category, and one single-hue chart ranking what each
subscription costs per month.
Most recently a review pass closed the gaps between what the app said and what
it did. Every push into the editor now carries a **line** as well as a note,
so a search hit, a task row, and a format warning that prints "line 42" all
land where they point — the Settings link had been promising that in prose for
some time. **Quick capture became undoable**, which was the last mutating task
action that wasn't. Derived state stopped being rebuilt for changes that
cannot affect it: the widget snapshot and the notification schedule are
reconciled off a fingerprint of the tasks and the day, the recovery counts are
off the checkbox path, and no screen rescans the vault merely because it was
opened. And the things a reader could not see are visible — recovered drafts
raise their own non-alarming state rather than reading as "Ready", a capped
diagnostic list says how much it is hiding, and a chart drawn in one currency
says which one.
Most recently the direction was pressed on the one thing it had been
accumulating: **surfaces**. A UI review found the app coherent and slightly
over-layered — a masthead, a capture well, a card per task group, and the
platform's own rounded chrome all reading as cards inside cards, with only
four tasks visible on the screen the app opens on. So the task groups became
one continuous list surface with their headings set inside it, section gaps
tightened app-wide, overview panels are drawn only where summing more than one
thing means something, tracked capitals were pulled back to headings alone,
and the quick-capture field got a token of its own so that at night it lifts
off the panel rather than sinking invisibly into it.
Most recently the mark was redrawn a third time, and this one is a retreat
from meaning rather than toward it: the coastline's silhouette is a **horizon
line**, so below about 40pt its 4-unit shoreline goes sub-pixel and what is
left reads as texture — which on a Home Screen, at a Dock size, or in a 32pt
sidebar stamp is where the mark actually lives. It is now **one disc, cut
once**: a circle split by a single vertical kerf left of centre, the larger
piece in ink and the smaller in ember, two filled shapes that differ in value
rather than in outline. Nothing is stroked, so nothing needs an optical
minimum, and the app icon holds an ink ground in both appearances because a
dark tile keeps its edge against any wallpaper. The 18 PNGs came with it, and
so did their generator — `Scripts/render-mark.swift` is kept in the repo now
rather than deleted after use.
Before that, a full review — the suite, both builds, and the app driven on
the Simulator — found two things the reading alone had not. `main` was failing
its own `Scripts/verify-build.sh` at the log-privacy scan, which halts before
the tests and both builds ever run; and the **Undo bar reached two of the nine
undoable actions**, so four confirmation dialogs promised an Undo that iPhone
had no route to, over deletions that never reach `.cove-recovery`. Deleting a
list on a phone destroyed its tasks permanently while saying it did not. The
bar is now `CoveUndoCenter`, any screen can own one, and registering does both
halves in a single call. The same pass made the lint step `--strict` — it had
been reporting 28 findings and exiting 0 — and stopped a subscription row
tinting its cost and cycle because a renewal happened to be within the week.
Before that, a UI review found the app coherent and asked for five things,
all of which were about *reach* rather than about the look: a task could be
rescheduled only by editing Markdown by hand, an Undo that existed was
invisible on a phone, Settings answered four questions beside four nobody
asked, a refresh button sat beside every title for an action that is
automatic, and an iPad ran a phone's tab bar. So a task row now opens its own
details with the note one item away, a destructive action raises a bar that
says it can be taken back, Settings keeps four rows and puts the rest behind
**Advanced**, iOS refreshes by pulling instead of by a button, and a
regular-width iPad takes the Mac's sidebar. The quick-capture placeholder,
which truncated to three useless words at accessibility sizes, became "Add a
task…"; the example under the field has since gone too, leaving the live
preview as the only thing teaching the grammar.
Before that, a durability review found four places where a *second device*
was quietly overruled. Completion and status are deliberately outside the
semantic keys that re-find a line, which is what makes setting them
idempotent — and it is also what let a stale write through: a tap on a
checkbox another device had already ticked wrote nothing and still registered
an Undo, a subscription sheet saved the status it opened with over a
cancellation made meanwhile, and both delete Undos restored the index's copy
of a line rather than the bytes the coordinated write took out. Each is now
either refused or captured inside the coordination. The fourth was the
opposite failure: an unreadable recovery draft read as *no draft*, so the
clean-load path deleted the only copy of some unsaved text — it is quarantined
now.
See `CHANGELOG.md`
for what has shipped and "The visual system" below for what the direction
commits to.

**Cove is a personal app and is not distributed.** No App Store, no
TestFlight, no notarized build, no external testers — it is built from this
repo and run on its author's own devices. That is a scoping decision, not a
stage: work that exists only to satisfy a submission pipeline (privacy
manifests, distribution signing, archive validation) does not belong here and
was deliberately removed. macOS therefore keeps ad-hoc signing, which needs
no certificate and no team.

What it does *not* excuse is durability. The vault is the user's real notes,
in real iCloud, with no backend to re-sync from and no support channel — a
lost buffer or a corrupted `Tasks.md` is simply lost. So the current focus is
the reliability half of a full technical audit: the crash-recovery draft
journal, the transactional vault switch, the awaited save → index →
notification → widget pipeline, the Markdown-context-aware parser, the
anchored recurrence arithmetic, the in-app recovery review, and
`Scripts/verify-build.sh`. Those earn their keep on one device.

The gates that remain genuinely open are the ones a simulator cannot close:
two-device iCloud conflict behavior, real notification delivery, forced
termination, and App Group behavior on a signed device build.

The phases were: folder picker and bookmarks (1), editor and file operations
(2), live Markdown styling (3), iCloud change detection (4), search (5), tasks
(6), notifications (7), quick capture (8), appearance and icon (9), task lists
(10), Today widget (11), trackers (12, in progress).

---

## Fixed rules

These are non-negotiable. A change that breaks one is wrong even if it works.

* The filesystem is the source of truth; no database, no backend, no accounts,
  no plugins, no custom sync.
* No third-party dependencies (app or build tooling).
* Never hardcode a vault folder name or location.
* All vault filesystem access goes through `NSFileCoordinator`.
* Hidden files, packages, aliases, and symlinks are always ignored.
* The task line Cove **writes** is fixed:
  `- [ ] Task text @due(YYYY-MM-DD[ HH:MM])[ @repeat(rule)][ @anchor(YYYY-MM-DD)]`
  — one space between parts, `-` bullet, no indentation, no alternates. Every
  generated line is round-tripped through the parser before it is saved.
  What Cove **reads** is deliberately wider, and only in ways that cannot
  change a line's meaning: leading indentation, `*` and `+` bullets, and runs
  of spaces or tabs where the canonical form has one. That is the difference
  between a nested Obsidian checkbox silently vanishing from the Tasks screen
  and being understood. A date that is not a date and a time that is not a
  time are still rejected, and rejection is now reported (see diagnostics)
  rather than silent.
* `@anchor(YYYY-MM-DD)` is written by Cove, never typed. It records the
  occurrence a recurring task was last advanced from, and only ever follows
  `@repeat`. Without it "every month on the 31st" walks backwards off
  February and a Feb-29 yearly task never returns to leap day.
* The one relaxation of `@due` itself is `@due`-less lines inside a `##` list
  section of the capture note, and it applies nowhere else.
* The subscription line Cove **writes** is fixed the same way:
  `- Name @cost(0.00 CUR) @every(cycle) @since(YYYY-MM-DD)[ @status(paused|cancelled)]`
  — one space between parts, `-` bullet, no indentation, tags in that order.
  Every generated line is round-tripped through the parser before it is saved.
  What it **reads** is wider in ways that cannot change meaning: indentation,
  `*` and `+` bullets, runs of spaces or tabs, a lower-case currency code, a
  cost with fewer than two fraction digits, and any cycle wording
  `BillingCycle` understands. A cost that is not a number, a date that is not a
  date, and a cycle that is not a cycle are rejected and reported.
* Amounts are `Decimal`, never `Double`, and **no currency is ever converted**
  — conversion needs a rate, a rate needs a network. Totals are per currency.
* Task-looking text inside YAML front matter, a fenced code block, or an HTML
  comment is never indexed and never edited.
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
the affected files and rebuild the index. A macOS root-descriptor event does
not identify a child, so it deliberately takes the full-scan fallback.

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
Overdue, Today, and Tomorrow are always shown; Upcoming can be collapsed and
the completed section also starts collapsed.

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
* A list item with a `@due` date also appears on the Tasks screen, grouped by
  day with everything else and naming its list under the title; an undated one
  never does. The Tasks screen's Clear All takes what it showed — dated list
  items included — and never the undated ones
* Lists can be created, renamed, and deleted; deleting one removes its heading
  and every task under it

**Subscriptions** — recurring charges, recorded in `Trackers/Subscriptions.md`,
with the folder and the note both created on demand. One line per charge, `##` headings as
categories, and the grammar in Fixed rules above. This is the first
**tracker**: a Markdown note at the vault root with a fixed line grammar and a
screen that reads it. The plan is a Trackers hub section holding one row per
tracker, so a later one is a row rather than a navigation rework — but the
abstraction stops there. The format, the parser, the math, and the views are
subscription-specific, the same way Lists and Tasks are concrete.

* `@since` is the **first** charge date and the permanent anchor. The next
  charge is derived, never stored
* `@status(paused|cancelled)` is written only when set; absent means active,
  and only active charges count toward totals or upcoming
* Monthly and yearly cycles normalize exactly — twelve monthly charges a year,
  four quarterly ones — so a monthly subscription's monthly figure is its own
  price. Weekly and daily cycles use the mean Gregorian year (365.25 days) and
  are therefore averages; `SubscriptionMath.totalsAreExact` reports which case
  a screen is in
* A weekday set (`every mon wed`) is a valid task recurrence and is not a
  billing cycle, so `BillingCycle` cannot hold one

**The intended scope is software and service subscriptions** — streaming,
games, tools, a gym — not large recurring bills. Rent and a mortgage are not
what this is for. Nothing in the format or the arithmetic forbids them, and
they would be reported correctly; the reason it is written down is that the
chart is tuned for that range. One charge an order of magnitude above the rest
compresses every other bar to a sliver, which is the data reported honestly (a
log scale would misstate the magnitudes) but makes the chart useless. At
subscription scale that does not happen.

**Settings** — select or reselect vault, recover from stale bookmarks,
system/light/dark appearance, notification permission. Task *and* subscription
format warnings are listed here with note and line number, each opening the
editor at that line.

A **Vault Safety** row reports one of three states rather than two.
`CoveStorageHealth.attention` is `ready`, `recovery`, or `needsAttention`:
recovery is work Cove *saved* rather than a fault, so reporting it in alert
red would overstate it and reporting it not at all — which "Ready" did — left
recovered drafts sitting in Application Support with nothing on screen saying
so. Only *drafts* raise it. `recoveryItemCount` deliberately cannot: deleted
items live in the recovery area for a week by design, so any vault where
something was recently deleted would sit permanently in a non-ready state, and
a signal that is always on is not a signal.

**Everything a healthy vault never has to be told sits behind one
`Advanced` disclosure**: Cove Recovery, the widget's status, folder access,
and bookmark state. Settings is read for four things — which folder, which
appearance, whether reminders are on, and whether anything is wrong — and it
had grown to answer those beside four more that a reader neither chose nor can
act on while they are healthy. They are behind a disclosure rather than gone
because each is the whole explanation for something that *does* go wrong, so
the group opens itself in exactly those cases: a bookmark that is not
persisted (why a vault keeps asking to be reselected), a recovered draft
waiting for a decision, or a widget change that could not be applied. A
deleted item deliberately cannot open it, for the reason it cannot raise
`CoveStorageHealth.attention` — the recovery area holds them for a week by
design.

**A capped diagnostic list says what it is hiding.** The cap keeps a vault
with a thousand bad lines from building a thousand rows into a `Form`; what it
used to do was truncate silently, so a header reading "20 task format
warnings" sat over exactly 20 rows out of 200 and told the reader they had
seen everything. `DiagnosticDisclosure` is the one component behind all four
lists, and it carries the omitted count and a Show All.

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
`App/`, `DesignSystem/`, `Core/Models/`, `Core/Services/`,
`Features/{VaultBrowser, Editor, Search, Tasks, Lists, Trackers, Settings}/`
(with `Trackers/Subscriptions/` under it), and
`Platform/{iOS, macOS}/`. Tests are in top-level `Tests/`. The widget
extension is in top-level `CoveWidgets/`, outside `Cove/`, because it is a
separate build target.

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

**Every platform carries entitlements, for different reasons.** macOS
(`Cove/Cove.entitlements`) needs App Sandbox, user-selected read-write, and
app-scope bookmarks. iOS still needs none of those for document-picker folder
access — but `Cove/Cove-iOS.entitlements` and
`CoveWidgets/CoveWidgets.entitlements` exist for the App Group the widget
channel runs through, so the older "entitlements are macOS-only" note is no
longer true. macOS signing stays ad-hoc
(`CODE_SIGN_IDENTITY[sdk=macosx*] = -`), which is right for an app that is
only ever built and run here: it needs no certificate, no team, and no
renewal. A `DEVELOPMENT_TEAM` is set for iOS device builds.

**There are no privacy manifests, deliberately.** `PrivacyInfo.xcprivacy`
exists to satisfy App Store Connect's required-reason API declarations at
upload time; it has no runtime effect whatsoever. Cove is not uploaded
anywhere, so the manifests, their test, and the archive-validation script
were removed rather than carried as ceremony. If this ever *were* submitted,
they would need to come back — the app uses `UserDefaults` (CA92.1, the
bookmark store) and file timestamps (3B52.1, the index cache key).

The widget still omits `VaultBookmarkStore`, reading its bookmark from the
App Group container and inlining the two resolution flags in
`ToggleTaskIntent`. That began as a way to keep the extension free of
required-reason APIs; it survives the manifests because it is simply less
code in the extension.

**A file shared with the widget can only use what the widget compiles.**
`Cove/` belongs to the app target alone, so the shared sources are explicit
pbxproj entries under "Shared with CoveWidgets" — and a new dependency added
to one of them has to join that list. `CoveDiagnostics.swift` (`CoveLog`) is
there for exactly this reason: `VaultFileOperations` started logging, and
without it the widget target stops compiling while the macOS app keeps
building fine, so only an iOS build catches it.

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

**The widget and the notifications are reconciled off a fingerprint, not off
every rebuild.** Both are derived from the *tasks*, and a rebuild happens for
any content change at all — so typing a sentence into an unrelated note
rewrote the widget snapshot and re-diffed every pending notification for a
task set that had not moved. `reconcileDerivedState` hashes `index.allTasks`
plus the current day and returns early when it matches the last one. The day
is in the hash because a snapshot is built *for* a day and one built for
another reads as empty, so a task set that never changes still has to be
republished across midnight.

**The fingerprint therefore needs a way to be forced, and forgetting that is
how it breaks.** Newly granted notification permission changes nothing about
the tasks and is exactly the moment the rebuild matters, so Settings calls
`rescheduleDerivedState()` rather than `refresh()` — as does the retry after a
failed schedule. A vault switch and an unavailable vault both clear it, since
a fingerprint taken against one vault's tasks says nothing about another's.

**Recovery counts are a filesystem walk, so they are off the tap path.**
`refreshStorageCounts` walks the recovery area and the draft store, and only a
delete, a restore, or a draft can move either number — none of which a
targeted refresh can be. It runs on every full scan (`force`), and a targeted
one reuses the last count for 30 seconds. The cost is that a draft written
moments ago may not be counted until the next full scan, which the
scene-activation rescan guarantees.

**No screen rescans on appearance any more.** Tasks, Lists, Trackers, and
Subscriptions each opened with `await vaultManager.refresh()`, justified by a
comment saying editor autosaves don't reach the index. They do —
`noteDidPersist` has re-read the one changed note for some time — so between
that, the metadata observer, and `RootView`'s scene-activation rescan, a full
scan per tab visit was the same answer arrived at the expensive way. Each
screen keeps its toolbar refresh, which is the manual path for a vault the
observer cannot see.

### Files and coordination

`VaultFileOperations` (stateless, `Sendable`) performs every mutation and note
read/save under per-item `NSFileCoordinator` coordination. Mutations run off
the main actor via `Task.detached` and rescan afterward.

**`FileCoordination` is the one coordinator call shape.** Every coordinated
access is the same five lines — make a coordinator, hand it an `NSError`
out-parameter, capture the accessor's value or its throw, then work out which
of the two failed — and written per call site that had become five
near-identical copies across `VaultFileOperations` and the widget queue. It
lives in `VaultFileOperations.swift` deliberately: that file is already in the
widget target's shared-sources group, so both processes get it with no pbxproj
edit. The dual-URL variant hands the coordinator itself to its body, which is
the only reason it is exposed — a move has to report `item(at:didMoveTo:)`
from inside the coordination. A coordinator that reported no error and never
ran its accessor is treated as a failure rather than success, since the
alternative is silently claiming a write that never happened.

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
the vault from opening. Cleanup trusts only an owner- and schema-marked
manifest and exact Cove timestamp/UUID names; unknown files in that hidden
folder are never treated as expired recovery data.

**Tree scans** take one coordinated read of the root, then list recursively
with `FileManager`, skipping hidden, package, alias, and symlinked items,
sorting folders-first then `localizedStandardCompare`.

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

**A recovery draft that cannot be decoded is quarantined, never cleared.** A
damaged record, or one written by a future version, throws out of
`draftStore.load` — and the load then treats the note as having *no* draft,
which is the branch that clears the slot. So the one file holding text that
reached no other storage was deleted by the code that could not read it. It is
moved to `<hash>.unreadable` instead, which the editor's message names and
which `summaries()` skips, since a record that cannot be decoded cannot be
listed either. The slot holds one file per note and a later quarantine
replaces an earlier one: the alternative is unbounded growth in a container
with no UI. This is the widget snapshot's "preserve the unreadable bytes once"
rule applied to data that is not derived and therefore cannot be rebuilt.

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
its neighbors. It parses the whole string to retain fenced-code and YAML
context, then applies only ranges intersecting those paragraphs; load and
global style changes still apply across the whole document.

**A `#` line is set in the serif face**, which is the same split the rest of
the type system draws — a heading is read once where the text under it is
scanned — and it puts a note's own title in the voice of the screen title
directly above it. **Paragraph spacing has to beat line spacing** (7 against
4): at 4 and 2 a wrapped sentence and the next task line opened the same gap,
so a note of checkboxes read as a single block of text. **Styling is attribute-only** — the stored text stays plain Markdown,
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

**Recurrence advances from an anchor, not from the tap.** The old arithmetic
added one interval to `max(dueDate, today)`, which meant an overdue task
re-anchored its whole cadence to the day the checkbox happened to be pressed,
"every month on the 31st" walked back to the 28th the first time it passed
February and stayed there, and a Feb-29 yearly task clamped to the 28th and
never found leap day again. The rule now computes the first occurrence in the
*anchor's* cadence after both the completed occurrence and today, so catching
up on a task three weeks late lands on the next real occurrence rather than
three weeks off the schedule. The anchor is persisted as `@anchor(...)` on
first advance because a single Markdown line is the task's whole history —
there is nowhere else to keep it — and it is the reason
`revertingRecurringCompletionResult` can find the advanced line at all: Undo
that merely set the old occurrence back to incomplete had nothing to match.

**Every task mutation re-finds its line semantically**, matching text plus
full schedule, and **refuses when that is not unique**. It used to fall back
to the first candidate, which is the one case where being helpful is wrong:
after an external edit shifts lines, "the first task that looks like this" is
not the task the user tapped. `MutationError.ambiguousTask` names the lines,
the index carries a `duplicateTask` diagnostic, and Settings links to it. A
line that changed meanwhile raises `TaskChangedOnDiskError` and still
refreshes, so the list corrects itself rather than rewriting the wrong task.
Completing a recurring task advances its due date in place and leaves the
checkbox open, because the line is the task's single home.

**What the semantic key leaves out is what a stale write gets through.**
Completion is excluded on purpose — a semantic "set this to done" has to find
a line another device already ticked, or a replay fails against content that
is already correct. The cost is that such a tap is a *no-op* that still looked
like a successful toggle: it registered an Undo whose only effect would be to
reverse the other device's change. `setTaskCompleted` therefore reports
`NoteMutationResult.changed` and `toggleTask` returns `nil` when nothing was
written, so `TaskActions` registers nothing. The same exclusion is why a
delete has to capture its own line (below).

**An edit rewrites the line's body and nothing else.**
`TaskParser.replacingTaskResult` re-finds the line semantically like every
other mutation, then replaces only the span between the `- [ ] ` marker and
the line's trailing whitespace. The indentation, the bullet character, the
checkbox, and the terminator stay as the file had them, because an edit
changed the *task* and not how the file writes it down — a canonical
whole-line rewrite would flatten a nested Obsidian checkbox and tick a box
another device had just ticked, neither of which anyone asked for. `TaskDraft`
gained `validatedLineBody()` for it, and `validatedMarkdownLine()` is now that
plus the marker, so the capture path and the edit path cannot disagree about
the tag order.

**The recurrence anchor survives an edit only when the schedule does.** It
records the occurrence a recurring task was last advanced from, and a new due
date *is* a new anchor — carrying the old one forward would drag the cadence
back to a date the user has just moved away from. `keepingRecurrenceAnchor` is
therefore decided by `TaskDraft.hasSameSchedule(as:)` and passed in, since the
draft has no field for a tag Cove writes and never reads from a person.

**Undo restores a body captured inside the coordination**, exactly as the
delete records its line: `TaskEditRecord` carries the *edited* line's identity
— read back out of the parser, the round trip every generated line makes — and
the previous body, which includes whatever anchor the line had.
`VaultManager.identity(forLine:in:list:isSectionedDocument:)` is the one
"parse back what we just wrote" helper, generalized from the capture-only
version because an edit can touch a task in any note, where a `##` heading
means nothing and the strict rules apply.

**An unlisted task cannot be edited into an undated one.** `@due` is what
makes a line a task outside a list section of the capture note, so dropping it
would not reschedule the task, it would delete it from the index. The sheet
does not offer the toggle and `updateTask` refuses anyway
(`TaskUpdateError.dueDateRequired`), because the sheet is a caller and the
rule is the file format's.

**Deleting one task is unconfirmed but undoable.** The swipe is already
deliberate; the bulk Clear All is what warrants a dialog. Undo reinserts the
line near stable neighboring task identities rather than restoring a whole old
document, so unrelated later edits survive.

**The line Undo puts back is captured inside the coordination, not read
before it.** A caller-side read followed by a write is exactly what
`VaultRepository` exists to prevent, and a delete record built from the index
is that read at its stalest. Completion, the bullet, and interior spacing are
all outside the semantic key, so a line edited elsewhere is still *found* —
and restoring the index's copy would silently undo that edit too.
`removingTaskWithLineResult` and `removingSubscriptionWithRecordResult` return
the removed line alongside the new text, and `CoordinatedTransformOutput`
carries it back out of the `@Sendable` transform. Last value wins, because the
coordinated write re-runs its transform when the bytes change under it and the
last run is the one that was committed. The bulk paths keep the index's copy:
they preflight completion against the coordinated bytes before removing
anything.

**Bulk clear is a grouped semantic operation.** It targets only completed
identities present in the current index, preflights every affected file before
the first write, repeats the checks inside each coordinated transform, and
rolls back already-applied batches if a later write fails. Undo restores the
removed lines against the newest file contents rather than restoring snapshots.

**Sorting compares `(dueDateString ?? "9999-99-99", dueTimeString ?? "",
fileTitle, lineNumber)`** — zero-padded strings order chronologically for
free, and the sentinel puts undated list items last.

**Dates are always Gregorian** (`TaskCalendar`), regardless of the user's
system calendar: the stored `YYYY-MM-DD` is a file format, not a display.
Presentation keeps the user's locale and zone.

**So date APIs take a time zone, not a calendar.** Fourteen of them used to
accept a `Calendar` and open by rebuilding it as Gregorian from the incoming
one's time zone — correct, but a signature that asked for something it then
threw away, so a caller passing a Hebrew or Buddhist calendar was silently
overridden with nothing saying so. The zone was the only part ever honored.
Private helpers that do the arithmetic and the locale-aware formatting still
take the resolved `Calendar`, because that is what they genuinely need.

**Both task screens run one `TaskActions`.** The Tasks tab and a list's detail
view show different sections of different tasks, but a checkbox means the same
thing in both, so check-off, swipe-to-delete, the in-flight row set, and the
names those actions take in the Edit menu live in one `@Observable` model
rather than being written out twice. They *were* written out twice, and they
had already drifted: the same gesture registered its Undo as "Toggle Task" on
one screen and "Toggle Checkbox" on the other. `TaskRows` renders any run of
rows against it, and `CompletedTasksHeader` is the one Done/Completed header,
so the two screens differ in wording alone — "To Do"/"Done" against the due
groups and "Completed" — and not in what a tap does. `clearCompleted` takes
the sweep as a closure, because *which* tasks a screen clears is the one thing
the two genuinely disagree about, and registers the returned deletion records
as one Undo group.

**A row's tap opens the task, not the file it lives in.** Pushing the editor
with the caret on the line is the right escape hatch and it was the wrong
default: it made rescheduling something the one action on these screens that
meant hand-editing a `@due(...)` tag while everything else was a gesture.
`TaskEditSheet` is what a tap opens; **Open in Note** is in the sheet, in the
row's context menu, and on a leading swipe. The two sheets share
`TaskScheduleFields` and `TaskNotificationNote`, so a repeat option offered on
one is offered on the other — the same reason `TaskRow` and `TaskActions` are
shared by the two screens.

**Which means the task screens need explicit navigation paths.** A sheet and a
swipe action cannot carry a `NavigationLink`, so `TaskActions` records the
push as `pendingNoteDestination` and the screen owning the stack consumes it:
`TasksView` keeps a `[NoteDestination]`, and `ListsView` keeps a type-erased
`NavigationPath` it hands into `TaskListDetailView`, which sits one level
inside it and cannot reach the stack any other way. `coveTaskScreen(_:openNote:)`
is the one modifier carrying the sheet, that hand-off, and the Undo bar, for
the same reason `TaskRows` is one view.

**The Undo bar carries the reversal itself rather than calling
`UndoManager.undo()`.** Outside a `DocumentGroup`, SwiftUI's `\.undoManager`
is **nil on iOS** — which was found by building the bar against it and
watching the button do nothing — so a bar that only drove the manager would
have been dead on the one platform it exists for. It prefers the manager when
there is one, so a Mac keeps a single stack and the Edit menu stays in step.

**Which is why the bar is `CoveUndoCenter` rather than a part of
`TaskActions`, and why registering goes through one call.** It started as task
state, so only the two actions on those screens got it — and *every other*
destructive action in the app registered its reversal with the nil manager
alone. Four confirmation dialogs said "you can undo the deletion" over changes
a phone had no route back from: deleting a list, deleting a list from its own
detail view, deleting a subscription, and deleting a subscription category.
None of those moves a file — they rewrite a `##` section or a line — so
nothing reaches `.cove-recovery` either, and the Undo *is* the recovery. A
list deletion on iPhone therefore destroyed its tasks permanently while the
dialog promised otherwise. `CoveUndoCenter.register(named:announcing:
withTarget:undoManager:reverse:)` does both halves in one call, so a
manager-only registration is not something a call site can express any more.

**A screen that dismisses itself has to announce on its parent's center.**
Deleting a list from `TaskListDetailView` pops back to the overview, so a
notice raised on that view's own `TaskActions` would be torn down with the
view and never seen. `ListsView` owns the center and hands it down.

**And the bar goes at the top, which is not where a toast goes.** iOS 26's tab
bar floats *over* scrolling content and contributes no safe-area inset, so a
bar placed against the bottom edge came out underneath it — a sliver of card
behind the tab labels, which is exactly the failure the storage banner had one
level up and in the opposite direction. Under the navigation bar it is
unobstructed, it stacks predictably with the storage banner that already
reports from up there, and it needs no guess at how tall the platform's chrome
is this year.

**A task row omits its source note** — tasks nearly all live in the capture
note, so the caption repeated "Tasks" under every row. It does name its
*list*, which is the opposite call for the opposite reason: a dated list item
on the Tasks screen sits among unlisted rows, so without the label nothing
distinguishes it from a task in no list at all.

Display logic is pure and tested against a fixed `now` (`TaskPresentation`).
Grouping into Overdue/Today/Tomorrow/Upcoming only *partitions* the sorted
list, leaving the spec's ordering untouched. Upcoming is the one *group* that
folds away (`TaskGroup.isCollapsible`): it is unbounded — a year of dated
tasks all land in it — so it is the one a reader may want out of the way. It
still arrives open, because what is further out is work that is coming. The
completed section folds the same way and is the one that arrives closed,
being finished by definition. Both keep their count in the header while
closed, so a section still says how much is behind it. A minute tick keeps those groups
true across a due moment or midnight, and the tab refreshes on appearance
because editor autosaves don't trigger a rescan.

### Subscriptions

**A subscription is a task line's shape without being a task**, so it reuses
the machinery and none of the meaning. `SubscriptionParser` is built on
`MarkdownContextScanner`, so front matter, fences, and HTML comments are
excluded for free and identically; `##` categories go through
`TaskListDocument.headingName`, so the tracker and Lists cannot disagree about
where a section starts and ends; and mutations re-find their line semantically
and **refuse on ambiguity**, which is the same call `TaskParser` makes for the
same reason. `TaskListDocument` is deliberately reused rather than copied: it
deals in headings and lines, and is task-specific in name only.

**The two grammars cannot see each other, and that is tested rather than
assumed.** A subscription line has no `[ ]` after its bullet, so
`TaskParser`'s checkbox-candidate regex never treats it as a candidate and it
produces no task diagnostic; a task line has no `@cost(`, so the subscription
candidate detector ignores it. Both directions are covered in
`VaultIndexSubscriptionTests`, because the failure mode is silent — a note of
subscriptions quietly generating a wall of task warnings, or the reverse.

**Status is outside the identity, so the edit sheet checks it by hand.** It is
excluded for the reason completion is — "set this to paused" has to find a
line already paused — and that leaves it the one field a whole-line rewrite
can silently revert, since every other field failing to match aborts the write
on its own. A sheet opened before another device cancelled a charge would
reactivate it on save. `updateSubscription` therefore reads the matched line's
status inside the coordinated transform and refuses
(`MutationError.statusChangedOnDisk`) unless it is the status the sheet opened
from *or* the one being written — the second case being the idempotent replay
the exclusion exists for, which is what keeps `setSubscriptionStatus` working
against a line another caller already moved.

**`@since` is the anchor, and nothing rolls forward.** The obvious design
stores the *next* charge and advances it as time passes, which is what tasks
do — and it is exactly what forced `@anchor(...)` into the task grammar,
because an anchor that moves walks "every month on the 31st" back off February
and strands a Feb-29 yearly charge on the 28th forever. Storing the *first*
charge instead makes the next one derived:
`RecurrenceRule.nextDueDateString(after:anchoredTo:)` already computes it
correctly, **the file is never rewritten by the passage of time**, and "how
long have I been paying for this" is answerable for free.

**`BillingCycle` wraps `RecurrenceRule` to narrow it.** The interval clamping,
the occurrence search, and the month-end and leap-day handling are all there
and all tested. What the wrapper adds is a refusal — `init?(rule:)` returns nil
for a weekday set, which is a fine task recurrence and not a billing cycle —
plus `@every(...)` wording, since `RecurrenceRule.tagText` is worded for
`@repeat` and would produce `@every(monthly)`, "every monthly". It also reads
bare unit forms (`month`, `3 months`, `1 month`) that `RecurrenceRule` has no
grammar for at all.

**The Trackers hub carries no overview panel, and the subscriptions screen
does.** The hub shipped with one — tracked count, spend per month, spend per
year — and every figure in it was a *subscription* figure sitting on a screen
that is meant to be about trackers in general. A second tracker would have had
to either go missing from that panel or force it to special-case each kind,
and a weight or reading tracker has no monthly dollar total to contribute at
all. It also restated the row directly beneath it, which is the exact fault
that cost `CoveMasthead` its place everywhere else. A tracker's numbers belong
inside that tracker; the hub says which trackers exist and each row carries
its own summary. The **Lists** overview is not the same case and keeps its
panel: every list is the same kind of thing, so summing them means something.

**There is one chart, and it is single-hue ember bars rather than a pie.** The
palette allows one accent, moss for containers, and rust for lateness —
nothing else gets a colour, and the deliberate absence is a second bright hue.
A pie needs one hue per slice, so at eight subscriptions it needs eight, which
would mean inventing exactly the categorical ramp this system does without. A
bar chart ranked by value says what a pie says and says it better: length is
the encoding people read accurately and slice angle is the one they read
worst. Depth comes from opacity against each bar's own share, which is the
same single-hue trick `coveTintedSurface` uses everywhere else.

**A twelve-month projection chart shipped beside it and was removed.** It
bucketed the coming year's charges by month, and it was genuinely the more
*informative* of the two — a flat monthly average cannot show that a yearly
renewal lands entirely in one month. It went because it answers a different
question from the one this screen is for: what a *month* will cost, rather
than what a *subscription* costs. `SubscriptionMath.monthlyProjection`,
`MonthBucket`, and `categoryTotals` went with it rather than being left as
unreferenced code with tests keeping them alive.

**The breakdown is by subscription, not by category.** A category breakdown
says nothing at all for a vault that never used categories, and the list
directly under the chart *already* groups by category — so a chart repeating
that grouping would be the second time the screen said it. "What is costing me
the most" has an answer either way. Past the eighth bar the tail is **pooled
into a remainder rather than dropped**, because the bars sit under a total and
a dropped tail would make them visibly fail to add up to it.

**A chart with nothing to say is not drawn.** One bar is not a comparison, so
the chart appears only with two or more — the same call as the widget's count
badge disappearing at zero.

**Axis amounts carry no fraction digits and are not compact-formatted.**
`.notation(.compactName)` — the "$1.5K" form — is macOS 15 and up, and Cove's
floor is macOS 14. Whole units in the reader's locale work on every supported
target and are short enough at four axis marks anyway.

**Tracker notes live in `Trackers/` at the vault root, not beside `Tasks.md`
in it.** There will be more than one tracker, and a vault root accumulating a
note per tracker is a root that stops being about the user's own notes. It is
still a *fixed* path — one location, nothing to configure, no ambiguity about
which file is meant — so it keeps everything the root-only rule had and only
changes where the rule points. The folder is created on demand with the first
charge, since `updateNote(named:in:)` creates the file but not the directory
holding it.

The folder name is matched **case-insensitively**, like the file name already
was: a path-string comparison is case-sensitive and APFS is not, so
`trackers/` and `Trackers/` are one folder on disk and have to read as one
here.

**A `Subscriptions.md` at the vault root gets named in the empty state.** It
is an ordinary note as far as the index is concerned, and that is correct —
but the root is where the note used to live and where a person would put it by
hand, so an empty tracker sitting beside a file full of charges is the one
wrong-place case worth explaining rather than leaving silent. No other folder
gets that treatment; this is a signpost, not a search.

**Category management is `TaskListDocument`'s section surgery, unchanged.**
Create, rename, and delete all route through the same primitives the Lists
feature uses, so the tracker inherits their fail-closed behaviour: a rename
into an existing name is refused, a duplicate heading makes an edit ambiguous
rather than guessing, and Undo restores the exact removed section and refuses
if the name has been reused. `SubscriptionCategoryTests` covers what those
primitives do to *subscription* lines specifically — a rename that dropped a
charge would still leave a valid Markdown file, so nothing else would notice.

**Deleting a category takes its charges with it, as deleting a list takes its
tasks.** The alternative — remove the heading and relocate every line into the
unlisted region — was rejected: it silently rewrites lines the user did not
ask to touch, and its Undo cannot put them back where they were. Emptying a
category first is the explicit path (each charge's sheet has a Category
field), and the confirmation dialog names the count and says so.

**An empty category is still a category, so it is still on screen.** The
grouping is built from the note's headings rather than from the charges under
them, the same way `VaultIndex.lists` is — otherwise a category created and
not yet filled would be invisible, which also means unrenameable and
undeletable.

**The diagnostic path is wired end to end or it is not worth having.** The
parser's rejections reach `NoteIndexEntry.subscriptionDiagnostics`,
`CoveStorageHealth.subscriptionDiagnosticCount`, the attention banner, and a
Settings disclosure that opens the editor at the line. A count with nowhere to
tap is worse than no count.

**Money is `Decimal`, and the file format is not the display.** A binary float
cannot hold 15.49, and a total built from a dozen of them drifts by cents on a
screen whose only job is adding money up. `@cost(...)` renders through a POSIX
locale at exactly two fraction digits so it round-trips byte for byte;
presentation formats with the reader's own locale and currency style — the same
split a stored `YYYY-MM-DD` already makes.

**The index types were split so the widget doesn't compile any of this.**
`VaultIndex.swift` was in the extension's shared-sources list, so putting
subscriptions on `NoteIndexEntry` would have dragged the whole subscription
model into a target that has no use for it. `TaskCalendar`, `TaskIdentity`, and
`TaskItem` moved to `TaskItem.swift`, which is now what the widget shares;
`NoteIndexEntry`, `TaskList`, and `VaultIndex` stayed behind in
`VaultIndex.swift`, which only the app builds. `byDueDate` moved with them onto
`TaskItem`, where it belonged anyway — it compares two tasks and nothing else,
and the widget sorts with it while compiling none of the index types. The
shared file is now named for what it shares, which it was not before.

### Quick capture

`QuickTaskParser` is a Swift port of grove-app's capture parser
(`grove-app/src/lib/parser/parse.ts`), matching its grammar and resolution
rules; its test suite ports grove's `parse.test.ts`. Each extractor claims the
span it consumed (overlaps lose), and the title is what's left.
The pinned source revision and its MIT notice are in `ATTRIBUTION.md`; Grove
is a separate project by the same author, not a Cove runtime dependency.

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

**Capture registers Undo, and its record is read back out of the parser.**
It was the one mutating task action without one: return put a line in the note
with nothing but the preview between a mis-parsed sentence and the file, while
a checkbox, a swipe, a bulk clear, and a list deletion were all undoable.
`captureTask` returns a `CapturedTaskRecord` whose identity comes from parsing
the line Cove just generated — the round trip every generated line already
makes — so Undo can only target a line the parser agrees exists, and it
removes it through `TaskParser.removingTaskResult`, which re-finds it
semantically and refuses on ambiguity exactly as a swipe-delete does. A list
item is parsed under a synthetic `##` heading, because the list is part of
what re-finds the line and a record without it would miss the very line the
capture wrote. It goes through `TaskActions` like the rest, so the two capture
screens cannot word or handle it differently.

Competing time or recurrence expressions are blocking rather than guesses:
the first interpretation stays in the editable fields and later tokens remain
visible in the title. A date/time pair is resolved in the selected time zone
both during parsing and at the final storage boundary, so a nonexistent
spring-forward wall time cannot slip through after opening the details sheet.

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
render no due line at all, and can't be scheduled a notification.

**Whether a list item reaches the Tasks screen is the date, not the
heading** (`TaskItem.belongsOnTasksScreen`). A dated list item is scheduled
work that happens to be filed somewhere — a Thursday laundry run and a weekly
recurring chore are the same kind of thing as any other dated task, and
hiding them one tab away meant the screen that answers "what is due" was
answering it incompletely. Notifications had already made this call: the
planner runs off `allTasks`, so a timed list item has always fired a
reminder for a task the Tasks screen refused to show. An undated item has no
day to be grouped under, so the groceries case is untouched — which is the
whole distinction the Lists feature was for.

The row that results names its list (`CoveListLabel`, beside the due date),
which is the one exception to a task row saying nothing about where its line
lives: among unlisted rows a list item would otherwise be indistinguishable
from a task in no list at all. Inside a list's own detail view the label is
off, since the navigation title already says it.

**Lists build from the note's headings, not from its tasks**, so a list
created but not yet filled still exists.

**Each screen clears exactly what it shows.** The Tasks screen's Clear All
sweeps `index.completedTasks`, so it follows that section's own membership:
completed *dated* list items go with it, and an undated one — which the
screen never showed — is left to its list's own Clear All, which touches only
that heading's items. This is the one place the rule reversed when dated list
items joined the screen: the sweep is defined by what was on screen, not by
whether a line sits under a heading.

Clear All and list deletion both register semantic Undo. A deleted list keeps
its exact source section plus neighboring list anchors; restoration inserts
that section into the latest `Tasks.md` and fails closed if the name has been
reused.

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

`RootView` keeps a five-section tab bar on iPhone and the same destinations in
a branded `NavigationSplitView` sidebar on macOS and on a regular-width iPad,
sharing one selection model so no behavior diverges. Five is the ceiling: iOS
collapses a sixth tab into "More", so a later section has to displace one
rather than join them.

**iPad takes the Mac's sidebar rather than a layout of its own.** Five tab
labels stretched across a 13-inch window, with the sections they name
reachable only at the bottom of it, is a phone layout on a desk-sized canvas —
and the sidebar is the same five destinations arranged the way a regular-width
canvas wants them. The gate is the idiom **and** the size class: a Max-sized
iPhone reports regular width in landscape, and swapping its tab bar for a
sidebar on rotation would be a different app in each orientation. The one
divergence the shared view needs is `.listStyle(.sidebar)` on iOS, where a
plain `List` in a split view is still an inset-grouped table, and an optional
selection binding, which is the only form `List(_:selection:)` offers there —
clearing it is ignored, since the detail column has to be showing something.

**The manual rescan is a gesture on iOS and a button on macOS.** It was a
toolbar item on all four list screens, which on iOS 26 is a floating control
beside the navigation title — prominence an action that is automatic almost
all of the time does not earn, given the index rebuilds on launch, after every
change Cove makes, on iCloud's own change events, and on scene activation.
`coveRefreshable(_:)` is `.refreshable` plus a hidden ⌘R button on iOS and the
`CoveRefreshButton` toolbar item on macOS, where there is no pull gesture and
a toolbar is not scarce.

**Every editor push carries a `NoteDestination`, not a `URL`.** A search hit
knows the line it matched, a task row knows its own line, and a format warning
prints the line it is about — and all three used to open the top of the file
and leave the reader to find it, which made the Settings link a promise the
code did not keep. The value is note-plus-optional-line and its `Hashable`
conformance includes the line, so the same note at two lines is two distinct
navigation values rather than one the stack treats as already shown.

**The browser's path element had to change type for that, not gain a
sibling.** `NavigationStack(path:)` is typed and silently ignores any other
value, which is exactly how note rows were once dead — so `folderPath` is
`[NoteDestination]` and a folder is simply a destination with no line. The
screens with implicit paths (Tasks, Lists, Trackers) only had to swap which
type they register.

**The editor applies the line after the load, and once.** There is no text to
count lines in until the file is read, and the text view does not exist
outside the `.loaded` state; the binding is then cleared by the representable
so a later redraw cannot yank the reader back after they have scrolled away.
`MarkdownParser.range(ofLine:in:)` is the one line-to-range conversion, and it
counts lines the way `MarkdownContextScanner` does — a caret that landed one
line off from what a diagnostic said would be worse than not moving it.

**The attention banner is stacked above the navigation, not inset into it.**
As a `.safeAreaInset(edge: .top)` on the `TabView` it was laid out *over* each
tab's navigation bar — and because the banner is itself a full-width button,
it won the hit test, so while any warning was showing the toolbar's + and
refresh could not be pressed on any screen. The large title cleared it and the
toolbar row did not, which is why it read as a cosmetic overlap rather than a
dead control. A `VStack` gives the banner its own height and hands the rest to
the tabs, which is the one arrangement that cannot overlap. It was found by
driving the simulator, not by a build or a test, and nothing automated would
have caught it.

**⌘1–⌘5 are hidden buttons rather than a `.commands` block.** The selection
lives in `RootView`, and a command group would have to reach it through a
second piece of shared state existing only to carry it. ⌘L focuses quick
capture, and only the Tasks screen claims it: on iOS every tab stays alive, so
a list's field carrying the same key would put two claims on it and let the
system pick.

**Tasks is the landing section, and it leads the bar.** It is the one screen
that is about *right now*, and it is where the Today widget's `cove://tasks`
deep link already went — leaving the default on Notes meant a launch from the
Home Screen and a launch from the app icon arrived at different places.
`AppSection`'s declaration order *is* the order of the tab bar and the
sidebar, so opening on Tasks while Notes still held the first slot left the
landing screen under the second target and the first one unvisited. Tasks
first, then Notes, then Lists, then Settings: what's due now, the structure
it lives in, the groupings beside it, and configuration last.

**The browser shows one folder level at a time, bound directly to
`NavigationStack(path:)`.** A folder row is a real push, so the system back
button, its parent-folder title, and iOS swipe-back all work — the earlier
in-place swap had none of those and needed a custom back button.

**Folders and notes must share one path value type.** A typed `[URL]` path
silently ignores a `NavigationLink` carrying anything else, which is exactly
how note rows and search results were once dead. Because notes sit on the path
too, stale-path pruning looks up files as well as folders, so an open editor
survives rescans and pops only when its file really is gone.

**Nothing in the app addresses the reader.** A `Greeting` type owned the
vault root's headline — seven stretches of the day, phrases in a named and a
plain form, seeded so the minute tick couldn't reshuffle them mid-read — and a
Settings field fed it a name. It was the one thing on the browser that changed
while saying nothing about the folder being looked at, and it went with the
mastheads; the type, its tests, and the name setting went with it. A vault
that carried a name in `UserDefaults` simply stops reading it.

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
reads once — screen titles, headings inside a note, empty states, the brand
mark — are set
in the system serif; data, labels, and anything scanned stay in the system
sans. It scales with Dynamic Type and needs no font asset. Every count is
monospaced, so a badge doesn't resize as its number changes.

**Tracked capitals name a region of the screen and nothing else.**
`coveEyebrow` is for a section header, a panel's own label, and the sidebar's
tagline; `coveMetaLabel` — plain caption, secondary, the reader's own sentence
case — is for everything *under* one of those: a stat's name, a row's caption,
a unit suffix. The style used to carry both, which put QUICK CAPTURE, OVERDUE,
COLLECTIONS, LISTS, OPEN, DONE and 2 ITEMS in one voice on one screen, and a
style that marks everything marks nothing. `CoveRowTitle`'s caption lost its
`captionIsLabel` split in the process: the distinction between a data caption
and a path was real, and it was still one voice too many under a header set in
the same capitals.

A chart axis is the one place worth naming separately: `$40` is a number, not
a heading, so uppercasing it did nothing but put it in the headers' voice.

**`NavigationBarAppearance` is the one UIKit appearance-proxy call in the
app.** SwiftUI has no modifier for a `navigationTitle`'s font, and that title
is the largest text on every screen — and now that the headers under it are
label lines rather than serif titles, it is the whole of the serif voice on a
list screen. Left as the system's bold sans it was the one part of the app
still reading as a default. Touching `standardAppearance` replaces the whole
appearance object, so the transparent scroll-edge bar has to be restated or
every screen gains a material behind its title.

**`CovePanel` is the one screen header, and it is a label line.** Every main
screen used to open with a `CoveMasthead`: accent rule, eyebrow, serif title,
a sentence of prose, then the screen's own content. None of those titles said
anything the screen didn't. A slogan ("Write it, naturally", "Everything in
its place") is read once and paid for on every launch; a greeting is about the
reader rather than about the folder they came to look at; and the subtitles
under them repeated what a field's placeholder already said. Stacked over the
landing screen it pushed the first overdue task most of the way down the
display. The panel keeps the same card, the same ember rule, and the eyebrow,
adds an optional trailing count badge, and then gets out of the way — six
tasks fit above the fold where three did, and `CoveMasthead` is gone.

The panel's ornament sits *inline* with its label rather than stacked above
it: a compact card has no room for a rule on its own line.

**An eyebrow never repeats the navigation title above it**: at the vault root
it names the open vault, which nothing else on screen says; on a capture card
it names the card. There is no longer a case where it has to say "Overview"
because the bar is already naming the folder — that panel is gone (below).

**A panel is only drawn where summing means something.** The Lists panel
reported "1 list · 3 open · 1 done" directly above the only row, which said
"3 open · 1 done"; a pushed folder level's panel sat between a navigation bar
naming the folder and rows each carrying their own item count. In both cases
the card was the screen saying a third time what it had already said twice,
and that repetition is what makes every screen start to feel templated rather
than informative. So the Lists panel appears from two lists on, and the
browser's belongs to the vault root alone — the one level whose counts are
nowhere else on screen and whose eyebrow names something the bar does not.
This is the same call as "a chart with nothing to say is not drawn". It is
*not* a case against panels: the subscriptions overview stays unconditionally,
because a monthly and a yearly total are not derivable from any row.

**One continuous list surface for a screen whose groups are one list
partitioned.** An inset-grouped `Section` draws its own rounded card, so the
Tasks screen's Overdue, Today, Tomorrow, Upcoming, and Completed were five
soft capsules stacked inside iOS's own rounded chrome — card inside card — and
each gap between two of them cost roughly a task of what fits above the fold
on the screen the app opens on. They are one sorted list split five ways by a
single rule, so they take one section with the headings set inside it
(`coveGroupHeaderRow`), and a list's To Do and Done do the same. Quick Capture
stays a raised panel of its own, being a different kind of thing.

Where a screen's sections are *genuinely* different things — the subscriptions
chart, then the next thirty days, then the categories — separate sections are
still right, and that screen keeps them.

**Three numbers make that merge pay for itself, and the third is the one that
is easy to miss.** `CoveTheme.sectionSpacing` replaces the system's ~35pt gap
between sections app-wide (iOS only — `listSectionSpacing` is unavailable in
AppKit, and a macOS `.inset` list draws no per-section card for it to space).
`groupHeaderRowInsets` gives a heading room above and almost none below, since
it belongs to the rows under it. And `defaultMinListRowHeight` goes to 0,
because a list row is 44pt tall whatever is in it: a line of caption text was
getting 30pt of padding the row's own insets cannot take back, which handed
most of the saving straight back. Nothing else in the app shrinks — every
other row is past 44 from its own content plus the system's insets before the
floor is ever consulted.

`isLast` on a heading is for the folded case: a collapsed Done section is a
header with nothing beneath it, and with the rows gone there is nothing left
holding it off the card's bottom corner.

**A collapsible section's header is the control, because SwiftUI's own is
not.** `Section(isExpanded:)` exists and looks like the right answer, but
outside `.sidebar` list style on iOS it draws no disclosure control and takes
no taps — an inset-grouped section built with it starts collapsed and can
never be opened, which a build cannot catch and a screenshot of the collapsed
state looks entirely correct in. `CoveSectionHeader` takes an optional
`isExpanded` binding instead: the whole header — label, the space after it,
and a rotating chevron at the trailing edge — becomes one button, which grows
its target into the section gap and gives the growth back to the layout (the
same trick the task checkbox uses), so a collapsible header is exactly as
tall as an ordinary one. It works identically on macOS.

**A collapsible section carries no action in its header, which is what lets
that be one button.** Clear All lived there first, a caption-sized red text
button a few points from the chevron — two controls of very different
consequence sharing one corner, and the header had to be built as a *pair* of
buttons to keep them apart, since one button cannot span two regions with a
third between them. `ClearCompletedTasksRow` moved the sweep to the section's
last row: it takes the same grid as the rows above it, gets a full row's
target instead of a caption's, and is only reachable with the section open,
so what it would remove is on screen when it is pressed. Its tile takes the
role's own red rather than the palette's rust — destructive controls keeping
the system red is a decision this app already made, but a rust tile beside
role-red text puts that near-miss inside a single row, where it reads as a
mistake rather than as two components a screen apart.

Two sections fold: Upcoming (see `TaskGroup.isCollapsible`) and the completed
section on either task screen. Only the completed one arrives closed —
folding is offered on Upcoming because it is unbounded, but it is still work
that is coming, and a screen that hides it by default hides most of what a
reader came to check. `CompletedTasksHeader` takes the binding and
`ClearCompletedTasksRow` the sweep, so Completed on the Tasks tab and Done in
a list cannot fold or clear differently; those components exist precisely to
stop the two from drifting. Expansion is session state in both cases: folding
Upcoming away lasts as long as the app runs, and a launch opens on what is
due rather than on a pile of what's done.

`CoveSectionHeader` is the one list-section header, `CoveIconTile` the one
row glyph (decorative, so `accessibilityHidden` — the row carries the label —
and `@ScaledMetric`-sized), and `CoveCountBadge` the one shape for "how many".
**Section headers are text, never `Label`s.** Caption-size SF Symbols with
fine detail — a sunrise, a calendar grid — render as smudges, and a header
that already says "Tomorrow · 1" has nothing left for a glyph to add.

**`CoveRow` owns the grid every list is read against.** Rows used to be built
by hand at each call site, which produced three gaps between a tile and its
text, four vertical paddings, and — in Settings — `Label`-based rows whose
system-derived icon column sat several points left of the `HStack` rows
directly above them. Two tabs apart that goes unnoticed; three rows apart in
one `Form` it is the misalignment a reader sees without being able to name.
The component holds `Space.rowGlyph`, `Space.rowGap`, and `Space.rowPadding`
so a folder row, a
list row, and a settings row cannot disagree, and `CoveRowTitle` carries the
title-plus-caption pairing (tracked capitals when the caption is data, plain
secondary text when it is a path or a snippet). It also pins
`.listRowSeparatorLeading` to its text column: left alone SwiftUI infers that
inset from whichever nested label it selects, so a folder row with a caption
and a note row without one broke their separators at two different depths in
the same list.

**`TaskRow` is on that grid rather than beside it.** It was the last row type
setting its own `listRowInsets` — a tighter leading edge, a trailing edge 6pt
short of every other row's, vertical padding cut to 5pt, and a separator run
the full width of the row — which made a two-line task shorter than a
one-line folder row and put the landing screen's text column five points off
the tab beside it. It now takes the system's row insets like everything else,
lays its checkbox out in a `Space.rowGlyph` column so the text starts exactly
where an icon tile's does, and breaks its separator at that text column. The
checkbox keeps a genuine 44pt target by being framed at 44 and *then* laid
out in the 32pt column: the target overflows into the row's own padding
rather than widening the column and pushing this one row's text past every
other row's. `Space.rowGlyph` is the `@ScaledMetric` base at both call sites,
so the two columns grow together under Dynamic Type. For the same reason the
two task screens no longer ask for `.listSectionSpacing(.compact)` on their
own: a section gap that changes between tabs is the kind of difference that is
felt before it is seen. The gap *is* tighter than the system's now — but
through `CoveTheme.sectionSpacing` in `coveListStyle`, which every list in the
app takes, so it is still one number rather than a screen's private one.

**Tinted surfaces come from `Tint.fill`/`Tint.stroke`, applied through
`coveTintedSurface(_:in:)`.** A tile, a badge, an editor banner, and the
recovery emblem are all one idea — a wash of a hue under a hairline of the
same hue — and they had drifted to five hand-tuned pairs across 0.11–0.13
fills and 0.14–0.22 strokes. The modifier takes any `InsettableShape`, so the
caller keeps the shape it already had.

**A field is a well on paper and a lift at night, and `CoveTheme.field` owns
the flip.** The quick-capture field took `canvas`, which is right in light — a
well cut into the lighter `surface` reads as a place to put something — and
wrong in dark, where the canvas sits *below* the panel it is set into by four
points of luminance. An empty field and its placeholder all but vanished into
the card. Sinking it further had no room left; lifting it has all the room
there is, so in dark the field is lighter than the surface and the idea
survives with the direction reversed. `fieldStroke` is a step past `hairline`
for the same reason: a hairline separates two surfaces that already differ,
while the edge of an *empty* control is the only thing saying it is there.

`CoveThemeTests` pins the direction in each appearance rather than a single
ratio, because a token that quietly went back to sinking in dark would look
plausible in a screenshot and fail the one reader it was changed for.

**The example left the placeholder, then left the screen.** A placeholder is
one line that cannot wrap, so the sentence teaching the grammar — "e.g. Get
bread tomorrow at 3pm" — truncated to about three words at accessibility text
sizes, and the words it kept were the least useful ones. It moved under the
field as wrapping caption text, which fixed the truncation and then cost a
line of the landing screen on every launch to teach something a reader of a
personal app learns once. `QuickCaptureField`'s `hint` is gone with it: the
field says "Add a task…", which fits at any size, and the live preview under
it is what actually teaches the grammar — it answers "did it understand me?"
against the reader's own sentence rather than against an example of someone
else's.

**The capture placeholder is drawn, not handed to the field.** The system's is
a tertiary fill at about a third opacity, and it is the only instruction the
capture screen has now that the masthead's prose is gone. Set as ordinary
secondary text it reads at a glance and still sits clearly below what is typed
over it; the accessibility label the field loses by taking an empty title is
given straight back.

**A due date is a subtitle, not a capsule.** It used to be a tinted pill
carrying a clock or calendar glyph, and every part of that was wrong for a
line that says when something is due: a pill is a control's shape, so a list
with one under every title read as a list of buttons; the well's hard edge sat
a few points below the title and crowded it in a way a line of text does not;
and the glyph restated the date beside it. `CoveDueLabel` is what is left —
the wording, a step down in size and a step quieter — which is the shape Apple
Reminders uses for the same fact, and the reference this was measured against.

**Lateness is the only thing a due line raises its voice for.** Overdue takes
`CoveTheme.alert`; everything else, today included, stays secondary. Today
used to take the accent, and on the landing screen — where nearly everything
is due today or overdue — that meant almost every row carried a saturated
second line. A subtitle at the title's own strength stops reading as a
subtitle: the pair clumps into one block, and a list where every date is
coloured says nothing about which one to read first. It was also redundant
twice over, since a row reading "Today" sits under a header reading TODAY and
its checkbox is already ember. A completed task's line stays quiet for the
reason it always did — finishing something should settle a row, not light it
up — which is the same call the widget's muted checkboxes make.

**A subscription row follows that rule, and took two goes to.** Its forward
equivalent of lateness is a charge about to land, and the first version tinted
the whole summary — `$11.99 · monthly · Renews tomorrow` — for anything inside
seven days. Both halves of that were the fault above: the window is one every
monthly charge enters once a month, so a share of the list was accented at all
times for doing nothing unusual, and the tint covered a cost and a cycle that
are never urgent on behalf of a clause that sometimes is. `summaryParts` splits
the line so only the clause can be emphasised, and `isRenewingNow` narrows the
trigger to today and tomorrow. `isImminent`'s week survives where it is
actually a discriminator — inside **Next 30 Days**, a section already scoped to
a month. That section is also why the row's window had to shrink rather than
just its scope: it lists the imminent charges by name directly above, so a
tinted row was the screen saying the same thing a third time.

**A task title is regular where every other row title is medium, and that is
what separates it from its date.** The pair was tried at medium first, with
the gap opened up to compensate; it did not work, because distance was never
what was wrong. A medium 17pt title has enough ink that a caption under it
reads as attached to it no matter how far down it sits, so the two clump into
one block and the row stops having a hierarchy. Lightening the title is what
breaks them apart, and the gap then goes back to 4pt — Reminders' own
geometry, which the rows were measured against.

The divergence from `CoveRowTitle` is deliberate and it is about what the row
*is*, not about the grid: a folder or list row is a label with a tag under it,
where a task row is a sentence with a second line about it. The grid — the
glyph column, the gap after it, the row padding, the separator inset — is
still the shared one, which is the part that shows when rows sit together.
The two weights never appear in the same list anyway: the Lists overview is
`CoveRow`, and a list's tasks are one push below it.

**`CoveDueLabel` and `CoveRecurrenceLabel` are shared by the task row and the
capture preview.** The preview *becomes* the row it sits one keystroke above,
so two implementations could word or shade the same date two ways. They sit at
one size and one tint so the pair reads as a single line — a date and how
often it comes back — rather than as parts assembled.
`CoveRecurrenceLabel` takes the rule's wording rather than a `RecurrenceRule`,
which keeps the design system clear of the task model.

**`CoveMark` is drawn, not loaded, and it is geometry rather than type.** One
disc, cut once, in a 0…100 design space: a circle of radius 36 centred in the
tile, split by a vertical kerf 6 wide centred at x = 60. The larger piece is
ink and the smaller is ember, both on the centreline with no vertical offset,
so the mark is symmetric about the horizontal axis and needs no y-flip when it
is rasterized.

**Both pieces are the same circle clipped by the same two edges**, so the cut
cannot drift open or overlap the way two independently placed shapes would;
`CoveDiscPiece` takes only which side of the kerf it is.

Three marks preceded it. A serif `c` cupping an ember dot leaned right, because
a serif face is drawn with a diagonal stress and tapered terminals, so the
letter pulled one way and the dot beside it pulled further: geometrically
centred in the tile and visibly off balance. Two concentric arcs on one axis
fixed that — arcs have no stress — but a C and a ripple is a shape that has to
be explained. A coastline said what the app is and made the whole tile the
mark, and it is the one this replaces: its silhouette is a **horizon line**, so
below about 40pt the 4-unit shoreline goes sub-pixel and what survives reads as
texture rather than as a mark, which on a Home Screen is nothing at all. The
disc keeps what the coastline got right — the split is the subject — and puts
it in two filled shapes that differ in *value* rather than in outline. The mark
still inherits the appearance and scales to any size without a new export.

**The kerf is the smallest feature, at 6% of the tile**, which is about a point
at the 16pt Dock size. That is what removes the old mark's optical minimum: a
stroke thins toward nothing as the tile shrinks and needed a 1pt floor, while a
gap between two fills stays a gap. Nothing here is stroked, so nothing needs
widening at small sizes and the 16 and 32px Mac renders are the same drawing as
the 1024.

**Both pieces invert with appearance.** Warm paper ground under ink and ember
in light, night ground under paper and a lighter ember in dark — the dark
appearance's own `CoveTheme.accent` value, rather than the light one held
across both the way the shoreline was. The old mark held its ember fixed
because a stroke that changed value with the appearance would have read as two
marks; here the ember is one of two large fills and has to carry the same
contrast against night that it does against paper.

**The tile carries `CoveTheme.hairline`, and the app icon deliberately does
not.** The mark's ground is Cove's own canvas, so on a setup card, a loading
card, or the Mac sidebar the tile's ground vanishes into what it is drawn on
and the mark reads as two shapes floating on the page rather than as a tile.
`strokeBorder` inside the clip is what puts the edge back. An icon is masked by
the system and sits on a wallpaper rather than on Cove's canvas, so the PNGs in
`AppIcon.appiconset` and `DockIconDark` have no edge — and the `LaunchIcon`
PNGs no longer do either. They used to bake one in, because `LaunchBackground`
is *exactly* the light tile's paper and the coastline's ground half went
missing without it, taking the top two corners with it. The disc is centred and
closed, so on the launch screen it simply sits on the paper with no tile edge
around it, which is the same mark rather than a broken one.

**Tab and sidebar symbols are outline names.** The iOS tab bar substitutes
the filled variant itself, so the choice only shows through on the macOS
sidebar, where outline is the platform convention. **The bar itself carries no
background override.** `toolbarBackground(_:for: .tabBar)` replaces whatever
the running system draws there, which on iOS 26 meant a flat pill in place of
the platform's own bar with rows showing through it unblurred — a tab bar is
the one piece of chrome every app on the device shares, so it is left alone.
The visual system is standard SwiftUI throughout — no assets beyond
`LaunchIcon`, no dependencies, no persistence changes.

**`covePresence()` is the one optional-to-`Bool` presentation binding.**
Alerts, dialogs, and sheets are driven by optional state — the item being
renamed, deleted, or reported — and the getter/setter pair that turns it into
an `isPresented:` had three implementations, one of them a private copy in the
browser sitting beside a hand-built "Something Went Wrong" alert that
`coveErrorAlert` already produced character for character. `Wrapped: Sendable`
on the extension is what keeps the returned binding's `@Sendable` accessors
clean under strict concurrency; every optional it drives is a value type
already, which is why `NamePrompt` carries the conformance.

`SettingsView` has no About section: the app's identity and version are
visible from the system. `AppearanceSetting` is applied by `RootView` around
*every* vault state, so the preference also covers the welcome and recovery
screens; an unrecognized stored value falls back to `system`.

### Icon and launch screen

The asset catalog carries generated `CoveMark` artwork — the cut disc the
interface draws. The set is a full-bleed 1024 iOS icon plus dark and tinted
variants, icon-grid rounded rects for every mac size, and a `LaunchIcon`
imageset used by the iOS launch screen. The launch tiles are the in-app mark,
so they swap with the appearance — warm paper in light, night in dark.

**The icon and the in-app mark are one shape.** The catalog art and the live
`CoveMark` are the same disc and the same kerf, so the springboard icon, the
launch screen, and the loading/setup mark all agree. The coastal wordmark and
the coastline that replaced it are both retired.

**The app icon keeps an ink ground in both appearances, and the in-app mark
does not.** `#24211D` in light and `#161513` in dark are both dark tiles: an
icon sits on someone's wallpaper rather than on Cove's canvas, and a dark tile
is the one that holds its edge against any of them, so the icon has no light
arrangement to offer. The in-app mark still follows the app's appearance,
because there its ground *is* the canvas.

**Which is why the icon's palette forks from the app's, deliberately.** The
icon's ember is `#D9812F` against the app's `#9E5827` accent, and its paper is
`#F2EEE7` against the mark's `#EDE6DA` — ember has room to sit lighter on ink
than it does on paper, and Home Screen size needs the extra separation. An
earlier version of this file claimed every value in the artwork was a
`CoveTheme` literal; that was true of the coastline and is not true here. The
widget's deeper accent is the other such divergence, documented where
`WidgetPalette` is.

**The tinted iOS variant is a real render, not a derived one.** iOS builds a
tinted icon from the luminance of whatever it is given, so without an entry it
would flatten the tile into mush. The supplied render is the same arrangement
in greys (`#000000` ground, `#FFFFFF` major piece, `#9E9E9E` minor), which
keeps the cut legible under the system's tint.

**The Mac's dark icon is applied at runtime, because the catalog has nowhere
to put it.** `luminosity` appearances on an `appiconset` are honoured for the
`universal`/iOS idiom only; `actool` parses `mac` idiom entries that carry one,
assigns them to nothing, and reports "the app icon set has N unassigned
children" — a *warning*, so a catalog that looks complete in Xcode's inspector
ships the light tile to both appearances anyway. This was checked rather than
assumed: `platform: macos` is not a recognised value at all, `platform: osx` is
recognised and still unassigned, and the result does not change at a 15.0 or
26.0 deployment target.

So `DockIcon` (`Cove/Platform/macOS/`) drives the icon at runtime instead, from
a plain `DockIconDark` imageset holding the dark tile at 512 and 1024. Light
sets everything back to `nil`, which hands the Dock back to the bundle's own
icon rather than installing a second copy of the light artwork — so the catalog
stays the single home of the light tile.

**What a bundle-level dark icon would actually cost, since the runtime one
cannot follow a *quit* app.** Apple's own apps change while closed because they
do not use an `appiconset` at all: Notes.app's compiled catalog carries
`AppIcon` keyed by `NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua`, and
`ISAppearanceTintable`, plus layered `AppIcon_Assets/*` groups. That is macOS
26's `.icon` (Icon Composer) format, and the variants live in the bundle, so
the system swaps them with nothing running.

It is not the deployment target that stops Cove adopting it — an earlier
version of this file claimed a macOS 26 floor, and that is wrong. A
hand-authored `icon.json` compiles through `actool` cleanly at Cove's **macOS
14** target, emitting Notes' rendition structure plus an `.icns` fallback. Two
other things stop it, and they are the ones to weigh if this is revisited:

* **macOS 26 renders `.icon` files with its own material treatment**, and it is
  not optional — it is why native icons follow appearance at all. Cove's flat
  land comes out as a glossy gradient and the ember shoreline picks up a
  metallic sheen, against a direction whose whole premise is flat shapes at
  one weight.
* **The light/dark colour schema is undocumented and fails silently.** `actool`
  accepts an invented `"totally-bogus-key"` without a word, and `dark-color`,
  `light-color`/`dark-color`, and `fill-specializations` each left the dark
  rendition byte-identical to a baseline with no dark colour at all. A
  baseline `.icon` *does* still get a distinct dark rendition — the system
  derives one — so the format works; it is Cove's specific night-black ground
  that could not be expressed. Nor can the result be checked here:
  `NSWorkspace.icon(forFile:)` resolves once, and returns identical pixels for
  Notes under both appearances.

The flat direction was kept and the quit-app gap accepted. Reversing that means
authoring the `.icon` in Icon Composer, where the colours are set in a UI
rather than guessed at.

**Setting `applicationIconImage` is not enough on its own, and the way it fails
is silent.** It is the app's *icon* — what the app switcher and the window menu
read — while the Dock draws a *tile* that caches what it last drew. Assigning
the property and stopping there leaves the property visibly correct from inside
the process (it reads back as the 512pt dark tile) while the Dock goes on
showing the light one, so nothing in the app can detect the failure. `DockIcon`
therefore also sets `dockTile.contentView` to an `NSImageView` of the same
image and calls `dockTile.display()`. This was found the way it had to be
found — by shipping the property-only version, having it look right in every
check available here, and being told the Dock had not changed.

**The Dock icon follows SwiftUI's `colorScheme`, not the stored setting.**
`coveDockIcon()` is applied *before* `preferredColorScheme` in `RootView`'s
modifier chain, so it sits below that setting in the view tree and reads the
scheme the setting actually resolved to. Passing the `AppearanceSetting` in
instead would mean re-deriving what `.system` means and observing the desktop's
appearance by hand, and the two answers could then disagree.

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

**How many rows are drawn is measured, not declared.** The families took a
literal `prefix(2)` and `prefix(3)`, and a small widget is 148pt tall on one
iPhone and 170pt on another — so the count was wrong on both ends: it clipped
nothing only because it withheld a row the tile had room for, and three tasks
due today showed as two above a third of blank tile. `ViewThatFits(in:
.vertical)` is handed four candidates, longest first, and takes the tallest
that fits under the header. The candidates are spelled out rather than
generated, because `ViewThatFits` reads its content as a list of alternatives
and a `ForEach` inside it is *one* child, not four. What the space actually
holds today is three rows on every current iPhone; the point is that it is the
space that decides, so an accessibility text size drops a row rather than
squashing three.

**The checkbox's target is exactly a row tall and wider than its column.**
Vertical overflow is the one direction that must not happen — a hit region
reaching into the next row would dispatch a neighbouring App Intent — so the
button's height is `rowHeight` and its extra width falls into the widget's own
padding on one side and the gap before the title on the other. Laying it out
in a column as wide as the ring is what puts the ring's leading edge under the
date above it, rather than the 6pt inside it that a centred 32pt frame gave.

**Checkboxes are drawn in `checkboxRest`, a muted accent, not the full one.**
The boxes repeat down the widget while the count and the times appear once
each, so at full saturation the rings were the loudest thing on a surface
whose job is to be glanced at. A completed row fills the same soft tone, so
finishing something quiets the row rather than lighting it up.

**The due time is a subtitle and the count badge disappears at zero.** The
time carried a clock glyph, or an exclamation mark once it had passed, on
every row that had one — the same restatement the app removed from its own due
lines, and here it repeated down a surface meant to be glanced at. Lateness is
the tint, as it is in the app. The badge went for the same reason: a `0` beside
"All clear" is a shape that asks to be read and then says nothing.

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

**The toggle intent carries the row's semantic id and an explicit desired
completion state.** The id fingerprints path, line, text, schedule, recurrence,
and list context but deliberately excludes completion, so an old control
cannot apply to replacement content while replaying the same desired state
stays idempotent. Everything else is looked up in the snapshot the widget was
drawing.

**`SnapshotTask` carries the `##` section its line sits under.** The widget
shows the same rows the Tasks screen does, which now includes a list's dated
items, and a task's line is re-found by matching its text, its schedule, *and*
its list — so a toggle sent back with the list dropped would fail to match the
very line the widget drew. The field is additive: it is written and read with
`encodeIfPresent`/`decodeIfPresent`, so a snapshot from a build that predates
it decodes as unlisted, which is exactly what those snapshots held. No schema
bump, because bumping would make the *older* build reject the file.

**A recorded path is validated against the vault, never trusted.** A
`TaskIdentity` is persisted state that crosses the App Group and can outlive
the vault it was written for — a queued toggle survives the user picking a
different folder. Both the extension and the app's drain resolve the path
against the vault they just opened (`fileURL(within:)`), holding it to the
scanner's own rules — inside the vault, a Markdown file, nothing hidden or
packaged, aliased, or symlinked on the way in — and drop an operation that fails rather than
retrying it, since no retry can make it apply.

**Operations record desired state, not an instruction to toggle**, so
replaying one cannot undo a successful first attempt. Each is queued *before*
the write is attempted and acknowledged only after success, because whether an
extension can resolve a bookmark its host app created is not guaranteed on
iOS. The app drains the queue at the start of the next tree load, before the
scan, so the index is still built once. The snapshot updates optimistically
either way, which is what makes the tap feel instant.

Malformed current-version snapshots are preserved once as an unreadable
backup and rebuilt from authoritative app state. A future schema is never
overwritten by an older build.

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

# Lint, offline/log-privacy rules, the suite, and both platforms, in one pass
Scripts/verify-build.sh
```

Current verified suite: **591 tests** (macOS host), plus clean macOS and
generic iOS Simulator builds, all with zero warnings.

**Never pipe `xcodebuild` into `tail` or `grep` to read the result.** The
pipeline exits with the *last* command's status, so a failing build reports
success and the errors scroll past the window you kept. Redirect to a file
and check `$?`, then grep the file. Two "clean builds" in this project's
history were pipelines hiding a broken iOS target.

**A macOS build is not evidence the iOS build works.** The widget target only
compiles on iOS, and it compiles a *different* subset of `Cove/`, so a shared
file that gains a dependency the widget doesn't have breaks only there. Run
both before calling anything green.

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

```sh
swift Scripts/render-mark.swift   # from the repo root; overwrites all 18 PNGs
```

`Scripts/render-mark.swift` is the generator, and it is **kept** rather than
thrown away. The two before it were deleted after use, which left the drawn
`CoveMark` as the only geometry in version control and the PNGs as pixels with
nothing to check them against; a script that is 170 lines of CoreGraphics and
needs no font, no webfont, no headless browser, and no network is cheaper to
keep than to reconstruct. It writes every file at the exact path the existing
`Contents.json` files already name, so **no manifest edit is ever needed**.

It is not, however, the same drawing as `CoveMark` — it is CoreGraphics where
the view is SwiftUI, so the geometry is stated twice and the two can drift.
The mark is symmetric about the horizontal axis, which is the one thing that
keeps the drift from being silent in the obvious place: CoreGraphics' bottom-
left origin needs no compensation, so a y-flip cannot be got wrong. Everything
else — the radius, the kerf, the corner ratio — has to be changed in both.

Three shapes: full-bleed square for iOS (no baked corners — iOS masks it), a
rounded-rect body inset into the macOS icon grid at 824/1024 at *every* size,
corner radius 22.37% of the *tile*, and full-bleed rounded tiles (radius
`0.2237·S`) for `LaunchIcon`. Nothing carries a bevel, a drop shadow, or a
baked hairline; the grounds are flat. iOS carries light, dark, and tinted
renders, and the launch tiles carry light and dark (`.png` light, `-dark.png`
dark).

macOS is the exception: `AppIcon.appiconset` takes the light tile at every
size, and the dark one is a *separate* `DockIconDark` imageset at 512 (1x) and
1024 (2x), because the app icon set has no dark Mac slot and `DockIcon` loads
that image by name at runtime. The script writes both.

Verify with a macOS and an iOS build afterwards — `actool` reports icon
problems as build *warnings*, not errors, and "unassigned children" is how it
says a `Contents.json` entry it parsed is being used by nothing. Then eyeball
the renders at 32 and 16 px, where the kerf either stays a visible dark band
between the two pieces or closes up and leaves one disc.

---

## Known limitations

Rough edges and surprises, not restatements of the design above.

### Vault and files

* An open editor whose note is renamed, moved, or deleted still points at the
  old URL. The live text is no longer lost — it is journaled locally and the
  banner offers Save Copy — but the editor does not follow the file to its
  new name, and the copy lands at the vault root rather than where the note
  went.
* A new note is pushed onto whatever level the browser is currently showing,
  so one created into a *different* folder from a row's context menu leaves
  back-navigation pointing at the level you were on rather than at the folder
  it was created in.
* The recovery banner and Vault Safety only count drafts belonging to the open
  vault, and drafts are per-device — so a draft from another device, or from a
  folder that is no longer the vault, is invisible here and is only swept when
  its note is next opened clean.
* A dirty editor blocks switching vaults. Settings refuses with "Finish
  saving or export the open note's recovery copy" until the editor is clean
  or closed, which is surprising if the editor is on another tab and out of
  sight.
* Recovery drafts are per-device and never expire on their own. One is
  removed when its note is next opened clean, accepted, or discarded — a
  draft for a note that is deleted before it is reopened sits in Application
  Support indefinitely. Settings → Cove Recovery is the only place it is
  visible.
* A quarantined draft — one whose bytes could not be decoded — is kept but is
  reachable only by hand. It is named once, in the editor's message the time
  it is set aside, and after that nothing in the app lists it, counts it, or
  offers to export it; Settings → Cove Recovery shows readable drafts only. It
  is also never swept, since the sweep works on drafts it can read.
* The sweep runs once per vault open, so a session left running for weeks
  keeps accumulating; reopening clears the backlog. Entries predating the
  sweep carry no timestamp and go on the first launch that includes it,
  regardless of age.
* Stranded `.cove-write-*` temporaries are only swept at vault open and only
  once they are an hour old, so a crash mid-write leaves one visible to other
  Markdown tools until the next launch.
* Bookmarks are per-device, so each device runs folder selection once
  (expected — there is no custom sync).
* A tree scan holds one coordinated read for its whole duration. Fine for
  reads; all mutations use per-item coordination.

### Editor and styling

* Clicking anywhere in a `- [ ]` marker toggles it instead of placing the
  insertion point. Edit the marker by moving the caret in from outside.
* Header fonts are computed from the body font at restyle time, so an iOS
  Dynamic Type change updates header sizes on the next edit, not instantly.
* The save indicator comes and goes while typing — it appears on the first
  keystroke and leaves about a second after typing stops.
* While a recovered draft is showing, nothing is written to the note at all:
  typing keeps updating the local journal, the indicator reads "Held for
  Review", and only Save Recovered Edits or Discard Draft releases it. A user
  who ignores the banner and keeps working is editing a file that is not
  being saved.
* Discard Draft is confirmed, but the confirmation is the only guard: once
  taken it replaces the recovered text with what is on disk and the journal
  entry is gone. There is no undo past that point.

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
* A result opens at its *first* matching line, and there is no way to step
  through the rest. A title-only hit reads no content at all, so it has no
  line and opens the note at the top.
* On iOS 26 a pushed folder level collapses the `.searchable` field into the
  toolbar rather than showing it under the title. That's the system's behavior
  for pushed levels, not a Cove layout bug.

### Tasks

* Tasks kept outside `Tasks.md` are indistinguishable in the list until
  opened, since a row doesn't name its note. The details sheet names it, so it
  is one tap rather than none — but the list itself still doesn't say.
* The details sheet edits a task's title and schedule, and nothing else. It
  cannot move a task to another list or another note, and it cannot check it
  off — the checkbox on the row is what does that, and it carries recurrence
  semantics a toggle in a form would bypass.
* An edit is refused when the line changed elsewhere in the meantime, and the
  sheet does not reload itself or merge — the same trade the subscription
  sheet makes, and with the same cost: the typed values have to be re-entered
  after reopening it.
* The Undo bar shows only the most recent action and lasts six seconds. A
  second delete replaces the first notice, after which the earlier one is
  reachable through ⌘Z on a Mac and — since `\.undoManager` is nil on iOS —
  not at all on a phone. Leaving a list's detail view still drops that
  screen's own notices, since they belong to its `TaskActions`; the list
  *deletion* is the one action that survives the trip, because it announces on
  the overview's center instead.
* Capture, checkbox toggles, and task edits are undoable through the Edit menu
  and ⌘Z but raise no bar, so on iPhone they cannot be reversed from the UI at
  all. That is deliberate for the first two — a notice after every capture and
  every checkbox is the bar becoming furniture — and it is the reason the
  quick-capture preview is not optional chrome. An edit is the arguable one:
  it is reversible, infrequent, and currently silent on a phone.
* Pull-to-refresh is not advertised anywhere on iOS, which is the cost of
  taking the button out of the toolbar. It is the platform's own gesture on a
  list, and ⌘R still works with a keyboard, but a reader who never pulls down
  will not find it.
* Opening a task lands on the line the index last saw. An external edit that
  shifted the note since the last rebuild puts the caret on whatever now sits
  there, and a line number past the end of the file simply opens the top —
  the caret is a convenience, not a second re-find.
* Two task lines identical in text, schedule, recurrence, and list cannot be
  checked off, deleted, or undone from the Tasks screen at all — the mutation
  refuses rather than guess which line was meant, because after an external
  edit shifts the lines a remembered line number is not evidence. Both rows
  stay stuck until one is made distinct. Settings lists every duplicate under
  "task format warnings" with the note and line number, and tapping it opens
  the editor there; that is the only way out.
* An invalid line is no longer silent, but it is only reported in Settings.
  Nothing on the Tasks screen itself says a note contains a checkbox that
  didn't parse.
* Recurrence-aware completion lives only in the Tasks tab. Tapping the same
  line's checkbox in the editor flips it to `[x]` like any checkbox, and the
  Tasks tab then shows it completed rather than rolled forward.
* Tapping a checkbox whose line another device already put in that state does
  nothing but correct the row — no write, and no Undo entry. That is right,
  but it is also silent: the tap looks like it did something because the row
  changes, and the reason it changed is the rescan rather than the tap.
* The minute tick re-evaluates the whole list body. Cheap at typical counts; a
  very large list would want it narrowed to rows that can actually change.
* Neither section remembers how it was left. Folding Upcoming away lasts as
  long as the app is running, and the completed section reopens collapsed on
  every launch — which is the point for the second one, but it does mean
  Upcoming cannot be left folded.
* Clearing completed tasks means opening the section first — the sweep is its
  last row, not a control in its header. Deliberate, and it also means the
  rows being removed are on screen when it is pressed.

### Quick capture

* English-only. Tokens are consumed anywhere in the sentence, so "plan friday
  party tmr" is due tomorrow and titled "Plan party" — the losing date word
  still leaves the title.
* Hashtags stay in the title (no tag feature), and ISO dates ("2026-07-21")
  aren't in grove's grammar — use slash or month-name dates, or the picker.
* Capture writes on return with no confirmation. It is undoable now, but the
  live preview is still the only thing between a typo and the note *before*
  the write, which is why it isn't optional chrome — and Undo reaches only the
  most recent capture, so a mis-parsed task noticed three captures later is
  still a swipe-and-retype.
* A sentence Cove cannot write down is refused: an impossible date ("feb
  30"), a token that is not a time ("25:00"), a nonexistent daylight-saving
  wall time, or competing time/repeat expressions disables the add button.
  Bare past times, two competing dates, and clamped counts still resolve to a
  real task; the preview shows which one.
* A bare time stays on today even when that moment has passed: "standup 9a"
  typed at 10:00 lands today, already overdue, and gets no notification. It
  now says so under the field, but it still lands.
* Time ranges keep only the start; Cove has no calendar events.
* An empty title can't be captured, so a sentence that is nothing but a date
  leaves the add button disabled.
* Absurd counts are clamped: "in 99999 weeks" is read as the maximum relative
  count, and a repeat interval above `RecurrenceRule.maximumInterval` becomes
  that maximum. The preview shows the clamped date and a warning names it.
* A title whose spacing the writer has to normalize — a tab, a double space —
  is reported as unsafe and must be adjusted before it can be added from the
  details sheet. Quick capture rarely hits this, since the parser already
  collapses whitespace when it strips the tokens out of the sentence.
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
* Deleting a list deletes its tasks with it. It is confirmed by dialog and
  undoable, but Undo refuses if a new list has since reused the name.
* An undated list item can never gain a time or repeat rule, since both live
  inside or after the `@due` tag. The draft sheet's date toggle drops all three
  together, so turning the date back on starts from today with no time.
* An undated completed list item stays under its Done header until that
  list's own Clear All sweeps them. A dated one is also on the Tasks screen,
  so the Tasks screen's Clear All takes it out of the list — which is the
  point, but it does mean a sweep on one tab empties rows on another.
* A dated list item is reachable from two screens, so it can be deleted from
  the Tasks screen without ever opening the list it belongs to. The swipe is
  undoable, but nothing on that row warns that the line lives in a list
  beyond the list name under its title.
* An item captured into a list deleted meanwhile recreates the heading at the
  end of the note rather than failing.

### Subscriptions

* The chart is drawn in the **leading currency only** — nothing is converted,
  so bars from two currencies on one axis would be a comparison that isn't
  one. It no longer does that quietly: the header names the currency and a
  caption says so, both only when there is more than one. The Trackers hub row
  drops its monthly figure entirely in that case, since one line has no room
  for a total per currency.
* Nothing shows what a given *month* will cost. A yearly charge is spread
  evenly across twelve months in every figure on the screen, so the month its
  renewal actually lands in is not called out anywhere. That is a deliberate
  scope choice rather than an oversight — see the projection note in
  Architecture.
* **A price change is not history, deliberately.** The line holds one cost, so
  editing it rewrites the only record and every figure recomputes at the new
  price. Keeping history would need a second place to put it, and Cove was
  asked not to track it — so this is a decision, not an oversight. It is here
  because a reader will still be surprised the first time a raise rewrites
  last year's numbers.
* Deleting a category takes its charges with it. The dialog says how many and
  names the way out — set each charge's Category to None first — but there is
  no "delete the heading, keep the charges" action.
* Deleting a `##` heading by hand in the editor is a different thing from
  deleting the category in the tracker: the charges under it survive and fall
  into whichever category precedes them, or become uncategorized if there is
  none.
* Currencies are never converted, so a vault mixing them gets one set of
  totals per currency and no combined figure.
* Weekly and daily cycles normalize over a 365.25-day year, so their monthly
  figures are averages and will not match a bank statement to the cent.
  `totalsAreExact` is what a screen should ask before implying otherwise.
* Tag order is fixed in what Cove writes *and* in what it matches, so a
  hand-edited line with `@since` before `@every` is reported as malformed
  rather than understood. Unlike the widened bullet, spacing, and case rules,
  order was not worth a second regex.
* A subscription paused or cancelled elsewhere while its sheet was open cannot
  be saved: the edit is refused and the sheet's other changes have to be
  retyped after reopening it. Refusing is the point — the alternative reverted
  the status silently — but nothing merges the two edits, and the sheet does
  not reload itself.
* Two lines identical in name, cost, cycle, start date, and category cannot be
  edited or deleted — the mutation refuses rather than guess, exactly as with
  duplicate tasks. Settings lists them; making one distinct is the only way
  out.
* `Trackers/Subscriptions.md` is fixed and not configurable, and the note must
  be a file — if iCloud syncs a *folder* of that name, nothing is tracked. A
  `Subscriptions.md` anywhere else is an ordinary note; the tracker's empty
  state calls out the vault-root case by name, since that is where it used to
  live and where a person would put it by hand, but not any other folder.
* An amount needing more than two decimal places is refused rather than
  rounded, so a cost cannot silently change by a fraction of a cent on save.
* A charge whose cycle is shorter than the projection window is walked one
  occurrence at a time, capped at
  `SubscriptionMath.maximumProjectedOccurrences` (512). A daily charge over a
  projected year is ~365 of those, so the cap is not tight — but the walk is
  recomputed rather than memoized, and a screen redrawing it every frame would
  feel it.

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
* A widget checkbox's target is a row tall — well under the 44pt an app
  control gets. It no longer overlaps its neighbour, but it is a small thing
  to hit, and that is the cost of fitting three tasks on a tile.
* Three rows is what a small or medium tile holds, so a fourth task due today
  is only implied by the count in the corner. Nothing says "2 more"; the
  badge and the row count are what the reader has to reconcile.

### Visual system

* Serif navigation titles are iOS-only. `NavigationBarAppearance` has no
  AppKit counterpart, so on macOS the window title and sidebar labels stay in
  the system sans while the empty states and note headings under them are
  serif.
* Destructive buttons (`Clear All`, swipe-to-delete) keep the system red
  rather than `CoveTheme.alert`, so a swipe action's red fill sits a shade off
  the rust an overdue task uses. Deliberate — the role also carries VoiceOver
  and confirmation semantics that a tinted plain button would drop.
* ⌘1–⌘5, ⌘L, and iOS's ⌘R are hidden buttons in the view tree rather than menu
  commands, so they work but appear in no menu — on macOS there is nothing in
  the menu bar that discovers them.
* Changing size class on iPad — entering Split View or Slide Over — swaps the
  sidebar for the tab bar and back, which rebuilds the navigation and resets
  whatever each section had pushed. The selected section survives; a folder
  you had opened does not.
* Cove Recovery is two taps away rather than one now that it lives under
  Advanced. The group opens itself for a recovered *draft*, so the case that
  matters is still one tap from the banner — but a deleted item waiting out
  its week is not signposted from the top level at all.
* The eyebrow is uppercased by `textCase`, so a vault or list name that is
  already an acronym or deliberately lowercase is restyled in the panel.
* The Lists overview panel appears and disappears as the second list is added
  or removed, which is a card materializing over a screen you were already
  looking at. Deliberate — a summary of one thing is not a summary — but it is
  the one place a figure a reader saw once is simply not there any more.
* `coveListStyle` sets `defaultMinListRowHeight` to 0, so a list row no longer
  has a 44pt floor. Nothing in the app relies on it today — every row is past
  44 from its own content and insets — but a new row built from short text
  alone would silently come out under the platform's minimum target, with
  nothing failing to say so.
* A merged surface's group headings are ordinary rows rather than `Section`
  headers, so whatever a future OS does with real section semantics —
  sticky headers, an index, a VoiceOver rotor — the task screens will not get
  it. In practice SwiftUI reads an inset-grouped section header as a line of
  text anyway, which is what these are.

### Icon and platform

* The icon PNGs are generated artwork checked into the catalog, and the spec
  (the design doc) lives in the Claude Design project, not the repo — an icon
  change means re-rendering the full size set (see "Regenerating the app
  icon"). `Scripts/render-mark.swift` is now in the repo, so the PNGs do have
  something to check them against, but it states the geometry a second time in
  CoreGraphics rather than reading it from `CoveMark`. Nothing fails if the two
  disagree: the app draws one mark and ships another.
* The Mac's dark icon reaches the Dock and the app switcher only, and only
  while Cove is running — it is `NSApp.applicationIconImage`, not the bundle's
  icon, because `appiconset` has no dark `mac` slot. Finder, Spotlight,
  Launchpad, and the Dock's own icon for a *quit* app all keep the light tile.
  This is the most visible rough edge in the app: turn on dark mode with Cove
  closed and its icon is the one thing on the Dock that does not change.
  Closing it means adopting `.icon`, which costs the flat look rather than the
  deployment target — see "What a bundle-level dark icon would actually cost".
* **No automated check can see the Dock tile, and the tests would pass without
  it.** macOS GUI capture needs Screen Recording permission the build shell
  does not have, so `DockIconTests` asserts against `applicationIconImage`
  inside the test host — which is exactly the property that was already
  correct while the Dock was still wrong. The `dockTile` half of `apply` has
  no automated cover at all. Changing `DockIcon` means looking at the Dock by
  hand, with Cove **running**: switch the system or Cove's own appearance and
  watch the tile.
* The dark iOS icon variant is opaque rather than transparent. Apple's iOS 18
  guidance prefers a transparent dark icon over a system backdrop, but the mark
  supplies its own night-black ground. iOS 17 ignores the variant entirely.
* The launch screen is iOS-only; macOS windows open with the app's content.
* The launch tile carries no edge, and in light its ground is exactly
  `LaunchBackground` — so on the launch screen the tile is invisible and only
  the cut disc is on the page. That is the intended reading for this mark and
  it is still a difference from every other place `CoveMark` appears, where the
  hairline makes the tile a tile.
* iOS caches the launch-screen snapshot, so after reinstalling a build with
  new launch artwork the *first* launch can still draw the previous tile. A
  simulator reboot, or simply launching twice, clears it — worth knowing
  before concluding that a launch-screen change did not take.

### Testing

* The unit-test bundle runs inside the sandboxed app host on macOS. During an
  XCTest launch, `CoveApp` uses an empty bookmark domain, no-op notification
  boundaries, and process-temporary widget storage so the host cannot open the
  developer's saved vault or mutate the signed App Group. Tests that create
  bookmarks use the app container's temporary directory, which the sandbox can
  bookmark.
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
* Widget *layout* can be checked without any of that, and the row-count work
  was. `TodayWidgetView` is pure SwiftUI, so a throwaway harness under `Cove/`
  — the synchronized folder picks it up with no pbxproj edit — renders it at
  exact tile sizes (148/158/170 square, and the medium widths) in both
  appearances, with `RootView`'s `.open` case routed to it. Two things have to
  be faked: `\.widgetFamily` is not writable, so the copy takes the family as
  a plain property, and `.containerBackground(for: .widget)` paints nothing
  outside a widget, so the harness supplies `WidgetPalette.background` itself.
  Everything else is the shipping view. It is not a substitute for the Home
  Screen — App Intent taps and timeline reloads only happen there — but it is
  the only way to see all the sizes and states at once, and it needs no
  permission.
* Date handling is tested against UTC-ahead and -behind zones, New York DST
  transitions, and midnight. A non-Gregorian calendar can no longer be handed
  to a date API at all — the parameter is a `TimeZone` — so what was a runtime
  assertion is now a type constraint, and the surviving test pins
  `TaskCalendar` to Gregorian and checks the stored strings carry Gregorian
  years (Buddhist would read 2569 where the fixture reads 2026).
