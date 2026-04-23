import UIKit

/// Container view managing a stack of view controllers with push/pop transitions.
/// Replaces the original NavigationContainer.
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

    /// True during the narrow window inside `performTransition` between
    /// `addSubview(to.view)` and assigning `self.transitionCoordinator`.
    /// UIKit fires `viewWillAppear` on the incoming controller synchronously
    /// from `addSubview`, which in our base `ViewController` triggers
    /// `bar.requestContainerLayout?(.immediate)` → `CrystalNavigationController.
    /// requestLayout` → reentrant `setControllers` on this container.
    /// Without this flag, that reentry sees `transitionCoordinator == nil`
    /// and takes the non-animated path, which evicts the outgoing
    /// controller's view from the hierarchy — leaving the outgoing screen
    /// blank at animation start. Treat this flag as "coordinator is about
    /// to be installed, stay out."
    private var isInstallingTransition: Bool = false

    private var isTransitionActive: Bool {
        return transitionCoordinator != nil || isInstallingTransition
    }

    public var topController: ViewController? {
        return controllers.last
    }

    private var validLayout: ContainerViewLayout?
    private var interactiveGestureRecognizer: InteractiveTransitionGestureRecognizer?

    public var isReady: Bool = true
    public var readyChanged: (() -> Void)?

    public var controllerRemoved: ((ViewController) -> Void)?
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

        // If a transition is already in flight (e.g. an interactive pop
        // gesture), the coordinator owns the frames of top/bottom views.
        // Running updateControllerViews here would reset the top view's
        // frame to (0,0,w,h) via transition.updateFrame, stomping on the
        // gesture's in-progress frame. The follow-up containerLayoutUpdated
        // call (from the same updateRootContainer site) already takes the
        // transition-aware path and forwards layout per-controller.
        //
        // Also bail when `isInstallingTransition` is set: we're in the
        // narrow window of `performTransition` where `addSubview(to.view)`
        // has fired `viewWillAppear` on the incoming controller, which
        // cascades back into this method before the coordinator has been
        // assigned. See the flag's declaration for the full story.
        if isTransitionActive {
            return
        }

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

        if !isTransitionActive {
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

        // Mark the transition as "being installed" BEFORE any call that
        // could reach the view hierarchy for `to` (including
        // `to.containerLayoutUpdated` which lays out the bar, and
        // `addSubview` which fires UIKit's appearance transitions). Both
        // can cause `viewWillAppear` → `bar.requestContainerLayout` →
        // `requestLayout` reentry into this container before the
        // coordinator reference is assigned.
        isInstallingTransition = true
        to.containerLayoutUpdated(layout, transition: .immediate)

        if push {
            addSubview(to.view)
            to.view.frame = frame.offsetBy(dx: frame.width, dy: 0)

            let coordinator = NavigationTransitionCoordinator(
                container: self,
                direction: .push,
                topView: to.view,
                bottomView: from.view,
                topBar: nil,
                bottomBar: nil,
                isInteractive: false
            )
            self.transitionCoordinator = coordinator
            isInstallingTransition = false

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
                topBar: nil,
                bottomBar: nil,
                isInteractive: false
            )
            self.transitionCoordinator = coordinator
            isInstallingTransition = false

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
                topBar: nil,
                bottomBar: nil,
                isInteractive: true
            )
            self.transitionCoordinator = coordinator
            coordinator.updateProgress(0.0, transition: .immediate, completion: {})

            // Dismiss the keyboard along with the outgoing view. Done *after*
            // the coordinator is installed so the keyboard's synchronous
            // layout cascade hits the transition-aware branch of
            // containerLayoutUpdated rather than stomping the interactive
            // frames.
            currentController.view.endEditing(true)

        case .changed:
            // Mirror upstream: once the completion animation is in flight,
            // progress updates would race the coordinator and corrupt the
            // interpolated frames.
            if let coordinator = transitionCoordinator, !coordinator.animatingCompletion {
                coordinator.updateProgress(progress, transition: .immediate, completion: {})
            }

        case .ended, .cancelled:
            guard let coordinator = transitionCoordinator, !coordinator.animatingCompletion else {
                break
            }
            // Thresholds match Telegram-iOS: a deliberate 20% drag OR a fast
            // flick (>1000pt/s). The previous 30%/500pt/s was too easy to
            // trigger accidentally during vertical-leaning drags.
            let shouldComplete = progress > 0.2 || velocity.x > 1000
            if shouldComplete {
                coordinator.animateCompletion(velocity: velocity.x) { [weak self] in
                    guard let self = self else { return }
                    let removed = self.controllers.removeLast()
                    removed.view.removeFromSuperview()
                    self.transitionCoordinator = nil
                    self.controllerRemoved?(removed)
                }
            } else {
                coordinator.animateCancel { [weak self] in
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
