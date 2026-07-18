#if os(iOS)
import SwiftUI
import UIKit

/// Live-styled Markdown `UITextView` wrapper for the editor. The text stays
/// plain Markdown; `MarkdownStyler` reapplies attributes after every change,
/// and a tap on a `- [ ]` marker toggles the checkbox.
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
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

        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)
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

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            // Restyling during multistage input (e.g. Japanese IME) would
            // break the composition, so wait until it commits.
            guard textView.markedTextRange == nil else { return }
            MarkdownStyler.applyLiveStyles(to: textView.textStorage)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }
            let point = gesture.location(in: textView)
            guard let position = textView.closestPosition(to: point) else { return }
            let index = textView.offset(from: textView.beginningOfDocument, to: position)
            guard let checkbox = MarkdownParser.parse(textView.text).checkbox(at: index) else {
                return
            }
            textView.textStorage.replaceCharacters(
                in: checkbox.statusRange, with: checkbox.toggledStatus)
            text.wrappedValue = textView.text
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
#endif
