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

    public static func liquidGlass(overallDarkAppearance: Bool = false, emptyAreaColor: UIColor = .systemBackground) -> NavigationControllerTheme {
        return NavigationControllerTheme(
            statusBar: overallDarkAppearance ? .white : .black,
            navigationBar: .liquidGlass(
                overallDarkAppearance: overallDarkAppearance,
                buttonColor: overallDarkAppearance ? .white : .label,
                primaryTextColor: overallDarkAppearance ? .white : .label
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
open class CrystalNavigationController: UIViewController, UIGestureRecognizerDelegate {
    // MARK: - Properties

    private let mode: NavigationControllerMode
    private var theme: NavigationControllerTheme

    private var rootContainer: RootContainer?
    private var overlayContainers: [NavigationOverlayContainer] = []

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

    private var _viewControllers: [ViewController] = []
    public var viewControllerStack: [ViewController] {
        _viewControllers
    }

    public var topController: ViewController? {
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
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = theme.emptyAreaColor
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
        // When hosted inside a CrystalModalController the "status bar"
        // region is reused for the grabber strip: a navbar built with
        // statusBarHeight = grabberContainerHeight has its chrome laid
        // out below the grabber, and its own edge-effect frost covers
        // the grabber area naturally (no extra work). Outside a modal,
        // use the real window status bar height.
        let statusBarHeight: CGFloat? = isHostedInModal
            ? CrystalModalController.grabberContainerHeight
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
            if vc is CrystalModalController { return true }
            current = vc.parent
        }
        return false
    }

    public func requestLayout(transition: ContainedViewLayoutTransition) {
        updateContainerLayout(transition: transition)
    }

    // MARK: - Navigation Stack

    public func setViewControllers(_ viewControllers: [ViewController], animated: Bool = true) {
        _viewControllers = viewControllers
        wireControllers(viewControllers)

        if let layout = currentLayoutForComputation() {
            updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: animated))
        }
    }

    public func pushViewController(_ controller: ViewController, animated: Bool = true) {
        _viewControllers.append(controller)
        wireControllers(_viewControllers)

        if let layout = currentLayoutForComputation() {
            updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: animated))
        }
    }

    @discardableResult
    public func popViewController(animated: Bool = true) -> ViewController? {
        guard _viewControllers.count > 1 else {
            return nil
        }

        let removedController = _viewControllers.removeLast()
        if let layout = currentLayoutForComputation() {
            updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: animated))
        }
        return removedController
    }

    public func popToRoot(animated: Bool = true) {
        guard let firstController = _viewControllers.first else {
            return
        }
        _viewControllers = [firstController]
        if let layout = currentLayoutForComputation() {
            updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: animated))
        }
    }

    public func replaceTopController(_ controller: ViewController, animated: Bool = true) {
        guard !_viewControllers.isEmpty else {
            pushViewController(controller, animated: animated)
            return
        }

        _viewControllers[_viewControllers.count - 1] = controller
        wireControllers(_viewControllers)

        if let layout = currentLayoutForComputation() {
            updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: animated))
        }
    }

    // MARK: - Overlay Presentation

    public var overlayControllers: [ViewController] {
        return overlayContainers.filter { !$0.isRemoved }.map(\.controller)
    }

    public var topOverlayController: ViewController? {
        return overlayContainers.last(where: { !$0.isRemoved })?.controller
    }

    public func presentOverlay(_ controller: ViewController, blocksInteractionUntilReady: Bool = false, animated: Bool = true, completion: (() -> Void)? = nil) {
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

    public func dismissOverlay(_ controller: ViewController? = nil, animated: Bool = true, completion: (() -> Void)? = nil) {
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
        beforeMaximize: @escaping (CrystalNavigationController, @escaping () -> Void) -> Void,
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
        view.backgroundColor = theme.emptyAreaColor

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

    private func updateVisibleContainers(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let navigationLayout = makeNavigationLayout(mode: mode, layout: layout, controllers: _viewControllers)
        updateRootContainer(for: navigationLayout.root, layout: layout, transition: transition)
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

            view.bringSubviewToFront(container)
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
        view.bringSubviewToFront(minimizedContainer)
    }

    private func wireControllers(_ viewControllers: [ViewController]) {
        let barData = NavigationBarPresentationData(theme: theme.navigationBar)
        let layoutCallback: (ContainedViewLayoutTransition) -> Void = { [weak self] transition in
            self?.requestLayout(transition: transition)
        }
        let backCallback: () -> Void = { [weak self] in
            self?.popViewController(animated: true)
        }

        for (index, controller) in viewControllers.enumerated() {
            // Ensure the controller has its own nav bar.
            if controller.navigationBarView == nil {
                let bar = NavigationBarImpl(presentationData: barData)
                controller.navigationBarView = bar
                bar.backPressed = backCallback
                if controller.isViewLoaded {
                    controller.view.addSubview(bar)
                }
            }

            // Configure per-screen bar state.
            if let bar = controller.navigationBarView {
                bar.item = controller.navigationItem

                if index > 0 {
                    bar.previousItem = .item(viewControllers[index - 1].navigationItem)
                } else {
                    bar.previousItem = nil
                }

                // Content view (filter bar) — silence the layout callback
                // while swapping it in so we don't trigger a recursive pass.
                if controller.displayNavigationBar {
                    bar.requestContainerLayout = nil
                    bar.setContentView(controller.navigationBarContent, animated: false)
                }
                bar.requestContainerLayout = layoutCallback
            }

            if controller.parent !== self {
                addChild(controller)
                controller.didMove(toParent: self)
            }
        }
    }

    private func cleanupRemovedChildren() {
        var activeIdentifiers = Set(_viewControllers.map { ObjectIdentifier($0) })
        for overlayContainer in overlayContainers where !overlayContainer.isRemoved {
            activeIdentifiers.insert(ObjectIdentifier(overlayContainer.controller))
        }
        for child in children {
            guard let controller = child as? ViewController else {
                continue
            }
            guard !activeIdentifiers.contains(ObjectIdentifier(controller)) else {
                continue
            }
            guard controller.parent === self else {
                continue
            }
            controller.willMove(toParent: nil)
            controller.removeFromParent()
        }
    }

    private func handleControllerRemoved(_ controller: ViewController) {
        _viewControllers.removeAll { $0 === controller }
        wireControllers(_viewControllers)
        if let layout = validLayout {
            updateVisibleContainers(layout: layout, transition: .immediate)
        }
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
        container.requestLayout = { [weak self] transition in
            self?.requestLayout(transition: transition)
        }

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

        installRootContainerView(container)
        rootContainer = .split(container)
        return container
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
            ? CrystalModalController.grabberContainerHeight
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
