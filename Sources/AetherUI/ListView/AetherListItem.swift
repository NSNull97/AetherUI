import UIKit

// MARK: - Item Protocol

/// Protocol for items displayed in a `AetherListView`.
///
/// Each item knows how to create and update its view (node). The list view
/// manages the node lifecycle, reuse, and layout.
public protocol AetherListItem: AnyObject {
    /// Create a new node for this item.
    ///
    /// - Parameters:
    ///   - params: Layout parameters (available width, insets).
    ///   - previousItem: The item above in the list (for separator decisions).
    ///   - nextItem: The item below in the list.
    /// - Returns: A configured node with its layout.
    func createNode(params: AetherListItemLayoutParams, previousItem: AetherListItem?, nextItem: AetherListItem?) -> (AetherListItemNode, AetherListItemNodeLayout)

    /// Update an existing node when the item model changes.
    ///
    /// - Parameters:
    ///   - node: The existing node to update.
    ///   - params: Current layout parameters.
    ///   - previousItem: The item above.
    ///   - nextItem: The item below.
    ///   - animation: How to animate the update.
    /// - Returns: Updated layout (height may have changed).
    func updateNode(_ node: AetherListItemNode, params: AetherListItemLayoutParams, previousItem: AetherListItem?, nextItem: AetherListItem?, animation: AetherListItemUpdateAnimation) -> AetherListItemNodeLayout

    /// Approximate height for placeholder layout before the node is created.
    var approximateHeight: CGFloat { get }

    /// Whether the item can be selected (tapped).
    var selectable: Bool { get }

    /// Called when the item is selected.
    func selected(listView: AetherListView)

    /// `true` if this item should "pin" to the top of the viewport
    /// while items below it scroll past — classic sticky-header
    /// behaviour. The list view keeps a node alive for the currently-
    /// pinned header even if the index is outside the preload range,
    /// and pushes it down when the next floating header reaches it.
    var isFloatingHeader: Bool { get }

    /// Whether the item participates in drag-to-reorder. Headers /
    /// separators / non-movable rows return `false`. Has no effect
    /// unless `AetherListView.allowsReorder == true`.
    var canReorder: Bool { get }
}

// Default implementations
public extension AetherListItem {
    var approximateHeight: CGFloat { 44.0 }
    var selectable: Bool { true }
    func selected(listView: AetherListView) {}
    var isFloatingHeader: Bool { false }
    var canReorder: Bool { true }
}

// MARK: - Layout Parameters

/// Parameters passed to items for layout calculation.
public struct AetherListItemLayoutParams: Equatable {
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
public struct AetherListItemNodeLayout {
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
public enum AetherListItemUpdateAnimation {
    /// No animation.
    case none
    /// Crossfade transition.
    case crossfade
    /// Custom animation with duration.
    case animated(duration: Double)
}

// MARK: - Selection

/// Selection mode for a `AetherListView`. `.none` falls back to the
/// classic "tap fires `item.selected(listView:)`" behaviour. The two
/// active modes drive `node.isSelected` based on tap events and emit
/// `AetherListView.selectionChanged`.
public enum AetherListSelectionMode: Equatable {
    case none
    case single
    case multiple
}

// MARK: - Transaction Operations

/// Direction hint for insertion/deletion animations.
public enum AetherListItemOperationDirectionHint {
    case up
    case down
}

/// Visual animation used when a node is removed from the list.
///
/// Each case defines the *shape* of the disappearance — the list view
/// applies it to the node's snapshot or directly to the node, leaving
/// the surrounding items free to slide into the freed slot through the
/// regular transaction animation.
public enum AetherListItemDeleteAnimation: Equatable {
    /// Fade alpha to 0 in place.
    case fade
    /// Slide off the leading or trailing edge while fading.
    case slide(AetherListItemOperationDirectionHint)
    /// Scale-down + fade.
    case scale
    /// Disintegrate the node into a grid of small textured tiles that
    /// drift apart and fade — Telegram-style sand-burst dissolve.
    /// `tileSize` controls how fine the grain is — ~10pt is a good
    /// balance between visual fidelity and the number of layers the
    /// renderer has to push around. Use the `.particles` shorthand
    /// to skip naming the size.
    case particleDissolve(tileSize: CGFloat)
}

public extension AetherListItemDeleteAnimation {
    /// Default-tuned particle dissolve — 1pt-per-pixel grain that
    /// matches the Telegram reference. The Metal compute path is
    /// pre-warmed once per `AetherDustEffectView` so the first
    /// burst doesn't pay PSO compile / driver upload cost.
    static var particles: AetherListItemDeleteAnimation { .particleDissolve(tileSize: 1.0) }
}

/// Describes an item to delete.
public struct AetherListDeleteItem {
    public let index: Int
    public let directionHint: AetherListItemOperationDirectionHint?
    public let animation: AetherListItemDeleteAnimation

    public init(
        index: Int,
        directionHint: AetherListItemOperationDirectionHint? = nil,
        animation: AetherListItemDeleteAnimation = .fade
    ) {
        self.index = index
        self.directionHint = directionHint
        self.animation = animation
    }
}

/// Describes an item to move from one index to another. The move is
/// applied AFTER deletes and BEFORE inserts within a transaction, so
/// `fromIndex` is in the post-delete coordinate space and `toIndex` is
/// in the post-move (pre-insert) space.
public struct AetherListMoveItem {
    public let fromIndex: Int
    public let toIndex: Int
    public let directionHint: AetherListItemOperationDirectionHint?

    public init(fromIndex: Int, toIndex: Int, directionHint: AetherListItemOperationDirectionHint? = nil) {
        self.fromIndex = fromIndex
        self.toIndex = toIndex
        self.directionHint = directionHint
    }
}

/// Describes an item to insert.
public struct AetherListInsertItem {
    /// Target index in the final list.
    public let index: Int
    /// If this item replaces one at a previous index, that node can be reused.
    public let previousIndex: Int?
    /// The item model.
    public let item: AetherListItem
    /// Animation direction.
    public let directionHint: AetherListItemOperationDirectionHint?

    public init(index: Int, previousIndex: Int? = nil, item: AetherListItem, directionHint: AetherListItemOperationDirectionHint? = nil) {
        self.index = index
        self.previousIndex = previousIndex
        self.item = item
        self.directionHint = directionHint
    }
}

/// Describes an item to update in place.
public struct AetherListUpdateItem {
    /// Current index.
    public let index: Int
    /// Previous index (for node lookup).
    public let previousIndex: Int
    /// New item model.
    public let item: AetherListItem
    /// Animation direction.
    public let directionHint: AetherListItemOperationDirectionHint?

    public init(index: Int, previousIndex: Int, item: AetherListItem, directionHint: AetherListItemOperationDirectionHint? = nil) {
        self.index = index
        self.previousIndex = previousIndex
        self.item = item
        self.directionHint = directionHint
    }
}

// MARK: - Transaction Options

/// Options controlling how a transaction is applied.
public struct AetherListTransactionOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Animate insertions and deletions.
    public static let animateInsertions = AetherListTransactionOptions(rawValue: 1 << 0)
    /// Fade items in/out instead of sliding.
    public static let animateAlpha = AetherListTransactionOptions(rawValue: 1 << 1)
    /// Synchronous — block until complete.
    public static let synchronous = AetherListTransactionOptions(rawValue: 1 << 2)
    /// Crossfade updated items.
    public static let crossfade = AetherListTransactionOptions(rawValue: 1 << 3)
}

// MARK: - Scroll Position

/// Where to position an item when scrolling to it.
public enum AetherListScrollPosition {
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
public struct AetherListScrollToItem {
    public let index: Int
    public let position: AetherListScrollPosition
    public let animated: Bool

    public init(index: Int, position: AetherListScrollPosition, animated: Bool = true) {
        self.index = index
        self.position = position
        self.animated = animated
    }
}

// MARK: - Visible Range

/// Range of items currently loaded and visible.
public struct AetherListDisplayedItemRange: Equatable {
    /// Range of all items in memory (visible + preload buffer).
    public let loadedRange: Range<Int>?
    /// Range of items actually visible on screen.
    public let visibleRange: Range<Int>?
}

// MARK: - Size and Insets Update

/// Bundle of size/inset changes to apply in a transaction.
public struct AetherListUpdateSizeAndInsets {
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
