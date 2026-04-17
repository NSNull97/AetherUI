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
    private var itemViews: [ItemEntry] = []

    private struct ItemEntry {
        let id: AnyHashable
        let contentId: ContentId
        let button: HighlightTrackingButton
        let contentView: UIView
        var contentInsets: UIEdgeInsets
        var isInteractive: Bool
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

    // MARK: - Init

    public init(style: GlassBackgroundView.Style = .regular) {
        self.backgroundView = GlassBackgroundView(style: style)

        super.init(frame: .zero)

        addSubview(backgroundView)
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
        self.foregroundColor = derivedForeground

        // Diff item views by (id, content-id).
        var newEntries: [ItemEntry] = []
        newEntries.reserveCapacity(items.count)

        let alphaTransition: ContainedViewLayoutTransition = transition.isAnimated ? .animated(duration: 0.2, curve: .easeInOut) : .immediate

        var isInteractiveOverall = false
        var contentsWidth: CGFloat = 0.0

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
            if let existingIndex {
                entry = itemViews.remove(at: existingIndex)
                entry.contentInsets = item.contentInsets
                entry.isInteractive = item.action != nil
                // Keep existing content view; just update action.
            } else {
                let button = HighlightTrackingButton(type: .custom)
                button.isUserInteractionEnabled = item.action != nil
                button.addSubview(freshView)
                backgroundView.contentView.addSubview(button)

                entry = ItemEntry(
                    id: item.id,
                    contentId: contentId,
                    button: button,
                    contentView: freshView,
                    contentInsets: item.contentInsets,
                    isInteractive: item.action != nil
                )
                button.alpha = 0.0
                alphaTransition.updateAlpha(view: button, alpha: item.action != nil ? 1.0 : 0.5)
            }

            // Wire action.
            entry.button.onTap = { item.action?() }
            entry.button.alpha = item.action != nil ? 1.0 : 0.5

            if item.action != nil {
                isInteractiveOverall = true
            }

            // Measure content.
            let maxContentHeight = availableHeight
            var contentSize = freshView.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: maxContentHeight))
            if case .customView = item.content {
                contentSize = freshView.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: maxContentHeight))
                if contentSize == .zero {
                    contentSize = freshView.bounds.size
                }
            } else if case .text = item.content {
                contentSize.width = ceil(contentSize.width)
                contentSize.height = ceil(contentSize.height)
            } else {
                // Icon buttons use a 36pt icon per Figma spec — visibly larger
                // than the previous 28pt so they're easy to tap on a glass
                // capsule and match the iOS 26 reference size.
                contentSize = CGSize(width: 36.0, height: 36.0)
            }

            // Item frame is at least max(minWidth, availableHeight) wide for single-item groups.
            var itemWidth = contentSize.width + entry.contentInsets.left + entry.contentInsets.right
            itemWidth = max(itemWidth, availableHeight)
            if items.count == 1 {
                itemWidth = max(itemWidth, minWidth)
            }

            let itemFrame = CGRect(x: contentsWidth, y: 0.0, width: itemWidth, height: availableHeight)
            transition.updateFrame(view: entry.button, frame: itemFrame)

            // Center the content view inside the button with contentInsets.
            let contentOrigin = CGPoint(
                x: entry.contentInsets.left + floor((itemWidth - entry.contentInsets.left - entry.contentInsets.right - contentSize.width) / 2.0),
                y: floor((availableHeight - contentSize.height) / 2.0)
            )
            transition.updateFrame(
                view: freshView,
                frame: CGRect(origin: contentOrigin, size: contentSize)
            )

            newEntries.append(entry)
            contentsWidth += itemWidth
        }

        // Remove stale views.
        for stale in itemViews {
            if transition.isAnimated {
                alphaTransition.updateAlpha(view: stale.button, alpha: 0.0) { [weak button = stale.button] _ in
                    button?.removeFromSuperview()
                }
            } else {
                stale.button.removeFromSuperview()
            }
        }
        itemViews = newEntries

        // If there are no items, collapse the group entirely — otherwise the
        // glass capsule would still render at its min-width size, producing a
        // visible empty pill next to real content (matches behaviour).
        if items.isEmpty {
            transition.updateFrame(view: backgroundView, frame: .zero)
            backgroundView.isHidden = true
            frame.size = .zero
            return .zero
        }

        backgroundView.isHidden = false
        let size = CGSize(width: max(availableHeight, contentsWidth), height: availableHeight)

        transition.updateFrame(view: backgroundView, frame: CGRect(origin: .zero, size: size))
        backgroundView.update(
            size: size,
            cornerRadius: size.height * 0.5,
            isDark: isDark,
            tintColor: tintColor,
            isInteractive: isInteractiveOverall,
            transition: transition
        )

        frame.size = size
        return size
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
                applyPressAnimation(pressed: isHighlighted)
            }
        }
    }

    /// Port of glass-press animation: spring-scale up to 1.1 on
    /// press, relax back to 1.0 on release. Subtle but unmistakably iOS 26.
    private func applyPressAnimation(pressed: Bool) {
        // Use a CASpring on `transform.scale` for the natural squash feel.
        let key = "transform.scale"
        layer.removeAnimation(forKey: key)

        let fromValue = (layer.presentation()?.value(forKeyPath: "transform.scale.x") as? NSNumber)?.floatValue
            ?? Float(pressed ? 1.0 : 1.0)
        let toValue: Float = pressed ? 1.0 : 1.0

        let spring = CASpringAnimation(keyPath: key)
        spring.fromValue = fromValue
        spring.toValue = toValue
        spring.mass = 1.0
        spring.stiffness = pressed ? 520.0 : 480.0
        spring.damping = pressed ? 34.0 : 22.0
        spring.initialVelocity = 0.0
        spring.duration = spring.settlingDuration
        spring.fillMode = .forwards
        spring.isRemovedOnCompletion = false

        layer.add(spring, forKey: key)
        // Set the final model value so the layer stays at the target after
        // the animation completes.
        layer.setValue(toValue, forKeyPath: key)
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
