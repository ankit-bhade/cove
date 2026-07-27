#if os(iOS)
    import SwiftUI
    import UIKit

    /// Live-styled Markdown `UITextView` wrapper for the editor. The text stays
    /// plain Markdown; `MarkdownStyler` reapplies attributes after every change,
    /// and a tap on a `- [ ]` marker toggles the checkbox.
    struct MarkdownTextView: UIViewRepresentable {
        @Binding var text: String
        let sectionedTaskDocument: Bool
        @Binding var checkboxError: String?
        /// A line to put the caret on and scroll into view, consumed once.
        /// Set by whoever opened the note at a line — a search hit, a task
        /// row, a format warning — and cleared here so a later redraw can't
        /// yank the reader back to it after they have scrolled away.
        @Binding var focusLine: Int?

        func makeUIView(context: Context) -> UITextView {
            let textView = CheckboxTogglingTextView()
            textView.delegate = context.coordinator
            textView.adjustsFontForContentSizeCategory = true
            textView.backgroundColor = .clear
            textView.alwaysBounceVertical = true
            textView.keyboardDismissMode = .interactive
            textView.textContainerInset = UIEdgeInsets(top: 28, left: 24, bottom: 40, right: 24)
            textView.textContainer.lineFragmentPadding = 0
            // Smart punctuation rewrites Markdown syntax (straight quotes, "--"),
            // so it stays off.
            textView.smartQuotesType = .no
            textView.smartDashesType = .no
            textView.typingAttributes = MarkdownStyler.bodyAttributes
            textView.text = text
            MarkdownStyler.applyLiveStyles(to: textView.textStorage)
            context.coordinator.textView = textView

            let tap = UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            tap.delegate = context.coordinator
            textView.addGestureRecognizer(tap)
            textView.accessibilityCustomActions = [
                UIAccessibilityCustomAction(
                    name: "Toggle checkbox at cursor",
                    target: context.coordinator,
                    selector: #selector(Coordinator.toggleCheckboxAtCursor))
            ]
            textView.toggleCheckboxHandler = { [weak coordinator = context.coordinator] in
                coordinator?.toggleCheckboxAtCursor() ?? false
            }
            return textView
        }

        func updateUIView(_ textView: UITextView, context: Context) {
            if textView.text != text {
                textView.text = text
                MarkdownStyler.applyLiveStyles(to: textView.textStorage)
            }
            guard let focusLine else { return }
            // Deferred for two reasons: scrolling to a range the text view
            // has not laid out yet does nothing, and clearing the binding
            // inside `updateUIView` is a state mutation during a view update.
            DispatchQueue.main.async {
                self.focusLine = nil
                guard
                    let range = MarkdownParser.range(
                        ofLine: focusLine, in: textView.text)
                else { return }
                textView.selectedRange = NSRange(
                    location: range.location, length: 0)
                Self.scroll(textView, toShow: range)
            }
        }

        /// Puts the line a third of the way down the visible area rather than
        /// just barely inside it.
        ///
        /// `scrollRangeToVisible` scrolls the least it can, which lands the
        /// line hard against the bottom edge — underneath the tab bar on a
        /// phone, and with none of the surrounding note visible either way.
        /// The point of opening at a line is to be able to read it in context.
        ///
        /// The rect comes from `UITextInput` rather than the layout manager,
        /// since touching `layoutManager` drops a `UITextView` into TextKit 1
        /// compatibility for the rest of its life.
        private static func scroll(_ textView: UITextView, toShow range: NSRange) {
            guard
                let start = textView.position(
                    from: textView.beginningOfDocument, offset: range.location),
                let end = textView.position(from: start, offset: range.length),
                let textRange = textView.textRange(from: start, to: end)
            else {
                textView.scrollRangeToVisible(range)
                return
            }
            let rect = textView.firstRect(for: textRange)
            guard !rect.isNull, !rect.isInfinite, rect.minY.isFinite else {
                textView.scrollRangeToVisible(range)
                return
            }
            let inset = textView.adjustedContentInset
            let visibleHeight = textView.bounds.height - inset.top - inset.bottom
            let minimum = -inset.top
            let maximum = max(
                minimum,
                textView.contentSize.height + inset.bottom - textView.bounds.height)
            let target = rect.minY - visibleHeight / 3 - inset.top
            textView.setContentOffset(
                CGPoint(x: 0, y: min(max(target, minimum), maximum)),
                animated: false)
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(
                text: $text,
                sectionedTaskDocument: sectionedTaskDocument,
                checkboxError: $checkboxError)
        }

        final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
            private let text: Binding<String>
            private let sectionedTaskDocument: Bool
            private let checkboxError: Binding<String?>
            weak var textView: UITextView?
            private var dirtyRange: NSRange?

            init(
                text: Binding<String>,
                sectionedTaskDocument: Bool,
                checkboxError: Binding<String?>
            ) {
                self.text = text
                self.sectionedTaskDocument = sectionedTaskDocument
                self.checkboxError = checkboxError
            }

            func textView(
                _ textView: UITextView,
                shouldChangeTextIn range: NSRange,
                replacementText replacement: String
            ) -> Bool {
                let edited = NSRange(
                    location: range.location,
                    length: max(
                        range.length,
                        (replacement as NSString).length))
                if let current = dirtyRange {
                    dirtyRange = NSUnionRange(current, edited)
                } else {
                    dirtyRange = edited
                }
                return true
            }

            func textViewDidChange(_ textView: UITextView) {
                text.wrappedValue = textView.text
                // Restyling during multistage input (e.g. Japanese IME) would
                // break the composition, so wait until it commits.
                guard textView.markedTextRange == nil else { return }
                MarkdownStyler.applyLiveStyles(
                    to: textView.textStorage,
                    dirtyRange: dirtyRange ?? textView.selectedRange)
                dirtyRange = nil
            }

            @objc func handleTap(_ gesture: UITapGestureRecognizer) {
                guard let textView = gesture.view as? UITextView else { return }
                let point = gesture.location(in: textView)
                guard let position = textView.closestPosition(to: point) else { return }
                let index = textView.offset(from: textView.beginningOfDocument, to: position)
                guard let checkbox = MarkdownParser.parse(textView.text).checkbox(at: index) else {
                    return
                }
                _ = toggleCheckbox(in: textView, checkbox: checkbox)
            }

            @objc func toggleCheckboxAtCursor() -> Bool {
                guard let textView,
                    let checkbox = MarkdownParser.parse(textView.text)
                        .checkboxes.first(where: {
                            NSLocationInRange(
                                textView.selectedRange.location,
                                $0.markerRange)
                                || $0.markerRange.location <= textView.selectedRange.location
                                    && textView.selectedRange.location <= NSMaxRange($0.textRange)
                        })
                else { return false }
                return toggleCheckbox(in: textView, checkbox: checkbox)
            }

            @discardableResult
            private func toggleCheckbox(
                in textView: UITextView,
                checkbox: MarkdownParser.Checkbox
            ) -> Bool {
                if let result = MarkdownParser.recurringTaskToggleResult(
                    for: checkbox,
                    in: textView.text,
                    sectioned: sectionedTaskDocument)
                {
                    switch result {
                    case .success(let updated):
                        checkboxError.wrappedValue = nil
                        setDocumentText(in: textView, to: updated)
                        return true
                    case .failure(let error):
                        checkboxError.wrappedValue =
                            error.localizedDescription
                        return false
                    }
                }
                checkboxError.wrappedValue = nil
                setCheckbox(
                    in: textView,
                    range: checkbox.statusRange,
                    status: checkbox.toggledStatus)
                return true
            }

            private func setCheckbox(
                in textView: UITextView,
                range: NSRange,
                status: String
            ) {
                let previous = (textView.text as NSString).substring(with: range)
                textView.undoManager?.registerUndo(withTarget: self) { coordinator in
                    coordinator.setCheckbox(in: textView, range: range, status: previous)
                }
                textView.undoManager?.setActionName("Toggle Checkbox")
                textView.textStorage.replaceCharacters(in: range, with: status)
                text.wrappedValue = textView.text
                MarkdownStyler.applyLiveStyles(
                    to: textView.textStorage,
                    dirtyRange: range)
            }

            private func setDocumentText(
                in textView: UITextView,
                to updated: String
            ) {
                let previous = textView.text ?? ""
                guard previous != updated else { return }
                let selection = textView.selectedRange
                textView.undoManager?.registerUndo(withTarget: self) {
                    coordinator in
                    coordinator.setDocumentText(
                        in: textView,
                        to: previous)
                }
                textView.undoManager?.setActionName("Toggle Recurring Task")
                let whole = NSRange(
                    location: 0,
                    length: (previous as NSString).length)
                textView.textStorage.replaceCharacters(
                    in: whole,
                    with: updated)
                textView.selectedRange = NSRange(
                    location: min(
                        selection.location,
                        (updated as NSString).length),
                    length: 0)
                text.wrappedValue = updated
                MarkdownStyler.applyLiveStyles(to: textView.textStorage)
            }

            // Run alongside the text view's own gestures so cursor placement
            // still works for non-checkbox taps.
            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
            ) -> Bool {
                true
            }
        }
    }

    /// Makes the checkbox shortcut discoverable through the responder chain.
    /// `UITextView` itself does not expose `addKeyCommand`, so the commands must
    /// be declared by a responder subclass.
    private final class CheckboxTogglingTextView: UITextView {
        var toggleCheckboxHandler: (() -> Bool)?

        override var keyCommands: [UIKeyCommand]? {
            [
                UIKeyCommand(
                    title: "Toggle Checkbox",
                    action: #selector(toggleCheckboxFromKeyboard),
                    input: " ",
                    modifierFlags: [.command, .shift])
            ]
        }

        @objc private func toggleCheckboxFromKeyboard() {
            _ = toggleCheckboxHandler?()
        }
    }
#endif
