import UIKit

/// A high-performance virtualized list view, ported from Telegram's `ListView`.
///
/// Uses a transaction-based API for all modifications. Only visible items
/// (plus a preload buffer) are kept in the view hierarchy. Items are
/// represented by `CrystalListItem` models that create and update
/// `CrystalListItemNode` views on demand.
///
/// ```swift
/// let listView = CrystalListView()
/// listView.transaction(
///     insertIndicesAndItems: items.enumerated().map { i, item in
///         CrystalListInsertItem(index: i, item: item)
///     },
///     options: [],
///     completion: { range in print("Visible: \(range)") }
/// )
/// ```
open class CrystalListView: UIView, UIScrollViewDelegate {

    // MARK: - Configuration

    /// Number of viewport heights to preload above and below.
    public var preloadPages: CGFloat = 1.0

    /// Whether scrolling is enabled.
    public var scrollEnabled: Bool {
        get { scrollView.isScrollEnabled }
        set { scrollView.isScrollEnabled = newValue }
    }

    /// Whether to stack items from the bottom (chat-style).
    public var stackFromBottom: Bool = false

    /// Edge insets for the list content.
    public var insets: UIEdgeInsets = .zero {
        didSet {
            scrollView.contentInset = insets
        }
    }

    // MARK: - Callbacks

    /// Called when the range of visible items changes.
    public var displayedItemRangeChanged: ((CrystalListDisplayedItemRange) -> Void)?

    /// Called on every scroll offset change.
    public var visibleContentOffsetChanged: ((CGFloat) -> Void)?

    /// Called when the user begins dragging.
    public var beganInteractiveDragging: (() -> Void)?

    /// Called when scrolling finishes (deceleration ended or drag ended without deceleration).
    public var didEndScrolling: (() -> Void)?

    /// Called when an item is tapped.
    public var itemTapped: ((Int) -> Void)?

    // MARK: - Read-only State

    /// Size of the visible viewport.
    public var visibleSize: CGSize { scrollView.bounds.size }

    /// Whether the user is currently touching the scroll view.
    public var isTracking: Bool { scrollView.isTracking }

    /// Whether the user is currently dragging.
    public var isDragging: Bool { scrollView.isDragging }

    // MARK: - Private State

    private let scrollView = UIScrollView()

    /// All item models in order.
    private var items: [CrystalListItem] = []

    /// Currently loaded nodes, sorted by index. Not all items have nodes —
    /// only those within the visible + preload range.
    private var itemNodes: [CrystalListItemNode] = []

    /// Cached heights for each item (index → totalHeight).
    private var itemHeights: [CGFloat] = []

    /// Cumulative Y offsets for each item (index → top Y of item).
    private var itemOffsets: [CGFloat] = []

    /// Total content height.
    private var totalContentHeight: CGFloat = 0

    /// Current layout params.
    private var layoutParams: CrystalListItemLayoutParams?

    /// Animation duration for transactions.
    private let animationDuration: Double = 0.3

    /// Pending transaction queue (serialized).
    private var isProcessingTransaction = false
    private var pendingTransactions: [() -> Void] = []

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        scrollView.delegate = self
        scrollView.alwaysBounceVertical = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.scrollsToTop = true
        if #available(iOS 13.0, *) {
            scrollView.automaticallyAdjustsScrollIndicatorInsets = true
        }
        if #available(iOS 11.0, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        addSubview(scrollView)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.cancelsTouchesInView = false
        scrollView.addGestureRecognizer(tapGesture)
    }

    // MARK: - Layout

    override open func layoutSubviews() {
        super.layoutSubviews()

        let boundsChanged = scrollView.frame.size != bounds.size
        scrollView.frame = bounds

        if boundsChanged {
            let params = CrystalListItemLayoutParams(
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
        }
    }

    // MARK: - Public API: Transaction

    /// Apply a batch of changes to the list.
    ///
    /// All modifications (add, remove, update) go through this single method.
    /// Changes are applied atomically and can be animated.
    public func transaction(
        deleteIndices: [CrystalListDeleteItem] = [],
        insertIndicesAndItems: [CrystalListInsertItem] = [],
        updateIndicesAndItems: [CrystalListUpdateItem] = [],
        options: CrystalListTransactionOptions = [],
        scrollToItem: CrystalListScrollToItem? = nil,
        updateSizeAndInsets: CrystalListUpdateSizeAndInsets? = nil,
        completion: ((CrystalListDisplayedItemRange) -> Void)? = nil
    ) {
        let work: () -> Void = { [weak self] in
            guard let self else { return }
            self.executeTransaction(
                deleteIndices: deleteIndices,
                insertIndicesAndItems: insertIndicesAndItems,
                updateIndicesAndItems: updateIndicesAndItems,
                options: options,
                scrollToItem: scrollToItem,
                updateSizeAndInsets: updateSizeAndInsets,
                completion: completion
            )
        }

        if isProcessingTransaction {
            pendingTransactions.append(work)
        } else {
            work()
        }
    }

    /// Scroll to an item at the given index.
    public func scrollToItem(at index: Int, position: CrystalListScrollPosition, animated: Bool) {
        guard index >= 0 && index < items.count else { return }
        let targetY = computeScrollOffset(for: index, position: position)
        scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
    }

    /// Stop any ongoing scrolling animation.
    public func stopScrolling() {
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
    }

    /// Iterate over all currently visible item nodes.
    public func forEachVisibleItemNode(_ body: (CrystalListItemNode) -> Void) {
        for node in itemNodes {
            body(node)
        }
    }

    /// Find the visible node for an item at the given index.
    public func nodeForItem(at index: Int) -> CrystalListItemNode? {
        return itemNodes.first { $0.index == index }
    }

    /// Current visible content offset from top.
    public func visibleContentOffset() -> CGFloat {
        return scrollView.contentOffset.y + scrollView.contentInset.top
    }

    // MARK: - Private: Transaction Execution

    private func executeTransaction(
        deleteIndices: [CrystalListDeleteItem],
        insertIndicesAndItems: [CrystalListInsertItem],
        updateIndicesAndItems: [CrystalListUpdateItem],
        options: CrystalListTransactionOptions,
        scrollToItem: CrystalListScrollToItem?,
        updateSizeAndInsets: CrystalListUpdateSizeAndInsets?,
        completion: ((CrystalListDisplayedItemRange) -> Void)?
    ) {
        isProcessingTransaction = true

        // Apply size/insets update
        if let update = updateSizeAndInsets {
            insets = update.insets
            if update.size != bounds.size {
                // Caller should resize the view; we just update insets
            }
        }

        let animate = options.contains(.animateInsertions)
        let animateAlpha = options.contains(.animateAlpha)

        // 1. Collect nodes being removed (for animation)
        var removingNodes: [(CrystalListItemNode, CrystalListItemOperationDirectionHint?)] = []
        let sortedDeletes = deleteIndices.sorted { $0.index > $1.index }
        for delete in sortedDeletes {
            if let nodeIdx = itemNodes.firstIndex(where: { $0.index == delete.index }) {
                let node = itemNodes[nodeIdx]
                removingNodes.append((node, delete.directionHint))
                itemNodes.remove(at: nodeIdx)
            }
            items.remove(at: delete.index)
            itemHeights.remove(at: delete.index)
        }

        // 2. Apply updates
        for update in updateIndicesAndItems {
            guard update.index < items.count else { continue }
            items[update.index] = update.item

            if let node = itemNodes.first(where: { $0.index == update.previousIndex }),
               let params = layoutParams {
                let prevItem = update.index > 0 ? items[update.index - 1] : nil
                let nextItem = update.index + 1 < items.count ? items[update.index + 1] : nil
                let animation: CrystalListItemUpdateAnimation = options.contains(.crossfade) ? .crossfade : .none
                let newLayout = update.item.updateNode(node, params: params, previousItem: prevItem, nextItem: nextItem, animation: animation)
                node.applyLayout(newLayout)
                node.index = update.index
                itemHeights[update.index] = newLayout.totalHeight
            }
        }

        // 3. Apply insertions (sorted by index ascending)
        let sortedInserts = insertIndicesAndItems.sorted { $0.index < $1.index }
        var insertedNodes: [CrystalListItemNode] = []
        for insert in sortedInserts {
            let idx = min(insert.index, items.count)
            items.insert(insert.item, at: idx)
            itemHeights.insert(insert.item.approximateHeight, at: idx)
        }

        // 4. Rebuild offsets
        rebuildOffsets()

        // 5. Create nodes for visible items
        let params = layoutParams ?? CrystalListItemLayoutParams(width: bounds.width)
        let visibleRange = computeVisibleRange()

        // Create nodes for newly visible items
        for i in visibleRange {
            if itemNodes.contains(where: { $0.index == i }) { continue }

            let item = items[i]
            let prevItem = i > 0 ? items[i - 1] : nil
            let nextItem = i + 1 < items.count ? items[i + 1] : nil
            let (node, layout) = item.createNode(params: params, previousItem: prevItem, nextItem: nextItem)
            node.applyLayout(layout)
            node.index = i
            itemHeights[i] = layout.totalHeight
            itemNodes.append(node)
            insertedNodes.append(node)
            scrollView.addSubview(node)
        }

        // Re-sort nodes by index
        itemNodes.sort { ($0.index ?? 0) < ($1.index ?? 0) }

        // Update indices for all nodes
        for node in itemNodes {
            if let oldIndex = node.index {
                // Find new index: the item the node represents
                // (items array was modified, so indices shifted)
            }
        }

        // 6. Rebuild offsets again (heights may have been updated by createNode)
        rebuildOffsets()

        // 7. Position all nodes
        positionNodes()

        // 8. Update scroll view content size
        updateContentSize()

        // 9. Animate
        if animate {
            for node in insertedNodes {
                node.animateInsertion(duration: animationDuration)
            }
            for (node, _) in removingNodes {
                node.animateRemoval(duration: animationDuration) {
                    node.removeFromSuperview()
                }
            }
        } else {
            for (node, _) in removingNodes {
                node.removeFromSuperview()
            }
        }

        // 10. Scroll to item
        if let scrollTo = scrollToItem {
            self.scrollToItem(at: scrollTo.index, position: scrollTo.position, animated: scrollTo.animated)
        }

        // 11. Notify
        let displayedRange = computeDisplayedRange()
        displayedItemRangeChanged?(displayedRange)
        completion?(displayedRange)

        // Process pending
        isProcessingTransaction = false
        if let next = pendingTransactions.first {
            pendingTransactions.removeFirst()
            next()
        }
    }

    // MARK: - Private: Layout Engine

    /// Rebuild cumulative Y offsets from item heights.
    private func rebuildOffsets() {
        itemOffsets = []
        itemOffsets.reserveCapacity(items.count)
        var y: CGFloat = 0
        for height in itemHeights {
            itemOffsets.append(y)
            y += height
        }
        totalContentHeight = y
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
        }
    }

    /// Relayout all existing nodes (e.g. after width change).
    private func relayoutAllNodes(params: CrystalListItemLayoutParams) {
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

        // Remove nodes outside visible range
        var i = 0
        while i < itemNodes.count {
            if let index = itemNodes[i].index, !visibleRange.contains(index) {
                itemNodes[i].removeFromSuperview()
                itemNodes.remove(at: i)
            } else {
                i += 1
            }
        }

        // Add nodes for newly visible items
        for idx in visibleRange {
            if itemNodes.contains(where: { $0.index == idx }) { continue }

            let item = items[idx]
            let prevItem = idx > 0 ? items[idx - 1] : nil
            let nextItem = idx + 1 < items.count ? items[idx + 1] : nil
            let (node, layout) = item.createNode(params: params, previousItem: prevItem, nextItem: nextItem)
            node.applyLayout(layout)
            node.index = idx
            itemHeights[idx] = layout.totalHeight
            itemNodes.append(node)
            scrollView.addSubview(node)

            let y = itemOffsets[idx]
            node.frame = CGRect(x: 0, y: y, width: bounds.width, height: layout.totalHeight)
        }

        itemNodes.sort { ($0.index ?? 0) < ($1.index ?? 0) }

        // Update displayed range
        let displayedRange = computeDisplayedRange()
        displayedItemRangeChanged?(displayedRange)
    }

    // MARK: - Private: Scroll Calculations

    private func computeScrollOffset(for index: Int, position: CrystalListScrollPosition) -> CGFloat {
        guard index < itemOffsets.count else { return 0 }
        let itemTop = itemOffsets[index]
        let itemHeight = itemHeights[index]

        switch position {
        case .visible:
            let currentTop = scrollView.contentOffset.y
            let currentBottom = currentTop + bounds.height
            if itemTop >= currentTop && itemTop + itemHeight <= currentBottom {
                return scrollView.contentOffset.y // already visible
            }
            if itemTop < currentTop {
                return itemTop - insets.top
            }
            return itemTop + itemHeight - bounds.height + insets.bottom

        case .top(let offset):
            return itemTop - insets.top - offset

        case .bottom(let offset):
            return itemTop + itemHeight - bounds.height + insets.bottom + offset

        case .center:
            return itemTop + itemHeight / 2 - bounds.height / 2
        }
    }

    private func computeDisplayedRange() -> CrystalListDisplayedItemRange {
        guard !items.isEmpty else {
            return CrystalListDisplayedItemRange(loadedRange: nil, visibleRange: nil)
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

        for node in itemNodes {
            guard let index = node.index else { continue }
            let nodeTop = node.frame.minY
            let nodeBottom = node.frame.maxY
            if nodeBottom > viewportTop && nodeTop < viewportBottom {
                if visibleFirst == nil { visibleFirst = index }
                visibleLast = index
            }
        }

        let visibleRange: Range<Int>?
        if let first = visibleFirst, let last = visibleLast {
            visibleRange = first ..< (last + 1)
        } else {
            visibleRange = nil
        }

        return CrystalListDisplayedItemRange(loadedRange: loadedRange, visibleRange: visibleRange)
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateVisibleNodes()
        visibleContentOffsetChanged?(scrollView.contentOffset.y + scrollView.contentInset.top)
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
                if items[index].selectable {
                    items[index].selected(listView: self)
                    itemTapped?(index)
                }
                break
            }
        }
    }
}
