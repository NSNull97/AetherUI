import UIKit

public struct AetherTextCoverRects {
    public let lineRects: [CGRect]
    public let wordRects: [CGRect]

    public init(lineRects: [CGRect], wordRects: [CGRect]) {
        self.lineRects = lineRects
        self.wordRects = wordRects
    }

    var effectiveRects: [CGRect] {
        if !wordRects.isEmpty {
            return wordRects
        }
        return lineRects
    }

    var isEmpty: Bool {
        lineRects.isEmpty && wordRects.isEmpty
    }

    static func make(for label: UILabel) -> AetherTextCoverRects {
        guard label.bounds.width > 0.0, label.bounds.height > 0.0 else {
            return AetherTextCoverRects(lineRects: [], wordRects: [])
        }

        let attributedText = normalizedAttributedText(for: label)
        guard attributedText.length > 0 else {
            return AetherTextCoverRects(lineRects: [], wordRects: [])
        }

        let textRect = label.textRect(forBounds: label.bounds, limitedToNumberOfLines: label.numberOfLines)
        guard textRect.width > 0.0, textRect.height > 0.0 else {
            return AetherTextCoverRects(lineRects: [], wordRects: [])
        }

        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: textRect.size)
        textContainer.lineFragmentPadding = 0.0
        textContainer.maximumNumberOfLines = max(0, label.numberOfLines)
        textContainer.lineBreakMode = label.lineBreakMode
        layoutManager.usesFontLeading = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        layoutManager.ensureLayout(for: textContainer)

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let origin = textRect.origin

        var lineRects: [CGRect] = []
        if glyphRange.length > 0 {
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
                let visibleRange = NSIntersectionRange(lineGlyphRange, glyphRange)
                guard visibleRange.length > 0 else {
                    return
                }
                lineRects.append(usedRect.offsetBy(dx: origin.x, dy: origin.y).integral)
            }
        }

        var wordRects: [CGRect] = []
        let fullRange = NSRange(location: 0, length: textStorage.length)
        (textStorage.string as NSString).enumerateSubstrings(in: fullRange, options: [.byWords, .localized]) { _, substringRange, _, _ in
            let wordGlyphRange = layoutManager.glyphRange(forCharacterRange: substringRange, actualCharacterRange: nil)
            let visibleWordGlyphRange = NSIntersectionRange(wordGlyphRange, glyphRange)
            guard visibleWordGlyphRange.length > 0 else {
                return
            }

            layoutManager.enumerateEnclosingRects(
                forGlyphRange: visibleWordGlyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { rect, _ in
                wordRects.append(rect.offsetBy(dx: origin.x, dy: origin.y).integral)
            }
        }

        return AetherTextCoverRects(lineRects: lineRects, wordRects: wordRects)
    }

    private static func normalizedAttributedText(for label: UILabel) -> NSAttributedString {
        let source: NSAttributedString
        if let attributedText = label.attributedText, attributedText.length > 0 {
            source = attributedText
        } else {
            source = NSAttributedString(
                string: label.text ?? "",
                attributes: [
                    .font: label.font ?? UIFont.systemFont(ofSize: UIFont.systemFontSize),
                    .foregroundColor: label.textColor ?? UIColor.label
                ]
            )
        }

        let mutable = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: mutable.length)
        guard fullRange.length > 0 else {
            return mutable
        }

        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.font, value: label.font ?? UIFont.systemFont(ofSize: UIFont.systemFontSize), range: range)
            }
        }

        mutable.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.foregroundColor, value: label.textColor ?? UIColor.label, range: range)
            }
        }

        mutable.string.enumerateSubstrings(in: mutable.string.startIndex..<mutable.string.endIndex, options: [.byParagraphs, .substringNotRequired]) { _, substringRange, _, _ in
            let range = NSRange(substringRange, in: mutable.string)
            guard range.length > 0 else {
                return
            }
            let existing = mutable.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let paragraphStyle = (existing?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            paragraphStyle.alignment = label.textAlignment
            paragraphStyle.lineBreakMode = label.lineBreakMode
            mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }

        return mutable
    }
}
