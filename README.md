# Cove

Cove is a minimal native Markdown notes app for iPhone, iPad, and Mac. You
point it at a folder of Markdown files — typically in iCloud Drive — and that
folder is the single source of truth. There is no backend, no account, no
database, and no custom sync.

## Current state

Phase 12 — trackers — on top of the eleven complete build phases. What
follows is everything the app does today, by area.

### The vault

You select a folder with the system picker and Cove remembers it per device
via a security-scoped bookmark; if the folder is later moved or deleted, a
recovery screen offers to reselect one. The Notes screen browses nested
folders one level at a time — opening a folder pushes it, so the system back
button and the iOS swipe-back gesture return you to its parent. The vault root
opens with a compact count of direct folders, deeper subfolders, and notes; a
folder you have pushed into does not, since the title bar already names it and
each row already carries its own item count.

Notes and folders can be created, renamed, moved, and deleted: swipe a row on
iPhone or iPad, right-click it on any platform, or use the **+** toolbar
menu. Creating a note opens it straight away. Deletion moves content into a
hidden Cove Recovery area and registers immediate Undo; if the original name
has since been reused, Cove asks for a replacement rather than overwriting
it. Recovered items are kept for a week and swept the next time the vault
opens, so a deleted note eventually frees its space instead of sitting in the
folder forever.

### The editor

Any note opens in a live-styled Markdown editor that saves automatically as
you type. Headers and `**bold**` spans are styled in place — the text stays
plain Markdown — and `- [ ]` checkboxes toggle with a tap or click, at the
cursor with an accessibility action, or with Command-Shift-Space.

Your typing survives whatever happens to the file underneath it. A
simultaneous local and external edit preserves the external version as a
named sibling conflict copy, which the banner offers to open. Unsaved text is
journaled locally as you type, so a crash or a forced quit doesn't take it.
If the note is renamed or deleted out from under the editor, the recovered
text is offered back with a Save Copy action rather than dropped. Recovered
edits are held for review before they overwrite anything, and Settings → Cove
Recovery lists both deleted items and unsaved drafts. A journal entry Cove
cannot read is set aside rather than cleared — the note still opens, and the
banner names the file the unreadable copy was kept as.

### Search

The search field in the browser searches every note's title and contents as
you type — case-insensitively, with no persisted index — and selecting a
result opens that note **at the matching line**.

### Tasks

The Tasks tab collects every line of the form
`- [ ] Task text @due(YYYY-MM-DD)` from across the vault. Indented and `*`/`+`
bullets count, so nested checklists aren't skipped, while task-like text
inside fenced code, HTML comments, or YAML front matter is left alone.

Open tasks sort by due date and group into Overdue, Today, Tomorrow, and
Upcoming, with dates written the way you'd say them ("Today, 3:00 PM",
"Tomorrow", "Friday", "Jul 24") and overdue ones in red. Upcoming folds away
with the chevron on its header when it gets long; the completed section below
starts folded. A closed header still shows how many are behind it.

Tapping a task opens its details — title, due date, time, and repeat rule —
and saving rewrites just that line, keeping its indentation, bullet, checkbox,
and line ending exactly as the file had them. A list item can be edited to
have no date at all; a task outside a list can't, since `@due` is what makes
it one. Changing the date of a recurring task re-anchors its cadence to the
new date; changing only its title leaves the cadence alone. **Open in Note**
— in the sheet, in the row's context menu, or on a leading swipe — opens the
Markdown at that task's own line.

Checking a task off rewrites that line in its original Markdown file.
Opening the completed section reveals a Clear All Completed row that, after
confirmation, removes every completed Cove task line from its note — it
preflights every affected note before the first write and registers one
semantic Undo, so a stale target aborts the sweep and later unrelated edits
survive restoration. A single task can be deleted by swiping its row or
right-clicking it. Adding, completing, and deleting all register semantic
Undo, so later edits to the same note are preserved — including for a
recurring task, where undoing a completion rolls its date back rather than
failing to find the line it just advanced. If two task lines are identical in
every respect, Cove refuses to act on either rather than guess which one you
meant, and points at them from Settings. A checkbox another device already
ticked simply corrects itself: nothing is written, and nothing lands in Undo
that would reverse that other change.

Every destructive action raises a short bar naming what happened with an Undo
beside it, which stays for a few seconds: deleting a task, clearing the
completed ones, deleting a list, and deleting a subscription or one of its
categories. It is the same reversal ⌘Z performs on a Mac — the bar exists
because a phone's only route to it is a shake gesture nothing on screen
advertises. It matters most for the deletions that rewrite a note rather than
move a file, since those leave nothing in Cove Recovery to go back to.

### Quick capture

New tasks are typed as one sentence in the field at the top of the Tasks tab
— "get bread 3p tmr", "gym every mon wed 6a", "rent 2/3", "meeting next fri
2pm". The interpreter, a port of the grove-app capture parser, understands:

- **relative dates** — "tdy", "tmr", "day after tomorrow", "tonight", "next
  week", "next fri", "in 3 days"
- **explicit dates** — "sep 12", "feb 3rd", "2/3", "4/15/27"
- **times** — "3p", "6pm", "3:30pm", "940p", "noon", "midnight", "15:00",
  ranges like "7-9pm"
- **repeats** — "daily", "every 2 weeks", "every weekday", "every mon wed
  fri", "monthly"

Tokens are recognized anywhere in the sentence; what's left over is the
title. The interpretation appears under the field as you type, so pressing
return adds the task immediately with no confirmation step. When Cove reads a
sentence wrong, the sliders button beside the preview opens a details sheet
where the title, date, time, and repeat can be set by hand.

Competing time or repeat expressions stay visible in the title and block
capture until reviewed; a local clock time that does not exist during a
daylight-saving transition is rejected rather than silently shifted. Capture
controls show progress while the Markdown write finishes, reject duplicate
taps, and keep the typed sentence in place if saving fails.

Added tasks go into a `Tasks.md` note at the vault root, created on demand,
above any lists kept there. A line like
`- [ ] Get bread @due(2026-07-19 15:00) @repeat(every 2 weeks)` can equally be
typed by hand in any note.

### Lists

A list — Groceries, Packing — is a `##` heading inside that same `Tasks.md`,
and its items are ordinary task lines beneath it, so lists can be built in
the app or by typing Markdown. Items use the same one-sentence field ("order
cake fri 3pm") and may carry dates, times, and repeats — but here a due date
is optional, so "milk" simply stays an item to buy.

Dated items sort first within a list and undated ones follow in the order you
added them. A list item with a due date also appears on the Tasks screen,
grouped by day among everything else and naming its list under the title — a
dated chore is due whether or not it was filed somewhere. An undated item has
no day to appear under and stays in its list alone.

The Tasks screen's Clear All takes the completed items it showed, lists
included, and leaves undated list items alone; each list has its own Clear
All as the last row of its Done section. Both are undoable. Lists can be renamed, and deleting
one — from its Options menu, or by swiping or right-clicking its row —
removes it and its items after confirmation; Undo reinserts only the removed
section into the latest file and refuses if a new list has reused the name.

### Trackers

The Trackers tab holds what Cove keeps that isn't a task. Today that is
**Subscriptions**, kept in `Trackers/Subscriptions.md` as one line per
recurring charge — `- Netflix @cost(15.49 USD) @every(month)
@since(2024-03-04)` — with `##` headings as categories, so it stays a note you
can edit by hand.

The screen shows what everything costs per month and per year, the charges
landing in the next thirty days, and the rest grouped by category, with a
chart above them ranking each subscription by monthly cost. It is meant for
software and service subscriptions — streaming, games, tools, a gym — rather
than large recurring bills.

`@since` is the *first* charge, never the next, so the file is never
rewritten as time passes and a charge on the 31st doesn't drift to the 28th
after February. A subscription can be paused or cancelled, after which it
counts toward nothing and folds away at the bottom. Categories can be
created, renamed, and deleted from the screen; deleting one takes the charges
filed under it, so the confirmation says how many and how to keep them, and
the deletion is undoable. If a charge is paused or cancelled somewhere else
while you have its sheet open, saving is refused rather than putting it back
the way the sheet found it.

Currencies are never converted. Totals are kept per currency, the chart names
which currency it is drawn in when there is more than one, and weekly or
daily charges are averaged over a year — all of which the screen says rather
than implying otherwise.

### Notifications and the Today widget

Tasks with a time get one local notification at that moment; tasks with only
a date get none. Completing a recurring task rolls it to the next occurrence,
whose notification is scheduled in turn. Reminder details use your localized
compact date and time, and the app asks for notification permission only from
Settings, never during a background refresh.

On iPhone and iPad, a Today widget can be added to the Home Screen in small
or medium size. It heads with the day and date, lists the tasks due today with
a checkbox to tick one off without opening the app, shows overdue ones in red
and a count of what's left, and reads "All clear" once nothing is due.
Tapping it opens the Tasks tab. A widget checkbox is first recorded as a
durable desired-state operation, so an unavailable vault can be retried the
next time Cove opens, and replaying an already-applied operation cannot
toggle the task back.

### Keeping up with changes outside the app

For a vault in iCloud Drive, changes made elsewhere — edits syncing in from
another device, files added or removed in Finder or the Files app — are
detected while the app runs: the folder tree refreshes and an open note
reloads the new contents as long as you have no unsaved edits. Vaults outside
iCloud Drive refresh whenever the app returns to the foreground, or from the
refresh button on any screen.

A note Cove can't read — text that isn't UTF-8, or a file iCloud hasn't
finished downloading — is passed over rather than blocking the vault, and is
picked up again on the next refresh. Settings lists any note whose tasks
couldn't be read, and any checkbox or subscription line whose tags didn't
parse, each opening the editor at the exact line. Long lists of warnings are
capped with the hidden count shown and a way to see the rest.

### Settings

Settings shows the current vault and can point Cove at a different folder —
the same flow that recovers a stale selection — switches between system,
light, and dark appearance, and reports whether notification permission is
granted with a shortcut to enable it. A Vault Safety row summarizes the
vault's state as Ready, Recovery, or Attention; when something needs review,
it is listed right there, a banner on every screen says so, and each warning
opens the note at the line it names.

Everything else — Cove Recovery, the Today widget's status, folder access,
and bookmark state — sits behind one **Advanced** group. It opens itself when
something in it needs attention: an unsaved bookmark (the whole explanation
for a vault that keeps asking to be reselected), a recovered draft waiting for
review, or a widget change that could not be applied.

### The look of it

The app has its own icon and launch screen — the `CoveMark` stamp, a bay cut
into the land's edge with its shoreline traced in ember, warm paper over ink
in light and night over paper in dark.

Inside, the interface is set in ink on warm paper: a warm off-white canvas,
screen titles and headlines in the system serif, tracked capitals for labels,
monospaced digits for every count, and a single burnt-ember accent that
carries interaction — with moss for folders and lists and a warm rust for
anything overdue. Every screen opens with the same compact panel — a short
accent rule, a label, an optional count, and the screen's own content right
under it. Every list row shares one icon-and-text grid, so a task's checkbox
sits in the same column a folder's tile does and the text lines up wherever
you are. Setup, loading, empty, and search states all come from that one
system.

On Mac and on a regular-width iPad, Tasks, Notes, Lists, Trackers, and
Settings live in a native branded sidebar; iPhone keeps the familiar tab bar
in every orientation. Tasks leads both and is
where Cove opens everywhere — including the Today widget's deep link, so both
ways in land on the same screen. Wide screens use comfortable readable
content widths, the editor keeps long lines under control, and compact
layouts adapt for large text and short windows without hiding primary
controls.

### Keyboard

- **⌘1**–**⌘5** — switch to Tasks, Notes, Lists, Trackers, Settings
- **⌘L** — focus the quick-capture field on the Tasks screen
- **⌘N** — new note, from the Notes screen
- **⌘R** — refresh the current screen (on iOS, pull down on the list instead)
- **⌘⇧Space** — toggle the checkbox at the cursor, in the editor

## Supported platforms

- iOS / iPadOS 17 or later
- macOS 14 (Sonoma) or later

Built in Swift 6 with complete concurrency checking, using SwiftUI and Apple
frameworks only — no third-party dependencies.

The Today widget is iOS-only; it builds and installs on the simulator as is,
but running it on a device needs the `group.com.ankitbhade.Cove` App Group
registered for your team. The container holds only the current derived Today
snapshot, the vault bookmark needed for a direct write, and a bounded pending
desired-state queue.

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

# Check Swift formatting
xcrun swift-format lint --configuration .swift-format --recursive Cove CoveWidgets Tests

# Run the full warnings-as-errors verification (tests and Release builds)
Scripts/verify-build.sh
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
  filesystem is separate from your Mac's. In the booted simulator, open
  **Files › On My iPhone**, create a folder, add a Markdown file if desired,
  then select that folder from Cove. Any writable folder offered by the
  picker works; `simctl addmedia` does not import folders into Files.

The selected folder is remembered per device via a security-scoped bookmark.
If the folder is later moved or deleted, Cove shows a recovery screen where
you can reselect a vault.

## Source attribution

Quick capture is a Swift port of the author’s MIT-licensed Grove parser.
The pinned source, adapted files, and license notice are recorded in
[`ATTRIBUTION.md`](ATTRIBUTION.md).
