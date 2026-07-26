import Foundation
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Applies live Markdown styling to the editor's text storage from
/// `MarkdownParser` output. Shared by both platform representables; only the
/// font and color types differ.
enum MarkdownStyler {
    #if os(iOS)
        typealias PlatformFont = UIFont

        static var bodyFont: UIFont { .preferredFont(forTextStyle: .body) }
        private static var textColor: UIColor { .label }
        private static var syntaxColor: UIColor { .secondaryLabel }

        private static func boldVariant(of font: UIFont) -> UIFont {
            let traits = font.fontDescriptor.symbolicTraits.union(.traitBold)
            guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else {
                return font
            }
            return UIFont(descriptor: descriptor, size: 0)
        }
    #elseif os(macOS)
        typealias PlatformFont = NSFont

        static var bodyFont: NSFont { .preferredFont(forTextStyle: .body, options: [:]) }
        private static var textColor: NSColor { .labelColor }
        private static var syntaxColor: NSColor { .secondaryLabelColor }

        private static func boldVariant(of font: NSFont) -> NSFont {
            NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
    #endif

    /// Paragraph spacing has to beat line spacing or the two are
    /// indistinguishable: at 4 and 2 a wrapped sentence and the next task line
    /// opened the same gap, and a note of checkboxes read as one block of
    /// text. Seven against four is enough to see where a line ends.
    static var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 7
        return [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    /// Headers are set in the serif face, like every other title in the app.
    /// A `#` line is the one thing in a note that is read once rather than
    /// scanned, which is exactly the split the type system draws — and it puts
    /// the note's own title in the same voice as the screen title above it.
    private static func headerFont(level: Int) -> PlatformFont {
        let multipliers: [CGFloat] = [1.8, 1.55, 1.35, 1.2, 1.1, 1.0]
        let size = (bodyFont.pointSize * multipliers[max(0, min(5, level - 1))]).rounded()
        let base = PlatformFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        #if os(iOS)
            return UIFont(descriptor: descriptor, size: size)
        #else
            return NSFont(descriptor: descriptor, size: size) ?? base
        #endif
    }

    /// Restyles the whole document. Attribute-only edits, so the selection
    /// and undo stack are unaffected.
    static func applyLiveStyles(to textStorage: NSTextStorage) {
        applyLiveStyles(
            to: textStorage,
            dirtyRange: NSRange(location: 0, length: textStorage.length),
            includeNeighbors: false)
    }

    /// Restyles only affected paragraphs. Parsing still uses the whole
    /// document because fenced code and YAML front matter can begin well
    /// before the edited paragraph. Only runs intersecting the local range
    /// are applied, so ordinary typing does not restyle the entire note.
    static func applyLiveStyles(
        to textStorage: NSTextStorage,
        dirtyRange: NSRange,
        includeNeighbors: Bool = true
    ) {
        let range = expandedParagraphRange(
            in: textStorage.string,
            around: dirtyRange,
            includeNeighbors: includeNeighbors)
        guard range.location != NSNotFound else { return }
        let parsed = MarkdownParser.parse(textStorage.string)
        textStorage.beginEditing()
        for key in [
            NSAttributedString.Key.font, .foregroundColor,
            .paragraphStyle, .strikethroughStyle,
        ] {
            textStorage.removeAttribute(key, range: range)
        }
        textStorage.addAttributes(bodyAttributes, range: range)

        for header in parsed.headers {
            guard let lineRange = intersection(header.lineRange, range) else {
                continue
            }
            textStorage.addAttribute(
                .font, value: headerFont(level: header.level),
                range: lineRange)
            if let markerRange = intersection(header.markerRange, range) {
                textStorage.addAttribute(
                    .foregroundColor, value: syntaxColor,
                    range: markerRange)
            }
        }

        for bold in parsed.boldSpans {
            guard let boldRange = intersection(bold.range, range) else {
                continue
            }
            // Bold the font already in effect (body, or a header's font).
            if let font = textStorage.attribute(
                .font, at: boldRange.location, effectiveRange: nil) as? PlatformFont
            {
                textStorage.addAttribute(.font, value: boldVariant(of: font), range: boldRange)
            }
            for delimiterRange in [
                bold.leadingDelimiterRange,
                bold.trailingDelimiterRange,
            ] {
                if let delimiterRange = intersection(delimiterRange, range) {
                    textStorage.addAttribute(
                        .foregroundColor, value: syntaxColor,
                        range: delimiterRange)
                }
            }
        }

        for checkbox in parsed.checkboxes {
            if let markerRange = intersection(checkbox.markerRange, range) {
                textStorage.addAttribute(
                    .foregroundColor, value: syntaxColor,
                    range: markerRange)
            }
            if checkbox.isChecked,
                let textRange = intersection(checkbox.textRange, range)
            {
                textStorage.addAttributes(
                    [
                        .foregroundColor: syntaxColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    ], range: textRange)
            }
        }

        textStorage.endEditing()
    }

    private static func intersection(
        _ lhs: NSRange,
        _ rhs: NSRange
    ) -> NSRange? {
        let result = NSIntersectionRange(lhs, rhs)
        return result.length > 0 ? result : nil
    }

    private static func expandedParagraphRange(
        in text: String,
        around dirtyRange: NSRange,
        includeNeighbors: Bool
    ) -> NSRange {
        let ns = text as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        guard dirtyRange.location != NSNotFound else {
            return NSRange(location: 0, length: ns.length)
        }
        let safeLocation = min(max(0, dirtyRange.location), ns.length - 1)
        let safeEnd = min(ns.length, max(safeLocation + 1, NSMaxRange(dirtyRange)))
        var start = 0
        var end = 0
        var contentsEnd = 0
        ns.getParagraphStart(
            &start, end: &end, contentsEnd: &contentsEnd,
            for: NSRange(
                location: safeLocation,
                length: safeEnd - safeLocation))
        if includeNeighbors, start > 0 {
            var previousStart = 0
            ns.getParagraphStart(
                &previousStart, end: nil, contentsEnd: nil,
                for: NSRange(location: start - 1, length: 1))
            start = previousStart
        }
        if includeNeighbors, end < ns.length {
            var nextEnd = 0
            ns.getParagraphStart(
                nil, end: &nextEnd, contentsEnd: nil,
                for: NSRange(location: end, length: 1))
            end = nextEnd
        }
        return NSRange(location: start, length: end - start)
    }
}
