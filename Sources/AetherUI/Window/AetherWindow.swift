import UIKit

// MARK: - Internal Layout Types

private let statusBarHiddenInLandscape: Bool = UIDevice.current.userInterfaceIdiom == .phone

private struct WindowLayout: Equatable {
    var size: CGSize
    var metrics: LayoutMetrics
    var statusBarHeight: CGFloat?
    var forceInCallStatusBarText: String?
    var inputHeight: CGFloat?
    var safeInsets: UIEdgeInsets
    var upperKeyboardInputPositionBound: CGFloat?
    var inVoiceOver: Bool
}

private struct UpdatingLayout {
    var layout: WindowLayout
    var transition: ContainedViewLayoutTransition

    mutating func upgradeTransition(_ transition: ContainedViewLayoutTransition, override: Bool) {
        switch self.transition {
        case .immediate:
            self.transition = transition
        default:
            if override {
                self.transition = transition
            }
        }
    }

    mutating func updateSize(_ size: CGSize, metrics: LayoutMetrics, safeInsets: UIEdgeInsets, transition: ContainedViewLayoutTransition, overrideTransition: Bool) {
        self.upgradeTransition(transition, override: overrideTransition)
        self.layout.size = size
        self.layout.metrics = metrics
        self.layout.safeInsets = safeInsets
    }

    mutating func updateForceInCallStatusBarText(_ text: String?, transition: ContainedViewLayoutTransition, overrideTransition: Bool) {
        self.upgradeTransition(transition, override: overrideTransition)
        self.layout.forceInCallStatusBarText = text
    }

    mutating func updateStatusBarHeight(_ statusBarHeight: CGFloat?, transition: ContainedViewLayoutTransition, overrideTransition: Bool) {
        self.upgradeTransition(transition, override: overrideTransition)
        self.layout.statusBarHeight = statusBarHeight
    }

    mutating func updateInputHeight(_ inputHeight: CGFloat?, transition: ContainedViewLayoutTransition, overrideTransition: Bool) {
        self.upgradeTransition(transition, override: overrideTransition)
        self.layout.inputHeight = inputHeight
    }

    mutating func updateUpperKeyboardInputPositionBound(_ bound: CGFloat?, transition: ContainedViewLayoutTransition, overrideTransition: Bool) {
        self.upgradeTransition(transition, override: overrideTransition)
        self.layout.upperKeyboardInputPositionBound = bound
    }

    mutating func updateInVoiceOver(_ inVoiceOver: Bool) {
        self.layout.inVoiceOver = inVoiceOver
    }
}

private func inputHeightOffset(for layout: WindowLayout) -> CGFloat {
    if let inputHeight = layout.inputHeight, let upperBound = layout.upperKeyboardInputPositionBound {
        return max(0.0, upperBound - (layout.size.height - inputHeight))
    }
    return 0.0
}

private func containedLayout(from layout: WindowLayout) -> ContainerViewLayout {
    var resolvedStatusBarHeight = layout.statusBarHeight
    if layout.forceInCallStatusBarText != nil, resolvedStatusBarHeight != nil {
        resolvedStatusBarHeight = max(40.0, layout.safeInsets.top)
    }
    let isLandscape = layout.size.width > layout.size.height
    if statusBarHiddenInLandscape && isLandscape {
        resolvedStatusBarHeight = nil
    }

    var updatedInputHeight = layout.inputHeight
    if updatedInputHeight != nil && layout.upperKeyboardInputPositionBound != nil {
        updatedInputHeight = (updatedInputHeight ?? 0) - inputHeightOffset(for: layout)
    }

    let isInteractivelyChanging = layout.upperKeyboardInputPositionBound != nil
        && layout.upperKeyboardInputPositionBound != layout.size.height
        && layout.inputHeight != nil

    return ContainerViewLayout(
        size: layout.size,
        metrics: layout.metrics,
        safeInsets: layout.safeInsets,
        additionalInsets: .zero,
        statusBarHeight: resolvedStatusBarHeight,
        inputHeight: updatedInputHeight,
        inputHeightIsInteractivellyChanging: isInteractivelyChanging,
        inVoiceOver: layout.inVoiceOver
    )
}

private func layoutMetrics(for size: CGSize) -> LayoutMetrics {
    if size.width > 690.0 && size.height > 650.0 {
        return LayoutMetrics(widthClass: .regular, isTablet: UIDevice.current.userInterfaceIdiom == .pad)
    } else {
        return LayoutMetrics(widthClass: .compact, isTablet: UIDevice.current.userInterfaceIdiom == .pad)
    }
}

// MARK: - AetherNativeWindow

/// Custom `UIWindow` subclass that provides keyboard tracking, interactive
/// keyboard dismissal, status bar management, orientation handling, and
/// layout propagation to the content controller hierarchy.
///
/// Usage:
/// ```swift
/// let window = AetherWindow(windowScene: scene)
/// window.contentController = myTabBarController   // or nav controller
/// window.makeKeyAndVisible()
/// ```
public final class AetherNativeWindow: UIWindow, AetherWindowHost {

    // MARK: - Private State

    private let _rootController = AetherWindowRootViewController()

    private var windowLayout: WindowLayout
    private var updatingLayout: UpdatingLayout?
    private var updatedContainerLayout: ContainerViewLayout?
    private var isFirstLayout = true

    // Keyboard
    private var keyboardFrameChangeObserver: NSObjectProtocol?
    private var keyboardDidHideObserver: NSObjectProtocol?
    private var keyboardTypeChangeObserver: NSObjectProtocol?
    private var keyboardTypeChangeTimer: Timer?
    private var interactiveKeyboardDismissCleanupWorkItem: DispatchWorkItem?
    private var shouldNotAnimateLikelyKeyboardAutocorrectionSwitch = false
    private var isCompletingInteractiveKeyboardDismissal = false

    // Pan gesture for interactive keyboard dismissal
    private var windowPanRecognizer: AetherWindowPanRecognizer?
    private let keyboardGestureDelegate = AetherWindowKeyboardGestureRecognizerDelegate()
    private var keyboardGestureBeginLocation: CGPoint?
    private var keyboardGestureAccessoryHeight: CGFloat?

    // VoiceOver
    private var voiceOverObserver: NSObjectProtocol?

    // Status bar
    private var statusBarHidden = false
    private var forceInCallStatusBarText: String?
    private var forceInCallStatusBarView: UILabel?

    // Global overlay / portal
    private lazy var presentationContext: AetherPresentationContext = {
        let context = AetherPresentationContext(parentController: _rootController, containerView: _rootController.view)
        context.topLevelSubview = { [weak self] _ in
            self?.topLevelOverlayControllers.first?.view
                ?? self?.globalPortalHostViews.first
                ?? self?.forceInCallStatusBarView
                ?? self?.coveringView
        }
        return context
    }()
    private var _topLevelOverlayControllers: [UIViewController] = []
    private var globalPortalHostViews: [UIView] = []
    private var forceBadgeHidden = true
    private var proximityDimView: UIView?
    private var postUpdateToInterfaceOrientationBlocks: [() -> Void] = []

    // Debug tap
    private var debugTapCounter: (Double, Int) = (0.0, 0)
    private var debugTapRecognizer: UITapGestureRecognizer?

    // MARK: - Public API

    /// The main content controller displayed in this window.
    /// Typically a `AetherTabBarController` or `AetherNavigationController`.
    public var contentController: UIViewController? {
        didSet {
            if let old = oldValue {
                old.willMove(toParent: nil)
                old.view.removeFromSuperview()
                old.removeFromParent()
            }
            if let controller = contentController {
                _rootController.addChild(controller)
                _rootController.view.insertSubview(controller.view, at: 0)
                controller.didMove(toParent: _rootController)
                presentationContext.underlyingAccessibilityViews = [controller.view]

                if !windowLayout.size.width.isZero && !windowLayout.size.height.isZero {
                    controller.view.frame = CGRect(origin: .zero, size: windowLayout.size)
                    let layout = containedLayout(from: windowLayout)
                    updateContentController(layout: layout, transition: .immediate)
                }
            } else {
                presentationContext.underlyingAccessibilityViews = []
            }
        }
    }

    /// The current layout computed by this window, including keyboard height.
    /// Controllers can read this to obtain keyboard-aware layout data.
    public var currentLayout: ContainerViewLayout {
        return containedLayout(from: windowLayout)
    }

    /// Controllers displayed above the main root controller, matching
    /// AetherUI's top-level overlay surface. They receive the same
    /// keyboard-aware `ContainerViewLayout` as the content controller.
    public var topLevelOverlayControllers: [UIViewController] {
        get {
            return _topLevelOverlayControllers
        }
        set {
            for controller in _topLevelOverlayControllers where !newValue.contains(where: { $0 === controller }) {
                controller.willMove(toParent: nil)
                controller.view.removeFromSuperview()
                controller.removeFromParent()
            }

            _topLevelOverlayControllers = newValue

            for controller in _topLevelOverlayControllers {
                if controller.parent !== _rootController {
                    _rootController.addChild(controller)
                    _rootController.view.addSubview(controller.view)
                    controller.didMove(toParent: _rootController)
                } else if controller.view.superview == nil {
                    _rootController.view.addSubview(controller.view)
                }

                if !windowLayout.size.width.isZero && !windowLayout.size.height.isZero {
                    controller.view.frame = CGRect(origin: .zero, size: windowLayout.size)
                    updateOverlayController(controller, layout: currentLayout, transition: .immediate)
                }
            }

            reorderTopLevelSurfaces()
        }
    }

    /// Overlay view shown for app snapshot protection in the task switcher.
    /// Animates in/out with a fade when set/unset.
    public var coveringView: AetherWindowCoveringView? {
        didSet {
            guard coveringView !== oldValue else { return }
            if let old = oldValue {
                old.layer.allowsGroupOpacity = true
                old.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2) { [weak old] _ in
                    old?.removeFromSuperview()
                }
            }
            if let covering = coveringView {
                covering.layer.removeAnimation(forKey: "opacity")
                covering.layer.allowsGroupOpacity = false
                covering.alpha = 1.0
                _rootController.view.addSubview(covering)
                if !windowLayout.size.width.isZero {
                    covering.frame = CGRect(origin: .zero, size: windowLayout.size)
                    covering.updateLayout(windowLayout.size)
                }
                reorderTopLevelSurfaces()
            }
        }
    }

    /// Closure triggered by tapping the window 10 times within 0.4 seconds.
    public var debugAction: (() -> Void)? {
        didSet {
            if debugAction != nil {
                if debugTapRecognizer == nil {
                    let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleDebugTap(_:)))
                    debugTapRecognizer = recognizer
                    _rootController.view.addGestureRecognizer(recognizer)
                }
            } else if let recognizer = debugTapRecognizer {
                debugTapRecognizer = nil
                _rootController.view.removeGestureRecognizer(recognizer)
            }
        }
    }

    public func presentInGlobalOverlay(_ controller: UIViewController, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard !topLevelOverlayControllers.contains(where: { $0 === controller }) else {
            completion?()
            return
        }

        var controllers = topLevelOverlayControllers
        controllers.append(controller)
        topLevelOverlayControllers = controllers

        if animated {
            controller.view.alpha = 0.0
            controller.view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
            UIView.animate(withDuration: 0.22, delay: 0.0, options: [.curveEaseOut, .beginFromCurrentState], animations: {
                controller.view.alpha = 1.0
                controller.view.transform = .identity
            }, completion: { _ in
                completion?()
            })
        } else {
            controller.view.alpha = 1.0
            controller.view.transform = .identity
            completion?()
        }
    }

    public func dismissGlobalOverlay(_ controller: UIViewController, animated: Bool = true, completion: (() -> Void)? = nil) {
        guard topLevelOverlayControllers.contains(where: { $0 === controller }) else {
            completion?()
            return
        }

        let finish = { [weak self, weak controller] in
            guard let self, let controller else {
                completion?()
                return
            }
            self.topLevelOverlayControllers = self.topLevelOverlayControllers.filter { $0 !== controller }
            completion?()
        }

        if animated {
            UIView.animate(withDuration: 0.18, delay: 0.0, options: [.curveEaseIn, .beginFromCurrentState], animations: {
                controller.view.alpha = 0.0
                controller.view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
            }, completion: { _ in
                finish()
            })
        } else {
            finish()
        }
    }

    public func present(
        _ controller: AetherContainableController,
        on level: AetherPresentationSurfaceLevel,
        blockInteraction: Bool,
        completion: @escaping () -> Void
    ) {
        let viewController = controller.aetherViewController
        if level >= .globalOverlay {
            presentInGlobalOverlay(viewController, animated: true, completion: completion)
        } else {
            presentationContext.present(controller, on: level, blockInteraction: blockInteraction, completion: completion)
        }
    }

    public func presentInGlobalOverlay(_ controller: AetherContainableController) {
        presentInGlobalOverlay(controller.aetherViewController, animated: true)
    }

    public func presentNative(_ controller: UIViewController) {
        _rootController.present(controller, animated: true)
    }

    public func addGlobalPortalHostView(_ view: UIView) {
        guard !globalPortalHostViews.contains(where: { $0 === view }) else {
            return
        }
        globalPortalHostViews.append(view)
        _rootController.view.addSubview(view)
        view.frame = CGRect(origin: .zero, size: windowLayout.size)
        reorderTopLevelSurfaces()
    }

    public func addGlobalPortalHostView(sourceView: AetherPortalSourceView) {
        let portal = AetherPortalView(sourceView: sourceView)
        portal.isUserInteractionEnabled = false
        sourceView.setGlobalPortal(portal)
        addGlobalPortalHostView(portal)
    }

    public func removeGlobalPortalHostView(_ view: UIView) {
        globalPortalHostViews.removeAll { $0 === view }
        view.removeFromSuperview()
    }

    public func setForceBadgeHidden(_ hidden: Bool) {
        guard hidden != forceBadgeHidden else {
            return
        }
        forceBadgeHidden = hidden
    }

    public func setProximityDimHidden(_ hidden: Bool) {
        if hidden {
            proximityDimView?.removeFromSuperview()
            proximityDimView = nil
        } else if proximityDimView == nil {
            let dimView = UIView()
            dimView.backgroundColor = UIColor.black.withAlphaComponent(0.92)
            dimView.frame = CGRect(origin: .zero, size: windowLayout.size)
            dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            _rootController.view.addSubview(dimView)
            proximityDimView = dimView
            reorderTopLevelSurfaces()
        }
    }

    public func setForceInCallStatusBar(_ text: String?, transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)) {
        guard forceInCallStatusBarText != text else {
            return
        }

        forceInCallStatusBarText = text
        updateForceInCallStatusBarView(text: text, transition: transition)
        updateLayout {
            $0.updateForceInCallStatusBarText(text, transition: transition, overrideTransition: true)
        }
    }

    public func addPostUpdateToInterfaceOrientationBlock(_ block: @escaping () -> Void) {
        postUpdateToInterfaceOrientationBlocks.append(block)
    }

    /// Programmatically cancel any in-progress interactive keyboard dismissal gesture.
    public func cancelInteractiveKeyboardGestures() {
        windowPanRecognizer?.isEnabled = false
        windowPanRecognizer?.isEnabled = true

        if windowLayout.upperKeyboardInputPositionBound != nil {
            updateLayout {
                $0.updateUpperKeyboardInputPositionBound(nil, transition: .animated(duration: 0.25, curve: .spring), overrideTransition: false)
            }
        }
        keyboardGestureBeginLocation = nil
    }

    public func forEachController(_ body: (AetherContainableController) -> Void) {
        if let contentController {
            body(contentController)
        }
        for controller in topLevelOverlayControllers {
            body(controller)
        }
    }

    public func simulateKeyboardDismiss(transition: ContainedViewLayoutTransition = .animated(duration: 0.25, curve: .spring)) {
        let shouldSimulate = topLevelOverlayControllers.contains { controller in
            controller.isViewLoaded && controller.view.window !== _rootController.view.window
        }

        if shouldSimulate {
            updateLayout {
                $0.updateUpperKeyboardInputPositionBound(windowLayout.size.height, transition: transition, overrideTransition: false)
            }
        } else {
            _rootController.view.endEditing(true)
        }
    }

    /// Update the status bar style and visibility.
    public func updateStatusBar(style: UIStatusBarStyle, hidden: Bool, transition: ContainedViewLayoutTransition) {
        _rootController.updateStatusBar(style: style, hidden: hidden, transition: transition)
    }

    /// Call when the content controller's supported orientations change.
    public func invalidateSupportedOrientations() {
        setNeedsLayout()
    }

    /// Call when the content controller's deferred screen edge gestures change.
    public func invalidateDeferScreenEdgeGestures() {
        setNeedsLayout()
    }

    /// Call when the content controller's home indicator preference changes.
    public func invalidatePrefersOnScreenNavigationHidden() {
        setNeedsLayout()
    }

    /// Suppress keyboard animation for autocorrection bar height changes.
    public func doNotAnimateLikelyKeyboardAutocorrectionSwitch() {
        shouldNotAnimateLikelyKeyboardAutocorrectionSwitch = true
        DispatchQueue.main.async { [weak self] in
            self?.shouldNotAnimateLikelyKeyboardAutocorrectionSwitch = false
        }
    }

    // MARK: - Initializers

    override public init(windowScene: UIWindowScene) {
        let boundsSize = UIScreen.main.bounds.size
        let statusBarHeight = windowScene.statusBarManager?.statusBarFrame.height ?? 0.0
        let safeInsets = UIEdgeInsets.zero // will be updated in first layout

        self.windowLayout = WindowLayout(
            size: boundsSize,
            metrics: layoutMetrics(for: boundsSize),
            statusBarHeight: statusBarHeight,
            forceInCallStatusBarText: nil,
            inputHeight: nil,
            safeInsets: safeInsets,
            upperKeyboardInputPositionBound: nil,
            inVoiceOver: UIAccessibility.isVoiceOverRunning
        )

        super.init(windowScene: windowScene)

        self.rootViewController = _rootController
        _rootController.view.frame = CGRect(origin: .zero, size: bounds.size)

        self.updatingLayout = UpdatingLayout(layout: windowLayout, transition: .immediate)

        setupRootControllerCallbacks()
        setupKeyboardObservers()
        setupVoiceOverObserver()
        setupPanRecognizer()
    }

    override public init(frame: CGRect) {
        let statusBarHeight: CGFloat = 0.0
        self.windowLayout = WindowLayout(
            size: frame.size,
            metrics: layoutMetrics(for: frame.size),
            statusBarHeight: statusBarHeight,
            forceInCallStatusBarText: nil,
            inputHeight: nil,
            safeInsets: .zero,
            upperKeyboardInputPositionBound: nil,
            inVoiceOver: UIAccessibility.isVoiceOverRunning
        )

        super.init(frame: frame)

        self.rootViewController = _rootController
        _rootController.view.frame = CGRect(origin: .zero, size: bounds.size)

        self.updatingLayout = UpdatingLayout(layout: windowLayout, transition: .immediate)

        setupRootControllerCallbacks()
        setupKeyboardObservers()
        setupVoiceOverObserver()
        setupPanRecognizer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let observer = keyboardFrameChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = keyboardDidHideObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = keyboardTypeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = voiceOverObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        interactiveKeyboardDismissCleanupWorkItem?.cancel()
        keyboardTypeChangeTimer?.invalidate()
    }

    // MARK: - UIWindow Overrides

    override public var frame: CGRect {
        get { super.frame }
        set {
            let sizeUpdated = super.frame.size != newValue.size
            super.frame = newValue
            if sizeUpdated {
                handleSizeUpdate(newValue.size)
            }
        }
    }

    override public var bounds: CGRect {
        get { super.bounds }
        set {
            let sizeUpdated = super.bounds.size != newValue.size
            super.bounds = newValue
            if sizeUpdated {
                handleSizeUpdate(newValue.size)
            }
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        commitUpdatingLayout()
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let covering = coveringView, !covering.isHidden, covering.frame.contains(point) {
            return covering.hitTest(point, with: event)
        }
        for controller in topLevelOverlayControllers.reversed() where controller.isViewLoaded {
            let converted = convert(point, to: controller.view)
            if let result = controller.view.hitTest(converted, with: event) {
                return result
            }
        }
        let rootPoint = convert(point, to: _rootController.view)
        if let result = presentationContext.hitTest(point: rootPoint, in: _rootController.view, with: event) {
            return result
        }
        return super.hitTest(point, with: event)
    }

    // MARK: - Setup

    private func setupRootControllerCallbacks() {
        _rootController.transitionToSize = { [weak self] size, duration, _ in
            guard let self else { return }
            let transition: ContainedViewLayoutTransition = duration > .ulpOfOne
                ? .animated(duration: duration, curve: .easeInOut)
                : .immediate
            let safeInsets = self._rootController.view.safeAreaInsets
            self.updateLayout {
                $0.updateSize(size, metrics: layoutMetrics(for: size), safeInsets: safeInsets, transition: transition, overrideTransition: true)
            }
            let blocks = self.postUpdateToInterfaceOrientationBlocks
            self.postUpdateToInterfaceOrientationBlocks.removeAll()
            for block in blocks {
                block()
            }
        }
    }

    private func setupKeyboardObservers() {
        keyboardFrameChangeObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.handleKeyboardFrameChange(notification)
        }

        keyboardDidHideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleKeyboardDidHide()
        }

        keyboardTypeChangeObserver = NotificationCenter.default.addObserver(
            forName: UITextInputMode.currentInputModeDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleKeyboardTypeChange()
        }
    }

    private func setupVoiceOverObserver() {
        voiceOverObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateLayout { $0.updateInVoiceOver(UIAccessibility.isVoiceOverRunning) }
        }
    }

    private func setupPanRecognizer() {
        let recognizer = AetherWindowPanRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = keyboardGestureDelegate
        recognizer.isEnabled = UIDevice.current.userInterfaceIdiom == .phone
        recognizer.began = { [weak self] point in self?.panGestureBegan(location: point) }
        recognizer.moved = { [weak self] point in self?.panGestureMoved(location: point) }
        recognizer.ended = { [weak self] point, velocity in self?.panGestureEnded(location: point, velocity: velocity) }
        windowPanRecognizer = recognizer
        _rootController.view.addGestureRecognizer(recognizer)
    }

    private func reorderTopLevelSurfaces() {
        for controller in _topLevelOverlayControllers where controller.view.superview === _rootController.view {
            _rootController.view.bringSubviewToFront(controller.view)
        }
        for view in globalPortalHostViews where view.superview === _rootController.view {
            _rootController.view.bringSubviewToFront(view)
        }
        if let proximityDimView, proximityDimView.superview === _rootController.view {
            _rootController.view.bringSubviewToFront(proximityDimView)
        }
        if let statusBarView = forceInCallStatusBarView, statusBarView.superview === _rootController.view {
            _rootController.view.bringSubviewToFront(statusBarView)
        }
        if let covering = coveringView, covering.superview === _rootController.view {
            _rootController.view.bringSubviewToFront(covering)
        }
    }

    private func updateForceInCallStatusBarView(text: String?, transition: ContainedViewLayoutTransition) {
        if let text {
            let label: UILabel
            if let current = forceInCallStatusBarView {
                label = current
            } else {
                let current = UILabel()
                current.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.92)
                current.textColor = .white
                current.textAlignment = .center
                current.font = UIFont.systemFont(ofSize: 13.0, weight: .semibold)
                current.alpha = 0.0
                _rootController.view.addSubview(current)
                forceInCallStatusBarView = current
                label = current
            }
            label.text = text
            label.frame = CGRect(x: 0.0, y: 0.0, width: windowLayout.size.width, height: max(40.0, windowLayout.safeInsets.top))
            reorderTopLevelSurfaces()
            transition.updateAlpha(view: label, alpha: 1.0)
        } else if let label = forceInCallStatusBarView {
            forceInCallStatusBarView = nil
            transition.updateAlpha(view: label, alpha: 0.0, completion: { _ in
                label.removeFromSuperview()
            })
        }
    }

    private func updateOverlayController(_ controller: UIViewController, layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: controller.view, frame: CGRect(origin: .zero, size: layout.size))
        if let tabBar = controller as? AetherTabBarController {
            tabBar.containerLayoutUpdated(layout, transition: transition)
        } else if let nav = controller as? AetherNavigationController {
            nav.containerLayoutUpdated(layout, transition: transition)
        } else if let vc = controller as? AetherViewController {
            vc.containerLayoutUpdated(layout, transition: transition)
        }
    }

    // MARK: - Size Update

    private func handleSizeUpdate(_ size: CGSize) {
        let safeInsets = _rootController.view.safeAreaInsets
        updateLayout {
            $0.updateSize(size, metrics: layoutMetrics(for: size), safeInsets: safeInsets, transition: .immediate, overrideTransition: false)
        }
    }

    // MARK: - Keyboard Handling

    private func handleKeyboardFrameChange(_ notification: Notification) {
        let isTablet = windowLayout.metrics.widthClass == .regular

        var keyboardFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        if isTablet && keyboardFrame.isEmpty {
            return
        }

        // iOS 16.1+ coordinate-space-based keyboard position
        var minKeyboardY: CGFloat?
        if #available(iOS 16.1, *),
           let screen = notification.object as? UIScreen,
           let frameEnd = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            let converted = screen.coordinateSpace.convert(frameEnd, to: _rootController.view)
            minKeyboardY = converted.minY
        }

        var windowedHeightDifference: CGFloat = 0.0
        let screenHeight: CGFloat
        var isWindowed = false

        if keyboardFrame.width.isEqual(to: UIScreen.main.bounds.width) {
            let screenSize = UIScreen.main.bounds.size
            if windowLayout.size.height != screenSize.height {
                isWindowed = true
                windowedHeightDifference = (screenSize.height - windowLayout.size.height) / 2.0
            }
            if isWindowed, let _ = minKeyboardY {
                screenHeight = windowLayout.size.height
            } else {
                screenHeight = UIScreen.main.bounds.height
            }
        } else {
            if let _ = minKeyboardY {
                screenHeight = windowLayout.size.height
            } else {
                screenHeight = keyboardFrame.minX > 0.0 ? UIScreen.main.bounds.height : UIScreen.main.bounds.width
            }
        }

        var keyboardHeight: CGFloat
        if keyboardFrame.isEmpty || keyboardFrame.maxY < screenHeight {
            if isWindowed || (isTablet && screenHeight - keyboardFrame.maxY < 5.0) {
                if let minY = minKeyboardY {
                    keyboardFrame.origin.y = minY
                }
                keyboardHeight = max(0.0, screenHeight - keyboardFrame.minY)
                if isWindowed && !keyboardHeight.isZero && minKeyboardY == nil {
                    keyboardHeight = max(0.0, keyboardHeight - windowedHeightDifference)
                }
            } else {
                keyboardHeight = 0.0
            }
        } else {
            if let minY = minKeyboardY {
                keyboardFrame.origin.y = minY
            }
            keyboardHeight = max(0.0, screenHeight - keyboardFrame.minY)
            if isWindowed && !keyboardHeight.isZero && minKeyboardY == nil {
                keyboardHeight = max(0.0, keyboardHeight - windowedHeightDifference)
            }
        }

        var duration: Double = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.0
        if duration > .ulpOfOne {
            if #available(iOS 26.0, *) {
                // keep original duration on iOS 26+
            } else {
                duration = 0.5
            }
        }
        let curve: UInt = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
        let transitionCurve: ContainedViewLayoutTransitionCurve = curve == 7 ? .spring : .easeInOut

        var transition: ContainedViewLayoutTransition = .animated(duration: duration, curve: transitionCurve)

        if shouldNotAnimateLikelyKeyboardAutocorrectionSwitch, let currentInputHeight = windowLayout.inputHeight {
            if abs(currentInputHeight - keyboardHeight) <= 44.1 {
                transition = .immediate
            }
        }
        if isCompletingInteractiveKeyboardDismissal && keyboardHeight.isLessThanOrEqualTo(0.0) {
            transition = .immediate
        }

        updateLayout {
            $0.updateInputHeight(keyboardHeight.isLessThanOrEqualTo(0.0) ? nil : keyboardHeight, transition: transition, overrideTransition: false)
        }
    }

    private func handleKeyboardDidHide() {
        guard isCompletingInteractiveKeyboardDismissal || windowLayout.upperKeyboardInputPositionBound != nil else {
            return
        }
        finishInteractiveKeyboardDismissalCleanup()
    }

    private func handleKeyboardTypeChange() {
        guard let initialInputHeight = windowLayout.inputHeight,
              let firstResponder = getFirstResponderAndAccessoryHeight(_rootController.view).0 else {
            return
        }
        if firstResponder.textInputMode?.primaryLanguage != nil {
            return
        }

        keyboardTypeChangeTimer?.invalidate()
        keyboardTypeChangeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            guard let self,
                  let firstResponder = getFirstResponderAndAccessoryHeight(self._rootController.view).0 else { return }
            if firstResponder.textInputMode?.primaryLanguage != nil {
                return
            }
            // Re-read keyboard height from notification-based state — if it changed,
            // the next keyboardWillChangeFrame will handle it. This timer catches
            // cases where the keyboard type changes without a frame notification.
            let _ = initialInputHeight
        }
    }

    // MARK: - Interactive Keyboard Dismissal

    /// Override the accessory-bar height the interactive keyboard
    /// pan recognizer uses to clamp the bar's top edge to the
    /// finger. Pass `nil` to fall back to the active first
    /// responder's `inputAccessoryView.frame.height`. Useful when
    /// the chat input bar is a regular subview (avoiding UIKit's
    /// `inputAccessoryView` ghost-during-pop bug) but the gesture
    /// still needs to know how tall it is so the bar tracks the
    /// finger from its top edge instead of its bottom.
    public func setManualKeyboardGestureAccessoryHeight(_ height: CGFloat?) {
        manualKeyboardGestureAccessoryHeight = height
    }

    /// Toggle the window-level pan recognizer that drives the
    /// `upperKeyboardInputPositionBound` flow. Disable it from a
    /// chat controller that prefers the system
    /// `UIScrollView.keyboardDismissMode = .interactive` path; running
    /// both recognizers at once fights itself.
    public func setInteractiveKeyboardPanEnabled(_ enabled: Bool) {
        windowPanRecognizer?.isEnabled = enabled
    }

    private var manualKeyboardGestureAccessoryHeight: CGFloat?

    private func panGestureBegan(location: CGPoint) {
        guard windowLayout.upperKeyboardInputPositionBound == nil else { return }

        let (firstResponder, autoAccessoryHeight) = getFirstResponderAndAccessoryHeight(_rootController.view)
        // Manual override wins (chat detail with a normal subview as
        // its input bar) — falls back to the auto-detected accessory
        // height for screens that do use the UIKit accessory view.
        let resolvedAccessory: CGFloat? = manualKeyboardGestureAccessoryHeight ?? autoAccessoryHeight
        if let inputHeight = windowLayout.inputHeight, !inputHeight.isZero,
           location.y < windowLayout.size.height - inputHeight - (resolvedAccessory ?? 0.0) {
            var enableGesture = true
            if let hitView = _rootController.view.hitTest(location, with: nil) {
                if doesViewTreeDisableInteractiveKeyboardGestureRecognizer(hitView) {
                    enableGesture = false
                }
            }
            if enableGesture, let _ = firstResponder {
                keyboardGestureBeginLocation = location
                keyboardGestureAccessoryHeight = resolvedAccessory
            }
        }
    }

    private func panGestureMoved(location: CGPoint) {
        guard let beginLocation = keyboardGestureBeginLocation else { return }

        let deltaY = beginLocation.y - location.y
        if deltaY * deltaY >= 9.0 || windowLayout.upperKeyboardInputPositionBound != nil {
            updateLayout {
                $0.updateUpperKeyboardInputPositionBound(
                    location.y + (self.keyboardGestureAccessoryHeight ?? 0.0),
                    transition: .immediate,
                    overrideTransition: false
                )
            }
        }
    }

    private func panGestureEnded(location: CGPoint, velocity: CGPoint?) {
        guard keyboardGestureBeginLocation != nil else { return }
        keyboardGestureBeginLocation = nil

        let accessoryHeight = keyboardGestureAccessoryHeight ?? 0.0

        var canDismiss = false
        if let bound = windowLayout.upperKeyboardInputPositionBound, bound >= windowLayout.size.height - accessoryHeight {
            canDismiss = true
        } else if let velocity, velocity.y > 100.0 {
            canDismiss = true
        }

        if canDismiss,
           let inputHeight = windowLayout.inputHeight,
           location.y + accessoryHeight > windowLayout.size.height - inputHeight {
            let dismissDuration: CGFloat
            if #available(iOS 26.0, *) {
                dismissDuration = 0.3832
            } else {
                dismissDuration = 0.25
            }
            updateLayout {
                $0.updateUpperKeyboardInputPositionBound(
                    self.windowLayout.size.height,
                    transition: .animated(duration: dismissDuration, curve: .spring),
                    overrideTransition: false
                )
            }
        } else {
            updateLayout {
                $0.updateUpperKeyboardInputPositionBound(nil, transition: .animated(duration: 0.25, curve: .easeInOut), overrideTransition: false)
            }
        }
    }

    private func beginInteractiveKeyboardDismissalCleanup() {
        guard !isCompletingInteractiveKeyboardDismissal else {
            return
        }
        isCompletingInteractiveKeyboardDismissal = true
        interactiveKeyboardDismissCleanupWorkItem?.cancel()

        if let firstResponder = _rootController.view.findFirstResponder() {
            firstResponder.resignFirstResponder()
        } else {
            finishInteractiveKeyboardDismissalCleanup()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isCompletingInteractiveKeyboardDismissal else {
                return
            }
            if !AetherLegacyKeyboardRuntime.isKeyboardVisible() {
                self.finishInteractiveKeyboardDismissalCleanup()
            }
        }
        interactiveKeyboardDismissCleanupWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func finishInteractiveKeyboardDismissalCleanup() {
        interactiveKeyboardDismissCleanupWorkItem?.cancel()
        interactiveKeyboardDismissCleanupWorkItem = nil
        isCompletingInteractiveKeyboardDismissal = false

        AetherLegacyKeyboardRuntime.updateInteractiveKeyboardOffset(0.0, transition: .immediate)

        guard windowLayout.upperKeyboardInputPositionBound != nil || windowLayout.inputHeight != nil else {
            return
        }
        updateLayout {
            $0.updateInputHeight(nil, transition: .immediate, overrideTransition: false)
            $0.updateUpperKeyboardInputPositionBound(nil, transition: .immediate, overrideTransition: false)
        }
    }

    @objc private func handlePanGesture(_ recognizer: AetherWindowPanRecognizer) {
        // Gesture state is handled via the began/moved/ended callbacks
    }

    /// Applies the Telegram-style interactive keyboard offset through the
    /// framework-internal legacy bridge. The lookup details stay inside
    /// AetherUI; external apps only opt into the window mechanics.
    private func updateInteractiveKeyboardOffset(
        _ offset: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: (() -> Void)? = nil
    ) {
        AetherLegacyKeyboardRuntime.updateInteractiveKeyboardOffset(
            offset,
            transition: transition,
            completion: completion
        )
    }

    // MARK: - Layout Update Batching

    private func updateLayout(_ update: (inout UpdatingLayout) -> Void) {
        if updatingLayout == nil {
            var pending = UpdatingLayout(layout: windowLayout, transition: .immediate)
            update(&pending)
            if pending.layout != windowLayout {
                updatingLayout = pending
                setNeedsLayout()
            }
        } else {
            update(&updatingLayout!)
            setNeedsLayout()
        }
    }

    private func commitUpdatingLayout() {
        guard let pending = updatingLayout else { return }
        updatingLayout = nil

        guard pending.layout != windowLayout || isFirstLayout else { return }
        isFirstLayout = false

        // Resolve status bar height from the window scene
        var statusBarHeight: CGFloat? = windowScene?.statusBarManager?.statusBarFrame.height
        let isLandscape = pending.layout.size.width > pending.layout.size.height
        if statusBarHiddenInLandscape && isLandscape {
            statusBarHeight = nil
        }

        // Resolve safe area insets from the root controller's view
        var safeInsets = _rootController.view.safeAreaInsets
        if safeInsets == .zero {
            // Fallback: use the window's safe area
            safeInsets = self.safeAreaInsets
        }

        let previousInputOffset = inputHeightOffset(for: windowLayout)

        windowLayout = WindowLayout(
            size: pending.layout.size,
            metrics: layoutMetrics(for: pending.layout.size),
            statusBarHeight: statusBarHeight,
            forceInCallStatusBarText: pending.layout.forceInCallStatusBarText,
            inputHeight: pending.layout.inputHeight,
            safeInsets: safeInsets,
            upperKeyboardInputPositionBound: pending.layout.upperKeyboardInputPositionBound,
            inVoiceOver: pending.layout.inVoiceOver
        )

        let childLayout = containedLayout(from: windowLayout)
        let childLayoutUpdated = updatedContainerLayout != childLayout
        updatedContainerLayout = childLayout

        let runtimeLayout = AetherWindowLayout(
            size: windowLayout.size,
            safeAreaInsets: windowLayout.safeInsets,
            statusBarHeight: windowLayout.statusBarHeight,
            keyboardHeight: childLayout.inputHeight ?? 0.0,
            orientation: _rootController.currentInterfaceOrientation(),
            horizontalSizeClass: childLayout.metrics.widthClass == .regular ? .regular : .compact,
            verticalSizeClass: windowLayout.size.width > windowLayout.size.height ? .compact : .regular,
            isVoiceOverRunning: windowLayout.inVoiceOver,
            transition: AetherWindowLayout.Transition(
                reason: .manual,
                duration: pending.transition.duration,
                curve: .easeInOut,
                isInteractive: childLayout.inputHeightIsInteractivellyChanging
            )
        )
        presentationContext.updateLayout(runtimeLayout, transition: pending.transition)

        if childLayoutUpdated {
            if let controller = contentController {
                pending.transition.updateFrame(view: controller.view, frame: CGRect(origin: .zero, size: windowLayout.size))
                updateContentController(layout: childLayout, transition: pending.transition)
            }
            for controller in topLevelOverlayControllers {
                updateOverlayController(controller, layout: childLayout, transition: pending.transition)
            }
        }

        // Commit the interactive keyboard offset to both Aether layout and the
        // native keyboard surface when UIKit exposes the legacy host view.
        let updatedInputOffset = inputHeightOffset(for: windowLayout)
        let shouldDeferKeyboardOffsetReset = isCompletingInteractiveKeyboardDismissal
            && updatedInputOffset.isZero
            && pending.layout.inputHeight == nil
        if !previousInputOffset.isEqual(to: updatedInputOffset), !shouldDeferKeyboardOffsetReset {
            let isHiding = pending.transition.isAnimated
                && pending.layout.upperKeyboardInputPositionBound == pending.layout.size.height
            updateInteractiveKeyboardOffset(
                updatedInputOffset,
                transition: pending.transition
            ) { [weak self] in
                guard let self, isHiding else { return }
                self.beginInteractiveKeyboardDismissalCleanup()
            }
        }

        // Update covering view
        for view in globalPortalHostViews {
            view.frame = CGRect(origin: .zero, size: windowLayout.size)
        }
        if let proximityDimView {
            proximityDimView.frame = CGRect(origin: .zero, size: windowLayout.size)
        }
        if let statusBarView = forceInCallStatusBarView {
            statusBarView.frame = CGRect(x: 0.0, y: 0.0, width: windowLayout.size.width, height: max(40.0, windowLayout.safeInsets.top))
        }
        if let covering = coveringView {
            covering.frame = CGRect(origin: .zero, size: windowLayout.size)
            covering.updateLayout(windowLayout.size)
        }
        reorderTopLevelSurfaces()
    }

    // MARK: - Content Controller Layout Dispatch

    private func updateContentController(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        guard let controller = contentController else { return }
        if let tabBar = controller as? AetherTabBarController {
            tabBar.containerLayoutUpdated(layout, transition: transition)
        } else if let nav = controller as? AetherNavigationController {
            nav.containerLayoutUpdated(layout, transition: transition)
        } else if let vc = controller as? AetherViewController {
            vc.containerLayoutUpdated(layout, transition: transition)
        }
    }

    // MARK: - Debug Tap

    @objc private func handleDebugTap(_ recognizer: UITapGestureRecognizer) {
        guard case .ended = recognizer.state else { return }
        let timestamp = CACurrentMediaTime()
        if debugTapCounter.0 < timestamp - 0.4 {
            debugTapCounter = (timestamp, 0)
        }
        if debugTapCounter.0 >= timestamp - 0.4 {
            debugTapCounter = (timestamp, debugTapCounter.1 + 1)
        }
        if debugTapCounter.1 >= 10 {
            debugTapCounter.1 = 0
            debugAction?()
        }
    }
}

// MARK: - UIView First Responder Helper

public extension UIView {
    func findFirstResponder() -> UIView? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let result = subview.findFirstResponder() {
                return result
            }
        }
        return nil
    }
}

public typealias AetherWindow = AetherNativeWindow
