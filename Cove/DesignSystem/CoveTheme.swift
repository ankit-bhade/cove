import SwiftUI

/// Cove's visual system: a small set of tokens every screen is assembled
/// from. Reusable views live beside these tokens in the DesignSystem folder.
///
/// The palette is **ink on warm paper, marked in ember**. A notes app is a
/// page before it is anything else, so the canvas is an unbleached warm
/// off-white rather than a cool system gray, text sits on it as warm ink, and
/// exactly one saturated hue — a burnt ember — carries interaction and
/// emphasis. Moss is the single supporting hue, reserved for containers
/// (folders, destinations), and a warm rust carries lateness.
///
/// Every token is a dynamic color that resolves itself against the current
/// appearance, so nested views cannot disagree about the active appearance.
enum CoveTheme {

    // MARK: - Palette

    static let canvas = dynamic(
        light: Color(red: 0.965, green: 0.953, blue: 0.933),
        dark: Color(red: 0.086, green: 0.082, blue: 0.075)
    )

    static let surface = dynamic(
        light: Color(red: 1.000, green: 0.992, blue: 0.976),
        dark: Color(red: 0.125, green: 0.118, blue: 0.106)
    )

    static let ink = dynamic(
        light: Color(red: 0.141, green: 0.129, blue: 0.114),
        dark: Color(red: 0.949, green: 0.933, blue: 0.906)
    )

    static let accent = dynamic(
        light: Color(red: 0.620, green: 0.345, blue: 0.153),
        dark: Color(red: 0.878, green: 0.635, blue: 0.392)
    )

    static let moss = dynamic(
        light: Color(red: 0.337, green: 0.420, blue: 0.306),
        dark: Color(red: 0.639, green: 0.702, blue: 0.580)
    )

    static let alert = dynamic(
        light: Color(red: 0.698, green: 0.227, blue: 0.169),
        dark: Color(red: 0.910, green: 0.475, blue: 0.416)
    )

    static let hairline = dynamic(
        light: Color(red: 0.141, green: 0.129, blue: 0.114).opacity(0.12),
        dark: .white.opacity(0.10)
    )

    /// The fill behind an editable field sunk into a panel.
    ///
    /// It was `canvas`, which is the right idea in light — a well cut into the
    /// lighter `surface` reads as a place to put something — and exactly wrong
    /// in dark, where the canvas is *darker* than the surface it sits in by
    /// four points of luminance. An empty capture field and its placeholder all
    /// but vanished into the panel. In dark the well is therefore lifted above
    /// the surface instead of sunk below it: the direction flips, the idea
    /// doesn't, and the field is visible before anything is typed in it.
    static let field = dynamic(
        light: Color(red: 0.965, green: 0.953, blue: 0.933),
        dark: Color(red: 0.184, green: 0.176, blue: 0.161)
    )

    /// A field's edge, a step stronger than `hairline`. A hairline is enough
    /// to separate two surfaces that already differ; the edge of an empty
    /// control is the only thing saying it is there at all.
    static let fieldStroke = dynamic(
        light: Color(red: 0.141, green: 0.129, blue: 0.114).opacity(0.18),
        dark: .white.opacity(0.22)
    )

    // MARK: - Metrics

    enum Space {
        static let tight: CGFloat = 6
        static let snug: CGFloat = 10
        static let regular: CGFloat = 16
        static let loose: CGFloat = 22

        /// The width of a row's leading glyph column, the gap between it and
        /// what it labels, and the breathing room above and below that row.
        /// Every list in the app is read against the one directly before it in
        /// the tab bar, so these three numbers are the app's grid — a row that
        /// picks its own is a row that visibly doesn't line up with its
        /// neighbours. The column is a `@ScaledMetric` base at both call
        /// sites, so it grows with Dynamic Type in step.
        static let rowGlyph: CGFloat = 32
        static let rowGap: CGFloat = 12
        static let rowPadding: CGFloat = 4
    }

    static let cardRadius: CGFloat = 18
    static let fieldRadius: CGFloat = 12

    /// Every tinted surface in the app — an icon tile, a count badge, the
    /// recovery emblem, an editor banner — is the same two values: a wash of the hue
    /// with a hairline of the same hue a little stronger over it. Held as
    /// tokens because hand-tuned pairs drift, and a screen carrying three
    /// tints at three strengths reads as three components rather than one.
    enum Tint {
        static let fill: Double = 0.12
        static let stroke: Double = 0.18
    }

    /// The insets a masthead or a panel takes as the first row of a list:
    /// no side padding, since the card already draws its own edge.
    static func headerRowInsets() -> EdgeInsets {
        EdgeInsets(top: 6, leading: 0, bottom: 10, trailing: 0)
    }

    /// The insets a group heading takes when it sits *inside* one continuous
    /// list surface rather than above a card of its own.
    ///
    /// A screen whose groups are each their own inset-grouped section is a
    /// stack of soft capsules inside the platform's own rounded chrome, and
    /// every gap between two of them costs a row of what fits above the fold.
    /// Set as rows within a single section the headings divide the list
    /// without breaking it, and the space they take is this rather than the
    /// system's section spacing: room above to separate a group from the one
    /// before it, almost none below, since the heading belongs to the rows
    /// under it.
    ///
    /// `isLast` is for a folded heading that ends the surface — a collapsed
    /// Done section is a header with nothing beneath it, and with the rows
    /// gone there is nothing left to hold it off the card's bottom corner.
    static func groupHeaderRowInsets(isFirst: Bool = false, isLast: Bool = false) -> EdgeInsets {
        EdgeInsets(
            top: isFirst ? 7 : 16,
            leading: Space.regular,
            bottom: isLast ? 11 : 0,
            trailing: Space.regular)
    }

    /// The gap between two list sections, on every iOS list in the app.
    ///
    /// The system's own is around 35pt, which is a lot of empty canvas to
    /// spend saying that a panel and the list under it are two things — and on
    /// the screen the app opens on it is spent twice before the first task.
    /// Sections that genuinely differ (a chart, then charges, then categories)
    /// still read as separate at this; what it stops paying for is the
    /// distance between a screen's header card and the screen.
    ///
    /// It is set once in `coveListStyle` rather than per screen. The two task
    /// screens once asked for `.listSectionSpacing(.compact)` on their own and
    /// it was removed for exactly that reason: a section gap that changes
    /// between tabs is felt before it is seen.
    static let sectionSpacing: CGFloat = 18

    // MARK: - Dynamic colors

    private static func dynamic(light: Color, dark: Color) -> Color {
        #if os(iOS)
            Color(
                UIColor { traits in
                    traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
                })
        #else
            Color(
                NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                        ? NSColor(dark) : NSColor(light)
                })
        #endif
    }
}

// MARK: - Typography

extension Font {
    static var coveDisplayLarge: Font { .system(.largeTitle, design: .serif).weight(.semibold) }
    static var coveDisplay: Font { .system(.title2, design: .serif).weight(.semibold) }
    static var coveDisplaySmall: Font { .system(.title3, design: .serif).weight(.semibold) }
    static var coveHeadline: Font { .system(.headline, design: .serif) }
}

extension View {
    /// Fills a shape with a wash of `tint` and traces it with a hairline of
    /// the same hue, at the one strength the whole app uses.
    func coveTintedSurface<S: InsettableShape>(_ tint: Color, in shape: S) -> some View {
        background(tint.opacity(CoveTheme.Tint.fill), in: shape)
            .overlay {
                shape.stroke(tint.opacity(CoveTheme.Tint.stroke), lineWidth: 1)
            }
    }

    /// Tracked capitals, and **only for a heading that names a region of the
    /// screen**: a section header, a panel's own label, the sidebar's tagline.
    ///
    /// It used to carry everything that was not body text — stat names, row
    /// captions, a per-month suffix — which meant QUICK CAPTURE, OVERDUE,
    /// COLLECTIONS, LISTS, OPEN, DONE and 2 ITEMS all spoke in one voice on one
    /// screen. A style that marks everything marks nothing, so what is under a
    /// heading now speaks a step quieter; see `coveMetaLabel`.
    func coveEyebrow(tint: Color? = nil) -> some View {
        self
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.9)
            .foregroundStyle(tint ?? .secondary)
    }

    /// A secondary label — a stat's name, a row's caption, a unit suffix — in
    /// the reader's own sentence case. Quiet by design: it sits under
    /// something that already said what this region is.
    func coveMetaLabel() -> some View {
        self
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Chrome

private struct CoveScrollBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(CoveTheme.canvas)
    }
}

/// The canvas under a list, its section spacing, and its row-height floor.
private struct CoveListMetrics: ViewModifier {
    func body(content: Content) -> some View {
        sectionSpaced(content)
            // A list row is 44pt tall whatever is in it. That floor is right
            // for a row you can tap and wrong for a group heading set inside a
            // continuous surface: a line of caption text got 30pt of padding
            // the row's own insets cannot take back, which handed most of the
            // saving from merging the sections straight back. Removing the
            // floor changes nothing else here — every other row in the app is
            // past 44 from its own content and the system's insets before the
            // floor is consulted, and the only rows under it are the headings
            // this is for.
            .environment(\.defaultMinListRowHeight, 0)
            .modifier(CoveScrollBackground())
    }

    /// `listSectionSpacing` is unavailable in AppKit — a macOS `.inset` list
    /// draws no card per section for it to space out. The gap it tightens is
    /// an iOS one, so it is applied where it exists and the macOS list keeps
    /// what it already had.
    @ViewBuilder
    private func sectionSpaced(_ content: Content) -> some View {
        #if os(iOS)
            content.listSectionSpacing(CoveTheme.sectionSpacing)
        #else
            content
        #endif
    }
}

extension View {
    func coveListStyle() -> some View {
        #if os(iOS)
            self.listStyle(.insetGrouped)
                .modifier(CoveListMetrics())
        #else
            self.listStyle(.inset)
                .modifier(CoveListMetrics())
        #endif
    }

    func coveFormStyle() -> some View {
        formStyle(.grouped).modifier(CoveScrollBackground())
    }

    func coveReadableWidth(_ width: CGFloat = 760) -> some View {
        modifier(CoveReadableWidth(maxWidth: width))
    }

    func coveErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Something Went Wrong",
            isPresented: message.covePresence()
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

extension Binding {
    /// Optional state as the `Bool` every `isPresented:` wants: present while
    /// the value is non-nil, and cleared when the presentation dismisses.
    ///
    /// Alerts, dialogs, and sheets throughout the app are driven by optional
    /// state — the item being renamed, deleted, or reported. Written inline
    /// each time, the getter and the setter are two lines that must agree at
    /// every call site; here they agree once.
    ///
    /// `Wrapped: Sendable` is what keeps the returned binding's `@Sendable`
    /// accessors clean under strict concurrency; every optional this drives is
    /// a value type already.
    func covePresence<Wrapped: Sendable>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { if !$0 { wrappedValue = nil } }
        )
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
