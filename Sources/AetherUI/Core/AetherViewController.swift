import UIKit
import AetherUIBridging

/// Base ViewController with glass-style navigation support.
/// Pure UIKit replacement for Display.ViewController.
@objc open class AetherViewController: UIViewController {
    public struct SupportedOrientations: Equatable {
        public var regularSize: UIInterfaceOrientationMask
        public var compactSize: UIInterfaceOrientationMask

        public init(regularSize: UIInterfaceOrientationMask = .all, compactSize: UIInterfaceOrientationMask = .allButUpsideDown) {
            self.regularSize = regularSize
            self.compactSize = compactSize
        }

        public func intersection(_ other: SupportedOrientations) -> SupportedOrientations {
            return SupportedOrientations(
                regularSize: self.regularSize.intersection(other.regularSize),
                compactSize: self.compactSize.intersection(other.compactSize)
            )
        }
    }

    public enum NavigationPresentation {
        case `default`
        case master
        case modal
        case flatModal
        case standaloneModal
        case standaloneFlatModal
        case modalInLargeLayout
        case modalInCompactLayout
    }

    public enum TabBarItemContextActionType {
        case none
        case always
        case whenActive
    }

    public struct NavigationLayout {
        public var navigationFrame: CGRect
        public var defaultContentHeight: CGFloat

        public init(navigationFrame: CGRect, defaultContentHeight: CGFloat) {
            self.navigationFrame = navigationFrame
            self.defaultContentHeight = defaultContentHeight
        }
    }

    public struct TabBarSearchState: Equatable {
        public var isActive: Bool

        public init(isActive: Bool) {
            self.isActive = isActive
        }
    }

    // MARK: - Layout

    private var validLayout: ContainerViewLayout?
    public var currentlyAppliedLayout: ContainerViewLayout? {
        return self.validLayout
    }

    // MARK: - Orientation

    public final var supportedOrientations = AetherViewController.SupportedOrientations()
    public final var lockedOrientation: UIInterfaceOrientationMask?
    public final var lockOrientation: Bool = false

    // MARK: - Presentation

    open var previousItem: NavigationPreviousAction?
    open var navigationPresentation: AetherViewController.NavigationPresentation = .default
    open var _hasGlassStyle: Bool = false
    public private(set) lazy var navigationBarItem: NavigationBarItem = {
        let item = NavigationBarItem(navigationItem: self.navigationItem)
        item.searchBarControllerChanged = { [weak self] _, newValue in
            guard let self, self.searchController !== newValue else { return }
            self.searchController = newValue
        }
        item.topBarAccessoryChanged = { [weak self] _, newValue, transition in
            self?.applyNavigationBarItemTopBarAccessory(newValue, transition: transition)
        }
        item.chromeContentDidChange = { [weak self] in
            self?.navigationBarItemContentDidChange()
        }
        return item
    }()
    public let pageItem = AetherPageItem()

    // MARK: - Tab Bar

    public var tabBarItemDebugTapAction: (() -> Void)?
    open var tabBarItemContextActionType: TabBarItemContextActionType = .none
    public private(set) var tabBarSearchState: TabBarSearchState?
    public var tabBarSearchStateUpdated: ((ContainedViewLayoutTransition) -> Void)?

    // MARK: - Search

    /// Search controller integrated with the navigation bar.
    ///
    /// When set, a glass search pill appears in the nav bar expansion area
    /// (between title and content like filter chips). Tapping the pill
    /// activates search: title/buttons fade, pill becomes a text field,
    /// glass close button appears, keyboard shows.
    ///
    /// Mirrors the `UINavigationItem.searchController` pattern:
    /// ```swift
    /// let search = AetherSearchController()
    /// search.placeholder = "Search"
    /// search.delegate = self
    /// searchController = search
    /// ```
    ///
    /// Set to `nil` to remove the search pill from the nav bar.
    public var searchController: AetherSearchController? {
        didSet {
            if navigationBarItem.searchBarController !== searchController {
                navigationBarItem.searchBarController = searchController
            }
            cachedStackedTopBarAccessory = nil
            oldValue?.uninstall()
            if let sc = searchController {
                sc.searchBar.placeholder = sc.placeholder
                sc.searchBar.isDark = traitCollection.userInterfaceStyle == .dark
                sc.install(on: self)
                rebuildTopBarAccessory()
            } else {
                rebuildTopBarAccessory()
            }
        }
    }

    /// Rebuilds the nav bar content view to include the search pill
    /// (if `searchController` is set) stacked above `topBarAccessory`.
    internal func rebuildTopBarAccessory() {
        if navigationBarView != nil, displayNavigationBar {
            navigationBarView?.setContentView(effectiveTopBarAccessory, animated: false)
        }
        notifyTopBarAccessoryDidChange(transition: .immediate)
    }

    internal var effectiveTopBarAccessory: NavigationBarContentView? {
        guard let sc = searchController, sc.placement == .navBar else {
            cachedStackedTopBarAccessory = nil
            return _rawTopBarAccessory
        }
        if let cachedStackedTopBarAccessory {
            let expectedCount = _rawTopBarAccessory == nil ? 1 : 2
            if cachedStackedTopBarAccessory.views.count == expectedCount,
               cachedStackedTopBarAccessory.views.first === sc.searchBar,
               (expectedCount == 1 || cachedStackedTopBarAccessory.views.last === _rawTopBarAccessory) {
                return cachedStackedTopBarAccessory
            }
        }
        var views: [NavigationBarContentView] = [sc.searchBar]
        if let raw = _rawTopBarAccessory {
            views.append(raw)
        }
        let stacked = AetherStackedBarContent(views: views)
        cachedStackedTopBarAccessory = stacked
        return stacked
    }

    /// The raw content set by the consumer (filters, chips, etc.).
    /// Stored separately from the search pill so `rebuildTopBarAccessory`
    /// can stack them.
    internal var _rawTopBarAccessory: NavigationBarContentView?
    private var cachedStackedTopBarAccessory: AetherStackedBarContent?

    // MARK: - Navigation Bar

    public var navigationBarView: NavigationBarView?
    internal var explicitNavigationBarPresentationData: NavigationBarPresentationData?
    public var displayNavigationBar: Bool = true
    public internal(set) var navigationBarIsExternallyHosted: Bool = false
    public internal(set) var externalNavigationBarHeight: CGFloat?

    // MARK: - Floating Toolbar

    /// Bottom floating "Liquid Glass" toolbar — Safari/Mail/Messages style.
    ///
    /// Assigning a toolbar adds it to `view`, anchors it to the bottom
    /// of the screen just above any ancestor chrome (tab bar) and the
    /// device safe area (home indicator), and propagates the toolbar's
    /// height to `additionalSafeAreaInsets.bottom` so scroll content
    /// lays out above it without the caller having to do anything.
    ///
    /// Set to `nil` to remove. The previous toolbar is cleaned up.
    public var floatingToolbar: AetherFloatingToolbarView? {
        didSet {
            guard floatingToolbar !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if isViewLoaded, let toolbar = floatingToolbar {
                view.addSubview(toolbar)
            }
            if isViewLoaded, let layout = currentlyAppliedLayout {
                containerLayoutUpdated(layout, transition: .immediate)
            }
        }
    }

    /// Natural vertical budget a floating toolbar needs (pill height +
    /// top/bottom breathing). Overridable if a subclass uses a taller
    /// pill. Returns `0` when no toolbar is assigned.
    open var floatingToolbarHeight: CGFloat {
        return floatingToolbar != nil ? AetherFloatingToolbarView.defaultHeight : 0
    }

    // MARK: - Input Bar Accessory

    private var _inputBarAccessoryReservedHeight: CGFloat?
    public private(set) var inputBarAccessoryFrame: CGRect = .zero

    /// Bottom input accessory hosted by the controller itself.
    ///
    /// Use this for chat-style input bars that should sit above the keyboard
    /// but remain a regular view in this controller hierarchy. The view is
    /// laid out at the bottom, above the keyboard when it is visible and
    /// above ancestor bottom chrome / the home indicator otherwise.
    public var inputBarAccessoryView: UIView? {
        didSet {
            guard inputBarAccessoryView !== oldValue else { return }
            oldValue?.input_setInputAccessoryHeightProvider(nil)
            oldValue?.removeFromSuperview()

            if let accessory = inputBarAccessoryView {
                installInputBarAccessoryHeightProvider(on: accessory)
                if isViewLoaded {
                    view.addSubview(accessory)
                    view.bringSubviewToFront(accessory)
                }
            }

            syncInputBarAccessoryHeightWithWindow()
            if isViewLoaded, let layout = currentlyAppliedLayout {
                containerLayoutUpdated(layout, transition: .immediate)
            }
        }
    }

    /// Default height used when the accessory has no measured frame or
    /// intrinsic Auto Layout height yet. Subclasses can override this for
    /// custom compose bars.
    open var inputBarAccessoryDefaultHeight: CGFloat {
        return 49.0
    }

    /// Bottom gap for `inputBarAccessoryView` when it is not attached to
    /// the keyboard or an ancestor tab-bar chrome.
    open var inputBarAccessoryBottomInset: CGFloat {
        return 28.0
    }

    open var inputBarAccessoryUsesBottomEdgeEffect: Bool {
        return false
    }

    open var primaryScrollViewForChrome: UIScrollView? {
        return nil
    }

    open func resolvedNavigationBarAppearance(
        placement: AetherBarPlacement = .navigation
    ) -> AetherNavigationBarResolvedAppearance {
        let appearance = AetherAppearance.runtimeCurrent
        let resolutionContext = AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .navigation,
            placement: placement,
            traitCollection: traitCollection
        )
        let overrideContext = AetherAppearanceOverrideContext(
            appearance: appearance,
            surface: .navigation,
            placement: placement,
            traitCollection: traitCollection,
            viewController: self
        )
        let override = (self as? AetherControllerAppearanceProviding)?
            .aetherAppearanceOverride(for: overrideContext)?
            .navigationBar
        return AetherNavigationBarAppearanceResolver.resolve(context: resolutionContext, override: override)
    }

    open func resolvedSearchAppearance(
        surface: AetherAppearanceSurface = .search,
        placement: AetherBarPlacement = .top
    ) -> AetherSearchResolvedAppearance {
        let appearance = AetherAppearance.runtimeCurrent
        let resolutionContext = AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: surface,
            placement: placement,
            traitCollection: traitCollection
        )
        let overrideContext = AetherAppearanceOverrideContext(
            appearance: appearance,
            surface: surface,
            placement: placement,
            traitCollection: traitCollection,
            viewController: self
        )
        let override = (self as? AetherControllerAppearanceProviding)?
            .aetherAppearanceOverride(for: overrideContext)?
            .search
        return AetherSearchAppearanceResolver.resolve(context: resolutionContext, override: override)
    }

    open func resolvedInputBarAppearance() -> AetherInputBarResolvedAppearance {
        let appearance = AetherAppearance.runtimeCurrent
        let resolutionContext = AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .inputBar,
            placement: .inputAccessory,
            traitCollection: traitCollection
        )
        let overrideContext = AetherAppearanceOverrideContext(
            appearance: appearance,
            surface: .inputBar,
            placement: .inputAccessory,
            traitCollection: traitCollection,
            viewController: self
        )
        let override = (self as? AetherControllerAppearanceProviding)?
            .aetherAppearanceOverride(for: overrideContext)?
            .inputBar
        return AetherInputBarAppearanceResolver.resolve(context: resolutionContext, override: override)
    }

    /// Height reserved for `inputBarAccessoryView` in safe-area propagation.
    ///
    /// Assigning this pins the reserved height. Use
    /// `setInputBarAccessoryReservedHeight(_:transition:)` with `nil` to
    /// return to automatic measurement.
    open var inputBarAccessoryReservedHeight: CGFloat {
        get {
            if let reservedHeight = _inputBarAccessoryReservedHeight {
                return reservedHeight
            }
            let fallbackWidth = isViewLoaded ? view.bounds.width : 0.0
            return resolvedInputBarAccessoryHeight(width: currentlyAppliedLayout?.size.width ?? fallbackWidth)
        }
        set {
            setInputBarAccessoryReservedHeight(newValue, transition: .immediate)
        }
    }

    public func setInputBarAccessoryReservedHeight(_ height: CGFloat?, transition: ContainedViewLayoutTransition = .immediate) {
        let clampedHeight = height.map { max(0.0, $0) }
        guard _inputBarAccessoryReservedHeight != clampedHeight else {
            return
        }
        _inputBarAccessoryReservedHeight = clampedHeight
        syncInputBarAccessoryHeightWithWindow()
        if isViewLoaded, let layout = currentlyAppliedLayout {
            containerLayoutUpdated(layout, transition: transition)
        }
    }

    public func invalidateInputBarAccessoryLayout(transition: ContainedViewLayoutTransition = .immediate) {
        syncInputBarAccessoryHeightWithWindow()
        guard isViewLoaded, let layout = currentlyAppliedLayout else {
            return
        }
        containerLayoutUpdated(layout, transition: transition)
    }

    /// Top-bar accessory view installed below the nav bar title row in
    /// `.expansion` mode (filter chips, segmented controls, etc.).
    ///
    /// When a `searchController` is set, the search pill is automatically
    /// stacked above this content. Set this to filters/chips — don't include
    /// the search bar manually.
    ///
    /// Mirrors iOS 26's `UINavigationItem.bottomPalette` pattern on the
    /// top chrome side. See also `bottomBarAccessory` for the companion
    /// accessory that sits above the tab bar.
    public var topBarAccessory: NavigationBarContentView? {
        get { _rawTopBarAccessory }
        set {
            guard _rawTopBarAccessory !== newValue else { return }
            if navigationBarItem.topBarAccessory !== newValue {
                navigationBarItem.setTopBarAccessory(newValue, transition: .immediate)
                return
            }
            applyNavigationBarItemTopBarAccessory(newValue, transition: .immediate)
        }
    }

    /// Installs or removes the top-bar accessory with the same public
    /// semantics as assigning ``topBarAccessory``. When `animated` is true,
    /// AetherUI performs the framework-private blur crossfade inside the
    /// navigation bar; callers only provide the content view.
    public func setTopBarAccessory(_ accessory: NavigationBarContentView?, animated: Bool) {
        guard _rawTopBarAccessory !== accessory else { return }
        if navigationBarItem.topBarAccessory !== accessory {
            navigationBarItem.setTopBarAccessory(accessory, animated: animated)
            return
        }
        let transition: ContainedViewLayoutTransition = animated
            ? .animated(duration: 0.32, curve: .easeInOut)
            : .immediate
        applyNavigationBarItemTopBarAccessory(accessory, transition: transition)
    }

    private func applyNavigationBarItemTopBarAccessory(_ accessory: NavigationBarContentView?, transition: ContainedViewLayoutTransition) {
        guard _rawTopBarAccessory !== accessory else { return }
        let animated = transition.isAnimated
        let newValue = accessory
        _rawTopBarAccessory = newValue
        cachedStackedTopBarAccessory = nil
        if searchController != nil {
            rebuildTopBarAccessory()
        } else {
            if navigationBarView != nil, displayNavigationBar {
                navigationBarView?.setContentView(newValue, animated: animated)
            } else {
                navigationBarView?.setContentView(nil, animated: false)
            }
            notifyTopBarAccessoryDidChange(transition: transition)
        }
    }

    /// Internal hook so `AetherTabBarController` can re-sync when a child's
    /// `topBarAccessory` changes.
    public var topBarAccessoryDidChange: (() -> Void)?
    internal var topBarAccessoryTransitionDidChange: ((ContainedViewLayoutTransition) -> Void)?

    private func notifyTopBarAccessoryDidChange(transition: ContainedViewLayoutTransition) {
        topBarAccessoryTransitionDidChange?(transition)
        topBarAccessoryDidChange?()
    }

    public var navigationBarRequiresEntireLayoutUpdate: Bool {
        return true
    }

    // MARK: - Status Bar

    public var statusBarStyle: UIStatusBarStyle = .default {
        didSet {
            if statusBarStyle != oldValue {
                setNeedsStatusBarAppearanceUpdate()
            }
        }
    }

    override open var preferredStatusBarStyle: UIStatusBarStyle {
        return statusBarStyle
    }

    // MARK: - Readiness

    private var _ready: Bool = true
    public var isReady: Bool {
        return _ready
    }
    public var readyChanged: ((Bool) -> Void)?

    public func setReady(_ ready: Bool) {
        if _ready != ready {
            _ready = ready
            readyChanged?(ready)
        }
    }

    // MARK: - Scroll to Top

    private var scrollToTopView: ScrollToTopView?
    public var scrollToTop: (() -> Void)? {
        didSet {
            if isViewLoaded {
                updateScrollToTopView()
            }
        }
    }
    public var scrollToTopWithTabBar: (() -> Void)?
    public var longTapWithTabBar: (() -> Void)?

    // MARK: - Focus

    public internal(set) var isInFocus: Bool = false {
        didSet {
            if isInFocus != oldValue {
                inFocusUpdated(isInFocus: isInFocus)
            }
        }
    }

    open func inFocusUpdated(isInFocus: Bool) {}

    // MARK: - Navigation Attempt

    public var attemptNavigation: (@escaping () -> Void) -> Bool = { navigate in
        navigate()
        return true
    }

    // MARK: - Interactive Edge

    open var interactiveNavivationGestureEdgeWidth: InteractiveTransitionGestureRecognizerEdgeWidth? {
        return nil
    }

    // MARK: - Additional Heights

    open var additionalNavigationBarHeight: CGFloat {
        return 0.0
    }

    open var overlayWantsToBeBelowKeyboard: Bool {
        return false
    }

    public var additionalSideInsets: UIEdgeInsets = .zero

    // MARK: - Initialization

    public init(navigationBarPresentationData: NavigationBarPresentationData? = nil) {
        super.init(nibName: nil, bundle: nil)
        explicitNavigationBarPresentationData = navigationBarPresentationData

        if let data = navigationBarPresentationData {
            let bar = NavigationBarImpl(presentationData: data)
            self.navigationBarView = bar
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public final func updateCurrentContainerLayout(_ layout: ContainerViewLayout) {
        self.validLayout = layout
    }

    // MARK: - Layout

    open func navigationLayout(layout: ContainerViewLayout) -> NavigationLayout {
        // The nav bar visually starts at y=0 and must absorb the system
        // chrome above its content (status bar, notch, Dynamic Island).
        // Prefer whichever is bigger: the actual status-bar height OR the
        // top safe-area inset. On devices with a cutout the two usually
        // agree, but when the app hides the status bar in fullscreen mode
        // `statusBarHeight` drops to 0 while `safeInsets.top` still
        // reports the cutout reservation — using just `statusBarHeight`
        // would let title/buttons slide under the island.
        let topOffset: CGFloat = max(layout.statusBarHeight ?? 0.0, layout.safeInsets.top)
        let defaultNavigationBarHeight: CGFloat = 60.0

        if navigationBarIsExternallyHosted, let externalNavigationBarHeight {
            var navigationBarFrame = CGRect(
                origin: .zero,
                size: CGSize(width: layout.size.width, height: externalNavigationBarHeight)
            )
            if !displayNavigationBar {
                navigationBarFrame.origin.y = -navigationBarFrame.size.height
            }
            return NavigationLayout(navigationFrame: navigationBarFrame, defaultContentHeight: defaultNavigationBarHeight)
        }

        let navBarContentHeight = navigationBarView?.contentHeight(defaultHeight: defaultNavigationBarHeight) ?? defaultNavigationBarHeight
        let navigationBarHeight: CGFloat = topOffset + navBarContentHeight + additionalNavigationBarHeight

        var navigationBarFrame = CGRect(origin: .zero, size: CGSize(width: layout.size.width, height: navigationBarHeight))

        if !displayNavigationBar {
            navigationBarFrame.origin.y = -navigationBarFrame.size.height
        }

        return NavigationLayout(navigationFrame: navigationBarFrame, defaultContentHeight: defaultNavigationBarHeight)
    }

    open var cleanNavigationHeight: CGFloat {
        if navigationBarIsExternallyHosted, let externalNavigationBarHeight {
            return displayNavigationBar ? externalNavigationBarHeight : 0.0
        }
        if let bar = navigationBarView {
            return bar.frame.maxY
        }
        return 0.0
    }

    open func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let previousLayout = currentlyAppliedLayout
        self.updateCurrentContainerLayout(layout)
        let navigationChromeTransition: ContainedViewLayoutTransition = previousLayout.map { layout.differsOnlyInKeyboardInputOrBottomAdditionalInset(from: $0) } == true
            ? .immediate
            : transition

        let navLayout = navigationLayout(layout: layout)

        // Content-unavailable overlay: full-bounds, kept above content but
        // below nav bar / floating toolbar (those re-bring themselves to
        // front below).
        if let unavailableView = _contentUnavailableView {
            transition.updateFrame(view: unavailableView, frame: view.bounds)
            view.bringSubviewToFront(unavailableView)
        }

        if let bar = navigationBarView, !navigationBarIsExternallyHosted {
            // Snap the nav-bar frame synchronously rather than animating
            // it. When the bar resized over a `.animated` transition the
            // bar's `frame.maxY` was halfway between old and new for the
            // duration, but `additionalSafeAreaInsets.top` (set further
            // down) sits at the FINAL value the moment the layout pass
            // runs — so the content under the bar lands at the final
            // position immediately and reveals a strip of unchaperoned
            // background between the still-animating bar's bottom edge
            // and the content's top. Snapping the bar frame to the final
            // value puts both edges in lockstep. Internal subviews
            // (buttons, content view, edge effect) still animate via
            // the passed `transition` inside `bar.updateLayout`.
            bar.frame = navLayout.navigationFrame
            bar.updateLayout(
                size: navLayout.navigationFrame.size,
                defaultHeight: navLayout.defaultContentHeight,
                additionalTopHeight: 0.0,
                additionalContentHeight: 0.0,
                additionalBackgroundHeight: 0.0,
                leftInset: layout.safeInsets.left,
                rightInset: layout.safeInsets.right,
                appearsHidden: !displayNavigationBar,
                isLandscape: layout.size.width > layout.size.height,
                transition: navigationChromeTransition
            )
            view.bringSubviewToFront(bar)
        }

        // Floating toolbar — anchors 12pt above whatever ancestor chrome
        // is visible below us. The tab-bar controller aggregates its pill
        // + optional `bottomBarAccessory` and returns a single top-Y via
        // `chromeTopY(in:)`; if no tab bar is hosting us, fall back to
        // the device safe area.
        //
        // We don't read `layout.additionalInsets.bottom` here — the
        // tab-bar dispatch path sets it to the tab chrome height, but
        // `AetherNavigationController.updateContainerLayout` resets it
        // to `.zero` on every layout pass, so it flickers. UIKit's
        // propagated `layout.safeInsets.bottom` stays stable; we use
        // that for the no-tab-bar fallback.
        let tabBarChromeTopY: CGFloat?
        if shouldAnchorToTabBarChrome, let tabBar = aetherTabBarController, let topY = tabBar.chromeTopY(in: view) {
            tabBarChromeTopY = topY
        } else {
            tabBarChromeTopY = nil
        }
        let rawSafeBottom: CGFloat = view.window?.safeAreaInsets.bottom ?? layout.safeInsets.bottom
        let pillOrSafeTopY = tabBarChromeTopY ?? (layout.size.height - rawSafeBottom)
        let inputAccessoryRestingAnchorTopY = tabBarChromeTopY
            ?? (layout.size.height - max(0.0, inputBarAccessoryBottomInset))

        let keyboardHeight = max(0.0, layout.inputHeight ?? 0.0)
        let inputAnchorTopY = keyboardHeight > 0.0
            ? layout.size.height - max(keyboardHeight, max(0.0, inputBarAccessoryBottomInset))
            : inputAccessoryRestingAnchorTopY

        var inputBarAccessoryTopY = inputAnchorTopY
        let inputBarHeight: CGFloat
        if let inputBarAccessoryView {
            inputBarHeight = resolvedInputBarAccessoryHeight(width: layout.size.width)
            inputBarAccessoryTopY = inputAnchorTopY - inputBarHeight
            if inputBarAccessoryView.superview !== view {
                view.addSubview(inputBarAccessoryView)
            }
            let accessoryFrame = CGRect(
                x: 0.0,
                y: inputBarAccessoryTopY,
                width: layout.size.width,
                height: inputBarHeight
            )
            inputBarAccessoryFrame = accessoryFrame
            transition.updateFrame(view: inputBarAccessoryView, frame: accessoryFrame)
            view.bringSubviewToFront(inputBarAccessoryView)
        } else {
            inputBarHeight = 0.0
            inputBarAccessoryFrame = .zero
        }
        syncInputBarAccessoryHeightWithWindow()

        let toolbarHeight = floatingToolbarHeight
        let toolbarBottomGap: CGFloat = 12
        let toolbarAnchorTopY = inputBarAccessoryView != nil ? inputBarAccessoryTopY : pillOrSafeTopY
        var toolbarTopY: CGFloat = layout.size.height
        if let toolbar = floatingToolbar {
            let toolbarY = toolbarAnchorTopY - toolbarBottomGap - toolbarHeight
            toolbarTopY = toolbarY
            let toolbarFrame = CGRect(
                x: 0,
                y: toolbarY,
                width: layout.size.width,
                height: toolbarHeight
            )
            transition.updateFrame(view: toolbar, frame: toolbarFrame)
            view.bringSubviewToFront(toolbar)
        }

        // additionalSafeAreaInsets.bottom = distance from "previous
        // content-bottom" (what descendants saw before we added our
        // chrome) to our toolbar's TOP. This is the extra chrome WE
        // contribute on top of the ancestor's.
        //
        // `layout.safeInsets.bottom` here is UIKit's propagated value —
        // it already sums device safe area + all ancestors' own
        // `additionalSafeAreaInsets` contributions (which now includes the
        // tab bar's `bottomBarAccessory` if present, since the tab bar
        // folds it into its own additional inset). Reading only the
        // propagated side reconciles the TabBar/Nav dispatch paths.
        let previousContentBottomY = layout.size.height - layout.safeInsets.bottom
        let addedInputBarBottom: CGFloat = inputBarAccessoryView != nil
            ? max(0.0, previousContentBottomY - inputBarAccessoryTopY)
            : 0.0
        let addedToolbarBottom: CGFloat
        if floatingToolbar != nil {
            if inputBarAccessoryView != nil {
                addedToolbarBottom = toolbarHeight + toolbarBottomGap
            } else {
                addedToolbarBottom = max(0, previousContentBottomY - toolbarTopY)
            }
        } else {
            addedToolbarBottom = 0.0
        }
        let addedChromeBottom: CGFloat = addedInputBarBottom + addedToolbarBottom

        let topInset = max(0.0, navLayout.navigationFrame.maxY - layout.safeInsets.top) + layout.additionalInsets.top
        let updatedInsets = UIEdgeInsets(
            top: topInset,
            left: 0.0,
            bottom: addedChromeBottom,
            right: 0.0
        )
        if additionalSafeAreaInsets != updatedInsets {
            // Apply synchronously rather than via `transition.animateView`.
            // Wrapping the setter in a UIView.animate block (the .animated
            // path) deferred the safe-area propagation a CA tick behind
            // the nav-bar frame change — visible as a one-frame "seam"
            // strip between the navbar bottom and the content top whenever
            // the nav bar resized (search pill jumping navbar↔bottom on
            // launch, modal sheet detent change). The frame animation of
            // the nav bar itself is still animated by `bar.updateLayout`
            // — only the inset propagation needs to be eager.
            additionalSafeAreaInsets = updatedInsets
        }

        // Bottom search mode: update pill position on keyboard changes
        if let sc = searchController, sc.placement == .bottom {
            if sc.isActive {
                sc.layoutBottomSearchActive(in: view, keyboardHeight: layout.inputHeight ?? 0)
            } else {
                sc.layoutBottomPill(in: view)
            }
        }
    }

    // MARK: - View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()

        if let bar = navigationBarView {
            // Only set defaults if not already configured by a
            // NavigationController (wireControllers sets these before
            // viewDidLoad and they must not be overwritten).
            if !navigationBarIsExternallyHosted, bar.superview == nil {
                view.addSubview(bar)
            }
            if !navigationBarIsExternallyHosted, bar.requestContainerLayout == nil {
                bar.requestContainerLayout = { [weak self] transition in
                    self?.requestLayout(transition: transition)
                }
            }
            
            if !navigationBarIsExternallyHosted {
                bar.backPressed = { [weak self] in
                    guard let self else { return }
                    pop(animated: true)
                }
            }
        }

        // Attach a content-unavailable overlay assigned before the view loaded.
        if let host = _contentUnavailableView, host.superview == nil {
            host.frame = view.bounds
            view.addSubview(host)
        }

        if let inputBarAccessoryView, inputBarAccessoryView.superview == nil {
            view.addSubview(inputBarAccessoryView)
        }

        updateScrollToTopView()
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-pick up `navigationBarItem` contents now that viewDidLoad has run.
        // NavigationController wires `bar.item = navigationBarItem` at setViewControllers
        // time, which can happen BEFORE the view is loaded — on that path the
        // subclass hasn't yet had a chance to assign title, titleView, or bar
        // button items in viewDidLoad. Re-assigning the same UINavigationItem
        // here re-fires the bar's `didSet` and lets it observe the populated
        // state. Idempotent for unchanged screens (reference-equality checks
        // inside updateItemContent skip redundant work).
        if let bar = navigationBarView {
            bar.item = navigationBarItem
            bar.requestContainerLayout?(.immediate)
        }
    }

    private func navigationBarItemContentDidChange() {
        if let bar = navigationBarView {
            bar.item = navigationBarItem
            bar.requestContainerLayout?(.immediate)
        }
        notifyTopBarAccessoryDidChange(transition: .immediate)
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isInFocus = true
        syncInputBarAccessoryHeightWithWindow()
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    override open func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isInFocus = false
        (view.window as? AetherWindow)?.setManualKeyboardGestureAccessoryHeight(nil)
    }

    // MARK: - Navigation Bar

    public func setNavigationBarPresentationData(_ presentationData: NavigationBarPresentationData, animated: Bool) {
        explicitNavigationBarPresentationData = presentationData
        navigationBarView?.updatePresentationData(presentationData, transition: animated ? .animated(duration: 0.3, curve: .easeInOut) : .immediate)
    }

    open func updateNavigationBarScrollEdgeOffset(
        for scrollView: UIScrollView,
        transition: ContainedViewLayoutTransition
    ) {
        let visibleOffset = scrollView.contentOffset.y + scrollView.contentInset.top
        let alpha = min(1.0, max(0.0, visibleOffset / 16.0))
        scrollEdgeNavigationBar()?.updateBackgroundAlpha(alpha, transition: transition)
    }

    private func scrollEdgeNavigationBar() -> NavigationBarView? {
        if let bar = navigationBarView, shouldUseNavigationBarForScrollEdgeOffset(bar) {
            return bar
        }

        var ancestor = parent
        while let current = ancestor {
            if let viewController = current as? AetherViewController,
               viewController.displayNavigationBar,
               let bar = viewController.navigationBarView,
               viewController.shouldUseNavigationBarForScrollEdgeOffset(bar) {
                return bar
            }
            ancestor = current.parent
        }

        return nil
    }

    private func shouldUseNavigationBarForScrollEdgeOffset(_ bar: NavigationBarView) -> Bool {
        if !navigationBarIsExternallyHosted {
            return true
        }
        if bar.superview != nil {
            return true
        }
        return (externalNavigationBarHeight ?? 0.0) > 0.0
    }

    open func updateNavigationCustomData(_ data: Any?, progress: CGFloat, transition: ContainedViewLayoutTransition) {
    }

    open func tabBarItemContextAction(sourceView: UIView, gesture: UIGestureRecognizer) {
    }

    open func tabBarItemHasDoubleTapAction() -> Bool {
        return false
    }

    open func tabBarItemPerformDoubleTapAction() {
    }

    open func tabBarDisabledAction() {
    }

    open func tabBarActivateSearch() {
    }

    open func tabBarDeactivateSearch() {
    }

    open func tabBarItemSwipeAction(direction: TabBarItemSwipeDirection) {
    }

    public func updateTabBarSearchState(_ tabBarSearchState: TabBarSearchState?, transition: ContainedViewLayoutTransition) {
        if self.tabBarSearchState != tabBarSearchState {
            self.tabBarSearchState = tabBarSearchState
            self.tabBarSearchStateUpdated?(transition)
        }
    }

    // MARK: - Private

    private func installInputBarAccessoryHeightProvider(on view: UIView) {
        view.input_setInputAccessoryHeightProvider { [weak self] in
            return self?.inputBarAccessoryReservedHeight ?? 0.0
        }
    }

    private func resolvedInputBarAccessoryHeight(width: CGFloat) -> CGFloat {
        if let reservedHeight = _inputBarAccessoryReservedHeight {
            return reservedHeight
        }
        guard let inputBarAccessoryView else {
            return 0.0
        }

        let fittingWidth = width > 0.0 ? width : UIView.layoutFittingCompressedSize.width
        let fittingSize = inputBarAccessoryView.systemLayoutSizeFitting(
            CGSize(width: fittingWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: width > 0.0 ? .required : .defaultLow,
            verticalFittingPriority: .fittingSizeLevel
        )
        if fittingSize.height > 0.0 {
            return fittingSize.height
        }
        if inputBarAccessoryView.bounds.height > 0.0 {
            return inputBarAccessoryView.bounds.height
        }
        return inputBarAccessoryDefaultHeight
    }

    private func syncInputBarAccessoryHeightWithWindow() {
        guard isViewLoaded, isInFocus, let window = view.window as? AetherWindow else {
            return
        }
        if inputBarAccessoryView != nil {
            window.setManualKeyboardGestureAccessoryHeight(inputBarAccessoryReservedHeight)
        } else {
            window.setManualKeyboardGestureAccessoryHeight(nil)
        }
    }

    private func updateScrollToTopView() {
        if let scrollToTop = self.scrollToTop {
            if scrollToTopView == nil {
                let stv = ScrollToTopView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 10))
                stv.autoresizingMask = [.flexibleWidth]
                view.addSubview(stv)
                self.scrollToTopView = stv
            }
            scrollToTopView?.action = scrollToTop
        } else {
            scrollToTopView?.removeFromSuperview()
            scrollToTopView = nil
        }
    }

    // MARK: - Push/Pop

    /// Push a new controller on the nearest enclosing navigation stack.
    ///
    /// Routing is straightforward now that the architecture is
    /// native-iOS-shape (TabBarController → per-tab NavigationController
    /// → screens): we just walk up to the nearest
    /// `AetherNavigationController` and push there. Tab bar visibility
    /// stays whatever it is — it is the TabBarController's concern, not
    /// this call's.
    open func push(_ controller: AetherViewController, animated: Bool = true) {
        if let nav = aetherNavigationController {
            nav.pushViewController(controller, animated: animated)
        } else {
            self.navigationController?.pushViewController(controller, animated: animated)
        }
    }

    open func pop(animated: Bool = true) {
        if let nav = aetherNavigationController {
            nav.popViewController(animated: animated)
        } else {
            self.navigationController?.popViewController(animated: animated)
        }
    }

    public func presentInGlobalOverlay(_ controller: UIViewController, animated: Bool = true, completion: (() -> Void)? = nil) {
        if let window = view.window as? AetherWindow {
            window.presentInGlobalOverlay(controller, animated: animated, completion: completion)
        } else if let controller = controller as? AetherViewController, let nav = aetherNavigationController {
            nav.presentOverlay(controller, animated: animated, completion: completion)
        } else {
            present(controller, animated: animated, completion: completion)
        }
    }

    public func addGlobalPortalHostView(_ view: UIView) {
        (self.view.window as? AetherWindow)?.addGlobalPortalHostView(view)
    }

    public func requestLayout(transition: ContainedViewLayoutTransition) {
        if let layout = self.validLayout {
            self.containerLayoutUpdated(layout, transition: transition)
        }
    }

    // MARK: - Content Unavailable Configuration

    private var _contentUnavailableView: AetherContentUnavailableView?

    /// UIKit-style content-unavailable overlay. Assign a configuration to
    /// surface an empty / loading / error state on top of this controller's
    /// content; assign `nil` to remove it.
    ///
    ///     var config = AetherContentUnavailableConfiguration.empty()
    ///     config.image = UIImage(systemName: "tray")
    ///     config.text = "Здесь пока пусто"
    ///     aetherContentUnavailableConfiguration = config
    ///
    /// The overlay sits below the navigation bar and floating toolbar so
    /// chrome remains interactive. For a cross-fade between states use
    /// `setAetherContentUnavailableConfiguration(_:animated:)`.
    ///
    /// Named with an `aether` prefix to avoid colliding with UIKit's own
    /// `UIViewController.contentUnavailableConfiguration` introduced on
    /// iOS 17 (different type signature: `UIContentConfiguration?`).
    public var aetherContentUnavailableConfiguration: AetherContentUnavailableConfiguration? {
        get { _contentUnavailableView?.configuration }
        set { setAetherContentUnavailableConfiguration(newValue, animated: false) }
    }

    public func setAetherContentUnavailableConfiguration(_ configuration: AetherContentUnavailableConfiguration?, animated: Bool) {
        if let configuration {
            let host = ensureContentUnavailableView()
            host.setConfiguration(configuration, animated: animated)
            requestLayout(transition: .immediate)
        } else if let existing = _contentUnavailableView {
            existing.setConfiguration(nil, animated: animated)
            let cleanup: () -> Void = { [weak self, weak existing] in
                guard let self, let existing else { return }
                guard self._contentUnavailableView === existing, existing.configuration == nil else { return }
                existing.removeFromSuperview()
                self._contentUnavailableView = nil
            }
            if animated {
                let delay = existing.transitionDuration
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: cleanup)
            } else {
                cleanup()
            }
        }
    }

    private func ensureContentUnavailableView() -> AetherContentUnavailableView {
        if let existing = _contentUnavailableView { return existing }
        let host = AetherContentUnavailableView()
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        if isViewLoaded {
            host.frame = view.bounds
            view.addSubview(host)
        }
        _contentUnavailableView = host
        return host
    }

    private var aetherNavigationController: AetherNavigationController? {
        var current: UIViewController? = self
        while let controller = current {
            if let navigationController = controller as? AetherNavigationController {
                return navigationController
            }
            current = controller.parent
        }
        return nil
    }

    private var shouldAnchorToTabBarChrome: Bool {
        guard hidesBottomBarWhenPushed,
              let navigationController = aetherNavigationController,
              let rootController = navigationController.viewControllerStack.first
        else {
            return true
        }
        return self === rootController
    }

    /// The closest `AetherTabBarController` up the parent chain, if
    /// any. Useful for screens that need to hide / show the tab bar
    /// during their own appearance lifecycle (e.g. detail screens
    /// pushed from a tab root).
    ///
    /// Named with an `aether` prefix to avoid colliding with UIKit's own
    /// `UIViewController.tabBarController` (different type: `UITabBarController?`).
    public var aetherTabBarController: AetherTabBarController? {
        var current: UIViewController? = self
        while let controller = current {
            if let tabBar = controller as? AetherTabBarController {
                return tabBar
            }
            current = controller.parent
        }
        return nil
    }
}

public extension NavigationBarPresentationData {
    class func defaultTheme(edgeColor: UIColor) -> NavigationBarPresentationData {
        // `primaryTextColor: .label` is required — without it the
        // `NavigationBarTheme.init` default (`.black`) wins and the
        // navigation title stays black even when the trait collection
        // flips to dark mode. `.label` is a dynamic UIColor that
        // resolves at draw time off the host's traitCollection, so the
        // title tracks light/dark just like the button glyphs.
        let theme = NavigationBarTheme(
            buttonColor: .label,
            primaryTextColor: .label,
            edgeEffectColor: edgeColor,
            style: .glass,
            glassStyle: .clear,
            edgeEffectAlpha: 0.85,
            edgeEffectBlurRadiusAtEdge: 1,
            edgeEffectBlurRadiusAtFade: 1
        )
        
        return .init(theme: theme)
    }
}
