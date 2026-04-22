import UIKit

final class CrystalModalPresentationController: UIPresentationController, UIGestureRecognizerDelegate {
    private let dimView = UIView()
    private var panGesture: UIPanGestureRecognizer?

    private var detent: CrystalModalController.Detent = .stage1

    // Drag state (per gesture).
    private var dragStartFrame: CGRect = .zero
    private var dragStartDetent: CrystalModalController.Detent = .stage1
    private var dragDriving: Bool = false
    private var dragScrollAtStart: Bool = true
    private var dragStartedInScrollContent: Bool = false
    private var settleAnimating: Bool = false

    // Settle animation state — driven manually via CADisplayLink so every
    // glass/tint/mask update happens in the same run-loop tick as the root
    // frame change. UIView.animate spawned a nested animation context for
    // the glass internals that desynced against the outer spring.
    private var settleLink: CADisplayLink?
    private var settleStartTime: CFTimeInterval = 0
    private var settleDuration: CFTimeInterval = 0
    private var settleStartFrame: CGRect = .zero
    private var settleTargetFrame: CGRect = .zero
    private var settleStartProgress: CGFloat = 0
    private var settleTargetProgress: CGFloat = 0
    private var settleStartDim: CGFloat = 0
    private var settleTargetDim: CGFloat = 0

    lazy var deviceCornerRadius: CGFloat = {
        if let window = presentingViewController.view.window,
           let value = window.screen.value(forKey: "_displayCornerRadius") as? CGFloat,
           value > 0 {
            return value
        }
        return 38.0
    }()

    private var modalController: CrystalModalController? {
        presentedViewController as? CrystalModalController
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        return frame(for: detent, in: container.bounds)
    }

    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()
        guard let container = containerView else { return }

        detent = modalController?.config.resolvedInitialDetent ?? .stage1

        dimView.backgroundColor = UIColor(white: 0.0, alpha: 1.0)
        dimView.alpha = 0.0
        dimView.frame = container.bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDimTap))
        dimView.addGestureRecognizer(tap)
        container.addSubview(dimView)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        presentedView?.addGestureRecognizer(pan)
        panGesture = pan

        modalController?.applyCurrentDetent(detent)
        // Tint overlay reflects the current detent (stage2 → full tint).
        modalController?.applyDetentProgress(detent == .stage2 ? 1.0 : 0.0)
        dimView.alpha = dimAlpha(forProgress: detent == .stage2 ? 1.0 : 0.0)
    }

    override func dismissalTransitionWillBegin() {
        super.dismissalTransitionWillBegin()
        stopSettleLink()
        if let coordinator = presentingViewController.transitionCoordinator {
            coordinator.animate(alongsideTransition: { [weak self] _ in
                self?.dimView.alpha = 0.0
            })
        } else {
            dimView.alpha = 0.0
        }
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        super.dismissalTransitionDidEnd(completed)
        if completed {
            dimView.removeFromSuperview()
        }
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        dimView.frame = containerView?.bounds ?? .zero
        if !dragDriving && !settleAnimating {
            presentedView?.frame = frameOfPresentedViewInContainerView
        }
    }

    // MARK: - Detent API

    func setDetent(_ newDetent: CrystalModalController.Detent, animated: Bool) {
        guard detent != newDetent else { return }
        guard modalController?.config.detents.contains(newDetent) ?? true else { return }
        animateTo(detent: newDetent, container: containerView, initialVelocityY: 0.0, animated: animated)
    }

    private var allowedDetents: Set<CrystalModalController.Detent> {
        modalController?.config.detents ?? [.stage1, .stage2]
    }

    // MARK: - Frame calc

    private func frame(for detent: CrystalModalController.Detent, in bounds: CGRect) -> CGRect {
        let cfg = modalController?.config ?? .init()
        let safeArea = containerView?.safeAreaInsets ?? presentingViewController.view.safeAreaInsets
        switch detent {
        case .stage1:
            let bottom = bounds.height - cfg.bottomInsetStage1
            let configuredTop = safeArea.top + cfg.topInsetStage1
            let minimumHeight = bounds.height * 0.5
            let height = max(bottom - configuredTop, minimumHeight)
            let top = bottom - height
            return CGRect(
                x: cfg.sideInset,
                y: top,
                width: bounds.width - cfg.sideInset * 2.0,
                height: max(0.0, height)
            )
        case .stage2:
            let bottom = bounds.height - cfg.bottomInsetStage2
            let top = safeArea.top + cfg.topInsetStage2
            return CGRect(
                x: 0.0,
                y: top,
                width: bounds.width,
                height: max(0.0, bottom - top)
            )
        }
    }

    // MARK: - Dim tap

    @objc private func handleDimTap() {
        presentedViewController.dismiss(animated: true)
    }

    // MARK: - Pan gesture

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = containerView,
              let presentedView else {
            return
        }
        let velocity = gesture.velocity(in: container)

        switch gesture.state {
        case .began:
            cancelSettleAnimationIfNeeded(container: container)
            dragStartFrame = presentedView.frame
            dragStartDetent = nearestDetent(to: presentedView.frame, in: container.bounds)
            dragStartedInScrollContent = gestureStartedInPrimaryScrollContent(gesture)
            if let scrollView = modalController?.primaryScrollView {
                dragScrollAtStart = isPrimaryScrollViewAtTop(scrollView)
            } else {
                dragScrollAtStart = true
            }
            // Driving decision is deferred to `.changed` — we need the
            // drag direction before deciding whether scroll or sheet owns
            // this gesture.
            dragDriving = false

        case .changed:
            let translation = gesture.translation(in: container)
            let draggingDown = translation.y > 0
            let draggingUp = translation.y < 0

            if !dragDriving {
                dragDriving = shouldSheetDrive(
                    draggingDown: draggingDown,
                    draggingUp: draggingUp
                )
                if dragDriving, let scrollView = modalController?.primaryScrollView {
                    // Cancel the scroll's in-progress pan so it stops
                    // tracking this touch stream. Without this the scroll
                    // still processes motion alongside the sheet for the
                    // rest of the gesture — user sees the sheet expand
                    // while the content simultaneously bounces.
                    let scrollPan = scrollView.panGestureRecognizer
                    if scrollPan.isEnabled {
                        scrollPan.isEnabled = false
                        scrollPan.isEnabled = true
                    }
                    // Snap the scroll back to its top so nothing is
                    // mid-scroll when the sheet takes over.
                    let topOffset = scrollTopOffset(for: scrollView)
                    if scrollView.contentOffset.y != topOffset {
                        scrollView.contentOffset.y = topOffset
                    }
                }
            }

            guard dragDriving else {
                // Scroll handles this gesture; we stay out of the way.
                return
            }

            applyDrag(translation: translation, container: container, draggingDown: draggingDown, draggingUp: draggingUp)

        case .ended, .cancelled, .failed:
            if !dragDriving {
                return
            }

            dragDriving = false
            let translation = gesture.translation(in: container)
            finishDrag(translation: translation, velocity: velocity, container: container)

        default:
            break
        }
    }

    /// Decide at the first `.changed` whether the sheet should own this
    /// pan or leave it to the scroll view. Sheet drives when:
    /// - the touch started outside the primary scroll view, or
    /// - there is no primary scroll view at all, or
    /// - at stage1, the drag is upward (to stage2) OR downward AND the
    ///   scroll was at its top when the drag began, or
    /// - at stage2, the drag is downward AND the scroll was at its top.
    /// Otherwise scroll owns the gesture.
    private func shouldSheetDrive(draggingDown: Bool, draggingUp: Bool) -> Bool {
        if !dragStartedInScrollContent { return true }
        guard modalController?.primaryScrollView != nil else { return true }
        switch dragStartDetent {
        case .stage1:
            if draggingUp {
                // Expand-drag always beats scroll at stage1 (the sheet is
                // the natural handle, not the content).
                return allowedDetents.contains(.stage2) || allowedDetents == [.stage1]
            }
            // Downward: only take the gesture when scroll is at the top
            // (otherwise user is scrolling the content back up).
            return dragScrollAtStart
        case .stage2:
            if draggingUp {
                return false
            }
            return dragScrollAtStart
        }
    }

    private func applyDrag(translation: CGPoint, container: UIView, draggingDown: Bool, draggingUp: Bool) {
        guard let presentedView else { return }
        let bounds = container.bounds
        let stage1 = frame(for: .stage1, in: bounds)
        let stage2 = frame(for: .stage2, in: bounds)
        let allowed = allowedDetents

        var newFrame = dragStartFrame
        var progress: CGFloat
        switch dragStartDetent {
        case .stage1:
            if draggingUp {
                if allowed.contains(.stage2) {
                    // Grow toward stage2 with the bottom pinned.
                    let distance = transitionDistance(from: stage1, to: stage2)
                    let t = max(0.0, min(1.0, -translation.y / distance))
                    newFrame = expandFrame(from: stage1, to: stage2, t: t)
                    progress = t
                } else {
                    // Stage2 not allowed — resist with a rubberband so the
                    // sheet doesn't go anywhere past its detent.
                    let resistance = Self.rubberband(offset: -translation.y, dimension: 100.0)
                    newFrame = stage1.offsetBy(dx: 0.0, dy: -resistance)
                    progress = 0.0
                }
            } else {
                // Dismiss-drag: translate downward, keep size.
                newFrame = stage1.offsetBy(dx: 0.0, dy: max(0.0, translation.y))
                progress = 0.0
            }
        case .stage2:
            if draggingDown {
                if allowed.contains(.stage1) {
                    let distance = transitionDistance(from: stage1, to: stage2)
                    let t = max(0.0, min(1.0, translation.y / distance))
                    newFrame = collapseFrame(from: stage2, to: stage1, t: t)
                    progress = 1.0 - t
                } else {
                    // Stage1 not allowed — dismiss-drag straight from stage2:
                    // translate the whole sheet down like a single-detent sheet.
                    newFrame = stage2.offsetBy(dx: 0.0, dy: max(0.0, translation.y))
                    progress = 1.0
                }
            } else {
                // Drag up from stage2 — no-op.
                newFrame = stage2
                progress = 1.0
            }
        }

        presentedView.frame = newFrame
        modalController?.applyDetentProgress(progress)
        dimView.alpha = dimAlpha(forProgress: progress)
    }

    private static func rubberband(offset: CGFloat, dimension: CGFloat, coefficient: CGFloat = 0.55) -> CGFloat {
        guard offset > 0, dimension > 0 else { return 0 }
        return (1.0 - 1.0 / ((offset * coefficient / dimension) + 1.0)) * dimension
    }

    private func finishDrag(translation: CGPoint, velocity: CGPoint, container: UIView) {
        let dismissVelocityThreshold: CGFloat = 800.0
        let expandVelocityThreshold: CGFloat = 400.0
        let expandProgressThreshold: CGFloat = 0.4
        let collapseProgressThreshold: CGFloat = 0.4
        let dismissTranslationThreshold: CGFloat = 140.0

        let bounds = container.bounds
        let stage1 = frame(for: .stage1, in: bounds)
        let stage2 = frame(for: .stage2, in: bounds)
        let allowed = allowedDetents

        switch dragStartDetent {
        case .stage1:
            if translation.y > 0 {
                if velocity.y > dismissVelocityThreshold {
                    animateDismiss()
                } else {
                    animateTo(detent: .stage1, container: container, initialVelocityY: velocity.y)
                }
            } else {
                guard allowed.contains(.stage2) else {
                    animateTo(detent: .stage1, container: container, initialVelocityY: velocity.y)
                    return
                }
                let distance = transitionDistance(from: stage1, to: stage2)
                let progress = max(0.0, min(1.0, -translation.y / distance))
                if progress > expandProgressThreshold || velocity.y < -expandVelocityThreshold {
                    animateTo(detent: .stage2, container: container, initialVelocityY: velocity.y)
                } else {
                    animateTo(detent: .stage1, container: container, initialVelocityY: velocity.y)
                }
            }
        case .stage2:
            if translation.y > 0 {
                if !allowed.contains(.stage1) {
                    // Single-detent stage2: downward drag is a dismiss
                    // candidate. Dismiss on velocity OR on a significant
                    // translation, otherwise snap back.
                    if velocity.y > dismissVelocityThreshold || translation.y > dismissTranslationThreshold {
                        animateDismiss()
                    } else {
                        animateTo(detent: .stage2, container: container, initialVelocityY: velocity.y)
                    }
                    return
                }
                let distance = transitionDistance(from: stage1, to: stage2)
                let progress = max(0.0, min(1.0, translation.y / distance))
                if progress > collapseProgressThreshold || velocity.y > expandVelocityThreshold {
                    animateTo(detent: .stage1, container: container, initialVelocityY: velocity.y)
                } else {
                    animateTo(detent: .stage2, container: container, initialVelocityY: velocity.y)
                }
            } else {
                animateTo(detent: .stage2, container: container, initialVelocityY: velocity.y)
            }
        }
    }

    private func animateTo(
        detent targetDetent: CrystalModalController.Detent,
        container: UIView?,
        initialVelocityY: CGFloat,
        animated: Bool = true
    ) {
        guard let container else {
            detent = targetDetent
            modalController?.applyCurrentDetent(targetDetent)
            modalController?.applyDetentProgress(targetDetent == .stage2 ? 1.0 : 0.0)
            return
        }

        stopSettleLink()

        let currentFrame = presentedView?.frame ?? frame(for: detent, in: container.bounds)
        let currentProgress = progress(for: currentFrame, in: container.bounds)
        let currentDimAlpha = dimView.alpha

        self.detent = targetDetent
        modalController?.applyCurrentDetent(targetDetent)

        let targetFrame = frame(for: targetDetent, in: container.bounds)
        let targetProgress: CGFloat = targetDetent == .stage2 ? 1.0 : 0.0
        let targetDim = dimAlpha(forProgress: targetProgress)

        if !animated {
            presentedView?.frame = targetFrame
            modalController?.applyDetentProgress(targetProgress)
            dimView.alpha = targetDim
            return
        }

        let isCollapsingTowardStage1 = targetDetent == .stage1 && currentFrame.minY < targetFrame.minY
        let baseDuration: CFTimeInterval = isCollapsingTowardStage1 ? 0.52 : 0.58
        // Scale down when the distance remaining is small — keep brief
        // corrections crisp rather than padding them out to the full
        // duration.
        let distance = abs(targetFrame.minY - currentFrame.minY)
        let fullDistance = abs(frame(for: .stage2, in: container.bounds).minY - frame(for: .stage1, in: container.bounds).minY)
        let durationScale = fullDistance > 0 ? max(0.5, min(1.0, distance / fullDistance)) : 1.0

        settleStartFrame = currentFrame
        settleTargetFrame = targetFrame
        settleStartProgress = currentProgress
        settleTargetProgress = targetProgress
        settleStartDim = currentDimAlpha
        settleTargetDim = targetDim
        settleDuration = baseDuration * durationScale
        settleStartTime = CACurrentMediaTime()
        settleAnimating = true

        let link = CADisplayLink(target: self, selector: #selector(tickSettleLink))
        if #available(iOS 15.0, *) {
            // Opt into ProMotion 120Hz. Requires the host app's Info.plist
            // to include `CADisableMinimumFrameDurationOnPhone = YES`
            // (otherwise iOS caps the display link at 60Hz regardless of
            // the range).
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60.0, maximum: 120.0, preferred: 120.0)
        }
        link.add(to: .main, forMode: .common)
        settleLink = link
    }

    @objc private func tickSettleLink() {
        guard settleAnimating else {
            stopSettleLink()
            return
        }
        let elapsed = CACurrentMediaTime() - settleStartTime
        let raw: CGFloat = settleDuration > 0 ? max(0.0, min(1.0, CGFloat(elapsed / settleDuration))) : 1.0
        let t = Self.easeOutSpring(raw)

        let f = CGRect(
            x: settleStartFrame.origin.x + (settleTargetFrame.origin.x - settleStartFrame.origin.x) * t,
            y: settleStartFrame.origin.y + (settleTargetFrame.origin.y - settleStartFrame.origin.y) * t,
            width: settleStartFrame.size.width + (settleTargetFrame.size.width - settleStartFrame.size.width) * t,
            height: settleStartFrame.size.height + (settleTargetFrame.size.height - settleStartFrame.size.height) * t
        )
        presentedView?.frame = f

        let prog = settleStartProgress + (settleTargetProgress - settleStartProgress) * t
        modalController?.applyDetentProgress(prog)
        dimView.alpha = settleStartDim + (settleTargetDim - settleStartDim) * t

        if raw >= 1.0 {
            stopSettleLink()
        }
    }

    private func stopSettleLink() {
        settleLink?.invalidate()
        settleLink = nil
        settleAnimating = false
    }

    /// Underdamped spring step response — ~8% overshoot with a visible
    /// bounce-back. Fully settled by t = 1.
    private static func easeOutSpring(_ t: CGFloat) -> CGFloat {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        let zeta: CGFloat = 0.62
        let omega: CGFloat = 9.5
        let omegaD = omega * sqrt(max(0.0, 1.0 - zeta * zeta))
        let envelope = exp(-zeta * omega * t)
        return 1.0 - envelope * (cos(omegaD * t) + (zeta * omega / omegaD) * sin(omegaD * t))
    }

    private func animateDismiss() {
        presentedViewController.dismiss(animated: true)
    }

    private func cancelSettleAnimationIfNeeded(container: UIView) {
        guard settleAnimating else { return }

        stopSettleLink()

        guard let currentFrame = presentedView?.frame else { return }
        let snappedDetent = nearestDetent(to: currentFrame, in: container.bounds)
        let currentProgress = progress(for: currentFrame, in: container.bounds)
        detent = snappedDetent
        modalController?.applyCurrentDetent(snappedDetent)
        modalController?.applyDetentProgress(currentProgress)
        dimView.alpha = dimAlpha(forProgress: currentProgress)
    }

    private func gestureStartedInPrimaryScrollContent(_ gesture: UIGestureRecognizer) -> Bool {
        guard let presentedView,
              let scrollView = modalController?.primaryScrollView else {
            return false
        }
        let location = gesture.location(in: presentedView)
        guard let hitView = presentedView.hitTest(location, with: nil) else {
            return false
        }
        return hitView.isDescendant(of: scrollView)
    }

    private func isPrimaryScrollViewAtTop(_ scrollView: UIScrollView) -> Bool {
        scrollView.contentOffset.y - scrollTopOffset(for: scrollView) <= 0.5
    }

    private func nearestDetent(to frame: CGRect, in bounds: CGRect) -> CrystalModalController.Detent {
        let allowed = allowedDetents
        if allowed == [.stage1] { return .stage1 }
        if allowed == [.stage2] { return .stage2 }
        let stage1 = self.frame(for: .stage1, in: bounds)
        let stage2 = self.frame(for: .stage2, in: bounds)
        let stage1Distance = abs(frame.minY - stage1.minY)
        let stage2Distance = abs(frame.minY - stage2.minY)
        return stage1Distance <= stage2Distance ? .stage1 : .stage2
    }

    private func progress(for frame: CGRect, in bounds: CGRect) -> CGFloat {
        let stage1 = self.frame(for: .stage1, in: bounds)
        let stage2 = self.frame(for: .stage2, in: bounds)
        let distance = transitionDistance(from: stage1, to: stage2)
        return max(0.0, min(1.0, (stage1.minY - frame.minY) / distance))
    }

    private func scrollTopOffset(for sv: UIScrollView) -> CGFloat {
        return -sv.adjustedContentInset.top
    }

    /// Interpolate dim alpha between the two detents' configured values.
    /// Progress 0 → stage1, 1 → stage2.
    private func dimAlpha(forProgress progress: CGFloat) -> CGFloat {
        let cfg = modalController?.config
        let a = cfg?.dimAlphaStage1 ?? 0.25
        let b = cfg?.dimAlphaStage2 ?? 0.4
        let clamped = max(0.0, min(1.0, progress))
        return a + (b - a) * clamped
    }

    private func transitionDistance(from stage1: CGRect, to stage2: CGRect) -> CGFloat {
        max(1.0, stage1.minY - stage2.minY)
    }

    private func interpolate(from a: CGRect, to b: CGRect, t: CGFloat) -> CGRect {
        return CGRect(
            x: a.minX + (b.minX - a.minX) * t,
            y: a.minY + (b.minY - a.minY) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }

    private func collapseFrame(from expanded: CGRect, to compact: CGRect, t: CGFloat) -> CGRect {
        let verticalT = t
        let horizontalT = t * t
        let y = expanded.minY + (compact.minY - expanded.minY) * verticalT
        let x = expanded.minX + (compact.minX - expanded.minX) * horizontalT
        let width = expanded.width + (compact.width - expanded.width) * horizontalT
        // Bottom interpolates quadratically too, so the bottom inset
        // appears late during collapse (matching the sides).
        let bottom = expanded.maxY + (compact.maxY - expanded.maxY) * horizontalT
        return CGRect(
            x: x,
            y: y,
            width: width,
            height: max(0.0, bottom - y)
        )
    }

    private func expandFrame(from compact: CGRect, to expanded: CGRect, t: CGFloat) -> CGRect {
        let verticalT = t
        let horizontalT = t * t
        let y = compact.minY + (expanded.minY - compact.minY) * verticalT
        let x = compact.minX + (expanded.minX - compact.minX) * horizontalT
        let width = compact.width + (expanded.width - compact.width) * horizontalT
        // Bottom interpolates quadratically toward the target's bottom
        // (which usually sits lower — 0pt inset at stage2 vs stage1's).
        let bottom = compact.maxY + (expanded.maxY - compact.maxY) * horizontalT
        return CGRect(
            x: x,
            y: y,
            width: width,
            height: max(0.0, bottom - y)
        )
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
              let view = pan.view else {
            return true
        }
        // Require a mostly-vertical initial motion — horizontal swipes
        // (e.g. cell swipe actions) shouldn't wake up the sheet pan.
        let velocity = pan.velocity(in: view)
        return abs(velocity.y) >= abs(velocity.x)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        // Run alongside the primary scroll view's pan so its touch stream
        // is never pre-empted. We decide per-drag inside `handlePan`
        // whether the sheet or the scroll actually drives — and when the
        // sheet drives we pin the scroll's contentOffset at its top so
        // both recognizers can coexist without fighting each other.
        if let scrollView = modalController?.primaryScrollView,
           other === scrollView.panGestureRecognizer {
            return true
        }
        return false
    }
}
