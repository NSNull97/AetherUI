import UIKit

/// Modal sheet container — direct port of Display framework
/// `submodules/Display/Source/Navigation/NavigationModalContainer.swift`
/// (ASDisplayNode → UIView, ASScrollNode → UIScrollView, signals → callbacks).
///
/// The "sheet" gesture-coordination trick is the key move: an outer
/// `UIScrollView` with `contentSize.height = layout.height * 2` and bounds
/// pinned to `(0, height)` so dragging DOWN reduces `bounds.origin.y` (modal
/// translates down → dismiss), while dragging UP is impossible past the
/// pinned position. UIKit's own gesture-cooperation between scroll views
/// does the right thing for nested scroll content: the inner scroll consumes
/// vertical drag while it's not at `contentOffset.top`, then hand-off occurs
/// at the boundary and the outer modal scroll picks up the rest.
public final class NavigationModalContainer: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private var theme: NavigationControllerTheme
    let isFlat: Bool

    private let dimView: UIView
    private let scrollView: UIScrollView
    private let containerView: UIView
    private let navigationContainer: NavigationContainer

    private let dismissRequested: () -> Void
    private let requestLayoutHook: (ContainedViewLayoutTransition) -> Void
    private let controllerRemovedHook: (ViewController) -> Void

    private var isUpdatingState = false
    private var ignoreScrolling = false
    private var isDismissed = false

    private var validLayout: ContainerViewLayout?
    private var horizontalDismissOffset: CGFloat?

    private var controllers: [ViewController]
    private(set) var dismissProgress: CGFloat = 0.0
    private var endDraggingVelocity: CGPoint?

    /// Cached device corner radius — bottom corners are computed concentrically
    /// so they nest into the device chamfer when the modal is at the screen edge.
    private lazy var deviceCornerRadius: CGFloat = {
        if let value = window?.screen.value(forKey: "_displayCornerRadius") as? CGFloat, value > 0 {
            return value
        }
        return 39.0
    }()

    public var topController: ViewController? {
        controllers.last
    }

    init(
        controllers: [ViewController],
        theme: NavigationControllerTheme,
        isFlat: Bool,
        controllerRemoved: @escaping (ViewController) -> Void,
        requestLayout: @escaping (ContainedViewLayoutTransition) -> Void,
        dismissRequested: @escaping () -> Void
    ) {
        self.controllers = controllers
        self.theme = theme
        self.isFlat = isFlat

        self.dimView = UIView()
        self.dimView.alpha = 0.0
        // Match exactly — compact width-class modals dim the backing
        // at 25% black. Without this set, the dim view stays clear and the
        // backing chat doesn't darken when the modal slides up.
        self.dimView.backgroundColor = UIColor(white: 0.0, alpha: 0.25)

        self.scrollView = UIScrollView()
        self.containerView = UIView()
        self.navigationContainer = NavigationContainer(frame: .zero)

        self.dismissRequested = dismissRequested
        self.requestLayoutHook = requestLayout
        self.controllerRemovedHook = controllerRemoved

        super.init(frame: .zero)

        addSubview(dimView)
        addSubview(scrollView)
        scrollView.addSubview(containerView)
        containerView.addSubview(navigationContainer)

        // Container clip + smooth corners (applies `applySmoothRoundedCorners`
        // — we use `.continuous` corner curve which is the public equivalent).
        containerView.clipsToBounds = true
        containerView.layer.cornerCurve = .continuous

        // Scroll view tuned exactly like the original: vertical-only, no bounce,
        // no bars, never auto-adjusts insets.
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.bounces = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.clipsToBounds = false
        scrollView.delegate = self

        navigationContainer.controllerRemoved = { [weak self] removed in
            self?.controllerRemovedHook(removed)
        }
        navigationContainer.requestLayout = { [weak self] transition in
            self?.requestLayoutHook(transition)
        }
        navigationContainer.setControllers(controllers, animated: false)

        let dimTap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimView.addGestureRecognizer(dimTap)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API matching the previous interface

    func setControllers(_ controllers: [ViewController], isFlat: Bool, animated: Bool) {
        self.controllers = controllers
        navigationContainer.setControllers(controllers, animated: animated)
        if let layout = validLayout {
            containerLayoutUpdated(layout, transition: animated ? .animated(duration: 0.35, curve: .spring) : .immediate)
        }
    }

    func updateTheme(_ theme: NavigationControllerTheme) {
        self.theme = theme
        containerView.backgroundColor = theme.emptyAreaColor
    }

    @discardableResult
    func popController(animated: Bool) -> ViewController? {
        let removed = navigationContainer.popController(animated: animated)
        if let removed {
            controllers.removeAll { $0 === removed }
        }
        return removed
    }

    // MARK: - Layout

    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        frame = CGRect(origin: .zero, size: layout.size)
        dimView.frame = bounds

        guard !isDismissed else { return }
        isUpdatingState = true

        // Standard behavior: scroll occupies the full screen, contentSize is
        // 2× height, default bounds origin.y = height. Dragging down decreases
        // the bounds.y → containerView translates down → dismiss progress
        // grows from 0 → 1.
        ignoreScrolling = true
        let scrollFrame = CGRect(origin: CGPoint(x: horizontalDismissOffset ?? 0.0, y: 0.0), size: layout.size)
        scrollView.frame = scrollFrame
        scrollView.contentSize = CGSize(width: layout.size.width, height: layout.size.height * 2.0)
        if !scrollView.isDecelerating, !scrollView.isDragging {
            let defaultBounds = CGRect(origin: CGPoint(x: 0.0, y: layout.size.height), size: layout.size)
            if scrollView.bounds != defaultBounds {
                scrollView.bounds = defaultBounds
            }
        }
        scrollView.isScrollEnabled = !isFlat && (layout.inputHeight ?? 0) <= 0
        ignoreScrolling = false

        // Sheet metrics (compact width class only — that's the iPhone case).
        let topInset: CGFloat
        if isFlat {
            topInset = 0.0
        } else if let statusBarHeight = layout.statusBarHeight {
            topInset = statusBarHeight + 10.0
        } else {
            topInset = max(layout.safeInsets.top, 50.0)
        }

        // Container is positioned in scroll content space at y = layout.height
        // (the lower half of the 2× content). When scroll bounds are at
        // origin.y = layout.height, container appears at screen y = topInset.
        let containerFrame = CGRect(
            x: 0.0,
            y: layout.size.height + topInset,
            width: layout.size.width,
            height: max(0.0, layout.size.height - topInset)
        )
        transition.updateFrame(view: containerView, frame: containerFrame)

        let cornerRadius: CGFloat = isFlat ? 0.0 : ((controllers.first?._hasGlassStyle == true) ? 38.0 : 10.0)
        transition.updateCornerRadius(layer: containerView.layer, cornerRadius: cornerRadius)
        if layout.safeInsets.bottom.isZero {
            containerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        } else {
            containerView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        containerView.backgroundColor = theme.emptyAreaColor

        let modalSafeInsets = UIEdgeInsets(
            top: 0.0,
            left: layout.safeInsets.left,
            bottom: layout.safeInsets.bottom,
            right: layout.safeInsets.right
        )
        let modalLayout = ContainerViewLayout(
            size: containerFrame.size,
            metrics: layout.metrics,
            safeInsets: modalSafeInsets,
            additionalInsets: layout.additionalInsets,
            statusBarHeight: nil,
            inputHeight: layout.inputHeight,
            inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging,
            inVoiceOver: layout.inVoiceOver
        )
        navigationContainer.frame = CGRect(origin: .zero, size: containerFrame.size)
        navigationContainer.containerLayoutUpdated(modalLayout, transition: transition)

        isUpdatingState = false
    }

    // MARK: - Animations

    func animateIn(completion: (() -> Void)? = nil) {
        // Direct port of `animateIn`:
        //
        //   transition.updateAlpha(node: dim, alpha: 1.0)
        //   transition.animatePositionAdditive(node: container,
        //       offset: CGPoint(x: 0, y: bounds.height + container.bounds.height/2 - (container.position.y - bounds.height)))
        //
        // The container's model layer position stays AT the final target;
        // we add a CAAdditive animation that starts from `+offset` and lands
        // at `+0`. That keeps the layer rendering correct even if the user
        // re-lays out mid-animation.
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.5, curve: .spring)
        let containerLayer = containerView.layer
        let containerHeight = containerLayer.bounds.height
        // `container.position.y - bounds.height` is the container's *visible*
        // y in screen space (since it's positioned at `layout.height + topInset`
        // inside the 2× scroll content). offset formula:
        let visibleY = containerLayer.position.y - bounds.height
        let offset = CGPoint(x: 0.0, y: bounds.height + containerHeight / 2.0 - visibleY)

        transition.updateAlpha(view: dimView, alpha: 1.0)
        transition.animatePositionAdditive(layer: containerLayer, offset: offset, completion: { _ in completion?() })
    }

    func applyPresentedState() {
        dimView.alpha = 1.0
    }

    func animateOut(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction],
            animations: {
                self.dimView.alpha = 0.0
                self.containerView.transform = CGAffineTransform(translationX: 0, y: self.bounds.height)
            },
            completion: { _ in completion() }
        )
    }

    // MARK: - Gestures / scroll-driven dismiss

    @objc private func dimTapped() {
        if !isDismissed {
            dismissRequested()
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !ignoreScrolling, !isDismissed else { return }
        // dismissProgress = (height - bounds.origin.y) / height — exactly the
        // formula. 0 = fully presented, 1 = dismissed.
        let progress = max(0.0, min(1.0, (bounds.height - scrollView.bounds.origin.y) / max(1.0, bounds.height)))
        dismissProgress = progress
        applyDismissProgress(transition: .immediate)
    }

    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        endDraggingVelocity = velocity
        // Snap to either dismissed or restored — standard snap behavior.
        targetContentOffset.pointee = scrollView.contentOffset
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let velocity = endDraggingVelocity ?? .zero
        endDraggingVelocity = nil

        let progress = max(0.0, min(1.0, (bounds.height - scrollView.bounds.origin.y) / max(1.0, bounds.height)))
        let shouldDismiss = velocity.y < -0.5 || progress >= 0.5

        ignoreScrolling = true
        if shouldDismiss {
            isDismissed = true
            let velocityFactor: CGFloat = 0.4 / max(1.0, abs(velocity.y))
            let duration = TimeInterval(min(0.3, velocityFactor))
            scrollView.setContentOffset(CGPoint(x: 0.0, y: 0.0), animated: false)
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut], animations: {
                self.dimView.alpha = 0.0
            }, completion: { _ in
                self.dismissRequested()
            })
        } else {
            // Snap back to presented.
            scrollView.setContentOffset(CGPoint(x: 0.0, y: bounds.height), animated: false)
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, animations: {
                self.dimView.alpha = 1.0
            })
            dismissProgress = 0.0
        }
        ignoreScrolling = false
    }

    private func applyDismissProgress(transition: ContainedViewLayoutTransition) {
        transition.updateAlpha(view: dimView, alpha: 1.0 - dismissProgress)
    }
}
