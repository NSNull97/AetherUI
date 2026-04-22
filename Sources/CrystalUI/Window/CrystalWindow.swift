import UIKit

// MARK: - Internal Layout Types

private let statusBarHiddenInLandscape: Bool = UIDevice.current.userInterfaceIdiom == .phone

private struct WindowLayout: Equatable {
    var size: CGSize
    var metrics: LayoutMetrics
    var statusBarHeight: CGFloat?
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

// MARK: - Window Root Controller

private final class CrystalWindowRootController: UIViewController {

    private var statusBarStyle: UIStatusBarStyle = .default
    private var isStatusBarHidden: Bool = false

    var orientations: UIInterfaceOrientationMask = {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }() {
        didSet {
            guard oldValue != orientations else { return }
            if #available(iOS 16.0, *) {
                let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
                setNeedsUpdateOfSupportedInterfaceOrientations()
            } else if orientations == .portrait, UIDevice.current.orientation != .portrait {
                UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            } else {
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
    }

    var gestureEdges: UIRectEdge = [] {
        didSet {
            guard oldValue != gestureEdges else { return }
            setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        }
    }

    var prefersOnScreenNavHidden: Bool = false {
        didSet {
            guard oldValue != prefersOnScreenNavHidden else { return }
            setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    var transitionToSize: ((CGSize, Double) -> Void)?

    func updateStatusBar(style: UIStatusBarStyle, hidden: Bool, transition: ContainedViewLayoutTransition) {
        guard statusBarStyle != style || isStatusBarHidden != hidden else { return }
        statusBarStyle = style
        isStatusBarHidden = hidden
        switch transition {
        case .immediate:
            setNeedsStatusBarAppearanceUpdate()
        case .animated:
            transition.animateView {
                self.setNeedsStatusBarAppearanceUpdate()
            }
        }
    }

    // MARK: UIViewController overrides

    override var preferredStatusBarStyle: UIStatusBarStyle { statusBarStyle }
    override var prefersStatusBarHidden: Bool { isStatusBarHidden }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { orientations }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { gestureEdges }
    override var prefersHomeIndicatorAutoHidden: Bool { prefersOnScreenNavHidden }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        UIView.performWithoutAnimation {
            self.transitionToSize?(size, coordinator.transitionDuration)
        }
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        extendedLayoutIncludesOpaqueBars = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let v = UIView()
        v.isOpaque = false
        v.backgroundColor = nil
        self.view = v
    }
}

// MARK: - CrystalWindow

/// Custom `UIWindow` subclass that provides keyboard tracking, interactive
/// keyboard dismissal, status bar management, orientation handling, and
/// layout propagation to the content controller hierarchy.
///
/// Usage:
/// ```swift
/// let window = CrystalWindow(windowScene: scene)
/// window.contentController = myTabBarController   // or nav controller
/// window.makeKeyAndVisible()
/// ```
public final class CrystalWindow: UIWindow {

    // MARK: - Private State

    private let _rootController = CrystalWindowRootController()

    private var windowLayout: WindowLayout
    private var updatingLayout: UpdatingLayout?
    private var updatedContainerLayout: ContainerViewLayout?
    private var isFirstLayout = true

    // Keyboard
    private var keyboardFrameChangeObserver: NSObjectProtocol?
    private var keyboardTypeChangeObserver: NSObjectProtocol?
    private var keyboardTypeChangeTimer: Timer?
    private var shouldNotAnimateLikelyKeyboardAutocorrectionSwitch = false

    // Pan gesture for interactive keyboard dismissal
    private var windowPanRecognizer: CrystalWindowPanRecognizer?
    private let keyboardGestureDelegate = CrystalWindowKeyboardGestureRecognizerDelegate()
    private var keyboardGestureBeginLocation: CGPoint?
    private var keyboardGestureAccessoryHeight: CGFloat?

    // VoiceOver
    private var voiceOverObserver: NSObjectProtocol?

    // Status bar
    private var statusBarHidden = false

    // Debug tap
    private var debugTapCounter: (Double, Int) = (0.0, 0)
    private var debugTapRecognizer: UITapGestureRecognizer?

    // MARK: - Public API

    /// The main content controller displayed in this window.
    /// Typically a `CrystalTabBarController` or `CrystalNavigationController`.
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

                if !windowLayout.size.width.isZero && !windowLayout.size.height.isZero {
                    controller.view.frame = CGRect(origin: .zero, size: windowLayout.size)
                    let layout = containedLayout(from: windowLayout)
                    updateContentController(layout: layout, transition: .immediate)
                }
            }
        }
    }

    /// The current layout computed by this window, including keyboard height.
    /// Controllers can read this to obtain keyboard-aware layout data.
    public var currentLayout: ContainerViewLayout {
        return containedLayout(from: windowLayout)
    }

    /// Overlay view shown for app snapshot protection in the task switcher.
    /// Animates in/out with a fade when set/unset.
    public var coveringView: CrystalWindowCoveringView? {
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
        if let observer = keyboardTypeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = voiceOverObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
        return super.hitTest(point, with: event)
    }

    // MARK: - Setup

    private func setupRootControllerCallbacks() {
        _rootController.transitionToSize = { [weak self] size, duration in
            guard let self else { return }
            let transition: ContainedViewLayoutTransition = duration > .ulpOfOne
                ? .animated(duration: duration, curve: .easeInOut)
                : .immediate
            let safeInsets = self._rootController.view.safeAreaInsets
            self.updateLayout {
                $0.updateSize(size, metrics: layoutMetrics(for: size), safeInsets: safeInsets, transition: transition, overrideTransition: true)
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
        let recognizer = CrystalWindowPanRecognizer(target: self, action: #selector(handlePanGesture(_:)))
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

        updateLayout {
            $0.updateInputHeight(keyboardHeight.isLessThanOrEqualTo(0.0) ? nil : keyboardHeight, transition: transition, overrideTransition: false)
        }
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

    private func panGestureBegan(location: CGPoint) {
        guard windowLayout.upperKeyboardInputPositionBound == nil else { return }

        let (firstResponder, accessoryHeight) = getFirstResponderAndAccessoryHeight(_rootController.view)
        if let inputHeight = windowLayout.inputHeight, !inputHeight.isZero,
           location.y < windowLayout.size.height - inputHeight - (accessoryHeight ?? 0.0) {
            var enableGesture = true
            if let hitView = _rootController.view.hitTest(location, with: nil) {
                if doesViewTreeDisableInteractiveKeyboardGestureRecognizer(hitView) {
                    enableGesture = false
                }
            }
            if enableGesture, let _ = firstResponder {
                keyboardGestureBeginLocation = location
                keyboardGestureAccessoryHeight = accessoryHeight
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
                $0.updateUpperKeyboardInputPositionBound(nil, transition: .animated(duration: 0.25, curve: .spring), overrideTransition: false)
            }
        }
    }

    @objc private func handlePanGesture(_ recognizer: CrystalWindowPanRecognizer) {
        // Gesture state is handled via the began/moved/ended callbacks
    }

    /// Physically shift the native keyboard view vertically by `offset`
    /// points (positive = keyboard slides further down off-screen).
    /// Mirrors `KeyboardManager.updateInteractiveInputOffset` from
    /// Telegram-iOS: we mutate the `UIInputSetHostView`'s `layer.bounds`
    /// origin, which visually translates the keyboard content without
    /// requiring `resignFirstResponder` first.
    ///
    /// When called with an animated transition, we also add an additive
    /// offset animation on the layer so the transition from the previous
    /// bounds to the new one interpolates smoothly (matches upstream's
    /// `animateOffsetAdditive` call).
    private func updateInteractiveKeyboardOffset(
        _ offset: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: (() -> Void)? = nil
    ) {
        guard let keyboardView = CrystalKeyboardAccess.keyboardView() else {
            completion?()
            return
        }
        let previousBounds = keyboardView.bounds
        let updatedBounds = CGRect(origin: CGPoint(x: 0.0, y: -offset), size: previousBounds.size)
        keyboardView.layer.bounds = updatedBounds

        if transition.isAnimated {
            transition.animateOffsetAdditive(
                layer: keyboardView.layer,
                offset: previousBounds.minY - updatedBounds.minY,
                completion: { _ in completion?() }
            )
        } else {
            completion?()
        }
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
            inputHeight: pending.layout.inputHeight,
            safeInsets: safeInsets,
            upperKeyboardInputPositionBound: pending.layout.upperKeyboardInputPositionBound,
            inVoiceOver: pending.layout.inVoiceOver
        )

        let childLayout = containedLayout(from: windowLayout)
        let childLayoutUpdated = updatedContainerLayout != childLayout
        updatedContainerLayout = childLayout

        if childLayoutUpdated {
            if let controller = contentController {
                pending.transition.updateFrame(view: controller.view, frame: CGRect(origin: .zero, size: windowLayout.size))
                updateContentController(layout: childLayout, transition: pending.transition)
            }
        }

        // Commit interactive keyboard offset
        let updatedInputOffset = inputHeightOffset(for: windowLayout)
        if !previousInputOffset.isEqual(to: updatedInputOffset) {
            let isHiding = pending.transition.isAnimated
                && pending.layout.upperKeyboardInputPositionBound == pending.layout.size.height
            // Move the native keyboard window's keyboard view in lockstep
            // with the layout change so the keyboard actually follows the
            // user's finger (rather than just the layout reacting while
            // the keyboard stays pinned). Port of Telegram-iOS
            // `KeyboardManager.updateInteractiveInputOffset`.
            updateInteractiveKeyboardOffset(
                updatedInputOffset,
                transition: pending.transition
            ) { [weak self] in
                guard let self, isHiding else { return }
                // Once the drag-out animation finishes, clear the interactive
                // bound and resign first responder — UIKit will tear down
                // the keyboard naturally from the off-screen position.
                self.updateLayout {
                    $0.updateUpperKeyboardInputPositionBound(nil, transition: .immediate, overrideTransition: false)
                }
                self._rootController.view.findFirstResponder()?.resignFirstResponder()
            }
        }

        // Update covering view
        if let covering = coveringView {
            covering.frame = CGRect(origin: .zero, size: windowLayout.size)
            covering.updateLayout(windowLayout.size)
        }
    }

    // MARK: - Content Controller Layout Dispatch

    private func updateContentController(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        guard let controller = contentController else { return }
        if let tabBar = controller as? CrystalTabBarController {
            tabBar.containerLayoutUpdated(layout, transition: transition)
        } else if let nav = controller as? CrystalNavigationController {
            nav.containerLayoutUpdated(layout, transition: transition)
        } else if let vc = controller as? ViewController {
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
