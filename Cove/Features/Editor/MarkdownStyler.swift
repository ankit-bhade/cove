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

    /// Restyles only affected paragraphs. All Cove-owned attributes are
    /// cleared locally before the substring is parsed and its ranges are
    /// translated back into document coordinates.
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
        let substring = (textStorage.string as NSString).substring(with: range)
        let parsed = MarkdownParser.parse(substring)
        textStorage.beginEditing()
        for key in [
            NSAttributedString.Key.font, .foregroundColor,
            .paragraphStyle, .strikethroughStyle,
        ] {
            textStorage.removeAttribute(key, range: range)
        }
        textStorage.addAttributes(bodyAttributes, range: range)

        for header in parsed.headers {
            textStorage.addAttribute(
                .font, value: headerFont(level: header.level),
                range: offset(header.lineRange, by: range.location))
            textStorage.addAttribute(
                .foregroundColor, value: syntaxColor,
                range: offset(header.markerRange, by: range.location))
        }

        for bold in parsed.boldSpans {
            let boldRange = offset(bold.range, by: range.location)
            // Bold the font already in effect (body, or a header's font).
            if let font = textStorage.attribute(
                .font, at: boldRange.location, effectiveRange: nil) as? PlatformFont
            {
                textStorage.addAttribute(.font, value: boldVariant(of: font), range: boldRange)
            }
            textStorage.addAttribute(
                .foregroundColor, value: syntaxColor,
                range: offset(bold.leadingDelimiterRange, by: range.location))
            textStorage.addAttribute(
                .foregroundColor, value: syntaxColor,
                range: offset(bold.trailingDelimiterRange, by: range.location))
        }

        for checkbox in parsed.checkboxes {
            textStorage.addAttribute(
                .foregroundColor, value: syntaxColor,
                range: offset(checkbox.markerRange, by: range.location))
            if checkbox.isChecked, checkbox.textRange.length > 0 {
                textStorage.addAttributes(
                    [
                        .foregroundColor: syntaxColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    ], range: offset(checkbox.textRange, by: range.location))
            }
        }

        textStorage.endEditing()
    }

    private static func offset(_ range: NSRange, by amount: Int) -> NSRange {
        NSRange(location: range.location + amount, length: range.length)
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
