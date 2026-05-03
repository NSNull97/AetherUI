import UIKit

/// Base class for custom navigation bar content (search bars, segmented
/// controls, etc.). Replaces NavigationBarContentNode.
///
/// ## Resizing when content changes
///
/// Override `nominalHeight` (and optionally `height` / `clippedHeight`)
/// to report your intrinsic size. Two common patterns:
///
/// 1. **Auto Layout** — return a measured size:
///    ```
///    open override var nominalHeight: CGFloat {
///        return systemLayoutSizeFitting(
///            UIView.layoutFittingCompressedSize,
///            withHorizontalFittingPriority: .defaultLow,
///            verticalFittingPriority: .fittingSizeLevel
///        ).height
///    }
///    ```
///    Call `invalidateLayout()` whenever constraints change so the
///    hosting nav bar re-measures.
///
/// 2. **Frame-based / state-driven** — return a computed value:
///    ```
///    open override var nominalHeight: CGFloat {
///        return isExpanded ? 88.0 : 44.0
///    }
///    ```
///    Call `invalidateLayout()` whenever the state that drives the
///    height changes.
open class NavigationBarContentView: UIView {
    /// Plumbed by `NavigationBarImpl` when the content view is installed.
    /// Subclasses should prefer `invalidateLayout(transition:)` instead of
    /// calling this directly — it's public for the framework wiring.
    open var requestContainerLayout: (ContainedViewLayoutTransition) -> Void = { _ in }

    open var height: CGFloat {
        return nominalHeight
    }

    open var clippedHeight: CGFloat {
        return nominalHeight
    }

    open var nominalHeight: CGFloat {
        return 44.0
    }

    open var mode: NavigationBarContentMode {
        return .replacement
    }

    open func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGSize {
        return size
    }

    /// Notify the hosting navigation bar that this view's reported height
    /// (`height` / `nominalHeight`) has changed — the parent will re-run
    /// its layout pass and re-read the new value. Call from subclasses
    /// whenever adding/removing/mutating content in a way that should
    /// visibly resize the nav bar's expansion area.
    ///
    /// The default transition is a soft spring so height changes animate
    /// smoothly; pass `.immediate` for synchronous updates (e.g. inside
    /// an enclosing animation block).
    public func invalidateLayout(
        transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .spring)
    ) {
        requestContainerLayout(transition)
    }
}
