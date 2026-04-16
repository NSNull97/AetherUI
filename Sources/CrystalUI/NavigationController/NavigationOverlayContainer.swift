import UIKit

/// Container for overlay-presented view controllers.
/// Replaces the original NavigationOverlayContainer.
final class NavigationOverlayContainer: UIView {
    let controller: ViewController
    let blocksInteractionUntilReady: Bool

    private(set) var isReady: Bool = false
    var isRemoved: Bool = false
    var isReadyUpdated: (() -> Void)?

    private var validLayout: ContainerViewLayout?

    init(controller: ViewController, blocksInteractionUntilReady: Bool) {
        self.controller = controller
        self.blocksInteractionUntilReady = blocksInteractionUntilReady

        super.init(frame: .zero)

        backgroundColor = .clear

        // Track readiness
        controller.readyChanged = { [weak self] ready in
            guard let self = self, ready, !self.isReady else { return }
            self.isReady = true
            self.isReadyUpdated?()
        }

        // If controller is already ready
        if controller.isReady {
            isReady = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let updateLayout = self.validLayout != layout
        self.validLayout = layout
        transition.updateFrame(view: self, frame: CGRect(origin: .zero, size: layout.size))

        if updateLayout {
            transition.updateFrame(view: controller.view, frame: CGRect(origin: .zero, size: layout.size))
            controller.containerLayoutUpdated(layout, transition: transition)
        }
    }

    func transitionIn(animated: Bool, completion: (() -> Void)? = nil) {
        if controller.view.superview !== self {
            controller.view.frame = bounds
            addSubview(controller.view)
        }

        if animated {
            alpha = 0.0
            transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
            UIView.animate(withDuration: 0.22, delay: 0.0, options: [.curveEaseOut], animations: {
                self.alpha = 1.0
                self.transform = .identity
            }, completion: { _ in
                completion?()
            })
        } else {
            alpha = 1.0
            transform = .identity
            completion?()
        }
    }

    func transitionOut(animated: Bool, completion: @escaping () -> Void) {
        let animations = {
            self.alpha = 0.0
            self.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
        }
        let completed: (Bool) -> Void = { _ in
            self.controller.view.removeFromSuperview()
            completion()
        }

        if animated {
            UIView.animate(withDuration: 0.18, delay: 0.0, options: [.curveEaseIn], animations: animations, completion: completed)
        } else {
            animations()
            completed(true)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if blocksInteractionUntilReady && !isReady {
            return self
        }
        return controller.view.hitTest(convert(point, to: controller.view), with: event)
    }
}
