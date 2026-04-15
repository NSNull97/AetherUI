import UIKit

/// Base class for custom navigation bar content (search bars, segmented controls, etc.).
/// Replaces ASDK-based NavigationBarContentNode.
open class NavigationBarContentView: UIView {
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
}
