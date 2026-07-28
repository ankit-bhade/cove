import SwiftUI

struct CoveIconTile: View {
    let systemName: String
    var tint: Color = CoveTheme.accent

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = CoveTheme.Space.rowGlyph
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 14

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: glyph, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .coveTintedSurface(
                tint,
                in: RoundedRectangle(cornerRadius: side * 0.32, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

/// One list row: a leading `CoveIconTile` and whatever the row says beside it.
///
/// Rows used to be hand-built at every call site — three different gaps, four
/// vertical paddings, and a `Label` in Settings whose system-derived icon
/// column started several points left of the `HStack` rows directly above it,
/// which is exactly the misalignment a reader notices without being able to
/// name. The component owns the grid so a folder row, a list row, and a
/// settings row cannot disagree about it.
struct CoveRow<Content: View>: View {
    let systemName: String
    var tint: Color = CoveTheme.accent
    /// `.top` for a row whose text runs past a line or two, so the tile pins
    /// near the title instead of floating beside the middle of a paragraph.
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: alignment, spacing: CoveTheme.Space.rowGap) {
            CoveIconTile(systemName: systemName, tint: tint)
            content()
                // Left to itself SwiftUI derives the separator's inset from
                // whichever nested label it happens to select, so a folder row
                // carrying a caption and a note row without one drew their
                // separators at two different depths in the same list. Pinning
                // the guide to the text column makes every row agree.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .padding(.vertical, CoveTheme.Space.rowPadding)
    }
}

/// A row's primary text with an optional caption under it, at the one weight
/// and gap every titled row in the app uses.
///
/// The caption used to come in two voices — tracked capitals when it was data
/// ("2 ITEMS", "3 OPEN · 1 DONE") and quiet sentence case when it was a path
/// or a snippet. The distinction was real and it was still one voice too many:
/// a list of rows shouting their counts under a section header already set in
/// the same capitals left nothing for the header to be. Every caption is now
/// the quiet one; tracked capitals belong to headings.
struct CoveRowTitle: View {
    let title: String
    var caption: String?
    var lineLimit: Int? = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(lineLimit)
            if let caption {
                Text(caption)
                    .coveMetaLabel()
                    .lineLimit(2)
            }
        }
    }
}

struct CoveCountBadge: View {
    let text: String
    var tint: Color = CoveTheme.accent

    init(_ text: String, tint: Color = CoveTheme.accent) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .coveTintedSurface(tint, in: Capsule())
    }
}

/// The one due-date label: the phrasing `DueDescription` settled on, set as a
/// subtitle under the task it belongs to. Shared because the capture preview
/// and the task row it becomes sit one keystroke apart on screen — drawn
/// twice, they could word or shade the same date two ways.
///
/// It used to be a tinted capsule with a clock or calendar glyph, and it was
/// the wrong shape for what it says. A pill is a control's shape, so a row
/// carrying one under every title read as a list of buttons; the well's hard
/// edge sat a few points under the title and crowded it in a way a line of
/// text does not; and the glyph restated the date beside it. What is left is
/// the wording, one step down from the title and a step quieter — which is
/// what makes it read as a subtitle rather than as a second title. The tint
/// defaults to secondary and callers raise it only for lateness; see
/// `TaskRow.dueTint`.
///
/// `isOverdue` no longer picks a glyph; it names the state for VoiceOver,
/// which is otherwise the one reader the tint doesn't reach.
struct CoveDueLabel: View {
    let text: String
    var isOverdue = false
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tint)
            .accessibilityLabel(isOverdue ? "Overdue, \(text)" : text)
    }
}

/// The repeat rule beside a task's due date. Takes the rule's wording rather
/// than the rule, so the design system stays clear of the task model.
struct CoveRecurrenceLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        // Not a `Label`: at this size SwiftUI lays its glyph out in an icon
        // column wide enough to leave the rule floating a quarter-inch from
        // the words it belongs to. It sits at `CoveDueLabel`'s size and tint
        // rather than a step below, because the two read as one line — a date
        // and how often it comes back — and two sizes on one line is what made
        // the pair look assembled from parts.
        HStack(spacing: 4) {
            Image(systemName: "repeat")
            Text(text)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Repeats \(text.lowercased())")
    }
}

/// The list a task was captured into, beside its due date on the Tasks
/// screen. A row otherwise says nothing about where its line lives — tasks
/// nearly all sit in the capture note, so naming the *note* was a repeated
/// caption — but a dated list item appearing among unlisted ones is the one
/// case where the row would otherwise be indistinguishable from a task that
/// is not in any list.
///
/// It sits at `CoveDueLabel`'s size and tint for the same reason
/// `CoveRecurrenceLabel` does: the metadata under a title reads as one line
/// about the task, and a second size makes it look assembled from parts.
struct CoveListLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "list.bullet")
            Text(text)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("In list \(text)")
    }
}

struct CoveEmptyState<Actions: View>: View {
    let title: String
    let description: String
    let systemName: String
    @ViewBuilder let actions: () -> Actions

    init(
        _ title: String,
        systemName: String,
        description: String,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.description = description
        self.systemName = systemName
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: CoveTheme.Space.regular) {
            emblem
            VStack(spacing: CoveTheme.Space.tight) {
                Text(title)
                    .font(.coveDisplaySmall)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            actions()
        }
        .frame(maxWidth: 430)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, CoveTheme.Space.loose)
        .padding(.vertical, 30)
        .accessibilityElement(children: .contain)
    }

    private var emblem: some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(CoveTheme.accent)
            .frame(width: 54, height: 54)
            .coveTintedSurface(CoveTheme.accent, in: Circle())
            .background {
                Circle()
                    .fill(CoveTheme.accent.opacity(0.06))
                    .frame(width: 78, height: 78)
            }
            .accessibilityHidden(true)
    }
}

extension CoveEmptyState where Actions == EmptyView {
    init(_ title: String, systemName: String, description: String) {
        self.init(title, systemName: systemName, description: description) {
            EmptyView()
        }
    }
}

/// A short-lived bar saying what just happened and offering to take it back.
///
/// It exists because Undo was reachable and invisible: every destructive task
/// action registers one, and on a Mac the Edit menu says so, but a phone's
/// only route to it is a shake gesture nothing on screen advertises. A swipe
/// that removed the wrong line therefore read as final when it never was.
///
/// It is a card rather than a tinted wash: it sits over content, and the one
/// thing it must not do is read as part of the list it is covering. The action
/// takes the accent — it is the reason the bar is there — while dismissing it
/// is the quiet glyph, since letting it time out does the same thing.
struct CoveUndoBar: View {
    let message: String
    let undo: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: CoveTheme.Space.snug) {
            Text(message)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("Undo", action: undo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CoveTheme.accent)
                .buttonStyle(.plain)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, CoveTheme.Space.regular)
        .padding(.trailing, CoveTheme.Space.tight)
        .padding(.vertical, CoveTheme.Space.snug)
        .background(CoveCardBackground(cornerRadius: CoveTheme.fieldRadius))
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// The manual rescan, put where each platform already looks for it.
    ///
    /// Every list screen used to carry it as a toolbar button, which on iOS 26
    /// is a floating control sitting beside the navigation title — prominence
    /// that an action almost never needed does not earn. Cove rebuilds its
    /// index on launch, on every change it makes, on iCloud's own change
    /// events, and whenever the scene activates; the manual path is for a
    /// vault the metadata query cannot see at all.
    ///
    /// So on iOS it becomes the gesture the platform has for exactly this —
    /// pull to refresh — plus ⌘R for an attached keyboard. AppKit has no pull
    /// gesture, so the Mac keeps the button, where a toolbar is not scarce.
    func coveRefreshable(_ action: @escaping @Sendable () async -> Void) -> some View {
        modifier(CoveRefreshAction(action: action))
    }
}

private struct CoveRefreshAction: ViewModifier {
    let action: @Sendable () async -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
            content
                .refreshable { await action() }
                .background {
                    Button("Refresh") { Task { await action() } }
                        .keyboardShortcut("r", modifiers: .command)
                        .opacity(0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        #else
            content.toolbar {
                ToolbarItem {
                    CoveRefreshButton { await action() }
                }
            }
        #endif
    }
}

/// A refresh action with progress feedback and duplicate-scan protection.
struct CoveRefreshButton: View {
    let action: () async -> Void

    @State private var isRefreshing = false

    var body: some View {
        Button {
            guard !isRefreshing else { return }
            isRefreshing = true
            Task {
                await action()
                isRefreshing = false
            }
        } label: {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .disabled(isRefreshing)
        .keyboardShortcut("r", modifiers: .command)
        .accessibilityLabel(isRefreshing ? "Refreshing" : "Refresh")
        .help(isRefreshing ? "Refreshing…" : "Refresh")
    }
}
