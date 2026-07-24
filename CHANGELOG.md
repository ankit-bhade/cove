# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Reliability hardening adds semantic Undo for task completion and deletion,
  recoverable note/folder deletion through a hidden `.cove-recovery` area,
  conflict-copy preservation for simultaneous editor/external edits, and a
  Retry action for failed saves.
- Editor checkboxes now expose a “Toggle checkbox at cursor” accessibility
  action and Command-Shift-Space keyboard shortcut on iOS/iPadOS and macOS.
- Local `Logger` categories cover vault, document, widget, notification, and
  index failures without logging note contents or task titles.

### Changed

- The screens whose first job is *doing* something lead with the thing itself.
  Quick capture, a list's capture card, and the lists overview each carried a
  full masthead — an accent rule, an eyebrow, a serif slogan, and a sentence of
  instruction — which on the landing screen pushed the first overdue task most
  of the way down the display for copy that is read once. They now use a
  compact `CovePanel`: one label line, an optional count badge, and the field
  or the figures. Six tasks fit above the fold where three did, and the
  quick-add draft sheet drops its header entirely, so every field fits on one
  screen without scrolling. `CoveMasthead` stays where its title says something
  that changes — the greeting at the vault root and a folder's own name.
- Markdown headers in the editor are set in the system serif, like every other
  title in the app, and paragraph spacing beats line spacing (7 against 4) so a
  new line is visibly a new line. At 4 and 2 a wrapped sentence and the next
  task line opened the same gap, and a note of checkboxes read as one block.
- The iOS tab bar is left to the system. Forcing a material on it replaced the
  platform's own bar with a flat pill that content showed through unblurred.
- Consolidated the duplication that had accumulated across the task screens,
  the coordination layer, and the date APIs, and removed the code nothing but
  the tests still reached. The Tasks tab and a list's detail view kept their
  own copies of check-off, swipe-to-delete, and clear-completed — and the
  copies had already drifted, so the same checkbox registered its Undo as
  “Toggle Task” on one screen and “Toggle Checkbox” on the other. Both now
  run one `TaskActions`, so that name is a single decision. The five
  hand-written `NSFileCoordinator` wrappers across the vault and the widget
  queue became one `FileCoordination`; the three copies of the
  optional-to-`Bool` presentation binding became `covePresence()`, and the
  browser's hand-built error alert became the shared `coveErrorAlert` every
  other screen already used.
- Date APIs take a **time zone** rather than a calendar. Fourteen of them
  accepted a `Calendar` and immediately rebuilt it as Gregorian from the
  incoming one's time zone — correct, but a signature asking for something it
  then discarded, so a caller handing over a Hebrew or Buddhist calendar was
  silently overridden with nothing saying so. The zone was the only part ever
  honored, and is now the only part asked for.
- Quick capture's recurrence maps moved beside the patterns they mirror and
  are no longer force-unwrapped: an `@repeat` synonym added to a regex but not
  to its map now fails to match instead of trapping the process mid-keystroke.
- Cove opens on Tasks on every surface — the iPhone and iPad tab bar, the
  macOS sidebar, and the Today widget's deep link, which already landed there.
  A launch from the Home Screen and a launch from the app icon now arrive at
  the same screen. Tasks also leads the tab bar and the sidebar, so the
  section the app opens on is the first target rather than the second:
  Tasks, Notes, Lists, Settings.
- Second visual consistency pass, this time on the grid every list is drawn
  on. Rows were hand-built at each call site with three different gaps between
  a row's icon tile and its text, four vertical paddings, and — in Settings —
  a `Label` whose system-derived icon column started several points left of
  the rows directly above it, so the vault, appearance, and notification rows
  visibly failed to line up. Every row in the app is now one `CoveRow`, and
  tinted surfaces (icon tiles, count badges, due capsules, editor banners,
  the recovery emblem) draw their wash and hairline from one pair of tokens
  instead of five hand-tuned pairs. The due capsule and repeat label existed
  twice — once in a task row and once in the capture preview it becomes — and
  are now one component each.
- A completed task's due capsule goes quiet with the rest of its row. Struck
  through grey text under a full-strength ember capsule left the loudest thing
  in the row attached to the one task that no longer wants attention.
- The quick-capture draft sheet's section headers are Cove's tracked capitals
  rather than the system's plain form headers, and the greeting row's icon
  takes the accent rather than moss, which the palette reserves for the things
  that contain other things.
- Task captures, toggles, deletions, and list edits rebuild the index over the
  tree already in memory instead of re-enumerating every folder in the vault.
  The mutated note is re-read, every other note reuses its index entry, and
  anything that can change the tree's shape — creating, renaming, moving, or
  deleting a note or folder, or the write that creates the capture note —
  still takes the full rescan.
- Date formatters are built once per template, locale, time zone, and calendar
  rather than per task row per render, and notification bodies are worded only
  for the plans that survive the 60-request cap.
- The Today widget heads with the date rather than the word "Today", which a
  widget showing only today's tasks already implies: the weekday reads wide on
  the medium family and abbreviated on the small one, with the month and day
  beside it. The accent rule left of the header is gone, and the checkboxes are
  drawn in a muted accent — repeated down a small surface, rings at full
  saturation were louder than the task text they belong to.
- New visual direction: ink on warm paper, marked in ember. The coastal
  teal-and-navy palette is replaced by a warm paper canvas, warm ink text, a
  burnt-ember accent that carries every interaction, moss for folders and
  lists, and a warm rust for overdue. Titles are set in the system serif —
  screen titles, mastheads, and empty states — against tracked capitals for
  labels and monospaced digits for every count. The three hand-built dashboard
  cards become one `CoveMasthead` (accent rule, eyebrow, serif title,
  subtitle, and whatever the screen puts under it), section headers become one
  `CoveSectionHeader`, and the app's in-product mark is now drawn rather than
  loaded from an asset. Search's two unavailable states and the editor's
  can't-open state use Cove's own empty state instead of the system's.
  Behavior, navigation, and information architecture are unchanged.
- Visual consistency pass across the shared UI. The Tasks card's open count is
  now the same tinted capsule the Lists rows use, instead of a `Label` whose
  dot glyph read as a stray bullet beside its own text; both draw from one
  `CoveCountBadge`. The Tasks section headers drop their icons — a sunrise and
  a calendar at caption size were illegible, and every other section header in
  the app is already plain text. Settings' vault-reselect row leads with the
  same icon tile as the rows around it rather than a bare body-size glyph. The
  macOS sidebar uses outline symbols, the platform's own convention.
- The app icon and iOS launch tile are redrawn as the `CoveMark` stamp — the
  serif `c` cupping an ember dot — on the new grounds: ink on warm paper in
  light, paper on night-black in dark, the same ember dot in both. This
  retires the last of the coastal teal-and-navy wordmark, so the springboard
  icon and splash now match the interface. The in-product `CoveMark` becomes
  appearance-aware to match the light icon face; its geometry is unchanged.

### Fixed

- List rows draw their separators at one depth. SwiftUI derived the inset from
  whichever nested label it happened to select, so in the same list a folder
  row carrying a caption and a note row without one broke the line at two
  different places; `CoveRow` now pins the guide to its text column.

- The repeat rule under a task sits beside its glyph rather than a quarter-inch
  away — a caption-size `Label` lays its icon out in a column wide enough to
  strand the words — and reads at secondary rather than tertiary, which was too
  faint against the due capsule next to it.

- The quick-add sheet's title field lines up with the values below it. Its
  label and field were stacked, leaving the title at the section's edge while
  the date, time, and repeat sat in the trailing column.

- One unreadable note no longer takes the whole vault down with it. A note
  whose bytes aren't UTF-8, or that iCloud hasn't materialized yet, used to
  fail the index build, close the vault, and leave the app on its recovery
  screen. Such a note is now indexed with no tasks, logged, and re-read on the
  next rebuild, so the rest of the vault stays open and the note recovers by
  itself once it can be read.

- Absurd repeat intervals no longer crash the app. "in 9223372036854775807
  weeks" trapped the process while it was still being typed, since the live
  preview re-parses on every keystroke, and the same value left in a note's
  `@repeat` tag trapped on the next completion. Relative counts and recurrence
  intervals are now clamped to bounds the date arithmetic can hold.

- Widget-initiated toggles validate the note path they were given. A queued
  operation is applied only when its recorded path still resolves to a
  non-hidden Markdown file inside the vault now open — one left over from a
  vault the user has since swapped away from is dropped instead of retried.

- Sweep the deleted-item recovery area. Recovered notes and folders are kept
  for a week and then removed the next time the vault opens, so deleting
  something eventually frees its space instead of parking it in the vault
  forever — which, in an iCloud vault, meant every note ever deleted kept
  syncing and consuming storage invisibly.

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
- Each list can clear its own completed items from its Done header, the way
  the Tasks screen clears its completed tasks.
- Deleting a list is reachable from the list itself (its Options menu) and
  by right-clicking it in the Lists overview, not only by swiping its row.
- iOS Today home-screen widget (Phase 11): a WidgetKit widget in small and
  medium showing the tasks due today, with a tappable checkbox that completes
  one in place. Overdue tasks read red, the count pill tracks what's left,
  and finishing the last one turns the widget over to an "All clear" state.
  Tapping the widget opens the Tasks tab. The app publishes the day's tasks
  to a shared App Group container on every index rebuild, so the widget never
  reads the vault itself.

### Fixed

- Task, list, capture, and widget mutations now perform one coordinated atomic
  read-modify-write against the latest file contents. Desired-state widget
  operations are durable and idempotent, so concurrent actions and retries no
  longer flip tasks twice or lose an independent edit.
- Autosave is serialized per open note, coalesces rapid revisions, flushes on
  navigation/background transitions, remains visibly dirty after failure, and
  preserves a concurrently changed disk version as a deterministic sibling
  conflict copy before saving local text.
- Vault refreshes are latest-wins and cancellation-aware, preventing an older
  scan or previous vault from replacing newer state. File-event bursts are
  coalesced and unchanged notes reuse their in-memory index entries.
- Stored task dates now always use Gregorian semantics regardless of the
  system calendar. Recurrence, grouping, reminders, and widget rollover use
  injected time zones and calendar-day arithmetic, including 23/25-hour DST
  days; midnight widget entries no longer reuse yesterday’s snapshot.
- Notification reconciliation now diffs Cove-owned requests instead of
  deleting and rebuilding all of them, and background refresh never presents
  an authorization prompt.
- Markdown editing restyles only affected paragraphs and their neighbors,
  preserving IME composition, selection, and text undo behavior.
- Widget queue corruption and bookmark/snapshot I/O failures are diagnosed
  instead of being silently replaced or discarded.
- A widget checkbox that can never be written back is now given up on after
  five failed attempts instead of being retried on every launch forever. A
  pre-upgrade queue is also persisted as it is migrated, so acknowledging one
  migrated operation no longer discards the rest.

- Quick capture no longer clears the typed sentence before its Markdown write
  succeeds. The entry field and review sheet now show saving progress, keep
  failed input available for retry, and block accidental duplicate submits.
- Task checkboxes now show an in-row progress indicator and ignore repeated
  taps while their filesystem update is in flight, preventing overlapping
  toggles from producing avoidable changed-on-disk errors.
- Quick capture's add and details controls now provide full 44-point touch
  targets, and blank list names can no longer submit from create or rename
  dialogs.
- The Today widget centered its task rows in the space under the header, so
  a single task floated in the middle of the widget and the list appeared to
  grow in both directions. Rows now hang from the header, with each new task
  added below the last.
- The Today widget's header date sat on its own baseline at a much smaller
  size than "Today". The two now share a size and a baseline, separated by
  weight and color instead.
- The Today widget's "All clear" state dropped the header entirely, losing
  the day, the date, and the count. The header is now unconditional, so an
  empty day still reads as today.
- A quick-captured task with no list was appended to the end of `Tasks.md`,
  which put it under the last `##` list heading — so a task added for today
  joined that list and vanished from the Tasks screen. Captures now land in
  the note's list-free region instead.
- Welcome and vault-recovery screens now scroll at large Dynamic Type sizes
  and in short windows, preventing their primary folder action from clipping.
- Tapping a note in the Notes browser, or a search result, did nothing and
  never opened the editor. The browser's navigation path is typed as
  `[URL]`, so the links carrying a `VaultNode` were silently inert; notes
  now push their URL like folders do, and one destination routes each URL
  to the editor or the next folder level.

### Changed

- The vault index no longer keeps every note's full text in memory. It was
  written on each rebuild and read by nothing — search re-reads from disk by
  design — so the index held a complete in-memory duplicate of the vault for
  no consumer.
- The app, tests, and widget now compile in Swift 6 mode with complete strict
  concurrency checking enabled.
- Note and folder deletion keeps the existing confirmation but moves content
  to Cove Recovery instead of permanently removing it. Immediate Undo restores
  the original path, or asks for a new name when that path is occupied.
- Reminder text now follows the user’s locale instead of a fixed POSIX format.
- `CLAUDE.md` is restructured around decisions rather than descriptions: the
  fixed rules lead, the specification is condensed, architecture keeps the
  rationale and drops narration the code already carries, and the known issues
  are grouped by area with duplicates removed.

- Quick capture now interprets as you type and adds on return. The Tasks and
  Lists entry fields show the title, due date, time, and repeat rule they read
  out of the sentence, so the confirmation sheet no longer sits in front of
  every capture — it is now a sliders button beside the preview, for the
  sentences Cove reads wrong.
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
- The Notes greeting, Quick Capture, and list-item capture cards now use a
  shared hero-card treatment with a decorative leading icon, and the Lists tab
  gained an overview card summarizing list, open, and done counts above its
  Collections section. Empty states across Notes, Tasks, and Lists were
  replaced with a shared `CoveEmptyState` view in place of the system's
  `ContentUnavailableView`, matching the app's visual language. The macOS
  sidebar rows now bold and tint their icon when selected, and both the
  sidebar header and iOS tab bar gained a subtle material background.
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
- Tightened row and quick-capture card density on the Tasks and Lists
  screens: task rows use smaller list-row insets and a shared separator
  edge instead of collapsing into the nearest metadata label, and the
  quick-capture cards use less padding.
