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

        public init(title: String) {
            self.title = title
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
            rebuildItemContent()
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    public var selectedIndex: Int {
        get { _selectedIndex }
        set {
            guard newValue != _selectedIndex else { return }
            _selectedIndex = max(0, min(_items.count - 1, newValue))
            updateLayoutInternal(transition: .immediate)
        }
    }

    public func setSelectedIndex(_ index: Int, animated: Bool) {
        guard index != _selectedIndex else { return }
        _selectedIndex = max(0, min(_items.count - 1, index))
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

    private let liquidLensView: LiquidLensView

    /// One label per item on the un-selected layer (lens.contentView).
    /// These read in the regular weight; the lens masks them out where
    /// the selection sits.
    private var normalLabels: [UILabel] = []

    /// One label per item on the selected layer (lens.selectedContentView).
    /// Bolder weight; only visible inside the lens window.
    private var selectedLabels: [UILabel] = []

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

        addSubview(liquidLensView)

        rebuildItemContent()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        panGestureRecognizer = pan
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Gesture gating

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only own the pan when the finger lands inside the current
        // selection rect — taps anywhere else fall through to the
        // per-item buttons.
        let location = gestureRecognizer.location(in: self)
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
        var maxItemWidth: CGFloat = 0
        for label in selectedLabels {  // selected weight is widest
            let size = label.intrinsicContentSize
            maxItemWidth = max(maxItemWidth, size.width)
        }
        // Per-item padding (16pt) + outer thumb-inset margin on both
        // ends.
        let intrinsicWidth = ceil((maxItemWidth + 16) * CGFloat(_items.count)) + thumbInset * 2
        return CGSize(width: intrinsicWidth, height: preferredHeight)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateLayoutInternal(transition: .immediate)
    }

    private func updateLayoutInternal(transition: ContainedViewLayoutTransition) {
        let size = bounds.size
        guard size.width > 0, size.height > 0, !_items.isEmpty else { return }

        let resolvedTrackCorner = cornerRadius ?? (size.height / 2.0)

        transition.updateFrame(view: liquidLensView, frame: CGRect(origin: .zero, size: size))

        // Item frames: equally spaced inside the track inset.
        let innerWidth = size.width - thumbInset * 2
        let itemWidth = innerWidth / CGFloat(_items.count)
        let itemHeight = size.height
        var itemFrames: [CGRect] = []
        itemFrames.reserveCapacity(_items.count)
        for i in 0..<_items.count {
            itemFrames.append(CGRect(
                x: thumbInset + itemWidth * CGFloat(i),
                y: 0,
                width: itemWidth,
                height: itemHeight
            ))
        }

        // Layout the per-item content on both lens layers + the hit-test
        // buttons that sit above. Same x/y for all three so they line
        // up pixel-for-pixel.
        for i in 0..<_items.count {
            let frame = itemFrames[i]
            transition.updateFrame(view: normalLabels[i], frame: frame)
            transition.updateFrame(view: selectedLabels[i], frame: frame)
            transition.updateFrame(view: itemButtons[i], frame: frame)
        }

        // Selection rectangle: the slot of the currently selected item,
        // unless a drag is in flight (then follow the finger).
        var selectionFrame = itemFrames[_selectedIndex]
        if let drag = dragState {
            // Centre the selection rect on the finger, clamp inside the
            // track. The lens itself adds its `inset` margin around this
            // rect, so we work in the same coords as the resting layout.
            let halfWidth = itemWidth / 2.0
            let clampedX = max(thumbInset + halfWidth, min(size.width - thumbInset - halfWidth, drag.currentX))
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
            selectionOrigin: selectionFrame.origin,
            selectionSize: selectionFrame.size,
            inset: thumbInset,
            isDark: isDark,
            isLifted: pressActive || dragState != nil,
            transition: transition
        )
    }

    /// Selection rect in self's coords — used by `gestureRecognizerShouldBegin`
    /// to decide whether the pan should take ownership.
    private func currentSelectionRect() -> CGRect {
        let size = bounds.size
        guard size.width > 0, !_items.isEmpty else { return .zero }
        let innerWidth = size.width - thumbInset * 2
        let itemWidth = innerWidth / CGFloat(_items.count)
        return CGRect(
            x: thumbInset + itemWidth * CGFloat(_selectedIndex),
            y: 0,
            width: itemWidth,
            height: size.height
        )
    }

    // MARK: - Subview construction

    private func rebuildItemContent() {
        normalLabels.forEach { $0.removeFromSuperview() }
        selectedLabels.forEach { $0.removeFromSuperview() }
        itemButtons.forEach { $0.removeFromSuperview() }
        normalLabels = []
        selectedLabels = []
        itemButtons = []

        for item in _items {
            let normal = UILabel()
            normal.attributedText = makeNormalAttributed(item.title)
            normal.textAlignment = .center
            normal.numberOfLines = 1
            normal.lineBreakMode = .byTruncatingTail
            normal.isUserInteractionEnabled = false
            liquidLensView.contentView.addSubview(normal)
            normalLabels.append(normal)

            let selected = UILabel()
            selected.attributedText = makeSelectedAttributed(item.title)
            selected.textAlignment = .center
            selected.numberOfLines = 1
            selected.lineBreakMode = .byTruncatingTail
            selected.isUserInteractionEnabled = false
            liquidLensView.selectedContentView.addSubview(selected)
            selectedLabels.append(selected)

            let button = SegmentedItemButton()
            button.accessibilityLabel = item.title
            button.accessibilityTraits = [.button]
            button.addTarget(self, action: #selector(itemButtonPressed(_:)), for: .touchUpInside)
            button.onHighlightChanged = { [weak self, weak button] highlighted in
                guard let self, let button else { return }
                self.handleItemHighlightChange(highlighted: highlighted, on: button)
            }
            addSubview(button)
            itemButtons.append(button)
        }
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
        selectedIndexShouldChange(index) { [weak self] commit in
            guard let self, commit else { return }
            self._selectedIndex = index
            self.selectedIndexChanged(index)
            self.updateLayoutInternal(transition: .animated(duration: 0.4, curve: .spring))
        }
    }

    // MARK: - Drag-to-scrub

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            dragState = DragState(currentX: location.x)
            updateLayoutInternal(transition: .animated(duration: 0.25, curve: .spring))
        case .changed:
            dragState?.currentX = location.x
            updateLayoutInternal(transition: .animated(duration: 0.15, curve: .easeInOut))
        case .ended, .cancelled, .failed:
            // Snap to the nearest item slot.
            let endingState = dragState
            dragState = nil
            if let endingState {
                let size = bounds.size
                let innerWidth = size.width - thumbInset * 2
                let itemWidth = innerWidth / CGFloat(_items.count)
                let normalisedX = max(0, endingState.currentX - thumbInset)
                let snappedIndex = min(_items.count - 1, max(0, Int(normalisedX / itemWidth)))
                if snappedIndex != _selectedIndex {
                    selectedIndexShouldChange(snappedIndex) { [weak self] commit in
                        guard let self else { return }
                        if commit {
                            self._selectedIndex = snappedIndex
                            self.selectedIndexChanged(snappedIndex)
                        }
                        self.updateLayoutInternal(transition: .animated(duration: 0.4, curve: .spring))
                    }
                } else {
                    updateLayoutInternal(transition: .animated(duration: 0.4, curve: .spring))
                }
            } else {
                updateLayoutInternal(transition: .animated(duration: 0.4, curve: .spring))
            }
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
