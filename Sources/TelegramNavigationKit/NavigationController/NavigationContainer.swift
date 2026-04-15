import UIKit

/// Container view managing a stack of view controllers with push/pop transitions.
/// Replaces Telegram's ASDK-based NavigationContainer.
public final class NavigationContainer: UIView, UIGestureRecognizerDelegate {
    public struct Child {
        public let controller: ViewController
        public let view: UIView
        public let navigationBar: NavigationBarView?
    }

    // MARK: - State

    private(set) var controllers: [ViewController] = []
    private var controllerViews: [UIView] = []
    private var transitionCoordinator: NavigationTransitionCoordinator?

    public var topController: ViewController? {
        return controllers.last
    }

    private var validLayout: ContainerViewLayout?
    private var interactiveGestureRecognizer: InteractiveTransitionGestureRecognizer?

    public var isReady: Bool = true
    public var readyChanged: (() -> Void)?

    public var controllerRemoved: ((ViewController) -> Void)?
    /// Fires at the START of an interactive swipe-back commit (right when
    /// the pan gesture lifts past the commit threshold and animateCompletion
    /// begins), NOT at the end of the animation. Outer observers — typically
    /// a TabBarController syncing the shared nav bar — need this so they can
    /// animate alongside the commit rather than snapping state at the end.
    public var controllerWillBeRemoved: ((ViewController) -> Void)?
    /// Interactive-gesture lifecycle for the shared outer nav bar to drive a
    /// progress-dependent crossfade between the "from" and "to" states.
    /// `interactivePopStarted` fires at `.began` — caller captures two
    /// snapshots. `interactivePopProgressed(progress)` fires at `.changed`.
    /// `interactivePopCancelled` fires when the gesture releases without
    /// committing. A committing end fires `controllerWillBeRemoved` (as it
    /// already does today); the caller cleans up the interactive snapshots
    /// from that hook.
    public var interactivePopStarted: ((_ popping: ViewController, _ previous: ViewController) -> Void)?
    public var interactivePopProgressed: ((CGFloat) -> Void)?
    public var interactivePopCancelled: (() -> Void)?
    public var requestLayout: ((ContainedViewLayoutTransition) -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.clipsToBounds = true

        let panRecognizer = InteractiveTransitionGestureRecognizer(
            target: self,
            action: #selector(panGesture(_:)),
            allowedDirections: { [weak self] point in
                guard let self = self, self.controllers.count > 1 else { return [] }
                return [.leftEdge]
            },
            edgeWidth: .constant(20.0)
        )
        panRecognizer.delegate = self
        addGestureRecognizer(panRecognizer)
        self.interactiveGestureRecognizer = panRecognizer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Controller Management

    public func setControllers(_ controllers: [ViewController], animated: Bool) {
        let previousControllers = self.controllers
        let previousTopController = self.controllers.last
        let newTopController = controllers.last

        self.controllers = controllers

        if let layout = validLayout {
            if animated, let previousTop = previousTopController, let newTop = newTopController, previousTop !== newTop {
                let isPush = controllers.count >= previousControllers.count
                performTransition(from: previousTop, to: newTop, push: isPush, layout: layout)
            } else {
                updateControllerViews(layout: layout, transition: animated ? .animated(duration: 0.25, curve: .easeInOut) : .immediate)
            }
        }
    }

    public func pushController(_ controller: ViewController, animated: Bool) {
        let previousTop = controllers.last
        controllers.append(controller)

        if let layout = validLayout {
            if animated, let previousTop = previousTop {
                performTransition(from: previousTop, to: controller, push: true, layout: layout)
            } else {
                updateControllerViews(layout: layout, transition: .immediate)
            }
        }
    }

    public func popController(animated: Bool) -> ViewController? {
        guard controllers.count > 1 else { return nil }

        let removedController = controllers.removeLast()
        let newTop = controllers.last!

        if let layout = validLayout, animated {
            performTransition(from: removedController, to: newTop, push: false, layout: layout)
        } else if let layout = validLayout {
            removedController.view.removeFromSuperview()
            updateControllerViews(layout: layout, transition: .immediate)
        }

        return removedController
    }

    // MARK: - Layout

    public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.validLayout = layout

        if transitionCoordinator == nil {
            updateControllerViews(layout: layout, transition: transition)
        } else {
            // A push/pop animation is in flight — the coordinator owns
            // child view frames so we mustn't touch them, but we DO need
            // to forward the layout to every currently-hosted controller
            // so they can react to changes in ancestors (e.g. the outer
            // nav bar growing back to include the filter bar on pop,
            // which changes the `additionalInsets.top` the root should
            // use for its contentInset). Without this propagation, the
            // "to" controller's contentInset stays stuck at whatever it
            // was when the animation started — the exact "scroll
            // contentInset wrong after pop" bug.
            for controller in controllers where controller.isViewLoaded {
                controller.containerLayoutUpdated(layout, transition: transition)
            }
        }
    }

    private func updateControllerViews(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        guard let topController = controllers.last else { return }

        let activeViews = Set(controllers.map { ObjectIdentifier($0.view) })
        for subview in subviews {
            guard activeViews.contains(ObjectIdentifier(subview)), subview !== topController.view else {
                continue
            }
            subview.removeFromSuperview()
        }

        if topController.view.superview !== self {
            addSubview(topController.view)
        }

        let frame = CGRect(origin: .zero, size: layout.size)
        transition.updateFrame(view: topController.view, frame: frame)
        topController.containerLayoutUpdated(layout, transition: transition)
    }

    // MARK: - Transitions

    private func performTransition(from: ViewController, to: ViewController, push: Bool, layout: ContainerViewLayout) {
        let frame = CGRect(origin: .zero, size: layout.size)

        to.view.frame = frame
        to.containerLayoutUpdated(layout, transition: .immediate)

        if push {
            addSubview(to.view)
            to.view.frame = frame.offsetBy(dx: frame.width, dy: 0)

            let coordinator = NavigationTransitionCoordinator(
                container: self,
                direction: .push,
                topView: to.view,
                bottomView: from.view,
                topBar: to.navigationBarView,
                bottomBar: from.navigationBarView,
                isInteractive: false
            )
            self.transitionCoordinator = coordinator

            coordinator.animateCompletion { [weak self] in
                from.view.removeFromSuperview()
                self?.transitionCoordinator = nil
            }
        } else {
            insertSubview(to.view, belowSubview: from.view)

            let coordinator = NavigationTransitionCoordinator(
                container: self,
                direction: .pop,
                topView: from.view,
                bottomView: to.view,
                topBar: from.navigationBarView,
                bottomBar: to.navigationBarView,
                isInteractive: false
            )
            self.transitionCoordinator = coordinator

            coordinator.animateCompletion { [weak self] in
                from.view.removeFromSuperview()
                self?.transitionCoordinator = nil
                self?.controllerRemoved?(from)
            }
        }
    }

    // MARK: - Interactive Gesture

    @objc private func panGesture(_ recognizer: UIPanGestureRecognizer) {
        guard controllers.count > 1 else { return }

        let translation = recognizer.translation(in: self)
        let velocity = recognizer.velocity(in: self)
        let width = max(1.0, bounds.width)
        let progress = max(0, min(1, translation.x / width))

        switch recognizer.state {
        case .began:
            guard let layout = validLayout else { return }
            let currentController = controllers.last!
            let previousController = controllers[controllers.count - 2]
            guard currentController.attemptNavigation({}) else {
                (recognizer as? InteractiveTransitionGestureRecognizer)?.cancel()
                return
            }

            previousController.view.frame = CGRect(origin: .zero, size: layout.size)
            previousController.containerLayoutUpdated(layout, transition: .immediate)
            insertSubview(previousController.view, belowSubview: currentController.view)

            let coordinator = NavigationTransitionCoordinator(
                container: self,
                direction: .pop,
                topView: currentController.view,
                bottomView: previousController.view,
                topBar: currentController.navigationBarView,
                bottomBar: previousController.navigationBarView,
                isInteractive: true
            )
            self.transitionCoordinator = coordinator
            coordinator.updateProgress(0.0, transition: .immediate, completion: {})

            interactivePopStarted?(currentController, previousController)

        case .changed:
            transitionCoordinator?.updateProgress(progress, transition: .immediate, completion: {})
            interactivePopProgressed?(progress)

        case .ended, .cancelled:
            let shouldComplete = progress > 0.3 || velocity.x > 500
            if shouldComplete {
                // Commit the pop IMMEDIATELY in the controllers array so
                // outer sync (nav bar) can animate alongside the swipe's
                // slide animation. The view stays in the hierarchy until
                // the animation completes and we removeFromSuperview.
                let removing = controllers.removeLast()
                controllerWillBeRemoved?(removing)
                transitionCoordinator?.animateCompletion(velocity: velocity.x) { [weak self] in
                    guard let self = self else { return }
                    removing.view.removeFromSuperview()
                    self.transitionCoordinator = nil
                    self.controllerRemoved?(removing)
                }
            } else {
                interactivePopCancelled?()
                transitionCoordinator?.animateCancel { [weak self] in
                    guard let self = self else { return }
                    let previousController = self.controllers[self.controllers.count - 2]
                    previousController.view.removeFromSuperview()
                    self.transitionCoordinator = nil
                }
            }

        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    override public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard controllers.count > 1, transitionCoordinator == nil else {
            return false
        }
        guard let topController = controllers.last else {
            return false
        }
        if case let .constant(width)? = topController.interactiveNavivationGestureEdgeWidth, width <= 0.0 {
            return false
        }
        return true
    }

    public func combinedSupportedOrientations(currentOrientationToLock: UIInterfaceOrientationMask) -> ViewControllerSupportedOrientations {
        var result = ViewControllerSupportedOrientations()
        for controller in controllers {
            result = result.intersection(controller.supportedOrientations)
        }
        return result
    }
}
