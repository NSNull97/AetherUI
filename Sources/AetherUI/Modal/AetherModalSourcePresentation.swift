import UIKit

/// Object that can provide a source for `AetherModalSourceTransition`.
///
/// Use this when the presenting feature wants to keep ownership of the
/// source view/frame and let the modal resolve it at transition time:
/// `modal.useSourceTransition(from: sourcePresentation)`.
public protocol AetherModalSourcePresentation: AnyObject {
    /// Source frame in window coordinates. Used when `aetherModalSourceView`
    /// is nil or no longer mounted in a window.
    var aetherModalSourceFrameInWindow: CGRect? { get set }
    /// Preferred live source view. When present, its current bounds are
    /// converted at transition time so rotation/layout changes are picked
    /// up automatically.
    var aetherModalSourceView: UIView? { get set }
}
