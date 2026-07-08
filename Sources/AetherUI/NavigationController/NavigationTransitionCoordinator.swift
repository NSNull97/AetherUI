import UIKit

// Direct port of Display framework `NavigationTransitionCoordinator` from
// submodules/Display/Source/NavigationTransitionCoordinator.swift
// adapted to pure UIKit.

enum NavigationTransitionDirection {
    case push
    case pop
}

private let navigationShadowWidth: CGFloat = 16.0
private let navigationPushTransitionDuration: Double = 0.40
private let navigationPopTransitionDuration: Double = 0.40
private let navigationStationaryPopCompletionProgress: CGFloat = 0.90
private let navigationStationaryPopVelocityTolerance: CGFloat = 140.0
private let navigationPopThrowVelocityThreshold: CGFloat = 900.0
private let navigationPopOneWayVelocityThreshold: CGFloat = 1500.0
private let navigationPopThrowVelocityRange: CGFloat = 2600.0
private let navigationSettleCurve = ContainedViewLayoutTransitionCurve.custom(0.26, 0.58, 0.28, 1.0)
private let navigationMinimumContinuationSlope: CGFloat = 0.0
private let navigationMaximumContinuationSlope: CGFloat = 4.80
private let navigationContinuationControlPointMaxY: CGFloat = 0.88
private let navigationInteractiveVelocityTailDuration: CGFloat = 0.095
private let navigationMinimumInteractiveCompletionDuration: CGFloat = 0.22
private let navigationMinimumLightThrowCompletionDuration: CGFloat = 0.30
private let navigationReleaseProgressFrameAllowance: CGFloat = 1.35
private let navigationReleaseMinimumProgressDistance: CGFloat = 1.5
private let navigationRecentVelocityMinimumSampleDuration: CFTimeInterval = 1.0 / 240.0
private let navigationRecentVelocityMaximumSampleAge: CFTimeInterval = 0.14

private func navigationTransitionPosition(_ value: CGFloat) -> CGFloat {
    return value
}

private func navigationSmootherStep(_ edge0: CGFloat, _ edge1: CGFloat, _ value: CGFloat) -> CGFloat {
    guard edge0 != edge1 else {
        return value < edge0 ? 0.0 : 1.0
    }
    let t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

private func navigationLerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
    return from + (to - from) * t
}

private func navigationNonInteractiveTransitionDuration(for direction: NavigationTransitionDirection) -> Double {
    switch direction {
    case .push:
        return navigationPushTransitionDuration
    case .pop:
        return navigationPopTransitionDuration
    }
}

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
    static let navigationSettle = NavigationProgressTiming(p1x: 0.26, p1y: 0.58, p2x: 0.28, p2y: 1.0)

    func withInitialSlope(_ slope: CGFloat) -> NavigationProgressTiming {
        let matchedSlope = max(navigationMinimumContinuationSlope, min(navigationMaximumContinuationSlope, slope))
        let matchedP1X = matchedSlope > .ulpOfOne
            ? min(p1x, navigationContinuationControlPointMaxY / matchedSlope)
            : p1x
        return NavigationProgressTiming(
            p1x: matchedP1X,
            p1y: matchedSlope * matchedP1X,
            p2x: p2x,
            p2y: p2y
        )
    }

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
    private var previousInteractiveProgressSample: (progress: CGFloat, timestamp: CFTimeInterval)?
    private var currentInteractiveProgressSample: (progress: CGFloat, timestamp: CFTimeInterval)?

    var completionTransition: ContainedViewLayoutTransition {
        return makeCompletionTransition(velocity: 0.0)
    }

    static func nonInteractiveCompletionTransition(direction: NavigationTransitionDirection) -> ContainedViewLayoutTransition {
        return .animated(duration: navigationNonInteractiveTransitionDuration(for: direction), curve: navigationSettleCurve)
    }

    func completionTransition(velocity: CGFloat) -> ContainedViewLayoutTransition {
        return makeCompletionTransition(velocity: effectiveCompletionVelocity(for: velocity))
    }

    var cancelTransition: ContainedViewLayoutTransition {
        return .animated(duration: navigationPopTransitionDuration, curve: navigationSettleCurve)
    }

    func shouldCompleteInteractivePop(progress proposedProgress: CGFloat? = nil, velocity: CGFloat) -> Bool {
        guard isInteractive, direction == .pop else {
            return progress >= 1.0
        }
        if velocity < -navigationStationaryPopVelocityTolerance {
            return false
        }
        if effectiveCompletionVelocity(for: velocity) > navigationPopThrowVelocityThreshold {
            return true
        }
        let effectiveProgress = proposedProgress ?? progress
        return effectiveProgress >= navigationStationaryPopCompletionProgress
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
        setProgress(0.0, transition: .immediate, recordsInteractiveSample: false, completion: {})
    }

    deinit {
        invalidateProgressDisplayLink()
    }

    // MARK: - Progress

    /// Maps `progress` (0 → 1) to the on-screen position of the transition.
    /// Mirrors the original: `position = 1 - progress` for `.push`, `position =
    /// progress` for `.pop`. All geometry is driven by `position`.
    func updateProgress(_ progress: CGFloat, transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        setProgress(progress, transition: transition, recordsInteractiveSample: true, completion: completion)
    }

    func updateProgressForRelease(_ proposedProgress: CGFloat, velocity: CGFloat) {
        guard isInteractive, direction == .pop else {
            updateProgress(proposedProgress, transition: .immediate, completion: {})
            return
        }

        let delta = proposedProgress - progress
        guard abs(delta) > .ulpOfOne else {
            return
        }

        let width = max(1.0, container.bounds.width)
        let frameProgress = abs(velocity) / width * CGFloat(preferredProgressFrameDuration())
        let minimumProgress = navigationReleaseMinimumProgressDistance / width
        let maximumDelta = max(minimumProgress, frameProgress * navigationReleaseProgressFrameAllowance)
        let clampedDelta = max(-maximumDelta, min(maximumDelta, delta))
        setProgress(progress + clampedDelta, transition: .immediate, recordsInteractiveSample: false, completion: {})
    }

    private func setProgress(_ progress: CGFloat, transition: ContainedViewLayoutTransition, recordsInteractiveSample: Bool, completion: @escaping () -> Void) {
        self.progress = progress
        if recordsInteractiveSample {
            recordInteractiveProgressSample(progress)
        }
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
        let topFrame = CGRect(origin: CGPoint(x: navigationTransitionPosition(position * size.width), y: 0.0), size: size)
        let bottomFrame: CGRect
        if isFlat {
            bottomFrame = CGRect(origin: CGPoint(x: -navigationTransitionPosition((1.0 - position) * size.width), y: 0.0), size: size)
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

        let effectiveVelocity = effectiveCompletionVelocity(for: velocity)
        if shouldUseOneWayPopExit(velocity: effectiveVelocity) {
            invalidateProgressDisplayLink()
            animateOneWayPopExit(velocity: effectiveVelocity)
            return
        }

        let transition = makeCompletionTransition(velocity: effectiveVelocity)
        let progressVelocity = continuationVelocity(for: effectiveVelocity) / max(1.0, container.bounds.width)
        animateProgressWithDisplayLink(to: 1.0, transition: transition, initialVelocity: progressVelocity, completion: { [weak self] in
            self?.finish()
        })
    }

    private func makeCompletionTransition(velocity: CGFloat) -> ContainedViewLayoutTransition {
        if shouldUseOneWayPopExit(velocity: velocity) {
            return makeOneWayPopExitTransition(velocity: velocity)
        }

        if abs(velocity) < .ulpOfOne, abs(progress) < .ulpOfOne {
            return Self.nonInteractiveCompletionTransition(direction: direction)
        } else {
            let duration = interactiveCompletionDuration(velocity: velocity)
            return .animated(duration: duration, curve: navigationSettleCurve)
        }
    }

    private func shouldUseOneWayPopExit(velocity: CGFloat) -> Bool {
        guard isInteractive, direction == .pop else {
            return false
        }
        return velocity > navigationPopOneWayVelocityThreshold
    }

    private func fastPopStrength(velocity: CGFloat) -> CGFloat {
        let rawStrength = max(0.0, min(1.0, (max(0.0, velocity) - navigationPopOneWayVelocityThreshold) / navigationPopThrowVelocityRange))
        return rawStrength * rawStrength * (3.0 - 2.0 * rawStrength)
    }

    private func throwCompletionStrength(velocity: CGFloat) -> CGFloat {
        return navigationSmootherStep(navigationPopThrowVelocityThreshold, navigationPopOneWayVelocityThreshold, max(0.0, velocity))
    }

    private func continuationVelocity(for velocity: CGFloat) -> CGFloat {
        guard isInteractive, direction == .pop, velocity > navigationPopThrowVelocityThreshold else {
            return velocity
        }
        let strength = throwCompletionStrength(velocity: velocity)
        let scale = navigationLerp(0.78, 1.0, strength)
        return velocity * scale
    }

    private func recordInteractiveProgressSample(_ progress: CGFloat) {
        guard isInteractive, direction == .pop, !animatingCompletion else {
            return
        }

        let timestamp = CACurrentMediaTime()
        if let currentInteractiveProgressSample, abs(currentInteractiveProgressSample.progress - progress) < 0.0005 {
            return
        }
        previousInteractiveProgressSample = currentInteractiveProgressSample
        currentInteractiveProgressSample = (progress, timestamp)
    }

    private func recentInteractiveProgressVelocity() -> CGFloat? {
        guard isInteractive, direction == .pop,
              let previousInteractiveProgressSample,
              let currentInteractiveProgressSample else {
            return nil
        }

        let sampleAge = CACurrentMediaTime() - currentInteractiveProgressSample.timestamp
        guard sampleAge <= navigationRecentVelocityMaximumSampleAge else {
            return nil
        }

        let sampleDuration = currentInteractiveProgressSample.timestamp - previousInteractiveProgressSample.timestamp
        guard sampleDuration >= navigationRecentVelocityMinimumSampleDuration else {
            return nil
        }

        let progressDelta = currentInteractiveProgressSample.progress - previousInteractiveProgressSample.progress
        guard progressDelta > 0.0 else {
            return nil
        }

        return progressDelta / CGFloat(sampleDuration)
    }

    private func effectiveCompletionVelocity(for velocity: CGFloat) -> CGFloat {
        guard isInteractive, direction == .pop else {
            return velocity
        }

        let recognizerVelocity = max(0.0, velocity)
        let sampledVelocity = (recentInteractiveProgressVelocity() ?? 0.0) * max(1.0, container.bounds.width)
        guard sampledVelocity > 0.0 else {
            return velocity
        }

        return max(recognizerVelocity, sampledVelocity)
    }

    private func makeOneWayPopExitTransition(velocity: CGFloat) -> ContainedViewLayoutTransition {
        return .animated(duration: interactiveCompletionDuration(velocity: velocity), curve: navigationSettleCurve)
    }

    private func interactiveCompletionDuration(velocity: CGFloat) -> Double {
        guard isInteractive, direction == .pop, velocity > navigationPopThrowVelocityThreshold else {
            return navigationPopTransitionDuration
        }

        let remainingProgress = max(0.0, min(1.0, 1.0 - progress))
        let remainingDistance = remainingProgress * max(1.0, container.bounds.width)
        let inertialDuration = remainingDistance / max(1.0, velocity) + navigationInteractiveVelocityTailDuration
        let throwStrength = throwCompletionStrength(velocity: velocity)
        let minimumDuration = navigationLerp(
            navigationMinimumLightThrowCompletionDuration,
            navigationMinimumInteractiveCompletionDuration,
            throwStrength
        )
        return Double(max(minimumDuration, min(CGFloat(navigationPopTransitionDuration), inertialDuration)))
    }

    private func oneWayPopExitOvershoot(velocity: CGFloat, width: CGFloat) -> CGFloat {
        let flickStrength = fastPopStrength(velocity: velocity)
        let velocityOvershoot = 56.0 * flickStrength
        let currentOvershoot = max(0.0, progress - 1.0) * width
        return max(velocityOvershoot, currentOvershoot)
    }

    private func velocityMatchedTiming(from: CGFloat, to: CGFloat, duration: Double, velocity: CGFloat, baseTiming: NavigationProgressTiming = .navigationSettle, allowsZeroVelocityHandoff: Bool = false) -> NavigationProgressTiming {
        let distance = to - from
        guard duration > 0.0, abs(distance) > .ulpOfOne else {
            return baseTiming
        }

        let direction: CGFloat = distance >= 0.0 ? 1.0 : -1.0
        let directedVelocity = velocity * direction
        guard directedVelocity > 0.0 else {
            return allowsZeroVelocityHandoff ? baseTiming.withInitialSlope(0.0) : baseTiming
        }

        let desiredSlope = directedVelocity * CGFloat(duration) / abs(distance)
        return baseTiming.withInitialSlope(desiredSlope)
    }

    private func animateOneWayPopExit(velocity: CGFloat) {
        invalidateProgressDisplayLink()

        let transition = makeOneWayPopExitTransition(velocity: velocity)
        let size = container.bounds.size
        let width = max(1.0, size.width)
        let startProgress = progress
        let startTopX = topView.frame.minX
        let startBottomX = bottomView.frame.minX
        let targetX = max(startTopX + 1.0, width + oneWayPopExitOvershoot(velocity: velocity, width: width))
        let flickStrength = fastPopStrength(velocity: velocity)
        let currentOverpullX = max(0.0, progress - 1.0) * width
        let bottomRubberbandAmplitude = max(
            4.0 + 16.0 * flickStrength,
            min(20.0, currentOverpullX * 0.12)
        )
        let duration = max(0.001, transition.duration)
        let topExitProgress = max(0.50, 0.64 - 0.10 * flickStrength)
        let timing = velocityMatchedTiming(
            from: startTopX,
            to: targetX,
            duration: duration * Double(topExitProgress),
            velocity: velocity
        )

        let applyFrame: (NavigationTransitionCoordinator, CGFloat, Bool) -> Void = { coordinator, linearProgress, finished in
            let clampedProgress = max(0.0, min(1.0, linearProgress))
            let externalProgress = finished ? 1.0 : startProgress + (1.0 - startProgress) * clampedProgress
            let topLinearProgress = min(1.0, clampedProgress / topExitProgress)
            let easedProgress = timing.value(at: topLinearProgress)
            let topX = finished
                ? targetX
                : startTopX + (targetX - startTopX) * easedProgress
            let bottomCatchUpProgress = navigationSmootherStep(0.0, 0.42, clampedProgress)
            let bottomPullProgress = navigationSmootherStep(0.20, topExitProgress, clampedProgress)
            let bottomSettleProgress = navigationSmootherStep(topExitProgress, 1.0, clampedProgress)
            let bottomBaseX = startBottomX * (1.0 - bottomCatchUpProgress)
            let bottomRubberbandX = bottomRubberbandAmplitude * bottomPullProgress * (1.0 - bottomSettleProgress)
            let bottomX = finished ? 0.0 : bottomBaseX + bottomRubberbandX

            let topFrame = CGRect(origin: CGPoint(x: navigationTransitionPosition(topX), y: 0.0), size: size)
            let bottomFrame = CGRect(origin: CGPoint(x: navigationTransitionPosition(bottomX), y: 0.0), size: size)
            coordinator.topView.frame = topFrame
            coordinator.bottomView.transform = .identity
            coordinator.bottomView.frame = bottomFrame

            coordinator.shadowView.frame = CGRect(
                x: topFrame.minX - navigationShadowWidth,
                y: 0.0,
                width: navigationShadowWidth,
                height: size.height
            )
            coordinator.shadowView.alpha = finished ? 0.0 : max(0.0, 1.0 - topFrame.minX / width) * 0.9
            coordinator.dimView.frame = CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height))
            coordinator.dimView.alpha = 0.0
            coordinator.progress = externalProgress
            coordinator.progressUpdated?(externalProgress, .immediate)
        }

        var elapsed: CFTimeInterval = 0.0
        applyFrame(self, 0.0, false)
        var lastTimestamp = CACurrentMediaTime()
        let target = NavigationProgressDisplayLinkTarget()
        target.tick = { [weak self] link in
            guard let self else {
                return
            }
            let frameTimestamp = link.targetTimestamp > link.timestamp ? link.targetTimestamp : link.timestamp
            let maximumFrameDelta = link.duration > 0.0 ? link.duration : 1.0 / 60.0
            let delta = min(max(0.0, frameTimestamp - lastTimestamp), maximumFrameDelta)
            elapsed += min(delta, 1.0 / 30.0)
            lastTimestamp = frameTimestamp

            if elapsed >= duration {
                applyFrame(self, 1.0, true)
                self.finish()
            } else {
                applyFrame(self, CGFloat(elapsed / duration), false)
            }
        }
        let link = CADisplayLink(target: target, selector: #selector(NavigationProgressDisplayLinkTarget.handleDisplayLink(_:)))
        if #available(iOS 15.0, *) {
            let preferred = Float(preferredProgressFramesPerSecond())
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60.0, maximum: preferred, preferred: preferred)
        }
        progressDisplayLinkTarget = target
        progressDisplayLink = link
        link.add(to: .main, forMode: .common)
    }

    /// Abort the transition (e.g. interactive pan released without enough
    /// velocity/distance). Animates back to `progress = 0` and tears down.
    func animateCancel(_ completion: @escaping () -> Void) {
        currentCompletion = completion
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

    private func animateProgressWithDisplayLink(to targetProgress: CGFloat, transition: ContainedViewLayoutTransition, initialVelocity: CGFloat = 0.0, completion: @escaping () -> Void) {
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
        let baseTiming = progressTiming(for: curve)
        progressAnimationTiming = velocityMatchedTiming(
            from: progress,
            to: targetProgress,
            duration: duration,
            velocity: initialVelocity,
            baseTiming: baseTiming,
            allowsZeroVelocityHandoff: isInteractive
        )
        progressAnimationCompletion = completion
        progressAnimationElapsed = 0.0
        progressAnimationLastTimestamp = nil

        progressAnimationLastTimestamp = CACurrentMediaTime()

        let target = NavigationProgressDisplayLinkTarget()
        target.tick = { [weak self] link in
            self?.handleProgressDisplayLink(link)
        }
        let link = CADisplayLink(target: target, selector: #selector(NavigationProgressDisplayLinkTarget.handleDisplayLink(_:)))
        if #available(iOS 15.0, *) {
            let preferred = Float(preferredProgressFramesPerSecond())
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60.0, maximum: preferred, preferred: preferred)
        }
        progressDisplayLinkTarget = target
        progressDisplayLink = link
        link.add(to: .main, forMode: .common)
    }

    private func handleProgressDisplayLink(_ link: CADisplayLink) {
        let frameTimestamp = link.targetTimestamp > link.timestamp ? link.targetTimestamp : link.timestamp
        let maximumFrameDelta = link.duration > 0.0 ? link.duration : 1.0 / 60.0
        let frameDelta: CFTimeInterval
        if let lastTimestamp = progressAnimationLastTimestamp {
            frameDelta = min(max(0.0, frameTimestamp - lastTimestamp), maximumFrameDelta)
        } else {
            frameDelta = maximumFrameDelta
        }
        if advanceProgressAnimation(by: frameDelta) {
            return
        }
        progressAnimationLastTimestamp = frameTimestamp
    }

    @discardableResult
    private func advanceProgressAnimation(by delta: CFTimeInterval) -> Bool {
        progressAnimationElapsed += min(max(0.0, delta), 1.0 / 30.0)

        let linearProgress = progressAnimationDuration > 0.0
            ? min(1.0, progressAnimationElapsed / progressAnimationDuration)
            : 1.0
        let easedProgress = progressAnimationTiming.value(at: CGFloat(linearProgress))
        let nextProgress = progressAnimationFrom + (progressAnimationTo - progressAnimationFrom) * easedProgress
        progress = nextProgress
        updateContentProgress(nextProgress, transition: .immediate, completion: {})
        progressUpdated?(nextProgress, .immediate)

        if linearProgress >= 1.0 {
            let finalProgress = progressAnimationTo
            let completion = progressAnimationCompletion
            invalidateProgressDisplayLink()
            progress = finalProgress
            updateContentProgress(finalProgress, transition: .immediate, completion: {})
            progressUpdated?(finalProgress, .immediate)
            completion?()
            return true
        }
        return false
    }

    private func preferredProgressFramesPerSecond() -> Int {
        let screenMaximum = container.window?.screen.maximumFramesPerSecond ?? UIScreen.main.maximumFramesPerSecond
        return min(120, max(60, screenMaximum))
    }

    private func preferredProgressFrameDuration() -> CFTimeInterval {
        return 1.0 / CFTimeInterval(preferredProgressFramesPerSecond())
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
