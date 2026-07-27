import SwiftUI

/// Every recurring charge in `Subscriptions.md`: what they cost per month and
/// per year, what lands soon, and the charges themselves grouped by category.
///
/// Paused and cancelled charges fold away at the bottom and are excluded from
/// every figure, which is the same call the task screens make for completed
/// work — what is finished settles rather than competing with what is live.
struct SubscriptionsView: View {
    @Environment(VaultManager.self) private var vaultManager
    @Environment(\.undoManager) private var undoManager

    @State private var editing: Subscription?
    @State private var isAdding = false
    @State private var pendingDeletion: Subscription?
    /// The category whose heading is being renamed, and the field beside it.
    @State private var renamingCategory: String?
    @State private var categoryNameDraft = ""
    @State private var pendingCategoryDeletion: String?
    @State private var isAddingCategory = false
    @State private var newCategoryName = ""
    @State private var errorMessage: String?
    @State private var isInactiveExpanded = false
    /// Keeps "renews today" and "renews in 4 days" true across midnight while
    /// the screen sits open.
    @State private var now = Date()

    private var subscriptions: [Subscription] { vaultManager.index.subscriptions }

    private var active: [Subscription] {
        subscriptions.filter(\.countsTowardSpending)
    }

    private var inactive: [Subscription] {
        subscriptions.filter { !$0.countsTowardSpending }
    }

    var body: some View {
        list
            .navigationTitle("Subscriptions")
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button {
                            isAdding = true
                        } label: {
                            Label("New Subscription", systemImage: "creditcard")
                        }
                        Button {
                            newCategoryName = ""
                            isAddingCategory = true
                        } label: {
                            Label("New Category", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
                ToolbarItem {
                    CoveRefreshButton { await vaultManager.refresh() }
                }
            }
            .sheet(isPresented: $isAdding) {
                SubscriptionDraftSheet(
                    mode: .add,
                    categories: vaultManager.index.subscriptionCategoryNames
                ) { draft, category in
                    try await vaultManager.addSubscription(draft, into: category)
                }
            }
            .sheet(item: $editing) { subscription in
                SubscriptionDraftSheet(
                    mode: .edit(subscription),
                    categories: vaultManager.index.subscriptionCategoryNames
                ) { draft, category in
                    try await vaultManager.updateSubscription(
                        subscription, to: draft, category: category)
                }
            }
            .confirmationDialog(
                "Delete “\(pendingDeletion?.name ?? "")”?",
                isPresented: $pendingDeletion.covePresence(),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let subscription = pendingDeletion { delete(subscription) }
                }
            } message: {
                Text("This removes the line from Subscriptions.md. You can undo the deletion.")
            }
            .alert("New Category", isPresented: $isAddingCategory) {
                TextField("Streaming", text: $newCategoryName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { createCategory() }
                    .disabled(
                        newCategoryName.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty)
            } message: {
                Text("Categories are `##` headings in Subscriptions.md, so you can rearrange them as Markdown too.")
            }
            .alert(
                "Rename “\(renamingCategory ?? "")”",
                isPresented: $renamingCategory.covePresence()
            ) {
                TextField("Category name", text: $categoryNameDraft)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    if let name = renamingCategory { renameCategory(name) }
                }
                .disabled(
                    categoryNameDraft.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty)
            } message: {
                Text("Every subscription filed under it stays where it is.")
            }
            .confirmationDialog(
                "Delete “\(pendingCategoryDeletion ?? "")”?",
                isPresented: $pendingCategoryDeletion.covePresence(),
                titleVisibility: .visible
            ) {
                Button("Delete Category", role: .destructive) {
                    if let name = pendingCategoryDeletion { deleteCategory(name) }
                }
            } message: {
                Text(deletionMessage(for: pendingCategoryDeletion ?? ""))
            }
            .coveErrorAlert($errorMessage)
            // Editor autosaves don't rescan the vault, so arriving here picks
            // up charges typed by hand.
            .task { await vaultManager.refresh() }
            .coveMinuteTick($now)
    }

    @ViewBuilder
    private var list: some View {
        List {
            if subscriptions.isEmpty {
                Section {
                    // A `Subscriptions.md` in the wrong place is the one empty
                    // state that has a cause worth naming: without this it
                    // reads as "you have no subscriptions" while the file sits
                    // in the vault full of them.
                    if let misplaced = vaultManager.misplacedSubscriptionNoteURL {
                        CoveEmptyState(
                            "Subscriptions.md Is at the Vault Root",
                            systemName: "folder.badge.questionmark",
                            description:
                                "Cove reads subscriptions from Trackers/Subscriptions.md. Move this note into a “Trackers” folder at the top of your vault and it will be picked up."
                        ) {
                            NavigationLink(value: misplaced) {
                                Text("Open the Note")
                            }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(
                                .roundedRectangle(radius: CoveTheme.fieldRadius))
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        CoveEmptyState(
                            "Nothing Tracked Yet",
                            systemName: "creditcard",
                            description: "Add what you pay for on a schedule and Cove keeps the monthly and yearly totals."
                        ) {
                            Button("New Subscription") { isAdding = true }
                                .buttonStyle(.borderedProminent)
                                .buttonBorderShape(
                                    .roundedRectangle(radius: CoveTheme.fieldRadius))
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            } else {
                Section {
                    overview
                        .listRowInsets(CoveTheme.headerRowInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                spendChartSection
                upcomingSection
                ForEach(categoryGroups, id: \.name) { group in
                    Section {
                        if group.subscriptions.isEmpty {
                            Text("Nothing filed here yet.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, CoveTheme.Space.rowPadding)
                        }
                        ForEach(group.subscriptions) { subscription in
                            row(for: subscription)
                        }
                    } header: {
                        // Uncategorized is not a heading in the file, so there
                        // is nothing there to rename or remove.
                        if let name = group.name {
                            CoveSectionHeader(
                                title: name,
                                count: group.subscriptions.count
                            ) {
                                categoryMenu(for: name)
                            }
                        } else {
                            CoveSectionHeader(
                                "Uncategorized",
                                count: group.subscriptions.count)
                        }
                    }
                }
                if !inactive.isEmpty {
                    Section {
                        if isInactiveExpanded {
                            ForEach(inactive) { subscription in
                                row(for: subscription, showsCategory: true)
                            }
                        }
                    } header: {
                        CoveSectionHeader(
                            "Paused & Cancelled",
                            count: inactive.count,
                            isExpanded: $isInactiveExpanded)
                    }
                }
            }
        }
        .coveListStyle()
        .coveReadableWidth()
    }

    // MARK: - Overview

    /// One strip per currency, because nothing is ever converted. With a
    /// single currency — the ordinary case — that is one strip and the code is
    /// never mentioned.
    private var overview: some View {
        let totals = SubscriptionMath.totals(for: active)
        let isExact = SubscriptionMath.totalsAreExact(active)
        return CovePanel(eyebrow: "Overview") {
            if totals.isEmpty {
                Text("Nothing active.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: CoveTheme.Space.regular) {
                    ForEach(totals) { total in
                        VStack(alignment: .leading, spacing: CoveTheme.Space.tight) {
                            if totals.count > 1 {
                                Text(total.currencyCode).coveEyebrow()
                            }
                            CoveStatStrip(stats: [
                                CoveStat(total.subscriptionCount, "Active"),
                                CoveStat(
                                    SubscriptionPresentation.money(
                                        total.monthly,
                                        currencyCode: total.currencyCode),
                                    "Per Month"),
                                CoveStat(
                                    SubscriptionPresentation.money(
                                        total.yearly,
                                        currencyCode: total.currencyCode),
                                    "Per Year"),
                            ])
                        }
                    }
                    // Weekly and daily cycles have no whole-number monthly
                    // answer, so the screen says so rather than implying a
                    // statement will match.
                    if !isExact {
                        Text("Weekly and daily charges are averaged over a year.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Categories

    /// A category header's own actions. The header is not collapsible, so it
    /// can carry a control — the rule against that applies to collapsible
    /// headers, where the whole row has to stay one button.
    private func categoryMenu(for name: String) -> some View {
        Menu {
            Button {
                categoryNameDraft = name
                renamingCategory = name
            } label: {
                Label("Rename Category", systemImage: "pencil")
            }
            Button(role: .destructive) {
                pendingCategoryDeletion = name
            } label: {
                Label("Delete Category", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(name) category options")
    }

    private func categoryCount(_ name: String) -> Int {
        subscriptions.filter {
            $0.category.map(TaskListDocument.canonicalName)
                == TaskListDocument.canonicalName(name)
        }.count
    }

    private func deletionMessage(for name: String) -> String {
        let count = categoryCount(name)
        guard count > 0 else {
            return "This removes the empty “\(name)” heading from Subscriptions.md. You can undo it."
        }
        return
            "This removes the heading and the \(count) subscription\(count == 1 ? "" : "s") filed under it from Subscriptions.md. To keep them, set each one's Category to None first. You can undo the deletion."
    }

    private func createCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await vaultManager.createSubscriptionCategory(named: name)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func renameCategory(_ name: String) {
        let newName = categoryNameDraft.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        Task {
            do {
                try await vaultManager.renameSubscriptionCategory(
                    named: name, to: newName)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteCategory(_ name: String) {
        Task {
            do {
                let record = try await vaultManager.deleteSubscriptionCategory(
                    named: name)
                undoManager?.registerUndo(withTarget: vaultManager) { manager in
                    Task {
                        do {
                            try await manager.restoreDeletedSubscriptionCategory(
                                record)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                undoManager?.setActionName("Delete Category")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Charts

    /// Charted in the leading currency only. Nothing is ever converted, so
    /// bars from two currencies on one axis would be a comparison that isn't
    /// one — the totals panel above already reports each currency separately.
    @ViewBuilder
    private var spendChartSection: some View {
        if let leading = SubscriptionMath.totals(for: active).first {
            let bars = SubscriptionMath.spendBars(
                for: active, currencyCode: leading.currencyCode)
            // One bar is not a comparison.
            if bars.count > 1 {
                Section {
                    SubscriptionSpendChart(
                        bars: bars, currencyCode: leading.currencyCode)
                        .padding(.vertical, CoveTheme.Space.tight)
                } header: {
                    CoveSectionHeader("Cost Per Month")
                }
            }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        let charges = SubscriptionMath.upcomingCharges(
            for: active, within: 30, on: now)
        if !charges.isEmpty {
            Section {
                ForEach(charges) { charge in
                    upcomingRow(charge)
                }
            } header: {
                CoveSectionHeader("Next 30 Days", count: charges.count)
            }
        }
    }

    private func upcomingRow(
        _ charge: SubscriptionMath.UpcomingCharge
    ) -> some View {
        CoveRow(systemName: "calendar", tint: CoveTheme.moss) {
            VStack(alignment: .leading, spacing: 3) {
                Text(charge.subscription.name)
                    .font(.body)
                    .lineLimit(1)
                CoveDueLabel(
                    text: SubscriptionPresentation.renewal(
                        on: charge.dateString, today: now),
                    tint: SubscriptionPresentation.isImminent(
                        charge.dateString, today: now)
                        ? CoveTheme.accent : .secondary)
            }
            Spacer(minLength: CoveTheme.Space.tight)
            Text(SubscriptionPresentation.money(charge.subscription.cost))
                .font(.subheadline.weight(.medium).monospacedDigit())
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Rows

    /// Categories in the note's heading order, with uncategorized charges
    /// first — they sit above the first `##` in the file, so that is where
    /// they read.
    private var categoryGroups: [(name: String?, subscriptions: [Subscription])] {
        let ordered = active.sorted {
            SubscriptionMath.monthlyEquivalent($0)
                == SubscriptionMath.monthlyEquivalent($1)
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : SubscriptionMath.monthlyEquivalent($0)
                    > SubscriptionMath.monthlyEquivalent($1)
        }
        var groups: [(name: String?, subscriptions: [Subscription])] = []
        let uncategorized = ordered.filter { $0.category == nil }
        if !uncategorized.isEmpty {
            groups.append((nil, uncategorized))
        }
        // Every heading in the note, filled or not — a category created but
        // not yet used still exists, the same way an empty list does, and it
        // has to be on screen to be renamed or removed.
        for name in vaultManager.index.subscriptionCategoryNames {
            let members = ordered.filter {
                $0.category.map(TaskListDocument.canonicalName)
                    == TaskListDocument.canonicalName(name)
            }
            groups.append((name, members))
        }
        return groups
    }

    private func row(
        for subscription: Subscription,
        showsCategory: Bool = false
    ) -> some View {
        Button {
            editing = subscription
        } label: {
            SubscriptionRow(
                subscription: subscription, now: now, showsCategory: showsCategory)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDeletion = subscription
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        // macOS has no swipe, and the swipe is invisible until it is tried.
        .contextMenu {
            Button {
                editing = subscription
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            ForEach(statusActions(for: subscription), id: \.self) { status in
                Button {
                    setStatus(status, on: subscription)
                } label: {
                    Label(
                        statusActionLabel(status),
                        systemImage: statusActionGlyph(status))
                }
            }
            Divider()
            Button(role: .destructive) {
                pendingDeletion = subscription
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func statusActions(for subscription: Subscription) -> [SubscriptionStatus] {
        SubscriptionStatus.allCases.filter { $0 != subscription.status }
    }

    private func statusActionLabel(_ status: SubscriptionStatus) -> String {
        switch status {
        case .active: "Reactivate"
        case .paused: "Pause"
        case .cancelled: "Mark Cancelled"
        }
    }

    private func statusActionGlyph(_ status: SubscriptionStatus) -> String {
        switch status {
        case .active: "play"
        case .paused: "pause"
        case .cancelled: "xmark"
        }
    }

    // MARK: - Actions

    private func setStatus(
        _ status: SubscriptionStatus,
        on subscription: Subscription
    ) {
        Task {
            do {
                try await vaultManager.setSubscriptionStatus(
                    subscription, to: status)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ subscription: Subscription) {
        Task {
            do {
                let record = try await vaultManager.deleteSubscription(subscription)
                registerDeletionUndo(record)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func registerDeletionUndo(_ record: DeletedSubscriptionRecord) {
        undoManager?.registerUndo(withTarget: vaultManager) { manager in
            Task {
                do {
                    try await manager.restoreDeletedSubscription(record)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        undoManager?.setActionName("Delete Subscription")
    }
}
