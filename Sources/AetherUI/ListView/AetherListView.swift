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
open class AetherListView: UIView, UIScrollViewDelegate {

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
        didSet {
            rebuildOffsets()
            positionNodes()
            updateContentSize()
            applyStickyHeaderLayout()
        }
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
        var effective = insets
        effective.bottom += keyboardBottomInset
        if stackFromBottom {
            // Pad the top so the (small) content visually sits at the
            // bottom of the viewport. When content is taller than the
            // viewport this adds zero — normal scroll resumes.
            let viewportHeight = scrollView.bounds.height
            let availableHeight = viewportHeight - effective.top - effective.bottom
            let topPadding = max(0, availableHeight - totalContentHeight)
            effective.top += topPadding
        }
        // Drive the inset change through the transition helper so
        // it compensates `contentOffset` by the delta — that's what
        // keeps the visual top of the content pinned where the
        // caller positioned it (under their navbar etc.) instead of
        // sliding under the new chrome.
        transition.updateContentInset(scrollView: scrollView, insets: effective)
        transition.updateScrollIndicatorInsets(scrollView: scrollView, insets: scrollIndicatorInsets ?? effective)
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

    /// Scroll to the last row's bottom edge.
    public func scrollToBottom(animated: Bool) {
        let bottomY = max(
            -scrollView.contentInset.top,
            scrollView.contentSize.height + scrollView.contentInset.bottom - scrollView.bounds.height
        )
        scrollView.setContentOffset(CGPoint(x: 0, y: bottomY), animated: animated)
    }

    /// Scroll to the very top.
    public func scrollToTop(animated: Bool) {
        let topY = -scrollView.contentInset.top
        scrollView.setContentOffset(CGPoint(x: 0, y: topY), animated: animated)
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

    /// Telegram-compatible scroll delta callback.
    public var didScrollWithOffset: ((CGFloat, ContainedViewLayoutTransition, AetherListItemNode?, Bool) -> Void)?

    /// Called when the user begins dragging.
    public var beganInteractiveDragging: (() -> Void)?

    /// Called when scrolling finishes (deceleration ended or drag ended without deceleration).
    public var didEndScrolling: (() -> Void)?

    /// Called when an item is tapped.
    public var itemTapped: ((Int) -> Void)?

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

    /// Fires once the drag completes if the item moved. The list
    /// view has already reshuffled its internal `items` and animated
    /// the node positions by the time this fires; the callback is
    /// for the data source to mirror the change.
    public var didMoveItem: ((_ from: Int, _ to: Int) -> Void)?

    private weak var reorderRecognizer: UILongPressGestureRecognizer?
    private var reorderState: ReorderState?

    private struct ReorderState {
        let originalIndex: Int
        var currentIndex: Int
        let touchOffsetY: CGFloat
        let draggingNode: AetherListItemNode
    }

    private func setupReorderRecognizer() {
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleReorderGesture(_:)))
        lp.minimumPressDuration = 0.4
        lp.cancelsTouchesInView = false
        lp.isEnabled = allowsReorder
        scrollView.addGestureRecognizer(lp)
        reorderRecognizer = lp
    }

    @objc private func handleReorderGesture(_ gr: UILongPressGestureRecognizer) {
        let location = gr.location(in: scrollView)

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
        guard let node = itemNodes.first(where: { $0.frame.contains(location) }),
              let index = node.index, index < items.count,
              items[index].canReorder else {
            return
        }

        let touchOffsetY = location.y - node.frame.minY
        // Lift effect: small scale + soft shadow + above-everything z.
        node.layer.zPosition = 2000
        node.layer.shadowColor = UIColor.black.cgColor
        node.layer.shadowOffset = CGSize(width: 0, height: 6)
        node.layer.shadowRadius = 12
        node.layer.masksToBounds = false
        scrollView.bringSubviewToFront(node)

        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState]) {
            node.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
            node.layer.shadowOpacity = 0.18
        }

        reorderState = ReorderState(
            originalIndex: index,
            currentIndex: index,
            touchOffsetY: touchOffsetY,
            draggingNode: node
        )
    }

    private func reorderChanged(to location: CGPoint) {
        guard var state = reorderState else { return }

        // Drag node tracks the finger directly — clamp to scroll
        // content so it doesn't disappear off the top/bottom.
        let dragHeight = state.draggingNode.frame.height
        let minY: CGFloat = 0
        let maxY: CGFloat = max(0, scrollView.contentSize.height - dragHeight)
        let targetY = max(minY, min(maxY, location.y - state.touchOffsetY))
        var f = state.draggingNode.frame
        f.origin.y = targetY
        state.draggingNode.frame = f

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

        // Re-derive node.index for everything by item identity, then
        // animate the non-dragging nodes to their new slots.
        var idMap: [ObjectIdentifier: Int] = [:]
        for (i, it) in items.enumerated() {
            idMap[ObjectIdentifier(it)] = i
        }
        for n in itemNodes {
            if let it = n.item, let newIdx = idMap[ObjectIdentifier(it)] {
                n.index = newIdx
            }
        }

        UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            for n in self.itemNodes where n !== state.draggingNode {
                guard let i = n.index, i < self.itemOffsets.count else { continue }
                var nf = n.frame
                nf.origin.y = self.itemOffsets[i]
                n.frame = nf
            }
        }

        state.currentIndex = proposedIndex
        reorderState = state
    }

    private func reorderEnded() {
        guard let state = reorderState else { return }
        let node = state.draggingNode
        let finalY: CGFloat
        if state.currentIndex < itemOffsets.count {
            finalY = itemOffsets[state.currentIndex]
        } else {
            finalY = node.frame.minY
        }

        UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState]) {
            node.transform = .identity
            node.layer.shadowOpacity = 0
            var f = node.frame
            f.origin.y = finalY
            node.frame = f
        } completion: { _ in
            node.layer.zPosition = 0
        }

        if state.originalIndex != state.currentIndex {
            didMoveItem?(state.originalIndex, state.currentIndex)
        }

        reorderState = nil
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

    private let scrollView = UIScrollView()
    private var previousDidScrollContentOffsetY: CGFloat?

    /// All item models in order.
    private var items: [AetherListItem] = []

    /// Currently loaded nodes, sorted by index. Not all items have nodes —
    /// only those within the visible + preload range.
    private var itemNodes: [AetherListItemNode] = []

    /// Cached heights for each item (index → totalHeight).
    private var itemHeights: [CGFloat] = []

    /// Cumulative Y offsets for each item (index → top Y of item).
    private var itemOffsets: [CGFloat] = []

    /// Total content height.
    private var totalContentHeight: CGFloat = 0

    /// Current layout params.
    private var layoutParams: AetherListItemLayoutParams?

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
        // The dust overlay may live in a host outside the list view
        // (e.g. `view.window` set by a chat controller). Without
        // this teardown a finished or in-flight burst would keep
        // the overlay parented to the window after the list itself
        // is gone — visually a stranded ghost effect on the next
        // screen.
        dustEffectView?.removeFromSuperview()
        dustEffectView = nil
    }

    private func setup() {
        scrollView.delegate = self
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.scrollsToTop = true
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
        scrollView.addGestureRecognizer(tapGesture)

        setupReorderRecognizer()
        // Tap should only fire if the long-press doesn't pick up
        // first — without this gating a successful drag also fires
        // the row tap on release.
        if let lp = reorderRecognizer {
            tapGesture.require(toFail: lp)
        }
    }

    // MARK: - Layout

    override open func layoutSubviews() {
        super.layoutSubviews()

        let boundsChanged = scrollView.frame.size != bounds.size
        scrollView.frame = bounds
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

        if isProcessingTransaction && !options.contains(.synchronous) && !options.contains(.lowLatency) {
            pendingTransactions.append(work)
        } else {
            work()
        }
    }

    /// Scroll to an item at the given index.
    public func scrollToItem(at index: Int, position: AetherListScrollPosition, animated: Bool) {
        guard index >= 0 && index < items.count else { return }
        let targetY = computeScrollOffset(for: index, position: position)
        scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
    }

    /// Stop any ongoing scrolling animation.
    public func stopScrolling() {
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
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
    }

    public func resetScrolledToItem() {
        scrollView.layer.removeAllAnimations()
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
        return true
    }

    // MARK: - Private: Transaction Execution

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
        if let updateOpaqueState {
            opaqueState = updateOpaqueState
        }

        // Snapshot whether the user is "at the bottom" BEFORE any
        // inserts grow the content size — needed for chat-style
        // auto-anchoring once the transaction settles.
        let wasNearBottom = stackFromBottom && isNearBottom(tolerance: stackFromBottomAutoAnchorTolerance)

        if let update = updateSizeAndInsets {
            let updateTransition: ContainedViewLayoutTransition = update.customTransition ?? (update.duration > .ulpOfOne
                ? .animated(duration: update.duration, curve: update.curve)
                : .immediate)
            if update.size.width > 0.0, update.size.height > 0.0, bounds.size != update.size {
                updateTransition.updateFrame(view: self, frame: CGRect(origin: frame.origin, size: update.size))
                layoutParams = AetherListItemLayoutParams(
                    width: update.size.width,
                    leftInset: safeAreaInsets.left,
                    rightInset: safeAreaInsets.right,
                    availableHeight: update.size.height
                )
            }
            headerInsets = update.headerInsets
            scrollIndicatorInsets = update.scrollIndicatorInsets
            itemOffsetInsets = update.itemOffsetInsets
            updateInsets(update.insets, transition: updateTransition)
        } else if options.contains(.forceUpdate), let params = layoutParams {
            relayoutAllNodes(params: params)
        }

        let animate = options.contains(.animateInsertions)
            || options.contains(.requestItemInsertionAnimations)
            || options.contains(.animateFullTransition)
            || insertIndicesAndItems.contains(where: { $0.forceAnimateInsertion })
        let animateAlpha = options.contains(.animateAlpha)
        func applyAdditionalScrollDistance(_ distance: CGFloat, animated: Bool) {
            guard !distance.isZero else { return }
            let targetOffset = CGPoint(
                x: scrollView.contentOffset.x,
                y: scrollView.contentOffset.y + distance
            )
            if let update = updateSizeAndInsets, update.duration > .ulpOfOne {
                ContainedViewLayoutTransition
                    .animated(duration: update.duration, curve: update.curve)
                    .animateView {
                        self.scrollView.contentOffset = targetOffset
                    }
            } else {
                scrollView.setContentOffset(targetOffset, animated: animated)
            }
        }

        // 1. Snapshot the geometry of every loaded node BEFORE the
        //    items array shifts. Used to drive the slide-into-the-gap
        //    animation: each surviving node animates from its old Y
        //    to whatever Y its (possibly different) index resolves to
        //    after the dust settles.
        var preFrames: [ObjectIdentifier: CGRect] = [:]
        var preNodesByIndex: [Int: AetherListItemNode] = [:]
        var preFramesByIndex: [Int: CGRect] = [:]
        for node in itemNodes {
            preFrames[ObjectIdentifier(node)] = node.frame
            if let index = node.index {
                preNodesByIndex[index] = node
                preFramesByIndex[index] = node.frame
            }
        }
        let stationaryItemIndex: Int? = stationaryItemRange.flatMap { range in
            let lower = min(range.0, range.1)
            let upper = max(range.0, range.1)
            return (lower...upper).first(where: { preFramesByIndex[$0] != nil })
        }

        // 2. Collect nodes about to disappear, then mutate the items
        //    array. Sorting deletes descending keeps lower indices
        //    valid as we go.
        var removingNodes: [(AetherListItemNode, AetherListItemDeleteAnimation, AetherListItemOperationDirectionHint?)] = []
        var consumedPreviousNodeIds = Set<ObjectIdentifier>()
        func takePreviousNode(previousIndex: Int, targetIndex: Int) -> AetherListItemNode? {
            guard let node = preNodesByIndex[previousIndex] else {
                return nil
            }
            let nodeId = ObjectIdentifier(node)
            guard !consumedPreviousNodeIds.contains(nodeId) else {
                return nil
            }
            consumedPreviousNodeIds.insert(nodeId)

            if let removingIndex = removingNodes.firstIndex(where: { $0.0 === node }) {
                removingNodes.remove(at: removingIndex)
            }
            if let duplicateIndex = itemNodes.firstIndex(where: { $0 !== node && $0.index == targetIndex }) {
                let duplicate = itemNodes.remove(at: duplicateIndex)
                duplicate.removeFromSuperview()
            }
            if !itemNodes.contains(where: { $0 === node }) {
                itemNodes.append(node)
            }
            if node.superview !== scrollView {
                scrollView.addSubview(node)
            }
            node.index = targetIndex
            return node
        }

        let sortedDeletes = deleteIndices.sorted { $0.index > $1.index }
        for delete in sortedDeletes {
            guard delete.index < items.count else { continue }
            if let nodeIdx = itemNodes.firstIndex(where: { $0.index == delete.index }) {
                let node = itemNodes[nodeIdx]
                removingNodes.append((node, delete.animation, delete.directionHint))
                itemNodes.remove(at: nodeIdx)
            }
            items.remove(at: delete.index)
            itemHeights.remove(at: delete.index)
        }

        // 3. Apply moves on the model. Each move is a remove + insert
        //    pair on the items array; node frames are reconciled later
        //    via the identity-based reindex pass.
        for move in moveIndices {
            guard move.fromIndex < items.count, move.toIndex <= items.count else { continue }
            let item = items.remove(at: move.fromIndex)
            let height = itemHeights.remove(at: move.fromIndex)
            let target = min(move.toIndex, items.count)
            items.insert(item, at: target)
            itemHeights.insert(height, at: target)
        }

        // 4. Apply inserts. Sorted ascending so earlier inserts don't
        //    shift the target indices of later ones in the same batch.
        let sortedInserts = insertIndicesAndItems.sorted { $0.index < $1.index }
        var insertPreviousIndexByTargetIndex: [Int: Int] = [:]
        var insertDirectionHintByTargetIndex: [Int: AetherListItemOperationDirectionHint] = [:]
        var forceAnimateInsertionIndices = Set<Int>()
        for insert in sortedInserts {
            let idx = min(insert.index, items.count)
            items.insert(insert.item, at: idx)
            itemHeights.insert(insert.item.approximateHeight, at: idx)
            if let previousIndex = insert.previousIndex {
                insertPreviousIndexByTargetIndex[idx] = previousIndex
            }
            if let directionHint = insert.directionHint {
                insertDirectionHintByTargetIndex[idx] = directionHint
            }
            if insert.forceAnimateInsertion {
                forceAnimateInsertionIndices.insert(idx)
            }
        }

        // 5. Re-index every surviving node by object identity. Walking
        //    `node.item` against the new `items` array is the only
        //    reliable way to recover the post-transaction index — chains
        //    of delete/move/insert make any "previousIndex"-based scheme
        //    drift after the second mutation.
        var itemIdentityToIndex: [ObjectIdentifier: Int] = [:]
        itemIdentityToIndex.reserveCapacity(items.count)
        for (i, item) in items.enumerated() {
            itemIdentityToIndex[ObjectIdentifier(item)] = i
        }
        for node in itemNodes {
            if let item = node.item, let newIdx = itemIdentityToIndex[ObjectIdentifier(item)] {
                node.index = newIdx
            } else {
                node.index = nil
            }
        }

        // 6. Apply in-place updates. After re-indexing the lookup is
        //    by NEW index — `previousIndex` only exists to disambiguate
        //    when the caller passes a still-loaded node.
        let params = layoutParams ?? AetherListItemLayoutParams(width: bounds.width)
        for update in updateIndicesAndItems {
            guard update.index < items.count else { continue }
            items[update.index] = update.item
            itemIdentityToIndex[ObjectIdentifier(update.item)] = update.index

            let node = takePreviousNode(previousIndex: update.previousIndex, targetIndex: update.index)
                ?? itemNodes.first(where: { $0.index == update.index })
            if let node {
                let prevItem = update.index > 0 ? items[update.index - 1] : nil
                let nextItem = update.index + 1 < items.count ? items[update.index + 1] : nil
                let animation: AetherListItemUpdateAnimation
                if options.contains(.crossfade) {
                    animation = .crossfade
                } else if options.contains(.animateFullTransition) {
                    animation = .system(duration: animationDuration, transition: .animated(duration: animationDuration, curve: .easeInOut))
                } else {
                    animation = .none
                }
                let newLayout = update.item.updateNode(node, params: params, previousItem: prevItem, nextItem: nextItem, animation: animation)
                node.applyLayout(newLayout)
                node.index = update.index
                node.item = update.item
                itemHeights[update.index] = newLayout.totalHeight
            }
        }

        rebuildOffsets()

        // 7. Materialise nodes for any items that have entered the
        //    visible range as a result of the mutations.
        var insertedNodes: [AetherListItemNode] = []
        let visibleRange = computeVisibleRange()
        for i in visibleRange {
            if itemNodes.contains(where: { $0.index == i }) { continue }

            let item = items[i]
            let prevItem = i > 0 ? items[i - 1] : nil
            let nextItem = i + 1 < items.count ? items[i + 1] : nil
            let node: AetherListItemNode
            let layout: AetherListItemNodeLayout
            if let previousIndex = insertPreviousIndexByTargetIndex[i],
               let previousNode = takePreviousNode(previousIndex: previousIndex, targetIndex: i) {
                node = previousNode
                let animation: AetherListItemUpdateAnimation
                if options.contains(.crossfade) {
                    animation = .crossfade
                } else if options.contains(.animateFullTransition) {
                    animation = .system(duration: animationDuration, transition: .animated(duration: animationDuration, curve: .easeInOut))
                } else {
                    animation = .none
                }
                layout = item.updateNode(previousNode, params: params, previousItem: prevItem, nextItem: nextItem, animation: animation)
            } else {
                let created = item.createNode(params: params, previousItem: prevItem, nextItem: nextItem)
                node = created.0
                layout = created.1
                insertedNodes.append(node)
            }
            node.applyLayout(layout)
            node.index = i
            node.item = item
            if selectedItemIds.contains(ObjectIdentifier(item)) {
                node.isSelected = true
            }
            itemHeights[i] = layout.totalHeight
            if !itemNodes.contains(where: { $0 === node }) {
                itemNodes.append(node)
            }
            if node.superview !== scrollView {
                scrollView.addSubview(node)
            }
        }

        itemNodes.sort { ($0.index ?? 0) < ($1.index ?? 0) }

        rebuildOffsets()
        updateContentSize()

        // 8. Settle frames. New nodes go straight to their final spot;
        //    surviving nodes either snap (no animation) or animate from
        //    `preFrames[node]` to the freshly computed slot.
        //
        //    The neighbour slide-into-the-gap duration normally tracks
        //    `animationDuration` (~0.3s). When at least one delete is a
        //    particle dissolve, that 0.3s is *too short*: rows below would
        //    finish climbing into the freed slot in a third of a second
        //    while the particle wave is still mid-burst above their old
        //    position — the cloud ends up floating disconnected from any
        //    visible row. Stretch the slide to match the particle wave's
        //    full lifetime so the gap closes at the same pace the cloud
        //    dissipates: visually the row "becomes" the cloud and the
        //    rows below "absorb" the now-empty space in lockstep.
        let particleDissolveDuration = particleDissolveVisualDuration
        let hasParticleDissolve = removingNodes.contains { _, animation, _ in
            if case .particleDissolve = animation { return true }
            return false
        }
        let effectiveSlideDuration = hasParticleDissolve ? particleDissolveDuration : animationDuration
        // EaseOut so most of the gap-closing happens early (under the
        // densest part of the cloud) and the last few percent stretch out
        // — matching the easeOut applied to the dissolving node's alpha.
        let effectiveSlideOptions: UIView.AnimationOptions = hasParticleDissolve
            ? [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
            : [.beginFromCurrentState, .allowUserInteraction]

        if animate {
            for node in itemNodes {
                guard let index = node.index, index < itemOffsets.count else { continue }
                let targetFrame = CGRect(
                    x: 0,
                    y: itemOffsets[index],
                    width: bounds.width,
                    height: itemHeights[index]
                )
                let nodeId = ObjectIdentifier(node)
                if insertedNodes.contains(where: { $0 === node }) {
                    node.frame = targetFrame
                    if animateAlpha {
                        node.alpha = 0.0
                        UIView.animate(
                            withDuration: min(animationDuration, 0.1),
                            delay: 0,
                            options: [.beginFromCurrentState, .allowUserInteraction],
                            animations: { node.alpha = 1.0 },
                            completion: nil
                        )
                    } else {
                        let directionHint = insertDirectionHintByTargetIndex[index]
                        let forceAnimate = forceAnimateInsertionIndices.contains(index)
                            || options.contains(.requestItemInsertionAnimations)
                        if forceAnimate || animate {
                            node.animateInsertion(
                                duration: animationDuration,
                                directionHint: directionHint,
                                invertOffsetDirection: options.contains(.invertOffsetDirection)
                            )
                        }
                    }
                } else if let from = preFrames[nodeId], from != targetFrame {
                    node.frame = from
                    UIView.animate(
                        withDuration: effectiveSlideDuration,
                        delay: 0,
                        options: effectiveSlideOptions,
                        animations: { node.frame = targetFrame },
                        completion: nil
                    )
                } else {
                    node.frame = targetFrame
                }
            }
            for (node, animation, hint) in removingNodes {
                let resolvedAnimation: AetherListItemDeleteAnimation
                if animateAlpha {
                    if case .particleDissolve = animation {
                        resolvedAnimation = animation
                    } else {
                        resolvedAnimation = .fade
                    }
                } else {
                    resolvedAnimation = animation
                }
                runDeleteAnimation(resolvedAnimation, on: node, hint: hint) {
                    node.removeFromSuperview()
                }
            }
        } else {
            positionNodes()
            for (node, _, _) in removingNodes {
                node.removeFromSuperview()
            }
        }

        // 9. Re-pin floating headers (their indices may have shifted
        // through insert/delete/move).
        applyStickyHeaderLayout()

        // 10. Honour scroll-to + notify subscribers.
        if let scrollTo = scrollToItem {
            if scrollTo.index >= 0, scrollTo.index < items.count {
                let targetY = computeScrollOffset(for: scrollTo.index, position: scrollTo.position) + additionalScrollDistance
                scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: scrollTo.animated)
            }
        } else if !additionalScrollDistance.isZero {
            applyAdditionalScrollDistance(additionalScrollDistance, animated: animate)
        } else if let stationaryItemIndex,
                  let previousFrame = preFramesByIndex[stationaryItemIndex],
                  let node = itemNodes.first(where: { $0.index == stationaryItemIndex }) {
            let delta = node.frame.minY - previousFrame.minY
            if abs(delta) > CGFloat.ulpOfOne {
                let targetOffset = CGPoint(x: scrollView.contentOffset.x, y: scrollView.contentOffset.y + delta)
                scrollView.setContentOffset(targetOffset, animated: options.contains(.animateTopItemPosition) && animate)
            }
        } else if stackFromBottom && wasNearBottom {
            // Chat-style anchor: if the user was at the bottom, keep
            // them there after the transaction even when new items
            // pushed the content size up.
            applyEffectiveInsets()
            scrollToBottom(animated: animate)
        }

        let displayedRange = computeDisplayedRange()
        displayedItemRangeChanged?(displayedRange)
        completion?(displayedRange)

        isProcessingTransaction = false
        if let next = pendingTransactions.first {
            pendingTransactions.removeFirst()
            next()
        } else if !afterTransactionsCompleted.isEmpty {
            let callbacks = afterTransactionsCompleted
            afterTransactionsCompleted.removeAll()
            callbacks.forEach { $0() }
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

    /// Rebuild cumulative Y offsets from item heights.
    private func rebuildOffsets() {
        itemOffsets = []
        itemOffsets.reserveCapacity(items.count)
        let offsetInsets = itemOffsetInsets ?? .zero
        var y: CGFloat = offsetInsets.top
        for height in itemHeights {
            itemOffsets.append(y)
            y += height
        }
        totalContentHeight = y + offsetInsets.bottom
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
    }

    /// Position all loaded nodes at their correct Y offsets.
    private func positionNodes() {
        for node in itemNodes {
            guard let index = node.index, index < itemOffsets.count else { continue }
            let y = itemOffsets[index]
            node.frame = CGRect(x: 0, y: y, width: bounds.width, height: itemHeights[index])
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
            let newLayout = item.updateNode(node, params: params, previousItem: prevItem, nextItem: nextItem, animation: .none)
            node.applyLayout(newLayout)
            itemHeights[index] = newLayout.totalHeight
        }
        rebuildOffsets()
        positionNodes()
        updateContentSize()
    }

    // MARK: - Private: Virtualization

    /// Compute the range of item indices that should be loaded.
    private func computeVisibleRange() -> Range<Int> {
        guard !items.isEmpty else { return 0..<0 }

        let viewportTop = scrollView.contentOffset.y - preloadPages * bounds.height
        let viewportBottom = scrollView.contentOffset.y + bounds.height + preloadPages * bounds.height

        var firstVisible = 0
        var lastVisible = items.count - 1

        // Binary search for first visible item
        var lo = 0, hi = items.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let itemBottom = itemOffsets[mid] + itemHeights[mid]
            if itemBottom < viewportTop {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        firstVisible = max(0, lo)

        // Binary search for last visible item
        lo = firstVisible
        hi = items.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let itemTop = itemOffsets[mid]
            if itemTop > viewportBottom {
                hi = mid - 1
            } else {
                lo = mid + 1
            }
        }
        lastVisible = min(items.count - 1, hi)

        return firstVisible ..< (lastVisible + 1)
    }

    /// Add/remove nodes to match the visible range.
    private func updateVisibleNodes() {
        guard !items.isEmpty, let params = layoutParams else { return }

        let visibleRange = computeVisibleRange()
        // Keep the currently-pinned floating header alive even when
        // its index falls outside the regular preload range — this
        // is what lets the header stay welded to the top while the
        // user scrolls far below it.
        let pinnedIndex = currentStickyHeaderIndex()

        // Remove nodes outside visible range
        var i = 0
        while i < itemNodes.count {
            if let index = itemNodes[i].index,
               !visibleRange.contains(index),
               index != pinnedIndex {
                itemNodes[i].removeFromSuperview()
                itemNodes.remove(at: i)
            } else {
                i += 1
            }
        }

        // Add nodes for newly visible items
        var didUpdateHeights = false
        for idx in visibleRange {
            if itemNodes.contains(where: { $0.index == idx }) { continue }

            let item = items[idx]
            let prevItem = idx > 0 ? items[idx - 1] : nil
            let nextItem = idx + 1 < items.count ? items[idx + 1] : nil
            let (node, layout) = item.createNode(params: params, previousItem: prevItem, nextItem: nextItem)
            node.applyLayout(layout)
            node.index = idx
            node.item = item
            if selectedItemIds.contains(ObjectIdentifier(item)) {
                node.isSelected = true
            }
            if abs(itemHeights[idx] - layout.totalHeight) > 0.5 {
                itemHeights[idx] = layout.totalHeight
                didUpdateHeights = true
            }
            itemNodes.append(node)
            scrollView.addSubview(node)
        }

        itemNodes.sort { ($0.index ?? 0) < ($1.index ?? 0) }
        
        if didUpdateHeights {
            rebuildOffsets()
            positionNodes()
            updateContentSize()
        } else {
            for node in itemNodes {
                guard let index = node.index, index < itemOffsets.count else { continue }
                let y = itemOffsets[index]
                node.frame = CGRect(x: 0, y: y, width: bounds.width, height: itemHeights[index])
            }
        }

        applyStickyHeaderLayout()

        // Update displayed range
        let displayedRange = computeDisplayedRange()
        displayedItemRangeChanged?(displayedRange)
    }

    // MARK: - Private: Scroll Calculations

    private func computeScrollOffset(for index: Int, position: AetherListScrollPosition) -> CGFloat {
        guard index < itemOffsets.count else { return 0 }
        let nodeInsets = itemNodes.first(where: { $0.index == index })?.scrollPositioningInsets ?? .zero
        let itemTop = itemOffsets[index] + nodeInsets.top
        let itemHeight = max(0.0, itemHeights[index] - nodeInsets.top - nodeInsets.bottom)
        let itemBottom = itemTop + itemHeight
        let effectiveTopInset = insets.top
        let effectiveBottomInset = insets.bottom

        switch position {
        case .visible:
            let currentTop = scrollView.contentOffset.y
            let currentBottom = currentTop + bounds.height
            if itemTop >= currentTop && itemBottom <= currentBottom {
                return scrollView.contentOffset.y // already visible
            }
            if itemTop < currentTop {
                return itemTop - effectiveTopInset
            }
            return itemBottom - bounds.height + effectiveBottomInset

        case .top(let offset):
            return itemTop - effectiveTopInset - offset

        case .bottom(let offset):
            return itemBottom - bounds.height + effectiveBottomInset + offset

        case .center:
            return itemTop + itemHeight / 2 - bounds.height / 2

        case .centerWithOverflow(let overflow):
            let contentAreaHeight = bounds.height - effectiveTopInset - effectiveBottomInset
            if itemHeight <= contentAreaHeight + CGFloat.ulpOfOne {
                return itemTop + itemHeight / 2 - bounds.height / 2
            }
            switch overflow {
            case .top:
                return itemTop - effectiveTopInset
            case .bottom:
                return itemBottom - bounds.height + effectiveBottomInset
            case .custom(let getOverflow):
                if let node = itemNodes.first(where: { $0.index == index }) {
                    return itemBottom - bounds.height + effectiveBottomInset + getOverflow(node)
                }
                return itemTop - effectiveTopInset
            }
        }
    }

    private func computeDisplayedRange() -> AetherListDisplayedItemRange {
        guard !items.isEmpty else {
            return AetherListDisplayedItemRange(loadedRange: nil, visibleRange: nil)
        }

        let loadedIndices = itemNodes.compactMap { $0.index }
        let loadedRange: Range<Int>?
        if let first = loadedIndices.min(), let last = loadedIndices.max() {
            loadedRange = first ..< (last + 1)
        } else {
            loadedRange = nil
        }

        let viewportTop = scrollView.contentOffset.y
        let viewportBottom = viewportTop + bounds.height
        var visibleFirst: Int?
        var visibleLast: Int?
        var firstFullyVisible = false

        for node in itemNodes {
            guard let index = node.index else { continue }
            let nodeTop = node.frame.minY
            let nodeBottom = node.frame.maxY
            if nodeBottom > viewportTop && nodeTop < viewportBottom {
                if visibleFirst == nil {
                    visibleFirst = index
                    firstFullyVisible = nodeTop >= viewportTop && nodeBottom <= viewportBottom
                }
                visibleLast = index
            }
        }

        let visibleRange: Range<Int>?
        if let first = visibleFirst, let last = visibleLast {
            visibleRange = first ..< (last + 1)
        } else {
            visibleRange = nil
        }

        let visibleItemRange: AetherListVisibleItemRange?
        if let first = visibleFirst, let last = visibleLast {
            visibleItemRange = AetherListVisibleItemRange(firstIndex: first, firstIndexFullyVisible: firstFullyVisible, lastIndex: last)
        } else {
            visibleItemRange = nil
        }

        return AetherListDisplayedItemRange(loadedRange: loadedRange, visibleRange: visibleRange, visibleItemRange: visibleItemRange)
    }

    // MARK: - Sticky headers

    /// Index of the floating header that should currently be pinned to
    /// the top of the viewport, if any. Headers are scanned in order;
    /// the last one whose natural Y is at or above the viewport top
    /// wins. Returns `nil` when nothing has scrolled past yet.
    private func currentStickyHeaderIndex() -> Int? {
        let viewportTop = scrollView.contentOffset.y + (headerInsets ?? insets).top
        var found: Int?
        for (i, item) in items.enumerated() {
            guard item.isFloatingHeader, i < itemOffsets.count else { continue }
            if itemOffsets[i] <= viewportTop {
                found = i
            } else {
                // Items are in vertical order — once we pass the
                // viewport top there can't be a later candidate.
                break
            }
        }
        return found
    }

    /// Materialise the floating-header node at `index` if it isn't
    /// already loaded. Called when the viewport scrolls past a header
    /// whose index is outside the regular preload range — without
    /// this the pinned header would briefly disappear.
    private func ensureStickyHeaderNode(at index: Int) {
        guard index >= 0, index < items.count else { return }
        if itemNodes.contains(where: { $0.index == index }) { return }
        let params = layoutParams ?? AetherListItemLayoutParams(width: bounds.width)
        let item = items[index]
        let prev = index > 0 ? items[index - 1] : nil
        let next = index + 1 < items.count ? items[index + 1] : nil
        let (node, layout) = item.createNode(params: params, previousItem: prev, nextItem: next)
        node.applyLayout(layout)
        node.index = index
        node.item = item
        if abs(itemHeights[index] - layout.totalHeight) > 0.5 {
            itemHeights[index] = layout.totalHeight
            rebuildOffsets()
            updateContentSize()
        }
        itemNodes.append(node)
        itemNodes.sort { ($0.index ?? 0) < ($1.index ?? 0) }
        scrollView.addSubview(node)
    }

    /// Reposition every floating-header node in line with the current
    /// scroll offset. Headers above the viewport stick to the top;
    /// when the next header reaches them they get pushed up
    /// naturally (the "domino" sticky behaviour from UITableView).
    private func applyStickyHeaderLayout() {
        guard !items.isEmpty, !itemOffsets.isEmpty else { return }

        let viewportTop = scrollView.contentOffset.y + (headerInsets ?? insets).top

        // Collect sticky-header indices in order.
        var headerIndices: [Int] = []
        for (i, item) in items.enumerated() {
            if item.isFloatingHeader { headerIndices.append(i) }
        }

        // Make sure the current pinned header has a live node — even
        // if its index is outside the regular preload range.
        if let pinnedIndex = currentStickyHeaderIndex(),
           !itemNodes.contains(where: { $0.index == pinnedIndex }) {
            ensureStickyHeaderNode(at: pinnedIndex)
        }

        for (j, headerIndex) in headerIndices.enumerated() {
            guard let node = itemNodes.first(where: { $0.index == headerIndex }) else { continue }
            guard headerIndex < itemOffsets.count, headerIndex < itemHeights.count else { continue }

            let naturalY = itemOffsets[headerIndex]
            let height = itemHeights[headerIndex]
            let nextNaturalY: CGFloat = (j + 1 < headerIndices.count)
                ? itemOffsets[headerIndices[j + 1]]
                : .greatestFiniteMagnitude

            // Header is "pinned" if it has scrolled past the top and
            // the next header hasn't pushed it off yet.
            let isPinned = naturalY <= viewportTop && (nextNaturalY - height) > viewportTop

            // Even if not currently pinned, a header transitioning
            // OUT (next one is approaching the top) should still
            // ride at `nextNaturalY - height` so the push-up is
            // visible. That's the same `min(viewportTop, maxStickY)`
            // formula — we just need to clamp it to >= naturalY.
            let maxStickY = nextNaturalY - height
            let stickY: CGFloat
            if naturalY <= viewportTop {
                stickY = min(maxStickY, max(viewportTop, naturalY))
            } else {
                stickY = naturalY
            }

            let targetFrame = CGRect(x: 0, y: stickY, width: bounds.width, height: height)
            if node.frame != targetFrame {
                node.frame = targetFrame
            }
            // Pinned headers ride above regular cells. Headers in
            // their natural slot keep zPosition 0 so layer ordering
            // stays sane after they un-pin.
            node.layer.zPosition = isPinned ? 1000 : 0
            if isPinned {
                scrollView.bringSubviewToFront(node)
            }
        }
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let currentOffsetY = scrollView.contentOffset.y
        let deltaY = currentOffsetY - (previousDidScrollContentOffsetY ?? currentOffsetY)
        previousDidScrollContentOffsetY = currentOffsetY
        updateVisibleNodes()
        applyStickyHeaderLayout()
        visibleContentOffsetChanged?(scrollView.contentOffset.y + scrollView.contentInset.top)
        didScrollWithOffset?(deltaY, .immediate, nil, scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating)
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

    // MARK: - Tap Handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: scrollView)
        for node in itemNodes {
            if node.frame.contains(point), let index = node.index {
                node.tapped()
                guard items[index].selectable else { break }

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
                break
            }
        }
    }
}
