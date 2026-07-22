# Cove

Cove is a minimal native Markdown notes app for iPhone, iPad, and Mac. You
point it at a folder of Markdown files — typically in iCloud Drive — and that
folder is the single source of truth. There is no backend, no account, no
database, and no custom sync.

Current state (Phase 11 — all build phases complete): select a vault folder,
browse its nested folders, and open any note in a live-styled
Markdown editor that saves automatically as you type. Opening a folder pushes
it onto the Notes screen, so the system back button and the iOS swipe-back
gesture return you to its parent; each level shows a time-aware greeting —
which varies through the day and can address you by name, set in Settings —
and a compact count of direct folders, deeper subfolders, and notes. Headers and
`**bold**` spans are styled in place
(the text stays plain Markdown), and `- [ ]` checkboxes toggle with a tap or
click. Editor checkboxes can also be toggled at the cursor with an accessibility
action or Command-Shift-Space. Notes and folders can be created, renamed,
moved, and deleted from the browser (long-press or right-click a row, or use
the + toolbar menu). Deletion moves content into a hidden Cove Recovery area
and registers immediate Undo; if the original name has since been reused,
Cove asks for a replacement name instead of overwriting it. Recovered items
are kept for a week and then swept the next time the vault opens, so a
deleted note eventually frees its space instead of sitting in the folder
forever. For a
vault in iCloud Drive, changes made outside the app — edits syncing in from
another device, or files added or removed in Finder or the Files app — are
detected while the app runs: the folder tree refreshes itself, and an open
note reloads the new contents as long as you have no unsaved edits (your
typing is never discarded; a simultaneous local/external edit preserves the
external version as a named sibling conflict copy and keeps failures visibly
retryable). Vaults outside iCloud Drive refresh whenever the
app returns to the foreground. The search field in the browser searches every
note's title and contents as you type (case-insensitively, with no persisted
index), and selecting a result opens that note in
the editor. A Tasks tab collects every line of the exact form
`- [ ] Task text @due(YYYY-MM-DD)` from across the vault: open tasks are
sorted by due date and grouped into Overdue, Today, Tomorrow, and Upcoming
sections, with due dates written the way you'd say them ("Today, 3:00 PM",
"Tomorrow", "Friday", "Jul 24") and overdue ones shown in red. Completed
tasks are listed below,
and checking a task off rewrites that line in its original Markdown file.
The completed section has a Clear All action that, after confirmation,
removes every completed Cove task line from its original note. A single task
can be deleted by swiping its row (or right-clicking it), which removes that
line from its note. Task completion and deletion register semantic Undo, so
later edits to the same note are preserved. Tapping a task opens its note. New tasks can be typed as one sentence in
the field at the top of the Tasks tab — "get bread 3p tmr", "gym every mon
wed 6a", "rent 2/3", "meeting next fri 2pm". The interpreter (a port of
the grove-app capture parser) understands relative dates ("tdy", "tmr",
"day after tomorrow", "tonight", "next week", "next fri", "in 3 days"),
explicit dates ("sep 12", "feb 3rd", "2/3", "4/15/27"), times ("3p",
"6pm", "3:30pm", "940p", "noon", "midnight", "15:00", ranges like
"7-9pm"), and repeats ("daily", "every 2 weeks", "every weekday", "every
mon wed fri", "monthly") anywhere in the sentence; what's left over is the
title. The interpretation appears under the field as you type — the
cleaned-up title, the due date and time, the repeat rule — so pressing
return adds the task immediately, with no confirmation step. When Cove
reads a sentence wrong, the sliders button beside the preview opens a
details sheet where the title, date, time, and repeat can be set by hand
before adding. Capture controls show progress while the Markdown write is
finishing, reject accidental duplicate taps, and keep the typed sentence in
place if saving fails so it can be retried. Added tasks go into a `Tasks.md`
note at the vault root
(created on demand), above any lists kept there, and a line like `- [ ] Get bread @due(2026-07-19 15:00)
@repeat(every 2 weeks)` can equally be typed by hand in any note. Tasks
with a time get one local notification at that moment, and completing a
recurring task rolls it to the next occurrence, whose notification is
scheduled in turn; tasks with only a date get none (the app asks for
notification permission only from Settings, never during a background
refresh). Reminder details use the user’s localized compact date and time.
A Lists tab keeps grouped tasks visually separate from what's actually due.
On iPhone and iPad, a Today widget can be added to the Home Screen in small
or medium size: it lists the tasks due today with a checkbox to tick one off
without opening the app, shows overdue ones in red and a count of what's
left, and reads "All clear" once nothing is due. Tapping it opens the Tasks
tab.
A widget checkbox is first recorded as a durable desired-state operation, so
an unavailable vault can be retried the next time Cove opens and replaying an
already-applied operation cannot toggle the task back.
A list — Groceries, Subscriptions, Packing — is a `##` heading inside the
same `Tasks.md`, and its items are ordinary task lines beneath it, so you can
create and edit lists either in the app or by typing Markdown. Items are
captured with the same one-sentence field ("order cake fri 3pm"), and they
can carry due dates, times, and repeats — but here a due date is optional,
so "milk" simply stays an item to buy. Dated items sort first within a list,
undated ones follow in the order you added them, and timed ones notify like
any other task. List items never appear on the Tasks screen, and the Tasks
screen's Clear All never touches them; each list has its own Clear All, in
its Done header, that removes that list's completed items and leaves its open
ones. Lists can be renamed, and deleting a list — from its own Options menu,
or by swiping or right-clicking its row in the overview — removes it and its
items from `Tasks.md` after confirmation.
The vault selection persists across launches, and the app
recovers gracefully when the saved folder access goes stale. A Settings tab
shows the current vault (and can point Cove at a different folder — the same
flow that recovers a stale selection), takes the name used in the Notes
greeting, switches between system, light, and dark appearance, and shows
whether notification permission is granted, with a shortcut to enable it. The app has its own icon and launch screen — the
`cove` wordmark over layered waves, its `o` a sun in light appearance and a
full moon in dark. The
interface uses a cohesive coastal navy-and-teal visual system derived from
that artwork, with branded setup and loading states, vault and task overview
cards, richer file and task rows, polished empty and search states, and a more
spacious writing canvas. On Mac, Notes, Tasks, Lists, and Settings live in a
native branded sidebar; iPhone and iPad keep the familiar tab bar. Wide screens use
comfortable readable content widths, the editor keeps long lines under
control, refresh actions show their progress, and compact layouts adapt for
large text and short windows without hiding primary controls. Command-R
refreshes the current screen, and Command-N creates a note from the Notes
screen.

## Supported platforms

- iOS / iPadOS 17 or later
- macOS 14 (Sonoma) or later

Built in Swift 6 with complete concurrency checking, using SwiftUI and Apple
frameworks only — no third-party dependencies.

The Today widget is iOS-only; it builds and installs on the simulator as is,
but running it on a device needs the `group.com.ankitbhade.Cove` App Group
registered for your team, since the app and the widget share data through it.

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
