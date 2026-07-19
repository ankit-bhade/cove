# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Project scaffolding and repository documentation (Phase 0)
- Folder picker, bookmark persistence, stale-bookmark recovery, and read-only vault tree browser (Phase 1)
- Editor with autosave, and note and folder creation, rename, move, and delete (Phase 2)
- Live Markdown styling in the editor: headers, bold, and tappable checkboxes (Phase 3)
- iCloud change detection and external-edit refreshing (Phase 4)
- Full-text search across all Markdown files (Phase 5)
- Task parsing and Tasks screen with an in-memory vault index (Phase 6)
- Local task notifications for incomplete due tasks (Phase 7)
- Natural-language quick task entry with times and recurrence (Phase 8)
- Appearance polish, app icon, and launch screen: a Settings tab (vault
  reselect, greeting name, system/light/dark appearance, notification
  permission status), a teal accent color, generated app icon artwork for
  iOS and macOS, and an iOS launch screen (Phase 9)
- A single task can now be deleted from the Tasks screen by swiping its row
  or right-clicking it, which removes that line from its Markdown note.
- Settings takes a name, used by the Notes greeting.
- Task lists (Phase 10): a Lists tab groups related tasks — groceries,
  subscriptions, packing — as `##` sections of the same `Tasks.md`. List
  items use the same natural-language capture and can carry due dates,
  times, and repeats, but a due date is optional there, and list items are
  kept out of the Tasks screen. Lists can be created, renamed, and deleted.

### Fixed

- Welcome and vault-recovery screens now scroll at large Dynamic Type sizes
  and in short windows, preventing their primary folder action from clipping.
- Tapping a note in the Notes browser, or a search result, did nothing and
  never opened the editor. The browser's navigation path is typed as
  `[URL]`, so the links carrying a `VaultNode` were silently inert; notes
  now push their URL like folders do, and one destination routes each URL
  to the editor or the next folder level.

### Changed

- The quick-entry interpreter no longer forces an undated sentence to today.
  The Tasks screen still resolves one to today (its tasks require a due
  date); the Lists screen leaves it undated.
- Refined the app-wide UI for faster, more predictable navigation: macOS now
  uses a branded Notes/Tasks/Lists/Settings sidebar while iPhone and iPad
  retain their native tab bar; refresh actions show progress, reject duplicate
  scans, and support Command-R, and New Note supports Command-N.
- Added readable-width layouts for wide windows and iPad, a narrower writing
  measure in the editor, adaptive dashboard/task/status layouts for Dynamic
  Type, multiline note names and task titles, capped deep-folder indentation,
  and more descriptive accessibility labels and hints.
- Reduced visual weight in Settings by making vault reselection a standard
  row action, and made task review titles multiline-editable.
- Refined the interface for clarity and consistency: folders now open as
  real navigation pushes (system back button and iOS swipe-back), open
  tasks are grouped into Overdue/Today/Tomorrow/Upcoming with plain-language
  due dates, the editor reports its actual save state instead of a fixed
  "Auto-save" label and can dismiss the iOS keyboard, search shows a
  searching indicator, and the quick-capture "+" glyph became a working
  submit button. Decorative icon tiles are hidden from VoiceOver and scale
  with Dynamic Type, checkbox hit targets meet the 44pt minimum, empty names
  no longer reach the create/rename error path, and the move picker marks
  the item's current folder.
- Replaced the app icon and launch-screen artwork with the `cove` wordmark
  over the coastal waves, its `o` a sun by day and a full moon at night.
  Adds a dark iOS app icon variant and a dark launch-screen tile.
- Standardized grouped-screen card widths and made prominent vault-selection
  actions fill their available row, keeping Notes, Tasks, Settings, and the
  task review sheet visually aligned on iOS.
- Folder taps in Notes now update the current browser and its scoped stats in
  place instead of pushing a new folder screen; notes still open in the editor.
- Task reminder details now use a concise month, day, and time without the year
  or source-note label, for example `Jul 18, 8:00pm.`
- The Notes browser shows folders level by level and replaces its branded
  workspace card with a time-aware greeting plus scoped folder, subfolder, and
  note counts; the greeting is visually lighter and less prominent.
- The Tasks screen now offers a confirmed Clear All action that removes every
  completed Cove task line from its original Markdown note.
- Trimmed the Tasks screen: task rows no longer repeat their source note's
  name beneath every task and sit tighter, and the quick-capture card drops
  its how-it-works description and the vault-wide completed count.
- The Notes greeting now varies across seven stretches of the day and can
  address you by the name set in Settings.
- Removed the About section from Settings.
- Refined the interface with a cohesive coastal visual system, branded
  loading and vault-setup states, dashboard cards for Notes and Tasks,
  richer file, search, task, settings, and move rows, improved empty states,
  and a more spacious live Markdown editor (Phase 9)
- Task notifications now fire at the task's due time; tasks with only a
  due date no longer get a 9:00 notification (Phase 8)
- Quick task entry now uses the grove-app capture grammar: tokens match
  anywhere in the sentence, with explicit dates ("2/3", "sep 12"),
  "tonight"/"next week"/"in 3 days", compact times ("940p"), time
  ranges, and richer recurrences ("every 2 weeks", "every mon wed fri",
  "monthly"); recurring tasks now get a one-shot notification for their
  current occurrence instead of repeating triggers (Phase 8)
