import UIKit

/// Base view class for items displayed in a `AetherListView`.
///
/// Subclass this to create custom list item views. Override lifecycle hooks
/// to handle animations, highlighting, and selection.
///
/// The node manages its own layout through `contentSize` and `insets`,
/// which the list view uses to compute the total frame.
open class AetherListItemNode: UIView {

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

    /// Apply a layout result. Called by the list view after item creation or update.
    public func applyLayout(_ layout: AetherListItemNodeLayout) {
        self.layout = layout
        self.contentSize = layout.contentSize
        self.insets = layout.insets
        self.apparentHeight = layout.totalHeight
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
}
