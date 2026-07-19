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
  reselect, system/light/dark appearance, notification permission status,
  app version), a teal accent color, generated app icon artwork for iOS
  and macOS, and an iOS launch screen (Phase 9)

### Changed

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
