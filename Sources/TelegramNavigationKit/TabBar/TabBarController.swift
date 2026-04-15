import UIKit

public enum TabBarItemSwipeDirection {
    case left
    case right
}

/// Tab bar controller with Telegram-style tab bar and glass support.
/// Replaces Telegram's ASDK-based TabBarController.
open class TelegramTabBarController: ViewController {
    // MARK: - Properties

    private let tabBarView: TabBarView
    private var _controllers: [ViewController] = []
    private var _selectedIndex: Int = 0
    /// Lazy per-tab navigation stacks. When a child of a tab calls `push`, we
    /// route it into THIS tab's local stack instead of replacing the tab bar
    /// in the outer NavigationController. Tab bar therefore stays visible
    /// across pushes (UIKit-standard behaviour). Only created on first push;
    /// nil entries mean the tab still uses its bare root controller view.
    private var _tabNavStacks: [NavigationContainer?] = []

    private var currentControllerView: UIView?

    public var controllers: [ViewController] {
        return _controllers
    }

    /// Top-of-stack controller for the active tab — i.e. whatever the user
    /// is actually looking at right now (root controller if nothing was
    /// pushed inside the tab; otherwise the deepest pushed controller).
    public var currentController: ViewController? {
        guard _selectedIndex < _controllers.count else { return nil }
        if _selectedIndex < _tabNavStacks.count, let stack = _tabNavStacks[_selectedIndex] {
            return stack.topController ?? _controllers[_selectedIndex]
        }
        return _controllers[_selectedIndex]
    }

    /// Root controller of the active tab (ignores any push stack on top).
    public var currentTabRootController: ViewController? {
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
            // Tab switch is treated as a STATE SWAP, not a transition — the
            // nav bar should re-skin instantly (no title crossfade, no
            // button slide). Animating it makes the switch feel like a
            // reload. The cross-tab content fade (handled by
            // `transitionToController`) still runs.
            syncNavigationItem(animated: false)
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

    private var tabBarHidden: Bool = false

    // MARK: - Init

    public init(navigationBarPresentationData: NavigationBarPresentationData? = nil, tabBarTheme: TabBarView.Theme = TabBarView.Theme()) {
        self.tabBarTheme = tabBarTheme
        self.tabBarView = TabBarView(theme: tabBarTheme)

        super.init(navigationBarPresentationData: navigationBarPresentationData)
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
                // Double tap = scroll to top
                self._controllers[index].scrollToTopWithTabBar?()
            } else {
                self.selectedIndex = index
            }
        }

        tabBarView.tabDoubleTapped = { [weak self] index in
            guard let self = self, index < self._controllers.count else {
                return
            }
            self._controllers[index].tabBarItemPerformDoubleTapAction()
        }

        tabBarView.itemHasDoubleTapAction = { [weak self] index in
            guard let self = self, index < self._controllers.count else {
                return false
            }
            return self._controllers[index].tabBarItemHasDoubleTapAction()
        }

        tabBarView.tabLongPressed = { [weak self] index, sourceView, gesture in
            guard let self = self else { return }
            guard index < self._controllers.count else { return }

            let controller = self._controllers[index]
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
            guard let self = self, index < self._controllers.count else {
                return
            }
            self._controllers[index].tabBarItemSwipeAction(direction: direction)
        }

        tabBarView.disabledPressed = { [weak self] in
            self?.currentController?.tabBarDisabledAction()
        }

        view.addSubview(tabBarView)

        if let current = currentController {
            syncNavigationItem(animated: false)
            showController(current, animated: false)
        }
    }

    // MARK: - Public API

    public func setControllers(_ controllers: [ViewController], selectedIndex: Int?) {
        let previousController = currentController

        self._controllers = controllers
        self._selectedIndex = selectedIndex ?? min(_selectedIndex, max(0, controllers.count - 1))
        // Reset per-tab nav stacks to match the new tab count.
        self._tabNavStacks = Array(repeating: nil, count: controllers.count)
        controllers.forEach(prepareControllerForTabEmbedding)

        // Build tab items
        let items = controllers.map { controller -> TelegramTabBarItem in
            let tabItem = controller.tabBarItem
            return TelegramTabBarItem(
                title: tabItem?.title ?? "",
                image: tabItem?.image,
                selectedImage: tabItem?.selectedImage,
                badgeValue: tabItem?.badgeValue,
                isEnabled: true
            )
        }
        tabBarView.items = items
        tabBarView.selectedIndex = _selectedIndex

        // Show selected controller
        if let previous = previousController, previous !== currentController {
            detachControllerIfNeeded(previous)
        }

        if let current = currentController, isViewLoaded {
            syncNavigationItem(animated: false)
            showController(current, animated: false)
        } else {
            syncNavigationItem(animated: false)
        }
    }

    /// Push a controller onto the active tab's local navigation stack (NOT
    /// the outer NavigationController). Tab bar stays visible. Lazy-creates
    /// the per-tab `NavigationContainer` on first push.
    ///
    /// Contract:
    /// - Pushed controller becomes a **child of TabBarController** (not the
    ///   stack, which is a UIView). Keeps the parent chain intact so nested
    ///   `push`es from the detail can still find `nearestTelegramTabBarController`.
    /// - Pushed controller's own nav bar is **hidden** — the shared outer nav
    ///   bar reflects its nav item. Without this, the detail's glass back-pill
    ///   bleeds through the translucent outer glass bar.
    /// - Outer nav bar is **re-synced** to the new top so title / previousItem
    ///   / backPressed all point at the detail, not the root.
    public func pushInCurrentTab(_ controller: ViewController, animated: Bool = true) {
        guard _selectedIndex < _controllers.count else { return }
        let stack = ensureTabNavStack(at: _selectedIndex)

        // If the bare root view is still attached directly to our view
        // (hasn't been pushed over yet), move it out — the stack is taking
        // over rendering. Root stays as a CHILD of TabBarController so
        // view-controller lifecycle still flows through us.
        let rootController = _controllers[_selectedIndex]
        if rootController.view.superview === view {
            rootController.view.removeFromSuperview()
        }

        if stack.superview !== view {
            view.insertSubview(stack, belowSubview: tabBarView)
        }
        if let layout = currentlyAppliedLayout {
            stack.frame = view.bounds
            stack.containerLayoutUpdated(makeStackLayout(layout: layout), transition: .immediate)
        }

        // Shared nav bar model: pushed controller MUST NOT render its own bar,
        // or the detail's back-pill shows through the outer glass bar.
        controller.displayNavigationBar = false
        controller.navigationBarView?.isHidden = true

        if controller.parent !== self {
            addChild(controller)
            controller.didMove(toParent: self)
        }

        stack.pushController(controller, animated: animated)
        syncNavigationItem(animated: animated)

        if let navigationBarView { view.bringSubviewToFront(navigationBarView) }
        view.bringSubviewToFront(tabBarView)
    }

    /// Pop the top of the active tab's local stack. Returns nil when the tab
    /// has no stack or only its root — caller falls through to the outer
    /// NavigationController's pop in that case.
    @discardableResult
    public func popInCurrentTab(animated: Bool = true) -> ViewController? {
        guard _selectedIndex < _tabNavStacks.count, let stack = _tabNavStacks[_selectedIndex] else {
            return nil
        }
        let popped = stack.popController(animated: animated)
        // `controllerRemoved` (wired in ensureTabNavStack) handles detach +
        // sync when the pop animation completes. We also resync now so the
        // outer bar's previousItem / title update immediately as the
        // animation starts — otherwise the stale title is visible for the
        // whole animation duration.
        if popped != nil {
            syncNavigationItem(animated: animated)
        }
        return popped
    }

    private func ensureTabNavStack(at index: Int) -> NavigationContainer {
        if index < _tabNavStacks.count, let existing = _tabNavStacks[index] {
            return existing
        }
        let container = NavigationContainer(frame: view.bounds)
        let rootController = _controllers[index]
        container.setControllers([rootController], animated: false)
        container.controllerWillBeRemoved = { [weak self] _ in
            guard let self else { return }
            // Fires at the START of a swipe-back commit animation. The
            // controllers array has already been decremented in the stack,
            // so `currentController` returns the NEW top. If an interactive
            // crossfade is in flight, let it finish (don't re-sync the bar
            // now — sync was already done at `.began` via the two-snapshot
            // path, and the `finishInteractiveItemTransition` call below
            // settles the final alpha state).
            let impl = self.navigationBarView as? NavigationBarImpl
            if impl?.hasInteractiveItemTransitionInFlight == true {
                // Item is still at the OLD state on the live container
                // (snapshots are on top). Apply NEW state permanently now
                // so the live container matches the "to" snapshot alpha=1.
                self.syncNavigationItem(animated: false)
                impl?.finishInteractiveItemTransition(cancelled: false)
            } else {
                // Non-interactive pop (programmatic tap). Just sync with
                // animation to match the tap-pop's slide duration.
                self.syncNavigationItem(animated: true)
            }
        }
        container.interactivePopStarted = { [weak self] _, _ in
            guard let self, let impl = self.navigationBarView as? NavigationBarImpl else { return }
            // Decide the TARGET state — what the bar will look like after
            // the pop completes. The stack's controllers still contains
            // the detail at this point (it was only removed from the
            // controllers array in the commit branch of .ended); so we
            // predict the new top from stack.controllers[count - 2].
            let targetItemAndPrevious: (UINavigationItem?, NavigationPreviousAction?) = {
                guard let stack = self._selectedIndex < self._tabNavStacks.count
                    ? self._tabNavStacks[self._selectedIndex]
                    : nil,
                      stack.controllers.count >= 2
                else {
                    return (nil, nil)
                }
                let newTop = stack.controllers[stack.controllers.count - 2]
                // The bar reflects the outer TabBarController's navigationItem,
                // mirrored from the current controller's item. For the new
                // top we build a synthetic item that matches what sync
                // would produce.
                let synthetic = UINavigationItem()
                let source = newTop.navigationItem
                synthetic.title = source.title ?? newTop.tabBarItem?.title
                synthetic.titleView = source.titleView
                synthetic.leftBarButtonItems = source.leftBarButtonItems ?? source.leftBarButtonItem.map { [$0] }
                synthetic.rightBarButtonItems = source.rightBarButtonItems ?? source.rightBarButtonItem.map { [$0] }
                // If after pop the new top is at the bottom of the stack,
                // there's no further previousItem. Otherwise point at the
                // level-below entry.
                let targetPrev: NavigationPreviousAction?
                if stack.controllers.count >= 3 {
                    targetPrev = .item(stack.controllers[stack.controllers.count - 3].navigationItem)
                } else {
                    targetPrev = self.previousItem
                }
                return (synthetic, targetPrev)
            }()
            impl.beginInteractiveItemTransition(
                targetItem: targetItemAndPrevious.0,
                targetPreviousItem: targetItemAndPrevious.1
            )
        }
        container.interactivePopProgressed = { [weak self] progress in
            guard let impl = self?.navigationBarView as? NavigationBarImpl else { return }
            impl.updateInteractiveItemTransition(progress: progress)
        }
        container.interactivePopCancelled = { [weak self] in
            guard let impl = self?.navigationBarView as? NavigationBarImpl else { return }
            impl.finishInteractiveItemTransition(cancelled: true)
        }
        container.controllerRemoved = { [weak self] removed in
            guard let self else { return }
            // Fires AFTER the pop animation completes. By design we do NOT
            // re-sync the nav bar here:
            //  - button-tap pop path: `popInCurrentTab` synced at call time
            //    and the layout is already animating toward the target.
            //  - swipe-back path: `controllerWillBeRemoved` synced at
            //    commit start.
            // Re-syncing here with `animated: false` would call
            // `containerLayoutUpdated(transition: .immediate)` and kill
            // the in-flight layout animation mid-way, snapping frames to
            // their target — the exact "buttons disappear" glitch the
            // user sees on swipe-back.
            if removed.parent === self {
                removed.willMove(toParent: nil)
                removed.removeFromParent()
            }
        }
        container.requestLayout = { [weak self] transition in
            guard let self, let layout = self.currentlyAppliedLayout else { return }
            self.containerLayoutUpdated(layout, transition: transition)
        }
        if index < _tabNavStacks.count {
            _tabNavStacks[index] = container
        } else {
            _tabNavStacks.append(container)
        }
        return container
    }

    /// Compute the layout to hand down to whichever child view is currently
    /// rendering the active tab (bare root view OR the tab's nav stack).
    /// Insets carve out the space our outer nav bar + tab bar occupy so
    /// embedded content never slides under either.
    private func makeStackLayout(layout: ContainerViewLayout) -> ContainerViewLayout {
        let navTopInset: CGFloat
        if navigationBarView != nil, displayNavigationBar {
            navTopInset = max(0.0, navigationLayout(layout: layout).navigationFrame.maxY - layout.safeInsets.top)
        } else {
            navTopInset = 0.0
        }

        let tabBarTotalHeight = TabBarView.defaultHeight + layout.safeInsets.bottom
        let tabBarContentInset = tabBarHidden ? 0.0 : max(0.0, tabBarTotalHeight - layout.safeInsets.bottom)

        return ContainerViewLayout(
            size: CGSize(width: layout.size.width, height: layout.size.height),
            metrics: layout.metrics,
            safeInsets: layout.safeInsets,
            additionalInsets: UIEdgeInsets(
                top: layout.additionalInsets.top + navTopInset,
                left: layout.additionalInsets.left,
                bottom: layout.additionalInsets.bottom + tabBarContentInset,
                right: layout.additionalInsets.right
            ),
            statusBarHeight: layout.statusBarHeight,
            inputHeight: layout.inputHeight,
            inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging,
            inVoiceOver: layout.inVoiceOver
        )
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

    public func updateCurrentNavigationItem(animated: Bool) {
        syncNavigationItem(animated: animated)
    }

    public func frameForControllerTab(controller: ViewController) -> CGRect? {
        guard let index = _controllers.firstIndex(where: { $0 === controller }) else { return nil }
        return tabBarView.frameForTab(at: index)
    }

    public func isPointInsideContentArea(point: CGPoint) -> Bool {
        let tabBarFrame = tabBarView.frame
        return point.y < tabBarFrame.minY
    }

    // MARK: - Layout

    override open func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        // Reset propagation of additionalSafeAreaInsets to child controllers:
        // TabBarController positions its own subviews (nav bar, tab bar) with
        // explicit frames, not safe-area driven. If we left the super's
        // additionalSafeAreaInsets in place, children embedded below would
        // inherit those insets via UIKit's safe-area propagation AND then add
        // their own additional.top on top → content ends up pushed ~2x too
        // far down. Child controllers receive the correct inset via
        // `controllerLayout.additionalInsets`.
        self.additionalSafeAreaInsets = .zero

        let tabBarHeight = TabBarView.defaultHeight + layout.safeInsets.bottom
        let tabBarY: CGFloat = tabBarHidden ? layout.size.height : (layout.size.height - tabBarHeight)
        let tabBarFrame = CGRect(x: 0, y: tabBarY, width: layout.size.width, height: tabBarHeight)
        transition.updateFrame(view: tabBarView, frame: tabBarFrame)
        tabBarView.layoutSubviews()

        let stackLayout = makeStackLayout(layout: layout)
        let activeStack = (_selectedIndex < _tabNavStacks.count) ? _tabNavStacks[_selectedIndex] : nil

        // When the active tab has a nav stack on screen, route layout into it
        // (it in turn lays out its own top controller). Otherwise the tab is
        // rendering its bare root view directly — lay it out itself.
        if let activeStack, activeStack.superview === view {
            transition.updateFrame(view: activeStack, frame: CGRect(origin: .zero, size: layout.size))
            activeStack.containerLayoutUpdated(stackLayout, transition: transition)
        } else if let current = currentController {
            transition.updateFrame(view: current.view, frame: CGRect(origin: .zero, size: layout.size))
            current.containerLayoutUpdated(stackLayout, transition: transition)
        }

        if let navigationBarView {
            view.bringSubviewToFront(navigationBarView)
        }
        view.bringSubviewToFront(tabBarView)
    }

    public func activateSearch() {
        currentController?.tabBarActivateSearch()
    }

    public func deactivateSearch() {
        currentController?.tabBarDeactivateSearch()
    }

    // MARK: - Private

    private func prepareControllerForTabEmbedding(_ controller: ViewController) {
        guard navigationBarView != nil else {
            return
        }
        controller.displayNavigationBar = false
    }

    private func syncNavigationItem(animated: Bool) {
        guard let currentController else {
            return
        }

        let activeStack = (_selectedIndex < _tabNavStacks.count) ? _tabNavStacks[_selectedIndex] : nil
        let isNested = (activeStack?.controllers.count ?? 0) > 1

        let sourceItem = currentController.navigationItem
        navigationItem.title = sourceItem.title ?? currentController.tabBarItem?.title
        navigationItem.titleView = sourceItem.titleView
        navigationItem.leftBarButtonItems = sourceItem.leftBarButtonItems ?? sourceItem.leftBarButtonItem.map { [$0] }
        navigationItem.rightBarButtonItems = sourceItem.rightBarButtonItems ?? sourceItem.rightBarButtonItem.map { [$0] }
        statusBarStyle = currentController.statusBarStyle

        // Compute the previousItem we want to end up with.
        let targetPreviousItem: NavigationPreviousAction?
        if isNested, let stack = activeStack, stack.controllers.count >= 2 {
            let previous = stack.controllers[stack.controllers.count - 2]
            targetPreviousItem = .item(previous.navigationItem)
        } else {
            targetPreviousItem = previousItem
        }

        // Install (or refresh) the dynamic back handler. Routes at tap time
        // based on current stack state, so it survives push/pop cycles.
        navigationBarView?.backPressed = { [weak self] in
            guard let self else { return }
            let activeStack = self._selectedIndex < self._tabNavStacks.count
                ? self._tabNavStacks[self._selectedIndex]
                : nil
            if let activeStack, activeStack.controllers.count > 1 {
                self.popInCurrentTab(animated: true)
                return
            }
            var current: UIViewController? = self.parent
            while let candidate = current {
                if let navigationController = candidate as? TelegramNavigationController {
                    navigationController.popViewController(animated: true)
                    return
                }
                current = candidate.parent
            }
        }

        // Animated item swap uses the iOS 26-style glass crossfade — a
        // snapshot of the current buttons is overlaid while the new
        // buttons emerge with a soft scale. Skip this when an
        // interactive gesture transition is already in flight (that path
        // has its own two-snapshot progress-driven crossfade).
        let itemChanges = { [weak self] in
            guard let self else { return }
            self.navigationBarView?.item = self.navigationItem
            self.navigationBarView?.previousItem = targetPreviousItem
        }
        if animated,
           let impl = navigationBarView as? NavigationBarImpl,
           !impl.hasInteractiveItemTransitionInFlight
        {
            impl.performGlassItemChange(changes: itemChanges)
        } else {
            itemChanges()
        }

        // Forward child's content view (filter chips / segmented controls / etc.)
        // to the tab bar controller's own nav bar so it visually attaches to the
        // single shared nav bar surface.
        navigationBarView?.setContentView(currentController.navigationBarContent, animated: animated)

        // Observe further changes so the content view stays in sync while the
        // controller is embedded.
        currentController.navigationBarContentDidChange = { [weak self, weak currentController] in
            guard let self, let currentController, currentController === self.currentController else {
                return
            }
            self.navigationBarView?.setContentView(currentController.navigationBarContent, animated: true)
            if let layout = self.currentlyAppliedLayout {
                self.containerLayoutUpdated(layout, transition: .animated(duration: 0.2, curve: .easeInOut))
            }
        }

        if let layout = currentlyAppliedLayout {
            // Always re-lay out after an item swap. For animated transitions
            // (push / pop) we match the stack's push/pop spring so nav-bar
            // settle and content-slide complete together. For non-animated
            // transitions (tab switch) we snap immediately — without this
            // the bar would briefly show stale layout (missing buttons,
            // wrong frames) until the tab-switch fade completion later
            // triggered its own layout pass.
            containerLayoutUpdated(
                layout,
                transition: animated
                    ? .animated(duration: 0.35, curve: .easeInOut)
                    : .immediate
            )
        }
    }

    private func transitionToController(at index: Int, from previousIndex: Int, animated: Bool) {
        guard index < _controllers.count else { return }
        let newController = _controllers[index]

        // Lifecycle hardening for rapid tab switches: cancel any in-flight
        // alpha animation on the previously-displayed controllers and force
        // a clean state so completions from old transitions can't detach
        // the wrong view or leave stale alpha values.
        for (controllerIndex, controller) in _controllers.enumerated() where controller.isViewLoaded {
            controller.view.layer.removeAllAnimations()
            if controllerIndex == index {
                continue
            }
            // Detach whichever view this tab is CURRENTLY rendering.
            // If the tab has a stack, its root is nested INSIDE the stack;
            // we only remove the stack wrapper — root stays parented to
            // TabBarController and its view stays inside the stack so we
            // can restore state when the tab comes back on screen.
            if controllerIndex < _tabNavStacks.count, let otherStack = _tabNavStacks[controllerIndex] {
                otherStack.layer.removeAllAnimations()
                otherStack.removeFromSuperview()
            } else {
                detachControllerIfNeeded(controller)
            }
            controller.view.alpha = 1.0
        }

        let newStack: NavigationContainer? = (index < _tabNavStacks.count) ? _tabNavStacks[index] : nil
        // If the tab has no stack (never been pushed into), the root renders
        // directly and needs its own nav bar hidden so the outer bar is the
        // only one on screen. With a stack, the stack's top controller was
        // configured at push time.
        if newStack == nil {
            prepareControllerForTabEmbedding(newController)
        }

        let viewToShow: UIView = newStack ?? newController.view

        if animated {
            viewToShow.frame = view.bounds
            // iOS 18-style tab-switch: a very small scale (0.985 → 1.0) +
            // quick alpha fade. Barely noticeable but gives the content a
            // "settle" feel rather than a hard cut. No nav-bar animation
            // involved — the bar was already re-skinned synchronously in
            // the selectedIndex setter.
            viewToShow.alpha = 0.0
            viewToShow.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)

            let didAttach = attachControllerIfNeeded(newController)
            view.insertSubview(viewToShow, belowSubview: tabBarView)
            if didAttach {
                newController.didMove(toParent: self)
            }
            if let navigationBarView {
                view.bringSubviewToFront(navigationBarView)
            }
            view.bringSubviewToFront(tabBarView)

            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
                viewToShow.alpha = 1.0
                viewToShow.transform = .identity
            }, completion: { [weak self] finished in
                guard let self else { return }
                // Only run finalization if THIS animation actually ran to
                // completion (a fast subsequent switch will have removed the
                // animation from the layer mid-flight, in which case
                // `finished == false` and we just bail — the new transition
                // owns cleanup now).
                guard finished, self._selectedIndex == index else { return }
                viewToShow.transform = .identity
                if let layout = self.currentlyAppliedLayout {
                    self.containerLayoutUpdated(layout, transition: .immediate)
                }
            })
        } else {
            showController(newController, animated: false)
        }
    }

    private func showController(_ controller: ViewController, animated: Bool) {
        let index = _selectedIndex
        let stack: NavigationContainer? = (index < _tabNavStacks.count) ? _tabNavStacks[index] : nil

        if stack == nil {
            prepareControllerForTabEmbedding(controller)
        }

        let viewToShow: UIView = stack ?? controller.view

        let didAttach = attachControllerIfNeeded(controller)
        viewToShow.frame = view.bounds
        view.insertSubview(viewToShow, belowSubview: tabBarView)
        if didAttach {
            controller.didMove(toParent: self)
        }
        if let navigationBarView {
            view.bringSubviewToFront(navigationBarView)
        }
        view.bringSubviewToFront(tabBarView)
        syncNavigationItem(animated: false)

        if let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    @discardableResult
    private func attachControllerIfNeeded(_ controller: ViewController) -> Bool {
        guard controller.parent !== self else {
            return false
        }
        addChild(controller)
        return true
    }

    private func detachControllerIfNeeded(_ controller: ViewController) {
        controller.view.removeFromSuperview()

        guard controller.parent === self else {
            return
        }

        controller.willMove(toParent: nil)
        controller.removeFromParent()
    }
}
