import UIKit

/// A UIView that only responds to touches on its subviews, not on itself.
/// Equivalent to SparseNode / SparseContainerView.
open class SparseView: UIView {
    override open func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews.reversed() {
            if subview.isHidden || !subview.isUserInteractionEnabled || subview.alpha < 0.01 {
                continue
            }
            let convertedPoint = subview.convert(point, from: self)
            if let result = subview.hitTest(convertedPoint, with: event) {
                return result
            }
        }
        return nil
    }
}
