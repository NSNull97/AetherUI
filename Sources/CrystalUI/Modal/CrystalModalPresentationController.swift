import UIKit

final class CrystalModalPresentationController: UIPresentationController, UIGestureRecognizerDelegate {
    private let dimView = UIView()
    private var panGesture: UIPanGestureRecognizer?

    private var detent: CrystalModalController.Detent = .stage1

    // Drag state (per gesture).
    private var dragStartFrame: CGRect = .zero
    private var dragStartDetent: CrystalModalController.Detent = .stage1
    private var dragDriving: Bool = false
    private var dragInitialScrollOffset: CGFloat = 0
    private var dragInitialScrollEnabled: Bool = true

    lazy var deviceCornerRadius: CGFloat = {
        if let window = presentingViewController.view.window,
           let value = window.screen.value(forKey: "_displayCornerRadius") as? CGFloat,
           value > 0 {
            return value
        }
        return 39.0
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
        if !dragDriving {
            presentedView?.frame = frameOfPresentedViewInContainerView
        }
    }

    // MARK: - Detent API

    func setDetent(_ newDetent: CrystalModalController.Detent, animated: Bool) {
        guard detent != newDetent else { return }
        detent = newDetent
        modalController?.applyCurrentDetent(newDetent)

        let targetFrame = frameOfPresentedViewInContainerView
        let targetProgress: CGFloat = newDetent == .stage2 ? 1.0 : 0.0
        let targetDim = (modalController?.config.dimAlphaStage2 ?? 0.25) * targetProgress

        let animations = { [weak self] in
            guard let self = self else { return }
            self.presentedView?.frame = targetFrame
            self.modalController?.applyDetentProgress(targetProgress)
            self.dimView.alpha = targetDim
        }
        if animated {
            UIView.animate(
                withDuration: 0.4,
                delay: 0.0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0.0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: animations
            )
        } else {
            animations()
        }
    }

    // MARK: - Frame calc

    private func frame(for detent: CrystalModalController.Detent, in bounds: CGRect) -> CGRect {
        let cfg = modalController?.config ?? .init()
        let safeArea = presentingViewController.view.safeAreaInsets
        switch detent {
        case .stage1:
            let top = safeArea.top + cfg.topInsetStage1
            return CGRect(
                x: cfg.sideInset,
                y: top,
                width: bounds.width - cfg.sideInset * 2.0,
                height: max(0.0, bounds.height - top)
            )
        case .stage2:
            let top = safeArea.top + cfg.topInsetStage2
            return CGRect(
                x: 0.0,
                y: top,
                width: bounds.width,
                height: max(0.0, bounds.height - top)
            )
        }
    }

    // MARK: - Dim tap

    @objc private func handleDimTap() {
        presentedViewController.dismiss(animated: true)
    }

    // MARK: - Pan gesture

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = containerView, let presentedView else { return }
        let translation = gesture.translation(in: container)
        let velocity = gesture.velocity(in: container)

        switch gesture.state {
        case .began:
            dragStartFrame = presentedView.frame
            dragStartDetent = detent
            dragDriving = false
            if let sv = modalController?.primaryScrollView {
                dragInitialScrollOffset = sv.contentOffset.y - scrollTopOffset(for: sv)
                dragInitialScrollEnabled = sv.isScrollEnabled
            } else {
                dragInitialScrollOffset = 0.0
                dragInitialScrollEnabled = true
            }

        case .changed:
            let draggingDown = translation.y > 0
            let draggingUp = translation.y < 0

            if !dragDriving {
                if dragStartDetent == .stage1 {
                    dragDriving = true
                } else {
                    if draggingDown && dragInitialScrollOffset <= 0.5 {
                        dragDriving = true
                    }
                }
            }

            guard dragDriving else { return }

            if let sv = modalController?.primaryScrollView {
                let topOffset = scrollTopOffset(for: sv)
                if sv.contentOffset.y != topOffset {
                    sv.contentOffset.y = topOffset
                }
                if sv.isScrollEnabled {
                    sv.isScrollEnabled = false
                }
            }

            applyDrag(translation: translation, container: container, draggingDown: draggingDown, draggingUp: draggingUp)

        case .ended, .cancelled, .failed:
            defer {
                if let sv = modalController?.primaryScrollView {
                    sv.isScrollEnabled = dragInitialScrollEnabled
                }
            }
            guard dragDriving else { return }
            dragDriving = false
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
                // Expand toward stage2.
                let distance: CGFloat = 140.0
                let t = max(0.0, min(1.0, -translation.y / distance))
                newFrame = interpolate(from: stage1, to: stage2, t: t)
                progress = t
            } else {
                // Translate down, no resize, no progress.
                newFrame = stage1.offsetBy(dx: 0.0, dy: max(0.0, translation.y))
                progress = 0.0
            }
        case .stage2:
            if draggingDown {
                // Collapse toward stage1.
                let distance: CGFloat = max(1.0, stage2.height - stage1.height)
                let t = max(0.0, min(1.0, translation.y / distance))
                newFrame = interpolate(from: stage2, to: stage1, t: t)
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
                    animateDismiss(from: presentedView?.frame ?? stage1, container: container, velocity: velocity)
                } else {
                    animateTo(detent: .stage1, container: container)
                }
            } else {
                let distance: CGFloat = 140.0
                let progress = max(0.0, min(1.0, -translation.y / distance))
                if progress > expandProgressThreshold || velocity.y < -expandVelocityThreshold {
                    animateTo(detent: .stage2, container: container)
                } else {
                    animateTo(detent: .stage1, container: container)
                }
            }
        case .stage2:
            if translation.y > 0 {
                let distance: CGFloat = max(1.0, stage2.height - stage1.height)
                let progress = max(0.0, min(1.0, translation.y / distance))
                if progress > collapseProgressThreshold || velocity.y > expandVelocityThreshold {
                    animateTo(detent: .stage1, container: container)
                } else {
                    animateTo(detent: .stage2, container: container)
                }
            } else {
                animateTo(detent: .stage2, container: container)
            }
        }
    }

    private func animateTo(detent targetDetent: CrystalModalController.Detent, container: UIView) {
        self.detent = targetDetent
        modalController?.applyCurrentDetent(targetDetent)

        let targetFrame = frame(for: targetDetent, in: container.bounds)
        let targetProgress: CGFloat = targetDetent == .stage2 ? 1.0 : 0.0
        let targetDim = (modalController?.config.dimAlphaStage2 ?? 0.25) * targetProgress

        UIView.animate(
            withDuration: 0.4,
            delay: 0.0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0.0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: { [weak self] in
                guard let self = self else { return }
                self.presentedView?.frame = targetFrame
                self.modalController?.applyDetentProgress(targetProgress)
                self.dimView.alpha = targetDim
            }
        )
    }

    private func animateDismiss(from currentFrame: CGRect, container: UIView, velocity: CGPoint) {
        presentedViewController.dismiss(animated: true)
    }

    private func scrollTopOffset(for sv: UIScrollView) -> CGFloat {
        return -sv.adjustedContentInset.top
    }

    private func interpolate(from a: CGRect, to b: CGRect, t: CGFloat) -> CGRect {
        return CGRect(
            x: a.minX + (b.minX - a.minX) * t,
            y: a.minY + (b.minY - a.minY) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return true
    }
}
