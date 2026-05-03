import UIKit

public enum TabBarItemSwipeDirection {
    case left
    case right
}

/// Container for top-level tabs. Pure UIKit replacement for the original
/// TabBarController.
///
/// Architecture (native-iOS shape, no shared nav bar):
/// - `AetherTabBarController` is the window's rootViewController.
/// - Each tab's controller is typically a `AetherNavigationController`
///   hosting its own navigation stack and its own nav bar. The tab bar
///   controller never owns a nav bar — every screen brings its own, so
///   push/pop inside a tab animates the bar naturally along with the
///   content (no snapshot crossfades, no hiding of child bars).
/// - The floating tab bar sits on top of the currently-visible tab's
///   content. `updateIsTabBarHidden(_:)` slides it out when a pushed
///   screen wants a full-height layout.
open class AetherTabBarController: AetherViewController {
    // MARK: - Properties

    private let tabBarView: TabBarView
    private var _controllers: [UIViewController] = []
    private var _selectedIndex: Int = 0

    public var controllers: [UIViewController] {
        return _controllers
    }

    /// Controller for the currently-visible tab.
    public var currentController: UIViewController? {
        guard _selectedIndex < _controllers.count else { return nil }
        return _controllers[_selectedIndex]
    }

    public var selectedIndex: Int {
        get { _selectedIndex }
        set {
            guard newValue != _selectedIndex, newValue < _controllers.count else { return }
            let previousIndex = _selectedIndex
            _selectedIndex = newValue
            tabBarView.selectedIndex = newValue
            transitionToController(at: newValue, from: previousIndex, animated: true)
        }
    }

    public var tabBarTheme: TabBarView.Theme {
        didSet {
            tabBarView.updateTheme(tabBarTheme)
        }
    }

    /// iOS 26-style `UISearchTab` showcase capsule placed next to the tab pill.
    /// Forwarded straight through to the underlying `TabBarView`.
    public var searchShowcase: TabBarView.SearchShowcase? {
        didSet { tabBarView.searchShowcase = searchShowcase }
    }

    /// Closure returning the `ContextMenuItem`s for a tab on long-press.
    /// Called with the tab index; return an empty array to suppress the
    /// menu for that tab. Setup-time configuration path — preferred over
    /// subclassing for most call sites (e.g. SceneDelegate wiring).
    ///
    /// Subclasses can alternatively override `contextMenuItems(forTabAt:)`
    /// and ignore this closure. The default implementation of that method
    /// calls this closure, so mixing the two is rarely needed.
    public var tabContextMenuItemsProvider: ((Int) -> [ContextMenuItem])?

    // MARK: - Bottom Bar Accessory

    /// Accessory view anchored directly above the tab bar pill, wrapped
    /// in a glass pill. Mirrors iOS 26's `UITabBarController.bottomAccessory`.
    ///
    /// Side insets track the tab bar theme's `sideInset`, the bottom gap
    /// against the pill is fixed at 8pt, and the tab bar's edge-effect
    /// frost extends upward to cover the accessory — scroll content
    /// dissolves through both as one visual band.
    ///
    /// Use `setBottomBarAccessory(_:animated:)` for an animated crossfade;
    /// direct assignment swaps immediately.
    public var bottomBarAccessory: TabBarAccessoryView? {
        get { _bottomBarAccessory }
        set { setBottomBarAccessory(newValue, animated: false) }
    }

    /// Assign the bottom bar accessory with an optional crossfade
    /// animation. `animated = false` matches direct property assignment.
    public func setBottomBarAccessory(_ accessory: TabBarAccessoryView?, animated: Bool) {
        guard accessory !== _bottomBarAccessory else { return }
        let old = _bottomBarAccessory
        _bottomBarAccessory = accessory
        installBottomBarAccessory(old: old, new: accessory, animated: animated)
    }

    private var _bottomBarAccessory: TabBarAccessoryView?
    private var bottomBarAccessoryWrapper: GlassBackgroundView?
    private var bottomBarAccessoryTap: UITapGestureRecognizer?
    private static let bottomBarAccessoryBottomGap: CGFloat = 8.0

    // MARK: - Expanded Accessory (Apple-Music-style morph)

    /// Controller currently presented in the expanded form. `nil` while
    /// the accessory sits in its collapsed pill state.
    public private(set) var expandedAccessoryViewController: UIViewController?

    /// `true` while the morph from collapsed → expanded (or vice versa)
    /// is in flight. Used to suppress further taps / scroll observer
    /// re-binding mid-animation.
    private var isAnimatingAccessoryExpansion: Bool = false

    private var accessoryDismissPan: UIPanGestureRecognizer?
    /// `true` once the dismiss pan has decided to "own" the gesture
    /// (either no scroll view under the finger, or the scroll view was
    /// already at its top edge). Until then, scroll views inside the
    /// expanded controller handle the touch and our handler is a no-op.
    private var accessoryDismissDragActive: Bool = false
    /// Scroll view that was pinned to the top to enable the dismiss
    /// drag — held while the gesture runs so each tick can rewrite its
    /// `contentOffset` and stop the system from scrolling underneath
    /// the card we're translating.
    private weak var accessoryDismissPinnedScroll: UIScrollView?
    /// Translation snapshot taken at the moment the dismiss pan
    /// hijacked control, so the visible Y offset starts from zero
    /// regardless of how far the user had already scrolled inside a
    /// scroll view before the hijack.
    private var accessoryDismissTranslationOrigin: CGFloat = 0

    /// Animate the accessory wrapper + its inner accessory through the
    /// minimize morph.
    ///
    /// Why a hand-rolled `UIView.animate` instead of `transition.updateFrame`:
    /// the `ContainedViewLayoutTransition.updateFrame` helper schedules
    /// the frame change and the child layout pass in *separate*
    /// animation blocks. With `GlassBackgroundView` (which re-applies
    /// internal effect-view frames inside its own `update(...)`) the
    /// nested blocks raced with the outer one and the wrapper would
    /// snap to the new frame while the spring kept running on a stale
    /// destination. Driving wrapper + accessory frame setters in a
    /// single, explicit `UIView.animate` block locks both into the
    /// same spring tick.
    private func applyAccessoryFrame(
        _ wrapper: GlassBackgroundView,
        frame: CGRect,
        transition: ContainedViewLayoutTransition
    ) {
        let innerSize = frame.size
        let accessory = _bottomBarAccessory
        let applyFrames = { [weak wrapper, weak accessory] in
            wrapper?.frame = frame
            accessory?.frame = CGRect(origin: .zero, size: innerSize)
        }

        switch transition {
        case .immediate:
            applyFrames()
        case let .animated(duration, curve):
            let damping: CGFloat
            let velocity: CGFloat
            switch curve {
            case let .customSpring(d, v):
                damping = d
                velocity = v
            case .spring:
                damping = 500.0
                velocity = 0.0
            default:
                damping = 1.0
                velocity = 0.0
            }
            UIView.animate(
                withDuration: duration,
                delay: 0,
                usingSpringWithDamping: damping,
                initialSpringVelocity: velocity,
                options: [.beginFromCurrentState, .allowUserInteraction, .layoutSubviews],
                animations: applyFrames,
                completion: nil
            )
        }

        wrapper.update(
            size: innerSize,
            cornerRadius: frame.height / 2.0,
            isDark: traitCollection.userInterfaceStyle == .dark,
            tintColor: .init(kind: .panel),
            isInteractive: true,
            isVisible: true,
            transition: transition
        )
        accessory?.updateLayout(size: innerSize, transition: transition)
    }

    private func installBottomBarAccessory(old: TabBarAccessoryView?, new: TabBarAccessoryView?, animated: Bool) {
        // Remove listener from the outgoing accessory first so it can't
        // trigger a re-layout we're about to discard anyway.
        old?.requestLayout = { _ in }

        guard isViewLoaded else {
            old?.removeFromSuperview()
            bottomBarAccessoryWrapper?.removeFromSuperview()
            bottomBarAccessoryWrapper = nil
            bottomBarAccessoryTap = nil
            return
        }

        let oldWrapper = bottomBarAccessoryWrapper
        bottomBarAccessoryWrapper = nil
        bottomBarAccessoryTap = nil

        let newWrapper: GlassBackgroundView?
        if let new {
            let wrapper = GlassBackgroundView(style: .regular)
            // Plain frame-based layout. Snapkit constraints (the prior
            // approach) would resolve the accessory's frame in a separate
            // auto-layout pass that runs OUTSIDE our spring's animation
            // block — the accessory would snap to its new size while the
            // wrapper smoothly animated, breaking the morph. Autoresizing
            // masks fight `applyAccessoryFrame`'s explicit frame setter
            // for the same reason. Both wrapper and accessory frames
            // are driven directly inside one `UIView.animate` block in
            // `applyAccessoryFrame`.
            new.translatesAutoresizingMaskIntoConstraints = true
            new.autoresizingMask = []
            new.frame = wrapper.bounds
            wrapper.addSubview(new)
            view.addSubview(wrapper)
            newWrapper = wrapper
            new.requestLayout = { [weak self] transition in
                guard let self, let layout = self.currentlyAppliedLayout else { return }
                self.containerLayoutUpdated(layout, transition: transition)
            }

            // Tap on the glass surface → expand into the accessory's
            // optional companion controller (Apple-Music-style "open
            // the player"). The recognizer is always attached, but the
            // handler bails out if no provider is set, so toggling the
            // provider on and off doesn't require re-installing the
            // accessory.
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleAccessoryTap(_:)))
            wrapper.addGestureRecognizer(tap)
            bottomBarAccessoryTap = tap
        } else {
            newWrapper = nil
        }

        bottomBarAccessoryWrapper = newWrapper

        if animated, oldWrapper != nil || newWrapper != nil {
            newWrapper?.alpha = 0
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: {
                oldWrapper?.alpha = 0
                newWrapper?.alpha = 1
            }, completion: { _ in
                oldWrapper?.removeFromSuperview()
            })
        } else {
            oldWrapper?.removeFromSuperview()
        }

        // Re-run layout so the new accessory gets positioned (and any
        // safe-area / edge-effect changes propagate to children).
        if let layout = currentlyAppliedLayout {
            let transition: ContainedViewLayoutTransition = animated
                ? .animated(duration: 0.25, curve: .easeInOut)
                : .immediate
            containerLayoutUpdated(layout, transition: transition)
        }
    }

    @objc private func handleAccessoryTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        guard !isAnimatingAccessoryExpansion, expandedAccessoryViewController == nil else { return }
        guard let provider = _bottomBarAccessory?.expandedViewControllerProvider else { return }
        guard let controller = provider() else { return }
        presentExpandedAccessory(controller, animated: true)
    }

    /// Spring parameters used by the expand / collapse morph. Damping
    /// of 0.78 gives the card a small overshoot (the "перекрут" the
    /// user asked for) before settling — closer to Apple Music's
    /// player open/close than a critically-damped curve would be.
    private static let accessoryMorphDuration: TimeInterval = 0.55
    private static let accessoryMorphDamping: CGFloat = 0.78
    private static let accessoryMorphVelocity: CGFloat = 0.0

    /// Display corner radius reported by `UIScreen` (private API access
    /// via KVC — `_displayCornerRadius`). Fallback to 0 on devices /
    /// SDKs where it isn't available; user can override visually by
    /// setting their controller's view's `layer.cornerRadius` after the
    /// expansion lands.
    private var deviceDisplayCornerRadius: CGFloat {
        guard let screen = view.window?.windowScene?.screen ?? view.window?.screen else { return 0 }
        if let value = screen.value(forKey: ObfuscatedSymbols.displayCornerRadius) as? CGFloat {
            return value
        }
        return 0
    }

    /// Cached accessory-collapsed frame / cornerRadius captured at the
    /// moment of expand — the dismiss morph springs back to these.
    /// Recording them up-front (instead of recomputing them at dismiss
    /// time) decouples the dismiss target from any chrome state changes
    /// that happened while the player was on screen (minimize toggle,
    /// rotation, etc.) — the player goes back to whatever pill it
    /// emerged from, even if the canonical accessory frame has moved.
    private var accessoryCollapsedFrame: CGRect = .zero
    private var accessoryCollapsedCornerRadius: CGFloat = 0

    /// Expand the bottom-bar accessory into a full-card presentation of
    /// `controller`. The wrapper itself is the morphing element — its
    /// frame grows from the accessory pill to a card sitting just above
    /// the tab bar, its cornerRadius animates from capsule (~24) to the
    /// device's display radius. The tab bar stays visible the whole
    /// time (Apple Music style: the chrome doesn't disappear, the pill
    /// just *becomes* the card). `controller`'s view is parented inside
    /// the wrapper and cross-faded over the existing accessory content.
    ///
    /// Idempotent — calling while another expansion is on screen or in
    /// flight is a no-op. Use `dismissExpandedAccessory(animated:)` to
    /// reverse.
    public func presentExpandedAccessory(_ controller: UIViewController, animated: Bool = true) {
        guard isViewLoaded else { return }
        guard expandedAccessoryViewController == nil, !isAnimatingAccessoryExpansion else { return }
        guard let wrapper = bottomBarAccessoryWrapper else { return }

        expandedAccessoryViewController = controller
        isAnimatingAccessoryExpansion = true

        // Pause the scroll observer — a stray scroll tick during the
        // morph would race the tab bar minimize state with the
        // player's growth.
        detachScrollObserver()

        // Snapshot the collapsed geometry so we can spring back to it
        // on dismiss, even if intermediate state changes (rotation,
        // minimize toggle) would have moved the canonical frame.
        //
        // CornerRadius isn't read from `wrapper.layer.cornerRadius` —
        // GlassBackgroundView routes the rounding to its inner native
        // effect view's layer, leaving the outer wrapper.layer at 0.
        // Using frame.height/2 reproduces what `applyAccessoryFrame`
        // applied via `wrapper.update(...)` (capsule for an accessory
        // pill, equal to half its height).
        accessoryCollapsedFrame = wrapper.frame
        accessoryCollapsedCornerRadius = wrapper.frame.height / 2.0

        // Squircle corners on the wrapper — smoother through the
        // morph than circular, and they blend correctly into the
        // device display radius at the apex.
        wrapper.layer.cornerCurve = .continuous

        // Target card frame — full screen.
        let targetFrame = expandedAccessoryFrame()
        // Keep the same corner radius as the accessory pill — the
        // user wants the expanded card to match the accessory's
        // capsule shape, not switch to a sharp / device radius.
        // `_displayCornerRadius` was returning 0 on the simulator
        // anyway, hence the "квадратные" complaint.
        let targetCornerRadius = accessoryCollapsedCornerRadius

        // Parent the controller's view INSIDE wrapper. Autoresizing
        // mask keeps it locked to wrapper.bounds throughout the spring
        // (so the controller content grows in lockstep with the glass
        // surface, not as a separate animation that could fall out of
        // sync with the wrapper's spring).
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = true
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.frame = wrapper.bounds
        controller.view.alpha = 0
        controller.view.clipsToBounds = true
        wrapper.addSubview(controller.view)
        controller.didMove(toParent: self)

        // Drag-to-dismiss pan — attached to the wrapper itself so the
        // whole card surface participates. Hijack-vs-defer logic in
        // the handler keeps it from racing scroll views inside the
        // controller.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleAccessoryDismissPan(_:)))
        pan.delegate = self
        wrapper.addGestureRecognizer(pan)
        accessoryDismissPan = pan

        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()

        let onCompletion: () -> Void = { [weak self] in
            self?.isAnimatingAccessoryExpansion = false
        }

        if animated {
            UIView.animate(
                withDuration: Self.accessoryMorphDuration,
                delay: 0,
                usingSpringWithDamping: Self.accessoryMorphDamping,
                initialSpringVelocity: Self.accessoryMorphVelocity,
                options: [.beginFromCurrentState, .allowUserInteraction, .layoutSubviews],
                animations: {
                    wrapper.frame = targetFrame
                    controller.view.alpha = 1
                    // Tab bar fades out alongside the wrapper expansion
                    // — full-screen card hides the tab bar, restored
                    // by the dismiss morph.
                    self.tabBarView.alpha = 0
                },
                completion: { _ in onCompletion() }
            )
            // Glass cornerRadius animates through the same spring on
            // its own animation timeline (cornerRadius isn't a vanilla
            // animatable property — `wrapper.update(...)` routes it
            // through `transition.setCornerRadius` which stages a
            // `CABasicAnimation`).
            wrapper.update(
                size: targetFrame.size,
                cornerRadius: targetCornerRadius,
                isDark: traitCollection.userInterfaceStyle == .dark,
                tintColor: .init(kind: .panel),
                isInteractive: true,
                isVisible: true,
                transition: .animated(duration: Self.accessoryMorphDuration, curve: .customSpring(damping: Self.accessoryMorphDamping, initialVelocity: Self.accessoryMorphVelocity))
            )
        } else {
            wrapper.frame = targetFrame
            controller.view.alpha = 1
            tabBarView.alpha = 0
            wrapper.update(
                size: targetFrame.size,
                cornerRadius: targetCornerRadius,
                isDark: traitCollection.userInterfaceStyle == .dark,
                tintColor: .init(kind: .panel),
                isInteractive: true,
                isVisible: true,
                transition: .immediate
            )
            onCompletion()
        }
    }

    /// Frame of the expanded card — the entire view bounds. Tab bar
    /// is z-ordered ABOVE the wrapper while expanded so it stays
    /// visible at the bottom even though the wrapper extends under it.
    private func expandedAccessoryFrame() -> CGRect {
        return view.bounds
    }

    /// Reverse the expand morph: wrapper frame springs back to the
    /// cached collapsed accessory pill, controller's view fades out
    /// over the existing accessory content, and the controller is
    /// removed on completion. Calling while no expansion is on screen
    /// is a no-op.
    public func dismissExpandedAccessory(animated: Bool = true) {
        guard let controller = expandedAccessoryViewController else { return }
        guard !isAnimatingAccessoryExpansion else { return }
        guard let wrapper = bottomBarAccessoryWrapper else {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            expandedAccessoryViewController = nil
            return
        }
        isAnimatingAccessoryExpansion = true

        // Commit any in-flight pan transform back to the frame so the
        // spring resumes from the visibly-dragged position instead of
        // teleporting to `wrapper.frame` (model layer value).
        if wrapper.transform != .identity {
            let visibleFrame = wrapper.frame.applying(wrapper.transform)
            wrapper.transform = .identity
            wrapper.frame = visibleFrame
        }

        let targetFrame = accessoryCollapsedFrame
        let targetCornerRadius = accessoryCollapsedCornerRadius

        let teardown: () -> Void = { [weak self, weak wrapper] in
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            guard let self else { return }
            self.expandedAccessoryViewController = nil
            self.isAnimatingAccessoryExpansion = false
            if let pan = self.accessoryDismissPan {
                wrapper?.removeGestureRecognizer(pan)
            }
            self.accessoryDismissPan = nil
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
            self.attachScrollObserverIfPossible()
            // Re-run layout so the collapsed-state z-order takes effect:
            // during expand we bring the tab bar ABOVE the wrapper (so
            // the chrome floats on top of the full-screen card), but
            // back in collapsed state the wrapper has to sit above the
            // tab bar — otherwise the tab bar's edge-effect frost
            // (which extends 12pt above the tab bar bounds via
            // `bandShift`) renders on top of the accessory pill,
            // bleeding into its glass surface.
            if let layout = self.currentlyAppliedLayout {
                self.containerLayoutUpdated(layout, transition: .immediate)
            }
        }

        if animated {
            UIView.animate(
                withDuration: Self.accessoryMorphDuration,
                delay: 0,
                usingSpringWithDamping: Self.accessoryMorphDamping,
                initialSpringVelocity: Self.accessoryMorphVelocity,
                options: [.beginFromCurrentState, .allowUserInteraction, .layoutSubviews],
                animations: {
                    wrapper.frame = targetFrame
                    controller.view.alpha = 0
                    // Tab bar fades back in alongside the collapse —
                    // matches the visual hand-off from card to chrome.
                    self.tabBarView.alpha = 1
                },
                completion: { _ in teardown() }
            )
            wrapper.update(
                size: targetFrame.size,
                cornerRadius: targetCornerRadius,
                isDark: traitCollection.userInterfaceStyle == .dark,
                tintColor: .init(kind: .panel),
                isInteractive: true,
                isVisible: true,
                transition: .animated(duration: Self.accessoryMorphDuration, curve: .customSpring(damping: Self.accessoryMorphDamping, initialVelocity: Self.accessoryMorphVelocity))
            )
        } else {
            wrapper.frame = targetFrame
            controller.view.alpha = 0
            tabBarView.alpha = 1
            wrapper.update(
                size: targetFrame.size,
                cornerRadius: targetCornerRadius,
                isDark: traitCollection.userInterfaceStyle == .dark,
                tintColor: .init(kind: .panel),
                isInteractive: true,
                isVisible: true,
                transition: .immediate
            )
            teardown()
        }
    }

    open override var childForStatusBarStyle: UIViewController? {
        return expandedAccessoryViewController ?? super.childForStatusBarStyle
    }

    open override var childForStatusBarHidden: UIViewController? {
        return expandedAccessoryViewController ?? super.childForStatusBarHidden
    }

    open override var childForHomeIndicatorAutoHidden: UIViewController? {
        return expandedAccessoryViewController ?? super.childForHomeIndicatorAutoHidden
    }

    private var tabBarHidden: Bool = false

    /// Re-entry guard for `containerLayoutUpdated`. Setting
    /// `additionalSafeAreaInsets` synchronously triggers UIKit's safe-area
    /// machinery, which calls `viewSafeAreaInsetsDidChange` →
    /// `applySelfComputedLayout(transition: .immediate)` →
    /// `containerLayoutUpdated(.immediate)`. Without this guard, the
    /// nested `.immediate` pass writes `wrapper.frame` directly BEFORE
    /// the outer animated pass has a chance to register its `UIView.animate`
    /// block — by the time the outer call gets there, the model frame
    /// already equals the target, so the animation captures `from == to`
    /// and renders no visible morph (looks like a snap). The pill /
    /// search circle live INSIDE `tabBarView` and animate inside
    /// `setMinimized` *before* we ever hit `containerLayoutUpdated`, so
    /// they're unaffected — only the bottom accessory was getting eaten.
    private var isApplyingContainerLayout: Bool = false

    // MARK: - Minimize Behavior (iOS 26 `tabBarMinimizeBehavior`)

    /// How the tab bar should behave when content scrolls. Mirrors the
    /// iOS 26 `UITabBarController.tabBarMinimizeBehavior` API surface.
    public enum TabBarMinimizeBehavior {
        /// Tab bar always stays in its full pill form (default).
        case never
        /// Scrolling DOWN (away from the top) collapses the tab bar into
        /// the iOS 26 minimized chrome: pill → 48×48 active-tab circle on
        /// the leading edge, search showcase → matching circle on the
        /// trailing edge, `bottomBarAccessory` reflows between them.
        /// Scrolling UP (or hitting the content top) expands it back.
        case onScrollDown
    }

    /// Drives the auto-minimize behaviour on scroll. Setting this to
    /// `.onScrollDown` immediately attaches a scroll observer to the
    /// current tab's primary scroll view; switching back to `.never`
    /// detaches the observer and animates the bar back to its full form.
    public var tabBarMinimizeBehavior: TabBarMinimizeBehavior = .never {
        didSet {
            guard tabBarMinimizeBehavior != oldValue else { return }
            switch tabBarMinimizeBehavior {
            case .never:
                detachScrollObserver()
                if isTabBarMinimized {
                    setTabBarMinimized(false, transition: .animated(duration: 0.35, curve: .customSpring(damping: 0.85, initialVelocity: 0)))
                }
            case .onScrollDown:
                attachScrollObserverIfPossible()
            }
        }
    }

    /// Current minimize state. Toggled either by the scroll observer
    /// (when `tabBarMinimizeBehavior == .onScrollDown`) or directly by
    /// callers via `setTabBarMinimized(_:transition:)`.
    public private(set) var isTabBarMinimized: Bool = false

    /// Toggle the minimized state with an animated morph.
    ///
    /// Drives both the tab bar's own pill→circle morph and the
    /// `bottomBarAccessory` reflow (between the circles) via the same
    /// transition. Safe to call repeatedly with the same value (no-op).
    public func setTabBarMinimized(_ minimized: Bool, transition: ContainedViewLayoutTransition) {
        guard isTabBarMinimized != minimized else { return }
        // Search mode owns the chrome — refuse to minimize while the
        // search field is up. Mirror of the same guard inside `TabBarView`.
        if minimized && tabBarView.isSearchActive {
            return
        }
        isTabBarMinimized = minimized
        tabBarView.setMinimized(minimized, transition: transition)
        if let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: transition)
        }
    }

    private var scrollObserver: TabBarScrollMinimizeObserver?
    private weak var observedScrollView: UIScrollView?

    /// Idempotent: re-binds the scroll observer to the current tab's
    /// primary scroll view if it differs from whatever's currently
    /// observed. Cheap to call on every layout pass — comparison is a
    /// single reference equality check when the target hasn't changed.
    ///
    /// Called on every `containerLayoutUpdated` so push/pop inside a
    /// tab's nav stack rebinds the observer to the freshly-visible
    /// detail screen — without it, scrolling a pushed list never
    /// triggers minimize because we'd still be watching the root.
    private func attachScrollObserverIfPossible() {
        guard tabBarMinimizeBehavior == .onScrollDown, isViewLoaded else {
            detachScrollObserver()
            return
        }
        let target = primaryScrollViewForCurrentTab()
        if let observed = observedScrollView, observed === target {
            return
        }
        scrollObserver?.invalidate()
        scrollObserver = nil
        observedScrollView = target
        guard let target else { return }
        scrollObserver = TabBarScrollMinimizeObserver(scrollView: target) { [weak self] direction in
            guard let self else { return }
            // Don't fight the user when search is active — the search
            // morph drives the chrome and minimize would race it.
            if self.tabBarView.isSearchActive { return }
            switch direction {
            case .down:
                self.setTabBarMinimized(true, transition: .animated(duration: 0.35, curve: .customSpring(damping: 0.85, initialVelocity: 0)))
            case .upOrAtTop:
                self.setTabBarMinimized(false, transition: .animated(duration: 0.35, curve: .customSpring(damping: 0.85, initialVelocity: 0)))
            }
        }
    }

    private func detachScrollObserver() {
        scrollObserver?.invalidate()
        scrollObserver = nil
        observedScrollView = nil
    }

    /// BFS for the first scroll view inside the current tab's view tree.
    /// Mirrors `firstScrollView` used by the active-tab re-tap handler so
    /// both behaviours target the same scroll view.
    private func primaryScrollViewForCurrentTab() -> UIScrollView? {
        let target: UIViewController?
        if let nav = currentController as? AetherNavigationController {
            target = nav.topController
        } else {
            target = currentController
        }
        guard let root = target?.view else { return nil }
        return Self.firstScrollView(in: root)
    }

    // MARK: - Init

    public init(tabBarTheme: TabBarView.Theme = TabBarView.Theme()) {
        self.tabBarTheme = tabBarTheme
        self.tabBarView = TabBarView(theme: tabBarTheme)

        // Deliberately no nav bar: each tab brings its own through its
        // embedded navigation controller / content screen.
        super.init(navigationBarPresentationData: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()

        tabBarView.tabSelected = { [weak self] index in
            guard let self = self else { return }
            if index == self._selectedIndex {
                self.handleActiveTabReTap()
            } else {
                self.selectedIndex = index
            }
        }

        tabBarView.tabDoubleTapped = { [weak self] index in
            guard let self, index < self._controllers.count else { return }
            (self._controllers[index] as? AetherViewController)?.tabBarItemPerformDoubleTapAction()
        }

        tabBarView.itemHasDoubleTapAction = { [weak self] index in
            guard let self, index < self._controllers.count else { return false }
            return (self._controllers[index] as? AetherViewController)?.tabBarItemHasDoubleTapAction() ?? false
        }

        tabBarView.tabLongPressed = { [weak self] index, sourceView, gesture in
            guard let self, index < self._controllers.count else { return }

            // Modern menu-items path — resolved via
            // `contextMenuItems(forTabAt:)`, no dependency on the tab's
            // controller being a Aether `ViewController`. Works for
            // plain `UIViewController` and `AetherNavigationController`
            // tabs (which used to fall through the old `as? ViewController`
            // guard and never get a menu).
            let menuItems = self.contextMenuItems(forTabAt: index)
            if !menuItems.isEmpty {
                ContextMenuController.present(source: sourceView, items: menuItems)
                return
            }

            // Legacy path — requires a Aether `ViewController`. Honour
            // the controller's explicit `tabBarItemContextActionType`
            // choice; silent no-op for non-Aether controllers (their
            // only "new" path is the menu-items API above).
            guard let controller = self._controllers[index] as? AetherViewController else { return }
            switch controller.tabBarItemContextActionType {
            case .none:
                controller.longTapWithTabBar?()
            case .always:
                controller.tabBarItemContextAction(sourceView: sourceView, gesture: gesture)
            case .whenActive:
                if index == self._selectedIndex {
                    controller.tabBarItemContextAction(sourceView: sourceView, gesture: gesture)
                } else {
                    controller.longTapWithTabBar?()
                }
            }
        }

        tabBarView.tabSwipeAction = { [weak self] index, direction in
            guard let self, index < self._controllers.count else { return }
            (self._controllers[index] as? AetherViewController)?.tabBarItemSwipeAction(direction: direction)
        }

        tabBarView.disabledPressed = { [weak self] in
            (self?.currentController as? AetherViewController)?.tabBarDisabledAction()
        }

        // Tap on the collapsed pill in minimized mode → expand back to
        // the full chrome. The tab bar fires this when the user taps
        // the 48×48 active-tab circle.
        tabBarView.onExpandRequested = { [weak self] in
            guard let self else { return }
            self.setTabBarMinimized(false, transition: .animated(duration: 0.35, curve: .customSpring(damping: 0.85, initialVelocity: 0)))
        }

        view.addSubview(tabBarView)

        if let current = currentController {
            showController(current, animated: false)
        }

        // After the first tab is shown, subscribe to its primary scroll
        // view if `tabBarMinimizeBehavior` is on. Subsequent tab switches
        // rebind through `transitionToController` / `showController`.
        attachScrollObserverIfPossible()
    }

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applySelfComputedLayout(transition: .immediate)
    }

    override open func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        applySelfComputedLayout(transition: .immediate)
    }

    /// When this controller is used as a root (the common case — tab bar
    /// at the window level), there is no parent driving layout for us.
    /// Compute a `ContainerViewLayout` from our own view's bounds + safe
    /// area insets and flow it through `containerLayoutUpdated` so our
    /// tab bar positions itself and the child tab receives an updated
    /// layout.
    private func applySelfComputedLayout(transition: ContainedViewLayoutTransition) {
        let layout = ContainerViewLayout(
            size: view.bounds.size,
            metrics: LayoutMetrics(
                widthClass: view.traitCollection.horizontalSizeClass == .regular ? .regular : .compact,
                isTablet: UIDevice.current.userInterfaceIdiom == .pad
            ),
            safeInsets: view.safeAreaInsets,
            additionalInsets: .zero,
            statusBarHeight: view.window?.windowScene?.statusBarManager?.statusBarFrame.height,
            inputHeight: currentlyAppliedLayout?.inputHeight,
            inputHeightIsInteractivellyChanging: currentlyAppliedLayout?.inputHeightIsInteractivellyChanging ?? false,
            inVoiceOver: UIAccessibility.isVoiceOverRunning
        )
        containerLayoutUpdated(layout, transition: transition)
    }

    // MARK: - Public API

    public func setControllers(_ controllers: [UIViewController], selectedIndex: Int?) {
        let previousController = currentController

        self._controllers = controllers
        self._selectedIndex = selectedIndex ?? min(_selectedIndex, max(0, controllers.count - 1))

        // Build tab items
        let items = controllers.map { controller -> AetherTabBarItem in
            let tabItem = controller.tabBarItem
            return AetherTabBarItem(
                title: tabItem?.title ?? "",
                image: tabItem?.image,
                selectedImage: tabItem?.selectedImage,
                badgeValue: tabItem?.badgeValue,
                isEnabled: true
            )
        }
        tabBarView.items = items
        tabBarView.selectedIndex = _selectedIndex

        if let previous = previousController, previous !== currentController {
            detachControllerIfNeeded(previous)
        }

        if let current = currentController, isViewLoaded {
            showController(current, animated: false)
        }

        // New tab tree → new primary scroll view. Drop the old observer
        // and bind to the freshly visible tab's content.
        attachScrollObserverIfPossible()
    }

    public func updateIsTabBarHidden(_ hidden: Bool, transition: ContainedViewLayoutTransition) {
        self.tabBarHidden = hidden
        if let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: transition)
        }
    }

    public func updateIsTabBarEnabled(_ enabled: Bool, transition: ContainedViewLayoutTransition) {
        tabBarView.updateInteractionsEnabled(enabled, transition: transition)
    }

    public func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        tabBarView.updateBackgroundAlpha(alpha, transition: transition)
    }

    public func frameForControllerTab(controller: UIViewController) -> CGRect? {
        guard let index = _controllers.firstIndex(where: { $0 === controller }) else { return nil }
        return tabBarView.frameForTab(at: index)
    }

    public func isPointInsideContentArea(point: CGPoint) -> Bool {
        let tabBarFrame = tabBarView.frame
        return point.y < tabBarFrame.minY
    }

    /// Frame of the tab bar pill (selection capsule) in `targetView`'s
    /// coordinate space. Returns `nil` if the tab bar hasn't laid out yet
    /// or the two views don't share a window.
    ///
    /// Use this to anchor floating overlays (toolbars, badges, etc.) to
    /// the pill without hardcoding the theme's pill height / bottom
    /// inset, which would drift the moment either is customized.
    public func pillFrame(in targetView: UIView) -> CGRect? {
        guard isViewLoaded, tabBarView.bounds.width > 0 else { return nil }
        let pillInTabBar = tabBarView.pillFrame
        guard pillInTabBar.width > 0 else { return nil }
        return tabBarView.convert(pillInTabBar, to: targetView)
    }

    /// Resolve the list of context-menu items to present on a long-press
    /// of the tab at `index`. Default implementation forwards to
    /// `tabContextMenuItemsProvider`; subclasses may override for more
    /// complex logic (per-state menus, async data, etc.). Returning an
    /// empty array suppresses the menu for that tab.
    open func contextMenuItems(forTabAt index: Int) -> [ContextMenuItem] {
        return tabContextMenuItemsProvider?(index) ?? []
    }

    // MARK: - Layout

    override open func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        // Intentionally NOT calling super: the base `ViewController`
        // implementation assumes this controller owns a nav bar and
        // computes `additionalSafeAreaInsets` for that. TabBarController
        // has no nav bar and needs to set `additionalSafeAreaInsets` to
        // propagate the TAB BAR height instead — letting super run
        // causes the two writers to fight and re-trigger each other via
        // UIKit's "safe area changed → schedule layout" path (infinite
        // recursion).

        // Skip the nested `.immediate` re-entry caused by setting
        // `additionalSafeAreaInsets` mid-pass. See `isApplyingContainerLayout`
        // doc comment — if we let it run we'd snap the accessory frame
        // before the outer animated pass registers its UIView.animate
        // block, killing the morph.
        if isApplyingContainerLayout {
            return
        }
        isApplyingContainerLayout = true
        defer { isApplyingContainerLayout = false }

        updateCurrentContainerLayout(layout)

        // TabBarView is at most 103pt TOTAL (safe area included inside).
        let tabBarHeight: CGFloat = TabBarView.defaultHeight // 103, never more
        // Use RAW device safe area (not layout.safeInsets which includes
        // our own additionalSafeAreaInsets — using that causes infinite recursion).
        let rawSafeBottom = view.window?.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom
        let tabBarContentInset = tabBarHidden ? 0.0 : max(0.0, tabBarHeight - rawSafeBottom)

        // Accessory chrome pushed onto children in addition to the pill.
        // Hidden when the tab bar itself hides (the accessory has no
        // standalone anchor — it lives on top of the pill).
        // In minimized mode, the accessory reflows INTO the pill row
        // (between the two 48×48 circles), so it no longer reserves
        // vertical space above the pill — children get only the tab
        // bar height and the accessory shares the same row.
        let accessoryHeight: CGFloat = (!tabBarHidden && !isTabBarMinimized) ? (_bottomBarAccessory?.height ?? 0) : 0
        let accessoryTotalReservation: CGFloat = accessoryHeight > 0
            ? accessoryHeight + Self.bottomBarAccessoryBottomGap
            : 0

        // Propagate the tab-bar height + accessory reservation to embedded
        // children via UIKit's safe area machinery. Anything below us —
        // embedded nav controllers, plain view controllers — will see
        // their `view.safeAreaInsets.bottom` include both, so they can
        // lay content above our chrome without knowing we exist.
        let desiredChildInsets = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: tabBarContentInset + accessoryTotalReservation,
            right: 0
        )
        if additionalSafeAreaInsets != desiredChildInsets {
            additionalSafeAreaInsets = desiredChildInsets
        }

        // When tab bar search is active AND keyboard is visible, lift the tab bar above the keyboard
        let isKeyboardVisible = (layout.inputHeight ?? 0) > 0
        let keyboardLift: CGFloat = tabBarView.isSearchActive ? (layout.inputHeight ?? 0) : 0
        let tabBarY: CGFloat = tabBarHidden ? layout.size.height : (layout.size.height - tabBarHeight - keyboardLift)
        let tabBarFrame = CGRect(x: 0, y: tabBarY, width: layout.size.width, height: tabBarHeight)
        transition.updateFrame(view: tabBarView, frame: tabBarFrame)

        // Drive search-mode chrome that depends on keyboard state — the
        // active-tab circle inside `TabBarView` cross-fades through this
        // (visible when the keyboard is down so the user has somewhere
        // to tap to exit, hidden when the keyboard owns the bottom of
        // the screen).
        tabBarView.setKeyboardVisible(isKeyboardVisible, transition: transition)

        // While search owns the chrome and the keyboard is up, fade the
        // accessory pill out — it would overlap the search row that
        // hugs the keyboard's top edge. With the keyboard down (search
        // still active) the accessory comes back, but it has to anchor
        // to the SEARCH ROW instead of the (invisible) tab pill so the
        // 8pt gap above it matches the no-search state — see
        // `searchRowTopOffset` below.
        let shouldFadeAccessoryForSearch = tabBarView.isSearchActive && isKeyboardVisible
        // The search row sits a few points below the tab pill's top
        // edge (capsule height < pill height). When search is active
        // and visible (keyboard down) we slide the accessory down by
        // that offset so it lands 8pt above the row, not 8pt above the
        // empty space the tab pill used to fill.
        let searchTopAdjustment: CGFloat = tabBarView.isSearchActive && !isKeyboardVisible
            ? tabBarView.searchRowTopOffset
            : 0

        // Pill frame is computed analytically rather than read after a
        // synchronous `tabBarView.layoutSubviews()` — that synchronous
        // call would override the in-flight morph by re-setting inner
        // frames with `.immediate`, snapping the pill / search circle
        // into place and killing the animation.
        let pillFrameInTab = tabBarView.computePillFrame(in: tabBarFrame.size, minimized: isTabBarMinimized)
        let pillTopInController = tabBarY + pillFrameInTab.minY

        // Position the bottom bar accessory (glass pill).
        //
        // Two layouts depending on minimize state:
        //   • Expanded — sits 8pt above the tab bar pill, full width.
        //   • Minimized — reflows INTO the pill row between the two
        //     48×48 circles (matches iOS 26's `tabBarMinimizeBehavior`,
        //     where the accessory drops down to fill the gap created by
        //     the collapsing tab bar).
        // Skip canonical accessory layout while the wrapper is in its
        // expanded card form — `presentExpandedAccessory` owns the
        // wrapper frame at that point, and overwriting it here mid-
        // morph would yank the card back to the pill position. Layout
        // resumes its normal control once the dismiss morph finishes.
        let updateAccessoryAlpha = { [weak self] (wrapper: GlassBackgroundView) in
            guard let _ = self else { return }
            let target: CGFloat = shouldFadeAccessoryForSearch ? 0.0 : 1.0
            if abs(wrapper.alpha - target) > 0.001 {
                transition.updateAlpha(view: wrapper, alpha: target)
            }
        }

        if expandedAccessoryViewController != nil {
            // Don't touch wrapper geometry while expanded.
        } else if isTabBarMinimized, _bottomBarAccessory != nil, let wrapper = bottomBarAccessoryWrapper, !tabBarHidden {
            let pillSize = TabBarView.minimizedButtonSize
            let sideInset = tabBarTheme.sideInset
            // Gap between each circle and the accessory pill in the row.
            // 8pt mirrors the visual breathing room iOS 26 leaves between
            // the minimized tab button and the player band.
            let interGap: CGFloat = 8.0
            let accessoryX = sideInset + pillSize + interGap
            let accessoryRight = layout.size.width - sideInset - pillSize - interGap
            let accessoryWidth = max(0, accessoryRight - accessoryX)
            let accessoryFrame = CGRect(
                x: accessoryX,
                y: pillTopInController,
                width: accessoryWidth,
                height: pillSize
            )
            applyAccessoryFrame(wrapper, frame: accessoryFrame, transition: transition)
            wrapper.isHidden = false
            updateAccessoryAlpha(wrapper)
            view.bringSubviewToFront(wrapper)
        } else if let _ = _bottomBarAccessory, let wrapper = bottomBarAccessoryWrapper, accessoryHeight > 0 {
            let accessoryAnchorY = pillTopInController + searchTopAdjustment
            let accessoryY = accessoryAnchorY - Self.bottomBarAccessoryBottomGap - accessoryHeight
            let sideInset = tabBarTheme.sideInset
            let accessoryWidth = max(0, layout.size.width - sideInset * 2)
            let accessoryFrame = CGRect(
                x: sideInset,
                y: accessoryY,
                width: accessoryWidth,
                height: accessoryHeight
            )
            applyAccessoryFrame(wrapper, frame: accessoryFrame, transition: transition)
            wrapper.isHidden = false
            updateAccessoryAlpha(wrapper)
            view.bringSubviewToFront(wrapper)
        } else if let wrapper = bottomBarAccessoryWrapper {
            // Tab bar hidden (or accessory set but h == 0) — park wrapper
            // off-screen so child layout isn't affected by stale frames.
            wrapper.isHidden = true
        }

        // Extend the tab bar's edge-effect frost upward to cover the
        // accessory + its 8pt bottom gap. Scroll content then dissolves
        // through both as a single visual band.
        //
        // While the accessory is faded out for the search keyboard, the
        // frost should snap back to the tab bar's own height — leaving
        // the extension up would render a tall blur band over content
        // with nothing actually sitting in it. `additionalSafeAreaInsets`
        // (computed above) keeps using the canonical reservation so
        // child controllers don't dance their content up and down as
        // the keyboard toggles.
        let visibleAccessoryReservation: CGFloat = shouldFadeAccessoryForSearch
            ? 0
            : max(0, accessoryTotalReservation - searchTopAdjustment)
        if tabBarView.bottomAccessoryReservedHeight != visibleAccessoryReservation {
            transition.animateView { [weak tabBarView] in
                tabBarView?.bottomAccessoryReservedHeight = visibleAccessoryReservation
                tabBarView?.layoutIfNeeded()
            }
        }

        if let current = currentController {
            transition.updateFrame(view: current.view, frame: CGRect(origin: .zero, size: layout.size))
            // Our AetherNavigationController recomputes its own layout
            // from `view.safeAreaInsets` in `viewDidLayoutSubviews`, so
            // setting `self.additionalSafeAreaInsets` above is enough —
            // UIKit will flow the new safe-area into the child and
            // trigger a layout pass there. We still forward an explicit
            // containerLayoutUpdated for non-AetherNavigation children
            // that rely on our layout object shape.
            let childLayout = ContainerViewLayout(
                size: layout.size,
                metrics: layout.metrics,
                safeInsets: layout.safeInsets,
                additionalInsets: UIEdgeInsets(
                    top: layout.additionalInsets.top,
                    left: layout.additionalInsets.left,
                    bottom: layout.additionalInsets.bottom + tabBarContentInset + accessoryTotalReservation,
                    right: layout.additionalInsets.right
                ),
                statusBarHeight: layout.statusBarHeight,
                inputHeight: layout.inputHeight,
                inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging,
                inVoiceOver: layout.inVoiceOver
            )
            if let navController = current as? AetherNavigationController {
                navController.containerLayoutUpdated(childLayout, transition: transition)
            } else if let tgController = current as? AetherViewController {
                tgController.containerLayoutUpdated(childLayout, transition: transition)
            }
        }

        // While the accessory is expanded, the wrapper covers the
        // entire screen — the tab bar floats ABOVE it so it stays
        // visible at the bottom. In collapsed state the wrapper sits
        // above the pill (just like before), so it's safe to bring it
        // forward AFTER the tab bar in that case too.
        if expandedAccessoryViewController != nil, let wrapper = bottomBarAccessoryWrapper {
            view.bringSubviewToFront(wrapper)
            view.bringSubviewToFront(tabBarView)
        } else {
            view.bringSubviewToFront(tabBarView)
            if let wrapper = bottomBarAccessoryWrapper, !wrapper.isHidden {
                view.bringSubviewToFront(wrapper)
            }
        }

        // After layout settles, re-check the observed scroll view —
        // push/pop inside the visible tab swaps in a new top controller
        // (and therefore a new primary scroll view) without going
        // through `transitionToController`, so the binding has to be
        // refreshed here too. Idempotent when the scroll view hasn't
        // changed.
        attachScrollObserverIfPossible()
    }

    /// Y coordinate (in `targetView`'s coord space) of the topmost edge
    /// of the tab bar's visible chrome — the accessory top when one is
    /// installed, otherwise the pill top. Floating overlays (toolbars,
    /// banners) should anchor to this so they always sit above whatever
    /// chrome is currently showing.
    public func chromeTopY(in targetView: UIView) -> CGFloat? {
        guard isViewLoaded, tabBarView.bounds.width > 0 else { return nil }
        if let wrapper = bottomBarAccessoryWrapper, !wrapper.isHidden {
            let origin = wrapper.convert(CGPoint.zero, to: targetView)
            return origin.y
        }
        let pillInTabBar = tabBarView.pillFrame
        guard pillInTabBar.width > 0 else { return nil }
        let pillTopInTargetView = tabBarView.convert(CGPoint(x: pillInTabBar.minX, y: pillInTabBar.minY), to: targetView)
        return pillTopInTargetView.y
    }

    /// Activate tab bar search: expands the search button into a search field.
    /// Does NOT affect the navigation bar — that's a separate action.
    public func activateSearch() {
        // Search and minimize fight over the same chrome — expand back
        // to the full pill before activating search so the morph runs
        // off the canonical layout. Use `.immediate` so the search morph
        // starts from a settled state instead of mid-spring.
        if isTabBarMinimized {
            setTabBarMinimized(false, transition: .immediate)
        }
        tabBarView.activateSearchMode(animated: true)
        tabBarView.onSearchDismissed = { [weak self] in
            self?.deactivateSearch()
        }
    }

    /// Deactivate tab bar search: collapses the search field back to the tab bar.
    public func deactivateSearch() {
        tabBarView.deactivateSearchMode(animated: true)
        // When dismissed via the active-tab circle the keyboard is
        // already down, so no `keyboardWillHide` notification fires to
        // re-run our `containerLayoutUpdated` — the accessory would be
        // left at its search-row offset / shrunken frost reservation.
        // Force a layout pass through the same transition used by the
        // search collapse so the accessory and frost spring back to
        // their canonical position together with the chrome morph.
        requestLayout(transition: .animated(duration: 0.3, curve: .easeInOut))
    }

    // MARK: - Private

    /// Respond to a tap on the already-selected tab.
    ///
    /// Native-iOS behaviour the user expects:
    ///   1. Nav stack has anything pushed → `popToRoot(animated:)`.
    ///   2. Already at root → scroll the visible content to top.
    ///      Prefers the explicit `scrollToTopWithTabBar` closure on
    ///      the top controller, falls back to the first scrollable
    ///      view inside the controller's view hierarchy so the
    ///      behaviour works out of the box without the controller
    ///      having to wire the closure.
    private func handleActiveTabReTap() {
        if let nav = currentController as? AetherNavigationController,
           nav.viewControllerStack.count > 1 {
            nav.popToRoot(animated: true)
            return
        }

        // Resolve the controller whose content we should scroll. For a
        // nav, that's its top (which equals its root at this point).
        let targetController: UIViewController?
        if let nav = currentController as? AetherNavigationController {
            targetController = nav.topController
        } else {
            targetController = currentController
        }

        // Explicit closure takes priority (allows custom scroll
        // behaviours — e.g. scrolling a non-UIScrollView virtual list).
        if let tg = targetController as? AetherViewController,
           let closure = tg.scrollToTopWithTabBar {
            closure()
            return
        }

        // Automatic fallback: walk the view tree for a UIScrollView and
        // scroll it to its top content inset.
        if let root = targetController?.view,
           let scrollView = Self.firstScrollView(in: root) {
            let topY = -scrollView.adjustedContentInset.top
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: topY), animated: true)
        }
    }

    /// Breadth-first search for the first visible `UIScrollView`
    /// descendant. BFS (not DFS) because a typical screen layout puts
    /// the main content scroll view near the top of the subview list —
    /// DFS would prefer nested scroll views inside menus, headers, etc.
    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        var queue: [UIView] = [view]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let scroll = next as? UIScrollView, !scroll.isHidden, scroll.alpha > 0.01 {
                return scroll
            }
            queue.append(contentsOf: next.subviews)
        }
        return nil
    }

    private func transitionToController(at index: Int, from previousIndex: Int, animated: Bool) {
        guard index < _controllers.count else { return }
        let newController = _controllers[index]

        for (controllerIndex, controller) in _controllers.enumerated() where controller.isViewLoaded {
            controller.view.layer.removeAllAnimations()
            if controllerIndex == index { continue }
            detachControllerIfNeeded(controller)
            controller.view.alpha = 1.0
            controller.view.transform = .identity
        }

        if animated {
            newController.view.frame = view.bounds
            // iOS 18-style tab switch: barely-noticeable scale + fade.
            newController.view.alpha = 0.0
            newController.view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)

            let didAttach = attachControllerIfNeeded(newController)
            view.insertSubview(newController.view, belowSubview: tabBarView)
            if didAttach {
                newController.didMove(toParent: self)
            }
            view.bringSubviewToFront(tabBarView)

            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState],
                animations: {
                    newController.view.alpha = 1.0
                    newController.view.transform = .identity
                },
                completion: { [weak self] finished in
                    guard let self else { return }
                    guard finished, self._selectedIndex == index else { return }
                    newController.view.transform = .identity
                    if let layout = self.currentlyAppliedLayout {
                        self.containerLayoutUpdated(layout, transition: .immediate)
                    }
                }
            )
        } else {
            showController(newController, animated: false)
        }

        // Tab swap → bind the scroll observer to the new tab's content
        // so the next scroll-down minimize fires off this tab's data.
        attachScrollObserverIfPossible()
    }

    private func showController(_ controller: UIViewController, animated: Bool) {
        let didAttach = attachControllerIfNeeded(controller)
        controller.view.frame = view.bounds
        view.insertSubview(controller.view, belowSubview: tabBarView)
        if didAttach {
            controller.didMove(toParent: self)
        }
        view.bringSubviewToFront(tabBarView)

        if let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    @discardableResult
    private func attachControllerIfNeeded(_ controller: UIViewController) -> Bool {
        guard controller.parent !== self else { return false }
        addChild(controller)
        return true
    }

    private func detachControllerIfNeeded(_ controller: UIViewController) {
        controller.view.removeFromSuperview()
        guard controller.parent === self else { return }
        controller.willMove(toParent: nil)
        controller.removeFromParent()
    }

    @objc private func handleAccessoryDismissPan(_ recognizer: UIPanGestureRecognizer) {
        guard let wrapper = bottomBarAccessoryWrapper else { return }
        guard expandedAccessoryViewController != nil else { return }

        switch recognizer.state {
        case .began:
            accessoryDismissDragActive = false
            accessoryDismissPinnedScroll = nil
            accessoryDismissTranslationOrigin = 0
            wrapper.layer.removeAllAnimations()
        case .changed:
            let translationY = recognizer.translation(in: view).y
            let velocityY = recognizer.velocity(in: view).y

            if !accessoryDismissDragActive {
                // Decide whether to hijack from any scroll view
                // currently under the finger. Same rules as before:
                // no scroll under finger → hijack; scroll at top +
                // moving down → hijack and pin scroll. Otherwise the
                // scroll keeps the gesture.
                let touchLocation = recognizer.location(in: wrapper)
                let scrollUnderTouch = topmostScrollView(at: touchLocation, in: wrapper)
                let scrollAtTop: Bool
                if let scroll = scrollUnderTouch {
                    let topY = -scroll.adjustedContentInset.top
                    scrollAtTop = scroll.contentOffset.y <= topY + 0.5
                } else {
                    scrollAtTop = true
                }
                let goingDown = translationY > 0 || velocityY > 0
                if scrollAtTop && goingDown {
                    accessoryDismissDragActive = true
                    accessoryDismissPinnedScroll = scrollUnderTouch
                    accessoryDismissTranslationOrigin = translationY
                } else {
                    return
                }
            }

            if let scroll = accessoryDismissPinnedScroll {
                let topY = -scroll.adjustedContentInset.top
                if scroll.contentOffset.y != topY {
                    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: topY), animated: false)
                }
            }

            // Translate the wrapper via `transform` so the card simply
            // slides down under the finger — frame, cornerRadius, and
            // controller view alpha all stay at their expanded values
            // (no morph during the pull, only on release).
            let yOffset = max(0, translationY - accessoryDismissTranslationOrigin)
            wrapper.transform = CGAffineTransform(translationX: 0, y: yOffset)
        case .ended, .cancelled, .failed:
            defer {
                accessoryDismissDragActive = false
                accessoryDismissPinnedScroll = nil
                accessoryDismissTranslationOrigin = 0
            }
            guard accessoryDismissDragActive else { return }

            let yTranslation = recognizer.translation(in: view).y - accessoryDismissTranslationOrigin
            let yVelocity = recognizer.velocity(in: view).y
            let dismissThreshold: CGFloat = view.bounds.height * 0.25
            let velocityThreshold: CGFloat = 800
            let shouldDismiss = recognizer.state == .ended
                && (yTranslation > dismissThreshold || yVelocity > velocityThreshold)

            if shouldDismiss {
                // `dismissExpandedAccessory` commits the live transform
                // into the frame and runs the standard spring back to
                // the collapsed pill — so the dismiss morph picks up
                // smoothly from where the finger let go.
                dismissExpandedAccessory(animated: true)
            } else {
                // Snap card back to identity with the standard spring.
                // Tab bar / chrome stayed visible the whole time so
                // there are no alpha values to restore here.
                UIView.animate(
                    withDuration: Self.accessoryMorphDuration,
                    delay: 0,
                    usingSpringWithDamping: Self.accessoryMorphDamping,
                    initialSpringVelocity: Self.accessoryMorphVelocity,
                    options: [.beginFromCurrentState, .allowUserInteraction]
                ) {
                    wrapper.transform = .identity
                }
            }
        default:
            break
        }
    }

    /// Walks the hit-test path at `location` (in `container`'s coords)
    /// and returns the deepest scroll-enabled `UIScrollView`, if any.
    /// Used by the dismiss pan to decide whether the gesture should
    /// fight a scroll view or just translate the card.
    private func topmostScrollView(at location: CGPoint, in container: UIView) -> UIScrollView? {
        guard let hit = container.hitTest(location, with: nil) else { return nil }
        var current: UIView? = hit
        while let v = current {
            if let scroll = v as? UIScrollView, scroll.isScrollEnabled {
                return scroll
            }
            if v === container { return nil }
            current = v.superview
        }
        return nil
    }
}

extension AetherTabBarController: UIGestureRecognizerDelegate {
    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // The dismiss pan needs to track touches that scroll views
        // also see — otherwise the scroll's pan would steal the
        // gesture and our handler would never run when the user
        // starts dragging from inside a scrolling area. Letting both
        // recognize keeps the touch flowing to our handler, where the
        // hijack-or-defer decision lives.
        if gestureRecognizer === accessoryDismissPan || otherGestureRecognizer === accessoryDismissPan {
            return true
        }
        return false
    }
}

/// Observes a scroll view's `contentOffset` and reports user-driven
/// direction changes — the signal that drives `tabBarMinimizeBehavior`.
///
/// Decisions are anchored to the offset where we last toggled, not the
/// previous tick — this prevents inertial wiggle from flipping state.
/// The user has to scroll past `threshold` from the last decision point
/// to trigger a new direction, and any time the content reaches the top
/// (`y <= -adjustedContentInset.top + nearTopBuffer`) we force expand,
/// matching the native iOS 26 "near top → bar always visible" rule.
private final class TabBarScrollMinimizeObserver: NSObject {
    enum Direction {
        case down
        case upOrAtTop
    }

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private let onChange: (Direction) -> Void
    private var lastDecisionOffsetY: CGFloat
    private var lastEmittedDirection: Direction?
    private var lastEmittedAt: CFTimeInterval = 0
    private var hasEmitted: Bool = false
    /// Sticky `canScroll` value — see `canScrollDeadband` doc comment.
    private var lastCanScroll: Bool?

    private static let threshold: CGFloat = 12.0
    private static let nearTopBuffer: CGFloat = 16.0
    /// Minimum gap between two state-toggling emissions. Combined with the
    /// `lastEmittedDirection` de-duplication this stops the bounce-loop
    /// you get on short content (offset wobbles around max while the
    /// scroller settles → KVO ticks alternating directions → tab bar
    /// flickers between minimized and expanded).
    private static let toggleCooldown: CFTimeInterval = 0.25
    /// Hysteresis margin around the "can the content scroll" decision
    /// boundary. Guards against an animated `contentInset` change
    /// (e.g. tab-bar minimize toggling its own height while the keyboard
    /// is up, or the search bar morph during keyboard-driven layout
    /// passes) flipping `canScroll` mid-animation: minimize shrinks the
    /// chrome → viewport grows → `canScroll` flips false → we emit
    /// `.upOrAtTop` → expand → viewport shrinks → `canScroll` flips
    /// true → we emit `.down` again → loop.
    /// With a deadband, `canScroll` only flips when the gap between
    /// `contentSize` and `viewportHeight` clears the band on its OWN
    /// side, so transient mid-animation viewport sizes don't toggle it.
    private static let canScrollDeadband: CGFloat = 24.0

    init(scrollView: UIScrollView, onChange: @escaping (Direction) -> Void) {
        self.scrollView = scrollView
        self.onChange = onChange
        self.lastDecisionOffsetY = scrollView.contentOffset.y
        super.init()
        // KVO (rather than delegate forwarding) keeps the observer
        // unaware of whatever `UIScrollViewDelegate` the host already
        // installed — important since callers usually own that delegate
        // for their own data plumbing.
        self.observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
            self?.process(scrollView: sv)
        }
    }

    func invalidate() {
        observation?.invalidate()
        observation = nil
    }

    deinit {
        observation?.invalidate()
    }

    private func process(scrollView: UIScrollView) {
        // Only react to user-driven scrolls. Programmatic
        // `setContentOffset` calls (table reloads, scroll-to-top from
        // re-tap, etc.) shouldn't toggle the chrome.
        let userDriven = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        guard userDriven else { return }

        // If the content can't actually scroll (fits within the
        // viewport), the bar must stay expanded — otherwise the
        // rubber-band on a forced down-drag generates a fake "scroll
        // down" reading and we'd start the minimize/expand race loop
        // the user reported on short lists.
        let viewportHeight = scrollView.bounds.height
            - scrollView.adjustedContentInset.top
            - scrollView.adjustedContentInset.bottom
        let diff = scrollView.contentSize.height - viewportHeight
        let canScroll: Bool
        if let last = lastCanScroll {
            // Hysteresis: if we previously decided the content was
            // scrollable, we keep saying so until the diff drops a
            // full deadband BELOW zero (and vice versa). Without this
            // an animated `contentInset` change makes the diff
            // wobble across zero during the animation and flips
            // `canScroll` every frame.
            canScroll = last
                ? diff > -Self.canScrollDeadband
                : diff > Self.canScrollDeadband
        } else {
            canScroll = diff > 0.5
        }
        lastCanScroll = canScroll
        guard canScroll else {
            emitIfNeeded(.upOrAtTop, atOffset: scrollView.contentOffset.y, allowDuringCooldown: true)
            return
        }

        let topAdjustedY = -scrollView.adjustedContentInset.top
        let y = scrollView.contentOffset.y

        if y <= topAdjustedY + Self.nearTopBuffer {
            // Always force expand near the top — matches the native
            // iOS 26 rule (bar visible whenever content top is reached).
            // No threshold gate here so a slow drag back to the top
            // still expands cleanly.
            lastDecisionOffsetY = y
            emitIfNeeded(.upOrAtTop, atOffset: y, allowDuringCooldown: true)
            return
        }

        let delta = y - lastDecisionOffsetY
        guard abs(delta) >= Self.threshold else { return }

        let direction: Direction = delta > 0 ? .down : .upOrAtTop
        emitIfNeeded(direction, atOffset: y, allowDuringCooldown: false)
        lastDecisionOffsetY = y
    }

    /// Centralised gate for `onChange` calls. Drops emissions that
    /// would just re-affirm the current state, and applies the cooldown
    /// to back-to-back direction flips. `allowDuringCooldown` lets the
    /// "near top" case still fire even if the user yanked the bar back
    /// up within the cooldown window — they explicitly want it visible.
    private func emitIfNeeded(_ direction: Direction, atOffset offsetY: CGFloat, allowDuringCooldown: Bool) {
        let now = CACurrentMediaTime()
        if hasEmitted && lastEmittedDirection == direction {
            // No-op: already in this state, no need to re-fire and
            // restart the controller's animation.
            return
        }
        if hasEmitted, !allowDuringCooldown, now - lastEmittedAt < Self.toggleCooldown {
            return
        }
        hasEmitted = true
        lastEmittedDirection = direction
        lastEmittedAt = now
        onChange(direction)
    }
}
