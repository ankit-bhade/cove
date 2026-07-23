import SwiftUI

/// Cove's small, dependency-free visual system. The palette is derived from
/// the moon-and-waves app icon so every screen feels part of the same product.
enum CoveTheme {
    static let navy = Color(red: 0.055, green: 0.207, blue: 0.320)
    static let deepTeal = Color(red: 0.055, green: 0.365, blue: 0.430)
    static let teal = Color(red: 0.129, green: 0.529, blue: 0.612)
    static let seaGlass = Color(red: 0.510, green: 0.710, blue: 0.750)

    static let brandGradient = LinearGradient(
        colors: [navy, deepTeal, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// A quieter wash for dashboard cards. It keeps the brand visible
    /// without lowering text contrast or making every card feel like a button.
    static func heroGradient(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [deepTeal.opacity(0.28), surface(for: scheme), teal.opacity(0.10)]
                : [seaGlass.opacity(0.24), .white, teal.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.035, green: 0.055, blue: 0.070)
            : Color(red: 0.955, green: 0.975, blue: 0.975)
    }

    static func surface(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.075, green: 0.100, blue: 0.115)
            : .white
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .dark ? .white.opacity(0.09) : navy.opacity(0.10)
    }

    /// Custom cards inside grouped lists should use the grouped section's
    /// own horizontal bounds. Adding another inset makes them visibly
    /// narrower than the native rows and controls around them.
    static func dashboardRowInsets(bottom: CGFloat = 14) -> EdgeInsets {
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
}

/// The shared list/form chrome: platform-appropriate grouped style over
/// Cove's own canvas. Every scrolling screen uses this so backgrounds,
/// insets, and separators stay identical across the app.
private struct CoveScrollBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(CoveTheme.canvas(for: colorScheme))
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

    /// Keeps dashboard content comfortable on large windows while preserving
    /// the native edge-to-edge layout on phones.
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
    @Environment(\.colorScheme) private var colorScheme
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(CoveTheme.canvas(for: colorScheme))
    }
}

/// A reusable raised surface used for dashboard-style cards.
struct CoveCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CoveTheme.surface(for: colorScheme))
            .shadow(color: CoveTheme.navy.opacity(colorScheme == .dark ? 0.14 : 0.08),
                    radius: 18, y: 8)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CoveTheme.border(for: colorScheme), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(.white.opacity(colorScheme == .dark ? 0.06 : 0.50))
                    .frame(height: 1)
                    .padding(.horizontal, cornerRadius)
            }
    }
}

/// The emphasized card used once at the top of a dashboard. The restrained
/// gradient separates overview content from ordinary rows while staying
/// equally legible in light and dark appearances.
struct CoveHeroCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var cornerRadius: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(CoveTheme.heroGradient(for: colorScheme))
            .shadow(color: CoveTheme.navy.opacity(colorScheme == .dark ? 0.18 : 0.10),
                    radius: 20, y: 9)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CoveTheme.teal.opacity(colorScheme == .dark ? 0.20 : 0.12),
                            lineWidth: 1)
            }
    }
}

/// A decorative symbol used at the leading edge of dashboard headlines and
/// empty states. Its layered treatment gives the app a recognizable visual
/// motif without relying on custom illustrations.
struct CoveHeroIcon: View {
    let systemName: String
    var tint: Color = CoveTheme.teal
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: Circle())
            .overlay {
                Circle().stroke(tint.opacity(0.16), lineWidth: 1)
            }
            .accessibilityHidden(true)
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
        VStack(spacing: 14) {
            CoveHeroIcon(systemName: systemName, size: 54)
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 30)
        .accessibilityElement(children: .contain)
    }
}

extension CoveEmptyState where Actions == EmptyView {
    init(_ title: String, systemName: String, description: String) {
        self.init(title, systemName: systemName, description: description) {
            EmptyView()
        }
    }
}

/// Compact branded icon treatment shared by rows and settings sections.
/// Purely decorative: the surrounding row always carries the real label, so
/// the tile is hidden from VoiceOver rather than read out as its symbol name.
/// The tile scales with Dynamic Type so large text sizes stay balanced.
struct CoveIconTile: View {
    let systemName: String
    var tint: Color = CoveTheme.teal

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 14

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: glyph, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: side * 0.3,
                                             style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A tinted count, the shape the app uses everywhere a row or card reports
/// "how many". Shared because the Tasks card and the Lists rows are read
/// side by side — a bare `Label` with a `circle.fill` glyph read as a stray
/// bullet next to its own text rather than as the badge beside it.
struct CoveCountBadge: View {
    let text: String
    var tint: Color = CoveTheme.teal

    init(_ text: String, tint: Color = CoveTheme.teal) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
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

/// Branded backdrop for first-launch, recovery, and loading states.
struct CoveBrandBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            CoveTheme.canvas(for: colorScheme)
            Circle()
                .fill(CoveTheme.seaGlass.opacity(colorScheme == .dark ? 0.08 : 0.16))
                .frame(width: 420, height: 420)
                .offset(x: -190, y: -260)
            Circle()
                .fill(CoveTheme.teal.opacity(colorScheme == .dark ? 0.08 : 0.12))
                .frame(width: 340, height: 340)
                .offset(x: 210, y: 300)
        }
        .ignoresSafeArea()
    }
}
