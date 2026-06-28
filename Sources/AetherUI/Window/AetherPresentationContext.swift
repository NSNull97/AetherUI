import UIKit

public final class AetherInteractionBlockToken {
    private let release: () -> Void
    private var isReleased = false

    init(release: @escaping () -> Void) {
        self.release = release
    }

    deinit {
        invalidate()
    }

    public func invalidate() {
        guard !isReleased else { return }
        isReleased = true
        release()
    }
}

public final class AetherPresentedController {
    public let controller: AetherContainableController
    public let level: AetherPresentationSurfaceLevel
    public let blocksInteraction: Bool
    public let isOpaque: Bool
    public let blocksBackground: Bool

    fileprivate var didInsertView = false
    fileprivate var readinessTimeout: DispatchWorkItem?
    fileprivate var interactionToken: AetherInteractionBlockToken?

    public init(
        controller: AetherContainableController,
        level: AetherPresentationSurfaceLevel,
        blocksInteraction: Bool = false,
        isOpaque: Bool? = nil,
        blocksBackground: Bool? = nil
    ) {
        self.controller = controller
        self.level = level
        self.blocksInteraction = blocksInteraction
        self.isOpaque = isOpaque ?? controller.aetherIsOpaqueWhenInOverlay
        self.blocksBackground = blocksBackground ?? controller.aetherBlocksBackgroundWhenInOverlay
    }
}

public final class AetherPresentationContext {
    public weak var parentController: UIViewController?
    public weak var containerView: UIView? {
        didSet {
            guard oldValue !== containerView else { return }
            if containerView == nil {
                removeInsertedViews()
            } else {
                addPendingViews()
            }
        }
    }

    public var topLevelSubview: ((AetherPresentationSurfaceLevel) -> UIView?)?
    public var underlyingAccessibilityViews: [UIView] = []
    public var controllersUpdated: (([AetherPresentedController]) -> Void)?
    public var interactionBlockedChanged: ((Bool) -> Void)?
    public var opaqueOverlayChanged: ((Bool) -> Void)?
    public var statusBarChanged: ((ContainedViewLayoutTransition) -> Void)?

    public private(set) var presentedControllers: [AetherPresentedController] = []
    public private(set) var blockInteractionTokens: Set<Int> = []
    private var nextBlockInteractionToken = 0
    private var layout: AetherWindowLayout?

    public var hasOpaqueOverlay: Bool {
        presentedControllers.contains { $0.isOpaque || $0.blocksBackground }
    }

    public var topStatusBarRequest: AetherStatusBarRequest? {
        for item in presentedControllers.reversed() {
            if let request = item.controller.aetherStatusBarRequest {
                return request
            }
        }
        return nil
    }

    public init(parentController: UIViewController? = nil, containerView: UIView? = nil) {
        self.parentController = parentController
        self.containerView = containerView
    }

    @discardableResult
    public func present(
        _ controller: AetherContainableController,
        on level: AetherPresentationSurfaceLevel,
        blockInteraction: Bool = false,
        completion: @escaping () -> Void = {}
    ) -> AetherPresentedController {
        aetherAssertMainThread()
        if let existing = presentedControllers.first(where: { $0.controller === controller }) {
            completion()
            return existing
        }

        let item = AetherPresentedController(
            controller: controller,
            level: level,
            blocksInteraction: blockInteraction
        )

        if blockInteraction {
            item.interactionToken = addBlockInteraction()
        }

        insertItemSorted(item)
        controllersUpdated?(presentedControllers)
        updateAccessibilityIsolation()
        statusBarChanged?(.animated(duration: 0.2, curve: .easeInOut))

        let finishPresentation = { [weak self, weak item] in
            guard let self, let item else { return }
            item.readinessTimeout?.cancel()
            item.readinessTimeout = nil
            item.controller.aetherSetReadyHandler(nil)
            item.interactionToken?.invalidate()
            item.interactionToken = nil
            self.insertViewIfPossible(item)
            completion()
        }

        if controller.aetherIsReady {
            finishPresentation()
        } else {
            controller.aetherSetReadyHandler { ready in
                guard ready else { return }
                DispatchQueue.main.async(execute: finishPresentation)
            }
            let timeout = DispatchWorkItem(block: finishPresentation)
            item.readinessTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timeout)
        }

        return item
    }

    public func dismiss(_ controller: AetherContainableController, completion: (() -> Void)? = nil) {
        aetherAssertMainThread()
        guard let index = presentedControllers.firstIndex(where: { $0.controller === controller }) else {
            completion?()
            return
        }
        let item = presentedControllers.remove(at: index)
        item.readinessTimeout?.cancel()
        item.controller.aetherSetReadyHandler(nil)
        item.interactionToken?.invalidate()
        item.interactionToken = nil
        removeViewIfNeeded(item)
        controllersUpdated?(presentedControllers)
        updateAccessibilityIsolation()
        statusBarChanged?(.animated(duration: 0.2, curve: .easeInOut))
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        completion?()
    }

    public func dismissAll() {
        for item in Array(presentedControllers.reversed()) {
            dismiss(item.controller)
        }
    }

    public func updateLayout(_ layout: AetherWindowLayout, transition: ContainedViewLayoutTransition) {
        aetherAssertMainThread()
        self.layout = layout
        for item in presentedControllers where item.didInsertView {
            layoutController(item, layout: layout, transition: transition)
        }
    }

    public func hitTest(point: CGPoint, in view: UIView? = nil, with event: UIEvent?) -> UIView? {
        let coordinateView = view ?? containerView
        guard let coordinateView else { return nil }
        for item in presentedControllers.reversed() where item.didInsertView {
            let controllerView = item.controller.aetherViewController.view!
            let converted = coordinateView.convert(point, to: controllerView)
            if let result = controllerView.hitTest(converted, with: event) {
                return result
            }
            if item.blocksInteraction || item.isOpaque || item.blocksBackground {
                return nil
            }
        }
        return nil
    }

    public func forEachController(_ body: (AetherContainableController) -> Void) {
        for item in presentedControllers {
            body(item.controller)
        }
    }

    public func combinedSupportedOrientations(default defaultMask: UIInterfaceOrientationMask) -> UIInterfaceOrientationMask {
        var mask = defaultMask
        for item in presentedControllers {
            let next = mask.intersection(item.controller.aetherSupportedOrientations)
            mask = next.isEmpty ? mask : next
        }
        return mask.isEmpty ? defaultMask : mask
    }

    public func combinedDeferredScreenEdges() -> UIRectEdge {
        presentedControllers.reduce(UIRectEdge()) { partial, item in
            partial.union(item.controller.aetherDeferredScreenEdges)
        }
    }

    public func combinedPrefersHomeIndicatorAutoHidden() -> Bool {
        presentedControllers.contains { $0.controller.aetherPrefersHomeIndicatorAutoHidden }
    }

    public func updateToInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        // UIViewController has no public imperative orientation callback. AetherUI
        // controllers receive the next deterministic layout update instead.
        _ = orientation
    }

    private func insertItemSorted(_ item: AetherPresentedController) {
        if let index = presentedControllers.firstIndex(where: { $0.level > item.level }) {
            presentedControllers.insert(item, at: index)
        } else {
            presentedControllers.append(item)
        }
    }

    private func addPendingViews() {
        for item in presentedControllers {
            insertViewIfPossible(item)
        }
    }

    private func removeInsertedViews() {
        for item in presentedControllers {
            removeViewIfNeeded(item)
        }
    }

    private func insertViewIfPossible(_ item: AetherPresentedController) {
        guard !item.didInsertView, let containerView else { return }
        item.didInsertView = true

        let viewController = item.controller.aetherViewController
        if viewController.parent !== parentController {
            parentController?.addChild(viewController)
        }

        viewController.beginAppearanceTransition(true, animated: false)
        let controllerView = viewController.view!
        if let layout {
            layoutController(item, layout: layout, transition: .immediate)
        } else {
            controllerView.frame = containerView.bounds
        }

        if let topLevelSubview = topLevelSubview?(item.level), topLevelSubview.superview === containerView {
            containerView.insertSubview(controllerView, belowSubview: topLevelSubview)
        } else if let topHigher = firstSubviewAbove(level: item.level) {
            containerView.insertSubview(controllerView, belowSubview: topHigher)
        } else {
            containerView.addSubview(controllerView)
        }
        viewController.endAppearanceTransition()

        if viewController.parent === parentController {
            viewController.didMove(toParent: parentController)
        }
        updateAccessibilityIsolation()
        UIAccessibility.post(notification: .screenChanged, argument: controllerView)
    }

    private func removeViewIfNeeded(_ item: AetherPresentedController) {
        guard item.didInsertView else { return }
        item.didInsertView = false

        let viewController = item.controller.aetherViewController
        viewController.willMove(toParent: nil)
        viewController.beginAppearanceTransition(false, animated: false)
        viewController.view.removeFromSuperview()
        viewController.endAppearanceTransition()
        if viewController.parent === parentController {
            viewController.removeFromParent()
        }
    }

    private func firstSubviewAbove(level: AetherPresentationSurfaceLevel) -> UIView? {
        for item in presentedControllers where item.level > level && item.didInsertView {
            let view = item.controller.aetherViewController.view!
            if view.superview === containerView {
                return view
            }
        }
        return nil
    }

    private func layoutController(
        _ item: AetherPresentedController,
        layout: AetherWindowLayout,
        transition: ContainedViewLayoutTransition
    ) {
        let view = item.controller.aetherViewController.view!
        transition.updateFrame(view: view, frame: CGRect(origin: .zero, size: layout.size))
        item.controller.aetherContainerLayoutUpdated(layout, transition: transition)
    }

    private func addBlockInteraction() -> AetherInteractionBlockToken {
        let token = nextBlockInteractionToken
        nextBlockInteractionToken += 1
        let wasEmpty = blockInteractionTokens.isEmpty
        blockInteractionTokens.insert(token)
        if wasEmpty {
            interactionBlockedChanged?(true)
        }
        return AetherInteractionBlockToken { [weak self] in
            guard let self else { return }
            let wasEmpty = self.blockInteractionTokens.isEmpty
            self.blockInteractionTokens.remove(token)
            if !wasEmpty && self.blockInteractionTokens.isEmpty {
                self.interactionBlockedChanged?(false)
            }
        }
    }

    private func updateAccessibilityIsolation() {
        var lowerViewsShouldBeHidden = false
        for item in presentedControllers.reversed() {
            let view = item.controller.aetherViewController.view
            view?.accessibilityElementsHidden = lowerViewsShouldBeHidden
            if item.isOpaque || item.blocksBackground {
                lowerViewsShouldBeHidden = true
            }
        }
        for view in underlyingAccessibilityViews {
            view.accessibilityElementsHidden = lowerViewsShouldBeHidden
        }
        opaqueOverlayChanged?(lowerViewsShouldBeHidden)
    }
}
