import UIKit

/// Glass segmented control built on `LiquidLensView` — same lens
/// machinery the tab bar uses for its selection pill. Track and selection
/// are baked into a single lens; selected/unselected item visuals live
/// on two stacked layers (`lensView.contentView` for un-selected,
/// `lensView.selectedContentView` for selected). The lens applies the
/// selection-shaped mask, so the selected style only shows inside the
/// thumb area and crossfades into the unselected style outside it.
///
/// On iOS 26+ this delivers Apple's native liquid-glass selection
/// (refraction, lift on press, elastic deformation under drag); on
/// legacy systems `LiquidLensView` falls back to a backdrop blur with a
/// soft mask blob that mimics the same effect.
///
/// Sizing is host-driven: set frame / use Auto Layout. `cornerRadius ==
/// nil` (default) makes the track a capsule (`bounds.height / 2`); pass
/// a fixed value for a rounded rectangle.
public final class AetherSegmentedControl: UIView {

    // MARK: - Public types

    public final class Theme: Equatable {
        /// Title colour for un-selected items.
        public let textColor: UIColor
        /// Title colour for the selected item (the one on top of the
        /// lens). Default uses the same colour as `textColor`; the
        /// visual distinction comes from the bolder font.
        public let selectedTextColor: UIColor

        public init(
            textColor: UIColor = .label,
            selectedTextColor: UIColor = .label
        ) {
            self.textColor = textColor
            self.selectedTextColor = selectedTextColor
        }

        public static func == (lhs: Theme, rhs: Theme) -> Bool {
            lhs.textColor == rhs.textColor && lhs.selectedTextColor == rhs.selectedTextColor
        }

        public static let system: Theme = Theme()
    }

    public struct Item: Equatable {
        public let title: String
        public let badgeValue: String?

        public init(title: String, badgeValue: String? = nil) {
            self.title = title
            self.badgeValue = badgeValue
        }
    }

    // MARK: - Public configuration

    /// Track corner radius. `nil` (default) → capsule.
    public var cornerRadius: CGFloat? {
        didSet { setNeedsLayout() }
    }

    /// Inset of the lens selection from the track on both axes. Default
    /// 2pt — same as the tab bar's selection pill.
    public var thumbInset: CGFloat = 2.0 {
        didSet { setNeedsLayout() }
    }

    /// Preferred fixed height when the host doesn't set one explicitly
    /// (used by `intrinsicContentSize`).
    public var preferredHeight: CGFloat = 36.0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    public var items: [Item] {
        get { _items }
        set {
            guard _items != newValue else { return }
            _items = newValue
            _selectedIndex = max(0, min(newValue.count - 1, _selectedIndex))
            if let selectionProgress {
                self.selectionProgress = clampedSelectionProgress(selectionProgress)
            }
            rebuildItemContent()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    public var selectedIndex: Int {
        get { _selectedIndex }
        set {
            setSelectedIndex(newValue, animated: false, updatesSelectionProgress: true)
        }
    }

    public func setSelectedIndex(_ index: Int, animated: Bool) {
        setSelectedIndex(index, animated: animated, updatesSelectionProgress: true)
    }

    internal func setSelectedIndex(_ index: Int, animated: Bool, updatesSelectionProgress: Bool) {
        let clampedIndex = clampedIndex(index)
        guard clampedIndex != _selectedIndex || (updatesSelectionProgress && selectionProgress != nil) else { return }
        let preservedSelectionProgress = displayedSelectionProgress
        _selectedIndex = clampedIndex
        if updatesSelectionProgress {
            selectionProgress = nil
        } else if selectionProgress == nil {
            selectionProgress = preservedSelectionProgress
        }
        updateLayoutInternal(transition: animated ? .animated(duration: 0.35, curve: .spring) : .immediate)
    }

    internal func setSelectionProgress(_ progress: CGFloat, animated: Bool) {
        let clampedProgress = clampedSelectionProgress(progress)
        if let selectionProgress, abs(selectionProgress - clampedProgress) < 0.001 {
            return
        }
        selectionProgress = clampedProgress
        updateLayoutInternal(transition: animated ? .animated(duration: 0.35, curve: .spring) : .immediate)
    }

    public var selectedIndexChanged: (Int) -> Void = { _ in }

    public var selectedIndexShouldChange: (Int, @escaping (Bool) -> Void) -> Void = { _, commit in
        commit(true)
    }

    // MARK: - Internal state

    private var theme: Theme
    private var _items: [Item]
    private var _selectedIndex: Int
    private var selectionProgress: CGFloat?

    private let scrollView = UIScrollView()
    private let contentHostView = UIView()
    private let normalContentView = UIView()
    private let selectedContentHostView = UIView()
    private let liquidLensView: LiquidLensView

    /// One label per item on the un-selected layer (lens.contentView).
    /// These read in the regular weight; the lens masks them out where
    /// the selection sits.
    private var normalLabels: [UILabel] = []

    /// One label per item on the selected layer (lens.selectedContentView).
    /// Bolder weight; only visible inside the lens window.
    private var selectedLabels: [UILabel] = []

    private var normalBadgeViews: [NavigationBarBadgeView] = []
    private var selectedBadgeViews: [NavigationBarBadgeView] = []

    /// Hit-test buttons sized + positioned to match each item slot. Sit
    /// ABOVE the lens so taps on text register, not on the lens glass.
    private var itemButtons: [SegmentedItemButton] = []

    private var panGestureRecognizer: UIPanGestureRecognizer?
    /// Drag-to-scrub state — `currentX` is the finger's x in lens coords;
    /// the layout pass clamps it and feeds it as the lens selection
    /// origin so the pill follows the finger.
    private struct DragState { var currentX: CGFloat }
    private var dragState: DragState?
    private var pressActive: Bool = false
    private var currentItemFrames: [CGRect] = []

    private enum Metrics {
        static let minimumSegmentHorizontalPadding: CGFloat = 16.0
        static let badgeSpacing: CGFloat = 4.0
    }

    internal var debugSelectionFrame: CGRect? {
        guard let origin = liquidLensView.selectionOrigin,
              let size = liquidLensView.selectionSize
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    internal var debugScrollView: UIScrollView {
        scrollView
    }

    internal func debugItemFrame(at index: Int) -> CGRect? {
        guard currentItemFrames.indices.contains(index) else {
            return nil
        }
        return currentItemFrames[index]
    }

    // MARK: - Init

    public init(
        theme: Theme = .system,
        items: [Item],
        selectedIndex: Int = 0,
        cornerRadius: CGFloat? = nil
    ) {
        self.theme = theme
        self._items = items
        self._selectedIndex = max(0, min(items.count - 1, selectedIndex))
        self.cornerRadius = cornerRadius
        // `.builtinContainer` makes the lens self-sufficient — it owns its
        // own glass background container (no external glass plumbing).
        self.liquidLensView = LiquidLensView(kind: .builtinContainer)

        super.init(frame: .zero)

        clipsToBounds = false  // lens shadow / lift overflow needs to bleed

        normalContentView.clipsToBounds = true
        normalContentView.layer.cornerCurve = .continuous
        selectedContentHostView.clipsToBounds = true
        selectedContentHostView.layer.cornerCurve = .continuous

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = true
        scrollView.clipsToBounds = true
        scrollView.backgroundColor = .clear
        if #available(iOS 11.0, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        addSubview(liquidLensView)
        addSubview(scrollView)
        liquidLensView.contentView.addSubview(normalContentView)
        liquidLensView.selectedContentView.addSubview(selectedContentHostView)
        scrollView.addSubview(contentHostView)

        rebuildItemContent()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        scrollView.panGestureRecognizer.require(toFail: pan)
        scrollView.delegate = self
        panGestureRecognizer = pan
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Gesture gating

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return true
        }
        // Only own the pan when the finger lands inside the current
        // selection rect — taps anywhere else fall through to the
        // per-item buttons.
        let location = gestureRecognizer.location(in: contentHostView)
        return currentSelectionRect().contains(location)
    }

    // MARK: - Theme

    public func updateTheme(_ newTheme: Theme) {
        guard newTheme != theme else { return }
        theme = newTheme
        for (label, item) in zip(normalLabels, _items) {
            label.attributedText = makeNormalAttributed(item.title)
            _ = item
        }
        for (label, item) in zip(selectedLabels, _items) {
            label.attributedText = makeSelectedAttributed(item.title)
            _ = item
        }
    }

    // MARK: - Layout

    public override var intrinsicContentSize: CGSize {
        guard !_items.isEmpty else {
            return CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight)
        }
        let intrinsicWidth = naturalContentWidth(for: naturalItemWidths()) + thumbInset * 2
        return CGSize(width: intrinsicWidth, height: preferredHeight)
    }

    private func clampedIndex(_ index: Int) -> Int {
        guard !_items.isEmpty else {
            return 0
        }
        return max(0, min(_items.count - 1, index))
    }

    private func clampedSelectionProgress(_ progress: CGFloat) -> CGFloat {
        guard !_items.isEmpty else {
            return 0.0
        }
        return max(0.0, min(CGFloat(_items.count - 1), progress))
    }

    private var displayedSelectionProgress: CGFloat {
        if let selectionProgress {
            return clampedSelectionProgress(selectionProgress)
        }
        return CGFloat(_selectedIndex)
    }

    private func naturalItemWidths() -> [CGFloat] {
        guard !_items.isEmpty else {
            return []
        }
        return selectedLabels.indices.map { index in
            let size = itemContentSize(
                label: selectedLabels[index],
                badgeView: selectedBadgeViews[index]
            )
            return ceil(size.width + Metrics.minimumSegmentHorizontalPadding * 2.0)
        }
    }

    private func naturalContentWidth(for itemWidths: [CGFloat]) -> CGFloat {
        itemWidths.reduce(0.0, +)
    }

    private func itemContentSize(label: UILabel, badgeView: NavigationBarBadgeView) -> CGSize {
        let labelSize = label.intrinsicContentSize
        guard !badgeView.isHidden else {
            return labelSize
        }
        let badgeSize = badgeView.sizeThatFits(CGSize(width: 80.0, height: 18.0))
        return CGSize(
            width: labelSize.width + Metrics.badgeSpacing + badgeSize.width,
            height: max(labelSize.height, badgeSize.height)
        )
    }

    private func layoutItemContent(
        label: UILabel,
        badgeView: NavigationBarBadgeView,
        in frame: CGRect,
        transition: ContainedViewLayoutTransition
    ) {
        let labelSize = label.intrinsicContentSize
        let horizontalPadding = Metrics.minimumSegmentHorizontalPadding
        let contentFrame = frame.insetBy(dx: min(horizontalPadding, frame.width * 0.5), dy: 0.0)
        if badgeView.isHidden {
            transition.updateFrame(view: label, frame: contentFrame)
            transition.updateFrame(view: badgeView, frame: CGRect(x: frame.midX, y: frame.midY, width: 0.0, height: 0.0))
            return
        }

        let badgeSize = badgeView.sizeThatFits(CGSize(width: 80.0, height: 18.0))
        let totalWidth = min(contentFrame.width, labelSize.width + Metrics.badgeSpacing + badgeSize.width)
        let labelWidth = max(0.0, min(labelSize.width, totalWidth - Metrics.badgeSpacing - badgeSize.width))
        let startX = contentFrame.minX + floor((contentFrame.width - totalWidth) / 2.0)
        let labelFrame = CGRect(
            x: startX,
            y: frame.minY,
            width: labelWidth,
            height: frame.height
        )
        let badgeFrame = CGRect(
            x: labelFrame.maxX + Metrics.badgeSpacing,
            y: frame.minY + floor((frame.height - badgeSize.height) / 2.0),
            width: badgeSize.width,
            height: badgeSize.height
        )
        transition.updateFrame(view: label, frame: labelFrame)
        transition.updateFrame(view: badgeView, frame: badgeFrame)
    }

    private func selectionFrame(for progress: CGFloat, itemFrames: [CGRect]) -> CGRect {
        guard !itemFrames.isEmpty else {
            return .zero
        }
        let clampedProgress = clampedSelectionProgress(progress)
        let lowerIndex = max(0, min(itemFrames.count - 1, Int(floor(clampedProgress))))
        let upperIndex = max(0, min(itemFrames.count - 1, Int(ceil(clampedProgress))))
        guard lowerIndex != upperIndex else {
            return itemFrames[lowerIndex]
        }
        let fraction = clampedProgress - CGFloat(lowerIndex)
        let lowerFrame = itemFrames[lowerIndex]
        let upperFrame = itemFrames[upperIndex]
        return CGRect(
            x: lowerFrame.minX + (upperFrame.minX - lowerFrame.minX) * fraction,
            y: lowerFrame.minY + (upperFrame.minY - lowerFrame.minY) * fraction,
            width: lowerFrame.width + (upperFrame.width - lowerFrame.width) * fraction,
            height: lowerFrame.height + (upperFrame.height - lowerFrame.height) * fraction
        )
    }

    private func ensureSelectionVisible(_ selectionFrame: CGRect, animated: Bool) {
        guard selectionFrame.width > 0.0,
              scrollView.contentSize.width > scrollView.bounds.width + 0.5,
              !scrollView.isTracking,
              !scrollView.isDragging,
              !scrollView.isDecelerating
        else { return }

        let visibleMinX = scrollView.contentOffset.x
        let visibleMaxX = visibleMinX + scrollView.bounds.width
        let targetFrame = selectionFrame.insetBy(dx: -Metrics.minimumSegmentHorizontalPadding, dy: 0.0)
        var targetOffsetX = visibleMinX
        if targetFrame.minX < visibleMinX {
            targetOffsetX = targetFrame.minX
        } else if targetFrame.maxX > visibleMaxX {
            targetOffsetX = targetFrame.maxX - scrollView.bounds.width
        } else {
            return
        }

        let maxOffsetX = max(0.0, scrollView.contentSize.width - scrollView.bounds.width)
        targetOffsetX = max(0.0, min(maxOffsetX, targetOffsetX))
        guard abs(targetOffsetX - scrollView.contentOffset.x) > 0.5 else {
            return
        }
        scrollView.setContentOffset(CGPoint(x: targetOffsetX, y: 0.0), animated: animated)
    }

    private func nearestItemIndex(to x: CGFloat) -> Int {
        guard !currentItemFrames.isEmpty else {
            return _selectedIndex
        }
        var nearestIndex = _selectedIndex
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for (index, frame) in currentItemFrames.enumerated() {
            let distance = abs(frame.midX - x)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }
        return nearestIndex
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateLayoutInternal(transition: .immediate)
    }

    private func updateLayoutInternal(transition: ContainedViewLayoutTransition) {
        let size = bounds.size
        guard size.width > 0, size.height > 0, !_items.isEmpty else { return }

        let resolvedTrackCorner = cornerRadius ?? (size.height / 2.0)

        transition.updateFrame(view: scrollView, frame: CGRect(origin: .zero, size: size))

        let naturalWidths = naturalItemWidths()
        let naturalWidth = naturalContentWidth(for: naturalWidths)
        let availableInnerWidth = max(0.0, size.width - thumbInset * 2.0)
        let contentInnerWidth = max(availableInnerWidth, naturalWidth)
        let contentSize = CGSize(width: contentInnerWidth + thumbInset * 2.0, height: size.height)
        let extraWidthPerItem = _items.isEmpty ? 0.0 : max(0.0, availableInnerWidth - naturalWidth) / CGFloat(_items.count)

        scrollView.contentSize = contentSize
        scrollView.alwaysBounceHorizontal = contentSize.width > size.width + 0.5
        transition.updateFrame(view: contentHostView, frame: CGRect(origin: .zero, size: contentSize))
        transition.updateFrame(view: normalContentView, frame: CGRect(origin: .zero, size: size))
        transition.updateFrame(view: selectedContentHostView, frame: CGRect(origin: .zero, size: size))
        transition.updateCornerRadius(layer: normalContentView.layer, cornerRadius: resolvedTrackCorner)
        transition.updateCornerRadius(layer: selectedContentHostView.layer, cornerRadius: resolvedTrackCorner)

        let maxOffsetX = max(0.0, contentSize.width - size.width)
        let clampedOffsetX = max(0.0, min(maxOffsetX, scrollView.contentOffset.x))
        if abs(scrollView.contentOffset.x - clampedOffsetX) > 0.5 || abs(scrollView.contentOffset.y) > 0.5 {
            scrollView.contentOffset = CGPoint(x: clampedOffsetX, y: 0.0)
        }
        let contentOffsetX = scrollView.contentOffset.x

        let itemHeight = size.height
        var itemFrames: [CGRect] = []
        itemFrames.reserveCapacity(_items.count)
        var itemX = thumbInset
        for i in 0..<_items.count {
            let itemWidth = naturalWidths[i] + extraWidthPerItem
            itemFrames.append(CGRect(
                x: itemX,
                y: 0,
                width: itemWidth,
                height: itemHeight
            ))
            itemX += itemWidth
        }
        currentItemFrames = itemFrames

        // Layout the per-item content on both lens layers + the hit-test
        // buttons that sit above. Same x/y for all three so they line
        // up pixel-for-pixel.
        for i in 0..<_items.count {
            let frame = itemFrames[i]
            let visualFrame = frame.offsetBy(dx: -contentOffsetX, dy: 0.0)
            layoutItemContent(
                label: normalLabels[i],
                badgeView: normalBadgeViews[i],
                in: visualFrame,
                transition: transition
            )
            layoutItemContent(
                label: selectedLabels[i],
                badgeView: selectedBadgeViews[i],
                in: visualFrame,
                transition: transition
            )
            transition.updateFrame(view: itemButtons[i], frame: frame)
        }

        // Selection rectangle: the slot of the currently selected item,
        // unless a drag is in flight (then follow the finger).
        var selectionFrame = selectionFrame(for: displayedSelectionProgress, itemFrames: itemFrames)
        if let drag = dragState {
            // Centre the selection rect on the finger, clamp inside the
            // track. The lens itself adds its `inset` margin around this
            // rect, so we work in the same coords as the resting layout.
            let halfWidth = selectionFrame.width / 2.0
            let clampedX = max(thumbInset + halfWidth, min(contentSize.width - thumbInset - halfWidth, drag.currentX))
            selectionFrame.origin.x = clampedX - halfWidth
        }

        let isDark: Bool
        if #available(iOS 13.0, *) {
            isDark = traitCollection.userInterfaceStyle == .dark
        } else {
            isDark = false
        }

        liquidLensView.update(
            size: size,
            cornerRadius: resolvedTrackCorner,
            selectionOrigin: selectionFrame.offsetBy(dx: -contentOffsetX, dy: 0.0).origin,
            selectionSize: selectionFrame.size,
            inset: thumbInset,
            isDark: isDark,
            isLifted: pressActive || dragState != nil,
            transition: transition
        )
        ensureSelectionVisible(selectionFrame, animated: transition.isAnimated)
    }

    /// Selection rect in the scroll content coords — used by
    /// `gestureRecognizerShouldBegin` to decide whether the pan should
    /// take ownership.
    private func currentSelectionRect() -> CGRect {
        selectionFrame(for: displayedSelectionProgress, itemFrames: currentItemFrames)
    }

    // MARK: - Subview construction

    private func rebuildItemContent() {
        normalLabels.forEach { $0.removeFromSuperview() }
        selectedLabels.forEach { $0.removeFromSuperview() }
        normalBadgeViews.forEach { $0.removeFromSuperview() }
        selectedBadgeViews.forEach { $0.removeFromSuperview() }
        itemButtons.forEach { $0.removeFromSuperview() }
        normalLabels = []
        selectedLabels = []
        normalBadgeViews = []
        selectedBadgeViews = []
        itemButtons = []

        for item in _items {
            let normal = UILabel()
            normal.attributedText = makeNormalAttributed(item.title)
            normal.textAlignment = .center
            normal.numberOfLines = 1
            normal.lineBreakMode = .byTruncatingTail
            normal.isUserInteractionEnabled = false
            normalContentView.addSubview(normal)
            normalLabels.append(normal)

            let normalBadge = makeBadgeView(value: item.badgeValue)
            normalContentView.addSubview(normalBadge)
            normalBadgeViews.append(normalBadge)

            let selected = UILabel()
            selected.attributedText = makeSelectedAttributed(item.title)
            selected.textAlignment = .center
            selected.numberOfLines = 1
            selected.lineBreakMode = .byTruncatingTail
            selected.isUserInteractionEnabled = false
            selectedContentHostView.addSubview(selected)
            selectedLabels.append(selected)

            let selectedBadge = makeBadgeView(value: item.badgeValue)
            selectedContentHostView.addSubview(selectedBadge)
            selectedBadgeViews.append(selectedBadge)

            let button = SegmentedItemButton()
            if let badgeValue = item.badgeValue, !badgeValue.isEmpty {
                button.accessibilityLabel = "\(item.title), \(badgeValue)"
            } else {
                button.accessibilityLabel = item.title
            }
            button.accessibilityTraits = [.button]
            button.addTarget(self, action: #selector(itemButtonPressed(_:)), for: .touchUpInside)
            button.onHighlightChanged = { [weak self, weak button] highlighted in
                guard let self, let button else { return }
                self.handleItemHighlightChange(highlighted: highlighted, on: button)
            }
            contentHostView.addSubview(button)
            itemButtons.append(button)
        }
    }

    private func makeBadgeView(value: String?) -> NavigationBarBadgeView {
        let badgeView = NavigationBarBadgeView()
        badgeView.text = value ?? ""
        badgeView.isUserInteractionEnabled = false
        return badgeView
    }

    private func makeNormalAttributed(_ title: String) -> NSAttributedString {
        return NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: theme.textColor
        ])
    }

    private func makeSelectedAttributed(_ title: String) -> NSAttributedString {
        return NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: theme.selectedTextColor
        ])
    }

    // MARK: - Press feedback

    private func handleItemHighlightChange(highlighted: Bool, on button: SegmentedItemButton) {
        guard let index = itemButtons.firstIndex(of: button) else { return }
        if _selectedIndex == index {
            // Pressing the already-selected item triggers the lens lift —
            // on iOS 26+ that's the native elastic deformation; on legacy
            // the lens scales+blurs its mask blob to mimic it.
            if pressActive != highlighted {
                pressActive = highlighted
                updateLayoutInternal(transition: .animated(duration: 0.25, curve: .spring))
            }
        } else if highlighted {
            UIView.animate(withDuration: 0.2) {
                button.alpha = 0.5
            }
        } else {
            UIView.animate(withDuration: 0.2) {
                button.alpha = 1.0
            }
        }
    }

    // MARK: - Tap

    @objc private func itemButtonPressed(_ button: SegmentedItemButton) {
        guard let index = itemButtons.firstIndex(of: button) else { return }
        guard index != _selectedIndex else { return }
        selectedIndexShouldChange(index) { [weak self] commit in
            guard let self, commit else { return }
            self._selectedIndex = index
            self.selectionProgress = nil
            self.selectedIndexChanged(index)
            self.updateLayoutInternal(transition: .animated(duration: 0.4, curve: .spring))
        }
    }

    // MARK: - Drag-to-scrub

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: contentHostView)
        switch recognizer.state {
        case .began:
            selectionProgress = nil
            dragState = DragState(currentX: location.x)
            updateLayoutInternal(transition: .animated(duration: 0.25, curve: .spring))
        case .changed:
            dragState?.currentX = location.x
            updateLayoutInternal(transition: .animated(duration: 0.15, curve: .easeInOut))
        case .ended:
            // Snap to the nearest item slot.
            let endingState = dragState
            dragState = nil
            if let endingState {
                let snappedIndex = nearestItemIndex(to: endingState.currentX)
                if snappedIndex != _selectedIndex {
                    selectedIndexShouldChange(snappedIndex) { [weak self] commit in
                        guard let self else { return }
                        if commit {
                            self._selectedIndex = snappedIndex
                            self.selectionProgress = nil
                            self.selectedIndexChanged(snappedIndex)
                            self.updateLayoutInternal(transition: .animated(duration: 0.4, curve: .spring))
                        } else {
                            self.updateLayoutInternal(transition: .immediate)
                        }
                    }
                } else {
                    updateLayoutInternal(transition: .animated(duration: 0.4, curve: .spring))
                }
            } else {
                updateLayoutInternal(transition: .immediate)
            }
        case .cancelled, .failed:
            dragState = nil
            updateLayoutInternal(transition: .immediate)
        default:
            break
        }
    }
}

// MARK: - Pan gesture delegate

extension AetherSegmentedControl: UIGestureRecognizerDelegate {
    // Conformance present so `pan.delegate = self` works; the actual
    // `gestureRecognizerShouldBegin` lives on the class so it can also
    // serve as an override of UIView's same-named method.
}

// MARK: - Scroll view delegate

extension AetherSegmentedControl: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateLayoutInternal(transition: .immediate)
    }
}

// MARK: - Highlight-tracking item button

private final class SegmentedItemButton: UIButton {
    var onHighlightChanged: ((Bool) -> Void)?

    override var isHighlighted: Bool {
        didSet {
            if oldValue != isHighlighted {
                onHighlightChanged?(isHighlighted)
            }
        }
    }
}
