import UIKit

public enum TabBarItemSwipeDirection {
    case left
    case right
}

/// Container for top-level tabs. Pure UIKit replacement for the original
/// TabBarController.
///
/// Architecture (native-iOS shape, no shared nav bar):
/// - `CrystalTabBarController` is the window's rootViewController.
/// - Each tab's controller is typically a `CrystalNavigationController`
///   hosting its own navigation stack and its own nav bar. The tab bar
///   controller never owns a nav bar — every screen brings its own, so
///   push/pop inside a tab animates the bar naturally along with the
///   content (no snapshot crossfades, no hiding of child bars).
/// - The floating tab bar sits on top of the currently-visible tab's
///   content. `updateIsTabBarHidden(_:)` slides it out when a pushed
///   screen wants a full-height layout.
open class CrystalTabBarController: ViewController {
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

    private var tabBarHidden: Bool = false

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
                // Double-tap on the active tab — ask the controller to scroll to top.
                (self.currentController as? ViewController)?.scrollToTopWithTabBar?()
                ((self.currentController as? CrystalNavigationController)?.topController)?.scrollToTopWithTabBar?()
            } else {
                self.selectedIndex = index
            }
        }

        tabBarView.tabDoubleTapped = { [weak self] index in
            guard let self, index < self._controllers.count else { return }
            (self._controllers[index] as? ViewController)?.tabBarItemPerformDoubleTapAction()
        }

        tabBarView.itemHasDoubleTapAction = { [weak self] index in
            guard let self, index < self._controllers.count else { return false }
            return (self._controllers[index] as? ViewController)?.tabBarItemHasDoubleTapAction() ?? false
        }

        tabBarView.tabLongPressed = { [weak self] index, sourceView, gesture in
            guard let self, index < self._controllers.count,
                  let controller = self._controllers[index] as? ViewController
            else { return }

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
            (self._controllers[index] as? ViewController)?.tabBarItemSwipeAction(direction: direction)
        }

        tabBarView.disabledPressed = { [weak self] in
            (self?.currentController as? ViewController)?.tabBarDisabledAction()
        }

        view.addSubview(tabBarView)

        if let current = currentController {
            showController(current, animated: false)
        }
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
        let items = controllers.map { controller -> CrystalTabBarItem in
            let tabItem = controller.tabBarItem
            return CrystalTabBarItem(
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
        updateCurrentContainerLayout(layout)

        // TabBarView is at most 103pt TOTAL (safe area included inside).
        let tabBarHeight: CGFloat = TabBarView.defaultHeight // 103, never more
        // Use RAW device safe area (not layout.safeInsets which includes
        // our own additionalSafeAreaInsets — using that causes infinite recursion).
        let rawSafeBottom = view.window?.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom
        let tabBarContentInset = tabBarHidden ? 0.0 : max(0.0, tabBarHeight - rawSafeBottom)

        // Propagate the tab-bar height to embedded children via UIKit's
        // safe area machinery. Anything below us — embedded navigation
        // controllers, plain view controllers, etc. — will see their
        // `view.safeAreaInsets.bottom` include the tab bar, so they can
        // lay content above it without having to know we exist.
        let desiredChildInsets = UIEdgeInsets(top: 0, left: 0, bottom: tabBarContentInset, right: 0)
        if additionalSafeAreaInsets != desiredChildInsets {
            additionalSafeAreaInsets = desiredChildInsets
        }

        let tabBarY: CGFloat = tabBarHidden ? layout.size.height : (layout.size.height - tabBarHeight)
        let tabBarFrame = CGRect(x: 0, y: tabBarY, width: layout.size.width, height: tabBarHeight)
        transition.updateFrame(view: tabBarView, frame: tabBarFrame)
        tabBarView.layoutSubviews()

        if let current = currentController {
            transition.updateFrame(view: current.view, frame: CGRect(origin: .zero, size: layout.size))
            // Our CrystalNavigationController recomputes its own layout
            // from `view.safeAreaInsets` in `viewDidLayoutSubviews`, so
            // setting `self.additionalSafeAreaInsets` above is enough —
            // UIKit will flow the new safe-area into the child and
            // trigger a layout pass there. We still forward an explicit
            // containerLayoutUpdated for non-CrystalNavigation children
            // that rely on our layout object shape.
            let childLayout = ContainerViewLayout(
                size: layout.size,
                metrics: layout.metrics,
                safeInsets: layout.safeInsets,
                additionalInsets: UIEdgeInsets(
                    top: layout.additionalInsets.top,
                    left: layout.additionalInsets.left,
                    bottom: layout.additionalInsets.bottom + tabBarContentInset,
                    right: layout.additionalInsets.right
                ),
                statusBarHeight: layout.statusBarHeight,
                inputHeight: layout.inputHeight,
                inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging,
                inVoiceOver: layout.inVoiceOver
            )
            if let navController = current as? CrystalNavigationController {
                navController.containerLayoutUpdated(childLayout, transition: transition)
            } else if let tgController = current as? ViewController {
                tgController.containerLayoutUpdated(childLayout, transition: transition)
            }
        }

        view.bringSubviewToFront(tabBarView)
    }

    public func activateSearch() {
        (currentController as? ViewController)?.tabBarActivateSearch()
        if let nav = currentController as? CrystalNavigationController {
            (nav.topController)?.tabBarActivateSearch()
        }
    }

    public func deactivateSearch() {
        (currentController as? ViewController)?.tabBarDeactivateSearch()
        if let nav = currentController as? CrystalNavigationController {
            (nav.topController)?.tabBarDeactivateSearch()
        }
    }

    // MARK: - Private

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
}
