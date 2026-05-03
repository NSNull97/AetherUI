import UIKit

/// Optional protocol for `ViewController`s that will be presented inside
/// a `AetherModalNavigationController`. Lets the modal pull the
/// content's footer / scroll preferences when it embeds the root —
/// callers don't have to repeat the boilerplate at every present site.
///
/// Conforming is opt-in. A VC that doesn't conform is presented as-is
/// (no footer slot, no scroll arbitration). All members carry sensible
/// defaults via the extension below, so a VC only declares the bits it
/// actually wants to customize.
///
/// ```swift
/// final class SendPushViewController: ViewController, AetherModalContent {
///     private(set) lazy var sendButton: UIButton = ...
///     private(set) var scroll: UIScrollView?
///
///     var modalFooterView: UIView? { sendButton.padding(...) }
///     var modalFooterHeight: CGFloat { 98 }
///     var modalPrimaryScrollView: UIScrollView? { scroll }
/// }
///
/// // Caller — one line:
/// let modal = AetherModalNavigationController(
///     rootViewController: SendPushViewController(),
///     config: .init(detents: [.stage1, .stage2], initialDetent: .stage2)
/// )
/// present(modal, animated: true)
/// ```
public protocol AetherModalContent: AnyObject {
    /// View to install in the modal's `footerView` slot. `nil` → no footer.
    var modalFooterView: UIView? { get }
    /// Total height (in points) of the footer including any internal
    /// padding. Drives the modal's edge-effect band height and the
    /// auto-added bottom safe-area inset.
    var modalFooterHeight: CGFloat { get }
    /// Height of the gradient fade above the footer that dissolves the
    /// scroll content into the frost.
    var modalFooterEdgeFadeHeight: CGFloat { get }
    /// Tint colour drawn behind the footer. `nil` → derive from
    /// `config.dimTintColor` with 0.86 alpha.
    var modalFooterEdgeTintColor: UIColor? { get }
    /// Blur radius behind the footer band.
    var modalFooterEdgeBlurRadius: CGFloat { get }
    /// Scroll view inside the content the modal should yield to during
    /// drag (gesture arbitration).
    var modalPrimaryScrollView: UIScrollView? { get }
}

public extension AetherModalContent {
    var modalFooterView: UIView? { nil }
    var modalFooterHeight: CGFloat { 0 }
    var modalFooterEdgeFadeHeight: CGFloat { 28 }
    var modalFooterEdgeTintColor: UIColor? { nil }
    var modalFooterEdgeBlurRadius: CGFloat { 2 }
    var modalPrimaryScrollView: UIScrollView? { nil }
}
