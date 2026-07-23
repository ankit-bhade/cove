import SwiftUI

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
