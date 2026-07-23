import SwiftUI

/// Cove's visual system: a small set of tokens and the handful of components
/// every screen is assembled from.
///
/// The palette is **ink on warm paper, marked in ember**. A notes app is a
/// page before it is anything else, so the canvas is an unbleached warm
/// off-white rather than a cool system gray, text sits on it as warm ink, and
/// exactly one saturated hue — a burnt ember — carries interaction and
/// emphasis. Moss is the single supporting hue, reserved for containers
/// (folders, destinations), and a warm rust carries lateness. Nothing else
/// gets a color.
///
/// Every token is a dynamic color that resolves itself against the current
/// appearance, so views never thread a `ColorScheme` through to pick a shade
/// and a nested component can't disagree with its container about which
/// appearance it is in.
enum CoveTheme {

    // MARK: - Palette

    /// The page. Warm, low-contrast, and never pure white — a full-white
    /// canvas under a full-white card leaves the card with nothing to sit on.
    static let canvas = dynamic(light: Color(red: 0.965, green: 0.953, blue: 0.933),
                                dark: Color(red: 0.086, green: 0.082, blue: 0.075))

    /// Cards, rows, and fields: one step up from the canvas.
    static let surface = dynamic(light: Color(red: 1.000, green: 0.992, blue: 0.976),
                                 dark: Color(red: 0.125, green: 0.118, blue: 0.106))

    /// Warm near-black. Used for shadows and for marks that should read as
    /// written rather than tinted; ordinary text keeps `.primary`.
    static let ink = dynamic(light: Color(red: 0.141, green: 0.129, blue: 0.114),
                             dark: Color(red: 0.949, green: 0.933, blue: 0.906))

    /// The one saturated hue: interaction, emphasis, and the brand mark.
    static let accent = dynamic(light: Color(red: 0.620, green: 0.345, blue: 0.153),
                                dark: Color(red: 0.878, green: 0.635, blue: 0.392))

    /// The supporting hue, reserved for things that *contain* other things.
    static let moss = dynamic(light: Color(red: 0.337, green: 0.420, blue: 0.306),
                              dark: Color(red: 0.639, green: 0.702, blue: 0.580))

    /// Overdue and other lateness. Warmer than the system red so it belongs
    /// to this palette, still unmistakably an alarm.
    static let alert = dynamic(light: Color(red: 0.698, green: 0.227, blue: 0.169),
                               dark: Color(red: 0.910, green: 0.475, blue: 0.416))

    /// Hairline separators and card edges. Deliberately faint: the layout
    /// does the dividing, and the line only confirms it.
    static let hairline = dynamic(light: Color(red: 0.141, green: 0.129, blue: 0.114)
                                    .opacity(0.12),
                                  dark: .white.opacity(0.10))

    // MARK: - Metrics

    /// The spacing scale. Four steps is enough for this app, and having only
    /// four is what keeps unrelated screens landing on the same rhythm.
    enum Space {
        static let tight: CGFloat = 6
        static let snug: CGFloat = 10
        static let regular: CGFloat = 16
        static let loose: CGFloat = 22
    }

    static let cardRadius: CGFloat = 18
    static let fieldRadius: CGFloat = 12

    /// Custom cards inside grouped lists should use the grouped section's
    /// own horizontal bounds. Adding another inset makes them visibly
    /// narrower than the native rows and controls around them.
    static func mastheadRowInsets(bottom: CGFloat = 14) -> EdgeInsets {
        EdgeInsets(top: 8, leading: 0, bottom: bottom, trailing: 0)
    }

    /// Task rows keep a full-size checkbox target, so they need less of the
    /// native List's extra vertical padding than an ordinary text row.
    static func taskRowInsets(hasMetadata: Bool) -> EdgeInsets {
        #if os(iOS)
        EdgeInsets(top: hasMetadata ? 6 : 5,
                   leading: 20,
                   bottom: hasMetadata ? 6 : 5,
                   trailing: 14)
        #else
        EdgeInsets(top: hasMetadata ? 4 : 3,
                   leading: 10,
                   bottom: hasMetadata ? 4 : 3,
                   trailing: 8)
        #endif
    }

    // MARK: - Dynamic colors

    /// One color that resolves itself per appearance. SwiftUI resolves these
    /// against the environment it renders in, which includes the appearance
    /// `RootView` forces from Settings.
    private static func dynamic(light: Color, dark: Color) -> Color {
        #if os(iOS)
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(dark) : NSColor(light)
        })
        #endif
    }
}

// MARK: - Typography

extension Font {
    /// Serif display type is the app's loudest identity signal and the one
    /// that costs nothing: New York ships with the system, scales with
    /// Dynamic Type, and separates the voice of a screen from its contents
    /// without a single custom asset. It is used for titles a person reads
    /// once — never for data, labels, or anything they scan.
    static var coveDisplayLarge: Font { .system(.largeTitle, design: .serif).weight(.semibold) }
    static var coveDisplay: Font { .system(.title2, design: .serif).weight(.semibold) }
    static var coveDisplaySmall: Font { .system(.title3, design: .serif).weight(.semibold) }
    static var coveHeadline: Font { .system(.headline, design: .serif) }
}

extension View {
    /// The small tracked capital label above a title or over a section. Its
    /// job is to name the region without competing with the title under it.
    func coveEyebrow(tint: Color? = nil) -> some View {
        self
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.9)
            .foregroundStyle(tint ?? .secondary)
    }
}

// MARK: - Chrome

/// The shared list/form chrome: platform-appropriate grouped style over
/// Cove's own canvas. Every scrolling screen uses this so backgrounds,
/// insets, and separators stay identical across the app.
private struct CoveScrollBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(CoveTheme.canvas)
    }
}

extension View {
    /// Applies Cove's grouped list styling and canvas background.
    func coveListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped).modifier(CoveScrollBackground())
        #else
        self.listStyle(.inset).modifier(CoveScrollBackground())
        #endif
    }

    /// Applies Cove's grouped form styling and canvas background.
    func coveFormStyle() -> some View {
        formStyle(.grouped).modifier(CoveScrollBackground())
    }

    /// Keeps content at a comfortable measure on large windows while
    /// preserving the native edge-to-edge layout on phones. Text that runs
    /// the full width of a maximized Mac window is the single biggest thing
    /// that makes a desktop port feel unconsidered.
    func coveReadableWidth(_ width: CGFloat = 760) -> some View {
        modifier(CoveReadableWidth(maxWidth: width))
    }

    /// The standard failure alert: bound to an optional message, dismissed
    /// by clearing it. Shared so every screen reports errors identically.
    func coveErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Something Went Wrong",
            isPresented: Binding(get: { message.wrappedValue != nil },
                                 set: { if !$0 { message.wrappedValue = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

private struct CoveReadableWidth: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(CoveTheme.canvas)
    }
}

// MARK: - Surfaces

/// A raised surface: warm fill, hairline edge, and a shadow soft enough to
/// suggest paper rather than a floating panel.
struct CoveCardBackground: View {
    var cornerRadius: CGFloat = CoveTheme.cardRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CoveTheme.surface)
            .shadow(color: CoveTheme.ink.opacity(0.06), radius: 14, y: 6)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CoveTheme.hairline, lineWidth: 1)
            }
    }
}

/// The masthead's surface: the card, plus a warm ember wash that fades out
/// before it reaches the content. It is the only gradient in the app, and it
/// exists so the one card at the top of a screen doesn't have to shout with
/// weight or saturation to be read as the header.
private struct CoveMastheadBackground: View {
    var cornerRadius: CGFloat = CoveTheme.cardRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CoveTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [CoveTheme.accent.opacity(0.10),
                                 CoveTheme.accent.opacity(0.02),
                                 .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CoveTheme.hairline, lineWidth: 1)
            }
            .shadow(color: CoveTheme.ink.opacity(0.07), radius: 16, y: 7)
    }
}

// MARK: - Masthead

/// The header card at the top of every main screen: a short accent rule, a
/// tracked eyebrow, a serif title, an optional subtitle, and whatever the
/// screen puts underneath — a stat strip, a capture field, nothing.
///
/// One component rather than three near-identical hand-built cards, because
/// the Notes, Tasks, and Lists tabs are one swipe apart and any drift between
/// their headers reads as three different apps.
struct CoveMasthead<Trailing: View, Content: View>: View {
    let eyebrow: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: CoveTheme.Space.regular) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CoveTheme.Space.snug) {
                    heading
                    trailing()
                }
            } else {
                HStack(alignment: .top, spacing: CoveTheme.Space.snug) {
                    heading
                    Spacer(minLength: 0)
                    trailing()
                }
            }
            content()
        }
        .padding(CoveTheme.Space.loose - 2)
        .background { CoveMastheadBackground() }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            // The rule is the app's one repeated ornament: a mark in the
            // margin, the same width on every screen.
            Capsule()
                .fill(CoveTheme.accent)
                .frame(width: 24, height: 2)
                .padding(.bottom, 3)
                .accessibilityHidden(true)
            Text(eyebrow)
                .coveEyebrow()
            Text(title)
                .font(.coveDisplay)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A masthead with content under the title and no trailing accessory. The
/// mirror case — an accessory and no content — deliberately has no shorthand:
/// two single-trailing-closure inits are ambiguous at the call site, and a
/// header carrying an accessory is the one that reads better spelled out.
extension CoveMasthead where Trailing == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle,
                  trailing: { EmptyView() }, content: content)
    }
}

extension CoveMasthead where Trailing == EmptyView, Content == EmptyView {
    init(eyebrow: String, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle,
                  trailing: { EmptyView() }, content: { EmptyView() })
    }
}

// MARK: - Stats

/// One figure in a masthead's stat strip.
struct CoveStat: Identifiable {
    let value: Int
    let label: String

    var id: String { label }

    init(_ value: Int, _ label: String) {
        self.value = value
        self.label = label
    }
}

/// A row of figures under a masthead, separated by hairlines and set in
/// monospaced digits so the numbers don't shuffle sideways as they change.
struct CoveStatStrip: View {
    let stats: [CoveStat]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: CoveTheme.Space.regular) {
            Rectangle()
                .fill(CoveTheme.hairline)
                .frame(height: 1)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: CoveTheme.Space.snug) {
                    ForEach(stats) { stat in figure(stat) }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        ForEach(stats) { stat in figure(stat) }
                    }
                    VStack(alignment: .leading, spacing: CoveTheme.Space.snug) {
                        ForEach(stats) { stat in figure(stat) }
                    }
                }
            }
        }
    }

    private func figure(_ stat: CoveStat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(stat.value, format: .number)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(stat.label)
                .coveEyebrow()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stat.value) \(stat.label)")
    }
}

// MARK: - Section headers

/// The editorial header over a list section: tracked capitals, an optional
/// count, and room for one trailing control. Shared so a section on the Tasks
/// screen and one in a list detail can't set themselves differently.
struct CoveSectionHeader<Trailing: View>: View {
    let title: String
    var count: Int?
    var tint: Color?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: CoveTheme.Space.tight) {
            Text(title)
                .coveEyebrow(tint: tint)
            if let count {
                Text(count, format: .number)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint ?? .secondary)
                    .opacity(0.65)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .accessibilityElement(children: .combine)
    }
}

extension CoveSectionHeader where Trailing == EmptyView {
    init(_ title: String, count: Int? = nil, tint: Color? = nil) {
        self.init(title: title, count: count, tint: tint) { EmptyView() }
    }
}

// MARK: - Small components

/// Compact branded icon treatment shared by rows and settings sections.
/// Purely decorative: the surrounding row always carries the real label, so
/// the tile is hidden from VoiceOver rather than read out as its symbol name.
/// The tile scales with Dynamic Type so large text sizes stay balanced.
struct CoveIconTile: View {
    let systemName: String
    var tint: Color = CoveTheme.accent

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 14

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: glyph, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background {
                RoundedRectangle(cornerRadius: side * 0.32, style: .continuous)
                    .fill(tint.opacity(0.13))
                    .overlay {
                        RoundedRectangle(cornerRadius: side * 0.32, style: .continuous)
                            .stroke(tint.opacity(0.16), lineWidth: 1)
                    }
            }
            .accessibilityHidden(true)
    }
}

/// A tinted count, the shape the app uses everywhere a row or card reports
/// "how many". Shared because the Tasks masthead and the Lists rows are read
/// side by side, and monospaced so a badge doesn't resize as its number does.
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
            .background(tint.opacity(0.13), in: Capsule())
            .overlay {
                Capsule().stroke(tint.opacity(0.16), lineWidth: 1)
            }
    }
}

/// A warmer, more compact alternative to the platform's generic unavailable
/// view. It is shared across the app so a new vault, an empty list, and a
/// finished task day all feel like Cove states rather than system placeholders.
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

    /// The glyph sits in the same soft ember disc the rest of the app uses
    /// for decorative marks, over a wider halo that keeps it from reading as
    /// a button in the middle of an otherwise empty screen.
    private var emblem: some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(CoveTheme.accent)
            .frame(width: 54, height: 54)
            .background(CoveTheme.accent.opacity(0.12), in: Circle())
            .overlay {
                Circle().stroke(CoveTheme.accent.opacity(0.18), lineWidth: 1)
            }
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

/// The app's in-product mark: a serif `c` cupping a single ember dot — the
/// shape of a sheltered inlet said abstractly, with no water in it.
///
/// It is drawn rather than drawn *from an asset* on purpose. A typographic
/// mark inherits the appearance, scales to any size without a new export, and
/// keeps the brand consistent with the serif titles beside it. Its colors are
/// literal in both appearances because a stamp that inverts is no longer the
/// same stamp.
struct CoveMark: View {
    var size: CGFloat = 34

    private let stamp = Color(red: 0.129, green: 0.114, blue: 0.098)
    private let paper = Color(red: 0.976, green: 0.961, blue: 0.933)
    private let ember = Color(red: 0.851, green: 0.545, blue: 0.267)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [stamp.opacity(0.94), stamp],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
            Text(verbatim: "c")
                .font(.system(size: size * 0.66, weight: .semibold, design: .serif))
                .foregroundStyle(paper)
                .offset(x: -size * 0.04, y: -size * 0.01)
            Circle()
                .fill(ember)
                .frame(width: size * 0.14, height: size * 0.14)
                .offset(x: size * 0.17, y: size * 0.05)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A refresh action with real progress feedback. It prevents accidental
/// duplicate scans and gives VoiceOver an accurate state while work runs.
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

/// Branded backdrop for first-launch, recovery, and loading states: warm
/// paper with a single soft ember light in the upper corner. Two hard-edged
/// circles used to sit here; a screen with nothing else on it is exactly
/// where a decorative shape reads as a stray element rather than as depth.
struct CoveBrandBackground: View {
    var body: some View {
        ZStack {
            CoveTheme.canvas
            RadialGradient(
                colors: [CoveTheme.accent.opacity(0.16), .clear],
                center: .init(x: 0.14, y: 0.04),
                startRadius: 0,
                endRadius: 520)
            RadialGradient(
                colors: [CoveTheme.moss.opacity(0.10), .clear],
                center: .init(x: 0.92, y: 1.02),
                startRadius: 0,
                endRadius: 460)
        }
        .ignoresSafeArea()
    }
}
