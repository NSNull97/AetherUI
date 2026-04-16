import UIKit

/// Base view class for items displayed in a `CrystalListView`.
///
/// Subclass this to create custom list item views. Override lifecycle hooks
/// to handle animations, highlighting, and selection.
///
/// The node manages its own layout through `contentSize` and `insets`,
/// which the list view uses to compute the total frame.
open class CrystalListItemNode: UIView {

    // MARK: - Layout Properties

    /// Index of this node in the list. Set by the list view.
    public internal(set) var index: Int?

    /// Size of the content area (excluding insets).
    public internal(set) var contentSize: CGSize = .zero

    /// Insets around the content.
    public internal(set) var insets: UIEdgeInsets = .zero

    /// Current layout snapshot.
    public internal(set) var layout: CrystalListItemNodeLayout = CrystalListItemNodeLayout(contentSize: .zero)

    /// Height used during animations (can differ from actual height).
    public var apparentHeight: CGFloat = 0

    /// Vertical offset applied during insertion/deletion transitions.
    public var transitionOffset: CGFloat = 0

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
    public func applyLayout(_ layout: CrystalListItemNodeLayout) {
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

    /// Called when the node is being inserted with animation.
    open func animateInsertion(duration: Double) {
        alpha = 0
        UIView.animate(withDuration: duration) {
            self.alpha = 1
        }
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
