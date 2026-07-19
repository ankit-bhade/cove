# Cove

Cove is a minimal native Markdown notes app for iPhone, iPad, and Mac. You
point it at a folder of Markdown files — typically in iCloud Drive — and that
folder is the single source of truth. There is no backend, no account, no
database, and no custom sync.

Current state (Phase 9 — all build phases complete): select a vault folder,
browse its nested folders in place, and open any note in a live-styled
Markdown editor that saves automatically as you type. Each folder level opens
instantly in the existing Notes screen, updating its time-aware greeting and
compact count of direct folders, deeper subfolders, and notes. Headers and
`**bold**` spans are styled in place
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
the editor. A Tasks tab collects every line of the exact form
`- [ ] Task text @due(YYYY-MM-DD)` from across the vault: open tasks are
sorted by due date (overdue dates shown in red), completed ones listed below,
and checking a task off rewrites that line in its original Markdown file.
The completed section has a Clear All action that, after confirmation,
removes every completed Cove task line from its original note. Tapping a task
opens its note. New tasks can be typed as one sentence in
the field at the top of the Tasks tab — "get bread 3p tmr", "gym every mon
wed 6a", "rent 2/3", "meeting next fri 2pm". The interpreter (a port of
the grove-app capture parser) understands relative dates ("tdy", "tmr",
"day after tomorrow", "tonight", "next week", "next fri", "in 3 days"),
explicit dates ("sep 12", "feb 3rd", "2/3", "4/15/27"), times ("3p",
"6pm", "3:30pm", "940p", "noon", "midnight", "15:00", ranges like
"7-9pm"), and repeats ("daily", "every 2 weeks", "every weekday", "every
mon wed fri", "monthly") anywhere in the sentence; what's left over is the
title. A confirmation sheet shows how the sentence was interpreted so you
can adjust the title, date, time, and repeat before saving; confirmed
tasks are appended to a `Tasks.md` note at the vault root (created on
demand), and a line like `- [ ] Get bread @due(2026-07-19 15:00)
@repeat(every 2 weeks)` can equally be typed by hand in any note. Tasks
with a time get one local notification at that moment, and completing a
recurring task rolls it to the next occurrence, whose notification is
scheduled in turn; tasks with only a date get none (the app asks for
notification permission the first time it has something to schedule). Reminder
details use a compact friendly date such as `Jul 18, 8:00pm.`
The vault selection persists across launches, and the app
recovers gracefully when the saved folder access goes stale. A Settings tab
shows the current vault (and can point Cove at a different folder — the same
flow that recovers a stale selection), switches between system, light, and
dark appearance, and shows whether notification permission is granted, with
a shortcut to enable it. The app has its own icon and launch screen. The
interface uses a cohesive coastal navy-and-teal visual system derived from
that artwork, with branded setup and loading states, vault and task overview
cards, richer file and task rows, polished empty and search states, and a more
spacious writing canvas.

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
