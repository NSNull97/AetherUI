import UIKit

// Direct port of Display framework `NavigationTransitionCoordinator` from
// submodules/Display/Source/NavigationTransitionCoordinator.swift
// adapted to pure UIKit.

enum NavigationTransitionDirection {
    case push
    case pop
}

private let navigationShadowWidth: CGFloat = 16.0

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

    private let dimView: UIView
    private let shadowView: UIImageView

    private var topInitialCorners: (clipsToBounds: Bool, cornerRadius: CGFloat, maskedCorners: CACornerMask, cornerCurve: CALayerCornerCurve)?

    private var currentCompletion: (() -> Void)?

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
        screenCornerRadius: CGFloat = 0.0
    ) {
        self.container = container
        self.direction = direction
        self.topView = topView
        self.bottomView = bottomView
        self.topBar = topBar
        self.bottomBar = bottomBar
        self.isInteractive = isInteractive
        self.isFlat = isFlat

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

    // MARK: - Progress

    /// Maps `progress` (0 → 1) to the on-screen position of the transition.
    /// Mirrors the original: `position = 1 - progress` for `.push`, `position =
    /// progress` for `.pop`. All geometry is driven by `position`.
    func updateProgress(_ progress: CGFloat, transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        self.progress = progress

        let position: CGFloat
        switch direction {
        case .push:
            position = 1.0 - progress
        case .pop:
            position = progress
        }

        let size = container.bounds.size
        let topFrame = CGRect(origin: CGPoint(x: floor(position * size.width), y: 0.0), size: size)
        let bottomFrame: CGRect
        if isFlat {
            bottomFrame = CGRect(origin: CGPoint(x: -floor((1.0 - position) * size.width), y: 0.0), size: size)
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

    /// Finish the transition with a spring animation. When a `velocity` is
    /// provided (e.g. from a pan-gesture end), timing is scaled to that
    /// velocity — matching iOS's natural flick-to-complete feel.
    ///
    /// Three regimes, each with its own damping:
    ///   * Programmatic **push** — critical damping (1.0). Pushing in a new
    ///     controller should feel deliberate and quiet; an overshoot bounce
    ///     reads as instability ("did the screen mis-land?").
    ///   * Programmatic **pop** — slight under-critical damping (0.88). The
    ///     revealed bottom controller settles with a barely-visible kiss,
    ///     consistent with the iOS 26 nav stack feel without being playful.
    ///   * **Interactive flick-to-pop** — pronounced under-critical damping
    ///     (0.62). When the user actively flicks the screen away, the
    ///     incoming bottom controller bounces visibly into place, mirroring
    ///     the energy of the gesture. Initial velocity is also fed in from
    ///     the pan velocity, so the bounce scales with how hard the user
    ///     flicked.
    func animateCompletion(velocity: CGFloat = 0.0, completion: @escaping () -> Void) {
        animatingCompletion = true
        currentCompletion = completion

        let distance = (1.0 - progress) * container.bounds.size.width
        let transition: ContainedViewLayoutTransition

        if abs(velocity) < .ulpOfOne, abs(progress) < .ulpOfOne {
            // Non-interactive (programmatic) completion.
            let damping: CGFloat
            switch direction {
            case .push: damping = 1.0  // critical — quiet, no bounce
            case .pop:  damping = 0.92 // barely-there soft kiss
            }
            transition = .animated(duration: 0.4, curve: .customSpring(damping: damping, initialVelocity: 0.0))
        } else {
            // Interactive flick-to-complete (always a pop — we don't expose
            // interactive push). Damping 0.74 with a tighter 0.42-0.55s
            // duration: the bounce stays clearly visible (peak ~7-9%) but
            // the whole spring motion (overshoot → return → settle) runs
            // faster, matching the snappy native iOS-26 feel — no slow
            // wobbly aftertaste.
            //
            // Duration must still be *long enough* for the spring's full
            // path to complete within `withDuration`, because the
            // `completion` callback fires at `withDuration` (not when the
            // spring physically settles). After completion fires,
            // `NavigationController.handleControllerRemoved` runs
            // `setControllers(animated: false)` which snaps every controller
            // view to its layout frame — instantly aborting any still-running
            // spring. The slightly higher damping (0.74 vs 0.66) lets the
            // spring settle quickly enough that 0.42s minimum is enough room
            // for it to complete naturally.
            let normalizedVelocity = max(1.0, min(10.0, abs(velocity) / max(1.0, abs(distance))))
            let duration = max(0.42, min(0.55, abs(distance) / max(1.0, abs(velocity))))
            transition = .animated(duration: duration, curve: .customSpring(damping: 0.74, initialVelocity: normalizedVelocity))
        }

        updateProgress(1.0, transition: transition, completion: { [weak self] in
            self?.finish()
        })
    }

    /// Abort the transition (e.g. interactive pan released without enough
    /// velocity/distance). Animates back to `progress = 0` and tears down.
    func animateCancel(_ completion: @escaping () -> Void) {
        currentCompletion = completion
        // Cancel: critically damped spring — snaps back to origin without
        // bouncing past 0 (no destination to overshoot toward).
        updateProgress(0.0, transition: .animated(duration: 0.22, curve: .customSpring(damping: 1.0, initialVelocity: 0.0)), completion: { [weak self] in
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
        updateProgress(1.0, transition: .immediate, completion: { [weak self] in
            self?.finish()
            completion()
        })
    }

    /// Synchronously mark the transition as complete and tear down overlays.
    /// Used when the caller has already applied `progress = 1.0`.
    func complete() {
        animatingCompletion = true
        progress = 1.0
        finish()
    }

    // MARK: - Teardown

    private func finish() {
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
