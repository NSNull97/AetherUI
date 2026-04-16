import UIKit

// Direct port of Telegram-iOS `NavigationTransitionCoordinator` from
// submodules/Display/Source/NavigationTransitionCoordinator.swift
// adapted to pure UIKit (no AsyncDisplayKit).

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

    private var topInitialCorners: (clipsToBounds: Bool, cornerRadius: CGFloat)?

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
    ///   - screenCornerRadius: matches device corner radius; used to round
    ///     `topView` during the transition for the iOS 26 card-like feel.
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
                topInitialCorners = (topView.clipsToBounds, topView.layer.cornerRadius)
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
    /// Mirrors Telegram: `position = 1 - progress` for `.push`, `position =
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

        // --- Nav bar pinning + crossfade ---
        // Each controller's nav bar lives inside its view (which slides
        // during push/pop). To achieve a stock-iOS feel where the bar
        // surface stays fixed and only its content crossfades, we:
        //   1. Apply a compensating translateX so the bar visually stays
        //      at x = 0 regardless of parent slide.
        //   2. Crossfade alpha between the outgoing and incoming bars.
        if let topBar {
            let barCompensation = CGAffineTransform(translationX: -topFrame.minX, y: 0)
            transition.updateTransform(view: topBar, transform: barCompensation)
        }
        if let bottomBar {
            let barCompensation = CGAffineTransform(translationX: -bottomFrame.minX, y: 0)
            transition.updateTransform(view: bottomBar, transform: barCompensation)
        }

        // Top bar is the INCOMING on push / OUTGOING on pop.
        // position = 0 means transition complete (both views at rest).
        // position = 1 means transition at start (top fully off-screen right).
        // For push: top starts at alpha 0, grows to 1.
        // For pop: top starts at alpha 1, shrinks to 0.
        let topBarAlpha: CGFloat
        let bottomBarAlpha: CGFloat
        switch direction {
        case .push:
            topBarAlpha = 1.0 - position      // 0 → 1
            bottomBarAlpha = position          // 1 → 0
        case .pop:
            topBarAlpha = position             // 1 → 0
            bottomBarAlpha = 1.0 - position    // 0 → 1
        }
        if let topBar {
            transition.updateAlpha(view: topBar, alpha: topBarAlpha)
        }
        if let bottomBar {
            transition.updateAlpha(view: bottomBar, alpha: bottomBarAlpha)
        }

        let shadowFrame = CGRect(
            x: topFrame.minX - navigationShadowWidth,
            y: 0.0,
            width: navigationShadowWidth,
            height: size.height
        )
        transition.updateFrame(view: shadowView, frame: shadowFrame)
        transition.updateAlpha(view: shadowView, alpha: (1.0 - position) * 0.9)

        transition.updateFrame(view: dimView, frame: CGRect(origin: .zero, size: CGSize(width: max(0.0, topFrame.minX), height: size.height)))
        transition.updateAlpha(view: dimView, alpha: (1.0 - position) * 0.15)

        if hadEarlyCompletion {
            completion()
        }
    }

    // MARK: - Animation entry points

    /// Finish the transition with a spring animation. When a `velocity` is
    /// provided (e.g. from a pan-gesture end), timing is scaled to that
    /// velocity — matching iOS's natural flick-to-complete feel.
    func animateCompletion(velocity: CGFloat = 0.0, completion: @escaping () -> Void) {
        animatingCompletion = true
        currentCompletion = completion

        let distance = (1.0 - progress) * container.bounds.size.width
        let transition: ContainedViewLayoutTransition

        if abs(velocity) < .ulpOfOne, abs(progress) < .ulpOfOne {
            // Non-interactive push / programmatic completion.
            transition = .animated(duration: 0.5, curve: .spring)
        } else {
            let duration = Double(max(0.05, min(0.2, abs(distance / velocity))))
            transition = .animated(duration: duration, curve: .easeInOut)
        }

        updateProgress(1.0, transition: transition, completion: { [weak self] in
            self?.finish()
        })
    }

    /// Abort the transition (e.g. interactive pan released without enough
    /// velocity/distance). Animates back to `progress = 0` and tears down.
    func animateCancel(_ completion: @escaping () -> Void) {
        currentCompletion = completion
        updateProgress(0.0, transition: .animated(duration: 0.2, curve: .easeInOut), completion: { [weak self] in
            guard let self else { return }
            // Remove the incoming view entirely — same controller just came
            // back to its original position.
            switch self.direction {
            case .push:
                self.topView.removeFromSuperview()
            case .pop:
                self.bottomView.removeFromSuperview()
            }
            self.restoreNavBars()
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
        restoreNavBars()
        cleanupOverlays()
        restoreTopViewCorners()
        let hook = currentCompletion
        currentCompletion = nil
        hook?()
    }

    /// Reset nav bars to their natural state after the transition.
    /// The pinning transform + alpha override must be removed so the
    /// bar renders normally when no transition is in flight.
    private func restoreNavBars() {
        topBar?.transform = .identity
        topBar?.alpha = 1.0
        bottomBar?.transform = .identity
        bottomBar?.alpha = 1.0
    }

    private func cleanupOverlays() {
        dimView.removeFromSuperview()
        shadowView.removeFromSuperview()
    }

    private func restoreTopViewCorners() {
        guard let (clipsToBounds, cornerRadius) = topInitialCorners else { return }
        topView.layer.cornerCurve = .circular
        topView.clipsToBounds = clipsToBounds
        topView.layer.cornerRadius = cornerRadius
        topInitialCorners = nil
    }
}
