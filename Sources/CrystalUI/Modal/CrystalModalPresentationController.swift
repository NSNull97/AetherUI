import UIKit

final class CrystalModalPresentationController: UIPresentationController, UIGestureRecognizerDelegate {
    private let dimView = UIView()
    private var panGesture: UIPanGestureRecognizer?

    private var detent: CrystalModalController.Detent = .stage1

    // Drag state (per gesture).
    private var dragStartFrame: CGRect = .zero
    private var dragStartDetent: CrystalModalController.Detent = .stage1
    private var dragDriving: Bool = false
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
        if let scrollView = modalController?.primaryScrollView {
            scrollView.panGestureRecognizer.require(toFail: pan)
        }

        modalController?.applyCurrentDetent(detent)
        modalController?.applyDetentProgress(0.0)
    }

    override func dismissalTransitionWillBegin() {
        super.dismissalTransitionWillBegin()
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
        animateTo(detent: newDetent, container: containerView, initialVelocityY: 0.0, animated: animated)
    }

    // MARK: - Frame calc

    private func frame(for detent: CrystalModalController.Detent, in bounds: CGRect) -> CGRect {
        let cfg = modalController?.config ?? .init()
        let safeArea = containerView?.safeAreaInsets ?? presentingViewController.view.safeAreaInsets
        // Bottom edge is pinned in both detents — the sheet never translates
        // while switching between them, only its top/side insets change.
        let bottom = bounds.height - cfg.bottomInset
        switch detent {
        case .stage1:
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
            dragDriving = true

        case .changed:
            guard dragDriving else { return }
            let translation = gesture.translation(in: container)
            let draggingDown = translation.y > 0
            let draggingUp = translation.y < 0
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

    private func applyDrag(translation: CGPoint, container: UIView, draggingDown: Bool, draggingUp: Bool) {
        guard let presentedView else { return }
        let bounds = container.bounds
        let stage1 = frame(for: .stage1, in: bounds)
        let stage2 = frame(for: .stage2, in: bounds)

        var newFrame = dragStartFrame
        var progress: CGFloat
        switch dragStartDetent {
        case .stage1:
            if draggingUp {
                // Grow toward stage2 with the bottom edge pinned — the sheet
                // doesn't translate, only its top/sides expand outward.
                let distance = transitionDistance(from: stage1, to: stage2)
                let t = max(0.0, min(1.0, -translation.y / distance))
                newFrame = expandFrame(from: stage1, to: stage2, t: t)
                progress = t
            } else {
                // Dismiss from the compact state while keeping its size.
                newFrame = stage1.offsetBy(dx: 0.0, dy: max(0.0, translation.y))
                progress = 0.0
            }
        case .stage2:
            if draggingDown {
                let distance = transitionDistance(from: stage1, to: stage2)
                let t = max(0.0, min(1.0, translation.y / distance))
                newFrame = collapseFrame(from: stage2, to: stage1, t: t)
                progress = 1.0 - t
            } else {
                // Drag up from stage2 — no-op here, scroll should be handling.
                newFrame = stage2
                progress = 1.0
            }
        }

        presentedView.frame = newFrame
        modalController?.applyDetentProgress(progress)
        dimView.alpha = (modalController?.config.dimAlphaStage2 ?? 0.25) * progress
    }

    private func finishDrag(translation: CGPoint, velocity: CGPoint, container: UIView) {
        let dismissVelocityThreshold: CGFloat = 800.0
        let expandVelocityThreshold: CGFloat = 400.0
        let expandProgressThreshold: CGFloat = 0.4
        let collapseProgressThreshold: CGFloat = 0.4

        let bounds = container.bounds
        let stage1 = frame(for: .stage1, in: bounds)
        let stage2 = frame(for: .stage2, in: bounds)

        switch dragStartDetent {
        case .stage1:
            if translation.y > 0 {
                if velocity.y > dismissVelocityThreshold {
                    animateDismiss()
                } else {
                    animateTo(detent: .stage1, container: container, initialVelocityY: velocity.y)
                }
            } else {
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
        let targetDim = (modalController?.config.dimAlphaStage2 ?? 0.25) * targetProgress

        if !animated {
            presentedView?.frame = targetFrame
            modalController?.applyDetentProgress(targetProgress)
            dimView.alpha = targetDim
            return
        }

        let isCollapsingTowardStage1 = targetDetent == .stage1 && currentFrame.minY < targetFrame.minY
        let baseDuration: CFTimeInterval = isCollapsingTowardStage1 ? 0.46 : 0.5
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

    /// Underdamped spring step response — light overshoot (~4%), quick settle.
    /// Approximates the "natural" spring UIKit gives you with spring damping
    /// ≈ 0.78 / initialVelocity 0. Fully settled by t = 1.
    private static func easeOutSpring(_ t: CGFloat) -> CGFloat {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        let zeta: CGFloat = 0.78
        let omega: CGFloat = 9.0
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
        dimView.alpha = (modalController?.config.dimAlphaStage2 ?? 0.25) * currentProgress
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
        let bottom = expanded.maxY
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
        // Bottom pinned at compact.maxY — the sheet grows upward/sideways
        // but its bottom edge stays put. On release, animateTo settles the
        // bottom to the target detent's position.
        let bottom = compact.maxY
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
        let velocity = pan.velocity(in: view)
        guard abs(velocity.y) >= abs(velocity.x) else {
            return false
        }
        guard gestureStartedInPrimaryScrollContent(pan),
              let scrollView = modalController?.primaryScrollView else {
            return true
        }

        let atTop = isPrimaryScrollViewAtTop(scrollView)
        switch detent {
        case .stage1:
            return atTop
        case .stage2:
            return velocity.y > 0.0 && atTop
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return false
    }
}
