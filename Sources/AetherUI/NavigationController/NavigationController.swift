import UIKit

// MARK: - Types

public enum NavigationStatusBarStyle {
    case black
    case white
}

public final class NavigationControllerTheme {
    public let statusBar: NavigationStatusBarStyle
    public let navigationBar: NavigationBarTheme
    public let emptyAreaColor: UIColor

    public init(statusBar: NavigationStatusBarStyle, navigationBar: NavigationBarTheme, emptyAreaColor: UIColor) {
        self.statusBar = statusBar
        self.navigationBar = navigationBar
        self.emptyAreaColor = emptyAreaColor
    }

    public static func liquidGlass(
        overallDarkAppearance: Bool = false,
        emptyAreaColor: UIColor = .systemBackground,
        edgeEffectAlpha: CGFloat = 0.75,
        edgeEffectBlurRadiusAtEdge: CGFloat = 2.0,
        edgeEffectBlurRadiusAtFade: CGFloat = 0.0,
        edgeEffectStyle: SystemGlassEffectStyle = .regular
    ) -> NavigationControllerTheme {
        return NavigationControllerTheme(
            statusBar: overallDarkAppearance ? .white : .black,
            navigationBar: .liquidGlass(
                overallDarkAppearance: overallDarkAppearance,
                buttonColor: overallDarkAppearance ? .white : .label,
                primaryTextColor: overallDarkAppearance ? .white : .label,
                edgeEffectAlpha: edgeEffectAlpha,
                edgeEffectBlurRadiusAtEdge: edgeEffectBlurRadiusAtEdge,
                edgeEffectBlurRadiusAtFade: edgeEffectBlurRadiusAtFade,
                edgeEffectStyle: edgeEffectStyle
            ),
            emptyAreaColor: emptyAreaColor
        )
    }
}

public struct NavigationAnimationOptions: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let removeOnMasterDetails = NavigationAnimationOptions(rawValue: 1 << 0)
}

public enum NavigationControllerMode {
    case single
    case automaticMasterDetail
}

private enum RootContainer {
    case flat(NavigationContainer)
    case split(NavigationSplitContainer)
}

/// Pure UIKit navigation controller with glass-style transitions and glass support.
/// Replaces the NavigationController.
open class AetherNavigationController: UIViewController, UIGestureRecognizerDelegate {
    // MARK: - Properties

    private let mode: NavigationControllerMode
    private var theme: NavigationControllerTheme
    private var defaultNavigationBarPresentationData: NavigationBarPresentationData

    private var rootContainer: RootContainer?
    private var overlayContainers: [NavigationOverlayContainer] = []
    private var sharedNavigationBar: NavigationBarImpl?
    private weak var sharedNavigationBarController: AetherViewController?
    private var isUpdatingSharedNavigationBar: Bool = false
    private var interactiveNavigationBarTransition: NavigationBarInteractiveTransition?
    private struct PendingViewControllersUpdate {
        let controllers: [AetherViewController]
        let animated: Bool
    }
    private var pendingViewControllersUpdate: PendingViewControllersUpdate?
    private var isApplyingPendingViewControllersUpdate: Bool = false

    var bottomBarVisibilityTransitionBegan: ((NavigationTransitionDirection, AetherViewController, AetherViewController, Bool) -> Void)?
    var bottomBarVisibilityTransitionProgress: ((CGFloat, ContainedViewLayoutTransition) -> Void)?
    var bottomBarVisibilityTransitionResolutionBegan: ((Bool, ContainedViewLayoutTransition) -> Void)?
    var bottomBarVisibilityTransitionEnded: ((Bool) -> Void)?

    private final class NavigationBarInteractiveTransition {
        let direction: NavigationTransitionDirection
        let sourceController: AetherViewController
        let targetController: AetherViewController
        let sourceStack: [AetherViewController]
        let targetStack: [AetherViewController]
        let sourceBar: NavigationBarImpl
        let targetBar: NavigationBarImpl
        let isInteractive: Bool
        var sourceButtonBar: NavigationBarImpl?
        var targetButtonBar: NavigationBarImpl?
        var sourceButtonChromeLayout: NavigationBarImpl.ButtonChromeLayout?
        var targetButtonChromeLayout: NavigationBarImpl.ButtonChromeLayout?
        var didPrepareHeldButtonChrome: Bool = false
        var lastHeldButtonHorizontalScale: CGFloat?
        var sourceBaseFrame: CGRect = .zero
        var targetBaseFrame: CGRect = .zero
        var progress: CGFloat = 0.0
        var didResolveButtonTransition: Bool = false
        var resolvedCompleted: Bool?

        init(
            direction: NavigationTransitionDirection,
            sourceController: AetherViewController,
            targetController: AetherViewController,
            sourceStack: [AetherViewController],
            targetStack: [AetherViewController],
            sourceBar: NavigationBarImpl,
            targetBar: NavigationBarImpl,
            isInteractive: Bool
        ) {
            self.direction = direction
            self.sourceController = sourceController
            self.targetController = targetController
            self.sourceStack = sourceStack
            self.targetStack = targetStack
            self.sourceBar = sourceBar
            self.targetBar = targetBar
            self.isInteractive = isInteractive
        }
    }

    public var minimizedContainer: MinimizedContainerProtocol? {
        didSet {
            if oldValue !== minimizedContainer {
                oldValue?.navigationController = nil
                oldValue?.removeFromSuperview()
            }

            minimizedContainer?.navigationController = self
            minimizedContainer?.willMaximize = { [weak self] _ in
                self?.requestLayout(transition: .animated(duration: 0.4, curve: .spring))
            }
            minimizedContainer?.willDismiss = { [weak self] _ in
                guard let self else { return }
                self.minimizedContainer = nil
                self.requestLayout(transition: .animated(duration: 0.4, curve: .spring))
            }
            minimizedContainer?.didDismiss = { container in
                container.removeFromSuperview()
            }
            minimizedContainer?.statusBarStyleUpdated = { [weak self] in
                self?.setNeedsStatusBarAppearanceUpdate()
            }

            if let layout = validLayout {
                updateMinimizedContainer(layout: layout, transition: .immediate)
            }
        }
    }

    private var _viewControllers: [AetherViewController] = []
    public var viewControllerStack: [AetherViewController] {
        _viewControllers
    }

    public var viewControllers: [UIViewController] {
        get {
            return _viewControllers
        }
        set {
            setViewControllers(newValue.compactMap { $0 as? AetherViewController }, animated: false)
        }
    }

    public var topViewController: UIViewController? {
        return topController
    }

    public var visibleViewController: UIViewController? {
        return topController
    }

    public var navigationBar: NavigationBarView {
        return ensureSharedNavigationBar()
    }

    public var topController: AetherViewController? {
        if let topOverlayController = overlayContainers.last?.controller {
            return topOverlayController
        }

        switch rootContainer {
        case let .flat(container):
            return container.topController
        case let .split(container):
            return container.detailContainer.topController ?? container.masterContainer.topController
        case nil:
            return _viewControllers.last
        }
    }

    private var validLayout: ContainerViewLayout?

    // MARK: - Status Bar

    public var statusBarHost: AnyObject?
    private var currentStatusBarStyle: NavigationStatusBarStyle

    override open var childForStatusBarStyle: UIViewController? {
        topController
    }

    override open var childForStatusBarHidden: UIViewController? {
        topController
    }

    override open var preferredStatusBarStyle: UIStatusBarStyle {
        switch currentStatusBarStyle {
        case .black:
            return .darkContent
        case .white:
            return .lightContent
        }
    }

    override open var prefersStatusBarHidden: Bool {
        topController?.prefersStatusBarHidden ?? false
    }

    // MARK: - Init

    public init(mode: NavigationControllerMode, theme: NavigationControllerTheme) {
        self.mode = mode
        self.theme = theme
        self.currentStatusBarStyle = theme.statusBar
        self.defaultNavigationBarPresentationData = NavigationBarPresentationData(theme: theme.navigationBar)
        super.init(nibName: nil, bundle: nil)
    }

    public convenience init(rootViewController: AetherViewController, mode: NavigationControllerMode = .single, theme: NavigationControllerTheme) {
        self.init(mode: mode, theme: theme)
        setViewControllers([rootViewController], animated: false)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.emptyAreaColor
        _ = ensureSharedNavigationBar()
        wireControllers(_viewControllers)
        requestLayout(transition: .immediate)
    }

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContainerLayout(transition: .immediate)
    }

    override open func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateContainerLayout(transition: .immediate)
    }

    // MARK: - Layout

    public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        validLayout = layout
        updateVisibleContainers(layout: layout, transition: transition)
    }

    private func updateContainerLayout(transition: ContainedViewLayoutTransition) {
        // When hosted inside a AetherModalController the "status bar"
        // region is reused for the grabber strip: a navbar built with
        // statusBarHeight = grabberContainerHeight has its chrome laid
        // out below the grabber, and its own edge-effect frost covers
        // the grabber area naturally (no extra work). Outside a modal,
        // use the real window status bar height.
        let statusBarHeight: CGFloat? = isHostedInModal
            ? AetherModalController.grabberContainerHeight
            : view.window?.windowScene?.statusBarManager?.statusBarFrame.height

        let layout = ContainerViewLayout(
            size: view.bounds.size,
            metrics: LayoutMetrics(
                widthClass: view.traitCollection.horizontalSizeClass == .regular ? .regular : .compact,
                isTablet: UIDevice.current.userInterfaceIdiom == .pad
            ),
            safeInsets: view.safeAreaInsets,
            additionalInsets: .zero,
            statusBarHeight: statusBarHeight,
            inputHeight: validLayout?.inputHeight,
            inputHeightIsInteractivellyChanging: validLayout?.inputHeightIsInteractivellyChanging ?? false,
            inVoiceOver: UIAccessibility.isVoiceOverRunning
        )
        containerLayoutUpdated(layout, transition: transition)
    }

    private var isHostedInModal: Bool {
        var current: UIViewController? = self
        while let vc = current {
            if vc is AetherModalController { return true }
            current = vc.parent
        }
        return false
    }

    public func requestLayout(transition: ContainedViewLayoutTransition) {
        updateContainerLayout(transition: transition)
    }

    // MARK: - Navigation Stack

    public func setViewControllers(_ viewControllers: [AetherViewController], animated: Bool = true) {
        // Match Telegram-iOS: silently drop duplicates rather than letting the
        // same controller appear twice in the stack (that guarantees broken
        // back-stack state — a single controller can't be its own previous).
        var deduped: [AetherViewController] = []
        deduped.reserveCapacity(viewControllers.count)
        for controller in viewControllers where !deduped.contains(where: { $0 === controller }) {
            deduped.append(controller)
        }

        _viewControllers = deduped
        wireControllers(deduped)

        if interactiveNavigationBarTransition != nil && !isApplyingPendingViewControllersUpdate {
            let shouldKeepAnimatedPendingUpdate: Bool
            if let pending = pendingViewControllersUpdate,
               pending.animated,
               viewControllerArraysAreEqual(pending.controllers, deduped) {
                shouldKeepAnimatedPendingUpdate = true
            } else {
                shouldKeepAnimatedPendingUpdate = false
            }
            pendingViewControllersUpdate = PendingViewControllersUpdate(
                controllers: deduped,
                animated: animated || shouldKeepAnimatedPendingUpdate
            )
            return
        }

        if let layout = currentLayoutForComputation() {
            updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: animated))
        }
    }

    public func setViewControllers(_ viewControllers: [UIViewController], animated: Bool, completion: @escaping () -> Void = {}) {
        setViewControllers(viewControllers.compactMap { $0 as? AetherViewController }, animated: animated)
        completion()
    }

    public func pushViewController(_ controller: AetherViewController, animated: Bool = true) {
        var controllers = _viewControllers
        controllers.append(controller)
        setViewControllers(controllers, animated: animated)
    }

    @discardableResult
    public func popViewController(animated: Bool = true) -> AetherViewController? {
        guard _viewControllers.count > 1 else {
            return nil
        }

        var controllers = _viewControllers
        let removedController = controllers.removeLast()
        setViewControllers(controllers, animated: animated)
        return removedController
    }

    public func popToRoot(animated: Bool = true) {
        guard let firstController = _viewControllers.first else {
            return
        }
        setViewControllers([firstController], animated: animated)
    }

    @discardableResult
    public func popToViewController(_ viewController: UIViewController, animated: Bool = true) -> [UIViewController]? {
        guard let target = viewController as? AetherViewController,
              let index = _viewControllers.firstIndex(where: { $0 === target })
        else {
            return nil
        }
        guard index < _viewControllers.count - 1 else {
            return []
        }
        let removed = Array(_viewControllers[(index + 1)..<_viewControllers.count])
        setViewControllers(Array(_viewControllers[...index]), animated: animated)
        return removed
    }

    public func replaceTopController(_ controller: AetherViewController, animated: Bool = true) {
        guard !_viewControllers.isEmpty else {
            pushViewController(controller, animated: animated)
            return
        }

        var controllers = _viewControllers
        controllers[controllers.count - 1] = controller
        setViewControllers(controllers, animated: animated)
    }

    public func replaceController(_ controller: AetherViewController, with replacement: AetherViewController, animated: Bool = true) {
        guard let index = _viewControllers.firstIndex(where: { $0 === controller }) else {
            return
        }
        var controllers = _viewControllers
        controllers[index] = replacement
        setViewControllers(controllers, animated: animated)
    }

    // MARK: - Overlay Presentation

    public var overlayControllers: [AetherViewController] {
        return overlayContainers.filter { !$0.isRemoved }.map(\.controller)
    }

    public var topOverlayController: AetherViewController? {
        return overlayContainers.last(where: { !$0.isRemoved })?.controller
    }

    public var globalOverlayControllers: [AetherViewController] {
        guard isViewLoaded, let window = view.window as? AetherWindow else {
            return []
        }
        return window.topLevelOverlayControllers.compactMap { $0 as? AetherViewController }
    }

    public func presentOverlay(controller: AetherViewController, inGlobal: Bool = false, blockInteraction: Bool = false, animated: Bool = true, completion: (() -> Void)? = nil) {
        if inGlobal, isViewLoaded, let window = view.window as? AetherWindow {
            window.presentInGlobalOverlay(controller, animated: animated, completion: completion)
            return
        }
        presentOverlay(controller, blocksInteractionUntilReady: blockInteraction, animated: animated, completion: completion)
    }

    public func presentOverlay(_ controller: AetherViewController, blocksInteractionUntilReady: Bool = false, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard !overlayContainers.contains(where: { $0.controller === controller && !$0.isRemoved }) else {
            completion?()
            return
        }

        let container = NavigationOverlayContainer(controller: controller, blocksInteractionUntilReady: blocksInteractionUntilReady)
        container.isReadyUpdated = { [weak self] in
            self?.requestLayout(transition: .immediate)
        }
        overlayContainers.append(container)

        if controller.parent !== self {
            addChild(controller)
            controller.didMove(toParent: self)
        }

        if let layout = currentLayoutForComputation() {
            updateOverlayContainers(layout: overlayLayout(from: layout), transition: transitionForUpdate(animated: animated), appearingContainer: container, completion: completion)
            updateStatusBarAppearance()
        } else {
            completion?()
        }
    }

    public func dismissOverlay(_ controller: AetherViewController? = nil, animated: Bool = true, completion: (() -> Void)? = nil) {
        let targetIndex: Int?
        if let controller {
            targetIndex = overlayContainers.lastIndex(where: { $0.controller === controller && !$0.isRemoved })
        } else {
            targetIndex = overlayContainers.lastIndex(where: { !$0.isRemoved })
        }

        guard let index = targetIndex else {
            completion?()
            return
        }

        let container = overlayContainers.remove(at: index)
        container.isRemoved = true
        container.controller.willMove(toParent: nil)

        let finish = { [weak self, weak container] in
            guard let self, let container else {
                completion?()
                return
            }
            container.removeFromSuperview()
            container.controller.removeFromParent()
            self.cleanupRemovedChildren()
            self.updateStatusBarAppearance()
            completion?()
        }

        if container.superview != nil {
            container.transitionOut(animated: animated, completion: finish)
        } else {
            finish()
        }
    }

    // MARK: - Minimized Controllers

    public func minimizeViewController(
        _ viewController: MinimizableController,
        topEdgeOffset: CGFloat? = nil,
        beforeMaximize: @escaping (AetherNavigationController, @escaping () -> Void) -> Void,
        setupContainer: (MinimizedContainerProtocol?) -> MinimizedContainerProtocol?,
        animated: Bool = true
    ) {
        let container = setupContainer(minimizedContainer)
        if minimizedContainer !== container {
            minimizedContainer = container
        }

        let transition = transitionForUpdate(animated: animated)
        minimizedContainer?.addController(viewController, topEdgeOffset: topEdgeOffset, beforeMaximize: beforeMaximize, transition: transition)
        if let layout = validLayout {
            updateMinimizedContainer(layout: layout, transition: transition)
        }
    }

    public func maximizeViewController(_ viewController: MinimizableController, animated: Bool = true, completion: @escaping (Bool) -> Void) {
        minimizedContainer?.maximizeController(viewController, animated: animated, completion: completion)
    }

    public func dismissMinimizedControllers(completion: @escaping () -> Void = {}) {
        guard let minimizedContainer else {
            completion()
            return
        }

        self.minimizedContainer = nil
        minimizedContainer.dismissAll {
            minimizedContainer.removeFromSuperview()
            completion()
        }
    }

    // MARK: - Theme

    public func updateTheme(_ theme: NavigationControllerTheme) {
        self.theme = theme
        self.currentStatusBarStyle = theme.statusBar
        self.defaultNavigationBarPresentationData = NavigationBarPresentationData(theme: theme.navigationBar)
        view.backgroundColor = theme.emptyAreaColor
        sharedNavigationBar?.updatePresentationData(defaultNavigationBarPresentationData, transition: .immediate)

        if case let .split(container)? = rootContainer {
            container.updateTheme(theme: theme)
        }

        if let layout = validLayout {
            updateVisibleContainers(layout: layout, transition: .immediate)
        } else {
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    // MARK: - Private

    private func navigationBarButtonMorphTransition() -> ContainedViewLayoutTransition {
        return .animated(duration: 0.44, curve: .custom(0.16, 1.0, 0.30, 1.0))
    }

    private func navigationBarButtonEffectTransition(from transition: ContainedViewLayoutTransition, appearing: Bool) -> ContainedViewLayoutTransition {
        guard transition.isAnimated else {
            return .immediate
        }
        let duration = max(0.38, transition.duration * 0.78)
        let curve: ContainedViewLayoutTransitionCurve = appearing
            ? .custom(0.16, 1.0, 0.30, 1.0)
            : .custom(0.70, 0.0, 0.84, 0.0)
        return .animated(duration: duration, curve: curve)
    }

    private func buttonPulseAmplitude(appearing: Bool) -> CGFloat {
        return appearing ? 0.115 : -0.115
    }

    private func viewControllerArraysAreEqual(_ lhs: [AetherViewController], _ rhs: [AetherViewController]) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }
        for (left, right) in zip(lhs, rhs) where left !== right {
            return false
        }
        return true
    }

    private func applyPendingViewControllersUpdateIfPossible() {
        guard interactiveNavigationBarTransition == nil, let pending = pendingViewControllersUpdate else {
            return
        }

        pendingViewControllersUpdate = nil
        isApplyingPendingViewControllersUpdate = true
        defer { isApplyingPendingViewControllersUpdate = false }

        _viewControllers = pending.controllers
        wireControllers(pending.controllers)
        if let layout = currentLayoutForComputation() {
            updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: pending.animated))
        }
    }

    private func updateVisibleContainers(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let navigationLayout = makeNavigationLayout(mode: mode, layout: layout, controllers: _viewControllers)
        let rootTopController = activeRootStack(for: navigationLayout.root).last
        let rootTransitionShouldDriveNavigationBar = transition.isAnimated
            && rootTopController != nil
            && sharedNavigationBarController != nil
            && sharedNavigationBarController !== rootTopController

        if rootTransitionShouldDriveNavigationBar {
            let previousNavigationBarTransition = interactiveNavigationBarTransition
            updateRootContainer(for: navigationLayout.root, layout: layout, transition: transition)
            if interactiveNavigationBarTransition == nil || interactiveNavigationBarTransition === previousNavigationBarTransition {
                updateSharedNavigationBar(for: navigationLayout.root, layout: layout, transition: transition)
            }
        } else {
            updateSharedNavigationBar(for: navigationLayout.root, layout: layout, transition: transition)
            updateRootContainer(for: navigationLayout.root, layout: layout, transition: transition)
        }
        updateMinimizedContainer(layout: layout, transition: transition)
        updateOverlayContainers(layout: overlayLayout(from: layout), transition: transition)
        cleanupRemovedChildren()
        updateStatusBarAppearance()
    }

    private func updateRootContainer(for rootLayout: RootNavigationLayout, layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        switch rootLayout {
        case let .flat(controllers):
            let container = ensureFlatRootContainer()
            container.frame = CGRect(origin: .zero, size: layout.size)
            container.setControllers(controllers, animated: transition.isAnimated)
            container.containerLayoutUpdated(layout, transition: transition)
        case let .split(masterControllers, detailControllers):
            let container = ensureSplitRootContainer()
            container.frame = CGRect(origin: .zero, size: layout.size)
            container.update(layout: layout, masterControllers: masterControllers, detailControllers: detailControllers, transition: transition)
        }
    }

    private func updateOverlayContainers(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition, appearingContainer: NavigationOverlayContainer? = nil, completion: (() -> Void)? = nil) {
        for container in overlayContainers where !container.isRemoved {
            let wasNotAdded = container.superview == nil
            if wasNotAdded {
                view.addSubview(container)
            }

            container.update(layout: layout, transition: transition)

            if wasNotAdded {
                container.transitionIn(animated: transition.isAnimated && container === appearingContainer, completion: container === appearingContainer ? completion : nil)
            } else if container === appearingContainer {
                completion?()
            }

            // bringSubviewToFront pays a z-reorder + implicit layout-invalidation
            // cost even when the view is already on top. Skip when no-op.
            if view.subviews.last !== container {
                view.bringSubviewToFront(container)
            }
        }

        if appearingContainer == nil {
            completion?()
        }
    }

    private func updateMinimizedContainer(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        guard let minimizedContainer else {
            return
        }

        if minimizedContainer.superview !== view {
            view.addSubview(minimizedContainer)
        }
        transition.updateFrame(view: minimizedContainer, frame: CGRect(origin: .zero, size: layout.size))
        minimizedContainer.updateLayout(layout, transition: transition)
        if view.subviews.last !== minimizedContainer {
            view.bringSubviewToFront(minimizedContainer)
        }
    }

    private func wireControllers(_ viewControllers: [AetherViewController]) {
        let sharedBar = self.sharedNavigationBar

        for controller in viewControllers {
            controller.navigationBarIsExternallyHosted = true

            if let bar = controller.navigationBarView, bar !== sharedBar {
                bar.removeFromSuperview()
                controller.navigationBarView = nil
            } else if controller.navigationBarView === sharedBar, controller !== sharedNavigationBarController {
                controller.navigationBarView = nil
            }

            controller.topBarAccessoryDidChange = { [weak self, weak controller] in
                guard let self, let controller else { return }
                guard !self.isUpdatingSharedNavigationBar else { return }
                guard self.sharedNavigationBarController === controller else { return }
                self.requestLayout(transition: .animated(duration: 0.3, curve: .spring))
            }

            if controller.parent !== self {
                addChild(controller)
                controller.didMove(toParent: self)
            }
        }
    }

    private func ensureSharedNavigationBar() -> NavigationBarImpl {
        if let sharedNavigationBar {
            return sharedNavigationBar
        }

        let bar = NavigationBarImpl(presentationData: defaultNavigationBarPresentationData)
        bar.autoresizingMask = [.flexibleWidth]
        bar.backPressed = { [weak self] in
            self?.popViewController(animated: true)
        }
        bar.requestContainerLayout = { [weak self] transition in
            self?.requestLayout(transition: transition)
        }
        bar.passthroughTouches = true
        sharedNavigationBar = bar

        if isViewLoaded, bar.superview !== view {
            view.addSubview(bar)
        }

        return bar
    }

    private func navigationBarPresentationData(for controller: AetherViewController) -> NavigationBarPresentationData {
        controller.explicitNavigationBarPresentationData ?? defaultNavigationBarPresentationData
    }

    private func activeRootStack(for rootLayout: RootNavigationLayout) -> [AetherViewController] {
        switch rootLayout {
        case let .flat(controllers):
            return controllers
        case let .split(masterControllers, detailControllers):
            return detailControllers.isEmpty ? masterControllers : detailControllers
        }
    }

    private func sharedNavigationLayout(for controller: AetherViewController, bar: NavigationBarView, layout: ContainerViewLayout) -> AetherViewController.NavigationLayout {
        let topOffset = max(layout.statusBarHeight ?? 0.0, layout.safeInsets.top)
        let defaultNavigationBarHeight: CGFloat = 60.0
        let navBarContentHeight = bar.contentHeight(defaultHeight: defaultNavigationBarHeight)
        let navigationBarHeight = topOffset + navBarContentHeight + controller.additionalNavigationBarHeight

        var frame = CGRect(origin: .zero, size: CGSize(width: layout.size.width, height: navigationBarHeight))
        if !controller.displayNavigationBar {
            frame.origin.y = -navigationBarHeight
        }

        return AetherViewController.NavigationLayout(navigationFrame: frame, defaultContentHeight: defaultNavigationBarHeight)
    }

    private func estimatedSharedNavigationContentHeight(for controller: AetherViewController, defaultHeight: CGFloat) -> CGFloat {
        let titleAreaHeight = defaultHeight
        guard controller.displayNavigationBar, let contentView = controller.effectiveTopBarAccessory else {
            return titleAreaHeight
        }

        if let searchController = controller.searchController, searchController.placement == .navBar, searchController.isActive {
            if let stacked = contentView as? AetherStackedBarContent {
                return stacked.views.first?.nominalHeight ?? contentView.height
            }
            return contentView.height
        }

        switch contentView.mode {
        case .replacement:
            return contentView.height
        case .expansion:
            return titleAreaHeight + contentView.height
        }
    }

    private func estimatedExternalNavigationBarHeight(for controller: AetherViewController, layout: ContainerViewLayout) -> CGFloat {
        let topOffset = max(layout.statusBarHeight ?? 0.0, layout.safeInsets.top)
        let defaultNavigationBarHeight: CGFloat = 60.0
        return topOffset
            + estimatedSharedNavigationContentHeight(for: controller, defaultHeight: defaultNavigationBarHeight)
            + controller.additionalNavigationBarHeight
    }

    private func updateExternalNavigationBarHeights(
        layout: ContainerViewLayout,
        resolvedTopController: AetherViewController?,
        resolvedTopHeight: CGFloat?
    ) {
        for controller in _viewControllers {
            controller.navigationBarIsExternallyHosted = true
            if let resolvedTopController, controller === resolvedTopController, let resolvedTopHeight {
                controller.externalNavigationBarHeight = resolvedTopHeight
            } else {
                controller.externalNavigationBarHeight = estimatedExternalNavigationBarHeight(for: controller, layout: layout)
            }
        }
    }

    private func updateExternalNavigationBarHeightsForTransition(
        _ state: NavigationBarInteractiveTransition,
        layout: ContainerViewLayout
    ) {
        for controller in _viewControllers {
            controller.navigationBarIsExternallyHosted = true
            if controller === state.sourceController {
                controller.externalNavigationBarHeight = state.sourceBaseFrame.height
            } else if controller === state.targetController {
                controller.externalNavigationBarHeight = state.targetBaseFrame.height
            } else {
                controller.externalNavigationBarHeight = estimatedExternalNavigationBarHeight(for: controller, layout: layout)
            }
        }
    }

    private func previousAction(for controller: AetherViewController, in stack: [AetherViewController]) -> NavigationPreviousAction? {
        guard let index = stack.firstIndex(where: { $0 === controller }), index > 0 else {
            return nil
        }
        return .item(stack[index - 1].navigationBarItem)
    }

    @discardableResult
    private func configureNavigationBar(
        _ bar: NavigationBarImpl,
        for controller: AetherViewController,
        in stack: [AetherViewController],
        layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition,
        animateContent: Bool,
        buttonMorphTransition: ContainedViewLayoutTransition? = nil,
        includeAccessoryContent: Bool = true,
        allowsContainerLayoutRequests: Bool = true
    ) -> AetherViewController.NavigationLayout {
        let presentationData = navigationBarPresentationData(for: controller)
        if bar.presentationData !== presentationData {
            bar.updatePresentationData(presentationData, transition: transition)
        }

        bar.item = controller.navigationBarItem
        bar.previousItem = previousAction(for: controller, in: stack)
        bar.backPressed = { [weak self] in
            self?.popViewController(animated: true)
        }

        let requestLayout = allowsContainerLayoutRequests ? bar.requestContainerLayout : nil
        bar.requestContainerLayout = nil
        if includeAccessoryContent {
            bar.setContentHeightOverride(nil)
            bar.setContentView(controller.displayNavigationBar ? controller.effectiveTopBarAccessory : nil, animated: animateContent)
        } else {
            bar.setContentView(nil, animated: false)
            bar.setContentHeightOverride(
                estimatedSharedNavigationContentHeight(for: controller, defaultHeight: 60.0)
            )
        }
        if bar === sharedNavigationBar {
            bar.edgeEffectHostView = controller.isViewLoaded ? controller.view : nil
        } else {
            bar.edgeEffectHostView = nil
        }
        if allowsContainerLayoutRequests {
            bar.requestContainerLayout = requestLayout ?? { [weak self] transition in
                self?.requestLayout(transition: transition)
            }
        } else {
            bar.requestContainerLayout = nil
        }

        let navLayout = sharedNavigationLayout(for: controller, bar: bar, layout: layout)
        bar.frame = navLayout.navigationFrame
        let updateLayout = {
            bar.updateLayout(
                size: navLayout.navigationFrame.size,
                defaultHeight: navLayout.defaultContentHeight,
                additionalTopHeight: 0.0,
                additionalContentHeight: 0.0,
                additionalBackgroundHeight: 0.0,
                leftInset: layout.safeInsets.left,
                rightInset: layout.safeInsets.right,
                appearsHidden: !controller.displayNavigationBar,
                isLandscape: layout.size.width > layout.size.height,
                transition: transition
            )
        }
        if let buttonMorphTransition {
            bar.withButtonMorphTransition(buttonMorphTransition, updateLayout)
        } else {
            updateLayout()
        }
        return navLayout
    }

    private func updateSharedNavigationBar(for rootLayout: RootNavigationLayout, layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        guard isViewLoaded else {
            return
        }

        let bar = ensureSharedNavigationBar()
        if bar.superview !== view {
            view.addSubview(bar)
        }

        if let interactiveNavigationBarTransition {
            bar.alpha = interactiveNavigationBarTransition.sourceController.displayNavigationBar ? 1.0 : 0.0
            bar.transform = .identity
            bar.setTitleContentHiddenForTransition(true)
            bar.setButtonContentHiddenForTransition(true)
            refreshInteractiveNavigationBarTransition(interactiveNavigationBarTransition, layout: layout, transition: transition)
            updateInteractiveNavigationBarTransition(progress: interactiveNavigationBarTransition.progress, transition: transition)
            return
        }

        let rootStack = activeRootStack(for: rootLayout)
        guard let topController = rootStack.last else {
            transition.updateAlpha(view: bar, alpha: 0.0)
            sharedNavigationBarController = nil
            for controller in _viewControllers {
                controller.navigationBarIsExternallyHosted = true
                controller.externalNavigationBarHeight = nil
                if controller.navigationBarView === bar {
                    controller.navigationBarView = nil
                }
            }
            return
        }
        topController.loadViewIfNeeded()

        let previousController = sharedNavigationBarController
        let shouldAnimateBarSwap = transition.isAnimated && previousController != nil && previousController !== topController
        if shouldAnimateBarSwap {
            bar.setTitleContentHiddenForTransition(true)
        } else {
            bar.setTitleContentHiddenForTransition(false)
        }
        bar.setButtonContentHiddenForTransition(false)
        bar.setButtonChromeScale(1.0, transition: .immediate)

        isUpdatingSharedNavigationBar = true
        defer { isUpdatingSharedNavigationBar = false }

        for controller in _viewControllers {
            controller.navigationBarIsExternallyHosted = true
            if controller === topController {
                controller.navigationBarView = bar
            } else if controller.navigationBarView === bar {
                controller.navigationBarView = nil
            }
        }

        let sharedButtonMorphTransition: ContainedViewLayoutTransition? = shouldAnimateBarSwap ? navigationBarButtonMorphTransition() : nil
        let navLayout = configureNavigationBar(
            bar,
            for: topController,
            in: rootStack,
            layout: layout,
            transition: shouldAnimateBarSwap ? .immediate : transition,
            animateContent: transition.isAnimated && !shouldAnimateBarSwap,
            buttonMorphTransition: sharedButtonMorphTransition
        )
        updateExternalNavigationBarHeights(
            layout: layout,
            resolvedTopController: topController,
            resolvedTopHeight: navLayout.navigationFrame.height
        )

        if shouldAnimateBarSwap {
            bar.alpha = topController.displayNavigationBar ? 1.0 : 0.0
            bar.transform = .identity
            bar.setTitleContentHiddenForTransition(true)
        } else {
            bar.alpha = topController.displayNavigationBar ? 1.0 : 0.0
            bar.transform = .identity
            bar.setTitleContentHiddenForTransition(false)
            bar.setButtonChromeScale(1.0, transition: .immediate)
        }

        sharedNavigationBarController = topController
        if view.subviews.last !== bar {
            view.bringSubviewToFront(bar)
        }
    }

    private func navigationStack(containing first: AetherViewController, pairedWith second: AetherViewController) -> [AetherViewController] {
        func stackByAppendingMissingSource(to controllers: [AetherViewController]) -> [AetherViewController]? {
            guard controllers.contains(where: { $0 === second }) else {
                return nil
            }
            if controllers.contains(where: { $0 === first }) {
                return controllers
            }

            var reconstructed = controllers
            reconstructed.append(first)
            return reconstructed
        }

        if let layout = currentLayoutForComputation() {
            switch makeNavigationLayout(mode: mode, layout: layout, controllers: _viewControllers).root {
            case let .flat(controllers):
                if controllers.contains(where: { $0 === first }) && controllers.contains(where: { $0 === second }) {
                    return controllers
                }
                if let reconstructed = stackByAppendingMissingSource(to: controllers) {
                    return reconstructed
                }
            case let .split(masterControllers, detailControllers):
                if detailControllers.contains(where: { $0 === first }) && detailControllers.contains(where: { $0 === second }) {
                    return detailControllers
                }
                if masterControllers.contains(where: { $0 === first }) && masterControllers.contains(where: { $0 === second }) {
                    return masterControllers
                }
                if let reconstructed = stackByAppendingMissingSource(to: detailControllers) {
                    return reconstructed
                }
                if let reconstructed = stackByAppendingMissingSource(to: masterControllers) {
                    return reconstructed
                }
            }
        }
        if let reconstructed = stackByAppendingMissingSource(to: _viewControllers) {
            return reconstructed
        }
        return _viewControllers
    }

    private func makeTransitionNavigationBar(
        for controller: AetherViewController,
        in stack: [AetherViewController],
        layout: ContainerViewLayout
    ) -> NavigationBarImpl {
        controller.loadViewIfNeeded()
        let bar = NavigationBarImpl(presentationData: navigationBarPresentationData(for: controller))
        bar.autoresizingMask = [.flexibleWidth]
        bar.requestContainerLayout = nil
        configureNavigationBar(
            bar,
            for: controller,
            in: stack,
            layout: layout,
            transition: .immediate,
            animateContent: false,
            allowsContainerLayoutRequests: false
        )
        bar.setTitleTransitionMode(true)
        bar.setTitleContentHiddenForTransition(false)
        bar.setButtonChromeScale(1.0, transition: .immediate)
        return bar
    }

    private func makeTransitionButtonNavigationBar(
        for controller: AetherViewController,
        in stack: [AetherViewController],
        layout: ContainerViewLayout
    ) -> NavigationBarImpl {
        controller.loadViewIfNeeded()
        let bar = NavigationBarImpl(presentationData: navigationBarPresentationData(for: controller))
        bar.autoresizingMask = [.flexibleWidth]
        bar.requestContainerLayout = nil
        configureNavigationBar(
            bar,
            for: controller,
            in: stack,
            layout: layout,
            transition: .immediate,
            animateContent: false,
            includeAccessoryContent: false,
            allowsContainerLayoutRequests: false
        )
        bar.setButtonsOnlyTransitionMode(true)
        bar.setTitleContentHiddenForTransition(true)
        bar.setButtonChromeScale(1.0, transition: .immediate)
        return bar
    }

    private func installTransitionNavigationBars(_ state: NavigationBarInteractiveTransition) {
        if state.targetBar.superview !== state.targetController.view {
            state.targetBar.removeFromSuperview()
            state.targetController.view.addSubview(state.targetBar)
        }
        if state.sourceBar.superview !== state.sourceController.view {
            state.sourceBar.removeFromSuperview()
            state.sourceController.view.addSubview(state.sourceBar)
        }
        state.targetController.view.bringSubviewToFront(state.targetBar)
        state.sourceController.view.bringSubviewToFront(state.sourceBar)
    }

    private func installTransitionButtonNavigationBars(_ state: NavigationBarInteractiveTransition) {
        guard let sourceButtonBar = state.sourceButtonBar, let targetButtonBar = state.targetButtonBar else {
            return
        }

        if sourceButtonBar.superview !== view {
            sourceButtonBar.removeFromSuperview()
            view.addSubview(sourceButtonBar)
        }
        if targetButtonBar.superview !== view {
            targetButtonBar.removeFromSuperview()
            view.addSubview(targetButtonBar)
        }
        view.bringSubviewToFront(targetButtonBar)
        view.bringSubviewToFront(sourceButtonBar)
    }

    private func beginInteractiveNavigationBarTransition(
        direction: NavigationTransitionDirection,
        sourceController: AetherViewController,
        targetController: AetherViewController,
        layout gestureLayout: ContainerViewLayout,
        isInteractive: Bool
    ) {
        guard isViewLoaded else {
            return
        }

        if let existingTransition = interactiveNavigationBarTransition {
            finishInteractiveNavigationBarTransition(existingTransition, completed: false)
        }

        let layout = validLayout ?? gestureLayout
        let stack = navigationStack(containing: sourceController, pairedWith: targetController)
        let sourceBar = makeTransitionNavigationBar(for: sourceController, in: stack, layout: layout)
        let targetBar = makeTransitionNavigationBar(for: targetController, in: stack, layout: layout)
        let state = NavigationBarInteractiveTransition(
            direction: direction,
            sourceController: sourceController,
            targetController: targetController,
            sourceStack: stack,
            targetStack: stack,
            sourceBar: sourceBar,
            targetBar: targetBar,
            isInteractive: isInteractive
        )
        state.sourceButtonBar = makeTransitionButtonNavigationBar(for: sourceController, in: stack, layout: layout)
        state.targetButtonBar = makeTransitionButtonNavigationBar(for: targetController, in: stack, layout: layout)
        interactiveNavigationBarTransition = state

        if let sharedNavigationBar {
            sharedNavigationBar.alpha = sourceController.displayNavigationBar ? 1.0 : 0.0
            sharedNavigationBar.transform = .identity
            sharedNavigationBar.setTitleContentHiddenForTransition(true)
            sharedNavigationBar.setButtonContentHiddenForTransition(true)
            sharedNavigationBar.setButtonChromeScale(1.0, transition: .immediate)
        }

        installTransitionNavigationBars(state)
        installTransitionButtonNavigationBars(state)
        refreshInteractiveNavigationBarTransition(state, layout: layout, transition: .immediate)
        updateExternalNavigationBarHeightsForTransition(state, layout: layout)
        sourceController.containerLayoutUpdated(layout, transition: .immediate)
        targetController.containerLayoutUpdated(layout, transition: .immediate)
        installTransitionNavigationBars(state)
        installTransitionButtonNavigationBars(state)
        updateInteractiveNavigationBarTransition(progress: 0.0, transition: .immediate)
    }

    private func refreshInteractiveNavigationBarTransition(
        _ state: NavigationBarInteractiveTransition,
        layout: ContainerViewLayout,
        transition: ContainedViewLayoutTransition
    ) {
        let sourceLayout = configureNavigationBar(
            state.sourceBar,
            for: state.sourceController,
            in: state.sourceStack,
            layout: layout,
            transition: .immediate,
            animateContent: false,
            allowsContainerLayoutRequests: false
        )
        state.sourceBaseFrame = sourceLayout.navigationFrame
        state.sourceBar.setTitleTransitionMode(true)
        state.sourceBar.setTitleContentHiddenForTransition(false)
        state.sourceBar.setButtonChromeScale(1.0, transition: .immediate)

        let targetLayout = configureNavigationBar(
            state.targetBar,
            for: state.targetController,
            in: state.targetStack,
            layout: layout,
            transition: .immediate,
            animateContent: false,
            allowsContainerLayoutRequests: false
        )
        state.targetBaseFrame = targetLayout.navigationFrame
        state.targetBar.setTitleTransitionMode(true)
        state.targetBar.setTitleContentHiddenForTransition(false)
        state.targetBar.setButtonChromeScale(1.0, transition: .immediate)

        if let sourceButtonBar = state.sourceButtonBar {
            let sourceButtonLayout = configureNavigationBar(
                sourceButtonBar,
                for: state.sourceController,
                in: state.sourceStack,
                layout: layout,
                transition: .immediate,
                animateContent: false,
                includeAccessoryContent: false,
                allowsContainerLayoutRequests: false
            )
            sourceButtonBar.frame = sourceButtonLayout.navigationFrame
            sourceButtonBar.setButtonsOnlyTransitionMode(true)
            sourceButtonBar.setTitleContentHiddenForTransition(true)
            state.sourceButtonChromeLayout = sourceButtonBar.buttonChromeLayout()
        }
        if let targetButtonBar = state.targetButtonBar {
            let targetButtonLayout = configureNavigationBar(
                targetButtonBar,
                for: state.targetController,
                in: state.targetStack,
                layout: layout,
                transition: .immediate,
                animateContent: false,
                includeAccessoryContent: false,
                allowsContainerLayoutRequests: false
            )
            targetButtonBar.frame = targetButtonLayout.navigationFrame
            targetButtonBar.setButtonsOnlyTransitionMode(true)
            targetButtonBar.setTitleContentHiddenForTransition(true)
            state.targetButtonChromeLayout = targetButtonBar.buttonChromeLayout()
        }
        state.didPrepareHeldButtonChrome = false
        state.lastHeldButtonHorizontalScale = nil

        installTransitionNavigationBars(state)
        installTransitionButtonNavigationBars(state)
        updateExternalNavigationBarHeightsForTransition(state, layout: layout)
        if let minimizedContainer, minimizedContainer.superview === view {
            view.bringSubviewToFront(minimizedContainer)
        }
    }

    private func applyNavigationBarTitleTransitionProgress(
        _ state: NavigationBarInteractiveTransition,
        progress: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: ((Bool) -> Void)? = nil
    ) {
        transition.updateFrame(view: state.sourceBar, frame: state.sourceBaseFrame)
        transition.updateFrame(view: state.targetBar, frame: state.targetBaseFrame, completion: completion)

        state.sourceBar.alpha = state.sourceController.displayNavigationBar ? 1.0 : 0.0
        state.targetBar.alpha = state.targetController.displayNavigationBar ? 1.0 : 0.0
        state.targetBar.layer.mask = nil
    }

    private func interpolatedButtonChromeLayout(
        source: NavigationBarImpl.ButtonChromeLayout?,
        target: NavigationBarImpl.ButtonChromeLayout?,
        progress: CGFloat
    ) -> NavigationBarImpl.ButtonChromeLayout? {
        guard let target else {
            return nil
        }
        return NavigationBarImpl.ButtonChromeLayout(
            leftFrame: interpolatedButtonChromeFrame(
                source: source?.leftFrame,
                target: target.leftFrame,
                progress: progress,
                alignment: .left
            ),
            rightFrame: interpolatedButtonChromeFrame(
                source: source?.rightFrame,
                target: target.rightFrame,
                progress: progress,
                alignment: .right
            )
        )
    }

    private func disappearingSourceButtonChromeLayout(
        source: NavigationBarImpl.ButtonChromeLayout?,
        target: NavigationBarImpl.ButtonChromeLayout?,
        progress: CGFloat
    ) -> NavigationBarImpl.ButtonChromeLayout? {
        guard let source else {
            return nil
        }
        return NavigationBarImpl.ButtonChromeLayout(
            leftFrame: disappearingSourceButtonChromeFrame(
                source: source.leftFrame,
                target: target?.leftFrame,
                progress: progress,
                alignment: .left
            ),
            rightFrame: disappearingSourceButtonChromeFrame(
                source: source.rightFrame,
                target: target?.rightFrame,
                progress: progress,
                alignment: .right
            )
        )
    }

    private enum ButtonChromeSide {
        case left
        case right
    }

    private func interpolatedButtonChromeFrame(
        source: CGRect?,
        target: CGRect?,
        progress: CGFloat,
        alignment: ButtonChromeSide
    ) -> CGRect? {
        guard let target else {
            return nil
        }
        let clampedProgress = max(0.0, min(1.0, progress))
        let startFrame = source ?? collapsedButtonChromeFrame(from: target, alignment: alignment)
        return interpolatedAnchoredButtonChromeFrame(
            from: startFrame,
            to: target,
            progress: clampedProgress,
            alignment: alignment,
            anchorFrame: target
        )
    }

    private func disappearingSourceButtonChromeFrame(
        source: CGRect?,
        target: CGRect?,
        progress: CGFloat,
        alignment: ButtonChromeSide
    ) -> CGRect? {
        guard let source else {
            return nil
        }
        let clampedProgress = max(0.0, min(1.0, progress))
        let endFrame = target ?? collapsedButtonChromeFrame(from: source, alignment: alignment)
        return interpolatedAnchoredButtonChromeFrame(
            from: source,
            to: endFrame,
            progress: clampedProgress,
            alignment: alignment,
            anchorFrame: source
        )
    }

    private func collapsedButtonChromeFrame(from frame: CGRect, alignment: ButtonChromeSide) -> CGRect {
        let collapsedWidth = min(frame.width, max(1.0, frame.height))
        switch alignment {
        case .left:
            return CGRect(x: frame.minX, y: frame.minY, width: collapsedWidth, height: frame.height)
        case .right:
            return CGRect(x: frame.maxX - collapsedWidth, y: frame.minY, width: collapsedWidth, height: frame.height)
        }
    }

    private func interpolatedAnchoredButtonChromeFrame(
        from source: CGRect,
        to target: CGRect,
        progress: CGFloat,
        alignment: ButtonChromeSide,
        anchorFrame: CGRect
    ) -> CGRect {
        let width = source.width + (target.width - source.width) * progress
        let height = source.height + (target.height - source.height) * progress
        let y = anchorFrame.midY - height * 0.5
        switch alignment {
        case .left:
            return CGRect(x: anchorFrame.minX, y: y, width: width, height: height)
        case .right:
            return CGRect(x: anchorFrame.maxX - width, y: y, width: width, height: height)
        }
    }

    private func sourceButtonChromeAlpha(source: CGRect?, target: CGRect?, progress: CGFloat) -> CGFloat {
        guard source != nil else {
            return 0.0
        }
        guard let source, let target else {
            return 1.0 - progress
        }
        if abs(source.width - target.width) > 1.0 || abs(source.height - target.height) > 1.0 {
            return 0.0
        }
        return 0.0
    }

    private func targetButtonChromeAlpha(source: CGRect?, target: CGRect?, progress: CGFloat) -> CGFloat {
        guard let target else {
            return 0.0
        }
        guard let source else {
            return progress
        }
        if abs(source.width - target.width) > 1.0 || abs(source.height - target.height) > 1.0 {
            return 1.0
        }
        return 1.0
    }

    private func buttonChromeLayoutHasSizeChange(
        source: NavigationBarImpl.ButtonChromeLayout?,
        target: NavigationBarImpl.ButtonChromeLayout?
    ) -> Bool {
        func hasSizeChange(_ source: CGRect?, _ target: CGRect?) -> Bool {
            guard let source, let target else {
                return false
            }
            return abs(source.width - target.width) > 1.0 || abs(source.height - target.height) > 1.0
        }
        return hasSizeChange(source?.leftFrame, target?.leftFrame) || hasSizeChange(source?.rightFrame, target?.rightFrame)
    }

    private func updateInteractiveButtonNavigationBarTransition(
        _ state: NavigationBarInteractiveTransition,
        progress: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        guard let sourceButtonBar = state.sourceButtonBar, let targetButtonBar = state.targetButtonBar else {
            return
        }

        let clampedProgress = max(0.0, min(1.0, progress))
        let sourceEffectTransition = navigationBarButtonEffectTransition(from: transition, appearing: false)
        let targetEffectTransition = navigationBarButtonEffectTransition(from: transition, appearing: true)
        let maxBlurRadius: CGFloat = 10.0
        let sourceAlpha = 1.0 - clampedProgress
        let targetAlpha = clampedProgress
        let transitionScaleDelta: CGFloat = 0.06
        let sourceScale = 1.0 - transitionScaleDelta * clampedProgress
        let targetScale = 1.0 - transitionScaleDelta * (1.0 - clampedProgress)
        let keepsSharedPureBackButtonStable = sourceButtonBar.hasPureAutomaticBackButtonGroup && targetButtonBar.hasPureAutomaticBackButtonGroup
        let hasChromeSizeChange = buttonChromeLayoutHasSizeChange(
            source: state.sourceButtonChromeLayout,
            target: state.targetButtonChromeLayout
        )
        let sourceChromeAlphaTransition: ContainedViewLayoutTransition = hasChromeSizeChange ? .immediate : sourceEffectTransition
        let targetChromeAlphaTransition: ContainedViewLayoutTransition = hasChromeSizeChange ? .immediate : targetEffectTransition

        sourceButtonBar.alpha = state.sourceController.displayNavigationBar ? 1.0 : 0.0
        targetButtonBar.alpha = state.targetController.displayNavigationBar ? 1.0 : 0.0
        if let sourceChromeLayout = disappearingSourceButtonChromeLayout(
            source: state.sourceButtonChromeLayout,
            target: state.targetButtonChromeLayout,
            progress: clampedProgress
        ) {
            sourceButtonBar.setButtonChromeLayout(sourceChromeLayout, transition: sourceEffectTransition, appearing: false)
        }
        if let targetChromeLayout = interpolatedButtonChromeLayout(
            source: state.sourceButtonChromeLayout,
            target: state.targetButtonChromeLayout,
            progress: clampedProgress
        ) {
            targetButtonBar.setButtonChromeLayout(targetChromeLayout, transition: targetEffectTransition, appearing: true)
        }
        sourceButtonBar.setButtonChromeAlpha(
            left: sourceButtonChromeAlpha(
                source: state.sourceButtonChromeLayout?.leftFrame,
                target: state.targetButtonChromeLayout?.leftFrame,
                progress: clampedProgress
            ),
            right: sourceButtonChromeAlpha(
                source: state.sourceButtonChromeLayout?.rightFrame,
                target: state.targetButtonChromeLayout?.rightFrame,
                progress: clampedProgress
            ),
            keepsPureBackButtonStable: keepsSharedPureBackButtonStable,
            transition: sourceChromeAlphaTransition
        )
        targetButtonBar.setButtonChromeAlpha(
            left: targetButtonChromeAlpha(
                source: state.sourceButtonChromeLayout?.leftFrame,
                target: state.targetButtonChromeLayout?.leftFrame,
                progress: clampedProgress
            ),
            right: targetButtonChromeAlpha(
                source: state.sourceButtonChromeLayout?.rightFrame,
                target: state.targetButtonChromeLayout?.rightFrame,
                progress: clampedProgress
            ),
            keepsPureBackButtonStable: keepsSharedPureBackButtonStable,
            transition: targetChromeAlphaTransition
        )
        sourceButtonBar.setButtonTransitionEffects(
            alpha: sourceAlpha,
            blurRadius: clampedProgress * maxBlurRadius,
            scale: sourceScale,
            pulseAmplitude: buttonPulseAmplitude(appearing: false),
            keepsPureBackButtonStable: keepsSharedPureBackButtonStable,
            transition: sourceEffectTransition
        )
        targetButtonBar.setButtonTransitionEffects(
            alpha: targetAlpha,
            blurRadius: (1.0 - clampedProgress) * maxBlurRadius,
            scale: targetScale,
            pulseAmplitude: buttonPulseAmplitude(appearing: true),
            keepsPureBackButtonStable: keepsSharedPureBackButtonStable,
            transition: targetEffectTransition
        )
    }

    private func holdInteractiveButtonNavigationBarTransition(
        _ state: NavigationBarInteractiveTransition,
        progress: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        guard let sourceButtonBar = state.sourceButtonBar, let targetButtonBar = state.targetButtonBar else {
            return
        }

        let horizontalScale = 1.0 + 0.012 * max(0.0, min(1.0, progress))
        sourceButtonBar.alpha = state.sourceController.displayNavigationBar ? 1.0 : 0.0
        targetButtonBar.alpha = 0.0
        if !state.didPrepareHeldButtonChrome {
            if let sourceChromeLayout = state.sourceButtonChromeLayout {
                sourceButtonBar.setButtonChromeLayout(sourceChromeLayout, transition: .immediate)
            }
            if let targetInitialChromeLayout = interpolatedButtonChromeLayout(
                source: state.sourceButtonChromeLayout,
                target: state.targetButtonChromeLayout,
                progress: 0.0
            ) {
                targetButtonBar.setButtonChromeLayout(targetInitialChromeLayout, transition: .immediate, appearing: true)
            }
            sourceButtonBar.setButtonChromeAlpha(left: 1.0, right: 1.0, transition: .immediate)
            targetButtonBar.setButtonChromeAlpha(left: 0.0, right: 0.0, transition: .immediate)
            sourceButtonBar.setButtonTransitionEffects(alpha: 1.0, blurRadius: 0.0, scale: 1.0, horizontalScale: horizontalScale, transition: .immediate)
            targetButtonBar.setButtonTransitionEffects(alpha: 0.0, blurRadius: 10.0, scale: 1.0, transition: .immediate)
            state.didPrepareHeldButtonChrome = true
            state.lastHeldButtonHorizontalScale = nil
        }

        if transition.isAnimated || state.lastHeldButtonHorizontalScale == nil || abs((state.lastHeldButtonHorizontalScale ?? 1.0) - horizontalScale) > 0.0005 {
            sourceButtonBar.setButtonContentTransform(scale: 1.0, horizontalScale: horizontalScale, transition: transition)
            state.lastHeldButtonHorizontalScale = horizontalScale
        }
    }

    private func updateInteractiveNavigationBarTransition(progress: CGFloat, transition: ContainedViewLayoutTransition) {
        guard let state = interactiveNavigationBarTransition else {
            return
        }

        state.progress = progress
        let clampedProgress = max(0.0, min(1.0, progress))

        applyNavigationBarTitleTransitionProgress(state, progress: progress, transition: transition)

        if state.sourceButtonBar != nil && state.targetButtonBar != nil {
            if state.isInteractive && state.resolvedCompleted != true {
                holdInteractiveButtonNavigationBarTransition(state, progress: clampedProgress, transition: transition)
            } else {
                updateInteractiveButtonNavigationBarTransition(state, progress: clampedProgress, transition: transition)
            }
        }

        if let sharedNavigationBar {
            if let resolvedCompleted = state.resolvedCompleted {
                let resolvedController = resolvedCompleted ? state.targetController : state.sourceController
                sharedNavigationBar.alpha = resolvedController.displayNavigationBar ? 1.0 : 0.0
                sharedNavigationBar.transform = .identity
                sharedNavigationBar.setTitleContentHiddenForTransition(true)
                sharedNavigationBar.setButtonContentHiddenForTransition(true)
                return
            }

            sharedNavigationBar.alpha = state.sourceController.displayNavigationBar ? 1.0 : 0.0
            sharedNavigationBar.transform = .identity
            sharedNavigationBar.setTitleContentHiddenForTransition(true)
            sharedNavigationBar.setButtonContentHiddenForTransition(true)
            sharedNavigationBar.setButtonChromeScale(1.0, transition: transition)
        }
    }

    private func resolveInteractiveNavigationBarTransition(
        completed: Bool,
        transition buttonTransition: ContainedViewLayoutTransition? = nil
    ) {
        guard let state = interactiveNavigationBarTransition else {
            return
        }
        if state.didResolveButtonTransition && state.resolvedCompleted == completed {
            return
        }

        state.didResolveButtonTransition = true
        state.resolvedCompleted = completed
        let targetController = completed ? state.targetController : state.sourceController
        let targetStack = completed ? state.targetStack : state.sourceStack

        if state.isInteractive {
            if let sharedNavigationBar {
                sharedNavigationBar.transform = .identity
                sharedNavigationBar.setTitleContentHiddenForTransition(true)
                sharedNavigationBar.setButtonContentHiddenForTransition(true)
                if view.subviews.last !== sharedNavigationBar {
                    view.bringSubviewToFront(sharedNavigationBar)
                }
            }
            installTransitionButtonNavigationBars(state)
            return
        }

        let bar = ensureSharedNavigationBar()
        if bar.superview !== view {
            view.addSubview(bar)
        }

        let buttonTransition = completed || !state.isInteractive ? (buttonTransition ?? navigationBarButtonMorphTransition()) : .immediate
        if let layout = validLayout ?? currentLayoutForComputation() {
            configureNavigationBar(
                bar,
                for: targetController,
                in: targetStack,
                layout: layout,
                transition: .immediate,
                animateContent: false,
                buttonMorphTransition: buttonTransition,
                includeAccessoryContent: false
            )
            updateExternalNavigationBarHeights(
                layout: layout,
                resolvedTopController: targetController,
                resolvedTopHeight: bar.frame.height
            )
        }

        bar.transform = .identity
        bar.alpha = targetController.displayNavigationBar ? 1.0 : 0.0
        bar.setTitleContentHiddenForTransition(true)
        bar.setButtonContentHiddenForTransition(true)
        if state.sourceButtonBar != nil && state.targetButtonBar != nil {
            if !state.isInteractive {
                updateInteractiveButtonNavigationBarTransition(state, progress: completed ? 1.0 : 0.0, transition: buttonTransition)
            }
        } else {
            bar.setButtonChromeScale(1.0, transition: buttonTransition)
        }
        sharedNavigationBarController = targetController
        if view.subviews.last !== bar {
            view.bringSubviewToFront(bar)
        }
        installTransitionButtonNavigationBars(state)
    }

    private func finishInteractiveNavigationBarTransition(_ state: NavigationBarInteractiveTransition, completed: Bool) {
        let targetController = completed ? state.targetController : state.sourceController
        let targetStack = completed ? state.targetStack : state.sourceStack
        interactiveNavigationBarTransition = nil

        let bar = ensureSharedNavigationBar()
        if bar.superview !== view {
            view.addSubview(bar)
        }

        let shouldRunFinishButtonMorph = completed && state.isInteractive && !state.didResolveButtonTransition
        let finishButtonTransition: ContainedViewLayoutTransition = shouldRunFinishButtonMorph ? navigationBarButtonMorphTransition() : .immediate
        if let layout = validLayout ?? currentLayoutForComputation() {
            configureNavigationBar(
                bar,
                for: targetController,
                in: targetStack,
                layout: layout,
                transition: .immediate,
                animateContent: false,
                buttonMorphTransition: shouldRunFinishButtonMorph ? finishButtonTransition : nil
            )
            updateExternalNavigationBarHeights(
                layout: layout,
                resolvedTopController: targetController,
                resolvedTopHeight: bar.frame.height
            )
        }
        bar.transform = .identity
        bar.alpha = targetController.displayNavigationBar ? 1.0 : 0.0
        bar.setTitleContentHiddenForTransition(false)
        bar.setButtonContentHiddenForTransition(false)
        bar.setButtonChromeScale(1.0, transition: finishButtonTransition)
        sharedNavigationBarController = targetController

        state.sourceBar.removeFromSuperview()
        state.targetBar.removeFromSuperview()
        state.sourceButtonBar?.removeFromSuperview()
        state.targetButtonBar?.removeFromSuperview()
        if view.subviews.last !== bar {
            view.bringSubviewToFront(bar)
        }
    }

    private func cleanupRemovedChildren() {
        var activeIdentifiers = Set(_viewControllers.map { ObjectIdentifier($0) })
        for overlayContainer in overlayContainers where !overlayContainer.isRemoved {
            activeIdentifiers.insert(ObjectIdentifier(overlayContainer.controller))
        }
        for child in children {
            guard let controller = child as? AetherViewController else {
                continue
            }
            guard !activeIdentifiers.contains(ObjectIdentifier(controller)) else {
                continue
            }
            guard controller.parent === self else {
                continue
            }
            controller.topBarAccessoryDidChange = nil
            controller.navigationBarIsExternallyHosted = false
            controller.externalNavigationBarHeight = nil
            if controller.navigationBarView === sharedNavigationBar {
                controller.navigationBarView = nil
            }
            controller.willMove(toParent: nil)
            controller.removeFromParent()
        }
    }

    private func handleControllerRemoved(_ controller: AetherViewController) {
        let wasPresent = _viewControllers.contains { $0 === controller }
        _viewControllers.removeAll { $0 === controller }
        if wasPresent {
            wireControllers(_viewControllers)
            if let layout = validLayout {
                updateVisibleContainers(layout: layout, transition: .immediate)
            }
        } else {
            cleanupRemovedChildren()
        }
    }

    private func handleControllerRemovalCommitted(_ controller: AetherViewController) {
        guard _viewControllers.contains(where: { $0 === controller }) else {
            return
        }
        _viewControllers.removeAll { $0 === controller }
        wireControllers(_viewControllers)
    }

    private func ensureFlatRootContainer() -> NavigationContainer {
        if case let .flat(container)? = rootContainer {
            return container
        }

        let container = NavigationContainer(frame: view.bounds)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.controllerRemoved = { [weak self] controller in
            self?.handleControllerRemoved(controller)
        }
        container.controllerRemovalCommitted = { [weak self] controller in
            self?.handleControllerRemovalCommitted(controller)
        }
        container.requestLayout = { [weak self] transition in
            self?.requestLayout(transition: transition)
        }
        wireNavigationBarTransitionCallbacks(to: container)

        installRootContainerView(container)
        rootContainer = .flat(container)
        return container
    }

    private func ensureSplitRootContainer() -> NavigationSplitContainer {
        if case let .split(container)? = rootContainer {
            return container
        }

        let container = NavigationSplitContainer(
            theme: theme,
            controllerRemoved: { [weak self] controller in
                self?.handleControllerRemoved(controller)
            },
            controllerRemovalCommitted: { [weak self] controller in
                self?.handleControllerRemovalCommitted(controller)
            },
            scrollToTop: { [weak self] target in
                guard let self else {
                    return
                }
                switch target {
                case .master:
                    if case let .split(container)? = self.rootContainer {
                        container.masterContainer.topController?.scrollToTop?()
                    }
                case .detail:
                    if case let .split(container)? = self.rootContainer {
                        container.detailContainer.topController?.scrollToTop?()
                    }
                }
            }
        )
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wireNavigationBarTransitionCallbacks(to: container.masterContainer)
        wireNavigationBarTransitionCallbacks(to: container.detailContainer)

        installRootContainerView(container)
        rootContainer = .split(container)
        return container
    }

    private func wireNavigationBarTransitionCallbacks(to container: NavigationContainer) {
        container.navigationBarTransitionBegan = { [weak self] direction, sourceController, targetController, layout, isInteractive in
            self?.beginInteractiveNavigationBarTransition(
                direction: direction,
                sourceController: sourceController,
                targetController: targetController,
                layout: layout,
                isInteractive: isInteractive
            )
        }
        container.navigationBarTransitionProgress = { [weak self] progress, transition in
            self?.updateInteractiveNavigationBarTransition(progress: progress, transition: transition)
        }
        container.navigationBarTransitionResolutionBegan = { [weak self] completed, transition in
            self?.resolveInteractiveNavigationBarTransition(completed: completed, transition: transition)
        }
        container.navigationBarTransitionEnded = { [weak self] completed in
            guard let self, let transition = self.interactiveNavigationBarTransition else {
                return
            }
            self.finishInteractiveNavigationBarTransition(transition, completed: completed)
            self.applyPendingViewControllersUpdateIfPossible()
        }

        container.bottomBarTransitionBegan = { [weak self] direction, sourceController, targetController, _, isInteractive in
            self?.bottomBarVisibilityTransitionBegan?(direction, sourceController, targetController, isInteractive)
        }
        container.bottomBarTransitionProgress = { [weak self] progress, transition in
            self?.bottomBarVisibilityTransitionProgress?(progress, transition)
        }
        container.bottomBarTransitionResolutionBegan = { [weak self] completed, transition in
            self?.bottomBarVisibilityTransitionResolutionBegan?(completed, transition)
        }
        container.bottomBarTransitionEnded = { [weak self] completed in
            self?.bottomBarVisibilityTransitionEnded?(completed)
        }
    }

    private func installRootContainerView(_ newView: UIView) {
        if let existingRootContainer = rootContainer {
            switch existingRootContainer {
            case let .flat(container):
                container.removeFromSuperview()
            case let .split(container):
                container.removeFromSuperview()
            }
        }

        view.insertSubview(newView, at: 0)
    }

    private func updateStatusBarAppearance() {
        currentStatusBarStyle = theme.statusBar
        setNeedsStatusBarAppearanceUpdate()
    }

    private func overlayLayout(from layout: ContainerViewLayout) -> ContainerViewLayout {
        guard let minimizedContainer, !minimizedContainer.isExpanded else {
            return layout
        }

        var additionalInsets = layout.additionalInsets
        additionalInsets.bottom += minimizedContainer.collapsedHeight(layout: layout)
        return layout.withUpdatedAdditionalInsets(additionalInsets)
    }

    private func currentLayoutForComputation() -> ContainerViewLayout? {
        if let validLayout {
            return validLayout
        }

        guard isViewLoaded else {
            return nil
        }

        let statusBarHeight: CGFloat? = isHostedInModal
            ? AetherModalController.grabberContainerHeight
            : view.window?.windowScene?.statusBarManager?.statusBarFrame.height

        return ContainerViewLayout(
            size: view.bounds.size,
            metrics: LayoutMetrics(
                widthClass: view.traitCollection.horizontalSizeClass == .regular ? .regular : .compact,
                isTablet: UIDevice.current.userInterfaceIdiom == .pad
            ),
            safeInsets: view.safeAreaInsets,
            additionalInsets: .zero,
            statusBarHeight: statusBarHeight,
            inputHeight: nil,
            inputHeightIsInteractivellyChanging: false,
            inVoiceOver: UIAccessibility.isVoiceOverRunning
        )
    }

    private func transitionForUpdate(animated: Bool) -> ContainedViewLayoutTransition {
        animated ? .animated(duration: 0.35, curve: .easeInOut) : .immediate
    }
}
