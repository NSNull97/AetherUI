import UIKit

public struct ViewControllerSupportedOrientations: Equatable {
    public var regularSize: UIInterfaceOrientationMask
    public var compactSize: UIInterfaceOrientationMask

    public init(regularSize: UIInterfaceOrientationMask = .all, compactSize: UIInterfaceOrientationMask = .allButUpsideDown) {
        self.regularSize = regularSize
        self.compactSize = compactSize
    }

    public func intersection(_ other: ViewControllerSupportedOrientations) -> ViewControllerSupportedOrientations {
        return ViewControllerSupportedOrientations(
            regularSize: self.regularSize.intersection(other.regularSize),
            compactSize: self.compactSize.intersection(other.compactSize)
        )
    }
}

public enum ViewControllerNavigationPresentation {
    case `default`
    case master
}

public enum TabBarItemContextActionType {
    case none
    case always
    case whenActive
}

/// Base ViewController with glass-style navigation support.
/// Pure UIKit replacement for Display.ViewController.
@objc open class ViewController: UIViewController {
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

    public final var supportedOrientations = ViewControllerSupportedOrientations()
    public final var lockedOrientation: UIInterfaceOrientationMask?
    public final var lockOrientation: Bool = false

    // MARK: - Presentation

    open var previousItem: NavigationPreviousAction?
    open var navigationPresentation: ViewControllerNavigationPresentation = .default
    open var _hasGlassStyle: Bool = false

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
    /// let search = CrystalSearchController()
    /// search.placeholder = "Search"
    /// search.delegate = self
    /// crystalSearchController = search
    /// ```
    ///
    /// Set to `nil` to remove the search pill from the nav bar.
    public var crystalSearchController: CrystalSearchController? {
        didSet {
            oldValue?.uninstall()
            if let sc = crystalSearchController {
                sc.searchBar.placeholder = sc.placeholder
                sc.searchBar.isDark = traitCollection.userInterfaceStyle == .dark
                sc.install(on: self)
                rebuildNavigationBarContent()
            } else {
                rebuildNavigationBarContent()
            }
        }
    }

    /// Rebuilds the nav bar content view to include the search pill
    /// (if `crystalSearchController` is set) stacked above `navigationBarContent`.
    internal func rebuildNavigationBarContent() {
        guard let sc = crystalSearchController, sc.placement == .navBar else {
            // No search controller, or bottom mode — just use raw content
            if navigationBarView != nil, displayNavigationBar {
                navigationBarView?.setContentView(_rawNavigationBarContent, animated: false)
            }
            navigationBarContentDidChange?()
            return
        }
        // Nav bar mode: stack search pill above raw content
        var views: [NavigationBarContentView] = [sc.searchBar]
        if let raw = _rawNavigationBarContent {
            views.append(raw)
        }
        let stacked = CrystalStackedBarContent(views: views)
        if navigationBarView != nil, displayNavigationBar {
            navigationBarView?.setContentView(stacked, animated: false)
        }
        navigationBarContentDidChange?()
    }

    /// The raw content set by the consumer (filters, chips, etc.).
    /// Stored separately from the search pill so `rebuildNavigationBarContent`
    /// can stack them.
    internal var _rawNavigationBarContent: NavigationBarContentView?

    // MARK: - Navigation Bar

    public var navigationBarView: NavigationBarView?
    public var displayNavigationBar: Bool = true

    /// Custom content view installed below the nav bar title row in `.expansion`
    /// mode (filter chips, segmented controls, etc.).
    ///
    /// When a `crystalSearchController` is set, the search pill is automatically
    /// stacked above this content. Set this to filters/chips — don't include
    /// the search bar manually.
    public var navigationBarContent: NavigationBarContentView? {
        get { _rawNavigationBarContent }
        set {
            guard _rawNavigationBarContent !== newValue else { return }
            _rawNavigationBarContent = newValue
            if crystalSearchController != nil {
                rebuildNavigationBarContent()
            } else {
                if navigationBarView != nil, displayNavigationBar {
                    navigationBarView?.setContentView(newValue, animated: false)
                } else {
                    navigationBarView?.setContentView(nil, animated: false)
                }
                navigationBarContentDidChange?()
            }
        }
    }

    /// Internal hook so `CrystalTabBarController` can re-sync when a child's
    /// `navigationBarContent` changes.
    public var navigationBarContentDidChange: (() -> Void)?

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
        let statusBarHeight: CGFloat = layout.statusBarHeight ?? 0.0
        let defaultNavigationBarHeight: CGFloat = 60.0
        let navBarContentHeight = navigationBarView?.contentHeight(defaultHeight: defaultNavigationBarHeight) ?? defaultNavigationBarHeight
        let navigationBarHeight: CGFloat = statusBarHeight + navBarContentHeight + additionalNavigationBarHeight

        var navigationBarFrame = CGRect(origin: .zero, size: CGSize(width: layout.size.width, height: navigationBarHeight))

        if !displayNavigationBar {
            navigationBarFrame.origin.y = -navigationBarFrame.size.height
        }

        return NavigationLayout(navigationFrame: navigationBarFrame, defaultContentHeight: defaultNavigationBarHeight)
    }

    open var cleanNavigationHeight: CGFloat {
        if let bar = navigationBarView {
            return bar.frame.maxY
        }
        return 0.0
    }

    open func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.updateCurrentContainerLayout(layout)

        let navLayout = navigationLayout(layout: layout)

        if let bar = navigationBarView {
            transition.updateFrame(view: bar, frame: navLayout.navigationFrame)
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
                transition: transition
            )
            view.bringSubviewToFront(bar)
        }

        let topInset = max(0.0, navLayout.navigationFrame.maxY - layout.safeInsets.top) + layout.additionalInsets.top
        let updatedInsets = UIEdgeInsets(
            top: topInset,
            left: 0.0,
            bottom: layout.additionalInsets.bottom,
            right: 0.0
        )
        if additionalSafeAreaInsets != updatedInsets {
            transition.animateView {
                self.additionalSafeAreaInsets = updatedInsets
            }
        }

        // Bottom search mode: update pill position on keyboard changes
        if let sc = crystalSearchController, sc.placement == .bottom {
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
            if bar.superview == nil {
                view.addSubview(bar)
            }
            if bar.requestContainerLayout == nil {
                bar.requestContainerLayout = { [weak self] transition in
                    self?.requestLayout(transition: transition)
                }
            }
        }

        updateScrollToTopView()
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-pick up `navigationItem` contents now that viewDidLoad has run.
        // NavigationController wires `bar.item = navigationItem` at setViewControllers
        // time, which can happen BEFORE the view is loaded — on that path the
        // subclass hasn't yet had a chance to assign title, titleView, or bar
        // button items in viewDidLoad. Re-assigning the same UINavigationItem
        // here re-fires the bar's `didSet` and lets it observe the populated
        // state. Idempotent for unchanged screens (reference-equality checks
        // inside updateItemContent skip redundant work).
        if let bar = navigationBarView {
            bar.item = navigationItem
            bar.requestContainerLayout?(.immediate)
        }
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isInFocus = true
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    override open func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isInFocus = false
    }

    // MARK: - Navigation Bar

    public func setNavigationBarPresentationData(_ presentationData: NavigationBarPresentationData, animated: Bool) {
        navigationBarView?.updatePresentationData(presentationData, transition: animated ? .animated(duration: 0.3, curve: .easeInOut) : .immediate)
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
    /// `CrystalNavigationController` and push there. Tab bar visibility
    /// stays whatever it is — it is the TabBarController's concern, not
    /// this call's.
    open func push(_ controller: ViewController, animated: Bool = true) {
        if let navigationController = crystalNavigationController {
            navigationController.pushViewController(controller, animated: animated)
        } else {
            self.navigationController?.pushViewController(controller, animated: animated)
        }
    }

    open func pop(animated: Bool = true) {
        if let navigationController = crystalNavigationController {
            navigationController.popViewController(animated: animated)
        } else {
            self.navigationController?.popViewController(animated: animated)
        }
    }

    public func requestLayout(transition: ContainedViewLayoutTransition) {
        if let layout = self.validLayout {
            self.containerLayoutUpdated(layout, transition: transition)
        }
    }

    private var crystalNavigationController: CrystalNavigationController? {
        var current: UIViewController? = self
        while let controller = current {
            if let navigationController = controller as? CrystalNavigationController {
                return navigationController
            }
            current = controller.parent
        }
        return nil
    }
}
