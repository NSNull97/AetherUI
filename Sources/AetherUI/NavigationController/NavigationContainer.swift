import UIKit

/// Container view managing a stack of view controllers with push/pop transitions.
/// Replaces the original NavigationContainer.
public final class NavigationContainer: UIView, UIGestureRecognizerDelegate {
    public struct Child {
        public let controller: AetherViewController
        public let view: UIView
        public let navigationBar: NavigationBarView?
    }

    // MARK: - State

    private(set) var controllers: [AetherViewController] = []
    private var controllerViews: [UIView] = []
    private var transitionCoordinator: NavigationTransitionCoordinator?

    private struct PendingControllersUpdate {
        let controllers: [AetherViewController]
        let animated: Bool
    }

    private var pendingControllersUpdate: PendingControllersUpdate?
    private var isDeferringPendingControllersUpdate: Bool = false

    /// True during the narrow window inside `performTransition` between
    /// `addSubview(to.view)` and assigning `self.transitionCoordinator`.
    /// UIKit fires `viewWillAppear` on the incoming controller synchronously
    /// from `addSubview`, which in our base `ViewController` triggers
    /// `bar.requestContainerLayout?(.immediate)` → `AetherNavigationController.
    /// requestLayout` → reentrant `setControllers` on this container.
    /// Without this flag, that reentry sees `transitionCoordinator == nil`
    /// and takes the non-animated path, which evicts the outgoing
    /// controller's view from the hierarchy — leaving the outgoing screen
    /// blank at animation start. Treat this flag as "coordinator is about
    /// to be installed, stay out."
    private var isInstallingTransition: Bool = false

    private var isTransitionActive: Bool {
        return transitionCoordinator != nil || isInstallingTransition || isDeferringPendingControllersUpdate
    }

    public var topController: AetherViewController? {
        return controllers.last
    }

    private var validLayout: ContainerViewLayout?
    private var interactiveGestureRecognizer: InteractiveTransitionGestureRecognizer?

    public var isReady: Bool = true
    public var readyChanged: (() -> Void)?

    public var controllerRemoved: ((AetherViewController) -> Void)?
    var controllerRemovalCommitted: ((AetherViewController) -> Void)?
    public var requestLayout: ((ContainedViewLayoutTransition) -> Void)?
    var navigationBarTransitionBegan: ((NavigationTransitionDirection, AetherViewController, AetherViewController, ContainerViewLayout, Bool) -> Void)?
    var navigationBarTransitionProgress: ((CGFloat, ContainedViewLayoutTransition) -> Void)?
    var navigationBarTransitionResolutionBegan: ((Bool, ContainedViewLayoutTransition) -> Void)?
    var navigationBarTransitionEnded: ((Bool) -> Void)?
    var bottomBarTransitionBegan: ((NavigationTransitionDirection, AetherViewController, AetherViewController, ContainerViewLayout, Bool) -> Void)?
    var bottomBarTransitionProgress: ((CGFloat, ContainedViewLayoutTransition) -> Void)?
    var bottomBarTransitionResolutionBegan: ((Bool, ContainedViewLayoutTransition) -> Void)?
    var bottomBarTransitionEnded: ((Bool) -> Void)?
    var layoutForController: ((AetherViewController, ContainerViewLayout) -> ContainerViewLayout)?

    /// The host device's display corner radius, used to round the **left
    /// edge** of the moving controller's view during push/pop — matches the
    /// iOS 26 native nav-bar transition where the card looks like it's
    /// emerging from / sliding into the device's curved bezel.
    ///
    /// Read via the same `_displayCornerRadius` KVC trick already used in
    /// `AetherTabBarController.deviceDisplayCornerRadius`. Returns `0` when
    /// the value isn't available (older OSes, simulator with non-bezeled
    /// display, embedded hosts) — and the coordinator skips rounding entirely
    /// in that case, so windowed/pop-up hosts behave normally.
    private var screenCornerRadius: CGFloat {
        guard let screen = window?.windowScene?.screen ?? window?.screen else {
            return 0
        }
        if let value = screen.value(forKey: ObfuscatedSymbols.displayCornerRadius) as? CGFloat {
            return value
        }
        return 0
    }

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.clipsToBounds = true

        let panRecognizer = InteractiveTransitionGestureRecognizer(
            target: self,
            action: #selector(panGesture(_:)),
            allowedDirections: { [weak self] point in
                return self?.interactivePopGestureDirections(at: point) ?? []
            },
            edgeWidth: .constant(20.0)
        )
        panRecognizer.edgeWidthOverride = { [weak self] in
            self?.controllers.last?.interactiveNavivationGestureEdgeWidth
        }
        panRecognizer.delegate = self
        addGestureRecognizer(panRecognizer)
        self.interactiveGestureRecognizer = panRecognizer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Controller Management

    public func setControllers(_ controllers: [AetherViewController], animated: Bool) {
        let dedupedControllers = deduplicatedControllers(controllers)

        let previousControllers = self.controllers
        let previousTopController = self.controllers.last
        let newTopController = dedupedControllers.last

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
            let shouldKeepAnimatedPendingUpdate: Bool
            if let pending = pendingControllersUpdate, pending.animated, controllersAreEqual(pending.controllers, dedupedControllers) {
                shouldKeepAnimatedPendingUpdate = true
            } else {
                shouldKeepAnimatedPendingUpdate = false
            }
            pendingControllersUpdate = PendingControllersUpdate(
                controllers: dedupedControllers,
                animated: animated || shouldKeepAnimatedPendingUpdate
            )
            return
        }

        self.controllers = dedupedControllers

        if let layout = validLayout {
            if animated, let previousTop = previousTopController, let newTop = newTopController, previousTop !== newTop {
                let isPush = dedupedControllers.count >= previousControllers.count
                performTransition(from: previousTop, to: newTop, push: isPush, layout: layout)
            } else {
                updateControllerViews(layout: layout, transition: animated ? .animated(duration: 0.25, curve: .easeInOut) : .immediate)
            }
        }
    }

    private func deduplicatedControllers(_ controllers: [AetherViewController]) -> [AetherViewController] {
        var dedupedControllers: [AetherViewController] = []
        dedupedControllers.reserveCapacity(controllers.count)
        for controller in controllers where !dedupedControllers.contains(where: { $0 === controller }) {
            dedupedControllers.append(controller)
        }
        return dedupedControllers
    }

    private func controllersAreEqual(_ lhs: [AetherViewController], _ rhs: [AetherViewController]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        for (left, right) in zip(lhs, rhs) where left !== right {
            return false
        }
        return true
    }

    private func resolvedLayout(for controller: AetherViewController, baseLayout: ContainerViewLayout) -> ContainerViewLayout {
        return layoutForController?(controller, baseLayout) ?? baseLayout
    }

    private func applyPendingControllersUpdateIfPossible(deferred: Bool = false, completion: (() -> Void)? = nil) {
        guard !isTransitionActive, let pending = pendingControllersUpdate else {
            completion?()
            return
        }

        pendingControllersUpdate = nil
        guard !controllersAreEqual(controllers, pending.controllers) else {
            completion?()
            return
        }

        let applyUpdate: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.isDeferringPendingControllersUpdate = false
            self.setControllers(pending.controllers, animated: pending.animated)
            completion?()
        }

        if deferred && pending.animated {
            isDeferringPendingControllersUpdate = true
            DispatchQueue.main.async(execute: applyUpdate)
        } else {
            applyUpdate()
        }
    }

    public func pushController(_ controller: AetherViewController, animated: Bool) {
        var controllers = self.controllers
        controllers.append(controller)
        setControllers(controllers, animated: animated)
    }

    public func popController(animated: Bool) -> AetherViewController? {
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
                controller.containerLayoutUpdated(resolvedLayout(for: controller, baseLayout: layout), transition: transition)
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
        topController.containerLayoutUpdated(resolvedLayout(for: topController, baseLayout: layout), transition: transition)
    }

    // MARK: - Transitions

    private func performTransition(from: AetherViewController, to: AetherViewController, push: Bool, layout: ContainerViewLayout) {
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
        to.containerLayoutUpdated(resolvedLayout(for: to, baseLayout: layout), transition: .immediate)

        if push {
            to.view.frame = frame.offsetBy(dx: frame.width, dy: 0)
            navigationBarTransitionBegan?(.push, from, to, layout, false)
            bottomBarTransitionBegan?(.push, from, to, layout, false)
            addSubview(to.view)
            to.containerLayoutUpdated(resolvedLayout(for: to, baseLayout: layout), transition: .immediate)

            let coordinator = NavigationTransitionCoordinator(
                container: self,
                direction: .push,
                topView: to.view,
                bottomView: from.view,
                topBar: nil,
                bottomBar: nil,
                isInteractive: false,
                screenCornerRadius: screenCornerRadius,
                progressUpdated: { [weak self] progress, transition in
                    self?.navigationBarTransitionProgress?(progress, transition)
                    self?.bottomBarTransitionProgress?(progress, transition)
                }
            )
            self.transitionCoordinator = coordinator
            isInstallingTransition = false

            coordinator.animateCompletion { [weak self] in
                guard let self = self else { return }
                self.navigationBarTransitionEnded?(true)
                self.bottomBarTransitionEnded?(true)
                from.view.removeFromSuperview()
                self.transitionCoordinator = nil
                self.applyPendingControllersUpdateIfPossible(deferred: true)
            }
        } else {
            navigationBarTransitionBegan?(.pop, from, to, layout, false)
            bottomBarTransitionBegan?(.pop, from, to, layout, false)
            insertSubview(to.view, belowSubview: from.view)
            to.containerLayoutUpdated(resolvedLayout(for: to, baseLayout: layout), transition: .immediate)

            let coordinator = NavigationTransitionCoordinator(
                container: self,
                direction: .pop,
                topView: from.view,
                bottomView: to.view,
                topBar: nil,
                bottomBar: nil,
                isInteractive: false,
                screenCornerRadius: screenCornerRadius,
                progressUpdated: { [weak self] progress, transition in
                    self?.navigationBarTransitionProgress?(progress, transition)
                    self?.bottomBarTransitionProgress?(progress, transition)
                }
            )
            self.transitionCoordinator = coordinator
            isInstallingTransition = false

            coordinator.animateCompletion { [weak self] in
                guard let self = self else { return }
                self.navigationBarTransitionEnded?(true)
                self.bottomBarTransitionEnded?(true)
                from.view.removeFromSuperview()
                self.transitionCoordinator = nil
                self.applyPendingControllersUpdateIfPossible(deferred: true) { [weak self] in
                    self?.controllerRemoved?(from)
                }
            }
        }
    }

    // MARK: - Interactive Gesture

    @objc private func panGesture(_ recognizer: UIPanGestureRecognizer) {
        guard controllers.count > 1 else { return }

        let translation = recognizer.translation(in: self)
        let velocity = recognizer.velocity(in: self)
        let width = max(1.0, bounds.width)

        // Map raw pan translation to transition progress with iOS-style
        // rubberband resistance for out-of-range pulls. Inside [0, width] it's
        // a 1:1 linear mapping; outside, the standard UIScrollView damping
        // formula `(1 - 1/(x*c/d + 1)) * d` returns a logarithmically-
        // attenuated effective offset, so the user feels a soft, decelerating
        // pull instead of a hard wall — matching iOS 26 nav-stack feel where
        // dragging the popping screen *back past its origin* (or *past full
        // completion*) tugs with resistance.
        //
        // Match UIScrollView's stock rubber-band constant. The previous 0.32
        // made edge overpull feel too heavy and removed the visible overpop
        // when the user throws the screen away with a fast back gesture.
        let rubberbandC: CGFloat = 0.55
        let progress: CGFloat
        if translation.x < 0 {
            // Backward overscroll — user is dragging the popping screen LEFT
            // past its starting position. Rubberband the negative side.
            let overshoot = -translation.x
            let damped = (1.0 - 1.0 / (overshoot * rubberbandC / width + 1.0)) * width
            progress = -damped / width
        } else if translation.x > width {
            // Forward overscroll past completion. Rare but possible on slow
            // drags after the threshold; same damping.
            let overshoot = translation.x - width
            let damped = (1.0 - 1.0 / (overshoot * rubberbandC / width + 1.0)) * width
            progress = (width + damped) / width
        } else {
            progress = translation.x / width
        }

        switch recognizer.state {
        case .began:
            // Don't spawn the pop coordinator yet. Wait for the first .changed
            // with translation.x > 0 — that's the user actually moving the
            // screen to the right (the pop intent). Spawning on .began would
            // engage the backward-rubberband path even for a stray left-going
            // pan from the screen edge, which is not a pop gesture at all
            // (just an idle drag) and shouldn't visibly tug the screen left.
            break

        case .changed:
            if let coordinator = transitionCoordinator, !coordinator.animatingCompletion {
                // Coordinator already exists — user has started a pop and is
                // now in the middle of it. Apply the (possibly rubberbanded)
                // progress freely, including negative values for backward
                // overscroll.
                coordinator.updateProgress(progress, transition: .immediate, completion: {})
            } else if transitionCoordinator == nil, translation.x > 0, let layout = validLayout {
                // First *rightward* movement — spawn the pop coordinator now
                // and immediately apply the current progress. Anything before
                // this point (idle .began, leftward .changed before any
                // rightward intent) is ignored.
                let currentController = controllers.last!
                let previousController = controllers[controllers.count - 2]
                guard currentController.attemptNavigation({}) else {
                    (recognizer as? InteractiveTransitionGestureRecognizer)?.cancel()
                    return
                }

                previousController.view.frame = CGRect(origin: .zero, size: layout.size)
                previousController.containerLayoutUpdated(resolvedLayout(for: previousController, baseLayout: layout), transition: .immediate)
                navigationBarTransitionBegan?(.pop, currentController, previousController, layout, true)
                bottomBarTransitionBegan?(.pop, currentController, previousController, layout, true)
                insertSubview(previousController.view, belowSubview: currentController.view)
                previousController.containerLayoutUpdated(resolvedLayout(for: previousController, baseLayout: layout), transition: .immediate)

                let coordinator = NavigationTransitionCoordinator(
                    container: self,
                    direction: .pop,
                    topView: currentController.view,
                    bottomView: previousController.view,
                    topBar: nil,
                    bottomBar: nil,
                    isInteractive: true,
                    screenCornerRadius: screenCornerRadius,
                    progressUpdated: { [weak self] progress, transition in
                        self?.navigationBarTransitionProgress?(progress, transition)
                        self?.bottomBarTransitionProgress?(progress, transition)
                    }
                )
                self.transitionCoordinator = coordinator
                coordinator.updateProgress(progress, transition: .immediate, completion: {})

                // Dismiss the keyboard along with the outgoing view. Done *after*
                // the coordinator is installed so the keyboard's synchronous
                // layout cascade hits the transition-aware branch of
                // containerLayoutUpdated rather than stomping the interactive
                // frames.
                currentController.view.endEditing(true)
            }
            // else: pre-coordinator state, translation still <= 0 — no-op.

        case .ended, .cancelled:
            guard let coordinator = transitionCoordinator, !coordinator.animatingCompletion else {
                break
            }
            // Thresholds match Telegram-iOS: a deliberate 20% drag OR a fast
            // flick (>1000pt/s). The previous 30%/500pt/s was too easy to
            // trigger accidentally during vertical-leaning drags.
            let shouldComplete = progress > 0.2 || velocity.x > 1000
            if shouldComplete {
                let committedController = controllers.last!
                let completionTransition = coordinator.completionTransition(velocity: velocity.x)
                navigationBarTransitionResolutionBegan?(true, completionTransition)
                bottomBarTransitionResolutionBegan?(true, completionTransition)
                controllerRemovalCommitted?(committedController)
                coordinator.animateCompletion(velocity: velocity.x) { [weak self] in
                    guard let self = self else { return }
                    let removed = self.controllers.removeLast()
                    removed.view.removeFromSuperview()
                    self.transitionCoordinator = nil
                    self.navigationBarTransitionEnded?(true)
                    self.bottomBarTransitionEnded?(true)
                    self.applyPendingControllersUpdateIfPossible(deferred: true) { [weak self] in
                        self?.controllerRemoved?(removed)
                    }
                }
            } else {
                navigationBarTransitionResolutionBegan?(false, coordinator.cancelTransition)
                bottomBarTransitionResolutionBegan?(false, coordinator.cancelTransition)
                coordinator.animateCancel { [weak self] in
                    guard let self = self else { return }
                    let previousController = self.controllers[self.controllers.count - 2]
                    previousController.view.removeFromSuperview()
                    self.transitionCoordinator = nil
                    self.navigationBarTransitionEnded?(false)
                    self.bottomBarTransitionEnded?(false)
                    self.applyPendingControllersUpdateIfPossible(deferred: true)
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
        if let edgeWidth = topController.interactiveNavivationGestureEdgeWidth?.effectiveWidth(for: bounds.width), edgeWidth <= 0.0 {
            return false
        }
        return true
    }

    func interactivePopGestureDirections(at point: CGPoint) -> InteractiveTransitionGestureRecognizerDirections {
        guard controllers.count > 1 else {
            return []
        }
        guard let topController = controllers.last else {
            return []
        }
        if let edgeWidth = topController.interactiveNavivationGestureEdgeWidth?.effectiveWidth(for: bounds.width), edgeWidth <= 0.0 {
            return []
        }
        return [.leftEdge, .right]
    }

    public func combinedSupportedOrientations(currentOrientationToLock: UIInterfaceOrientationMask) -> AetherViewController.SupportedOrientations {
        var result = AetherViewController.SupportedOrientations()
        for controller in controllers {
            result = result.intersection(controller.supportedOrientations)
        }
        return result
    }
}
