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

/// Pure UIKit navigation controller with Telegram-style transitions and glass support.
/// Replaces the ASDK-based NavigationController.
open class TelegramNavigationController: UIViewController, UIGestureRecognizerDelegate {
    // MARK: - Properties

    private let mode: NavigationControllerMode
    private var theme: NavigationControllerTheme

    /// Single shared navigation bar for this stack — like UINavigationBar
    /// on UINavigationController. Lives on the nav controller's own view,
    /// above the container. Children's own bars are hidden
    /// (`displayNavigationBar = false`) so this is the only visible one.
    public let navigationBar: NavigationBarImpl

    private var rootContainer: RootContainer?
    private var modalContainers: [NavigationModalContainer] = []
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

        if let topModalController = modalContainers.last?.topController {
            return topModalController
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
        self.navigationBar = NavigationBarImpl(
            presentationData: NavigationBarPresentationData(theme: theme.navigationBar)
        )

        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = theme.emptyAreaColor

        navigationBar.backPressed = { [weak self] in
            self?.popViewController(animated: true)
        }
        navigationBar.requestContainerLayout = { [weak self] transition in
            self?.requestLayout(transition: transition)
        }
        view.addSubview(navigationBar)

        wireControllers(_viewControllers)
        syncBarToTopController(animated: false)
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
        let layout = ContainerViewLayout(
            size: view.bounds.size,
            metrics: LayoutMetrics(
                widthClass: view.traitCollection.horizontalSizeClass == .regular ? .regular : .compact,
                isTablet: UIDevice.current.userInterfaceIdiom == .pad
            ),
            safeInsets: view.safeAreaInsets,
            additionalInsets: .zero,
            statusBarHeight: view.window?.windowScene?.statusBarManager?.statusBarFrame.height,
            inputHeight: nil,
            inputHeightIsInteractivellyChanging: false,
            inVoiceOver: UIAccessibility.isVoiceOverRunning
        )
        containerLayoutUpdated(layout, transition: transition)
    }

    public func requestLayout(transition: ContainedViewLayoutTransition) {
        updateContainerLayout(transition: transition)
    }

    // MARK: - Navigation Stack

    public func setViewControllers(_ viewControllers: [ViewController], animated: Bool = true) {
        _viewControllers = viewControllers
        wireControllers(viewControllers)
        syncBarToTopController(animated: false)

        if let layout = currentLayoutForComputation() {
            updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: animated))
        }
    }

    public func pushViewController(_ controller: ViewController, animated: Bool = true) {
        _viewControllers.append(controller)
        wireControllers(_viewControllers)
        syncBarToTopController(animated: animated)

        if let layout = currentLayoutForComputation() {
            updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: animated))
        }
    }

    @discardableResult
    public func popViewController(animated: Bool = true) -> ViewController? {
        guard let layout = currentLayoutForComputation() else {
            guard _viewControllers.count > 1 else {
                return nil
            }
            return _viewControllers.removeLast()
        }

        let navigationLayout = makeNavigationLayout(mode: mode, layout: layout, controllers: _viewControllers)
        if let lastModal = navigationLayout.modal.last, let removedController = lastModal.controllers.last {
            _viewControllers.removeAll { $0 === removedController }
            updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: animated))
            return removedController
        }

        guard _viewControllers.count > 1 else {
            return nil
        }

        let removedController = _viewControllers.removeLast()
        updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: animated))
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

    // MARK: - Modal Presentation

    public func presentModal(_ controller: ViewController, animated: Bool = true, completion: (() -> Void)? = nil) {
        if case .default = controller.navigationPresentation {
            controller.navigationPresentation = .modal
        }

        pushViewController(controller, animated: animated)
        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + transitionForUpdate(animated: true).duration) {
                completion?()
            }
        } else {
            completion?()
        }
    }

    public func dismissModal(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let layout = currentLayoutForComputation() else {
            completion?()
            return
        }

        let navigationLayout = makeNavigationLayout(mode: mode, layout: layout, controllers: _viewControllers)
        guard let lastModal = navigationLayout.modal.last, !lastModal.controllers.isEmpty else {
            completion?()
            return
        }

        removeControllers(lastModal.controllers)
        updateVisibleContainers(layout: layout, transition: transitionForUpdate(animated: animated))

        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + transitionForUpdate(animated: true).duration) {
                completion?()
            }
        } else {
            completion?()
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
        beforeMaximize: @escaping (TelegramNavigationController, @escaping () -> Void) -> Void,
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
        for modalContainer in modalContainers {
            modalContainer.updateTheme(theme)
        }

        if let layout = validLayout {
            updateVisibleContainers(layout: layout, transition: .immediate)
        } else {
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    // MARK: - Shared navigation bar

    /// Compute the bar's frame and the default content height for the
    /// current layout. Mirrors `ViewController.navigationLayout` but uses
    /// our own `navigationBar` instead of a child's.
    private func barLayout(for layout: ContainerViewLayout) -> (frame: CGRect, defaultHeight: CGFloat) {
        let statusBarHeight: CGFloat = layout.statusBarHeight ?? 0.0
        let defaultHeight: CGFloat = 60.0
        let contentHeight = navigationBar.contentHeight(defaultHeight: defaultHeight)
        let barHeight = statusBarHeight + contentHeight
        let frame = CGRect(origin: .zero, size: CGSize(width: layout.size.width, height: barHeight))
        return (frame, defaultHeight)
    }

    /// Update the shared bar's `item`, `previousItem`, and `contentView`
    /// to reflect the current top controller's state.
    public func syncBarToTopController(animated: Bool) {
        guard let top = _viewControllers.last else { return }
        let topIndex = _viewControllers.count - 1

        // Previous item (back button) — point at the controller below
        // the top, if any.
        let previous: NavigationPreviousAction?
        if topIndex > 0 {
            previous = .item(_viewControllers[topIndex - 1].navigationItem)
        } else {
            previous = nil
        }

        navigationBar.item = top.navigationItem
        navigationBar.previousItem = previous

        // Forward the top controller's content view (e.g. filter chips)
        // to the shared bar.
        navigationBar.setContentView(top.navigationBarContent, animated: animated)

        // Watch for future content-view changes while this controller
        // is on top.
        top.navigationBarContentDidChange = { [weak self, weak top] in
            guard let self, let top, top === self._viewControllers.last else { return }
            self.navigationBar.setContentView(top.navigationBarContent, animated: true)
            self.requestLayout(transition: .animated(duration: 0.25, curve: .easeInOut))
        }
    }

    // MARK: - Private

    private func updateVisibleContainers(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        wireControllers(_viewControllers)

        // Position the shared bar.
        let bar = barLayout(for: layout)
        transition.updateFrame(view: navigationBar, frame: bar.frame)
        navigationBar.updateLayout(
            size: bar.frame.size,
            defaultHeight: bar.defaultHeight,
            additionalTopHeight: 0,
            additionalContentHeight: 0,
            additionalBackgroundHeight: 0,
            leftInset: layout.safeInsets.left,
            rightInset: layout.safeInsets.right,
            appearsHidden: false,
            isLandscape: layout.size.width > layout.size.height,
            transition: transition
        )
        view.bringSubviewToFront(navigationBar)

        // Container layout: carve out the bar's height so children
        // position content below it.
        let barTopInset = max(0.0, bar.frame.maxY - layout.safeInsets.top)
        let containerLayout = ContainerViewLayout(
            size: layout.size,
            metrics: layout.metrics,
            safeInsets: layout.safeInsets,
            additionalInsets: UIEdgeInsets(
                top: layout.additionalInsets.top + barTopInset,
                left: layout.additionalInsets.left,
                bottom: layout.additionalInsets.bottom,
                right: layout.additionalInsets.right
            ),
            statusBarHeight: layout.statusBarHeight,
            inputHeight: layout.inputHeight,
            inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging,
            inVoiceOver: layout.inVoiceOver
        )

        let navigationLayout = makeNavigationLayout(mode: mode, layout: containerLayout, controllers: _viewControllers)
        updateRootContainer(for: navigationLayout.root, layout: containerLayout, transition: transition)
        updateMinimizedContainer(layout: layout, transition: transition)
        updateModalContainers(for: navigationLayout.modal, layout: containerLayout, transition: transition)
        updateOverlayContainers(layout: overlayLayout(from: containerLayout), transition: transition)
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

    private func updateModalContainers(for modalLayouts: [ModalContainerLayout], layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        for index in 0..<modalLayouts.count {
            let modalLayout = modalLayouts[index]
            let container: NavigationModalContainer
            let isNewContainer: Bool

            if index < modalContainers.count {
                container = modalContainers[index]
                isNewContainer = false
                container.updateTheme(theme)
                container.setControllers(modalLayout.controllers, isFlat: modalLayout.isFlat, animated: transition.isAnimated)
            } else {
                let newContainer = NavigationModalContainer(
                    controllers: modalLayout.controllers,
                    theme: theme,
                    isFlat: modalLayout.isFlat,
                    controllerRemoved: { [weak self] controller in
                        self?.handleControllerRemoved(controller)
                    },
                    requestLayout: { [weak self] transition in
                        self?.requestLayout(transition: transition)
                    },
                    dismissRequested: { [weak self] in
                        self?.dismissModal(animated: true, completion: nil)
                    }
                )
                modalContainers.append(newContainer)
                view.addSubview(newContainer)
                container = newContainer
                isNewContainer = true
            }

            container.frame = CGRect(origin: .zero, size: layout.size)
            container.containerLayoutUpdated(layout, transition: transition)
            if isNewContainer {
                if transition.isAnimated {
                    container.animateIn()
                } else {
                    container.applyPresentedState()
                }
            }
            view.bringSubviewToFront(container)
        }

        while modalContainers.count > modalLayouts.count {
            let container = modalContainers.removeLast()
            if transition.isAnimated {
                container.animateOut {
                    container.removeFromSuperview()
                }
            } else {
                container.removeFromSuperview()
            }
        }

        // The backing controller stays in place — modal sheet sits on top
        // without transforming root content (per user spec).
    }

    private func isModalPresentation(_ mode: ViewControllerNavigationPresentation) -> Bool {
        switch mode {
        case .modal, .flatModal, .standaloneModal, .standaloneFlatModal,
             .modalInLargeLayout, .modalInCompactLayout:
            return true
        case .default, .master:
            return false
        }
    }

    private func wireControllers(_ viewControllers: [ViewController]) {
        for controller in viewControllers {
            // Children don't render their own bars — the nav controller
            // owns the single shared bar. This prevents double glass
            // layers and simplifies transition animations.
            controller.displayNavigationBar = false

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
        syncBarToTopController(animated: false)
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

        if let firstModalContainer = modalContainers.first {
            view.insertSubview(newView, belowSubview: firstModalContainer)
        } else {
            view.insertSubview(newView, at: 0)
        }
    }

    private func updateStatusBarAppearance() {
        currentStatusBarStyle = theme.statusBar
        setNeedsStatusBarAppearanceUpdate()
    }

    private func removeControllers(_ controllers: [ViewController]) {
        let identifiers = Set(controllers.map { ObjectIdentifier($0) })
        _viewControllers.removeAll { identifiers.contains(ObjectIdentifier($0)) }
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

        return ContainerViewLayout(
            size: view.bounds.size,
            metrics: LayoutMetrics(
                widthClass: view.traitCollection.horizontalSizeClass == .regular ? .regular : .compact,
                isTablet: UIDevice.current.userInterfaceIdiom == .pad
            ),
            safeInsets: view.safeAreaInsets,
            additionalInsets: .zero,
            statusBarHeight: view.window?.windowScene?.statusBarManager?.statusBarFrame.height,
            inputHeight: nil,
            inputHeightIsInteractivellyChanging: false,
            inVoiceOver: UIAccessibility.isVoiceOverRunning
        )
    }

    private func transitionForUpdate(animated: Bool) -> ContainedViewLayoutTransition {
        animated ? .animated(duration: 0.35, curve: .easeInOut) : .immediate
    }
}
