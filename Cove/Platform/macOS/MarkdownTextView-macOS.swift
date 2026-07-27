#if os(macOS)
    import SwiftUI
    import AppKit

    /// Live-styled Markdown `NSTextView` wrapper for the editor. The text stays
    /// plain Markdown; `MarkdownStyler` reapplies attributes after every change,
    /// and a click on a `- [ ]` marker toggles the checkbox.
    struct MarkdownTextView: NSViewRepresentable {
        @Binding var text: String
        let sectionedTaskDocument: Bool
        @Binding var checkboxError: String?
        /// A line to put the insertion point on and scroll into view,
        /// consumed once. Set by whoever opened the note at a line — a search
        /// hit, a task row, a format warning — and cleared here so a later
        /// redraw can't yank the reader back to it after they have scrolled
        /// away.
        @Binding var focusLine: Int?

        func makeNSView(context: Context) -> NSScrollView {
            // Called on the subclass so the returned document view is a
            // CheckboxTogglingTextView with the standard scroll setup.
            let scrollView = CheckboxTogglingTextView.scrollableTextView()
            guard let textView = scrollView.documentView as? NSTextView else {
                return scrollView
            }
            textView.delegate = context.coordinator
            textView.isRichText = false
            textView.allowsUndo = true
            textView.drawsBackground = false
            scrollView.drawsBackground = false
            // Smart punctuation rewrites Markdown syntax (straight quotes, "--"),
            // so it stays off.
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.textContainerInset = NSSize(width: 32, height: 28)
            textView.textContainer?.lineFragmentPadding = 0
            textView.typingAttributes = MarkdownStyler.bodyAttributes
            textView.string = text
            if let textView = textView as? CheckboxTogglingTextView {
                textView.sectionedTaskDocument = sectionedTaskDocument
                textView.onCheckboxError = {
                    checkboxError = $0
                }
            }
            if let storage = textView.textStorage {
                MarkdownStyler.applyLiveStyles(to: storage)
            }
            return scrollView
        }

        func updateNSView(_ scrollView: NSScrollView, context: Context) {
            guard let textView = scrollView.documentView as? NSTextView else { return }
            if let textView = textView as? CheckboxTogglingTextView {
                textView.sectionedTaskDocument = sectionedTaskDocument
                textView.onCheckboxError = {
                    checkboxError = $0
                }
            }
            if textView.string != text {
                textView.string = text
                if let storage = textView.textStorage {
                    MarkdownStyler.applyLiveStyles(to: storage)
                }
            }
            guard let focusLine else { return }
            // Deferred for two reasons: scrolling to a range the text view
            // has not laid out yet does nothing, and clearing the binding
            // inside `updateNSView` is a state mutation during a view update.
            DispatchQueue.main.async {
                self.focusLine = nil
                guard
                    let range = MarkdownParser.range(
                        ofLine: focusLine, in: textView.string)
                else { return }
                textView.setSelectedRange(
                    NSRange(location: range.location, length: 0))
                // Centred rather than merely visible: `scrollRangeToVisible`
                // scrolls the least it can and leaves the line hard against
                // whichever edge it entered from, with none of the note
                // around it. AppKit has the responder method for this; iOS
                // has to compute the offset by hand.
                textView.scrollRangeToVisible(range)
                textView.centerSelectionInVisibleArea(nil)
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        final class Coordinator: NSObject, NSTextViewDelegate {
            private let text: Binding<String>

            init(text: Binding<String>) {
                self.text = text
            }

            func textDidChange(_ notification: Notification) {
                guard let textView = notification.object as? NSTextView else { return }
                text.wrappedValue = textView.string
                // Restyling during multistage input (e.g. Japanese IME) would
                // break the composition, so wait until it commits.
                guard !textView.hasMarkedText() else { return }
                if let storage = textView.textStorage {
                    MarkdownStyler.applyLiveStyles(
                        to: storage,
                        dirtyRange: storage.editedRange)
                }
            }
        }
    }

    /// `NSTextView` that toggles a `- [ ]` checkbox marker on click instead of
    /// moving the insertion point. The edit goes through `shouldChangeText`/
    /// `didChangeText` so it lands on the undo stack and reaches the delegate.
    final class CheckboxTogglingTextView: NSTextView {
        var sectionedTaskDocument = false
        var onCheckboxError: ((String?) -> Void)?

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let index = characterIndexForInsertion(at: point)
            if let checkbox = MarkdownParser.parse(string).checkbox(at: index),
                toggle(checkbox)
            {
                return
            }
            super.mouseDown(with: event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == [.command, .shift], event.charactersIgnoringModifiers == " ",
                toggleCheckboxAtCursor()
            {
                return true
            }
            return super.performKeyEquivalent(with: event)
        }

        override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
            [
                NSAccessibilityCustomAction(
                    name: "Toggle checkbox at cursor",
                    target: self,
                    selector: #selector(accessibilityToggleCheckbox))
            ]
        }

        @objc private func accessibilityToggleCheckbox() -> Bool {
            toggleCheckboxAtCursor()
        }

        private func toggleCheckboxAtCursor() -> Bool {
            let cursor = selectedRange().location
            guard
                let checkbox = MarkdownParser.parse(string).checkboxes.first(where: {
                    NSLocationInRange(cursor, $0.markerRange)
                        || $0.markerRange.location <= cursor && cursor <= NSMaxRange($0.textRange)
                })
            else { return false }
            return toggle(checkbox)
        }

        private func toggle(_ checkbox: MarkdownParser.Checkbox) -> Bool {
            if let result = MarkdownParser.recurringTaskToggleResult(
                for: checkbox,
                in: string,
                sectioned: sectionedTaskDocument)
            {
                switch result {
                case .success(let updated):
                    onCheckboxError?(nil)
                    let whole = NSRange(
                        location: 0,
                        length: (string as NSString).length)
                    guard
                        shouldChangeText(
                            in: whole,
                            replacementString: updated)
                    else { return false }
                    let selection = selectedRange()
                    textStorage?.replaceCharacters(in: whole, with: updated)
                    setSelectedRange(
                        NSRange(
                            location: min(
                                selection.location,
                                (updated as NSString).length),
                            length: 0))
                    didChangeText()
                    undoManager?.setActionName("Toggle Recurring Task")
                    return true
                case .failure(let error):
                    onCheckboxError?(error.localizedDescription)
                    return false
                }
            }
            guard
                shouldChangeText(
                    in: checkbox.statusRange,
                    replacementString: checkbox.toggledStatus)
            else { return false }
            onCheckboxError?(nil)
            textStorage?.replaceCharacters(
                in: checkbox.statusRange,
                with: checkbox.toggledStatus)
            didChangeText()
            return true
        }
    }
#endif
