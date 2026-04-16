import UIKit

// MARK: - Item Protocol

/// Protocol for items displayed in a `CrystalListView`.
///
/// Each item knows how to create and update its view (node). The list view
/// manages the node lifecycle, reuse, and layout.
public protocol CrystalListItem: AnyObject {
    /// Create a new node for this item.
    ///
    /// - Parameters:
    ///   - params: Layout parameters (available width, insets).
    ///   - previousItem: The item above in the list (for separator decisions).
    ///   - nextItem: The item below in the list.
    /// - Returns: A configured node with its layout.
    func createNode(params: CrystalListItemLayoutParams, previousItem: CrystalListItem?, nextItem: CrystalListItem?) -> (CrystalListItemNode, CrystalListItemNodeLayout)

    /// Update an existing node when the item model changes.
    ///
    /// - Parameters:
    ///   - node: The existing node to update.
    ///   - params: Current layout parameters.
    ///   - previousItem: The item above.
    ///   - nextItem: The item below.
    ///   - animation: How to animate the update.
    /// - Returns: Updated layout (height may have changed).
    func updateNode(_ node: CrystalListItemNode, params: CrystalListItemLayoutParams, previousItem: CrystalListItem?, nextItem: CrystalListItem?, animation: CrystalListItemUpdateAnimation) -> CrystalListItemNodeLayout

    /// Approximate height for placeholder layout before the node is created.
    var approximateHeight: CGFloat { get }

    /// Whether the item can be selected (tapped).
    var selectable: Bool { get }

    /// Called when the item is selected.
    func selected(listView: CrystalListView)
}

// Default implementations
public extension CrystalListItem {
    var approximateHeight: CGFloat { 44.0 }
    var selectable: Bool { true }
    func selected(listView: CrystalListView) {}
}

// MARK: - Layout Parameters

/// Parameters passed to items for layout calculation.
public struct CrystalListItemLayoutParams: Equatable {
    /// Available width for the item.
    public let width: CGFloat
    /// Left safe area / content inset.
    public let leftInset: CGFloat
    /// Right safe area / content inset.
    public let rightInset: CGFloat
    /// Available height (viewport height).
    public let availableHeight: CGFloat

    public init(width: CGFloat, leftInset: CGFloat = 0, rightInset: CGFloat = 0, availableHeight: CGFloat = .greatestFiniteMagnitude) {
        self.width = width
        self.leftInset = leftInset
        self.rightInset = rightInset
        self.availableHeight = availableHeight
    }
}

// MARK: - Node Layout

/// Layout result returned by item node creation/update.
public struct CrystalListItemNodeLayout {
    /// Size of the content area (excluding insets).
    public let contentSize: CGSize
    /// Insets around the content.
    public let insets: UIEdgeInsets

    public init(contentSize: CGSize, insets: UIEdgeInsets = .zero) {
        self.contentSize = contentSize
        self.insets = insets
    }

    /// Total height including insets.
    public var totalHeight: CGFloat {
        return insets.top + contentSize.height + insets.bottom
    }
}

// MARK: - Update Animation

/// How an item update should be animated.
public enum CrystalListItemUpdateAnimation {
    /// No animation.
    case none
    /// Crossfade transition.
    case crossfade
    /// Custom animation with duration.
    case animated(duration: Double)
}

// MARK: - Transaction Operations

/// Direction hint for insertion/deletion animations.
public enum CrystalListItemOperationDirectionHint {
    case up
    case down
}

/// Describes an item to delete.
public struct CrystalListDeleteItem {
    public let index: Int
    public let directionHint: CrystalListItemOperationDirectionHint?

    public init(index: Int, directionHint: CrystalListItemOperationDirectionHint? = nil) {
        self.index = index
        self.directionHint = directionHint
    }
}

/// Describes an item to insert.
public struct CrystalListInsertItem {
    /// Target index in the final list.
    public let index: Int
    /// If this item replaces one at a previous index, that node can be reused.
    public let previousIndex: Int?
    /// The item model.
    public let item: CrystalListItem
    /// Animation direction.
    public let directionHint: CrystalListItemOperationDirectionHint?

    public init(index: Int, previousIndex: Int? = nil, item: CrystalListItem, directionHint: CrystalListItemOperationDirectionHint? = nil) {
        self.index = index
        self.previousIndex = previousIndex
        self.item = item
        self.directionHint = directionHint
    }
}

/// Describes an item to update in place.
public struct CrystalListUpdateItem {
    /// Current index.
    public let index: Int
    /// Previous index (for node lookup).
    public let previousIndex: Int
    /// New item model.
    public let item: CrystalListItem
    /// Animation direction.
    public let directionHint: CrystalListItemOperationDirectionHint?

    public init(index: Int, previousIndex: Int, item: CrystalListItem, directionHint: CrystalListItemOperationDirectionHint? = nil) {
        self.index = index
        self.previousIndex = previousIndex
        self.item = item
        self.directionHint = directionHint
    }
}

// MARK: - Transaction Options

/// Options controlling how a transaction is applied.
public struct CrystalListTransactionOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Animate insertions and deletions.
    public static let animateInsertions = CrystalListTransactionOptions(rawValue: 1 << 0)
    /// Fade items in/out instead of sliding.
    public static let animateAlpha = CrystalListTransactionOptions(rawValue: 1 << 1)
    /// Synchronous — block until complete.
    public static let synchronous = CrystalListTransactionOptions(rawValue: 1 << 2)
    /// Crossfade updated items.
    public static let crossfade = CrystalListTransactionOptions(rawValue: 1 << 3)
}

// MARK: - Scroll Position

/// Where to position an item when scrolling to it.
public enum CrystalListScrollPosition {
    /// Scroll until the item is visible (no-op if already visible).
    case visible
    /// Scroll so the item is at the top of the visible area.
    case top(offset: CGFloat)
    /// Scroll so the item is at the bottom of the visible area.
    case bottom(offset: CGFloat)
    /// Scroll so the item is centered.
    case center
}

/// Describes a scroll-to-item request.
public struct CrystalListScrollToItem {
    public let index: Int
    public let position: CrystalListScrollPosition
    public let animated: Bool

    public init(index: Int, position: CrystalListScrollPosition, animated: Bool = true) {
        self.index = index
        self.position = position
        self.animated = animated
    }
}

// MARK: - Visible Range

/// Range of items currently loaded and visible.
public struct CrystalListDisplayedItemRange: Equatable {
    /// Range of all items in memory (visible + preload buffer).
    public let loadedRange: Range<Int>?
    /// Range of items actually visible on screen.
    public let visibleRange: Range<Int>?
}

// MARK: - Size and Insets Update

/// Bundle of size/inset changes to apply in a transaction.
public struct CrystalListUpdateSizeAndInsets {
    public let size: CGSize
    public let insets: UIEdgeInsets
    public let duration: Double
    public let curve: ContainedViewLayoutTransitionCurve

    public init(size: CGSize, insets: UIEdgeInsets, duration: Double = 0, curve: ContainedViewLayoutTransitionCurve = .easeInOut) {
        self.size = size
        self.insets = insets
        self.duration = duration
        self.curve = curve
    }
}
