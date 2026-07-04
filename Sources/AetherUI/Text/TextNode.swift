import UIKit

public enum TextVerticalAlignment {
    case top
    case middle
    case bottom
}

public struct TextNodeLayoutInfo {
    public let size: CGSize
    public let truncated: Bool
    public let numberOfLines: Int

    public init(size: CGSize, truncated: Bool, numberOfLines: Int) {
        self.size = size
        self.truncated = truncated
        self.numberOfLines = numberOfLines
    }
}

public extension NSAttributedString.Key {
    static let textNodeLink = NSAttributedString.Key("AetherUI.TextNode.Link")
}

private struct TextNodeHit {
    let index: Int
    let attributes: [NSAttributedString.Key: Any]
    let selectedAttribute: NSAttributedString.Key
    let range: NSRange
}

open class TextNode: UIView, UIGestureRecognizerDelegate {
    public static let defaultFont = UIFont.systemFont(ofSize: 15.0)

    public static let defaultHighlightAttributeAction: ([NSAttributedString.Key: Any]) -> NSAttributedString.Key? = { attributes in
        if attributes[.link] != nil {
            return .link
        }
        if attributes[.textNodeLink] != nil {
            return .textNodeLink
        }
        return nil
    }

    public var attributedText: NSAttributedString? {
        didSet {
            applyAttributedTextToStorage()
        }
    }

    public var textAlignment: NSTextAlignment = .natural {
        didSet { applyAttributedTextToStorage() }
    }

    public var verticalAlignment: TextVerticalAlignment = .top {
        didSet { setNeedsDisplay() }
    }

    public var maximumNumberOfLines: Int = 0 {
        didSet { relayoutText() }
    }

    public var lineBreakMode: NSLineBreakMode = .byTruncatingTail {
        didSet { applyAttributedTextToStorage() }
    }

    public var truncationMode: NSLineBreakMode {
        get { lineBreakMode }
        set { lineBreakMode = newValue }
    }

    public var lineSpacing: CGFloat = 0.0 {
        didSet { applyAttributedTextToStorage() }
    }

    public var insets: UIEdgeInsets = .zero {
        didSet { relayoutText() }
    }

    public var linkHighlightColor: UIColor = UIColor.systemBlue.withAlphaComponent(0.18)
    public var linkHighlightCornerRadius: CGFloat = 4.0
    public var linkHighlightInset: UIEdgeInsets = UIEdgeInsets(top: 1.0, left: 2.0, bottom: 1.0, right: 2.0)

    public var highlightAttributeAction: (([NSAttributedString.Key: Any]) -> NSAttributedString.Key?)? = TextNode.defaultHighlightAttributeAction
    public var tapAttributeAction: (([NSAttributedString.Key: Any], Int) -> Void)?
    public var longTapAttributeAction: (([NSAttributedString.Key: Any], Int) -> Void)?

    public var linkTapAction: ((Any, Int) -> Void)?
    public var linkLongTapAction: ((Any, Int) -> Void)?

    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)

    private var cachedLayoutInfo: TextNodeLayoutInfo?
    private var activeHit: TextNodeHit?
    private var didHandleLongTap = false
    private var highlightView: TextNodeLinkHighlightView?
    private var longPressRecognizer: UILongPressGestureRecognizer?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    open override var intrinsicContentSize: CGSize {
        return sizeThatFits(CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric))
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize {
        let constrainedWidth = size.width == UIView.noIntrinsicMetric ? CGFloat.greatestFiniteMagnitude : size.width
        let constrainedHeight = size.height == UIView.noIntrinsicMetric ? CGFloat.greatestFiniteMagnitude : size.height
        return updateLayout(CGSize(width: constrainedWidth, height: constrainedHeight)).size
    }

    @discardableResult
    public func updateLayout(_ constrainedSize: CGSize) -> TextNodeLayoutInfo {
        ensureLayout(for: constrainedSize)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)

        var lineCount = 0
        var truncated = false
        if glyphRange.length > 0 {
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, lineGlyphRange, _ in
                lineCount += 1
                let truncatedRange = self.layoutManager.truncatedGlyphRange(inLineFragmentForGlyphAt: lineGlyphRange.location)
                if truncatedRange.location != NSNotFound && truncatedRange.length > 0 {
                    truncated = true
                }
            }
        }

        let measuredWidth = ceil(max(0.0, usedRect.maxX) + insets.left + insets.right)
        let measuredHeight = ceil(max(0.0, usedRect.maxY) + insets.top + insets.bottom)
        let info = TextNodeLayoutInfo(
            size: CGSize(width: measuredWidth, height: measuredHeight),
            truncated: truncated,
            numberOfLines: lineCount
        )
        cachedLayoutInfo = info
        return info
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        ensureLayout(for: bounds.size)
        highlightView?.frame = bounds
    }

    open override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard textStorage.length > 0 else {
            return
        }

        ensureLayout(for: bounds.size)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let origin = textDrawingOrigin(for: bounds.size)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
    }

    public func attributesAtPoint(_ point: CGPoint) -> (Int, [NSAttributedString.Key: Any])? {
        ensureLayout(for: bounds.size)
        guard textStorage.length > 0, layoutManager.numberOfGlyphs > 0 else {
            return nil
        }

        let origin = textDrawingOrigin(for: bounds.size)
        let containerPoint = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        let usedRect = layoutManager.usedRect(for: textContainer).insetBy(dx: -4.0, dy: -6.0)
        guard usedRect.contains(containerPoint) else {
            return nil
        }

        var fraction: CGFloat = 0.0
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: &fraction
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else {
            return nil
        }

        var lineGlyphRange = NSRange(location: 0, length: 0)
        let lineRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: glyphIndex,
            effectiveRange: &lineGlyphRange
        ).insetBy(dx: -4.0, dy: -6.0)
        guard lineRect.contains(containerPoint) else {
            return nil
        }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else {
            return nil
        }

        return (characterIndex, textStorage.attributes(at: characterIndex, effectiveRange: nil))
    }

    public func attributeRects(name: String, at index: Int) -> [CGRect]? {
        return attributeRects(for: NSAttributedString.Key(name), at: index)
    }

    public func attributeRects(for key: NSAttributedString.Key, at index: Int) -> [CGRect]? {
        guard let range = attributeEffectiveRange(for: key, at: index) else {
            return nil
        }
        return rects(forCharacterRange: range)
    }

    public func lineAndAttributeRects(name: String, at index: Int) -> [(CGRect, CGRect)]? {
        return lineAndAttributeRects(for: NSAttributedString.Key(name), at: index)
    }

    public func lineAndAttributeRects(for key: NSAttributedString.Key, at index: Int) -> [(CGRect, CGRect)]? {
        guard let characterRange = attributeEffectiveRange(for: key, at: index) else {
            return nil
        }

        ensureLayout(for: bounds.size)
        let attributeGlyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard attributeGlyphRange.length > 0 else {
            return []
        }

        let origin = textDrawingOrigin(for: bounds.size)
        let fullGlyphRange = layoutManager.glyphRange(for: textContainer)
        var result: [(CGRect, CGRect)] = []
        layoutManager.enumerateLineFragments(forGlyphRange: fullGlyphRange) { _, usedRect, _, lineGlyphRange, _ in
            let intersection = NSIntersectionRange(lineGlyphRange, attributeGlyphRange)
            guard intersection.length > 0 else {
                return
            }
            let attributeRect = self.layoutManager.boundingRect(forGlyphRange: intersection, in: self.textContainer)
            result.append((usedRect.offsetBy(dx: origin.x, dy: origin.y), attributeRect.offsetBy(dx: origin.x, dy: origin.y)))
        }
        return result
    }

    public func textCoverRects() -> AetherTextCoverRects {
        ensureLayout(for: bounds.size)
        let origin = textDrawingOrigin(for: bounds.size)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var lineRects: [CGRect] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
            lineRects.append(usedRect.offsetBy(dx: origin.x, dy: origin.y).integral)
        }

        var wordRects: [CGRect] = []
        let fullRange = NSRange(location: 0, length: textStorage.length)
        (textStorage.string as NSString).enumerateSubstrings(in: fullRange, options: [.byWords, .localized]) { _, substringRange, _, _ in
            wordRects.append(contentsOf: self.rects(forCharacterRange: substringRange).map { $0.integral })
        }
        return AetherTextCoverRects(lineRects: lineRects, wordRects: wordRects)
    }

    public static func detectLinks(
        in attributedString: NSAttributedString,
        checkingTypes: NSTextCheckingResult.CheckingType = [.link, .phoneNumber],
        linkAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.systemBlue
        ]
    ) -> NSAttributedString {
        guard attributedString.length > 0,
              let detector = try? NSDataDetector(types: checkingTypes.rawValue) else {
            return attributedString
        }

        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutable.length)
        detector.enumerateMatches(in: mutable.string, options: [], range: fullRange) { result, _, _ in
            guard let result else {
                return
            }

            let value: Any?
            if let url = result.url {
                value = url
            } else if result.resultType == .phoneNumber, let phoneNumber = result.phoneNumber {
                value = URL(string: "tel:\(phoneNumber)")
            } else {
                value = nil
            }

            guard let value else {
                return
            }

            mutable.addAttribute(.link, value: value, range: result.range)
            for (key, attributeValue) in linkAttributes {
                mutable.addAttribute(key, value: attributeValue, range: result.range)
            }
        }
        return mutable
    }

    open override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self), let hit = interactiveHit(at: point) else {
            super.touchesBegan(touches, with: event)
            return
        }

        activeHit = hit
        didHandleLongTap = false
        updateHighlight(for: hit, animated: false)
    }

    open override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeHit, let point = touches.first?.location(in: self) else {
            super.touchesMoved(touches, with: event)
            return
        }

        if let hit = interactiveHit(at: point), hit.selectedAttribute == activeHit.selectedAttribute, hit.range == activeHit.range {
            updateHighlight(for: hit, animated: false)
        } else {
            clearHighlight(animated: true)
        }
    }

    open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            activeHit = nil
            didHandleLongTap = false
            clearHighlight(animated: true)
        }

        guard !didHandleLongTap,
              let activeHit,
              let point = touches.first?.location(in: self),
              let hit = interactiveHit(at: point),
              hit.selectedAttribute == activeHit.selectedAttribute,
              hit.range == activeHit.range else {
            super.touchesEnded(touches, with: event)
            return
        }

        tapAttributeAction?(hit.attributes, hit.index)
        if let linkValue = hit.attributes[hit.selectedAttribute] {
            linkTapAction?(linkValue, hit.index)
        }
    }

    open override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeHit = nil
        didHandleLongTap = false
        clearHighlight(animated: true)
        super.touchesCancelled(touches, with: event)
    }

    open override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === longPressRecognizer else {
            return true
        }
        guard longTapAttributeAction != nil || linkLongTapAction != nil else {
            return false
        }
        return interactiveHit(at: gestureRecognizer.location(in: self)) != nil
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    private func commonInit() {
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = false

        textContainer.lineFragmentPadding = 0.0
        textContainer.maximumNumberOfLines = maximumNumberOfLines
        textContainer.lineBreakMode = lineBreakMode
        layoutManager.usesFontLeading = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false
        longPress.delaysTouchesEnded = false
        longPress.delegate = self
        addGestureRecognizer(longPress)
        longPressRecognizer = longPress
    }

    private func applyAttributedTextToStorage() {
        let normalized = normalizedAttributedString(attributedText)
        textStorage.beginEditing()
        textStorage.setAttributedString(normalized)
        textStorage.endEditing()
        relayoutText()
    }

    private func normalizedAttributedString(_ attributedString: NSAttributedString?) -> NSAttributedString {
        guard let attributedString, attributedString.length > 0 else {
            return NSAttributedString()
        }

        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutable.length)

        mutable.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            if value == nil {
                mutable.addAttribute(.font, value: TextNode.defaultFont, range: range)
            }
        }

        mutable.string.enumerateSubstrings(in: mutable.string.startIndex..<mutable.string.endIndex, options: [.byParagraphs, .substringNotRequired]) { _, substringRange, _, _ in
            let nsRange = NSRange(substringRange, in: mutable.string)
            let existingStyle = mutable.attribute(.paragraphStyle, at: nsRange.location, effectiveRange: nil) as? NSParagraphStyle
            let paragraphStyle = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            paragraphStyle.alignment = self.textAlignment
            paragraphStyle.lineSpacing = self.lineSpacing
            paragraphStyle.lineBreakMode = self.lineBreakMode
            mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: nsRange)
        }

        if mutable.length == 1 || mutable.string.isEmpty {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = textAlignment
            paragraphStyle.lineSpacing = lineSpacing
            paragraphStyle.lineBreakMode = lineBreakMode
            mutable.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        }

        return mutable
    }

    private func relayoutText() {
        textContainer.maximumNumberOfLines = max(0, maximumNumberOfLines)
        textContainer.lineBreakMode = lineBreakMode
        cachedLayoutInfo = nil
        layoutManager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: textStorage.length), actualCharacterRange: nil)
        setNeedsLayout()
        setNeedsDisplay()
        invalidateIntrinsicContentSize()
    }

    private func ensureLayout(for size: CGSize) {
        let width = max(0.0, finiteDimension(size.width, fallback: UIScreen.main.bounds.width) - insets.left - insets.right)
        let height = max(0.0, finiteDimension(size.height, fallback: CGFloat.greatestFiniteMagnitude / 4.0) - insets.top - insets.bottom)
        let containerSize = CGSize(width: width, height: height)
        if textContainer.size != containerSize {
            textContainer.size = containerSize
            cachedLayoutInfo = nil
        }
        layoutManager.ensureLayout(for: textContainer)
    }

    private func finiteDimension(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        if value.isFinite, value != UIView.noIntrinsicMetric {
            return value
        }
        return fallback
    }

    private func textDrawingOrigin(for size: CGSize) -> CGPoint {
        let availableHeight = max(0.0, finiteDimension(size.height, fallback: 0.0) - insets.top - insets.bottom)
        let usedRect = layoutManager.usedRect(for: textContainer)
        var y = insets.top - usedRect.minY
        switch verticalAlignment {
        case .top:
            break
        case .middle:
            y += floor(max(0.0, availableHeight - usedRect.height) / 2.0)
        case .bottom:
            y += floor(max(0.0, availableHeight - usedRect.height))
        }
        return CGPoint(x: insets.left, y: y)
    }

    private func attributeEffectiveRange(for key: NSAttributedString.Key, at index: Int) -> NSRange? {
        ensureLayout(for: bounds.size)
        guard index >= 0, index < textStorage.length else {
            return nil
        }
        var effectiveRange = NSRange(location: 0, length: 0)
        guard textStorage.attribute(key, at: index, effectiveRange: &effectiveRange) != nil else {
            return nil
        }
        return effectiveRange
    }

    private func rects(forCharacterRange characterRange: NSRange) -> [CGRect] {
        ensureLayout(for: bounds.size)
        guard characterRange.length > 0 else {
            return []
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else {
            return []
        }

        let origin = textDrawingOrigin(for: bounds.size)
        var rects: [CGRect] = []
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { rect, _ in
            rects.append(rect.offsetBy(dx: origin.x, dy: origin.y))
        }
        return rects
    }

    private func interactiveHit(at point: CGPoint) -> TextNodeHit? {
        guard let highlightAttributeAction,
              let (index, attributes) = attributesAtPoint(point),
              let selectedAttribute = highlightAttributeAction(attributes),
              attributes[selectedAttribute] != nil,
              let range = attributeEffectiveRange(for: selectedAttribute, at: index) else {
            return nil
        }
        return TextNodeHit(index: index, attributes: attributes, selectedAttribute: selectedAttribute, range: range)
    }

    private func updateHighlight(for hit: TextNodeHit, animated: Bool) {
        guard let rects = attributeRects(for: hit.selectedAttribute, at: hit.index), !rects.isEmpty else {
            clearHighlight(animated: animated)
            return
        }

        let view: TextNodeLinkHighlightView
        if let current = highlightView {
            view = current
        } else {
            view = TextNodeLinkHighlightView()
            view.isUserInteractionEnabled = false
            highlightView = view
            insertSubview(view, at: 0)
        }

        view.frame = bounds
        view.color = linkHighlightColor
        view.cornerRadius = linkHighlightCornerRadius
        view.insets = linkHighlightInset
        view.rects = rects
        view.alpha = 1.0

        if animated {
            UIView.animate(withDuration: 0.12) {
                view.alpha = 1.0
            }
        }
    }

    private func clearHighlight(animated: Bool) {
        guard let view = highlightView else {
            return
        }
        highlightView = nil
        let cleanup = {
            view.removeFromSuperview()
        }
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0.0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                view.alpha = 0.0
            }, completion: { _ in
                cleanup()
            })
        } else {
            cleanup()
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            guard let hit = interactiveHit(at: recognizer.location(in: self)) else {
                return
            }
            activeHit = hit
            didHandleLongTap = true
            updateHighlight(for: hit, animated: false)
            longTapAttributeAction?(hit.attributes, hit.index)
            if let linkValue = hit.attributes[hit.selectedAttribute] {
                linkLongTapAction?(linkValue, hit.index)
            }
        case .ended, .cancelled, .failed:
            activeHit = nil
            clearHighlight(animated: true)
        default:
            break
        }
    }
}

private final class TextNodeLinkHighlightView: UIView {
    var rects: [CGRect] = [] {
        didSet { setNeedsDisplay() }
    }

    var color: UIColor = UIColor.systemBlue.withAlphaComponent(0.18) {
        didSet { setNeedsDisplay() }
    }

    var cornerRadius: CGFloat = 4.0 {
        didSet { setNeedsDisplay() }
    }

    var insets: UIEdgeInsets = .zero {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
        backgroundColor = .clear
    }

    override func draw(_ rect: CGRect) {
        guard !rects.isEmpty else {
            return
        }

        color.setFill()
        for itemRect in rects {
            let expanded = itemRect.inset(by: UIEdgeInsets(
                top: -insets.top,
                left: -insets.left,
                bottom: -insets.bottom,
                right: -insets.right
            ))
            UIBezierPath(roundedRect: expanded.integral, cornerRadius: cornerRadius).fill()
        }
    }
}
