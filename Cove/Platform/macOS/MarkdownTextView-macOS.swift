#if os(macOS)
import SwiftUI
import AppKit

/// Live-styled Markdown `NSTextView` wrapper for the editor. The text stays
/// plain Markdown; `MarkdownStyler` reapplies attributes after every change,
/// and a click on a `- [ ]` marker toggles the checkbox.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String

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
        if let storage = textView.textStorage {
            MarkdownStyler.applyLiveStyles(to: storage)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            if let storage = textView.textStorage {
                MarkdownStyler.applyLiveStyles(to: storage)
            }
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
                MarkdownStyler.applyLiveStyles(to: storage)
            }
        }
    }
}

/// `NSTextView` that toggles a `- [ ]` checkbox marker on click instead of
/// moving the insertion point. The edit goes through `shouldChangeText`/
/// `didChangeText` so it lands on the undo stack and reaches the delegate.
final class CheckboxTogglingTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if let checkbox = MarkdownParser.parse(string).checkbox(at: index),
           shouldChangeText(in: checkbox.statusRange, replacementString: checkbox.toggledStatus) {
            textStorage?.replaceCharacters(in: checkbox.statusRange, with: checkbox.toggledStatus)
            didChangeText()
            return
        }
        super.mouseDown(with: event)
    }
}
#endif
