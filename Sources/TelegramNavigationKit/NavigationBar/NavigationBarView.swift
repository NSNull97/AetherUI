import UIKit

/// Protocol for navigation bar views, equivalent to Telegram's NavigationBar protocol.
/// All ASDisplayNode references replaced with UIView.
public protocol NavigationBarView: UIView {
    var backPressed: () -> Void { get set }
    var userInfo: Any? { get set }

    var item: UINavigationItem? { get set }
    var previousItem: NavigationPreviousAction? { get set }
    var enableAutomaticBackButton: Bool { get set }

    var backgroundView: NavigationBackgroundView { get }
    var stripeView: UIView { get }
    var contentView: NavigationBarContentView? { get }

    var secondaryContentHeight: CGFloat { get set }
    var isBackgroundVisible: Bool { get }
    var intrinsicCanTransitionInline: Bool { get set }
    var canTransitionInline: Bool { get }
    var passthroughTouches: Bool { get set }
    var layoutSuspended: Bool { get set }

    var requestContainerLayout: ((ContainedViewLayoutTransition) -> Void)? { get set }

    func contentHeight(defaultHeight: CGFloat) -> CGFloat
    func setContentView(_ contentView: NavigationBarContentView?, animated: Bool)
    func executeBack() -> Bool
    func setHidden(_ hidden: Bool, animated: Bool)

    func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition)
    func updatePresentationData(_ presentationData: NavigationBarPresentationData, transition: ContainedViewLayoutTransition)

    func updateLayout(size: CGSize, defaultHeight: CGFloat, additionalTopHeight: CGFloat, additionalContentHeight: CGFloat, additionalBackgroundHeight: CGFloat, additionalCutout: CGSize?, leftInset: CGFloat, rightInset: CGFloat, appearsHidden: Bool, isLandscape: Bool, transition: ContainedViewLayoutTransition)
}

public extension NavigationBarView {
    /// Back-compat overload matching the old signature without `additionalCutout`.
    func updateLayout(size: CGSize, defaultHeight: CGFloat, additionalTopHeight: CGFloat, additionalContentHeight: CGFloat, additionalBackgroundHeight: CGFloat, leftInset: CGFloat, rightInset: CGFloat, appearsHidden: Bool, isLandscape: Bool, transition: ContainedViewLayoutTransition) {
        self.updateLayout(size: size, defaultHeight: defaultHeight, additionalTopHeight: additionalTopHeight, additionalContentHeight: additionalContentHeight, additionalBackgroundHeight: additionalBackgroundHeight, additionalCutout: nil, leftInset: leftInset, rightInset: rightInset, appearsHidden: appearsHidden, isLandscape: isLandscape, transition: transition)
    }
}
