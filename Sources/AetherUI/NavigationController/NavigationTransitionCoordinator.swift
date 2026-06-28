import UIKit

// Direct port of Display framework `NavigationTransitionCoordinator` from
// submodules/Display/Source/NavigationTransitionCoordinator.swift
// adapted to pure UIKit.

enum NavigationTransitionDirection {
    case push
    case pop
}

private let navigationShadowWidth: CGFloat = 16.0
private let fastPopOverpopVelocityThreshold: CGFloat = 1500.0
private let overpulledPopExitProgressThreshold: CGFloat = 1.035

private final class NavigationProgressDisplayLinkTarget: NSObject {
    var tick: ((CADisplayLink) -> Void)?

    @objc func handleDisplayLink(_ link: CADisplayLink) {
        tick?(link)
    }
}

private struct NavigationProgressTiming {
    let p1x: CGFloat
    let p1y: CGFloat
    let p2x: CGFloat
    let p2y: CGFloat

    static let linear = NavigationProgressTiming(p1x: 0.0, p1y: 0.0, p2x: 1.0, p2y: 1.0)
    static let easeInOut = NavigationProgressTiming(p1x: 0.42, p1y: 0.0, p2x: 0.58, p2y: 1.0)
    static let navigationEaseOut = NavigationProgressTiming(p1x: 0.18, p1y: 0.82, p2x: 0.22, p2y: 1.0)

    func value(at input: CGFloat) -> CGFloat {
        let x = max(0.0, min(1.0, input))
        var lower: CGFloat = 0.0
        var upper: CGFloat = 1.0
        var t = x
        for _ in 0..<8 {
            let estimatedX = cubicValue(t: t, p1: p1x, p2: p2x)
            if estimatedX < x {
                lower = t
            } else {
                upper = t
            }
            t = (lower + upper) * 0.5
        }
        return cubicValue(t: t, p1: p1y, p2: p2y)
    }

    private func cubicValue(t: CGFloat, p1: CGFloat, p2: CGFloat) -> CGFloat {
        let inverse = 1.0 - t
        return 3.0 * inverse * inverse * t * p1 + 3.0 * inverse * t * t * p2 + t * t * t
    }
}

private let navigationShadowImage: UIImage? = generateImage(CGSize(width: 16.0, height: 1.0), rotatedContext: { size, context in
    context.clear(CGRect(origin: .zero, size: size))
    context.setFillColor(UIColor.black.cgColor)
    context.setShadow(offset: .zero, blur: 16.0, color: UIColor(white: 0.0, alpha: 0.5).cgColor)
    context.fill(CGRect(origin: CGPoint(x: size.width, y: 0.0), size: CGSize(width: 16.0, height: 1.0)))
})

final class NavigationTransitionCoordinator {
    // MARK: - Public state

    /// 0 = start of transition, 1 = complete. For push, visually "1" means the
    /// new screen fully on-screen; for pop, "1" means the popped screen fully
    /// off-screen to the right.
    private(set) var progress: CGFloat = 0.0

    let isInteractive: Bool
    let isFlat: Bool

    private(set) var animatingCompletion: Bool = false

    // MARK: - Internal

    private let container: UIView
    private let direction: NavigationTransitionDirection
    private let topView: UIView
    private let bottomView: UIView
    private let topBar: NavigationBarView?
    private let bottomBar: NavigationBarView?
    private let progressUpdated: ((CGFloat, ContainedViewLayoutTransition) -> Void)?

    private let dimView: UIView
    private let shadowView: UIImageView

    private var topInitialCorners: (clipsToBounds: Bool, cornerRadius: CGFloat, maskedCorners: CACornerMask, cornerCurve: CALayerCornerCurve)?

    private var currentCompletion: (() -> Void)?

    private var progressDisplayLink: CADisplayLink?
    private var progressDisplayLinkTarget: NavigationProgressDisplayLinkTarget?
    private var progressAnimationElapsed: CFTimeInterval = 0.0
    private var progressAnimationLastTimestamp: CFTimeInterval?
    private var progressAnimationDuration: CFTimeInterval = 0.0
    private var progressAnimationFrom: CGFloat = 0.0
    private var progressAnimationTo: CGFloat = 0.0
    private var progressAnimationTiming: NavigationProgressTiming = .navigationEaseOut
    private var progressAnimationCompletion: (() -> Void)?

    var completionTransition: ContainedViewLayoutTransition {
        return makeCompletionTransition(velocity: 0.0)
    }

    static func nonInteractiveCompletionTransition(direction: NavigationTransitionDirection) -> ContainedViewLayoutTransition {
        let duration: Double
        switch direction {
        case .push:
            duration = 0.50
        case .pop:
            duration = 0.46
        }
        return .animated(duration: duration, curve: .navigationEaseOut)
    }

    func completionTransition(velocity: CGFloat) -> ContainedViewLayoutTransition {
        return makeCompletionTransition(velocity: velocity)
    }

    var cancelTransition: ContainedViewLayoutTransition {
        return .animated(duration: 0.30, curve: .navigationEaseOut)
    }

    // MARK: - Init

    /// - parameters:
    ///   - direction: `.push` or `.pop`.
    ///   - topView: the incoming controller's view on push, or the outgoing
    ///     (being dismissed) one on pop — i.e. the view that moves.
    ///   - bottomView: the stationary-ish view behind `topView` (it gets a
    ///     parallax translation unless `isFlat`).
    ///   - isInteractive: whether this was initiated by a pan gesture.
    ///   - isFlat: when true, no parallax — `bottomView` simply slides in sync.
    ///   - screenCornerRadius: matches the device's display corner radius;
    ///     used to round **all four corners** of `topView` during the transition
    ///     for the iOS 26 card-like feel — the moving controller looks like a
    ///     full carded surface. The right-side corners spend most of the
    ///     animation flush with the device bezel (so the rounding visually
    ///     fuses with the physical screen radius), and `restoreTopViewCorners`
    ///     resets the layer back to flat once the transition settles, so no
    ///     visible notch appears in the final full-bounds state.
    init(
        container: UIView,
        direction: NavigationTransitionDirection,
        topView: UIView,
        bottomView: UIView,
        topBar: NavigationBarView?,
        bottomBar: NavigationBarView?,
        isInteractive: Bool,
        isFlat: Bool = false,
        screenCornerRadius: CGFloat = 0.0,
        progressUpdated: ((CGFloat, ContainedViewLayoutTransition) -> Void)? = nil
    ) {
        self.container = container
        self.direction = direction
        self.topView = topView
        self.bottomView = bottomView
        self.topBar = topBar
        self.bottomBar = bottomBar
        self.isInteractive = isInteractive
        self.isFlat = isFlat
        self.progressUpdated = progressUpdated

        self.dimView = UIView()
        self.dimView.backgroundColor = .black
        self.dimView.alpha = 0.0

        self.shadowView = UIImageView(image: navigationShadowImage)
        self.shadowView.alpha = 0.0

        // Z-order: bottomView is added first by the caller; we add dim + shadow
        // just below topView so the shadow falls on bottomView.
        switch direction {
        case .push:
            if topView.superview == nil {
                container.addSubview(topView)
            }
        case .pop:
            // The caller is expected to have inserted bottomView below topView.
            if topView.superview == nil {
                container.addSubview(topView)
            }
        }

        if !isFlat {
            container.insertSubview(dimView, belowSubview: topView)
            container.insertSubview(shadowView, belowSubview: dimView)

            if screenCornerRadius > 0.0 {
                // Snapshot existing corner state so `restoreTopViewCorners`
                // can put it back exactly as we found it (different consumers
                // of the framework may already be applying their own rounding).
                topInitialCorners = (
                    topView.clipsToBounds,
                    topView.layer.cornerRadius,
                    topView.layer.maskedCorners,
                    topView.layer.cornerCurve
                )
                // Round all four corners (iOS 26 native nav-stack look —
                // the moving controller reads as a full carded surface, not
                // a half-rounded slab). The right side stays flush with the
                // physical bezel through most of the animation, so its
                // rounding fuses visually with the device radius.
                // `restoreTopViewCorners` resets to flat at completion, so
                // no notch appears in the settled full-bounds state.
                topView.layer.maskedCorners = [
                    .layerMinXMinYCorner, .layerMaxXMinYCorner,
                    .layerMinXMaxYCorner, .layerMaxXMaxYCorner
                ]
                topView.layer.cornerCurve = .continuous
                topView.clipsToBounds = true
                topView.layer.cornerRadius = screenCornerRadius
            }
        }

        dimView.frame = container.bounds
        updateProgress(0.0, transition: .immediate, completion: {})
    }

    deinit {
        invalidateProgressDisplayLink()
    }

    // MARK: - Progress

    /// Maps `progress` (0 → 1) to the on-screen position of the transition.
    /// Mirrors the original: `position = 1 - progress` for `.push`, `position =
    /// progress` for `.pop`. All geometry is driven by `position`.
    func updateProgress(_ progress: CGFloat, transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        self.progress = progress
        progressUpdated?(progress, transition)
        updateContentProgress(progress, transition: transition, completion: completion)
    }

    private func updateContentProgress(_ progress: CGFloat, transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        let position: CGFloat
        switch direction {
        case .push:
            position = 1.0 - progress
        case .pop:
            position = progress
        }

        let size = container.bounds.size
        let topFrame = CGRect(origin: CGPoint(x: position * size.width, y: 0.0), size: size)
        let bottomFrame: CGRect
        if isFlat {
            bottomFrame = CGRect(origin: CGPoint(x: -(1.0 - position) * size.width, y: 0.0), size: size)
        } else {
            // Parallax: bottomView moves at 30% of topView's displacement.
            bottomFrame = CGRect(origin: CGPoint(x: (position - 1.0) * size.width * 0.3, y: 0.0), size: size)
        }

        var canInvokeCompletion = false
        var hadEarlyCompletion = false
        transition.updateFrame(view: topView, frame: topFrame, completion: { _ in
            if canInvokeCompletion {
                completion()
            } else {
                hadEarlyCompletion = true
            }
        })
        canInvokeCompletion = true

        transition.updateFrame(view: bottomView, frame: bottomFrame)

        let shadowFrame = CGRect(
            x: topFrame.minX - navigationShadowWidth,
            y: 0.0,
            width: navigationShadowWidth,
            height: size.height
        )
        transition.updateFrame(view: shadowView, frame: shadowFrame)
        transition.updateAlpha(view: shadowView, alpha: (1.0 - position) * 0.9)

        transition.updateFrame(view: dimView, frame: CGRect(origin: .zero, size: CGSize(width: max(0.0, topFrame.minX), height: size.height)))
        // iOS 26-style transition: no dim layer over `bottomView` during the
        // push/pop morph. The bottom controller stays fully readable behind the
        // moving top view; only the parallax shift + drop shadow on the
        // top view's leading edge separate the two layers visually. The old
        // (1.0 - position) * 0.15 alpha tint was a Display/iOS 13 carry-over
        // that flattened the visible scene contrast in a way iOS 26 nav
        // explicitly walks back. `dimView` is kept in the hierarchy so its
        // teardown path stays simple — alpha pinned to 0.
        transition.updateAlpha(view: dimView, alpha: 0.0)

        if hadEarlyCompletion {
            completion()
        }
    }

    // MARK: - Animation entry points

    /// Finish the transition with a soft ease-out. Fast interactive pops use a
    /// one-way exit overpull: the outgoing card travels slightly past the
    /// right edge and is removed there, so it doesn't visibly spring back to
    /// the exact final edge position before teardown.
    func animateCompletion(velocity: CGFloat = 0.0, completion: @escaping () -> Void) {
        animatingCompletion = true
        currentCompletion = completion

        if shouldUseOneWayPopExit(velocity: velocity) {
            invalidateProgressDisplayLink()
            animateOneWayPopExit(velocity: velocity)
            return
        }

        let transition = makeCompletionTransition(velocity: velocity)
        animateProgressWithDisplayLink(to: 1.0, transition: transition, completion: { [weak self] in
            self?.finish()
        })
    }

    private func makeCompletionTransition(velocity: CGFloat) -> ContainedViewLayoutTransition {
        if shouldUseOneWayPopExit(velocity: velocity) {
            return makeOneWayPopExitTransition(velocity: velocity)
        }

        if abs(velocity) < .ulpOfOne, abs(progress) < .ulpOfOne {
            // Non-interactive (programmatic) completion. Slightly longer
            // than the previous 0.40s spring and explicitly ease-out, so the
            // card lands with a decelerating glide instead of a stiff snap.
            return Self.nonInteractiveCompletionTransition(direction: direction)
        } else {
            // Interactive slow release (fast flicks and already-overpulled
            // states are routed through the one-way exit path above).
            let remainingProgress = max(0.0, min(1.0, 1.0 - progress))
            let duration = 0.34 + 0.18 * Double(remainingProgress)
            return .animated(duration: duration, curve: .navigationEaseOut)
        }
    }

    private func shouldUseOneWayPopExit(velocity: CGFloat) -> Bool {
        guard isInteractive, direction == .pop else {
            return false
        }
        return velocity > fastPopOverpopVelocityThreshold || progress > overpulledPopExitProgressThreshold
    }

    private func fastPopStrength(velocity: CGFloat) -> CGFloat {
        return max(0.0, min(1.0, (max(0.0, velocity) - fastPopOverpopVelocityThreshold) / 2400.0))
    }

    private func makeOneWayPopExitTransition(velocity: CGFloat) -> ContainedViewLayoutTransition {
        let remainingProgress = max(0.0, min(1.0, 1.0 - progress))
        let flickStrength = fastPopStrength(velocity: velocity)
        let duration = max(0.30, min(0.42, 0.37 + 0.06 * Double(remainingProgress) - 0.05 * Double(flickStrength)))
        return .animated(duration: duration, curve: .navigationEaseOut)
    }

    private func oneWayPopExitOvershoot(velocity: CGFloat, width: CGFloat) -> CGFloat {
        let flickStrength = fastPopStrength(velocity: velocity)
        let velocityOvershoot = 28.0 + 44.0 * flickStrength
        let currentOvershoot = max(0.0, progress - 1.0) * width
        return max(velocityOvershoot, currentOvershoot + 16.0)
    }

    private func animateOneWayPopExit(velocity: CGFloat) {
        let transition = makeOneWayPopExitTransition(velocity: velocity)
        let size = container.bounds.size
        let width = max(1.0, size.width)
        let currentX = topView.frame.minX
        let targetX = max(currentX + 1.0, width + oneWayPopExitOvershoot(velocity: velocity, width: width))
        let flickStrength = fastPopStrength(velocity: velocity)
        let bottomOverpopX = flickStrength > 0.0 ? 4.0 + 8.0 * flickStrength : 0.0

        progress = 1.0
        progressUpdated?(1.0, transition)

        var pendingCompletions = 2
        var didFinish = false
        let markCompleted: (Bool) -> Void = { [weak self] _ in
            guard !didFinish else {
                return
            }
            pendingCompletions -= 1
            if pendingCompletions == 0 {
                didFinish = true
                self?.finish()
            }
        }

        let topFrame = CGRect(origin: CGPoint(x: floor(targetX), y: 0.0), size: size)
        let bottomFrame = CGRect(origin: .zero, size: size)
        transition.updateFrame(view: topView, frame: topFrame, completion: markCompleted)
        transition.updateFrame(view: bottomView, frame: bottomFrame, completion: markCompleted)

        if bottomOverpopX > 0.0 {
            bottomView.transform = .identity
            UIView.animateKeyframes(
                withDuration: transition.duration,
                delay: 0.0,
                options: [.beginFromCurrentState, .allowUserInteraction, .calculationModeCubic],
                animations: { [weak bottomView] in
                    UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.62) {
                        bottomView?.transform = CGAffineTransform(translationX: bottomOverpopX, y: 0.0)
                    }
                    UIView.addKeyframe(withRelativeStartTime: 0.62, relativeDuration: 0.38) {
                        bottomView?.transform = .identity
                    }
                },
                completion: { [weak bottomView] _ in
                    bottomView?.transform = .identity
                }
            )
        }

        let shadowFrame = CGRect(
            x: topFrame.minX - navigationShadowWidth,
            y: 0.0,
            width: navigationShadowWidth,
            height: size.height
        )
        transition.updateFrame(view: shadowView, frame: shadowFrame)
        transition.updateAlpha(view: shadowView, alpha: 0.0)

        transition.updateFrame(view: dimView, frame: CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height)))
        transition.updateAlpha(view: dimView, alpha: 0.0)
    }

    /// Abort the transition (e.g. interactive pan released without enough
    /// velocity/distance). Animates back to `progress = 0` and tears down.
    func animateCancel(_ completion: @escaping () -> Void) {
        currentCompletion = completion
        // Cancel: critically damped spring — snaps back to origin without
        // bouncing past 0 (no destination to overshoot toward).
        animateProgressWithDisplayLink(to: 0.0, transition: cancelTransition, completion: { [weak self] in
            guard let self else { return }
            // Remove the incoming view entirely — same controller just came
            // back to its original position.
            switch self.direction {
            case .push:
                self.topView.removeFromSuperview()
            case .pop:
                self.bottomView.removeFromSuperview()
            }
            self.cleanupOverlays()
            self.restoreTopViewCorners()
            let hook = self.currentCompletion
            self.currentCompletion = nil
            hook?()
        })
    }

    /// Instantly complete the transition without animation (used when the
    /// transition is being replaced mid-flight by a deeper one).
    func performCompletion(completion: @escaping () -> Void) {
        invalidateProgressDisplayLink()
        updateProgress(1.0, transition: .immediate, completion: { [weak self] in
            self?.finish()
            completion()
        })
    }

    /// Synchronously mark the transition as complete and tear down overlays.
    /// Used when the caller has already applied `progress = 1.0`.
    func complete() {
        invalidateProgressDisplayLink()
        animatingCompletion = true
        progress = 1.0
        finish()
    }

    // MARK: - High-refresh progress driving

    private func animateProgressWithDisplayLink(to targetProgress: CGFloat, transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        guard case let .animated(duration, curve) = transition, duration > 0.0 else {
            invalidateProgressDisplayLink()
            updateProgress(targetProgress, transition: .immediate, completion: {})
            completion()
            return
        }

        invalidateProgressDisplayLink()
        progressAnimationFrom = progress
        progressAnimationTo = targetProgress
        progressAnimationDuration = duration
        progressAnimationTiming = progressTiming(for: curve)
        progressAnimationCompletion = completion
        progressAnimationElapsed = 0.0
        progressAnimationLastTimestamp = nil

        progressUpdated?(targetProgress, transition)

        let target = NavigationProgressDisplayLinkTarget()
        target.tick = { [weak self] link in
            self?.handleProgressDisplayLink(link)
        }
        let link = CADisplayLink(target: target, selector: #selector(NavigationProgressDisplayLinkTarget.handleDisplayLink(_:)))
        if #available(iOS 15.0, *) {
            let screenMaximum = (container.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond)
            let preferred = Float(min(120, max(60, screenMaximum)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60.0, maximum: preferred, preferred: preferred)
        }
        progressDisplayLinkTarget = target
        progressDisplayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func handleProgressDisplayLink(_ link: CADisplayLink) {
        if let lastTimestamp = progressAnimationLastTimestamp {
            let delta = max(0.0, link.timestamp - lastTimestamp)
            progressAnimationElapsed += min(delta, 1.0 / 30.0)
        } else {
            progressAnimationLastTimestamp = link.timestamp
            progress = progressAnimationFrom
            updateContentProgress(progressAnimationFrom, transition: .immediate, completion: {})
            return
        }
        progressAnimationLastTimestamp = link.timestamp

        let linearProgress = progressAnimationDuration > 0.0
            ? min(1.0, progressAnimationElapsed / progressAnimationDuration)
            : 1.0
        let easedProgress = progressAnimationTiming.value(at: CGFloat(linearProgress))
        let nextProgress = progressAnimationFrom + (progressAnimationTo - progressAnimationFrom) * easedProgress
        progress = nextProgress
        updateContentProgress(nextProgress, transition: .immediate, completion: {})

        if linearProgress >= 1.0 {
            let finalProgress = progressAnimationTo
            let completion = progressAnimationCompletion
            invalidateProgressDisplayLink()
            progress = finalProgress
            updateContentProgress(finalProgress, transition: .immediate, completion: {})
            completion?()
        }
    }

    private func invalidateProgressDisplayLink() {
        progressDisplayLink?.invalidate()
        progressDisplayLink = nil
        progressDisplayLinkTarget = nil
        progressAnimationCompletion = nil
        progressAnimationElapsed = 0.0
        progressAnimationLastTimestamp = nil
    }

    private func progressTiming(for curve: ContainedViewLayoutTransitionCurve) -> NavigationProgressTiming {
        switch curve {
        case .linear:
            return .linear
        case .easeInOut:
            return .easeInOut
        case .spring, .customSpring:
            return .navigationEaseOut
        case let .custom(p1x, p1y, p2x, p2y):
            return NavigationProgressTiming(
                p1x: CGFloat(p1x),
                p1y: CGFloat(p1y),
                p2x: CGFloat(p2x),
                p2y: CGFloat(p2y)
            )
        }
    }

    // MARK: - Teardown

    private func finish() {
        invalidateProgressDisplayLink()
        cleanupOverlays()
        restoreTopViewCorners()
        let hook = currentCompletion
        currentCompletion = nil
        hook?()
    }

    private func cleanupOverlays() {
        dimView.removeFromSuperview()
        shadowView.removeFromSuperview()
    }

    private func restoreTopViewCorners() {
        guard let (clipsToBounds, cornerRadius, maskedCorners, cornerCurve) = topInitialCorners else { return }
        topView.layer.cornerCurve = cornerCurve
        topView.layer.maskedCorners = maskedCorners
        topView.clipsToBounds = clipsToBounds
        topView.layer.cornerRadius = cornerRadius
        topInitialCorners = nil
    }
}
