import SwiftUI

/// The form behind both adding and editing a charge.
///
/// Subscriptions are entered a handful of times a year and every field is
/// structured, so this is a form rather than a sentence — the opposite call
/// from quick capture, and for the opposite reason. What it keeps from
/// `TaskDraftSheet` is the shape: validation issues shown before anything is
/// written, a confirm button gated on them, and the line round-tripped through
/// the parser on the way out.
struct SubscriptionDraftSheet: View {
    enum Mode {
        case add
        case edit(Subscription)

        var title: String {
            switch self {
            case .add: "New Subscription"
            case .edit: "Edit Subscription"
            }
        }

        var confirmLabel: String {
            switch self {
            case .add: "Add"
            case .edit: "Save"
            }
        }
    }

    let mode: Mode
    /// Existing `##` headings, offered alongside "None" and a new-category
    /// field.
    let categories: [String]
    let onConfirm: (SubscriptionDraft, String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SubscriptionDraft
    /// The cost field is bound to an *optional* so a new subscription opens
    /// with it empty. Bound straight to `draft.amount` it opens showing `0`,
    /// and tapping in puts the caret before that zero — so typing `15` gives
    /// `150`. An empty field is not silently a free subscription either:
    /// saving is gated on this being filled, and `0` remains enterable.
    @State private var amountInput: Decimal?
    @State private var category: String?
    @State private var newCategoryName = ""
    @State private var isAddingCategory = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        mode: Mode,
        categories: [String],
        onConfirm: @escaping (SubscriptionDraft, String?) async throws -> Void
    ) {
        self.mode = mode
        self.categories = categories
        self.onConfirm = onConfirm
        switch mode {
        case .add:
            _draft = State(
                initialValue: SubscriptionDraft(
                    firstChargeDateString: SubscriptionMath.dateString(from: .now)))
            _amountInput = State(initialValue: nil)
            _category = State(initialValue: nil)
        case .edit(let subscription):
            _draft = State(initialValue: SubscriptionDraft(subscription))
            _amountInput = State(initialValue: subscription.cost.amount)
            _category = State(initialValue: subscription.category)
        }
    }

    private var canSave: Bool {
        amountInput != nil && draft.validationIssues.isEmpty
            && !resolvedCategoryIsBlank
    }

    /// The name is the first field, so its problem is named first even when
    /// the cost is also missing — a form that reports its last empty field
    /// sends the reader to the wrong place.
    private var firstIssueMessage: String? {
        if let naming = draft.validationIssues.first(where: {
            $0 == .emptyName || $0 == .unsafeName
        }) {
            return naming.message
        }
        if amountInput == nil { return "A subscription needs a cost." }
        return draft.validationIssues.first?.message
    }

    /// "New Category…" selected but nothing typed into it yet.
    private var resolvedCategoryIsBlank: Bool {
        isAddingCategory
            && newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var resolvedCategory: String? {
        guard isAddingCategory else { return category }
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        TextField("Netflix", text: $draft.name)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Name", systemImage: "textformat")
                    }
                    LabeledContent {
                        TextField(
                            "0.00",
                            value: amountBinding,
                            format: .number.precision(.fractionLength(0...2))
                        )
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                    } label: {
                        Label("Cost", systemImage: "creditcard")
                    }
                    LabeledContent {
                        TextField("USD", text: $draft.currencyCode)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textCase(.uppercase)
                            #if os(iOS)
                                .textInputAutocapitalization(.characters)
                            #endif
                    } label: {
                        Label("Currency", systemImage: "dollarsign.circle")
                    }
                    if let message = firstIssueMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(CoveTheme.alert)
                    }
                } header: {
                    CoveSectionHeader("Subscription")
                }

                Section {
                    Picker(selection: cycleBinding) {
                        ForEach(cycleOptions, id: \.self) { cycle in
                            Text(cycle.displayName).tag(cycle)
                        }
                    } label: {
                        Label("Billing Cycle", systemImage: "repeat")
                    }
                    DatePicker(
                        selection: firstChargeBinding, displayedComponents: .date
                    ) {
                        Label("First Charge", systemImage: "calendar")
                    }
                    Picker(selection: $draft.status) {
                        ForEach(SubscriptionStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    } label: {
                        Label("Status", systemImage: "circle.dashed")
                    }
                } header: {
                    CoveSectionHeader("Billing")
                } footer: {
                    Text(nextChargeFooter)
                }

                Section {
                    Picker(selection: categorySelection) {
                        Text("None").tag(String?.none)
                        ForEach(categories, id: \.self) { name in
                            Text(name).tag(String?.some(name))
                        }
                        Text("New Category…").tag(String?.some(Self.newCategoryTag))
                    } label: {
                        Label("Category", systemImage: "folder")
                    }
                    if isAddingCategory {
                        LabeledContent {
                            TextField("Streaming", text: $newCategoryName)
                                .multilineTextAlignment(.trailing)
                        } label: {
                            Label("Name", systemImage: "textformat")
                        }
                    }
                } header: {
                    CoveSectionHeader("Filing")
                } footer: {
                    Text(
                        "Categories are `##` headings in Subscriptions.md, so you can rearrange them as Markdown too."
                    )
                }
            }
            .disabled(isSaving)
            .coveFormStyle()
            .coveReadableWidth(680)
            .navigationTitle(mode.title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(mode.confirmLabel)
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .coveErrorAlert($errorMessage)
        }
        .interactiveDismissDisabled(isSaving)
        #if os(macOS)
            .frame(minWidth: 400, minHeight: 480)
        #endif
    }

    private static let newCategoryTag = "\u{0}new-category"

    /// What the note will actually say, in the wording the row will use — the
    /// one thing about this sheet that isn't visible from the fields.
    private var nextChargeFooter: String {
        guard draft.validationIssues.isEmpty, amountInput != nil else {
            return "Fix the details above to see when this renews."
        }
        let preview = Subscription(
            fileURL: URL(fileURLWithPath: "/preview"),
            lineNumber: 0,
            name: draft.sanitizedName,
            cost: draft.cost,
            cycle: draft.cycle,
            firstChargeDateString: draft.firstChargeDateString,
            status: draft.status)
        guard draft.status == .active else {
            return "\(draft.status.displayName), so it is left out of your totals."
        }
        guard
            let next = SubscriptionMath.nextChargeDateString(
                for: preview, on: .now)
        else { return "Cove could not work out when this renews." }
        let monthly = SubscriptionPresentation.money(
            SubscriptionMath.monthlyEquivalent(preview),
            currencyCode: draft.normalizedCurrencyCode)
        let renewal = SubscriptionPresentation.renewal(on: next, today: .now)
        let exactness =
            draft.cycle.normalizesExactly ? "" : " (averaged over a year)"
        return "\(renewal). That is \(monthly) per month\(exactness)."
    }

    /// The presets, plus whatever the edited line already carries when it is
    /// something the presets can't express.
    private var cycleOptions: [BillingCycle] {
        var options = BillingCycle.presets
        if !options.contains(draft.cycle) { options.append(draft.cycle) }
        return options
    }

    /// Keeps `draft.amount` in step with the optional field, so validation and
    /// the live footer read one value rather than two that can disagree.
    private var amountBinding: Binding<Decimal?> {
        Binding {
            amountInput
        } set: { newValue in
            amountInput = newValue
            draft.amount = newValue ?? 0
        }
    }

    private var cycleBinding: Binding<BillingCycle> {
        Binding { draft.cycle } set: { draft.cycle = $0 }
    }

    private var firstChargeBinding: Binding<Date> {
        Binding {
            SubscriptionMath.date(from: draft.firstChargeDateString) ?? .now
        } set: { newValue in
            draft.firstChargeDateString = SubscriptionMath.dateString(from: newValue)
        }
    }

    private var categorySelection: Binding<String?> {
        Binding {
            isAddingCategory ? Self.newCategoryTag : category
        } set: { selection in
            if selection == Self.newCategoryTag {
                isAddingCategory = true
            } else {
                isAddingCategory = false
                category = selection
            }
        }
    }

    private func save() {
        guard canSave, !isSaving else { return }
        do {
            _ = try draft.validatedMarkdownLine()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        isSaving = true
        let target = resolvedCategory
        Task {
            do {
                try await onConfirm(draft, target)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
