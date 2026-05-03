import UIKit

final class AetherModalTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        return AetherModalPresentationController(presentedViewController: presented, presenting: presenting)
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        return AetherModalPresentAnimator()
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return AetherModalDismissAnimator()
    }
}

final class AetherModalPresentAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    // Reference travel distance (~stage1 from the bottom). The actual
    // duration scales up for further travels (stage2 moves almost a full
    // screen) so the spring reads the same regardless of detent.
    private static let referenceTravel: CGFloat = 420.0
    private static let baseDuration: CFTimeInterval = 0.45

    private var contextTravel: CGFloat = referenceTravel

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        let scale = max(1.0, min(1.55, contextTravel / Self.referenceTravel))
        return Self.baseDuration * scale
    }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let toVC = ctx.viewController(forKey: .to),
              let toView = ctx.view(forKey: .to) else {
            ctx.completeTransition(false)
            return
        }
        let container = ctx.containerView
        let finalFrame = ctx.finalFrame(for: toVC)
        contextTravel = max(1.0, container.bounds.height - finalFrame.minY)

        toView.frame = finalFrame.offsetBy(dx: 0.0, dy: container.bounds.height - finalFrame.minY)
        container.addSubview(toView)
        toView.layoutIfNeeded()

        UIView.animate(
            withDuration: transitionDuration(using: ctx),
            delay: 0.0,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.2,
            options: [.allowUserInteraction],
            animations: {
                toView.frame = finalFrame
                toView.layoutIfNeeded()
            },
            completion: { _ in
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        )
    }
}

final class AetherModalDismissAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.16
    }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let fromView = ctx.view(forKey: .from) else {
            ctx.completeTransition(false)
            return
        }
        let container = ctx.containerView
        let startFrame = fromView.frame
        let endFrame = startFrame.offsetBy(dx: 0.0, dy: container.bounds.height - startFrame.minY)

        UIView.animate(
            withDuration: transitionDuration(using: ctx),
            delay: 0.0,
            options: [.curveEaseIn],
            animations: {
                fromView.frame = endFrame
                fromView.layoutIfNeeded()
            },
            completion: { _ in
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        )
    }
}
