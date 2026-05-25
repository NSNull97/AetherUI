import UIKit

// MARK: - GlassControlGroup

/// A group of controls rendered on a shared glass capsule.
/// Port of Display framework `GlassControlGroupComponent`, adapted from ComponentFlow to plain UIKit.
public final class GlassControlGroup: UIView {
    // MARK: - Types

    public struct Item {
        public enum Content {
            case icon(UIImage)
            case text(String)
            /// Caller-provided view; the group takes ownership and lays it out inside the capsule.
            case customView(UIView)
        }

        public let id: AnyHashable
        public let content: Content
        public let action: (() -> Void)?
        public let contentInsets: UIEdgeInsets

        public init(
            id: AnyHashable,
            content: Content,
            contentInsets: UIEdgeInsets = .zero,
            action: (() -> Void)?
        ) {
            self.id = id
            self.content = content
            self.contentInsets = contentInsets
            self.action = action
        }
    }

    public enum Background: Equatable {
        case panel
        case activeTint(foregroundColor: UIColor, fillColor: UIColor)
        case color(UIColor)
    }

    // MARK: - Subviews

    private let backgroundView: GlassBackgroundView
    private let controlsView: UIView
    private var itemViews: [ItemEntry] = []

    private struct ItemEntry {
        let id: AnyHashable
        let contentId: ContentId
        let button: HighlightTrackingButton
        let contentView: UIView
        var contentInsets: UIEdgeInsets
        var isInteractive: Bool
        var itemFrame: CGRect
    }

    private enum ContentId: Hashable {
        case icon(ObjectIdentifier)
        case text(String)
        case customView(ObjectIdentifier)
    }

    // MARK: - State

    public private(set) var items: [Item] = []
    public private(set) var background: Background = .panel
    public private(set) var preferClearGlass: Bool = false
    private var currentTintColor: GlassBackgroundView.TintColor = .init(kind: .panel)
    private var currentIsInteractive: Bool = false
    public var foregroundColor: UIColor = .label {
        didSet {
            applyForegroundColorToItems()
        }
    }
    /// Theme pin for the underlying glass. When set (including by
    /// `update(isDark:)` internally) the value forwards to
    /// `backgroundView.isDarkOverride`, so the glass re-renders with the
    /// override regardless of the next layout pass or trait-change event.
    /// Default `false`; assign externally before/after `update` to pin the
    /// glass tint to a specific theme (e.g. when hosted on a dark hero
    /// image while the system is in light mode).
    public var isDarkAppearance: Bool = false {
        didSet {
            if isDarkAppearance == oldValue { return }
            backgroundView.isDarkOverride = isDarkAppearance
        }
    }

    public var minWidth: CGFloat = 44.0
    public var animatesInsertedItemsAlpha: Bool = true
    private var naturalSize: CGSize = .zero
    private var updateGeneration: Int = 0

    private enum Overspring {
        static let itemChangeAmplitude: CGFloat = 0.110
        static let groupRemovalAmplitude: CGFloat = 0.095
        static let itemTransitionScale: CGFloat = 0.94
    }

    public enum TransitionChromeContentAlignment {
        case leading
        case trailing
    }

    public var transitionContentAlignment: TransitionChromeContentAlignment = .leading

    // MARK: - Init

    private var elasticRecognizer: GlassHighlightGestureRecognizer?

    public init(style: GlassBackgroundView.Style = .regular) {
        self.backgroundView = GlassBackgroundView(style: style)
        self.controlsView = UIView()

        super.init(frame: .zero)

        controlsView.clipsToBounds = true
        addSubview(backgroundView)
        backgroundView.contentView.addSubview(controlsView)

        // iOS ≤25 doesn't have UIGlassEffect.isInteractive — port the
        // Telegram elastic touch feedback so the whole capsule (glass
        // surface + inner buttons) stretches under the finger and
        // springs back on release. iOS 26+ gets the native warp via
        // `isInteractive` on the glass (see `update`).
        if #unavailable(iOS 26.0) {
            let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
            elastic.touchEffectView = self
            elastic.highlightContainerView = controlsView
            addGestureRecognizer(elastic)
            self.elasticRecognizer = elastic
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Update

    public func update(
        items: [Item],
        background: Background = .panel,
        preferClearGlass: Bool = false,
        foregroundColor: UIColor? = nil,
        isDark: Bool = false,
        availableHeight: CGFloat = 44.0,
        minWidth: CGFloat = 44.0,
        transition: ContainedViewLayoutTransition = .immediate
    ) -> CGSize {
        updateGeneration += 1
        let generation = updateGeneration
        self.items = items
        self.background = background
        self.preferClearGlass = preferClearGlass
        self.isDarkAppearance = isDark
        self.minWidth = minWidth

        // Derive tint color / foreground color from background.
        let tintColor: GlassBackgroundView.TintColor
        let derivedForeground: UIColor
        switch background {
        case .panel:
            tintColor = .init(kind: preferClearGlass ? .clear : .panel)
            derivedForeground = foregroundColor ?? (isDark ? .white : .label)
        case let .activeTint(fg, fill):
            tintColor = .init(kind: preferClearGlass ? .clear : .panel, innerColor: fill)
            derivedForeground = foregroundColor ?? fg
        case let .color(color):
            tintColor = .init(kind: .custom(style: preferClearGlass ? .clear : .default, color: color))
            derivedForeground = foregroundColor ?? .white
        }
        self.currentTintColor = tintColor
        self.foregroundColor = derivedForeground

        // Diff item views by (id, content-id).
        var newEntries: [ItemEntry] = []
        newEntries.reserveCapacity(items.count)

        var isInteractiveOverall = false
        var contentsWidth: CGFloat = 0.0
        var didChangeVisualItems = false
        var insertedEntryCount = 0
        var removedEntryCount = 0

        for item in items {
            let contentId: ContentId
            let freshView: UIView
            switch item.content {
            case let .icon(image):
                let key = ObjectIdentifier(image)
                contentId = .icon(key)
                let imageView = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
                imageView.contentMode = .center
                imageView.tintColor = derivedForeground
                imageView.setMonochromaticEffect(tintColor: derivedForeground)
                freshView = imageView
            case let .text(text):
                contentId = .text(text)
                let label = UILabel()
                label.text = text
                label.font = .systemFont(ofSize: 17.0, weight: .medium)
                label.textColor = derivedForeground
                label.textAlignment = .center
                freshView = label
            case let .customView(view):
                contentId = .customView(ObjectIdentifier(view))
                freshView = view
            }

            // Reuse existing entry with matching id & contentId.
            let existingIndex = itemViews.firstIndex { $0.id == item.id && $0.contentId == contentId }
            var entry: ItemEntry
            let contentView: UIView
            let isNewEntry: Bool
            if let existingIndex {
                entry = itemViews.remove(at: existingIndex)
                entry.contentInsets = item.contentInsets
                entry.isInteractive = item.action != nil
                // Keep existing content view; just update action.
                contentView = entry.contentView
                isNewEntry = false
            } else {
                let button = HighlightTrackingButton(type: .custom)
                button.isUserInteractionEnabled = item.action != nil
                button.addSubview(freshView)
                controlsView.addSubview(button)
                didChangeVisualItems = true
                insertedEntryCount += 1

                entry = ItemEntry(
                    id: item.id,
                    contentId: contentId,
                    button: button,
                    contentView: freshView,
                    contentInsets: item.contentInsets,
                    isInteractive: item.action != nil,
                    itemFrame: .zero
                )
                contentView = freshView
                isNewEntry = true
                animateInsertedButton(button, targetAlpha: item.action != nil ? 1.0 : 0.5, transition: transition)
            }

            // Wire action.
            entry.button.onTap = { item.action?() }
            entry.button.isUserInteractionEnabled = item.action != nil
            if !isNewEntry {
                restoreExistingButton(entry.button, targetAlpha: item.action != nil ? 1.0 : 0.5, transition: transition)
            }

            if item.action != nil {
                isInteractiveOverall = true
            }

            // Measure content.
            let maxContentHeight = availableHeight
            var contentSize = contentView.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: maxContentHeight))
            if case .customView = item.content {
                contentSize = contentView.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: maxContentHeight))
                if contentSize == .zero {
                    contentSize = contentView.bounds.size
                }
            } else if case .text = item.content {
                contentSize.width = ceil(contentSize.width)
                contentSize.height = ceil(contentSize.height)
            } else {
                // Icon buttons use a 36pt icon per Figma spec — visibly larger
                // than the previous 28pt so they're easy to tap on a glass
                // capsule and match the iOS 26 reference size.
                contentSize = CGSize(width: 44.0, height: 44.0)
            }

            // Item frame is at least max(minWidth, availableHeight) wide for single-item groups.
            var itemWidth = contentSize.width + entry.contentInsets.left + entry.contentInsets.right
            itemWidth = max(itemWidth, availableHeight)
            if items.count == 1 {
                itemWidth = max(itemWidth, minWidth)
            }

            let itemFrame = CGRect(x: contentsWidth, y: 0.0, width: itemWidth, height: availableHeight)
            entry.itemFrame = itemFrame
            let itemGeometryTransition: ContainedViewLayoutTransition = isNewEntry ? .immediate : transition
            itemGeometryTransition.updateFrame(view: entry.button, frame: itemFrame)

            // Center the content view inside the button with contentInsets.
            let contentOrigin = CGPoint(
                x: entry.contentInsets.left + floor((itemWidth - entry.contentInsets.left - entry.contentInsets.right - contentSize.width) / 2.0),
                y: floor((availableHeight - contentSize.height) / 2.0)
            )
            itemGeometryTransition.updateFrame(
                view: contentView,
                frame: CGRect(origin: contentOrigin, size: contentSize)
            )

            newEntries.append(entry)
            contentsWidth += itemWidth
        }

        // Remove stale views. For trailing bar-button groups, preserve the
        // outgoing button's right edge while the replacement fades in; otherwise
        // a narrower target group makes the old right button look like it moves.
        let nextNaturalWidth = items.isEmpty ? (naturalSize.width > 0.0 ? naturalSize.width : availableHeight) : max(availableHeight, contentsWidth)
        for stale in itemViews {
            didChangeVisualItems = true
            removedEntryCount += 1
            if transitionContentAlignment == .trailing {
                var staleFrame = stale.itemFrame
                staleFrame.origin.x = nextNaturalWidth - staleFrame.width
                ContainedViewLayoutTransition.immediate.updateFrame(view: stale.button, frame: staleFrame)
            }
            animateRemovedButton(stale.button, transition: transition)
        }
        itemViews = newEntries
        currentIsInteractive = isInteractiveOverall

        // If there are no items, collapse the group entirely — otherwise the
        // glass capsule would still render at its min-width size, producing a
        // visible empty pill next to real content (matches behaviour).
        if items.isEmpty {
            isUserInteractionEnabled = false
            let previousSize = naturalSize == .zero ? backgroundView.bounds.size : naturalSize
            if didChangeVisualItems,
               transition.isAnimated,
               animatesInsertedItemsAlpha,
               previousSize.width > 0.0,
               previousSize.height > 0.0 {
                backgroundView.isHidden = false
                if backgroundView.bounds.size == .zero {
                    backgroundView.frame = CGRect(origin: .zero, size: previousSize)
                }
                if controlsView.bounds.size == .zero {
                    controlsView.frame = CGRect(origin: .zero, size: previousSize)
                }
                animateGroupPulse(transition: transition, amplitude: -Overspring.groupRemovalAmplitude)
                transition.updateAlpha(view: backgroundView, alpha: 0.0) { [weak self] _ in
                    guard let self, self.updateGeneration == generation else {
                        return
                    }
                    self.backgroundView.isHidden = true
                    self.backgroundView.alpha = 1.0
                    self.backgroundView.frame = .zero
                    self.controlsView.frame = .zero
                    self.controlsView.alpha = 1.0
                    self.naturalSize = .zero
                    self.frame.size = .zero
                }
                transition.updateAlpha(view: controlsView, alpha: 0.0)
                return .zero
            }
            transition.updateFrame(view: backgroundView, frame: .zero)
            transition.updateFrame(view: controlsView, frame: .zero)
            backgroundView.isHidden = true
            backgroundView.alpha = 1.0
            controlsView.alpha = 1.0
            naturalSize = .zero
            frame.size = .zero
            return .zero
        }

        backgroundView.isHidden = false
        backgroundView.alpha = 1.0
        controlsView.alpha = 1.0
        isUserInteractionEnabled = isInteractiveOverall
        let size = CGSize(width: max(availableHeight, contentsWidth), height: availableHeight)
        naturalSize = size

        transition.updateFrame(view: backgroundView, frame: CGRect(origin: .zero, size: size))
        transition.updateFrame(view: controlsView, frame: CGRect(origin: .zero, size: size))
        backgroundView.update(
            size: size,
            cornerRadius: size.height * 0.5,
            isDark: isDark,
            tintColor: tintColor,
            isInteractive: isInteractiveOverall,
            transition: transition
        )
        if didChangeVisualItems {
            let pulseAmplitude = insertedEntryCount > 0 || removedEntryCount == 0 ? Overspring.itemChangeAmplitude : -Overspring.itemChangeAmplitude
            animateGroupPulse(transition: transition, amplitude: pulseAmplitude)
        }

        frame.size = size
        return size
    }

    private func softItemTransition(for transition: ContainedViewLayoutTransition, appearing: Bool) -> ContainedViewLayoutTransition {
        guard transition.isAnimated else {
            return .immediate
        }
        let duration = max(0.38, transition.duration * 0.78)
        let curve: ContainedViewLayoutTransitionCurve = appearing
            ? .custom(0.16, 1.0, 0.30, 1.0)
            : .custom(0.70, 0.0, 0.84, 0.0)
        return .animated(duration: duration, curve: curve)
    }

    private func animateInsertedButton(_ button: UIView, targetAlpha: CGFloat, transition: ContainedViewLayoutTransition) {
        guard transition.isAnimated && animatesInsertedItemsAlpha else {
            button.alpha = targetAlpha
            button.transform = .identity
            ContainedViewLayoutTransition.immediate.setBlur(layer: button.layer, radius: 0.0)
            return
        }

        let softTransition = softItemTransition(for: transition, appearing: true)
        button.alpha = 0.0
        button.transform = CGAffineTransform(scaleX: Overspring.itemTransitionScale, y: Overspring.itemTransitionScale)
        ContainedViewLayoutTransition.immediate.setBlur(layer: button.layer, radius: 8.0)
        softTransition.updateAlpha(view: button, alpha: targetAlpha)
        softTransition.updateTransform(view: button, transform: .identity)
        softTransition.setBlur(layer: button.layer, radius: 0.0)
    }

    private func restoreExistingButton(_ button: UIView, targetAlpha: CGFloat, transition: ContainedViewLayoutTransition) {
        guard transition.isAnimated && animatesInsertedItemsAlpha else {
            button.alpha = targetAlpha
            button.transform = .identity
            ContainedViewLayoutTransition.immediate.setBlur(layer: button.layer, radius: 0.0)
            return
        }

        let softTransition = softItemTransition(for: transition, appearing: true)
        softTransition.updateAlpha(view: button, alpha: targetAlpha)
        softTransition.updateTransform(view: button, transform: .identity)
        softTransition.setBlur(layer: button.layer, radius: 0.0)
    }

    private func animateRemovedButton(_ button: UIView, transition: ContainedViewLayoutTransition) {
        guard transition.isAnimated else {
            button.removeFromSuperview()
            return
        }

        guard animatesInsertedItemsAlpha else {
            transition.updateAlpha(view: button, alpha: 0.0) { [weak button] _ in
                button?.removeFromSuperview()
            }
            return
        }

        let softTransition = softItemTransition(for: transition, appearing: false)
        button.isUserInteractionEnabled = false
        softTransition.updateAlpha(view: button, alpha: 0.0)
        softTransition.updateTransform(view: button, transform: CGAffineTransform(scaleX: Overspring.itemTransitionScale, y: Overspring.itemTransitionScale))
        softTransition.setBlur(layer: button.layer, radius: 8.0) { [weak button] _ in
            button?.removeFromSuperview()
        }
    }

    private func animateGroupPulse(transition: ContainedViewLayoutTransition, amplitude: CGFloat) {
        guard transition.isAnimated && animatesInsertedItemsAlpha else {
            return
        }
        applyOverspringPulseIfNeeded(to: self, amplitude: amplitude, transition: transition)
    }

    public func setContentTransitionEffects(alpha: CGFloat, blurRadius: CGFloat, scale: CGFloat = 1.0, horizontalScale: CGFloat = 1.0, pulseAmplitude: CGFloat = 0.0, transition: ContainedViewLayoutTransition) {
        let transform = CGAffineTransform(scaleX: scale * horizontalScale, y: scale)
        transition.updateTransform(view: backgroundView, transform: transform)
        transition.updateAlpha(view: controlsView, alpha: alpha)
        transition.updateTransform(view: controlsView, transform: transform)
        transition.setBlur(layer: controlsView.layer, radius: blurRadius)
        applyOverspringPulseIfNeeded(to: self, amplitude: pulseAmplitude, transition: transition)
    }

    public func setContentTransform(scale: CGFloat = 1.0, horizontalScale: CGFloat = 1.0, transition: ContainedViewLayoutTransition) {
        let transform = CGAffineTransform(scaleX: scale * horizontalScale, y: scale)
        transition.updateTransform(view: backgroundView, transform: transform)
        transition.updateTransform(view: controlsView, transform: transform)
    }

    private func applyOverspringPulseIfNeeded(to view: UIView, amplitude: CGFloat, transition: ContainedViewLayoutTransition) {
        let resolvedAmplitude = abs(amplitude)
        guard resolvedAmplitude > 0.0, transition.isAnimated, !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        let duration = max(0.34, min(0.50, transition.duration))
        view.layer.removeAnimation(forKey: "aether.glassButtonOverspringPulse")

        let baseTransform = view.layer.transform
        let peakTransform = CATransform3DScale(baseTransform, 1.0 + resolvedAmplitude, 1.0 + resolvedAmplitude, 1.0)
        let undershootScale = max(0.968, 1.0 - resolvedAmplitude * 0.30)
        let undershootTransform = CATransform3DScale(baseTransform, undershootScale, undershootScale, 1.0)
        let animation = CAKeyframeAnimation(keyPath: "transform")
        if amplitude >= 0.0 {
            animation.values = [baseTransform, peakTransform, undershootTransform, baseTransform]
        } else {
            animation.values = [baseTransform, undershootTransform, peakTransform, baseTransform]
        }
        animation.keyTimes = [0.0, 0.36, 0.74, 1.0]
        animation.duration = duration
        let timingFunction = amplitude >= 0.0
            ? CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.30, 1.0)
            : CAMediaTimingFunction(controlPoints: 0.70, 0.0, 0.84, 0.0)
        animation.timingFunctions = [timingFunction, timingFunction, timingFunction]
        animation.isRemovedOnCompletion = true
        animation.aetherPreferHighFrameRate()
        view.layer.add(animation, forKey: "aether.glassButtonOverspringPulse")
    }

    public func setTransitionChromeSize(
        _ size: CGSize,
        contentAlignment: TransitionChromeContentAlignment = .leading,
        transition: ContainedViewLayoutTransition
    ) {
        setTransitionChromeFrame(
            CGRect(origin: frame.origin, size: size),
            contentAlignment: contentAlignment,
            transition: transition
        )
    }

    public func setTransitionChromeFrame(
        _ frame: CGRect,
        contentAlignment: TransitionChromeContentAlignment = .leading,
        transition: ContainedViewLayoutTransition
    ) {
        let resolvedSize = CGSize(width: max(0.0, frame.width), height: max(0.0, frame.height))
        let resolvedFrame = CGRect(origin: frame.origin, size: resolvedSize)
        let contentOffsetX: CGFloat
        switch contentAlignment {
        case .leading:
            contentOffsetX = 0.0
        case .trailing:
            contentOffsetX = resolvedSize.width - naturalSize.width
        }
        for entry in itemViews {
            transition.updateFrame(view: entry.button, frame: entry.itemFrame.offsetBy(dx: contentOffsetX, dy: 0.0))
        }
        transition.updateFrame(view: self, frame: resolvedFrame)
        transition.updateFrame(view: backgroundView, frame: CGRect(origin: .zero, size: resolvedSize))
        transition.updateFrame(view: controlsView, frame: CGRect(origin: .zero, size: resolvedSize))
        backgroundView.update(
            size: resolvedSize,
            cornerRadius: resolvedSize.height * 0.5,
            isDark: isDarkAppearance,
            tintColor: currentTintColor,
            isInteractive: currentIsInteractive,
            transition: transition
        )
    }

    public func setTransitionChromeAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        transition.updateAlpha(view: backgroundView, alpha: alpha)
    }

    private func applyForegroundColorToItems() {
        for entry in itemViews {
            if let image = entry.contentView as? UIImageView {
                image.tintColor = foregroundColor
                image.setMonochromaticEffect(tintColor: foregroundColor)
            } else if let label = entry.contentView as? UILabel {
                label.textColor = foregroundColor
            }
        }
    }

    // MARK: - Public accessors

    public func itemView(id: AnyHashable) -> UIView? {
        return itemViews.first(where: { $0.id == id })?.contentView
    }

    /// The tappable button slot for the item with the given id, or `nil`
    /// if no such item lives in the group. Used by callers that want to
    /// anchor a popover / context menu to the visible capsule cell —
    /// `itemView(id:)` returns just the inner icon/label, which is too
    /// small a target for that.
    public func itemButton(id: AnyHashable) -> UIView? {
        return itemViews.first(where: { $0.id == id })?.button
    }

    /// Visual source used by menu/presentation leases. A single-item group
    /// reads as one glass button, so the whole group is the visual owner.
    /// Multi-item groups share one background; in that case only the item
    /// button/content can be leased without hiding siblings.
    public func itemVisualSourceView(id: AnyHashable) -> UIView? {
        guard let entry = itemViews.first(where: { $0.id == id }) else {
            return nil
        }
        return itemViews.count == 1 ? self : entry.button
    }

    public func visualSourceView(containing view: UIView) -> UIView? {
        for entry in itemViews {
            if entry.button === view || entry.button.isDescendant(of: view) || view.isDescendant(of: entry.button) {
                return itemViews.count == 1 ? self : entry.button
            }
        }
        return nil
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        let count = CGFloat(max(1, items.count))
        let itemSize: CGFloat = 44.0
        return CGSize(width: itemSize * count, height: itemSize)
    }
}

// MARK: - HighlightTrackingButton
// Lightweight port of `HighlightTrackingButton` from `submodules/Display/Source/HighlightTrackingButton.swift`.

final class HighlightTrackingButton: UIButton {
    var highlightedChanged: ((Bool) -> Void)?
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted != oldValue {
                highlightedChanged?(isHighlighted)
            }
        }
    }

    @objc private func tapped() {
        onTap?()
    }
}

// MARK: - GlassControlPanel

/// Panel with left / centre / right groups of glass controls merged into a
/// shared `UIGlassContainerEffect` on iOS 26+.
/// Port of Display framework `GlassControlPanelComponent`.
public final class GlassControlPanel: UIView {
    public struct PanelItem {
        public let items: [GlassControlGroup.Item]
        public let background: GlassControlGroup.Background
        public let keepWide: Bool
        public let foregroundColor: UIColor?

        public init(
            items: [GlassControlGroup.Item],
            background: GlassControlGroup.Background = .panel,
            keepWide: Bool = false,
            foregroundColor: UIColor? = nil
        ) {
            self.items = items
            self.background = background
            self.keepWide = keepWide
            self.foregroundColor = foregroundColor
        }
    }

    private let glassContainerView: GlassBackgroundContainerView
    private var leftGroup: GlassControlGroup?
    private var centerGroup: GlassControlGroup?
    private var rightGroup: GlassControlGroup?

    private var leftItem: PanelItem?
    private var centralItem: PanelItem?
    private var rightItem: PanelItem?
    private var centerAlignmentIfPossible: Bool = false
    private var preferClearGlass: Bool = false
    /// Forwards into the underlying `GlassBackgroundContainerView` on
    /// change so the container's shared glass effect picks up the theme
    /// override without requiring a fresh `update(...)` call.
    private var isDarkAppearance: Bool = false {
        didSet {
            if isDarkAppearance == oldValue { return }
            glassContainerView.isDarkOverride = isDarkAppearance
        }
    }

    public override init(frame: CGRect) {
        self.glassContainerView = GlassBackgroundContainerView(spacing: 7.0)
        super.init(frame: frame)

        addSubview(glassContainerView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(
        leftItem: PanelItem?,
        centralItem: PanelItem?,
        rightItem: PanelItem?,
        centerAlignmentIfPossible: Bool = false,
        preferClearGlass: Bool = false,
        isDark: Bool = false,
        availableSize: CGSize,
        transition: ContainedViewLayoutTransition = .immediate
    ) -> CGSize {
        self.leftItem = leftItem
        self.centralItem = centralItem
        self.rightItem = rightItem
        self.centerAlignmentIfPossible = centerAlignmentIfPossible
        self.preferClearGlass = preferClearGlass
        self.isDarkAppearance = isDark

        let minSpacing: CGFloat = 8.0

        // Left
        var leftFrame: CGRect?
        if let leftItem {
            let group: GlassControlGroup
            if let existing = leftGroup {
                group = existing
            } else {
                group = GlassControlGroup()
                glassContainerView.contentView.addSubview(group)
                leftGroup = group
            }
            let size = group.update(
                items: leftItem.items,
                background: leftItem.background,
                preferClearGlass: preferClearGlass,
                foregroundColor: leftItem.foregroundColor,
                isDark: isDark,
                availableHeight: availableSize.height,
                minWidth: availableSize.height,
                transition: transition
            )
            let frame = CGRect(origin: .zero, size: size)
            leftFrame = frame
            transition.updateFrame(view: group, frame: frame)
        } else if let existing = leftGroup {
            leftGroup = nil
            if transition.isAnimated {
                transition.updateAlpha(view: existing, alpha: 0.0) { [weak existing] _ in existing?.removeFromSuperview() }
            } else {
                existing.removeFromSuperview()
            }
        }

        // Right
        var rightFrame: CGRect?
        if let rightItem {
            let group: GlassControlGroup
            if let existing = rightGroup {
                group = existing
            } else {
                group = GlassControlGroup()
                glassContainerView.contentView.addSubview(group)
                rightGroup = group
            }
            let size = group.update(
                items: rightItem.items,
                background: rightItem.background,
                preferClearGlass: preferClearGlass,
                foregroundColor: rightItem.foregroundColor,
                isDark: isDark,
                availableHeight: availableSize.height,
                minWidth: availableSize.height,
                transition: transition
            )
            let frame = CGRect(origin: CGPoint(x: availableSize.width - size.width, y: 0.0), size: size)
            rightFrame = frame
            transition.updateFrame(view: group, frame: frame)
        } else if let existing = rightGroup {
            rightGroup = nil
            if transition.isAnimated {
                transition.updateAlpha(view: existing, alpha: 0.0) { [weak existing] _ in existing?.removeFromSuperview() }
            } else {
                existing.removeFromSuperview()
            }
        }

        // Central
        if let centralItem {
            let group: GlassControlGroup
            if let existing = centerGroup {
                group = existing
            } else {
                group = GlassControlGroup()
                glassContainerView.contentView.addSubview(group)
                centerGroup = group
            }

            var centerLeftInset: CGFloat = 0.0
            var centerRightInset: CGFloat = 0.0
            if let leftFrame {
                centerLeftInset = leftFrame.maxX + minSpacing
            }
            if let rightFrame {
                centerRightInset = availableSize.width - rightFrame.minX + minSpacing
            }
            if centerLeftInset <= 48.0, centerRightInset <= 48.0 {
                let maxInset = max(centerLeftInset, centerRightInset)
                centerLeftInset = maxInset
                centerRightInset = maxInset
            }

            let size = group.update(
                items: centralItem.items,
                background: centralItem.background,
                preferClearGlass: preferClearGlass,
                foregroundColor: centralItem.foregroundColor,
                isDark: isDark,
                availableHeight: availableSize.height,
                minWidth: centralItem.keepWide ? 165.0 : availableSize.height,
                transition: transition
            )

            var originX = centerLeftInset + floor((availableSize.width - centerLeftInset - centerRightInset - size.width) / 2.0)
            if centerAlignmentIfPossible {
                let maxInset = max(centerLeftInset, centerRightInset)
                if availableSize.width - maxInset * 2.0 > size.width {
                    originX = maxInset + floor((availableSize.width - maxInset * 2.0 - size.width) / 2.0)
                }
            }

            transition.updateFrame(view: group, frame: CGRect(origin: CGPoint(x: originX, y: 0.0), size: size))
        } else if let existing = centerGroup {
            centerGroup = nil
            if transition.isAnimated {
                transition.updateAlpha(view: existing, alpha: 0.0) { [weak existing] _ in existing?.removeFromSuperview() }
            } else {
                existing.removeFromSuperview()
            }
        }

        transition.updateFrame(view: glassContainerView, frame: CGRect(origin: .zero, size: availableSize))
        glassContainerView.update(size: availableSize, isDark: isDark, transition: transition)

        frame.size = availableSize
        return availableSize
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        if result === self {
            return nil
        }
        return result
    }
}
