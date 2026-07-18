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

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 2
        return [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
    }

    private static func headerFont(level: Int) -> PlatformFont {
        let multipliers: [CGFloat] = [1.8, 1.55, 1.35, 1.2, 1.1, 1.0]
        let size = (bodyFont.pointSize * multipliers[max(0, min(5, level - 1))]).rounded()
        return .systemFont(ofSize: size, weight: .bold)
    }

    /// Restyles the whole document. Attribute-only edits, so the selection
    /// and undo stack are unaffected.
    static func applyLiveStyles(to textStorage: NSTextStorage) {
        let parsed = MarkdownParser.parse(textStorage.string)
        textStorage.beginEditing()
        textStorage.setAttributes(
            bodyAttributes, range: NSRange(location: 0, length: textStorage.length))

        for header in parsed.headers {
            textStorage.addAttribute(
                .font, value: headerFont(level: header.level), range: header.lineRange)
            textStorage.addAttribute(
                .foregroundColor, value: syntaxColor, range: header.markerRange)
        }

        for bold in parsed.boldSpans {
            // Bold the font already in effect (body, or a header's font).
            if let font = textStorage.attribute(
                .font, at: bold.range.location, effectiveRange: nil) as? PlatformFont {
                textStorage.addAttribute(.font, value: boldVariant(of: font), range: bold.range)
            }
            textStorage.addAttribute(
                .foregroundColor, value: syntaxColor, range: bold.leadingDelimiterRange)
            textStorage.addAttribute(
                .foregroundColor, value: syntaxColor, range: bold.trailingDelimiterRange)
        }

        for checkbox in parsed.checkboxes {
            textStorage.addAttribute(
                .foregroundColor, value: syntaxColor, range: checkbox.markerRange)
            if checkbox.isChecked, checkbox.textRange.length > 0 {
                textStorage.addAttributes([
                    .foregroundColor: syntaxColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ], range: checkbox.textRange)
            }
        }

        textStorage.endEditing()
    }
}
