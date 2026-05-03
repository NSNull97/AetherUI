import UIKit

/// Base class for `AetherTabBarController.bottomBarAccessory` views —
/// sits directly above the tab bar pill, wrapped in a glass pill by the
/// controller.
///
/// Mirrors the `NavigationBarContentView` pattern on the bottom chrome
/// side: subclass, override `nominalHeight` to size your content and
/// `updateLayout(size:transition:)` to position internal subviews. The
/// parent tab-bar controller handles the glass background, side insets
/// (matching the tab bar theme's `sideInset`), and an 8pt bottom gap
/// against the tab bar pill.
///
/// ## Resizing when content changes
///
/// Two common patterns for `nominalHeight`:
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
///    hosting tab bar re-measures.
///
/// 2. **Frame-based / state-driven** — return a computed value:
///    ```
///    open override var nominalHeight: CGFloat {
///        return isExpanded ? 96.0 : 56.0
///    }
///    ```
///    Call `invalidateLayout()` whenever state changes.
open class TabBarAccessoryView: UIView {
    /// Natural height of this accessory. Override to return a specific
    /// value; default is `56pt`.
    open var nominalHeight: CGFloat {
        return 56.0
    }

    /// Height actually used for layout. Defaults to `nominalHeight` —
    /// override when a subclass needs to distinguish between the two
    /// (e.g., animating between collapsed and expanded forms).
    open var height: CGFloat {
        return nominalHeight
    }

    /// Lay out internal content given the glass pill's resolved size.
    /// Subclasses that use frame-based layout should override; Auto
    /// Layout-based subclasses can ignore it.
    open func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
    }

    /// Plumbed by `AetherTabBarController` when the accessory is
    /// installed. Subclasses should prefer `invalidateLayout(transition:)`
    /// instead of calling this directly — it's public for the framework
    /// wiring.
    open var requestLayout: (ContainedViewLayoutTransition) -> Void = { _ in }

    /// When non-`nil`, taps on the accessory's glass surface trigger a
    /// fluid morph that expands the accessory pill into a full-screen
    /// presentation of the returned view controller (Apple-Music-style
    /// "open the player" gesture). Returning `nil` from the closure
    /// suppresses the expansion for that tap.
    ///
    /// The returned controller is added as a child of
    /// `AetherTabBarController` and its view animates from the
    /// accessory's current frame (with its cornerRadius) to the full
    /// view bounds. Restore the accessory by calling
    /// `AetherTabBarController.dismissExpandedAccessory(animated:)` —
    /// or wire any in-controller dismiss button to that method.
    ///
    /// Returning a freshly-built controller per call lets you treat the
    /// expanded form as ephemeral state. If you want to preserve state
    /// across collapses, cache the controller yourself and return the
    /// same instance.
    open var expandedViewControllerProvider: (() -> UIViewController?)?

    /// Notify the hosting tab bar that this view's reported height
    /// (`height` / `nominalHeight`) has changed — the parent will re-run
    /// its layout pass, re-read the new value, repositions the glass
    /// wrapper, updates `additionalSafeAreaInsets` for descendants, and
    /// re-extends the edge-effect frost to match. Call from subclasses
    /// whenever adding/removing/mutating content in a way that should
    /// visibly resize the accessory.
    ///
    /// The default transition is a soft spring so height changes animate
    /// smoothly; pass `.immediate` for synchronous updates (e.g. inside
    /// an enclosing animation block).
    public func invalidateLayout(
        transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .spring)
    ) {
        requestLayout(transition)
    }
}
