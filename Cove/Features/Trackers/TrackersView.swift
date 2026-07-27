import SwiftUI

/// The things Cove tracks that are not tasks.
///
/// Today that is one row. The hub exists anyway because it is the cheap half
/// of the decision: a second tracker becomes a row and a `Destination` case
/// rather than a sixth tab — and iOS collapses a tab bar into "More" past
/// five, so Trackers takes the last slot there is.
///
/// The abstraction stops here, deliberately. Below this screen everything is
/// subscription-specific — the file format, the parser, the arithmetic, the
/// views — the same way Lists and Tasks are concrete. A generic tracker engine
/// built for one tracker would be ceremony, which is what this project removes
/// rather than accumulates.
///
/// **The hub carries no overview panel, and that is the same restraint.** It
/// had one: tracked count, spend per month, spend per year. Every figure in it
/// was a *subscription* figure, so a second tracker would have had to either
/// go missing from it or force the panel to special-case each kind — and a
/// weight or reading tracker has no monthly dollar total to contribute at all.
/// It also restated the row directly beneath it, which is the exact fault that
/// cost `CoveMasthead` its place on every other screen. A tracker's numbers
/// belong to that tracker; the hub's job is to say which trackers exist, and
/// each row says its own summary.
///
/// The Lists overview is not the same case and keeps its panel: every list is
/// the same kind of thing, so summing them means something.
struct TrackersView: View {
    @Environment(VaultManager.self) private var vaultManager

    private enum Destination: Hashable {
        case subscriptions
    }

    var body: some View {
        NavigationStack {
            // One section, no header: the navigation title above already says
            // "Trackers", and an eyebrow never repeats it.
            List {
                NavigationLink(value: Destination.subscriptions) {
                    CoveRow(systemName: "creditcard", tint: CoveTheme.moss) {
                        CoveRowTitle(
                            title: "Subscriptions",
                            caption: SubscriptionPresentation.hubCaption(
                                for: vaultManager.index.subscriptions))
                        Spacer(minLength: 0)
                        if activeCount > 0 {
                            CoveCountBadge("\(activeCount)")
                        }
                    }
                }
            }
            .coveListStyle()
            .coveReadableWidth()
            .navigationTitle("Trackers")
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .subscriptions: SubscriptionsView()
                }
            }
            .navigationDestination(for: NoteDestination.self) { destination in
                EditorView(destination)
            }
        }
    }

    private var activeCount: Int {
        vaultManager.index.subscriptions.filter(\.countsTowardSpending).count
    }
}
