import UIKit

/// A high-performance virtualized list view, ported from Telegram's `ListView`.
///
/// Uses a transaction-based API for all modifications. Only visible items
/// (plus a preload buffer) are kept in the view hierarchy. Items are
/// represented by `AetherListItem` models that create and update
/// `AetherListItemNode` views on demand.
///
/// ```swift
/// let listView = AetherListView()
/// listView.transaction(
///     insertIndicesAndItems: items.enumerated().map { i, item in
///         AetherListInsertItem(index: i, item: item)
///     },
///     options: [],
///     completion: { range in print("Visible: \(range)") }
/// )
/// ```
open class AetherListView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    // MARK: - Configuration

    /// Number of viewport heights to preload above and below.
    public var preloadPages: CGFloat = 1.0

    /// Whether scrolling is enabled.
    public var scrollEnabled: Bool {
        get { scrollView.isScrollEnabled }
        set { scrollView.isScrollEnabled = newValue }
    }

    /// Stack items from the bottom (chat-style). When the content
    /// is shorter than the viewport, an extra top inset is added so
    /// rows sit at the bottom edge instead of the top. Long content
    /// scrolls normally — call `scrollToBottom(animated:)` or rely
    /// on the auto-anchor behaviour: if the user is parked near the
    /// bottom and a transaction inserts items past the end, the view
    /// re-scrolls to the new bottom.
    public var stackFromBottom: Bool = false {
        didSet {
            applyEffectiveInsets()
            if stackFromBottom {
                scrollToBottom(animated: false)
            }
        }
    }

    /// Distance from the bottom edge in points within which the user
    /// is considered to be "at the bottom" — used to decide whether
    /// new inserts should auto-scroll the view down.
    public var stackFromBottomAutoAnchorTolerance: CGFloat = 60

    /// Edge insets for the list content. The list view owns the scroll
    /// view's content / indicator insets fully — system safe-area
    /// adjustment is disabled so what callers pass here is what they get.
    /// When `automaticallyAdjustsContentInsetForKeyboard` is on, an
    /// additional bottom inset is layered on top to clear the
    /// software keyboard.
    ///
    /// Direct property assignment runs `.immediate`. From inside
    /// `containerLayoutUpdated` prefer `updateInsets(_:transition:)`
    /// so the inset change rides the same transition the caller
    /// already received — it animates and compensates content
    /// offset for the delta.
    public var insets: UIEdgeInsets {
        get { _insets }
        set {
            _insets = newValue
            applyEffectiveInsets()
        }
    }
    private var _insets: UIEdgeInsets = .zero

    /// Insets used for sticky/header positioning. Defaults to `insets` when
    /// unset, mirroring Telegram's `headerInsets ?? insets` behaviour.
    public var headerInsets: UIEdgeInsets? {
        didSet {
            applyStickyHeaderLayout()
        }
    }

    /// Optional scroll-indicator insets distinct from content insets.
    public var scrollIndicatorInsets: UIEdgeInsets? {
        didSet {
            applyEffectiveInsets()
        }
    }

    /// Insets applied to the item offset coordinate system. This is useful
    /// when callers need row geometry offset from the scroll content's raw
    /// origin without baking spacer rows into the data source.
    public var itemOffsetInsets: UIEdgeInsets? {
        get { _itemOffsetInsets }
        set {
            updateContentMetricInsets(
                itemOffsetInsets: newValue,
                virtualContentInsets: _virtualContentInsets,
                transition: .immediate,
                preserveContentOffset: true,
                notifyVisibilityLifecycle: true
            )
        }
    }
    private var _itemOffsetInsets: UIEdgeInsets?

    /// Estimated top/bottom content outside the currently loaded item models.
    /// This is the list-level equivalent of "there is more history above /
    /// below, but those rows are not materialized yet". Changing the top
    /// extent compensates `contentOffset` so visible rows do not jump.
    public var virtualContentInsets: AetherListVirtualContentInsets {
        get { _virtualContentInsets }
        set {
            updateVirtualContentInsets(newValue, transition: .immediate)
        }
    }
    private var _virtualContentInsets: AetherListVirtualContentInsets = .zero

    public func updateVirtualContentInsets(
        _ virtualContentInsets: AetherListVirtualContentInsets,
        transition: ContainedViewLayoutTransition = .immediate
    ) {
        updateContentMetricInsets(
            itemOffsetInsets: _itemOffsetInsets,
            virtualContentInsets: virtualContentInsets,
            transition: transition,
            preserveContentOffset: true,
            notifyVisibilityLifecycle: true
        )
    }

    /// When `true`, the list view listens for `UIKeyboardWill…`
    /// notifications and grows `scrollView.contentInset.bottom` by
    /// the on-screen keyboard's overlap with the list. Animation
    /// matches the keyboard's own duration & curve. Disabled by
    /// default so non-input lists don't pay for the observer.
    public var automaticallyAdjustsContentInsetForKeyboard: Bool = false {
        didSet {
            guard automaticallyAdjustsContentInsetForKeyboard != oldValue else { return }
            if automaticallyAdjustsContentInsetForKeyboard {
                registerKeyboardObserver()
            } else {
                unregisterKeyboardObserver()
                if keyboardBottomInset != 0 {
                    keyboardBottomInset = 0
                    applyEffectiveInsets()
                }
            }
        }
    }

    /// Bottom offset added by the on-screen keyboard. 0 when the
    /// keyboard is hidden or sitting outside the list's frame.
    private var keyboardBottomInset: CGFloat = 0

    private func applyEffectiveInsets(transition: ContainedViewLayoutTransition = .immediate) {
        let plan = AetherListEffectiveInsetsPlanner.plan(
            baseInsets: insets,
            keyboardBottomInset: keyboardBottomInset,
            explicitScrollIndicatorInsets: scrollIndicatorInsets,
            stackFromBottom: stackFromBottom,
            totalContentHeight: totalContentHeight,
            viewportHeight: scrollView.bounds.height,
            contentSizeHeight: scrollView.contentSize.height,
            currentContentInset: scrollView.contentInset,
            currentContentOffset: scrollView.contentOffset,
            isTrackingOrDragging: scrollView.isTracking || scrollView.isDragging,
            bottomAnchorTolerance: stackFromBottomAutoAnchorTolerance
        )
        switch transition {
        case .immediate:
            if scrollView.contentInset != plan.contentInset {
                scrollView.contentInset = plan.contentInset
            }
            if let contentOffset = plan.contentOffset {
                scrollView.contentOffset = contentOffset
                syncBackingViewBounds()
            }
        case .animated:
            transition.animateView {
                self.scrollView.contentInset = plan.contentInset
                if let contentOffset = plan.contentOffset {
                    self.scrollView.contentOffset = contentOffset
                    self.syncBackingViewBounds()
                }
            }
        }
        transition.updateScrollIndicatorInsets(scrollView: scrollView, insets: plan.scrollIndicatorInsets)
        updateCustomScrollIndicator()
        updateOverscrollState()
    }

    /// Update `insets` and propagate through `transition` so the
    /// scroll view animates its inset change in sync with the
    /// caller's layout pass — and, just as importantly, compensates
    /// `contentOffset` for the delta. The plain `insets =` setter
    /// runs immediate; this one is the right call from inside a
    /// `containerLayoutUpdated` override.
    public func updateInsets(_ insets: UIEdgeInsets, transition: ContainedViewLayoutTransition) {
        // Bypass the setter so we don't fire an immediate
        // `applyEffectiveInsets()` on top of the animated one below.
        _insets = insets
        applyEffectiveInsets(transition: transition)
    }

    private func effectiveItemOffsetInsets(
        itemOffsetInsets: UIEdgeInsets? = nil,
        virtualContentInsets: AetherListVirtualContentInsets? = nil
    ) -> UIEdgeInsets {
        AetherListContentMetricsPlanner.effectiveOffsetInsets(
            itemOffsetInsets: itemOffsetInsets ?? _itemOffsetInsets,
            virtualContentInsets: virtualContentInsets ?? _virtualContentInsets
        )
    }

    private func updateContentMetricInsets(
        itemOffsetInsets: UIEdgeInsets?,
        virtualContentInsets: AetherListVirtualContentInsets,
        transition: ContainedViewLayoutTransition,
        preserveContentOffset: Bool,
        notifyVisibilityLifecycle: Bool
    ) {
        let previousEffectiveInsets = effectiveItemOffsetInsets()
        _itemOffsetInsets = itemOffsetInsets
        _virtualContentInsets = virtualContentInsets
        rebuildOffsets()
        positionNodes()
        updateContentSize()

        let nextEffectiveInsets = effectiveItemOffsetInsets()
        let topDelta = AetherListContentMetricsPlanner.topDelta(
            from: previousEffectiveInsets,
            to: nextEffectiveInsets
        )
        if preserveContentOffset && abs(topDelta) > CGFloat.ulpOfOne {
            adjustContentOffsetForContentMetricTopDelta(topDelta, transition: transition)
        }

        applyStickyHeaderLayout()
        if notifyVisibilityLifecycle {
            applyVisibilityLifecycle()
        } else {
            updateDebugOverlay()
        }
    }

    private func adjustContentOffsetForContentMetricTopDelta(
        _ deltaY: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        let targetOffset = CGPoint(
            x: scrollView.contentOffset.x,
            y: scrollView.contentOffset.y + deltaY
        )
        switch transition {
        case .immediate:
            scrollView.setContentOffset(targetOffset, animated: false)
            syncBackingViewBounds()
        case .animated:
            transition.animateView {
                self.scrollView.contentOffset = targetOffset
                self.syncBackingViewBounds()
            }
        }
    }

    /// Scroll to the last row's bottom edge.
    public func scrollToBottom(animated: Bool) {
        let bottomY = max(
            -scrollView.contentInset.top,
            scrollView.contentSize.height + scrollView.contentInset.bottom - scrollView.bounds.height
        )
        scrollView.setContentOffset(CGPoint(x: 0, y: bottomY), animated: animated)
        if !animated {
            syncBackingViewBounds()
        }
    }

    /// Scroll to the very top.
    public func scrollToTop(animated: Bool) {
        let topY = -scrollView.contentInset.top
        scrollView.setContentOffset(CGPoint(x: 0, y: topY), animated: animated)
        if !animated {
            syncBackingViewBounds()
        }
    }

    /// Heuristic: is the user parked near the bottom edge? Used by
    /// chat-style auto-anchoring on insert.
    private func isNearBottom(tolerance: CGFloat) -> Bool {
        let maxOffset = scrollView.contentSize.height + scrollView.contentInset.bottom - scrollView.bounds.height
        return scrollView.contentOffset.y >= maxOffset - tolerance
    }

    private func registerKeyboardObserver() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleKeyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(handleKeyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private func unregisterKeyboardObserver() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func handleKeyboardWillChangeFrame(_ note: Notification) {
        guard let userInfo = note.userInfo,
              let frameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveRaw = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        adjustForKeyboard(endFrameInScreen: frameValue.cgRectValue, duration: duration, curveRaw: curveRaw)
    }

    @objc private func handleKeyboardWillHide(_ note: Notification) {
        guard let userInfo = note.userInfo else { return }
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveRaw = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        animateKeyboardInsetChange(to: 0, duration: duration, curveRaw: curveRaw)
    }

    private func adjustForKeyboard(endFrameInScreen: CGRect, duration: Double, curveRaw: UInt) {
        guard let window = window else { return }
        // Convert keyboard frame from screen → window → list view
        // coordinates so the overlap calculation works regardless of
        // where the list sits in the hierarchy.
        let frameInWindow = window.convert(endFrameInScreen, from: nil)
        let frameInList = convert(frameInWindow, from: nil)
        let overlap = max(0, bounds.maxY - frameInList.minY)
        animateKeyboardInsetChange(to: overlap, duration: duration, curveRaw: curveRaw)
    }

    private func animateKeyboardInsetChange(to overlap: CGFloat, duration: Double, curveRaw: UInt) {
        guard keyboardBottomInset != overlap else { return }
        let curveOption = UIView.AnimationOptions(rawValue: curveRaw << 16)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [curveOption, .beginFromCurrentState]
        ) {
            self.keyboardBottomInset = overlap
            self.applyEffectiveInsets()
        }
    }

    // MARK: - Callbacks

    /// Called when the range of visible items changes.
    public var displayedItemRangeChanged: ((AetherListDisplayedItemRange) -> Void)?

    /// Current loaded/visible item range snapshot.
    public var displayedItemRange: AetherListDisplayedItemRange {
        computeDisplayedRange()
    }

    /// Called on every scroll offset change.
    public var visibleContentOffsetChanged: ((CGFloat) -> Void)?

    /// Optional edge-trigger API for paged/infinite lists. The list computes
    /// top/bottom proximity from current offsets and loaded/visible ranges;
    /// the app decides how to load more data.
    public var boundaryTriggerConfiguration: AetherListBoundaryTriggerConfiguration? {
        didSet {
            guard boundaryTriggerConfiguration != oldValue else { return }
            resetBoundaryTriggers()
            evaluateBoundaryTriggers(displayedRange: displayedItemRange, isUserInitiated: false)
        }
    }

    /// Called when the configured top/bottom boundary is reached.
    public var boundaryReached: ((AetherListBoundaryTriggerContext) -> Void)?

    /// Telegram-compatible scroll delta callback.
    public var didScrollWithOffset: ((CGFloat, ContainedViewLayoutTransition, AetherListItemNode?, Bool) -> Void)?

    /// Called when the user begins dragging.
    public var beganInteractiveDragging: (() -> Void)?

    /// Called when scrolling finishes (deceleration ended or drag ended without deceleration).
    public var didEndScrolling: (() -> Void)?

    /// Called when an item is tapped.
    public var itemTapped: ((Int) -> Void)?

    /// Optional final gate for list-owned item gestures. Return `false` when a
    /// screen-level context menu, swipe action, or nested custom gesture should
    /// own the touch instead of the list's tap/reorder handling.
    public var itemGestureShouldBegin: ((_ gesture: AetherListItemGesture, _ index: Int, _ node: AetherListItemNode, _ pointInNode: CGPoint) -> Bool)?

    /// When enabled, the list tap recognizer ignores empty backing-view space
    /// instead of recognizing and then doing nothing.
    public var limitsListGestureHitTestingToVisibleItemNodes: Bool = true

    /// Called when the preferred content-size category changes. Row
    /// implementations can invalidate their own text caches here.
    public var dynamicTypeInvalidated: (() -> Void)?

    /// Enables os.signpost instrumentation, counters, and the optional debug
    /// overlay. This mirrors Telegram's `debugInfo` switch without printing in
    /// the scroll hot path.
    public var debugInfo: Bool = false {
        didSet {
            debugInstrumentation.isEnabled = debugInfo
            syncDebugOverlay()
        }
    }

    /// Debug counters/signposts for transaction and virtualization work.
    public let debugInstrumentation = AetherListDebugInstrumentation()

    /// Show a small overlay with visible/loaded ranges, cache/reuse counts and
    /// latest transaction duration.
    public var showsDebugOverlay: Bool = false {
        didSet {
            syncDebugOverlay()
        }
    }

    /// Use a lightweight custom vertical indicator instead of UIKit's
    /// indicator. The underlying scroll view still owns the physics.
    public var usesCustomScrollIndicator: Bool = false {
        didSet {
            syncCustomScrollIndicator()
        }
    }

    /// When enabled, the custom scroll indicator follows bounce offsets beyond
    /// the normal top/bottom track instead of staying pinned at the edge.
    public var customScrollIndicatorFollowsOverscroll: Bool = false {
        didSet {
            updateCustomScrollIndicator()
        }
    }

    /// Fired with positive overscroll distances while bouncing beyond edges.
    public var topOverscrollChanged: ((CGFloat) -> Void)?
    public var bottomOverscrollChanged: ((CGFloat) -> Void)?

    /// Optional decorative overscroll backgrounds. They are hosted behind the
    /// scroller and resized to the current overscroll height.
    public var topOverscrollBackgroundView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let topOverscrollBackgroundView {
                insertSubview(topOverscrollBackgroundView, belowSubview: scrollView)
            }
            updateOverscrollState()
        }
    }

    public var bottomOverscrollBackgroundView: UIView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let bottomOverscrollBackgroundView {
                insertSubview(bottomOverscrollBackgroundView, belowSubview: scrollView)
            }
            updateOverscrollState()
        }
    }

    /// Snapshot of the centralized list state.
    public var state: AetherListState {
        let displayed = computeDisplayedRange()
        return AetherListState(
            itemCount: items.count,
            visibleSize: visibleSize,
            insets: insets,
            visualInsets: scrollView.contentInset,
            headerInsets: headerInsets,
            scrollIndicatorInsets: scrollIndicatorInsets,
            virtualContentInsets: _virtualContentInsets,
            totalContentHeight: totalContentHeight,
            virtualOffset: visibleContentOffset(),
            visibleRange: displayed.visibleRange,
            loadedRange: displayed.loadedRange,
            visibleViewCount: itemNodes.count,
            layoutCacheCount: layoutCache.count,
            reusePoolCount: reusePool.reduce(0) { $0 + $1.value.count },
            pendingTransactionCount: pendingTransactions.count
        )
    }

    /// Opaque caller-owned state attached to the latest transaction. The list
    /// does not interpret it; it is kept so higher-level code can keep parity
    /// with Telegram's `updateOpaqueState` transaction channel.
    public private(set) var opaqueState: Any?

    // MARK: - Read-only State

    /// Size of the visible viewport.
    public var visibleSize: CGSize { scrollView.bounds.size }

    /// Telegram-compatible access to the underlying scrolling view.
    public var scroller: UIScrollView { scrollView }

    /// Whether the user is currently touching the scroll view.
    public var isTracking: Bool { scrollView.isTracking }

    /// Whether the user is currently dragging.
    public var isDragging: Bool { scrollView.isDragging }

    /// Whether UIKit is currently decelerating after a drag.
    public var isDecelerating: Bool { scrollView.isDecelerating }

    /// Whether the list is in any active scrolling state.
    public var isScrolling: Bool {
        return scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
    }

    /// Minimum logical visible offset accepted by `setVisibleContentOffset`.
    public var minimumVisibleContentOffset: CGFloat = 0.0

    /// Total number of items currently in the list (loaded + virtualised).
    public var itemCount: Int { items.count }

    /// Where the dust-overlay used by `.particleDissolve` deletes
    /// is attached. `nil` (default) → the list view itself, which
    /// is the right choice for plain lists. Set to `view.window`
    /// (or any ancestor) when chrome from outside the list — like
    /// a window-level context menu — needs to render *below* the
    /// particles. Caller is responsible for making sure the host
    /// outlives the burst (≈1.6s) and isn't itself in the middle
    /// of being torn down.
    public weak var particleDissolveOverlayHost: UIView?

    /// Mirrors `UIScrollView.keyboardDismissMode` on the underlying
    /// scroll view. Setting `.interactive` lets UIKit physically
    /// drive the system keyboard down with the finger via XPC —
    /// the only reliable path on iOS 26+ where the keyboard's
    /// CARemoteLayer ignores parent frame/transform mutations.
    public var keyboardDismissMode: UIScrollView.KeyboardDismissMode {
        get { scrollView.keyboardDismissMode }
        set { scrollView.keyboardDismissMode = newValue }
    }

    // MARK: - Selection

    /// How taps drive selection. `.none` keeps the legacy behaviour
    /// (just calls `item.selected(listView:)`); `.single` and
    /// `.multiple` toggle `node.isSelected`, with `single` clearing
    /// the previous selection on each tap.
    public var selectionMode: AetherListSelectionMode = .none {
        didSet {
            guard selectionMode != oldValue else { return }
            if selectionMode == .none {
                clearSelection(animated: false)
            } else if selectionMode == .single, selectedItemIds.count > 1 {
                // Drop everything but the first when downgrading.
                if let first = selectedItemIds.first {
                    selectedItemIds = [first]
                    syncSelectionToNodes(animated: false)
                    notifySelectionChanged()
                }
            }
        }
    }

    /// Indices in current items[] order that are currently selected.
    /// Computed live from the identity-set so it stays correct after
    /// inserts/moves/deletes.
    public var selectedIndices: [Int] {
        guard !selectedItemIds.isEmpty else { return [] }
        return items.enumerated()
            .filter { selectedItemIds.contains(ObjectIdentifier($0.element)) }
            .map { $0.offset }
            .sorted()
    }

    /// Fires whenever the selection set changes — through user taps or
    /// programmatic mutation.
    public var selectionChanged: ((_ indices: [Int]) -> Void)?

    /// Programmatic selection. `selectionMode` must be `.single` or
    /// `.multiple` — calls in `.none` are ignored. With `.single`,
    /// selecting a row deselects any previous one.
    public func setSelected(_ selected: Bool, at index: Int, animated: Bool) {
        guard selectionMode != .none else { return }
        guard index >= 0, index < items.count else { return }
        let id = ObjectIdentifier(items[index])
        let before = selectedItemIds
        if selected {
            if selectionMode == .single {
                selectedItemIds = [id]
            } else {
                selectedItemIds.insert(id)
            }
        } else {
            selectedItemIds.remove(id)
        }
        if selectedItemIds != before {
            syncSelectionToNodes(animated: animated)
            notifySelectionChanged()
        }
    }

    /// Drop every selected row.
    public func clearSelection(animated: Bool = true) {
        guard !selectedItemIds.isEmpty else { return }
        selectedItemIds = []
        syncSelectionToNodes(animated: animated)
        notifySelectionChanged()
    }

    /// Identity-based selection set. Survives index shifts in delete/
    /// move/insert because `node.item` is also tracked by identity.
    private var selectedItemIds: Set<ObjectIdentifier> = []

    private func syncSelectionToNodes(animated: Bool) {
        for node in itemNodes {
            guard let item = node.item else { continue }
            let shouldSelect = selectedItemIds.contains(ObjectIdentifier(item))
            if node.isSelected != shouldSelect {
                node.pendingSelectionAnimated = animated
                node.isSelected = shouldSelect
                node.pendingSelectionAnimated = false
            }
        }
    }

    private func notifySelectionChanged() {
        selectionChanged?(selectedIndices)
    }

    // MARK: - Drag-to-reorder

    /// When `true`, long-pressing a row picks it up and lets the user
    /// drop it elsewhere. Items that return `canReorder = false`
    /// (headers, separators) are skipped both as sources and as
    /// drop targets.
    public var allowsReorder: Bool = false {
        didSet {
            reorderRecognizer?.isEnabled = allowsReorder
        }
    }

    /// Optional gate — return `false` to forbid moving the row at
    /// `from` into `to` (e.g. to keep section boundaries). Default
    /// gate is "yes if both sides are reorderable".
    public var canMoveItem: ((_ from: Int, _ to: Int) -> Bool)?

    /// Optional asynchronous drop validation. Use this when a move depends on
    /// server, database, or cross-section policy checks. The list keeps the
    /// visual order while validation is pending and rolls the row back if the
    /// completion returns `false`.
    public var validateReorder: ((_ from: Int, _ to: Int, _ completion: @escaping (Bool) -> Void) -> Void)?

    /// Fires once the drag completes if the item moved. The list
    /// view has already reshuffled its internal `items` and animated
    /// the node positions by the time this fires; the callback is
    /// for the data source to mirror the change.
    public var didMoveItem: ((_ from: Int, _ to: Int) -> Void)?

    public var willBeginReorder: ((_ index: Int) -> Void)?
    public var reorderDidBegin: ((_ index: Int) -> Void)?
    public var reorderItem: ((_ from: Int, _ to: Int) -> Void)?
    public var reorderCompleted: ((_ from: Int, _ to: Int, _ finished: Bool) -> Void)?
    public var reorderHapticFeedback: (() -> Void)?

    private weak var reorderRecognizer: UILongPressGestureRecognizer?
    private weak var tapRecognizer: UITapGestureRecognizer?
    private var reorderState: ReorderState?

    private struct ReorderState {
        let originalIndex: Int
        var currentIndex: Int
        let touchOffsetY: CGFloat
        let draggingNode: AetherListItemNode
        let snapshotView: UIView
        let placeholderView: UIView
        let originalAlpha: CGFloat
        let dragHeight: CGFloat
    }

    private func setupReorderRecognizer() {
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleReorderGesture(_:)))
        lp.minimumPressDuration = 0.4
        lp.cancelsTouchesInView = false
        lp.isEnabled = allowsReorder
        lp.delegate = self
        scrollView.backingView.addGestureRecognizer(lp)
        reorderRecognizer = lp
    }

    @objc private func handleReorderGesture(_ gr: UILongPressGestureRecognizer) {
        let location = gr.location(in: scrollView.backingView)

        switch gr.state {
        case .began:
            reorderBegan(at: location)
        case .changed:
            reorderChanged(to: location)
        case .ended, .cancelled, .failed:
            reorderEnded()
        default:
            break
        }
    }

    private func reorderBegan(at location: CGPoint) {
        guard reorderState == nil else { return }
        guard let node = itemNodeForListGesture(at: location, gesture: .reorder),
              let index = node.index, index >= 0, index < items.count,
              items[index].canReorder else {
            return
        }
        willBeginReorder?(index)

        let touchOffsetY = location.y - node.frame.minY

        let placeholderView = UIView(frame: node.frame)
        placeholderView.backgroundColor = node.backgroundColor ?? .clear
        placeholderView.layer.cornerRadius = min(8.0, max(0.0, node.layer.cornerRadius))
        placeholderView.layer.masksToBounds = true
        placeholderView.layer.zPosition = 500
        placeholderView.alpha = 0.0
        scrollView.backingView.insertSubview(placeholderView, belowSubview: node)

        let snapshotView = node.snapshotView(afterScreenUpdates: false) ?? UIView(frame: node.frame)
        snapshotView.frame = node.frame
        snapshotView.layer.zPosition = 2000
        snapshotView.layer.shadowColor = UIColor.black.cgColor
        snapshotView.layer.shadowOffset = CGSize(width: 0, height: 8)
        snapshotView.layer.shadowRadius = 16
        snapshotView.layer.shadowOpacity = 0.0
        snapshotView.layer.masksToBounds = false
        scrollView.backingView.addSubview(snapshotView)

        let originalAlpha = node.alpha
        node.alpha = 0.0

        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState]) {
            placeholderView.alpha = 1.0
            snapshotView.transform = CGAffineTransform(scaleX: 1.035, y: 1.035)
            snapshotView.layer.shadowOpacity = 0.22
        }

        reorderState = ReorderState(
            originalIndex: index,
            currentIndex: index,
            touchOffsetY: touchOffsetY,
            draggingNode: node,
            snapshotView: snapshotView,
            placeholderView: placeholderView,
            originalAlpha: originalAlpha,
            dragHeight: node.frame.height
        )
        reorderHapticFeedback?()
        reorderDidBegin?(index)
    }

    private func reorderChanged(to location: CGPoint) {
        guard var state = reorderState else { return }

        // Drag snapshot tracks the finger directly — clamp to scroll
        // content so it doesn't disappear off the top/bottom.
        let dragHeight = state.dragHeight
        let minY: CGFloat = 0
        let maxY: CGFloat = max(0, scrollView.contentSize.height - dragHeight)
        let targetY = max(minY, min(maxY, location.y - state.touchOffsetY))
        state.snapshotView.center = CGPoint(x: state.snapshotView.center.x, y: targetY + dragHeight / 2.0)
        autoScrollForReorderIfNeeded(visibleY: location.y - scrollView.contentOffset.y)

        let centerY = targetY + dragHeight / 2
        guard let proposedIndex = indexForReorderInsertion(centerY: centerY, dragging: state.currentIndex) else {
            reorderState = state
            return
        }

        if proposedIndex == state.currentIndex {
            reorderState = state
            return
        }

        // Honour caller-supplied gate, then per-item canReorder.
        let allowed = (canMoveItem?(state.currentIndex, proposedIndex) ?? true)
            && items[proposedIndex].canReorder
        guard allowed else {
            reorderState = state
            return
        }

        // Commit the swap on the data side.
        let item = items.remove(at: state.currentIndex)
        let height = itemHeights.remove(at: state.currentIndex)
        items.insert(item, at: proposedIndex)
        itemHeights.insert(height, at: proposedIndex)
        rebuildOffsets()

        // Re-derive node.index for everything by item identity, then animate
        // the visible nodes and placeholder to their new slots. The dragged
        // source node stays hidden but remains in layout, ready to fade back
        // in under the snapshot on drop/rollback.
        reindexVisibleNodesByItemIdentity()

        UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            for n in self.itemNodes {
                guard let i = n.index, i < self.itemOffsets.count else { continue }
                var nf = n.frame
                nf.origin.y = self.itemOffsets[i]
                n.frame = nf
            }
            if proposedIndex < self.itemOffsets.count, proposedIndex < self.itemHeights.count {
                state.placeholderView.frame = self.alignedFrame(
                    x: 0,
                    y: self.itemOffsets[proposedIndex],
                    width: self.bounds.width,
                    height: self.itemHeights[proposedIndex]
                )
            }
        }

        reorderItem?(state.currentIndex, proposedIndex)
        reorderHapticFeedback?()
        state.currentIndex = proposedIndex
        reorderState = state
    }

    private func reorderEnded() {
        guard let state = reorderState else { return }

        if state.originalIndex != state.currentIndex {
            if let validateReorder {
                animateReorderNodesToCurrentLayout(state, settleSnapshot: true, restoreDraggingNode: false)
                validateReorder(state.originalIndex, state.currentIndex) { [weak self] accepted in
                    DispatchQueue.main.async {
                        self?.finishReorder(state: state, accepted: accepted)
                    }
                }
                return
            } else {
                didMoveItem?(state.originalIndex, state.currentIndex)
            }
        }

        reorderCompleted?(state.originalIndex, state.currentIndex, true)
        animateReorderNodesToCurrentLayout(state, settleSnapshot: true, restoreDraggingNode: true)
    }

    private func finishReorder(state: ReorderState, accepted: Bool) {
        assertMainThread()

        if accepted {
            didMoveItem?(state.originalIndex, state.currentIndex)
            reorderCompleted?(state.originalIndex, state.currentIndex, true)
            animateReorderNodesToCurrentLayout(state, settleSnapshot: true, restoreDraggingNode: true)
        } else {
            rollbackReorder(state)
            reorderCompleted?(state.originalIndex, state.currentIndex, false)
            animateReorderNodesToCurrentLayout(state, settleSnapshot: true, restoreDraggingNode: true)
        }
    }

    private func rollbackReorder(_ state: ReorderState) {
        guard let item = state.draggingNode.item,
              let currentIndex = items.firstIndex(where: { $0 === item }),
              currentIndex < itemHeights.count else {
            return
        }

        let movedItem = items.remove(at: currentIndex)
        let movedHeight = itemHeights.remove(at: currentIndex)
        let targetIndex = min(state.originalIndex, items.count)
        items.insert(movedItem, at: targetIndex)
        itemHeights.insert(movedHeight, at: targetIndex)
        rebuildOffsets()
        reindexVisibleNodesByItemIdentity()
    }

    private func animateReorderNodesToCurrentLayout(
        _ state: ReorderState,
        settleSnapshot: Bool,
        restoreDraggingNode: Bool
    ) {
        let targetFrame = reorderTargetFrame(for: state.draggingNode)
        UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            for node in self.itemNodes {
                guard let index = node.index, index < self.itemOffsets.count, index < self.itemHeights.count else { continue }
                node.frame = self.alignedFrame(
                    x: 0,
                    y: self.itemOffsets[index],
                    width: self.bounds.width,
                    height: self.itemHeights[index]
                )
            }
            if let targetFrame {
                state.placeholderView.frame = targetFrame
                if settleSnapshot {
                    state.snapshotView.transform = restoreDraggingNode ? .identity : state.snapshotView.transform
                    if restoreDraggingNode {
                        state.snapshotView.frame = targetFrame
                    } else {
                        state.snapshotView.center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
                    }
                }
            }
            if restoreDraggingNode {
                state.placeholderView.alpha = 0.0
                state.snapshotView.layer.shadowOpacity = 0.0
            }
        } completion: { _ in
            guard restoreDraggingNode else { return }
            state.draggingNode.alpha = state.originalAlpha
            state.snapshotView.removeFromSuperview()
            state.placeholderView.removeFromSuperview()
            if self.reorderState?.snapshotView === state.snapshotView {
                self.reorderState = nil
            }
        }
    }

    private func reorderTargetFrame(for node: AetherListItemNode) -> CGRect? {
        guard let index = node.index,
              index >= 0,
              index < itemOffsets.count,
              index < itemHeights.count else {
            return nil
        }
        return alignedFrame(
            x: 0,
            y: itemOffsets[index],
            width: bounds.width,
            height: itemHeights[index]
        )
    }

    private func reindexVisibleNodesByItemIdentity() {
        var idMap: [ObjectIdentifier: Int] = [:]
        idMap.reserveCapacity(items.count)
        for (i, item) in items.enumerated() {
            idMap[ObjectIdentifier(item)] = i
        }
        for node in itemNodes {
            guard let item = node.item else { continue }
            node.index = idMap[ObjectIdentifier(item)]
        }
    }

    private func autoScrollForReorderIfNeeded(visibleY: CGFloat) {
        let edge: CGFloat = 56
        let step: CGFloat = 10
        var offset = scrollView.contentOffset
        if visibleY < edge {
            offset.y -= step
        } else if visibleY > bounds.height - edge {
            offset.y += step
        } else {
            return
        }
        let minY = -scrollView.contentInset.top
        let maxY = max(minY, scrollView.contentSize.height + scrollView.contentInset.bottom - bounds.height)
        offset.y = min(maxY, max(minY, offset.y))
        if offset.y != scrollView.contentOffset.y {
            scrollView.setContentOffset(offset, animated: false)
            syncBackingViewBounds()
        }
    }

    // MARK: - Pull-to-refresh

    /// When non-nil, the list shows a `UIRefreshControl` at the top.
    /// On a pull-down release the closure runs with a `done` callback
    /// — invoke `done()` once the refresh work finishes and the
    /// control retracts itself.
    public var refreshHandler: ((_ done: @escaping () -> Void) -> Void)? {
        didSet { syncRefreshControl() }
    }

    /// Programmatic trigger — visually tugs the indicator down and
    /// fires `refreshHandler`. Useful for "refresh on first appear"
    /// patterns.
    public func beginRefreshing() {
        guard let control = refreshControl, refreshHandler != nil else { return }
        control.beginRefreshing()
        // Push the scroll view far enough that the indicator is
        // actually visible — UIRefreshControl by itself only sets
        // its `isRefreshing` flag.
        let offset = scrollView.contentOffset.y
        let target = -(scrollView.adjustedContentInset.top + control.frame.height)
        if offset > target {
            scrollView.setContentOffset(CGPoint(x: 0, y: target), animated: true)
        }
        triggerRefresh()
    }

    public var isRefreshing: Bool {
        refreshControl?.isRefreshing ?? false
    }

    private weak var refreshControl: UIRefreshControl?

    private func syncRefreshControl() {
        if refreshHandler != nil {
            if refreshControl == nil {
                let control = UIRefreshControl()
                control.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
                scrollView.refreshControl = control
                refreshControl = control
            }
        } else {
            scrollView.refreshControl = nil
            refreshControl = nil
        }
    }

    @objc private func handleRefresh() {
        triggerRefresh()
    }

    private func triggerRefresh() {
        guard let handler = refreshHandler else {
            refreshControl?.endRefreshing()
            return
        }
        handler { [weak self] in
            DispatchQueue.main.async {
                self?.refreshControl?.endRefreshing()
            }
        }
    }

    @objc private func handleContentSizeCategoryDidChange() {
        dynamicTypeInvalidated?()
        clearLayoutPreparationCaches(cancelPendingTasks: true)
        if let params = layoutParams {
            relayoutAllNodes(params: params)
        }
        updateVisibleNodes()
    }

    @objc private func handleMemoryWarning() {
        clearLayoutPreparationCaches(cancelPendingTasks: true)
        reusePool.removeAll()
        updateDebugOverlay()
    }

    private func clearLayoutPreparationCaches(cancelPendingTasks: Bool) {
        layoutCache.removeAll()
        layoutCacheOrder.removeAll()
        preparedLayoutCache.removeAll()
        if cancelPendingTasks {
            pendingLayoutTasks.values.forEach { $0.cancel() }
            pendingLayoutTasks.removeAll()
        }
    }

    private func invalidatePreparedLayout(for id: AnyHashable) {
        layoutCache.removeValue(forKey: id)
        preparedLayoutCache.removeValue(forKey: id)
        layoutCacheOrder.removeAll { $0 == id }
    }

    private func assertMainThread(file: StaticString = #fileID, line: UInt = #line) {
        assert(Thread.isMainThread, "AetherListView UI state must be mutated on the main thread", file: file, line: line)
    }

    private func alignedFrame(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        let scale = window?.screen.scale ?? UIScreen.main.scale
        return AetherListFrameMetrics.pixelAligned(CGRect(x: x, y: y, width: width, height: height), scale: scale)
    }

    /// Find the index `dragging` would land at if the drag finished
    /// right now. Walks the height table — proposed insertion is the
    /// first slot whose vertical centre is below the finger.
    private func indexForReorderInsertion(centerY: CGFloat, dragging: Int) -> Int? {
        guard !items.isEmpty else { return nil }
        // For each item, compute its centre Y and find the slot the
        // finger crossed. Items.count == itemHeights.count is invariant.
        var y: CGFloat = 0
        var proposed = items.count - 1
        for i in 0..<items.count {
            let h = itemHeights[i]
            let centre = y + h / 2
            if centerY < centre {
                proposed = i
                break
            }
            y += h
        }
        return min(items.count - 1, max(0, proposed))
    }

    // MARK: - Private State

    private let scrollView = AetherListScroller()
    private var previousDidScrollContentOffsetY: CGFloat?
    private var boundaryTriggerSignatures: [AetherListBoundaryEdge: BoundaryTriggerSignature] = [:]

    private struct BoundaryTriggerSignature: Equatable {
        let itemCount: Int
        let loadedLowerBound: Int?
        let loadedUpperBound: Int?
        let visibleLowerBound: Int?
        let visibleUpperBound: Int?
    }

    /// All item models in order.
    private var items: [AetherListItem] = []

    /// Currently loaded nodes, sorted by index. Not all items have nodes —
    /// only those within the visible + preload range.
    private var itemNodes: [AetherListItemNode] = []
    private var accessibilityNodeOrder: [ObjectIdentifier] = []

    /// Cached heights for each item (index → totalHeight).
    private var itemHeights: [CGFloat] = []

    /// Cumulative Y offsets for each item (index → top Y of item).
    private var itemOffsets: [CGFloat] = []

    /// Total content height.
    private var totalContentHeight: CGFloat = 0

    /// Current layout params.
    private var layoutParams: AetherListItemLayoutParams?

    /// Stable-id layout cache. Heights are kept even after views leave the
    /// hierarchy so variable-height lists do not fall back to estimates every
    /// time a row re-enters the preload window.
    private var layoutCache: [AnyHashable: AetherListItemNodeLayout] = [:]
    private var layoutCacheOrder: [AnyHashable] = []
    private let maxLayoutCacheEntries = 4096

    /// Prepared layout cache keyed by stable id. It stores the full
    /// layout+apply pair produced by `AetherListItem.asyncLayout`, not just
    /// the height, so materialized visible nodes can consume off-main work.
    private var preparedLayoutCache: [AnyHashable: AetherListPreparedItemLayout] = [:]

    /// Reuse pool keyed by `AetherListItem.reuseIdentifier`.
    private var reusePool: [String: [AetherListItemNode]] = [:]
    private let maxReusableNodesPerIdentifier = 32

    /// In-flight async layout preparation keyed by stable id.
    private var pendingLayoutTasks: [AnyHashable: AetherListLayoutTask] = [:]
    private var synchronousLayoutIdentifiers: Set<String> = []

    private let displayLinkDriver = AetherListDisplayLinkDriver()
    private weak var debugOverlayLabel: UILabel?
    private weak var customScrollIndicatorView: UIView?
    private var customScrollIndicatorFadeWorkItem: DispatchWorkItem?

    /// Animation duration for transactions.
    private let animationDuration: Double = 0.3

    /// Visible lifetime for the Telegram-style dust burst. Keep neighbour
    /// slide, source fade, and delayed removal tied to one value so the row
    /// does not disappear on one timeline while particles run on another.
    private let particleDissolveVisualDuration: TimeInterval = 0.8

    /// The shader keeps Telegram's original particle lifetime distribution;
    /// drive the overlay faster for list deletes so the dust cloud resolves
    /// on the same shorter timeline as the row fade.
    private let particleDissolveDustAnimationSpeed: Float = 2.0

    /// Pending transaction queue (serialized).
    private var isProcessingTransaction = false
    private var pendingTransactions: [() -> Void] = []
    private var afterTransactionsCompleted: [() -> Void] = []

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        if automaticallyAdjustsContentInsetForKeyboard {
            unregisterKeyboardObserver()
        }
        NotificationCenter.default.removeObserver(self, name: UIContentSizeCategory.didChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        // The dust overlay may live in a host outside the list view
        // (e.g. `view.window` set by a chat controller). Without
        // this teardown a finished or in-flight burst would keep
        // the overlay parented to the window after the list itself
        // is gone — visually a stranded ghost effect on the next
        // screen.
        dustEffectView?.removeFromSuperview()
        dustEffectView = nil
        pendingLayoutTasks.values.forEach { $0.cancel() }
        customScrollIndicatorFadeWorkItem?.cancel()
    }

    private func setup() {
        isOpaque = false
        scrollView.delegate = self
        scrollView.alwaysBounceVertical = true
        scrollView.bounces = true
        scrollView.backgroundColor = .clear
        scrollView.isOpaque = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.scrollsToTop = true
        scrollView.backingView.backgroundColor = .clear
        scrollView.backingView.isOpaque = false
        scrollView.backingView.isUserInteractionEnabled = true
        // The list owns its insets — UIKit's automatic safe-area
        // adjustment would stack on top of what callers pass via
        // `self.insets`, doubling the navbar/tabbar gap.
        if #available(iOS 13.0, *) {
            scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        }
        if #available(iOS 11.0, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        addSubview(scrollView)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        scrollView.backingView.addGestureRecognizer(tapGesture)
        tapRecognizer = tapGesture

        setupReorderRecognizer()
        // Tap should only fire if the long-press doesn't pick up
        // first — without this gating a successful drag also fires
        // the row tap on release.
        if let lp = reorderRecognizer {
            tapGesture.require(toFail: lp)
        }

        isAccessibilityElement = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleContentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    // MARK: - Layout

    override open func layoutSubviews() {
        super.layoutSubviews()

        let boundsChanged = scrollView.frame.size != bounds.size
        scrollView.frame = bounds
        syncBackingViewBounds()
        // Only sync dust overlay frame when it's attached to the
        // list view itself; for caller-hosted overlays (e.g. window),
        // the host owns the resize via its own autoresizing mask.
        if let dustView = dustEffectView,
           dustView.superview === self,
           dustView.frame != bounds {
            dustView.frame = bounds
        }

        if boundsChanged {
            let params = AetherListItemLayoutParams(
                width: bounds.width,
                leftInset: safeAreaInsets.left,
                rightInset: safeAreaInsets.right,
                availableHeight: bounds.height
            )
            if params != layoutParams {
                clearLayoutPreparationCaches(cancelPendingTasks: true)
                layoutParams = params
                relayoutAllNodes(params: params)
            }
            updateVisibleNodes()
            // Viewport changed — recompute the stack-from-bottom
            // top padding that depends on it.
            if stackFromBottom {
                applyEffectiveInsets()
            }
        }
        syncBackingViewBounds()
        updateCustomScrollIndicator()
        updateOverscrollState()
        layoutDebugOverlay()
    }

    private func syncBackingViewBounds() {
        guard bounds.width.isFinite, bounds.height.isFinite else { return }
        let contentHeight = max(scrollView.contentSize.height, bounds.height)
        let targetFrame = CGRect(x: 0, y: 0, width: bounds.width, height: contentHeight)
        if scrollView.backingView.frame != targetFrame {
            scrollView.backingView.frame = targetFrame
        }
        var backingBounds = scrollView.backingView.bounds
        backingBounds.origin = .zero
        backingBounds.size = targetFrame.size
        if scrollView.backingView.bounds != backingBounds {
            scrollView.backingView.bounds = backingBounds
        }
    }

    // MARK: - Public API: Transaction

    /// Apply a batch of changes to the list.
    ///
    /// All modifications (delete, move, insert, update) go through this
    /// single method. Changes are applied atomically and can be animated.
    /// Order of application: deletes → moves → inserts → updates. Indices
    /// for each step refer to the list state AFTER the previous step.
    public func transaction(
        deleteIndices: [AetherListDeleteItem] = [],
        moveIndices: [AetherListMoveItem] = [],
        insertIndicesAndItems: [AetherListInsertItem] = [],
        updateIndicesAndItems: [AetherListUpdateItem] = [],
        options: AetherListTransactionOptions = [],
        scrollToItem: AetherListScrollToItem? = nil,
        additionalScrollDistance: CGFloat = 0.0,
        updateSizeAndInsets: AetherListUpdateSizeAndInsets? = nil,
        stationaryItemRange: (Int, Int)? = nil,
        updateOpaqueState: Any? = nil,
        completion: ((AetherListDisplayedItemRange) -> Void)? = nil
    ) {
        let work: () -> Void = { [weak self] in
            guard let self else { return }
            self.assertMainThread()
            self.debugInstrumentation.measure("AetherListTransaction") {
                self.executeTransaction(
                    deleteIndices: deleteIndices,
                    moveIndices: moveIndices,
                    insertIndicesAndItems: insertIndicesAndItems,
                    updateIndicesAndItems: updateIndicesAndItems,
                    options: options,
                    scrollToItem: scrollToItem,
                    additionalScrollDistance: additionalScrollDistance,
                    updateSizeAndInsets: updateSizeAndInsets,
                    stationaryItemRange: stationaryItemRange,
                    updateOpaqueState: updateOpaqueState,
                    completion: completion
                )
            }
        }

        if isProcessingTransaction && !options.contains(.synchronous) && !options.contains(.lowLatency) {
            pendingTransactions.append(work)
        } else {
            work()
        }
    }

    /// Apply a prebuilt transaction object.
    public func transaction(
        _ transaction: AetherListTransaction,
        completion: ((AetherListDisplayedItemRange) -> Void)? = nil
    ) {
        self.transaction(
            deleteIndices: transaction.deleteIndices,
            moveIndices: transaction.moveIndices,
            insertIndicesAndItems: transaction.insertIndicesAndItems,
            updateIndicesAndItems: transaction.updateIndicesAndItems,
            options: transaction.options,
            scrollToItem: transaction.scrollToItem,
            additionalScrollDistance: transaction.additionalScrollDistance,
            updateSizeAndInsets: transaction.updateSizeAndInsets,
            stationaryItemRange: transaction.stationaryItemRange,
            updateOpaqueState: transaction.updateOpaqueState,
            completion: completion
        )
    }

    /// Scroll to an item at the given index.
    public func scrollToItem(at index: Int, position: AetherListScrollPosition, animated: Bool) {
        guard index >= 0 && index < items.count else { return }
        let targetY = computeScrollOffset(for: index, position: position)
        scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
        if !animated {
            syncBackingViewBounds()
        }
    }

    /// Stop any ongoing scrolling animation.
    public func stopScrolling() {
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        syncBackingViewBounds()
    }

    /// Velocity of the underlying pan gesture in the requested coordinate space.
    public func panVelocity(in view: UIView?) -> CGPoint {
        return scrollView.panGestureRecognizer.velocity(in: view)
    }

    /// Set a logical visible content offset and return whether the offset changed.
    @discardableResult
    public func setVisibleContentOffset(_ offset: CGFloat, animated: Bool) -> Bool {
        let clampedOffset = max(minimumVisibleContentOffset, offset)
        let targetY = clampedOffset - scrollView.contentInset.top
        let target = CGPoint(x: scrollView.contentOffset.x, y: targetY)
        guard abs(scrollView.contentOffset.y - target.y) > CGFloat.ulpOfOne else {
            return false
        }
        scrollView.setContentOffset(target, animated: animated)
        if !animated {
            syncBackingViewBounds()
        }
        return true
    }

    /// Iterate over all currently visible item nodes.
    public func forEachVisibleItemNode(_ body: (AetherListItemNode) -> Void) {
        for node in itemNodes {
            body(node)
        }
    }

    public func forEachItemNode(_ body: (AetherListItemNode) -> Void) {
        for node in itemNodes {
            body(node)
        }
    }

    public func enumerateItemNodes(_ body: (AetherListItemNode) -> Bool) {
        for node in itemNodes {
            if !body(node) {
                break
            }
        }
    }

    /// Find the visible node for an item at the given index.
    public func nodeForItem(at index: Int) -> AetherListItemNode? {
        return itemNodes.first { $0.index == index }
    }

    func itemNodeForListGesture(
        at point: CGPoint,
        gesture: AetherListItemGesture,
        consultExternalGate: Bool = true
    ) -> AetherListItemNode? {
        for node in itemNodesForListGestureHitTesting() {
            guard node.superview != nil,
                  !node.isHidden,
                  node.alpha > 0.01,
                  let index = node.index,
                  index >= 0,
                  index < items.count else {
                continue
            }

            let hitFrame = node.frame.inset(by: node.listGestureHitTestInsets(for: gesture))
            guard hitFrame.contains(point) else {
                continue
            }

            let pointInNode = node.convert(point, from: scrollView.backingView)
            guard node.allowsListGesture(gesture, at: pointInNode) else {
                continue
            }

            if gesture == .reorder {
                guard allowsReorder, items[index].canReorder else {
                    continue
                }
            }

            if consultExternalGate,
               let itemGestureShouldBegin,
               !itemGestureShouldBegin(gesture, index, node, pointInNode) {
                continue
            }

            return node
        }
        return nil
    }

    private func itemNodesForListGestureHitTesting() -> [AetherListItemNode] {
        let subviews = scrollView.backingView.subviews
        var subviewOrder: [ObjectIdentifier: Int] = [:]
        subviewOrder.reserveCapacity(subviews.count)
        for (index, view) in subviews.enumerated() {
            subviewOrder[ObjectIdentifier(view)] = index
        }

        return itemNodes.sorted { lhs, rhs in
            let lhsZ = lhs.layer.zPosition
            let rhsZ = rhs.layer.zPosition
            if abs(lhsZ - rhsZ) > CGFloat.ulpOfOne {
                return lhsZ > rhsZ
            }
            let lhsOrder = subviewOrder[ObjectIdentifier(lhs)] ?? -1
            let rhsOrder = subviewOrder[ObjectIdentifier(rhs)] ?? -1
            return lhsOrder > rhsOrder
        }
    }

    /// Current visible content offset from top.
    public func visibleContentOffset() -> CGFloat {
        return scrollView.contentOffset.y + scrollView.contentInset.top
    }

    /// Current visible content offset from bottom.
    public func visibleBottomContentOffset() -> CGFloat {
        return scrollView.contentSize.height + scrollView.contentInset.bottom - scrollView.bounds.height - scrollView.contentOffset.y
    }

    /// Run `f` after the currently executing/queued transactions settle.
    public func addAfterTransactionsCompleted(_ f: @escaping () -> Void) {
        if isProcessingTransaction || !pendingTransactions.isEmpty {
            afterTransactionsCompleted.append(f)
        } else {
            f()
        }
    }

    /// UIKit scroll views do not expose velocity transfer directly; this
    /// method keeps Telegram-compatible call sites valid and nudges the offset
    /// by one frame worth of velocity for handoff gestures.
    public func transferVelocity(_ velocity: CGFloat) {
        guard !velocity.isZero else { return }
        let delta = velocity / 60.0
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: scrollView.contentOffset.y - delta), animated: false)
        syncBackingViewBounds()
    }

    public func resetScrolledToItem() {
        scrollView.layer.removeAllAnimations()
    }

    public func resetBoundaryTriggers(edge: AetherListBoundaryEdge? = nil) {
        if let edge {
            boundaryTriggerSignatures.removeValue(forKey: edge)
        } else {
            boundaryTriggerSignatures.removeAll()
        }
    }

    @discardableResult
    public func ensureItemNodeVisible(_ node: AetherListItemNode, animated: Bool, overflow: CGFloat = 0.0, allowIntersection: Bool = true, atTop: Bool = false) -> Bool {
        guard itemNodes.contains(where: { $0 === node }) else { return false }
        let viewportTop = scrollView.contentOffset.y + scrollView.contentInset.top
        let viewportBottom = scrollView.contentOffset.y + bounds.height - scrollView.contentInset.bottom
        let frame = node.frame.inset(by: node.scrollPositioningInsets)
        if allowIntersection, frame.maxY > viewportTop, frame.minY < viewportBottom {
            return false
        }
        let targetY: CGFloat
        if atTop {
            targetY = frame.minY - scrollView.contentInset.top - overflow
        } else {
            targetY = frame.maxY - bounds.height + scrollView.contentInset.bottom + overflow
        }
        scrollView.setContentOffset(CGPoint(x: 0.0, y: targetY), animated: animated)
        if !animated {
            syncBackingViewBounds()
        }
        return true
    }

    // MARK: - Private: Transaction Execution

    private typealias TransactionRemovingNode = (
        node: AetherListItemNode,
        animation: AetherListItemDeleteAnimation,
        hint: AetherListItemOperationDirectionHint?
    )

    private struct TransactionLoadedNodeSnapshot {
        let preFrames: [ObjectIdentifier: CGRect]
        let preNodeIdsByIndex: [Int: ObjectIdentifier]
        let nodesByObjectIdentifier: [ObjectIdentifier: AetherListItemNode]
        let stationaryAnchor: AetherListIntermediateAnchor?
    }

    private struct TransactionModelMutationPhase {
        var removingNodes: [TransactionRemovingNode]
        let insertPreviousIndexByTargetIndex: [Int: Int]
        let insertDirectionHintByTargetIndex: [Int: AetherListItemOperationDirectionHint]
        let forceAnimateInsertionIndices: Set<Int>
        var materializationPlanner: AetherListNodeMaterializationPlanner<ObjectIdentifier>
    }

    private struct TransactionNodeMaterializationPhase {
        let insertedNodes: [AetherListItemNode]
        let visibleRange: Range<Int>
    }

    private final class AsyncLayoutTaskBox {
        var task: AetherListLayoutTask?
    }

    private final class UIKitModelMutationCommandExecutor: AetherListModelMutationCommandExecuting {
        private unowned let listView: AetherListView
        private let insertItems: [AetherListItem]
        private(set) var removingNodes: [TransactionRemovingNode] = []

        init(listView: AetherListView, insertItems: [AetherListItem]) {
            self.listView = listView
            self.insertItems = insertItems
        }

        func execute(_ command: AetherListModelMutationCommand<ObjectIdentifier>) {
            switch command {
            case let .delete(index, _, animation, hint):
                guard index >= 0, index < listView.items.count else { return }
                let deletingItem = listView.items[index]
                listView.cancelAsyncLayout(for: deletingItem)
                listView.invalidatePreparedLayout(for: deletingItem.stableId)
                if let nodeIndex = listView.itemNodes.firstIndex(where: { $0.index == index }) {
                    let node = listView.itemNodes[nodeIndex]
                    removingNodes.append((node, animation, hint))
                    listView.itemNodes.remove(at: nodeIndex)
                }
                listView.items.remove(at: index)
                listView.itemHeights.remove(at: index)

            case let .move(fromIndex, toIndex):
                guard fromIndex >= 0,
                      fromIndex < listView.items.count,
                      toIndex >= 0,
                      toIndex <= listView.items.count else {
                    return
                }
                let item = listView.items.remove(at: fromIndex)
                let height = listView.itemHeights.remove(at: fromIndex)
                let targetIndex = min(toIndex, listView.items.count)
                listView.items.insert(item, at: targetIndex)
                listView.itemHeights.insert(height, at: targetIndex)

            case let .insert(index, descriptor):
                guard descriptor.sourceIndex >= 0,
                      descriptor.sourceIndex < insertItems.count else {
                    return
                }
                let item = insertItems[descriptor.sourceIndex]
                let targetIndex = min(max(0, index), listView.items.count)
                listView.items.insert(item, at: targetIndex)
                listView.itemHeights.insert(descriptor.estimatedHeight, at: targetIndex)
            }
        }
    }

    private struct UIKitUpdateMaterializationCommandExecutor: AetherListUpdateMaterializationCommandExecuting {
        private unowned let listView: AetherListView
        private let updateItems: [AetherListUpdateItem]
        private let params: AetherListItemLayoutParams
        private let updateAnimation: AetherListItemUpdateAnimation
        private let snapshot: TransactionLoadedNodeSnapshot
        fileprivate var mutationPhase: TransactionModelMutationPhase

        init(
            listView: AetherListView,
            updateItems: [AetherListUpdateItem],
            params: AetherListItemLayoutParams,
            updateAnimation: AetherListItemUpdateAnimation,
            snapshot: TransactionLoadedNodeSnapshot,
            mutationPhase: TransactionModelMutationPhase
        ) {
            self.listView = listView
            self.updateItems = updateItems
            self.params = params
            self.updateAnimation = updateAnimation
            self.snapshot = snapshot
            self.mutationPhase = mutationPhase
        }

        mutating func execute(_ command: AetherListUpdateMaterializationCommand<ObjectIdentifier, ObjectIdentifier>) {
            switch command {
            case let .materialize(index, sourceIndex, _, nodeSource):
                guard applyUpdateItem(sourceIndex: sourceIndex, index: index) else {
                    return
                }
                guard let node = resolveNodeSource(nodeSource) else {
                    listView.itemHeights[index] = listView.estimatedHeight(for: updateItems[sourceIndex].item)
                    return
                }
                listView.mountNode(
                    at: index,
                    params: params,
                    source: .existing(node, updateAnimation),
                    notifyWillDisplay: false
                )

            case let .setEstimatedHeight(index, sourceIndex, _, height):
                guard applyUpdateItem(sourceIndex: sourceIndex, index: index) else {
                    return
                }
                listView.itemHeights[index] = height
            }
        }

        @discardableResult
        private func applyUpdateItem(sourceIndex: Int, index: Int) -> Bool {
            guard sourceIndex >= 0,
                  sourceIndex < updateItems.count,
                  index >= 0,
                  index < listView.items.count,
                  index < listView.itemHeights.count else {
                return false
            }

            let update = updateItems[sourceIndex]
            listView.cancelAsyncLayout(for: listView.items[index])
            listView.items[index] = update.item
            listView.invalidatePreparedLayout(for: update.item.stableId)
            return true
        }

        private mutating func resolveNodeSource(
            _ nodeSource: AetherListUpdateMaterializationNodeSource<ObjectIdentifier>
        ) -> AetherListItemNode? {
            switch nodeSource {
            case let .previous(command):
                return listView.applyPreviousNodeMaterializationCommand(
                    command,
                    snapshot: snapshot,
                    mutationPhase: &mutationPhase
                )

            case let .current(nodeId):
                return snapshot.nodesByObjectIdentifier[nodeId]
                    ?? listView.itemNodes.first(where: { ObjectIdentifier($0) == nodeId })
            }
        }
    }

    private struct UIKitVisibleNodeMaterializationCommandExecutor: AetherListVisibleNodeMaterializationCommandExecuting {
        private unowned let listView: AetherListView
        private let params: AetherListItemLayoutParams
        private let updateAnimation: AetherListItemUpdateAnimation
        private let snapshot: TransactionLoadedNodeSnapshot
        fileprivate var mutationPhase: TransactionModelMutationPhase
        fileprivate var insertedNodes: [AetherListItemNode] = []

        init(
            listView: AetherListView,
            params: AetherListItemLayoutParams,
            updateAnimation: AetherListItemUpdateAnimation,
            snapshot: TransactionLoadedNodeSnapshot,
            mutationPhase: TransactionModelMutationPhase
        ) {
            self.listView = listView
            self.params = params
            self.updateAnimation = updateAnimation
            self.snapshot = snapshot
            self.mutationPhase = mutationPhase
        }

        mutating func execute(_ command: AetherListVisibleNodeMaterializationCommand<ObjectIdentifier>) {
            switch command {
            case let .mount(index, source):
                if listView.itemNodes.contains(where: { $0.index == index }) {
                    return
                }

                let mountSource: NodeMountSource
                switch source {
                case let .previous(command):
                    if let previousNode = listView.applyPreviousNodeMaterializationCommand(
                        command,
                        snapshot: snapshot,
                        mutationPhase: &mutationPhase
                    ) {
                        mountSource = .existing(previousNode, updateAnimation)
                    } else {
                        mountSource = .reusableOrCreated
                    }

                case .reusableOrCreated:
                    mountSource = .reusableOrCreated
                }

                guard let mount = listView.mountNode(
                    at: index,
                    params: params,
                    source: mountSource,
                    notifyWillDisplay: true
                ) else {
                    return
                }
                if mount.didAcquireFreshNode {
                    insertedNodes.append(mount.node)
                }
            }
        }
    }

    private struct UIKitStickyHeaderCommandExecutor: AetherListStickyHeaderCommandExecuting {
        private unowned let listView: AetherListView
        private let params: AetherListItemLayoutParams
        fileprivate var didChangeHeights = false
        fileprivate var didMountNodes = false

        init(listView: AetherListView, params: AetherListItemLayoutParams) {
            self.listView = listView
            self.params = params
        }

        mutating func execute(_ command: AetherListStickyHeaderCommand<ObjectIdentifier>) {
            switch command {
            case let .ensureNode(index):
                guard index >= 0,
                      index < listView.items.count,
                      !listView.itemNodes.contains(where: { $0.index == index }) else {
                    return
                }
                guard let mount = listView.mountNode(
                    at: index,
                    params: params,
                    source: .reusableOrCreated,
                    notifyWillDisplay: true
                ) else {
                    return
                }
                didMountNodes = true
                if mount.didChangeHeight {
                    didChangeHeights = true
                }

            case let .applyLayout(nodeId, _, frame, state, zPosition, bringToFront):
                guard let node = listView.itemNodes.first(where: { ObjectIdentifier($0) == nodeId }) else {
                    return
                }
                if node.frame != frame {
                    node.frame = frame
                }
                node.updateStickyHeaderState(state, animated: false)
                node.layer.zPosition = zPosition
                if bringToFront {
                    listView.scrollView.backingView.bringSubviewToFront(node)
                }
            }
        }
    }

    private struct UIKitVirtualizationCommandExecutor: AetherListVirtualizationCommandExecuting {
        private unowned let listView: AetherListView
        private let params: AetherListItemLayoutParams
        fileprivate var didChangeHeights = false
        fileprivate var didMutateNodes = false

        init(listView: AetherListView, params: AetherListItemLayoutParams) {
            self.listView = listView
            self.params = params
        }

        mutating func execute(_ command: AetherListVirtualizationCommand<ObjectIdentifier>) {
            switch command {
            case let .recycle(nodeId, _):
                guard let nodeIndex = listView.itemNodes.firstIndex(where: { ObjectIdentifier($0) == nodeId }) else {
                    return
                }
                let node = listView.itemNodes[nodeIndex]
                listView.recycleNode(node)
                listView.itemNodes.remove(at: nodeIndex)
                didMutateNodes = true

            case let .mount(index):
                guard index >= 0,
                      index < listView.items.count,
                      !listView.itemNodes.contains(where: { $0.index == index }) else {
                    return
                }
                guard let mount = listView.mountNode(
                    at: index,
                    params: params,
                    source: .reusableOrCreated,
                    notifyWillDisplay: true
                ) else {
                    return
                }
                didMutateNodes = true
                if mount.didChangeHeight {
                    didChangeHeights = true
                }

            case let .setFrame(nodeId, _, frame):
                guard let node = listView.itemNodes.first(where: { ObjectIdentifier($0) == nodeId }) else {
                    return
                }
                node.frame = frame
                node.updateAbsoluteRect(frame, within: listView.bounds.size)
            }
        }
    }

    private struct UIKitAsyncLayoutCommandExecutor: AetherListAsyncLayoutCommandExecuting {
        private unowned let listView: AetherListView
        private let params: AetherListItemLayoutParams

        init(listView: AetherListView, params: AetherListItemLayoutParams) {
            self.listView = listView
            self.params = params
        }

        mutating func execute(_ command: AetherListAsyncLayoutCommand<AnyHashable>) {
            switch command {
            case let .cancel(itemId):
                listView.cancelAsyncLayout(forID: itemId)

            case let .prepare(index, itemId):
                listView.startAsyncLayoutPreparation(at: index, itemId: itemId, params: params)
            }
        }
    }

    private final class UIKitVisibilityLifecycleCommandExecutor: AetherListVisibilityLifecycleCommandExecuting {
        private unowned let listView: AetherListView

        init(listView: AetherListView) {
            self.listView = listView
        }

        func execute(_ command: AetherListVisibilityLifecycleCommand<ObjectIdentifier>) {
            switch command {
            case let .recordVisibleViews(count):
                listView.debugInstrumentation.recordVisibleViews(count)

            case let .setAccessibilityOrder(nodeIds):
                listView.accessibilityNodeOrder = nodeIds

            case let .notifyDisplayedRange(displayedRange):
                listView.displayedItemRangeChanged?(displayedRange)
            }
        }
    }

    private final class UIKitSizeAndInsetsCommandExecutor: AetherListSizeAndInsetsCommandExecuting {
        private unowned let listView: AetherListView
        private let customTransition: ContainedViewLayoutTransition?

        init(listView: AetherListView, customTransition: ContainedViewLayoutTransition?) {
            self.listView = listView
            self.customTransition = customTransition
        }

        func execute(_ command: AetherListSizeAndInsetsCommand) {
            switch command {
            case let .update(update):
                let transition: ContainedViewLayoutTransition
                if update.prefersCustomTransition, let customTransition {
                    transition = customTransition
                } else {
                    transition = update.transition.containedTransition
                }

                if let targetFrame = update.targetFrame {
                    transition.updateFrame(view: listView, frame: targetFrame)
                }
                if let updatedLayoutParams = update.updatedLayoutParams {
                    listView.clearLayoutPreparationCaches(cancelPendingTasks: true)
                    listView.layoutParams = updatedLayoutParams
                }
                listView.headerInsets = update.headerInsets
                listView.scrollIndicatorInsets = update.scrollIndicatorInsets
                listView.updateContentMetricInsets(
                    itemOffsetInsets: update.itemOffsetInsets,
                    virtualContentInsets: update.virtualContentInsets ?? listView._virtualContentInsets,
                    transition: transition,
                    preserveContentOffset: true,
                    notifyVisibilityLifecycle: false
                )
                listView.updateInsets(update.insets, transition: transition)

            case let .forceRelayout(params):
                listView.relayoutAllNodes(params: params)
            }
        }
    }

    private final class UIKitFrameReplayCommandExecutor: AetherListFrameReplayCommandExecuting {
        private unowned let listView: AetherListView
        private let nodesById: [ObjectIdentifier: AetherListItemNode]

        init(listView: AetherListView, nodesById: [ObjectIdentifier: AetherListItemNode]) {
            self.listView = listView
            self.nodesById = nodesById
        }

        func execute(_ command: AetherListFrameReplayCommand<ObjectIdentifier>) {
            switch command {
            case let .setFrame(nodeId, frame):
                guard let node = nodesById[nodeId] else { return }
                node.frame = frame
                node.updateAbsoluteRect(frame, within: listView.bounds.size)

            case let .animateFrame(nodeId, from, to, duration, curve):
                guard let node = nodesById[nodeId] else { return }
                node.frame = from
                UIView.animate(
                    withDuration: duration,
                    delay: 0,
                    options: curve.uiViewAnimationOptions,
                    animations: { node.frame = to },
                    completion: nil
                )

            case let .insert(nodeId, frame, animation):
                guard let node = nodesById[nodeId] else { return }
                node.frame = frame
                switch animation {
                case .none:
                    break
                case let .alphaFade(duration):
                    node.alpha = 0.0
                    UIView.animate(
                        withDuration: duration,
                        delay: 0,
                        options: [.beginFromCurrentState, .allowUserInteraction],
                        animations: { node.alpha = 1.0 },
                        completion: nil
                    )
                case let .item(duration, directionHint, invertOffsetDirection):
                    node.animateInsertion(
                        duration: duration,
                        directionHint: directionHint,
                        invertOffsetDirection: invertOffsetDirection
                    )
                }

            case let .remove(nodeId, animation, hint):
                guard let node = nodesById[nodeId] else { return }
                guard let animation else {
                    listView.recycleNode(node)
                    return
                }
                listView.runDeleteAnimation(animation, on: node, hint: hint) {
                    self.listView.recycleNode(node)
                }
            }
        }
    }

    private final class UIKitScrollAnchoringCommandExecutor: AetherListScrollAnchoringCommandExecuting {
        private unowned let listView: AetherListView

        init(listView: AetherListView) {
            self.listView = listView
        }

        func execute(_ command: AetherListScrollAnchoringCommand) {
            switch command {
            case let .setContentOffset(offset, animated):
                listView.scrollView.setContentOffset(offset, animated: animated)
                if !animated {
                    listView.syncBackingViewBounds()
                }

            case let .adjustContentOffset(deltaY, animated, transition):
                let targetOffset = CGPoint(
                    x: listView.scrollView.contentOffset.x,
                    y: listView.scrollView.contentOffset.y + deltaY
                )
                switch transition {
                case .immediate:
                    listView.scrollView.setContentOffset(targetOffset, animated: animated)
                    if !animated {
                        listView.syncBackingViewBounds()
                    }
                case .animated:
                    transition.containedTransition.animateView {
                        self.listView.scrollView.contentOffset = targetOffset
                    }
                }

            case let .applyEffectiveInsetsAndScrollToBottom(animated):
                listView.applyEffectiveInsets()
                listView.scrollToBottom(animated: animated)
            }
        }
    }

    private func executeTransaction(
        deleteIndices: [AetherListDeleteItem],
        moveIndices: [AetherListMoveItem],
        insertIndicesAndItems: [AetherListInsertItem],
        updateIndicesAndItems: [AetherListUpdateItem],
        options: AetherListTransactionOptions,
        scrollToItem: AetherListScrollToItem?,
        additionalScrollDistance: CGFloat,
        updateSizeAndInsets: AetherListUpdateSizeAndInsets?,
        stationaryItemRange: (Int, Int)?,
        updateOpaqueState: Any?,
        completion: ((AetherListDisplayedItemRange) -> Void)?
    ) {
        isProcessingTransaction = true
        debugInstrumentation.recordTransaction()
        if let updateOpaqueState {
            opaqueState = updateOpaqueState
        }

        let wasNearBottom = stackFromBottom && isNearBottom(tolerance: stackFromBottomAutoAnchorTolerance)
        let hasForcedInsertionAnimation = insertIndicesAndItems.contains(where: { $0.forceAnimateInsertion })
        applyTransactionSizeAndInsetsPhase(
            options: options,
            updateSizeAndInsets: updateSizeAndInsets
        )
        let initialReplayPlan = makeInitialReplayPlan(
            options: options,
            hasForcedInsertionAnimation: hasForcedInsertionAnimation
        )
        let snapshot = makeTransactionLoadedNodeSnapshot(stationaryItemRange: stationaryItemRange)
        var mutationPhase = applyTransactionModelMutationPhase(
            deleteIndices: deleteIndices,
            moveIndices: moveIndices,
            insertIndicesAndItems: insertIndicesAndItems,
            snapshot: snapshot
        )
        let params = layoutParams ?? AetherListItemLayoutParams(width: bounds.width)
        let materializationPhase = applyTransactionNodeMaterializationPhase(
            updateIndicesAndItems: updateIndicesAndItems,
            params: params,
            initialReplayPlan: initialReplayPlan,
            snapshot: snapshot,
            mutationPhase: &mutationPhase
        )
        let replayPlan = applyTransactionFrameReplayPhase(
            options: options,
            hasForcedInsertionAnimation: hasForcedInsertionAnimation,
            insertedNodes: materializationPhase.insertedNodes,
            removingNodes: mutationPhase.removingNodes,
            snapshot: snapshot,
            mutationPhase: mutationPhase
        )
        applyStickyHeaderLayout()
        prefetchAsyncLayouts(in: materializationPhase.visibleRange, params: params)
        assertNoDuplicateVisibleNodes()

        applyTransactionScrollAnchoringPhase(
            scrollToItem: scrollToItem,
            additionalScrollDistance: additionalScrollDistance,
            updateSizeAndInsets: updateSizeAndInsets,
            stationaryAnchor: snapshot.stationaryAnchor,
            wasNearBottom: wasNearBottom,
            animate: replayPlan.animatesStructuralChanges,
            options: options
        )

        let displayedRange = applyVisibilityLifecycle()
        completion?(displayedRange)
        updateCustomScrollIndicator()

        isProcessingTransaction = false
        if let next = pendingTransactions.first {
            pendingTransactions.removeFirst()
            displayLinkDriver.schedule(next)
        } else if !afterTransactionsCompleted.isEmpty {
            let callbacks = afterTransactionsCompleted
            afterTransactionsCompleted.removeAll()
            callbacks.forEach { $0() }
        }
    }

    private func applyTransactionSizeAndInsetsPhase(
        options: AetherListTransactionOptions,
        updateSizeAndInsets: AetherListUpdateSizeAndInsets?
    ) {
        guard let command = AetherListSizeAndInsetsCommandPlanner.command(
            currentFrame: frame,
            currentBoundsSize: bounds.size,
            safeAreaInsets: safeAreaInsets,
            currentLayoutParams: layoutParams,
            options: options,
            update: updateSizeAndInsets
        ) else { return }

        let executor = UIKitSizeAndInsetsCommandExecutor(
            listView: self,
            customTransition: updateSizeAndInsets?.customTransition
        )
        executor.execute(command)
    }

    private func makeInitialReplayPlan(
        options: AetherListTransactionOptions,
        hasForcedInsertionAnimation: Bool
    ) -> AetherListNodeReplayPlan {
        AetherListNodeReplayPlan.make(
            options: options,
            hasForcedInsertionAnimation: hasForcedInsertionAnimation,
            hasParticleDissolveRemoval: false,
            baseDuration: animationDuration,
            particleDissolveDuration: particleDissolveVisualDuration,
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
    }

    private func makeTransactionLoadedNodeSnapshot(stationaryItemRange: (Int, Int)?) -> TransactionLoadedNodeSnapshot {
        var preFrames: [ObjectIdentifier: CGRect] = [:]
        var preNodeIdsByIndex: [Int: ObjectIdentifier] = [:]
        var nodesByObjectIdentifier: [ObjectIdentifier: AetherListItemNode] = [:]
        var loadedIndices = Set<Int>()
        for node in itemNodes {
            let nodeId = ObjectIdentifier(node)
            preFrames[nodeId] = node.frame
            nodesByObjectIdentifier[nodeId] = node
            if let index = node.index {
                preNodeIdsByIndex[index] = nodeId
                loadedIndices.insert(index)
            }
        }

        let preIntermediateState = makeIntermediateState()
        return TransactionLoadedNodeSnapshot(
            preFrames: preFrames,
            preNodeIdsByIndex: preNodeIdsByIndex,
            nodesByObjectIdentifier: nodesByObjectIdentifier,
            stationaryAnchor: preIntermediateState.stationaryAnchor(
                in: stationaryItemRange,
                loadedIndices: loadedIndices
            )
        )
    }

    private func applyTransactionModelMutationPhase(
        deleteIndices: [AetherListDeleteItem],
        moveIndices: [AetherListMoveItem],
        insertIndicesAndItems: [AetherListInsertItem],
        snapshot: TransactionLoadedNodeSnapshot
    ) -> TransactionModelMutationPhase {
        let insertDescriptors = insertIndicesAndItems.enumerated().map { sourceIndex, insert in
            AetherListModelMutationInsertDescriptor(
                sourceIndex: sourceIndex,
                requestedIndex: insert.index,
                itemId: ObjectIdentifier(insert.item),
                estimatedHeight: estimatedHeight(for: insert.item),
                previousIndex: insert.previousIndex,
                directionHint: insert.directionHint,
                forceAnimateInsertion: insert.forceAnimateInsertion
            )
        }
        let plan = AetherListModelMutationCommandPlanner.plan(
            itemIds: items.map { ObjectIdentifier($0) },
            itemHeights: itemHeights,
            deleteItems: deleteIndices,
            moveItems: moveIndices,
            insertDescriptors: insertDescriptors
        )
        let executor = UIKitModelMutationCommandExecutor(
            listView: self,
            insertItems: insertIndicesAndItems.map(\.item)
        )
        plan.commands.forEach { executor.execute($0) }

        reindexVisibleNodesByItemIdentity()

        var currentNodeIdsByIndex: [Int: ObjectIdentifier] = [:]
        for node in itemNodes {
            if let index = node.index {
                currentNodeIdsByIndex[index] = ObjectIdentifier(node)
            }
        }

        return TransactionModelMutationPhase(
            removingNodes: executor.removingNodes,
            insertPreviousIndexByTargetIndex: plan.insertPreviousIndexByTargetIndex,
            insertDirectionHintByTargetIndex: plan.insertDirectionHintByTargetIndex,
            forceAnimateInsertionIndices: plan.forceAnimateInsertionIndices,
            materializationPlanner: AetherListNodeMaterializationPlanner(
                previousNodeByIndex: snapshot.preNodeIdsByIndex,
                currentNodeByIndex: currentNodeIdsByIndex
            )
        )
    }

    private func applyPreviousNodeMaterializationCommand(
        _ command: AetherListNodeMaterializationCommand<ObjectIdentifier>,
        snapshot: TransactionLoadedNodeSnapshot,
        mutationPhase: inout TransactionModelMutationPhase
    ) -> AetherListItemNode? {
        guard let node = snapshot.nodesByObjectIdentifier[command.nodeId] else {
            return nil
        }

        if let removingIndex = mutationPhase.removingNodes.firstIndex(where: { $0.node === node }) {
            mutationPhase.removingNodes.remove(at: removingIndex)
        }
        if let duplicateNodeId = command.duplicateTargetNodeId,
           let duplicate = snapshot.nodesByObjectIdentifier[duplicateNodeId],
           duplicate !== node,
           let duplicateIndex = itemNodes.firstIndex(where: { $0 === duplicate }) {
            itemNodes.remove(at: duplicateIndex)
            recycleNode(duplicate)
        }
        if !itemNodes.contains(where: { $0 === node }) {
            itemNodes.append(node)
        }
        if node.superview !== scrollView.backingView {
            scrollView.backingView.addSubview(node)
        }
        node.index = command.targetIndex
        return node
    }

    private func applyTransactionNodeMaterializationPhase(
        updateIndicesAndItems: [AetherListUpdateItem],
        params: AetherListItemLayoutParams,
        initialReplayPlan: AetherListNodeReplayPlan,
        snapshot: TransactionLoadedNodeSnapshot,
        mutationPhase: inout TransactionModelMutationPhase
    ) -> TransactionNodeMaterializationPhase {
        let updateDescriptors = updateIndicesAndItems.enumerated().map { sourceIndex, update in
            AetherListUpdateMaterializationDescriptor(
                sourceIndex: sourceIndex,
                index: update.index,
                previousIndex: update.previousIndex,
                itemId: ObjectIdentifier(update.item),
                estimatedHeight: estimatedHeight(for: update.item)
            )
        }
        let updateCommands = AetherListUpdateMaterializationCommandPlanner.commands(
            descriptors: updateDescriptors,
            itemCount: items.count,
            materializationPlanner: &mutationPhase.materializationPlanner
        )
        var updateExecutor = UIKitUpdateMaterializationCommandExecutor(
            listView: self,
            updateItems: updateIndicesAndItems,
            params: params,
            updateAnimation: itemUpdateAnimation(for: initialReplayPlan.updateAnimation),
            snapshot: snapshot,
            mutationPhase: mutationPhase
        )
        for command in updateCommands {
            updateExecutor.execute(command)
        }
        mutationPhase = updateExecutor.mutationPhase

        rebuildOffsets()

        let visibleRange = computeVisibleRange()
        let visibleMaterializationCommands = AetherListVisibleNodeMaterializationCommandPlanner.commands(
            visibleRange: visibleRange,
            insertPreviousIndexByTargetIndex: mutationPhase.insertPreviousIndexByTargetIndex,
            materializationPlanner: &mutationPhase.materializationPlanner
        )
        var visibleMaterializationExecutor = UIKitVisibleNodeMaterializationCommandExecutor(
            listView: self,
            params: params,
            updateAnimation: itemUpdateAnimation(for: initialReplayPlan.updateAnimation),
            snapshot: snapshot,
            mutationPhase: mutationPhase
        )
        for command in visibleMaterializationCommands {
            visibleMaterializationExecutor.execute(command)
        }
        mutationPhase = visibleMaterializationExecutor.mutationPhase

        itemNodes.sort { ($0.index ?? 0) < ($1.index ?? 0) }
        rebuildOffsets()
        updateContentSize()

        return TransactionNodeMaterializationPhase(
            insertedNodes: visibleMaterializationExecutor.insertedNodes,
            visibleRange: visibleRange
        )
    }

    @discardableResult
    private func applyTransactionFrameReplayPhase(
        options: AetherListTransactionOptions,
        hasForcedInsertionAnimation: Bool,
        insertedNodes: [AetherListItemNode],
        removingNodes: [TransactionRemovingNode],
        snapshot: TransactionLoadedNodeSnapshot,
        mutationPhase: TransactionModelMutationPhase
    ) -> AetherListNodeReplayPlan {
        let hasParticleDissolve = removingNodes.contains { _, animation, _ in
            if case .particleDissolve = animation { return true }
            return false
        }
        let replayPlan = AetherListNodeReplayPlan.make(
            options: options,
            hasForcedInsertionAnimation: hasForcedInsertionAnimation,
            hasParticleDissolveRemoval: hasParticleDissolve,
            baseDuration: animationDuration,
            particleDissolveDuration: particleDissolveVisualDuration,
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )

        executeFrameReplayCommands(
            replayPlan: replayPlan,
            options: options,
            insertedNodes: insertedNodes,
            removingNodes: removingNodes,
            snapshot: snapshot,
            mutationPhase: mutationPhase
        )

        return replayPlan
    }

    private func executeFrameReplayCommands(
        replayPlan: AetherListNodeReplayPlan,
        options: AetherListTransactionOptions,
        insertedNodes: [AetherListItemNode],
        removingNodes: [TransactionRemovingNode],
        snapshot: TransactionLoadedNodeSnapshot,
        mutationPhase: TransactionModelMutationPhase
    ) {
        var nodesById = snapshot.nodesByObjectIdentifier
        var nodeIdsInDisplayOrder: [ObjectIdentifier] = []
        var indexByNodeId: [ObjectIdentifier: Int] = [:]
        var targetFrameByNodeId: [ObjectIdentifier: CGRect] = [:]

        for node in itemNodes {
            let nodeId = ObjectIdentifier(node)
            nodesById[nodeId] = node
            nodeIdsInDisplayOrder.append(nodeId)
            guard let index = node.index,
                  index < itemOffsets.count,
                  index < itemHeights.count else {
                continue
            }
            indexByNodeId[nodeId] = index
            targetFrameByNodeId[nodeId] = alignedFrame(
                x: 0,
                y: itemOffsets[index],
                width: bounds.width,
                height: itemHeights[index]
            )
        }

        let insertedNodeIds = Set(insertedNodes.map { ObjectIdentifier($0) })
        let removals = removingNodes.map { node, animation, hint in
            AetherListFrameReplayRemoval(
                nodeId: ObjectIdentifier(node),
                animation: animation,
                hint: hint
            )
        }
        let commands = AetherListFrameReplayCommandPlanner.commands(
            nodeIdsInDisplayOrder: nodeIdsInDisplayOrder,
            indexByNodeId: indexByNodeId,
            targetFrameByNodeId: targetFrameByNodeId,
            previousFrameByNodeId: snapshot.preFrames,
            insertedNodeIds: insertedNodeIds,
            removals: removals,
            replayPlan: replayPlan,
            forceItemAnimationIndices: mutationPhase.forceAnimateInsertionIndices,
            insertionDirectionHintByIndex: mutationPhase.insertDirectionHintByTargetIndex,
            requestItemInsertionAnimations: options.contains(.requestItemInsertionAnimations),
            invertOffsetDirection: options.contains(.invertOffsetDirection)
        )
        let executor = UIKitFrameReplayCommandExecutor(listView: self, nodesById: nodesById)
        commands.forEach { executor.execute($0) }
    }

    private func applyTransactionScrollAnchoringPhase(
        scrollToItem: AetherListScrollToItem?,
        additionalScrollDistance: CGFloat,
        updateSizeAndInsets: AetherListUpdateSizeAndInsets?,
        stationaryAnchor: AetherListIntermediateAnchor?,
        wasNearBottom: Bool,
        animate: Bool,
        options: AetherListTransactionOptions
    ) {
        let postIntermediateState = makeIntermediateState()
        let resolvedScrollToOffsetY: CGFloat?
        if let scrollToItem,
           scrollToItem.index >= 0,
           scrollToItem.index < items.count {
            resolvedScrollToOffsetY = computeScrollOffset(
                for: scrollToItem.index,
                position: scrollToItem.position
            )
        } else {
            resolvedScrollToOffsetY = nil
        }
        let additionalDistanceTransition: AetherListLayoutTransitionSpec
        if let updateSizeAndInsets {
            additionalDistanceTransition = AetherListLayoutTransitionSpec.make(
                duration: updateSizeAndInsets.duration,
                curve: updateSizeAndInsets.curve
            )
        } else {
            additionalDistanceTransition = .immediate
        }

        guard let command = AetherListScrollAnchoringCommandPlanner.command(
            itemCount: items.count,
            scrollToItem: scrollToItem,
            resolvedScrollToOffsetY: resolvedScrollToOffsetY,
            additionalScrollDistance: additionalScrollDistance,
            additionalDistanceTransition: additionalDistanceTransition,
            stationaryAnchor: stationaryAnchor,
            postIntermediateState: postIntermediateState,
            currentContentOffset: scrollView.contentOffset,
            stackFromBottom: stackFromBottom,
            wasNearBottom: wasNearBottom,
            animate: animate,
            animateTopItemPosition: options.contains(.animateTopItemPosition)
        ) else { return }

        UIKitScrollAnchoringCommandExecutor(listView: self).execute(command)
    }

    private func itemUpdateAnimation(for replayAnimation: AetherListNodeUpdateReplayAnimation) -> AetherListItemUpdateAnimation {
        switch replayAnimation {
        case .none:
            return .none
        case .crossfade:
            return .crossfade
        case let .fullTransition(duration):
            return .system(duration: duration, transition: .animated(duration: duration, curve: .easeInOut))
        }
    }

    /// Drive one of the canned delete animations on `node`. Each style
    /// converges on alpha 0 plus an optional translate / scale; the
    /// caller is responsible for removing the node when `completion`
    /// fires.
    private func runDeleteAnimation(
        _ animation: AetherListItemDeleteAnimation,
        on node: AetherListItemNode,
        hint: AetherListItemOperationDirectionHint?,
        completion: @escaping () -> Void
    ) {
        switch animation {
        case .fade:
            UIView.animate(withDuration: animationDuration, animations: {
                node.alpha = 0
            }, completion: { _ in completion() })

        case .slide(let direction):
            let dx: CGFloat = direction == .up ? -bounds.width : bounds.width
            UIView.animate(withDuration: animationDuration, animations: {
                node.transform = CGAffineTransform(translationX: dx, y: 0)
                node.alpha = 0
            }, completion: { _ in completion() })

        case .scale:
            let resolvedHint = hint ?? .down
            let translateY: CGFloat = resolvedHint == .up ? -node.frame.height * 0.3 : node.frame.height * 0.3
            UIView.animate(
                withDuration: animationDuration,
                delay: 0,
                usingSpringWithDamping: 0.8,
                initialSpringVelocity: 0.2,
                options: [.beginFromCurrentState],
                animations: {
                    node.transform = CGAffineTransform(translationX: 0, y: translateY).scaledBy(x: 0.6, y: 0.6)
                    node.alpha = 0
                },
                completion: { _ in completion() }
            )

        case .particleDissolve(let tileSize):
            runParticleDissolve(on: node, tileSize: tileSize, completion: completion)
        }
    }

    /// Lazy-initialised dust effect view (`CAMetalLayer`-backed UIView).
    /// Sits as a sibling of the scroll view, covering the full list
    /// bounds so the Metal-rendered burst overlays whatever the row
    /// used to occupy.
    private var dustEffectView: AetherDustEffectView?

    /// Telegram's exact "Vanish on Delete" particle effect — direct
    /// port of `submodules/TelegramUI/Components/DustEffect`. The node
    /// is captured into a UIImage and handed to the dust layer, which
    /// runs a Metal compute kernel to evolve one particle per source
    /// pixel and draws them with a custom render pipeline. Falls back
    /// to a plain fade on devices without a Metal default library.
    private func runParticleDissolve(
        on node: AetherListItemNode,
        tileSize: CGFloat,
        completion: @escaping () -> Void
    ) {
        let target = node.particleDissolveTargetView
        let targetBounds = target.bounds
        guard targetBounds.width > 1, targetBounds.height > 1 else {
            UIView.animate(withDuration: animationDuration, animations: {
                node.alpha = 0
            }, completion: { _ in completion() })
            return
        }

        let dustView = ensureDustEffectView()
        guard dustView.isReady else {
            // No Metal pipeline — fall back to plain fade.
            UIView.animate(withDuration: animationDuration, animations: {
                node.alpha = 0
            }, completion: { _ in completion() })
            return
        }

        // ContextMenu (or other window-level chrome) may have left
        // the target with `alpha = 0`. A `drawHierarchy` snapshot of
        // an alpha-0 view is blank — force visible briefly, capture,
        // then drop alpha back so the particles own the visual.
        let savedAlpha = target.alpha
        target.alpha = 1
        let snapshot = AetherDustEffectView.snapshot(of: target)
        target.alpha = savedAlpha

        guard let snapshot = snapshot else {
            target.alpha = savedAlpha
            UIView.animate(withDuration: animationDuration, animations: {
                node.alpha = 0
            }, completion: { _ in completion() })
            return
        }

        // Convert directly into the dust overlay's coord space —
        // it might live in the list view, in the window, or in
        // some custom host the caller wired up. `tileSize` from the
        // delete-animation case caps the particle resolution: 1 = one
        // particle per pixel (Telegram default, expensive), larger
        // values quadratically reduce per-frame compute and prevent
        // micro-stutters when the burst overlaps other animations.
        let frameInOverlay = target.convert(target.bounds, to: dustView)
        dustView.animationSpeed = particleDissolveDustAnimationSpeed
        dustView.addItem(frame: frameInOverlay, image: snapshot, tileSize: tileSize)

        // Match the node's alpha decay to the shortened particle wave: the
        // row should look like it dissolves into the cloud, but the deletion
        // needs to resolve quickly enough for chat-like list interactions.
        // easeOut keeps the densest part of the cloud covering the source
        // while the last particles fade out.
        let dissolveDuration = particleDissolveVisualDuration
        UIView.animate(
            withDuration: dissolveDuration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: { node.alpha = 0 }
        )

        // Drop the node from the hierarchy at the same moment the fade
        // settles — keeps the visual deletion event ("row gone") in sync
        // with the wave's end. Neighbours slide up from this point on.
        DispatchQueue.main.asyncAfter(deadline: .now() + dissolveDuration) {
            completion()
        }
    }

    private func ensureDustEffectView() -> AetherDustEffectView {
        let view: AetherDustEffectView
        if let existing = dustEffectView {
            view = existing
        } else {
            let new = AetherDustEffectView(frame: .zero)
            new.isUserInteractionEnabled = false
            new.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            dustEffectView = new
            view = new
        }
        // Choose host: caller-supplied window-level overlay if set
        // (e.g. for chats with a context menu floating above),
        // otherwise the list view itself.
        let host: UIView = particleDissolveOverlayHost ?? self
        if view.superview !== host {
            view.removeFromSuperview()
            host.addSubview(view)
        }
        view.frame = host.bounds
        // Always bring to front — anything added after us (a context
        // menu, a toast, etc.) shouldn't paint over the burst.
        host.bringSubviewToFront(view)
        // Force the drawable size synchronously — layoutSubviews would
        // run a pass later, but the first `addItem` call below would
        // already try to grab a drawable. A 0-sized drawable hangs
        // inside `nextDrawable()`.
        let scale = view.metalLayer.contentsScale
        let pixelSize = CGSize(
            width: max(1, host.bounds.width * scale),
            height: max(1, host.bounds.height * scale)
        )
        if view.metalLayer.drawableSize != pixelSize {
            view.metalLayer.drawableSize = pixelSize
        }
        return view
    }

    // MARK: - Private: Layout Engine

    private func makeIntermediateState() -> AetherListIntermediateState {
        return AetherListIntermediateState(
            stableIds: items.map(\.stableId),
            heights: itemHeights,
            itemOffsetInsets: effectiveItemOffsetInsets()
        )
    }

    private func syncAccessories(for node: AetherListItemNode, item: AetherListItem) {
        node.setAccessoryItem(item.accessoryItem as? AetherListAccessoryItem, placement: .accessory)
        node.setAccessoryItem(item.headerAccessoryItem as? AetherListAccessoryItem, placement: .headerAccessory)
    }

    private enum NodeMountSource {
        case existing(AetherListItemNode, AetherListItemUpdateAnimation)
        case reusableOrCreated
    }

    private struct NodeMountResult {
        let node: AetherListItemNode
        let layout: AetherListItemNodeLayout
        let didAcquireFreshNode: Bool
        let didChangeHeight: Bool
    }

    @discardableResult
    private func mountNode(
        at index: Int,
        params: AetherListItemLayoutParams,
        source: NodeMountSource,
        notifyWillDisplay: Bool
    ) -> NodeMountResult? {
        guard index >= 0, index < items.count, index < itemHeights.count else {
            return nil
        }

        let item = items[index]
        let previousItem = index > 0 ? items[index - 1] : nil
        let nextItem = index + 1 < items.count ? items[index + 1] : nil
        let node: AetherListItemNode
        let fallbackLayout: AetherListItemNodeLayout
        let didAcquireFreshNode: Bool

        switch source {
        case let .existing(existingNode, animation):
            node = existingNode
            fallbackLayout = item.updateNode(
                existingNode,
                params: params,
                previousItem: previousItem,
                nextItem: nextItem,
                animation: animation
            )
            didAcquireFreshNode = false
        case .reusableOrCreated:
            if let reused = dequeueReusableNode(for: item) {
                node = reused
                fallbackLayout = item.updateNode(
                    reused,
                    params: params,
                    previousItem: previousItem,
                    nextItem: nextItem,
                    animation: .none
                )
            } else {
                let created = item.createNode(
                    params: params,
                    previousItem: previousItem,
                    nextItem: nextItem
                )
                node = created.0
                fallbackLayout = created.1
                debugInstrumentation.recordCreatedView()
            }
            didAcquireFreshNode = true
        }

        let layout = resolvedLayout(for: item, node: node, fallback: fallbackLayout)
        node.applyLayout(layout)
        node.index = index
        node.item = item
        syncAccessories(for: node, item: item)
        recordLayout(layout, for: item)
        node.pendingSelectionAnimated = false
        node.isSelected = selectedItemIds.contains(ObjectIdentifier(item))

        let didChangeHeight = abs(itemHeights[index] - layout.totalHeight) > 0.5
        itemHeights[index] = layout.totalHeight

        if !itemNodes.contains(where: { $0 === node }) {
            itemNodes.append(node)
        }
        if node.superview !== scrollView.backingView {
            scrollView.backingView.addSubview(node)
        }
        if notifyWillDisplay {
            item.willDisplay(node: node, at: index)
        }

        return NodeMountResult(
            node: node,
            layout: layout,
            didAcquireFreshNode: didAcquireFreshNode,
            didChangeHeight: didChangeHeight
        )
    }

    /// Rebuild cumulative Y offsets from item heights.
    private func rebuildOffsets() {
        let metrics = AetherListContentMetricsPlanner.metrics(
            itemHeights: itemHeights,
            itemOffsetInsets: _itemOffsetInsets,
            virtualContentInsets: _virtualContentInsets
        )
        itemOffsets = metrics.itemOffsets
        totalContentHeight = metrics.totalContentHeight
        // `stackFromBottom`'s top padding depends on
        // `totalContentHeight`, so any time the height changes the
        // effective insets need a refresh.
        if stackFromBottom {
            applyEffectiveInsets()
        }
    }

    /// Update the scroll view's content size.
    private func updateContentSize() {
        let contentHeight = max(totalContentHeight, 0)
        scrollView.contentSize = CGSize(width: bounds.width, height: contentHeight)
        syncBackingViewBounds()
        updateCustomScrollIndicator()
    }

    /// Position all loaded nodes at their correct Y offsets.
    private func positionNodes() {
        for node in itemNodes {
            guard let index = node.index, index < itemOffsets.count else { continue }
            let y = itemOffsets[index]
            node.frame = alignedFrame(x: 0, y: y, width: bounds.width, height: itemHeights[index])
            node.updateAbsoluteRect(node.frame, within: bounds.size)
        }
    }

    /// Relayout all existing nodes (e.g. after width change).
    private func relayoutAllNodes(params: AetherListItemLayoutParams) {
        for node in itemNodes {
            guard let index = node.index, index < items.count else { continue }
            let item = items[index]
            let prevItem = index > 0 ? items[index - 1] : nil
            let nextItem = index + 1 < items.count ? items[index + 1] : nil
            let fallbackLayout = item.updateNode(node, params: params, previousItem: prevItem, nextItem: nextItem, animation: .none)
            let newLayout = resolvedLayout(for: item, node: node, fallback: fallbackLayout)
            node.applyLayout(newLayout)
            syncAccessories(for: node, item: item)
            recordLayout(newLayout, for: item)
            itemHeights[index] = newLayout.totalHeight
        }
        rebuildOffsets()
        positionNodes()
        updateContentSize()
    }

    private func estimatedHeight(for item: AetherListItem) -> CGFloat {
        if let prepared = preparedLayoutCache[item.stableId] {
            debugInstrumentation.recordLayoutCacheHit()
            return prepared.layout.totalHeight
        }
        if let cached = layoutCache[item.stableId] {
            debugInstrumentation.recordLayoutCacheHit()
            return cached.totalHeight
        }
        debugInstrumentation.recordLayoutCacheMiss()
        return item.estimatedHeight
    }

    private func recordLayout(_ layout: AetherListItemNodeLayout, for item: AetherListItem) {
        let id = item.stableId
        if layoutCache[id] == nil {
            layoutCacheOrder.append(id)
        }
        layoutCache[id] = layout
        while layoutCacheOrder.count > maxLayoutCacheEntries {
            let removed = layoutCacheOrder.removeFirst()
            layoutCache.removeValue(forKey: removed)
            preparedLayoutCache.removeValue(forKey: removed)
        }
    }

    private func resolvedLayout(
        for item: AetherListItem,
        node: AetherListItemNode,
        fallback: AetherListItemNodeLayout
    ) -> AetherListItemNodeLayout {
        guard let prepared = preparedLayoutCache[item.stableId] else {
            return fallback
        }
        prepared.apply(node)
        return prepared.layout
    }

    private func dequeueReusableNode(for item: AetherListItem) -> AetherListItemNode? {
        let key = item.reuseIdentifier
        guard var bucket = reusePool[key], !bucket.isEmpty else { return nil }
        let node = bucket.removeLast()
        reusePool[key] = bucket
        node.alpha = 1
        node.transform = .identity
        node.updateStickyHeaderState(.none, animated: false)
        node.layer.removeAllAnimations()
        node.layer.zPosition = 0
        node.layer.shadowOpacity = 0
        node.isHidden = false
        debugInstrumentation.recordReusedView()
        return node
    }

    private func recycleNode(_ node: AetherListItemNode) {
        assertMainThread()
        if let item = node.item, let index = node.index {
            item.didEndDisplay(node: node, at: index)
        }
        let key = node.item?.reuseIdentifier
        node.prepareForReuse()
        node.removeFromSuperview()
        node.index = nil
        node.item = nil
        node.alpha = 1
        node.transform = .identity
        node.updateStickyHeaderState(.none, animated: false)
        node.layer.removeAllAnimations()
        node.layer.zPosition = 0
        node.layer.shadowOpacity = 0
        node.isHidden = false

        guard let key else { return }
        var bucket = reusePool[key] ?? []
        if bucket.count < maxReusableNodesPerIdentifier {
            bucket.append(node)
            reusePool[key] = bucket
            debugInstrumentation.recordRecycledView()
        }
    }

    private func cancelAsyncLayout(for item: AetherListItem) {
        cancelAsyncLayout(forID: item.stableId)
    }

    private func cancelAsyncLayout(forID id: AnyHashable) {
        if let task = pendingLayoutTasks.removeValue(forKey: id) {
            task.cancel()
        }
    }

    private func prefetchAsyncLayouts(in range: Range<Int>, params: AetherListItemLayoutParams) {
        var executor = UIKitAsyncLayoutCommandExecutor(listView: self, params: params)
        for command in makeAsyncLayoutCommands(prefetchRange: range) {
            executor.execute(command)
        }
    }

    private func makeAsyncLayoutCommands(
        prefetchRange: Range<Int>
    ) -> [AetherListAsyncLayoutCommand<AnyHashable>] {
        AetherListAsyncLayoutCommandPlanner.commands(
            prefetchRange: prefetchRange,
            itemDescriptors: items.enumerated().map { index, item in
                let id = item.stableId
                return AetherListAsyncLayoutItemDescriptor(
                    index: index,
                    itemId: id,
                    reuseIdentifier: item.reuseIdentifier,
                    hasPreparedLayout: preparedLayoutCache[id] != nil,
                    hasPendingLayoutTask: pendingLayoutTasks[id] != nil,
                    isKnownSynchronous: synchronousLayoutIdentifiers.contains(item.reuseIdentifier)
                )
            }
        )
    }

    private func startAsyncLayoutPreparation(
        at index: Int,
        itemId: AnyHashable,
        params: AetherListItemLayoutParams
    ) {
        guard index >= 0, index < items.count else { return }
        let item = items[index]
        let id = item.stableId
        guard id == itemId,
              preparedLayoutCache[id] == nil,
              pendingLayoutTasks[id] == nil,
              !synchronousLayoutIdentifiers.contains(item.reuseIdentifier) else {
            return
        }

        let previous = index > 0 ? items[index - 1] : nil
        let next = index + 1 < items.count ? items[index + 1] : nil
        let requestedWidth = params.width
        let taskBox = AsyncLayoutTaskBox()
        let task = item.asyncLayout(params: params, previousItem: previous, nextItem: next) { [weak self, weak item] prepared in
            DispatchQueue.main.async {
                guard let self, let item else { return }
                let expectedTask = taskBox.task
                if let expectedTask {
                    guard self.pendingLayoutTasks[item.stableId] === expectedTask else {
                        return
                    }
                    self.pendingLayoutTasks.removeValue(forKey: item.stableId)
                } else {
                    self.pendingLayoutTasks.removeValue(forKey: item.stableId)
                }

                guard self.layoutParams?.width == requestedWidth,
                      self.items.contains(where: { $0 === item }) else {
                    return
                }
                self.preparedLayoutCache[item.stableId] = prepared
                self.recordLayout(prepared.layout, for: item)
                self.applyPreparedLayoutIfVisible(prepared, for: item)
            }
        }
        taskBox.task = task
        if let task {
            pendingLayoutTasks[id] = task
        } else {
            synchronousLayoutIdentifiers.insert(item.reuseIdentifier)
        }
    }

    private func applyPreparedLayoutIfVisible(_ prepared: AetherListPreparedItemLayout, for item: AetherListItem) {
        assertMainThread()
        guard reorderState == nil,
              let currentIndex = items.firstIndex(where: { $0 === item }),
              currentIndex < itemHeights.count else {
            return
        }

        itemHeights[currentIndex] = prepared.layout.totalHeight
        if let node = itemNodes.first(where: { node in
            guard let nodeItem = node.item else { return false }
            return nodeItem === item
        }) {
            prepared.apply(node)
            node.applyLayout(prepared.layout)
            syncAccessories(for: node, item: item)
        }
        rebuildOffsets()
        positionNodes()
        updateContentSize()
        applyStickyHeaderLayout()
        updateDebugOverlay()
    }

    private func assertNoDuplicateVisibleNodes() {
        #if DEBUG
        var indices = Set<Int>()
        var ids = Set<AnyHashable>()
        for node in itemNodes {
            if let index = node.index {
                assert(indices.insert(index).inserted, "Duplicate visible AetherListItemNode index \(index)")
            }
            if let item = node.item {
                assert(ids.insert(item.stableId).inserted, "Duplicate visible AetherListItem stableId \(item.stableId)")
            }
        }
        #endif
    }

    // MARK: - Private: Virtualization

    /// Compute the range of item indices that should be loaded.
    private func computeVisibleRange() -> Range<Int> {
        guard !items.isEmpty else { return 0..<0 }
        return AetherListFrameMetrics.visibleRange(
            offsets: itemOffsets,
            heights: itemHeights,
            viewportTop: scrollView.contentOffset.y,
            viewportHeight: bounds.height,
            preloadPages: preloadPages
        )
    }

    private func makeVirtualizationLoadedNodes() -> [AetherListVirtualizationLoadedNode<ObjectIdentifier>] {
        itemNodes.map { node in
            AetherListVirtualizationLoadedNode(
                nodeId: ObjectIdentifier(node),
                index: node.index,
                isProtected: reorderState?.draggingNode === node
            )
        }
    }

    private func makeVirtualizationCommands(
        visibleRange: Range<Int>,
        pinnedIndices: Set<Int>
    ) -> [AetherListVirtualizationCommand<ObjectIdentifier>] {
        AetherListVirtualizationCommandPlanner.commands(
            visibleRange: visibleRange,
            pinnedIndices: pinnedIndices,
            loadedNodes: makeVirtualizationLoadedNodes(),
            itemOffsets: itemOffsets,
            itemHeights: itemHeights,
            boundsWidth: bounds.width,
            displayScale: window?.screen.scale ?? UIScreen.main.scale
        )
    }

    /// Add/remove nodes to match the visible range.
    private func updateVisibleNodes(isUserInitiated: Bool = false) {
        guard !items.isEmpty, let params = layoutParams else { return }

        let visibleRange = computeVisibleRange()
        // Keep currently-pinned floating headers alive even when
        // their indices fall outside the regular preload range.
        let pinnedIndices = currentStickyHeaderIndices()

        var executor = UIKitVirtualizationCommandExecutor(listView: self, params: params)
        for command in makeVirtualizationCommands(visibleRange: visibleRange, pinnedIndices: pinnedIndices) {
            switch command {
            case .recycle, .mount:
                executor.execute(command)
            case .setFrame:
                break
            }
        }

        if executor.didMutateNodes {
            itemNodes.sort { ($0.index ?? 0) < ($1.index ?? 0) }
        }
        
        if executor.didChangeHeights {
            rebuildOffsets()
            positionNodes()
            updateContentSize()
        } else {
            for command in makeVirtualizationCommands(visibleRange: visibleRange, pinnedIndices: pinnedIndices) {
                if case .setFrame = command {
                    executor.execute(command)
                }
            }
        }

        applyStickyHeaderLayout()
        prefetchAsyncLayouts(in: visibleRange, params: params)
        assertNoDuplicateVisibleNodes()
        applyVisibilityLifecycle(isUserInitiated: isUserInitiated)
    }

    // MARK: - Private: Scroll Calculations

    private func computeScrollOffset(for index: Int, position: AetherListScrollPosition) -> CGFloat {
        guard index < itemOffsets.count else { return 0 }
        let nodeInsets = itemNodes.first(where: { $0.index == index })?.scrollPositioningInsets ?? .zero
        let customOverflow: CGFloat?
        if case .centerWithOverflow(.custom(let getOverflow)) = position,
           let node = itemNodes.first(where: { $0.index == index }) {
            customOverflow = getOverflow(node)
        } else {
            customOverflow = nil
        }
        return AetherListFrameMetrics.scrollOffset(
            index: index,
            position: position,
            offsets: itemOffsets,
            heights: itemHeights,
            nodeInsets: nodeInsets,
            viewportHeight: bounds.height,
            insets: insets,
            currentOffset: scrollView.contentOffset.y,
            customOverflow: customOverflow
        )
    }

    private func makeVisibilityNodeDescriptors() -> [AetherListVisibilityNodeDescriptor<ObjectIdentifier>] {
        itemNodes.map { node in
            AetherListVisibilityNodeDescriptor(
                nodeId: ObjectIdentifier(node),
                index: node.index,
                frame: node.frame,
                isAccessibilityVisible: node.superview != nil && !node.isHidden && node.alpha > 0.01
            )
        }
    }

    private func makeVisibilitySnapshot() -> AetherListVisibilitySnapshot<ObjectIdentifier> {
        guard !items.isEmpty else {
            return AetherListVisibilitySnapshot(
                displayedRange: AetherListDisplayedItemRange(loadedRange: nil, visibleRange: nil),
                accessibilityNodeIds: [],
                loadedViewCount: 0
            )
        }
        return AetherListVisibilityLifecycleCommandPlanner.snapshot(
            nodeDescriptors: makeVisibilityNodeDescriptors(),
            viewportTop: scrollView.contentOffset.y,
            viewportHeight: bounds.height
        )
    }

    @discardableResult
    private func applyVisibilityLifecycle(
        notifyDisplayedRangeChanged: Bool = true,
        isUserInitiated: Bool = false
    ) -> AetherListDisplayedItemRange {
        let snapshot = makeVisibilitySnapshot()
        let executor = UIKitVisibilityLifecycleCommandExecutor(listView: self)
        for command in AetherListVisibilityLifecycleCommandPlanner.commands(
            snapshot: snapshot,
            notifyDisplayedRange: notifyDisplayedRangeChanged
        ) {
            executor.execute(command)
        }
        updateDebugOverlay()
        evaluateBoundaryTriggers(displayedRange: snapshot.displayedRange, isUserInitiated: isUserInitiated)
        return snapshot.displayedRange
    }

    private func evaluateBoundaryTriggers(
        displayedRange: AetherListDisplayedItemRange,
        isUserInitiated: Bool
    ) {
        guard let configuration = boundaryTriggerConfiguration,
              let boundaryReached else {
            return
        }
        let snapshot = AetherListBoundaryTriggerSnapshot(
            itemCount: items.count,
            displayedRange: displayedRange,
            visibleContentOffset: visibleContentOffset(),
            visibleBottomContentOffset: visibleBottomContentOffset(),
            isUserInitiated: isUserInitiated
        )
        let triggers = AetherListBoundaryTriggerPlanner.triggers(
            snapshot: snapshot,
            configuration: configuration
        )
        let activeEdges = Set(triggers.map(\.edge))
        for edge in [AetherListBoundaryEdge.top, .bottom] where !activeEdges.contains(edge) {
            boundaryTriggerSignatures.removeValue(forKey: edge)
        }

        for trigger in triggers {
            let signature = BoundaryTriggerSignature(
                itemCount: items.count,
                loadedLowerBound: displayedRange.loadedRange?.lowerBound,
                loadedUpperBound: displayedRange.loadedRange?.upperBound,
                visibleLowerBound: displayedRange.visibleRange?.lowerBound,
                visibleUpperBound: displayedRange.visibleRange?.upperBound
            )
            guard boundaryTriggerSignatures[trigger.edge] != signature else {
                continue
            }
            boundaryTriggerSignatures[trigger.edge] = signature
            boundaryReached(AetherListBoundaryTriggerContext(
                edge: trigger.edge,
                reasons: trigger.reasons,
                displayedRange: displayedRange,
                visibleContentOffset: snapshot.visibleContentOffset,
                visibleBottomContentOffset: snapshot.visibleBottomContentOffset,
                contentSize: scrollView.contentSize,
                visibleSize: visibleSize,
                isUserInitiated: isUserInitiated
            ))
        }
    }

    private func computeDisplayedRange() -> AetherListDisplayedItemRange {
        makeVisibilitySnapshot().displayedRange
    }

    // MARK: - Sticky headers

    private func stickyHeaderAffinity(for item: AetherListItem) -> AetherListHeaderAffinity {
        let affinity = item.headerAffinity
        if affinity != .none {
            return affinity
        }
        return item.isFloatingHeader ? .top : .none
    }

    private func stickyHeaderViewportEdges() -> (top: CGFloat, bottom: CGFloat) {
        let edgeInsets = headerInsets ?? insets
        return (
            top: scrollView.contentOffset.y + edgeInsets.top,
            bottom: scrollView.contentOffset.y + bounds.height - edgeInsets.bottom
        )
    }

    private func makeStickyHeaderDescriptors() -> [AetherListStickyHeaderDescriptor<ObjectIdentifier>] {
        guard !items.isEmpty, !itemOffsets.isEmpty else { return [] }

        var nodeIdByIndex: [Int: ObjectIdentifier] = [:]
        for node in itemNodes {
            if let index = node.index {
                nodeIdByIndex[index] = ObjectIdentifier(node)
            }
        }

        var descriptors: [AetherListStickyHeaderDescriptor<ObjectIdentifier>] = []
        descriptors.reserveCapacity(items.count)
        for (index, item) in items.enumerated() {
            let affinity = stickyHeaderAffinity(for: item)
            guard affinity != .none,
                  index < itemOffsets.count,
                  index < itemHeights.count else {
                continue
            }
            descriptors.append(AetherListStickyHeaderDescriptor(
                index: index,
                affinity: affinity,
                naturalY: itemOffsets[index],
                height: itemHeights[index],
                nodeId: nodeIdByIndex[index]
            ))
        }
        return descriptors
    }

    private func makeStickyHeaderCommands() -> [AetherListStickyHeaderCommand<ObjectIdentifier>] {
        let viewport = stickyHeaderViewportEdges()
        return AetherListStickyHeaderCommandPlanner.commands(
            descriptors: makeStickyHeaderDescriptors(),
            viewportTop: viewport.top,
            viewportBottom: viewport.bottom,
            boundsWidth: bounds.width,
            displayScale: window?.screen.scale ?? UIScreen.main.scale
        )
    }

    private func currentStickyHeaderIndices() -> Set<Int> {
        let viewport = stickyHeaderViewportEdges()
        return AetherListStickyHeaderCommandPlanner.pinnedIndices(
            descriptors: makeStickyHeaderDescriptors(),
            viewportTop: viewport.top,
            viewportBottom: viewport.bottom
        )
    }

    /// Reposition every floating-header node in line with the current
    /// scroll offset. Top headers keep the UITableView-like push-up
    /// behaviour; bottom-affinity headers pin to the bottom edge until their
    /// natural slot enters the viewport.
    private func applyStickyHeaderLayout() {
        guard !items.isEmpty, !itemOffsets.isEmpty else { return }

        let params = layoutParams ?? AetherListItemLayoutParams(width: bounds.width)
        var executor = UIKitStickyHeaderCommandExecutor(listView: self, params: params)
        for command in makeStickyHeaderCommands() {
            guard case .ensureNode = command else { continue }
            executor.execute(command)
        }

        if executor.didMountNodes {
            itemNodes.sort { ($0.index ?? 0) < ($1.index ?? 0) }
        }
        if executor.didChangeHeights {
            rebuildOffsets()
            updateContentSize()
        }

        for command in makeStickyHeaderCommands() {
            guard case .applyLayout = command else { continue }
            executor.execute(command)
        }
    }

    // MARK: - Debug / indicators / overscroll

    private func syncDebugOverlay() {
        let shouldShow = debugInfo || showsDebugOverlay
        if shouldShow {
            if debugOverlayLabel == nil {
                let label = UILabel()
                label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
                label.textColor = .white
                label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
                label.numberOfLines = 0
                label.layer.cornerRadius = 6
                label.layer.masksToBounds = true
                label.isUserInteractionEnabled = false
                addSubview(label)
                debugOverlayLabel = label
            }
            updateDebugOverlay()
            layoutDebugOverlay()
        } else {
            debugOverlayLabel?.removeFromSuperview()
            debugOverlayLabel = nil
        }
    }

    private func layoutDebugOverlay() {
        guard let label = debugOverlayLabel else { return }
        let width = min(bounds.width - 16, 280)
        label.frame = CGRect(x: 8, y: max(8, safeAreaInsets.top + 8), width: width, height: 86)
        bringSubviewToFront(label)
    }

    private func updateDebugOverlay() {
        guard let label = debugOverlayLabel else { return }
        let displayed = computeDisplayedRange()
        let counters = debugInstrumentation.counters
        let loaded = displayed.loadedRange.map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "nil"
        let visible = displayed.visibleRange.map { "\($0.lowerBound)..<\($0.upperBound)" } ?? "nil"
        let text = """
        visible \(visible) loaded \(loaded)
        views \(itemNodes.count) created \(counters.createdViews) reused \(counters.reusedViews)
        cache \(layoutCache.count) hits \(counters.layoutCacheHits) misses \(counters.layoutCacheMisses)
        tx \(counters.transactionCount) last \(String(format: "%.2f", counters.lastTransactionDuration * 1000))ms
        """
        label.text = "  " + text.replacingOccurrences(of: "\n", with: "\n  ")
    }

    private func syncCustomScrollIndicator() {
        if usesCustomScrollIndicator {
            scrollView.showsVerticalScrollIndicator = false
            if customScrollIndicatorView == nil {
                let view = UIView()
                view.backgroundColor = UIColor.label.withAlphaComponent(0.42)
                view.layer.cornerRadius = 1.5
                view.alpha = 0
                view.isUserInteractionEnabled = false
                addSubview(view)
                customScrollIndicatorView = view
            }
            updateCustomScrollIndicator()
        } else {
            scrollView.showsVerticalScrollIndicator = true
            customScrollIndicatorFadeWorkItem?.cancel()
            customScrollIndicatorFadeWorkItem = nil
            customScrollIndicatorView?.removeFromSuperview()
            customScrollIndicatorView = nil
        }
    }

    private func updateCustomScrollIndicator() {
        guard usesCustomScrollIndicator, let indicator = customScrollIndicatorView else { return }
        guard let frame = AetherListFrameMetrics.verticalScrollIndicatorFrame(
            boundsWidth: bounds.width,
            viewportHeight: bounds.height,
            contentSizeHeight: scrollView.contentSize.height,
            contentInset: scrollView.contentInset,
            scrollIndicatorInsets: scrollIndicatorInsets,
            contentOffsetY: scrollView.contentOffset.y,
            followsOverscroll: customScrollIndicatorFollowsOverscroll
        ) else {
            indicator.isHidden = true
            return
        }
        indicator.isHidden = false
        indicator.frame = alignedFrame(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
        bringSubviewToFront(indicator)
    }

    private func flashCustomScrollIndicator() {
        guard usesCustomScrollIndicator, let indicator = customScrollIndicatorView, !indicator.isHidden else { return }
        updateCustomScrollIndicator()
        customScrollIndicatorFadeWorkItem?.cancel()
        indicator.alpha = 1
        let workItem = DispatchWorkItem { [weak indicator] in
            UIView.animate(withDuration: 0.25) {
                indicator?.alpha = 0
            }
        }
        customScrollIndicatorFadeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func updateOverscrollState() {
        let overscroll = AetherListFrameMetrics.overscrollDistances(
            contentOffsetY: scrollView.contentOffset.y,
            contentSizeHeight: scrollView.contentSize.height,
            viewportHeight: bounds.height,
            contentInset: scrollView.contentInset
        )
        topOverscrollChanged?(overscroll.top)
        bottomOverscrollChanged?(overscroll.bottom)

        topOverscrollBackgroundView?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: overscroll.top)
        bottomOverscrollBackgroundView?.frame = CGRect(
            x: 0,
            y: bounds.height - overscroll.bottom,
            width: bounds.width,
            height: overscroll.bottom
        )
    }

    // MARK: - UIGestureRecognizerDelegate

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let gesture = listItemGesture(for: gestureRecognizer) else {
            return true
        }
        let point = touch.location(in: scrollView.backingView)
        return canReceiveListItemGesture(gesture, at: point, consultExternalGate: false)
    }

    open override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let gesture = listItemGesture(for: gestureRecognizer) else {
            return true
        }
        let point = gestureRecognizer.location(in: scrollView.backingView)
        return canReceiveListItemGesture(gesture, at: point, consultExternalGate: true)
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard let tapRecognizer else { return false }
        return gestureRecognizer === tapRecognizer || otherGestureRecognizer === tapRecognizer
    }

    private func listItemGesture(for recognizer: UIGestureRecognizer) -> AetherListItemGesture? {
        if let tapRecognizer, recognizer === tapRecognizer {
            return .tap
        }
        if let reorderRecognizer, recognizer === reorderRecognizer {
            return .reorder
        }
        return nil
    }

    private func canReceiveListItemGesture(
        _ gesture: AetherListItemGesture,
        at point: CGPoint,
        consultExternalGate: Bool
    ) -> Bool {
        if itemNodeForListGesture(at: point, gesture: gesture, consultExternalGate: consultExternalGate) != nil {
            return true
        }

        switch gesture {
        case .tap:
            return !limitsListGestureHitTestingToVisibleItemNodes
        case .reorder:
            return false
        }
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        assertMainThread()
        syncBackingViewBounds()
        let currentOffsetY = scrollView.contentOffset.y
        let deltaY = currentOffsetY - (previousDidScrollContentOffsetY ?? currentOffsetY)
        previousDidScrollContentOffsetY = currentOffsetY
        let isUserInitiated = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        updateVisibleNodes(isUserInitiated: isUserInitiated)
        applyStickyHeaderLayout()
        updateOverscrollState()
        flashCustomScrollIndicator()
        updateDebugOverlay()
        visibleContentOffsetChanged?(scrollView.contentOffset.y + scrollView.contentInset.top)
        didScrollWithOffset?(deltaY, .immediate, nil, isUserInitiated)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        beganInteractiveDragging?()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            didEndScrolling?()
        }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        didEndScrolling?()
    }

    // MARK: - Accessibility

    open override var accessibilityElements: [Any]? {
        get {
            let order = accessibilityNodeOrder.isEmpty && !itemNodes.isEmpty
                ? makeVisibilitySnapshot().accessibilityNodeIds
                : accessibilityNodeOrder
            let nodesById = Dictionary(uniqueKeysWithValues: itemNodes.map { (ObjectIdentifier($0), $0) })
            return order.compactMap { nodeId in
                guard let node = nodesById[nodeId],
                      node.superview != nil,
                      !node.isHidden,
                      node.alpha > 0.01 else {
                    return nil
                }
                return node
            }
        }
        set {
            // The list owns traversal order so invisible/recycled nodes never
            // leak into VoiceOver.
        }
    }

    open override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let page = max(1, bounds.height - scrollView.contentInset.top - scrollView.contentInset.bottom)
        var target = scrollView.contentOffset.y
        switch direction {
        case .up:
            target -= page
        case .down:
            target += page
        case .left, .right, .next, .previous:
            return false
        @unknown default:
            return false
        }

        let minY = -scrollView.contentInset.top
        let maxY = max(minY, scrollView.contentSize.height + scrollView.contentInset.bottom - bounds.height)
        target = min(maxY, max(minY, target))
        guard abs(target - scrollView.contentOffset.y) > 0.5 else { return false }
        let animated = !UIAccessibility.isReduceMotionEnabled
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: target), animated: animated)
        if !animated {
            syncBackingViewBounds()
        }
        UIAccessibility.post(notification: .pageScrolled, argument: nil)
        return true
    }

    // MARK: - Tap Handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: scrollView.backingView)
        guard let node = itemNodeForListGesture(at: point, gesture: .tap),
              let index = node.index,
              index >= 0,
              index < items.count else {
            return
        }

        node.tapped()
        guard items[index].selectable else { return }

        // Selection toggle (when active) runs alongside the
        // legacy `item.selected(listView:)` callback so existing
        // call sites that don't opt into selection keep working.
        switch selectionMode {
        case .none:
            break
        case .single:
            let id = ObjectIdentifier(items[index])
            if selectedItemIds == [id] {
                // Re-tapping the only selected row is a no-op
                // — single-select callers usually want stable
                // state on repeated taps.
            } else {
                selectedItemIds = [id]
                syncSelectionToNodes(animated: true)
                notifySelectionChanged()
            }
        case .multiple:
            let id = ObjectIdentifier(items[index])
            if selectedItemIds.contains(id) {
                selectedItemIds.remove(id)
            } else {
                selectedItemIds.insert(id)
            }
            syncSelectionToNodes(animated: true)
            notifySelectionChanged()
        }

        items[index].selected(listView: self)
        itemTapped?(index)
    }
}

private extension AetherListNodeFrameReplayCurve {
    var uiViewAnimationOptions: UIView.AnimationOptions {
        switch self {
        case .standard:
            return [.beginFromCurrentState, .allowUserInteraction]
        case .easeOut:
            return [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        }
    }
}
