import UIKit

final class CrystalModalTransitioningDelegate: NSObject, UIViewControllerTransitioningDelegate {
    func presentationController(
        forPresented presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController
    ) -> UIPresentationController? {
        return CrystalModalPresentationController(presentedViewController: presented, presenting: presenting)
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        return CrystalModalPresentAnimator()
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return CrystalModalDismissAnimator()
    }
}

final class CrystalModalPresentAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.42
    }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let toVC = ctx.viewController(forKey: .to),
              let toView = ctx.view(forKey: .to) else {
            ctx.completeTransition(false)
            return
        }
        let container = ctx.containerView
        let finalFrame = ctx.finalFrame(for: toVC)

        toView.frame = finalFrame.offsetBy(dx: 0.0, dy: container.bounds.height - finalFrame.minY)
        container.addSubview(toView)

        UIView.animate(
            withDuration: transitionDuration(using: ctx),
            delay: 0.0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.0,
            options: [.allowUserInteraction],
            animations: {
                toView.frame = finalFrame
            },
            completion: { _ in
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        )
    }
}

final class CrystalModalDismissAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.3
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
            },
            completion: { _ in
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        )
    }
}
