import UIKit

/// Custom tab bar view with Telegram-style rendering and glass support.
/// Replaces Telegram's ASDK-based TabBarNode.
public final class TabBarView: UIView {
    // MARK: - Types

    public enum Style {
        case legacy
        case liquidGlass
    }

    public struct Theme {
        public let tabBarBackgroundColor: UIColor
        public let tabBarSeparatorColor: UIColor
        public let tabBarIconColor: UIColor
        public let tabBarSelectedIconColor: UIColor
        public let tabBarTextColor: UIColor
        public let tabBarSelectedTextColor: UIColor
        public let tabBarBadgeBackgroundColor: UIColor
        public let tabBarBadgeStrokeColor: UIColor
        public let tabBarBadgeTextColor: UIColor
        public let enableBlur: Bool
        public let isDark: Bool
        public let style: Style
        public let outerInsets: UIEdgeInsets

        public init(
            tabBarBackgroundColor: UIColor = .systemBackground,
            tabBarSeparatorColor: UIColor = .separator,
            tabBarIconColor: UIColor = .label,
            tabBarSelectedIconColor: UIColor = .systemBlue,
            tabBarTextColor: UIColor = .label,
            tabBarSelectedTextColor: UIColor = .systemBlue,
            tabBarBadgeBackgroundColor: UIColor = .systemRed,
            tabBarBadgeStrokeColor: UIColor = .white,
            tabBarBadgeTextColor: UIColor = .white,
            enableBlur: Bool = true,
            isDark: Bool = false,
            style: Style = .liquidGlass,
            outerInsets: UIEdgeInsets = UIEdgeInsets(top: 4.0, left: 25.0, bottom: 4.0, right: 25.0)
        ) {
            self.tabBarBackgroundColor = tabBarBackgroundColor
            self.tabBarSeparatorColor = tabBarSeparatorColor
            self.tabBarIconColor = tabBarIconColor
            self.tabBarSelectedIconColor = tabBarSelectedIconColor
            self.tabBarTextColor = tabBarTextColor
            self.tabBarSelectedTextColor = tabBarSelectedTextColor
            self.tabBarBadgeBackgroundColor = tabBarBadgeBackgroundColor
            self.tabBarBadgeStrokeColor = tabBarBadgeStrokeColor
            self.tabBarBadgeTextColor = tabBarBadgeTextColor
            self.enableBlur = enableBlur
            self.isDark = isDark
            self.style = style
            self.outerInsets = outerInsets
        }
    }

    // MARK: - Properties

    // MARK: - Types

    /// Companion "search showcase" capsule shown next to the main tab pill,
    /// mirroring iOS 26's native `UISearchTab`. On iOS 26+ both capsules share
    /// a `UIGlassContainerEffect` via `GlassBackgroundContainerView` so they
    /// merge visually when close.
    public struct SearchShowcase {
        public let icon: UIImage?
        public let action: () -> Void
        public init(icon: UIImage? = UIImage(systemName: "magnifyingglass"), action: @escaping () -> Void) {
            self.icon = icon
            self.action = action
        }
    }

    private let backgroundView: NavigationBackgroundView
    private let separatorView: UIView
    /// Container that hosts the lens + optional search showcase so they merge
    /// into a single `UIGlassContainerEffect` on iOS 26+.
    private let tabBarGlassContainer: GlassBackgroundContainerView
    private let liquidLensView: LiquidLensView
    private var searchShowcaseView: GlassBarButtonView?
    private var itemViews: [TabBarItemView] = []
    private var selectedItemViews: [TabBarItemView] = []

    private var glassBackgroundView: GlassBackgroundView?
    /// Scroll-edge fade at the bottom — makes content dissolve as it approaches
    /// the floating tab bar pill (mirrors Telegram's edge-effect on the TabBar).
    private let edgeEffectView = EdgeEffectView()
    private var theme: Theme

    public var searchShowcase: SearchShowcase? {
        didSet { rebuildSearchShowcase() }
    }

    public var items: [TelegramTabBarItem] = [] {
        didSet {
            rebuildItemViews()
        }
    }

    public var selectedIndex: Int = 0 {
        didSet {
            if selectedIndex != oldValue {
                updateSelection(animated: true)
            }
        }
    }

    public var tabSelected: ((Int) -> Void)?
    public var tabDoubleTapped: ((Int) -> Void)?
    public var tabLongPressed: ((Int, UIView, UIGestureRecognizer) -> Void)?
    public var tabSwipeAction: ((Int, TabBarItemSwipeDirection) -> Void)?
    public var itemHasDoubleTapAction: ((Int) -> Bool)?
    public var disabledPressed: (() -> Void)?

    private var interactionsEnabled: Bool = true
    private var lastTapIndex: Int?
    private var lastTapTimestamp: CFTimeInterval = 0.0

    /// Drag-to-select state. Mirrors `TabBarComponent.selectionGestureState`:
    /// the native iOS 26 interaction where the liquid lens follows the user's
    /// finger as they drag across tabs.
    private struct SelectionGestureState {
        var startIndex: Int
        var currentIndex: Int
        var currentX: CGFloat
        var itemWidth: CGFloat
    }
    private var selectionGestureState: SelectionGestureState?

    // MARK: - Init

    public init(theme: Theme = Theme()) {
        self.theme = theme
        self.backgroundView = NavigationBackgroundView(color: theme.tabBarBackgroundColor, enableBlur: theme.enableBlur)
        self.separatorView = UIView()
        self.tabBarGlassContainer = GlassBackgroundContainerView(spacing: 7.0)
        self.liquidLensView = LiquidLensView(kind: .externalContainer)

        super.init(frame: .zero)

        addSubview(backgroundView)
        separatorView.backgroundColor = theme.tabBarSeparatorColor
        addSubview(separatorView)

        // Bottom scroll-edge fade — placed under the floating tab pill so
        // scroll content dissolves as it approaches the pill edge (mirrors
        // Telegram's EdgeEffect on TabBar).
        edgeEffectView.isUserInteractionEnabled = false
        insertSubview(edgeEffectView, aboveSubview: backgroundView)

        // Put the lens (and future search showcase) inside the shared container
        // so iOS 26's `UIGlassContainerEffect` can merge them when close.
        addSubview(tabBarGlassContainer)
        tabBarGlassContainer.contentView.addSubview(liquidLensView)

        let lensTap = UITapGestureRecognizer(target: self, action: #selector(lensTapped(_:)))
        liquidLensView.addGestureRecognizer(lensTap)

        // Drag-to-select: lens follows the finger. Matches the native iOS 26
        // TabBarController pan interaction.
        let lensPan = TabSelectionRecognizer(target: self, action: #selector(lensPanned(_:)))
        liquidLensView.addGestureRecognizer(lensPan)

        let lensLongPress = UILongPressGestureRecognizer(target: self, action: #selector(lensLongPressed(_:)))
        liquidLensView.addGestureRecognizer(lensLongPress)

        let lensSwipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(lensSwiped(_:)))
        lensSwipeLeft.direction = .left
        liquidLensView.addGestureRecognizer(lensSwipeLeft)

        let lensSwipeRight = UISwipeGestureRecognizer(target: self, action: #selector(lensSwiped(_:)))
        lensSwipeRight.direction = .right
        liquidLensView.addGestureRecognizer(lensSwipeRight)

        setGlassStyle(enabled: theme.enableBlur)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Theme

    public func updateTheme(_ theme: Theme) {
        self.theme = theme
        backgroundView.updateColor(color: theme.tabBarBackgroundColor, enableBlur: theme.enableBlur, transition: .immediate)
        separatorView.backgroundColor = theme.tabBarSeparatorColor
        setGlassStyle(enabled: theme.enableBlur)
        rebuildItemViews()
        updateSelection(animated: false)
    }

    // MARK: - Glass

    public func setGlassStyle(enabled: Bool) {
        if theme.style == .liquidGlass {
            glassBackgroundView?.removeFromSuperview()
            glassBackgroundView = nil
            backgroundView.alpha = 0.0
            separatorView.alpha = 0.0
            liquidLensView.isHidden = false
            return
        }

        liquidLensView.isHidden = true
        separatorView.alpha = 1.0
        if enabled {
            if glassBackgroundView == nil {
                let glass = GlassBackgroundView(style: .regular)
                insertSubview(glass, aboveSubview: backgroundView)
                self.glassBackgroundView = glass
                layoutGlassBackground()
            }
            backgroundView.alpha = 0.0
        } else {
            glassBackgroundView?.removeFromSuperview()
            glassBackgroundView = nil
            backgroundView.alpha = 1.0
        }
    }

    public func updateInteractionsEnabled(_ enabled: Bool, transition: ContainedViewLayoutTransition) {
        interactionsEnabled = enabled
        transition.updateAlpha(view: self, alpha: enabled ? 1.0 : 0.5)
    }

    public func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        backgroundView.updateBackgroundAlpha(alpha, transition: transition)
        transition.updateAlpha(view: separatorView, alpha: alpha)
        if let glassBackgroundView {
            transition.updateAlpha(view: glassBackgroundView, alpha: alpha)
        }
        transition.updateAlpha(view: liquidLensView, alpha: alpha)
    }

    // MARK: - Layout

    override public func layoutSubviews() {
        super.layoutSubviews()

        backgroundView.frame = bounds
        backgroundView.update(size: bounds.size, transition: .immediate)

        separatorView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: UIScreenPixel)

        // Scroll-edge frost anchored to the TOP of the tab bar. Covers the
        // entire tab bar area; fade zone terminates at the top boundary
        // (transparent there), transitioning cleanly from the scroll content
        // above to the floating pill below.
        if theme.style == .liquidGlass {
            edgeEffectView.isHidden = false
            let edgeFrame = CGRect(x: 0.0, y: 56, width: bounds.width, height: bounds.height - 56)
            edgeEffectView.frame = edgeFrame
            let fadeHeight: CGFloat = min(48, edgeFrame.height * 0.4)
            edgeEffectView.update(
                content: theme.tabBarBackgroundColor,
                blur: true,
                alpha: 0.65,
                rect: CGRect(origin: .zero, size: edgeFrame.size),
                edge: .bottom, // solid at BOTTOM (screen bottom), fade at TOP (content boundary)
                edgeSize: fadeHeight,
                blurRadiusAtEdge: 3.0, // strong blur near the screen bottom
                blurRadiusAtFade: 3.0, // tapers to almost nothing as it meets the scroll content
                transition: .immediate
            )
        } else {
            edgeEffectView.isHidden = true
        }

        layoutGlassBackground()
        layoutItemViews()
    }

    /// Effective dark flag — follows the system interface style in addition
    /// to the static theme flag. `theme.isDark` is often false even on a
    /// dark-mode device (the default theme doesn't carry that info), which
    /// caused the tab bar to render with a light tint on dark mode under
    /// `GlassBackgroundView.useCustomGlassImpl`.
    private var isEffectivelyDark: Bool {
        theme.isDark || traitCollection.userInterfaceStyle == .dark
    }

    private func layoutGlassBackground() {
        guard let glassBackgroundView else {
            return
        }
        glassBackgroundView.frame = bounds
        glassBackgroundView.update(
            size: bounds.size,
            cornerRadius: 0.0,
            isDark: isEffectivelyDark,
            tintColor: .init(kind: .panel),
            isInteractive: false,
            isVisible: true,
            transition: .immediate
        )
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            setNeedsLayout()
        }
    }

    private func layoutItemViews() {
        guard !itemViews.isEmpty else { return }

        let count = itemViews.count
        if theme.style == .liquidGlass {
            layoutLiquidGlassItems(count: count)
            return
        }

        liquidLensView.isHidden = true
        let itemWidth = bounds.width / CGFloat(count)
        let contentHeight: CGFloat = 49.0

        for (index, itemView) in itemViews.enumerated() {
            let x = CGFloat(index) * itemWidth
            itemView.frame = CGRect(x: x, y: 0, width: itemWidth, height: contentHeight)
        }
    }

    private func rebuildSearchShowcase() {
        searchShowcaseView?.removeFromSuperview()
        searchShowcaseView = nil

        guard let config = searchShowcase else {
            setNeedsLayout()
            return
        }

        let button = GlassBarButtonView(icon: config.icon, title: nil, state: .glass)
        button.contentTintColor = theme.tabBarIconColor
        button.action = { _ in config.action() }
        tabBarGlassContainer.contentView.addSubview(button)
        searchShowcaseView = button
        setNeedsLayout()
    }

    private func layoutLiquidGlassItems(count: Int) {
        liquidLensView.isHidden = false

        // 60pt pill height accommodates 8pt top inset + 30pt icon + 1pt +
        // 13pt label + 8pt bottom inset for each tab item (per Figma spec).
        let contentHeight: CGFloat = 62.0

        // Figma-spec insets:
        //  - sides: 25pt
        //  - bottom: 25pt from the SCREEN bottom (not safe area)
        //  - gap between pill and search: 8pt
        let sideInset: CGFloat = 16.0
        let bottomInset: CGFloat = 25.0
        let showcaseSpacing: CGFloat = 8.0

        let availableWidth = max(0.0, bounds.width - sideInset * 2.0)

        // Pill sizes to its content — each tab item gets a natural width so the
        // pill doesn't stretch to fill. Matches Figma where the main pill is a
        // compact group rather than spanning the screen.
        let perItemWidth: CGFloat = 72.0
        let naturalPillWidth = perItemWidth * CGFloat(count)

        let showcaseSize: CGFloat = searchShowcaseView != nil ? contentHeight : 0.0
        let showcaseFootprint: CGFloat = showcaseSize > 0.0 ? showcaseSize + showcaseSpacing : 0.0

        let pillWidth = min(naturalPillWidth, max(0.0, availableWidth - showcaseFootprint))
        let lensSize = CGSize(width: pillWidth, height: contentHeight)

        // Pill is centered in the space that's left after reserving room for
        // the search circle on the right (which anchors to the right side inset).
        let pillAvailableWidth = availableWidth - showcaseFootprint
        let pillX = sideInset + floor((pillAvailableWidth - pillWidth) / 2.0)
        let showcaseX = bounds.width - sideInset - showcaseSize

        // Pill bottom is pinned 25pt from the bottom of the screen (== bottom
        // of `bounds` since the tab bar view hugs the screen bottom).
        let pillY = bounds.height - bottomInset - contentHeight

        let containerFrame = CGRect(
            x: pillX,
            y: pillY,
            width: (showcaseSize > 0.0 ? (showcaseX + showcaseSize) - pillX : pillWidth),
            height: contentHeight
        )
        tabBarGlassContainer.frame = containerFrame
        tabBarGlassContainer.update(size: containerFrame.size, isDark: isEffectivelyDark, transition: .immediate)

        // Lens / showcase positions are relative to the container's origin.
        liquidLensView.frame = CGRect(origin: .zero, size: lensSize)

        if let showcase = searchShowcaseView {
            let localShowcaseX = showcaseX - pillX
            showcase.frame = CGRect(x: localShowcaseX, y: 0.0, width: showcaseSize, height: showcaseSize)
        }

        let itemWidth = lensSize.width / CGFloat(count)
        var selectionFrame = CGRect(x: 0.0, y: 0.0, width: max(56.0, itemWidth), height: lensSize.height)

        for (index, itemView) in itemViews.enumerated() {
            let itemFrame = CGRect(x: CGFloat(index) * itemWidth, y: 0.0, width: itemWidth, height: lensSize.height)
            itemView.frame = itemFrame
            if index < selectedItemViews.count {
                selectedItemViews[index].frame = itemFrame
            }
            if index == selectedIndex {
                selectionFrame = itemFrame.insetBy(dx: -4.0, dy: 0.0)
            }
        }

        // Drag-to-select: override the lens origin to follow the user's finger.
        // Clamped to the lens bounds so the lens can't leave the pill.
        if let drag = selectionGestureState {
            let maxOriginX = lensSize.width - selectionFrame.width
            let targetX = max(-4.0, min(maxOriginX, drag.currentX - 4.0))
            selectionFrame.origin.x = targetX
        }

        selectionFrame.origin.x = max(0.0, min(selectionFrame.origin.x, lensSize.width - selectionFrame.width))

        // iOS 26 native "liquid" lift: while the user is actively dragging
        // the lens, forward `isLifted = true` to the underlying
        // `_UILiquidLensView`. This triggers the system's liquid morph —
        // the selection capsule elevates/stretches out of the pill as the
        // finger moves, matching the Figma / iOS 26 reference.
        let isDraggingLens = selectionGestureState != nil
        liquidLensView.update(
            size: lensSize,
            selectionOrigin: selectionFrame.origin,
            selectionSize: selectionFrame.size,
            inset: 4.0,
            isDark: isEffectivelyDark,
            isLifted: isDraggingLens,
            transition: isDraggingLens ? .animated(duration: 0.25, curve: .spring) : .animated(duration: 0.35, curve: .spring)
        )
        // Lens already positioned at (0, 0, lensSize) inside the container.
    }

    // MARK: - Items

    private func rebuildItemViews() {
        itemViews.forEach { $0.removeFromSuperview() }
        selectedItemViews.forEach { $0.removeFromSuperview() }
        itemViews = []
        selectedItemViews = []

        for (index, item) in items.enumerated() {
            let itemView = TabBarItemView(item: item, theme: theme, selected: theme.style == .legacy && index == selectedIndex)
            itemView.tag = index

            let tap = UITapGestureRecognizer(target: self, action: #selector(itemTapped(_:)))
            itemView.addGestureRecognizer(tap)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(itemLongPressed(_:)))
            itemView.addGestureRecognizer(longPress)

            let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(itemSwiped(_:)))
            swipeLeft.direction = .left
            itemView.addGestureRecognizer(swipeLeft)

            let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(itemSwiped(_:)))
            swipeRight.direction = .right
            itemView.addGestureRecognizer(swipeRight)

            let selectedItemView = TabBarItemView(item: item, theme: theme, selected: true)
            selectedItemView.tag = index
            selectedItemView.isUserInteractionEnabled = false

            if theme.style == .liquidGlass {
                liquidLensView.contentView.addSubview(itemView)
                liquidLensView.selectedContentView.addSubview(selectedItemView)
            } else {
                addSubview(itemView)
            }
            itemViews.append(itemView)
            selectedItemViews.append(selectedItemView)
        }

        setNeedsLayout()
    }

    private func updateSelection(animated: Bool) {
        for (index, itemView) in itemViews.enumerated() {
            let isSelected = theme.style == .legacy && index == selectedIndex
            if animated {
                UIView.animate(withDuration: 0.2) {
                    itemView.isSelected = isSelected
                    if index < self.selectedItemViews.count {
                        self.selectedItemViews[index].isSelected = true
                    }
                }
            } else {
                itemView.isSelected = isSelected
                if index < selectedItemViews.count {
                    selectedItemViews[index].isSelected = true
                }
            }
        }
        setNeedsLayout()
    }

    // MARK: - Actions

    private func activateItem(at index: Int) {
        guard index < items.count else { return }
        guard interactionsEnabled, items[index].isEnabled else {
            disabledPressed?()
            return
        }

        let timestamp = CACurrentMediaTime()
        let isDoubleTap = lastTapIndex == index && (timestamp - lastTapTimestamp) < 0.35
        lastTapIndex = index
        lastTapTimestamp = timestamp

        if isDoubleTap, itemHasDoubleTapAction?(index) == true {
            tabDoubleTapped?(index)
            return
        }

        selectedIndex = index
        tabSelected?(index)
    }

    private func index(at point: CGPoint) -> Int? {
        for (index, itemView) in itemViews.enumerated() {
            let frame = convert(itemView.bounds, from: itemView)
            if frame.contains(point) {
                return index
            }
        }
        return nil
    }

    @objc private func lensPanned(_ recognizer: TabSelectionRecognizer) {
        guard theme.style == .liquidGlass, !items.isEmpty else { return }

        switch recognizer.state {
        case .began:
            let location = recognizer.location(in: liquidLensView)
            guard let idx = indexInLens(x: location.x) else { return }
            let itemW = liquidLensView.bounds.width / CGFloat(max(1, items.count))
            selectionGestureState = SelectionGestureState(
                startIndex: idx,
                currentIndex: idx,
                currentX: CGFloat(idx) * itemW,
                itemWidth: itemW
            )
            setNeedsLayout()
            layoutIfNeeded()
        case .changed:
            guard var state = selectionGestureState else { return }
            let translation = recognizer.translation(in: liquidLensView).x
            state.currentX = CGFloat(state.startIndex) * state.itemWidth + translation
            let location = recognizer.location(in: liquidLensView)
            if let idx = indexInLens(x: location.x) {
                state.currentIndex = idx
            }
            selectionGestureState = state
            setNeedsLayout()
            layoutIfNeeded()
        case .ended:
            if let state = selectionGestureState, items.indices.contains(state.currentIndex) {
                let newIndex = state.currentIndex
                selectionGestureState = nil
                if newIndex != selectedIndex {
                    selectedIndex = newIndex
                    tabSelected?(newIndex)
                } else {
                    setNeedsLayout()
                    layoutIfNeeded()
                }
            } else {
                selectionGestureState = nil
                setNeedsLayout()
                layoutIfNeeded()
            }
        case .cancelled, .failed:
            selectionGestureState = nil
            setNeedsLayout()
            layoutIfNeeded()
        default:
            break
        }
    }

    private func indexInLens(x: CGFloat) -> Int? {
        guard !items.isEmpty else { return nil }
        let itemW = liquidLensView.bounds.width / CGFloat(items.count)
        let idx = Int((max(0.0, x) / max(1.0, itemW)).rounded(.down))
        return min(items.count - 1, max(0, idx))
    }

    @objc private func lensTapped(_ recognizer: UITapGestureRecognizer) {
        guard theme.style == .liquidGlass, recognizer.state == .ended else {
            return
        }
        guard let index = index(at: recognizer.location(in: self)) else {
            return
        }
        activateItem(at: index)
    }

    @objc private func lensLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard theme.style == .liquidGlass, recognizer.state == .began else {
            return
        }
        guard let index = index(at: recognizer.location(in: self)) else {
            return
        }
        guard interactionsEnabled else {
            disabledPressed?()
            return
        }
        tabLongPressed?(index, itemViews[index], recognizer)
    }

    @objc private func lensSwiped(_ recognizer: UISwipeGestureRecognizer) {
        guard theme.style == .liquidGlass else {
            return
        }
        guard let index = index(at: recognizer.location(in: self)) else {
            return
        }
        guard interactionsEnabled else {
            disabledPressed?()
            return
        }
        let direction: TabBarItemSwipeDirection = recognizer.direction == .left ? .left : .right
        tabSwipeAction?(index, direction)
    }

    @objc private func itemTapped(_ recognizer: UITapGestureRecognizer) {
        guard let itemView = recognizer.view else { return }
        let index = itemView.tag
        activateItem(at: index)
    }

    @objc private func itemLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let itemView = recognizer.view else { return }
        guard interactionsEnabled else {
            disabledPressed?()
            return
        }
        tabLongPressed?(itemView.tag, itemView, recognizer)
    }

    @objc private func itemSwiped(_ recognizer: UISwipeGestureRecognizer) {
        guard let itemView = recognizer.view else {
            return
        }
        guard interactionsEnabled else {
            disabledPressed?()
            return
        }
        let direction: TabBarItemSwipeDirection = recognizer.direction == .left ? .left : .right
        tabSwipeAction?(itemView.tag, direction)
    }

    // MARK: - Public

    public func frameForTab(at index: Int) -> CGRect? {
        guard index < itemViews.count else { return nil }
        return convert(itemViews[index].bounds, from: itemViews[index])
    }

    /// Height the controller should reserve for the tab bar above the bottom
    /// safe area. 60pt pill + 25pt gap from the bottom of the screen.
    public class var defaultHeight: CGFloat {
        return 62 // 60 (pill) + 25 (bottom gap from screen bottom)
    }
}

// MARK: - TabBarItemView

private final class TabBarItemView: UIView {
    private let imageView: UIImageView
    private let textLabel: UILabel
    private let badgeView: NavigationBarBadgeView
    private var item: TelegramTabBarItem
    private var theme: TabBarView.Theme

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(item: TelegramTabBarItem, theme: TabBarView.Theme, selected: Bool) {
        self.item = item
        self.theme = theme
        self.isSelected = selected
        self.imageView = UIImageView()
        self.textLabel = UILabel()
        self.badgeView = NavigationBarBadgeView()

        super.init(frame: .zero)

        imageView.contentMode = .center
        addSubview(imageView)

        textLabel.font = UIFont.systemFont(ofSize: 11.0, weight: .medium)
        textLabel.textAlignment = .center
        addSubview(textLabel)

        addSubview(badgeView)
        if let badge = item.badgeValue, !badge.isEmpty {
            badgeView.text = badge
        }

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        imageView.image = (isSelected ? item.selectedImage : item.image)?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = isSelected ? theme.tabBarSelectedIconColor : theme.tabBarIconColor

        textLabel.text = item.title
        textLabel.textColor = isSelected ? theme.tabBarSelectedTextColor : theme.tabBarTextColor
        textLabel.font = UIFont.systemFont(ofSize: 10.0, weight: isSelected ? .bold : .medium)

        badgeView.badgeColor = theme.tabBarBadgeBackgroundColor
        badgeView.textColor = theme.tabBarBadgeTextColor
        badgeView.strokeColor = theme.tabBarBadgeStrokeColor
        badgeView.isHidden = item.badgeValue?.isEmpty ?? true
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Figma spec: 8pt inset on all sides of the item's content (icon +
        // label). With a 60pt-tall pill that leaves 44pt of vertical content,
        // which fits the 30pt icon + 1pt gap + 13pt label exactly.
        let contentInset: CGFloat = 8.0
        let imageSize: CGFloat = 36.0
        let textFontSize: CGFloat = 10.0
        textLabel.font = UIFont.systemFont(ofSize: textFontSize, weight: isSelected ? .bold : .medium)
        let textHeight: CGFloat = ceil(textFontSize * 1.25)

        let totalHeight = imageSize + textHeight
        // Vertical content is pinned between the 8pt top and 8pt bottom insets.
        let availableHeight = max(totalHeight, bounds.height - contentInset * 2.0)
        let topY = contentInset + floor((availableHeight - totalHeight) / 2.0)

        imageView.frame = CGRect(
            x: (bounds.width - imageSize) / 2.0,
            y: 6,
            width: imageSize,
            height: imageSize
        )
        // Label gets 8pt horizontal inset so long titles respect the padding
        // rather than bleeding to the pill edge.
        textLabel.frame = CGRect(
            x: contentInset,
            y: 38,
            width: max(0.0, bounds.width - contentInset * 2.0),
            height: 12
        )

        let badgeSize = badgeView.sizeThatFits(CGSize(width: 40, height: 20))
        badgeView.frame = CGRect(
            x: bounds.width / 2.0 + 8.0,
            y: topY - 2.0,
            width: badgeSize.width,
            height: badgeSize.height
        )
    }
}
