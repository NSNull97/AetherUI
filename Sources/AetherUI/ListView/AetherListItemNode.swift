import UIKit

/// List-owned gestures that may be routed through an item node.
public enum AetherListItemGesture: Equatable {
    case tap
    case reorder
}

/// Current sticky-header presentation state for a list item node.
public struct AetherListStickyHeaderState: Equatable {
    public let affinity: AetherListHeaderAffinity
    public let isPinned: Bool
    public let isFloating: Bool
    public let isFlashing: Bool

    public init(
        affinity: AetherListHeaderAffinity,
        isPinned: Bool,
        isFloating: Bool,
        isFlashing: Bool
    ) {
        self.affinity = affinity
        self.isPinned = isPinned
        self.isFloating = isFloating
        self.isFlashing = isFlashing
    }

    public static let none = AetherListStickyHeaderState(
        affinity: .none,
        isPinned: false,
        isFloating: false,
        isFlashing: false
    )
}

/// Base view class for items displayed in a `AetherListView`.
///
/// Subclass this to create custom list item views. Override lifecycle hooks
/// to handle animations, highlighting, and selection.
///
/// The node manages its own layout through `contentSize` and `insets`,
/// which the list view uses to compute the total frame.
open class AetherListItemNode: UIView {
    private struct AccessorySlot {
        var stableId: AnyHashable
        var item: AetherListAccessoryItem
        var view: UIView
    }

    private var accessorySlots: [AetherListAccessoryPlacement: AccessorySlot] = [:]

    // MARK: - Layout Properties

    /// Index of this node in the list. Kept in sync by the list view
    /// after every transaction.
    public internal(set) var index: Int?

    /// Strong reference to the item model the node is currently
    /// rendering. The list view uses this for object-identity-based
    /// re-indexing across delete / move / insert mutations — looking
    /// items up by previous index breaks the moment several mutations
    /// share a transaction.
    public internal(set) var item: AetherListItem?

    /// Size of the content area (excluding insets).
    public internal(set) var contentSize: CGSize = .zero

    /// Insets around the content.
    public internal(set) var insets: UIEdgeInsets = .zero

    /// Current layout snapshot.
    public internal(set) var layout: AetherListItemNodeLayout = AetherListItemNodeLayout(contentSize: .zero)

    /// Height used during animations (can differ from actual height).
    public var apparentHeight: CGFloat = 0

    /// Vertical offset applied during insertion/deletion transitions.
    public var transitionOffset: CGFloat = 0

    /// Sticky-header state assigned by `AetherListView`.
    public private(set) var stickyHeaderState: AetherListStickyHeaderState = .none

    /// Extra insets used only for scroll positioning. Telegram rows use this
    /// to align the meaningful visual content instead of the whole backing
    /// node; default is `.zero`.
    public var scrollPositioningInsets: UIEdgeInsets = .zero

    /// Selection state, synced by the list view from
    /// `AetherListView.selectedIndices`. Subclasses override
    /// `didChangeSelection(animated:)` to render whatever highlight
    /// they want (checkmark, tinted bg, etc.). Animations triggered
    /// at the right moment ride the list-view-supplied flag.
    public internal(set) var isSelected: Bool = false {
        didSet {
            if oldValue != isSelected {
                didChangeSelection(animated: pendingSelectionAnimated)
            }
        }
    }

    /// Set internally by the list view right before flipping
    /// `isSelected` so the override sees the right `animated` flag —
    /// avoids polluting the public setter with a method signature.
    internal var pendingSelectionAnimated: Bool = false

    // MARK: - Computed Properties

    /// Total height including insets.
    public var totalHeight: CGFloat {
        return insets.top + contentSize.height + insets.bottom
    }

    /// Content bounds (frame minus insets).
    public var contentBounds: CGRect {
        return CGRect(
            x: insets.left,
            y: insets.top,
            width: max(0, bounds.width - insets.left - insets.right),
            height: contentSize.height
        )
    }

    /// Frame adjusted for animated height.
    public var apparentFrame: CGRect {
        return CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: apparentHeight
        )
    }

    // MARK: - Init

    public override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    open override func layoutSubviews() {
        super.layoutSubviews()
        layoutAccessoryViews()
    }

    /// Apply a layout result. Called by the list view after item creation or update.
    public func applyLayout(_ layout: AetherListItemNodeLayout) {
        self.layout = layout
        self.contentSize = layout.contentSize
        self.insets = layout.insets
        self.apparentHeight = layout.totalHeight
        setNeedsLayout()
    }

    public final func setAccessoryItem(_ item: AetherListAccessoryItem?, placement: AetherListAccessoryPlacement) {
        guard let item else {
            if let slot = accessorySlots.removeValue(forKey: placement) {
                slot.view.removeFromSuperview()
                setNeedsLayout()
            }
            return
        }

        if var slot = accessorySlots[placement], slot.stableId == item.stableId {
            slot.item = item
            item.updateView(slot.view)
            accessorySlots[placement] = slot
            setNeedsLayout()
            return
        }

        if let oldSlot = accessorySlots.removeValue(forKey: placement) {
            oldSlot.view.removeFromSuperview()
        }

        let view = item.makeView()
        item.updateView(view)
        addSubview(view)
        accessorySlots[placement] = AccessorySlot(stableId: item.stableId, item: item, view: view)
        setNeedsLayout()
    }

    open func accessoryFrame(
        for placement: AetherListAccessoryPlacement,
        accessorySize: CGSize,
        bounds: CGRect
    ) -> CGRect {
        let size = CGSize(
            width: min(max(0.0, accessorySize.width), bounds.width),
            height: min(max(0.0, accessorySize.height), bounds.height)
        )
        switch placement {
        case .accessory:
            return CGRect(
                x: bounds.maxX - size.width - 16.0,
                y: bounds.midY - size.height / 2.0,
                width: size.width,
                height: size.height
            )
        case .headerAccessory:
            return CGRect(
                x: bounds.maxX - size.width - 16.0,
                y: bounds.minY,
                width: size.width,
                height: size.height
            )
        }
    }

    private func layoutAccessoryViews() {
        guard !accessorySlots.isEmpty else { return }
        for (placement, slot) in accessorySlots {
            let accessorySize = slot.item.size(constrainedTo: bounds.size)
            slot.view.frame = accessoryFrame(
                for: placement,
                accessorySize: accessorySize,
                bounds: bounds
            )
        }
    }

    /// Called before the node enters the reuse pool. Subclasses should cancel
    /// image/text work, clear transient gesture state, and reset content that
    /// is not overwritten by `updateNode`.
    open func prepareForReuse() {
        for slot in accessorySlots.values {
            slot.view.removeFromSuperview()
        }
        accessorySlots.removeAll()
        updateStickyHeaderState(.none, animated: false)
    }

    internal func updateStickyHeaderState(_ state: AetherListStickyHeaderState, animated: Bool) {
        guard stickyHeaderState != state else { return }
        stickyHeaderState = state
        stickyHeaderStateDidChange(state, animated: animated)
    }

    // MARK: - Lifecycle Hooks (Override in Subclasses)

    /// Called when the node's absolute position within the list changes.
    /// Use for visibility tracking, parallax effects, etc.
    open func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize) {
    }

    /// Called whenever `isSelected` flips. Override to render the
    /// highlight / checkmark / accessory. Default is a no-op.
    open func didChangeSelection(animated: Bool) {
    }

    /// Called when the node starts/stops acting as a sticky header. `isFlashing`
    /// is true while the header is temporarily overlaid outside its natural slot
    /// during pin/push transitions.
    open func stickyHeaderStateDidChange(_ state: AetherListStickyHeaderState, animated: Bool) {
    }

    /// Subview that owns the visual the particle-dissolve delete
    /// animation should target. Default is the node itself —
    /// overrides return a tighter sub-region (e.g. the chat
    /// bubble inside a row that has empty padding around it).
    /// The list view snapshots this view, hands it to its dust
    /// overlay, and hides it once the burst starts.
    open var particleDissolveTargetView: UIView { self }

    /// Called when the node is being inserted with animation.
    /// Default treatment is a soft slide-down from a quarter-row
    /// above its final slot, paired with an alpha fade in — same
    /// shape iMessage / Telegram use for incoming rows. Override
    /// for custom directions or to cut to a plain fade.
    open func animateInsertion(duration: Double) {
        animateInsertion(duration: duration, directionHint: nil, invertOffsetDirection: false)
    }

    /// Called when the node is being inserted with animation. The extended
    /// signature lets the list pass Telegram-style operation hints while
    /// preserving the old override point above.
    open func animateInsertion(duration: Double, directionHint: AetherListItemOperationDirectionHint?, invertOffsetDirection: Bool) {
        let dy = -bounds.height * 0.25
        let directionMultiplier: CGFloat
        switch directionHint {
        case .up:
            directionMultiplier = -1.0
        case .down:
            directionMultiplier = 1.0
        case nil:
            directionMultiplier = 1.0
        }
        let resolvedDy = dy * directionMultiplier * (invertOffsetDirection ? -1.0 : 1.0)
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: resolvedDy)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: 0.85,
            initialSpringVelocity: 0.2,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: {
                self.alpha = 1
                self.transform = .identity
            },
            completion: nil
        )
    }

    /// Called when the node is being removed with animation.
    open func animateRemoval(duration: Double, completion: @escaping () -> Void) {
        UIView.animate(withDuration: duration, animations: {
            self.alpha = 0
        }, completion: { _ in
            completion()
        })
    }

    // MARK: - Interaction Hooks

    /// Insets applied to the node frame before list-level gesture hit testing.
    /// Positive values shrink the active row area, negative values expand it.
    open func listGestureHitTestInsets(for gesture: AetherListItemGesture) -> UIEdgeInsets {
        return .zero
    }

    /// Return `false` to let nested controls or custom gestures own the touch.
    /// The default blocks list-level tap/reorder when the touched descendant is
    /// a `UIControl`, `UITextView`, nested `UIScrollView`, or has its own
    /// gesture recognizer.
    open func allowsListGesture(_ gesture: AetherListItemGesture, at point: CGPoint) -> Bool {
        return !containsInteractiveDescendantForListGesture(at: point)
    }

    /// Called when the node is highlighted (touch down).
    open func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
    }

    /// Called when the node is tapped.
    open func tapped() {
    }

    /// Called when the node is long-pressed.
    open func longTapped() {
    }

    /// Called when the node's item is selected.
    open func selected() {
    }

    private func containsInteractiveDescendantForListGesture(at point: CGPoint) -> Bool {
        guard bounds.contains(point), let hitView = hitTest(point, with: nil) else {
            return false
        }

        var current: UIView? = hitView
        while let view = current, view !== self {
            if view is UIControl || view is UITextView || view is UIScrollView {
                return true
            }
            if let recognizers = view.gestureRecognizers, !recognizers.isEmpty {
                return true
            }
            current = view.superview
        }
        return false
    }
}
