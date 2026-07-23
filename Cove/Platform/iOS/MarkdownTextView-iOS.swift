#if os(iOS)
    import SwiftUI
    import UIKit

    /// Live-styled Markdown `UITextView` wrapper for the editor. The text stays
    /// plain Markdown; `MarkdownStyler` reapplies attributes after every change,
    /// and a tap on a `- [ ]` marker toggles the checkbox.
    struct MarkdownTextView: UIViewRepresentable {
        @Binding var text: String

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
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
            private let text: Binding<String>
            weak var textView: UITextView?
            private var dirtyRange: NSRange?

            init(text: Binding<String>) {
                self.text = text
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
                setCheckbox(
                    in: textView,
                    range: checkbox.statusRange,
                    status: checkbox.toggledStatus)
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
