import UIKit

// MARK: - Delegate Protocol

/// Delegate for `AetherSearchController` lifecycle and text events.
///
/// Implement to react to search activation, text changes, and dismissal.
/// All methods have default empty implementations.
public protocol AetherSearchControllerDelegate: AnyObject {
    /// Called when search is about to activate (pill → text field).
    func searchControllerWillActivate(_ controller: AetherSearchController)

    /// Called after search has activated and the text field is first responder.
    func searchControllerDidActivate(_ controller: AetherSearchController)

    /// Called when the search text changes.
    func searchController(_ controller: AetherSearchController, didChangeText text: String)

    /// Called when the user taps the return key.
    func searchController(_ controller: AetherSearchController, didSubmitText text: String)

    /// Called when search is about to deactivate (text field → pill).
    func searchControllerWillDeactivate(_ controller: AetherSearchController)

    /// Called after search has fully deactivated and the nav bar is restored.
    func searchControllerDidDeactivate(_ controller: AetherSearchController)
}

// Default implementations (all optional)
public extension AetherSearchControllerDelegate {
    func searchControllerWillActivate(_ controller: AetherSearchController) {}
    func searchControllerDidActivate(_ controller: AetherSearchController) {}
    func searchController(_ controller: AetherSearchController, didChangeText text: String) {}
    func searchController(_ controller: AetherSearchController, didSubmitText text: String) {}
    func searchControllerWillDeactivate(_ controller: AetherSearchController) {}
    func searchControllerDidDeactivate(_ controller: AetherSearchController) {}
}

// MARK: - Search Controller

/// Glass-styled search controller that integrates with `ViewController`'s navigation bar.
///
/// ## Integration
///
/// Set on `ViewController.searchController`. The framework automatically
/// shows a glass search pill in the nav bar expansion area (between title and
/// content like filter chips).
///
/// ```swift
/// let search = AetherSearchController()
/// search.placeholder = "Search"
/// search.delegate = self
/// searchController = search
/// ```
///
/// ## Activation Flow
///
/// 1. User taps the search pill in the nav bar
/// 2. Title and buttons fade out (easeInOut 0.3s)
/// 3. Filter chips fade out, nav bar shrinks
/// 4. Search pill slides up to the title position
/// 5. Pill's icon/label hide, real `UITextField` appears inside
/// 6. Glass close button (36pt) appears to the right of the pill
/// 7. Keyboard shows, collection content animates up
///
/// ## Deactivation Flow
///
/// 1. User taps the close button (or `deactivate()` is called)
/// 2. Keyboard dismisses simultaneously with UI restoration
/// 3. Close button scales down and fades
/// 4. Text field removed, pill icon/label restored
/// 5. Nav bar expands back, title/buttons/filters fade in
/// 6. Collection content animates down
///
/// ## Tab Bar Integration
///
/// When the owning `ViewController` is inside a `AetherTabBarController`,
/// the tab bar's search item button can trigger activation:
///
/// ```swift
/// override func tabBarActivateSearch() {
///     searchController?.activate()
/// }
/// ```
///
/// ## Results Controller
///
/// Optionally set `searchResultsController` to display a custom results view
/// when search is active:
///
/// ```swift
/// search.searchResultsController = MySearchResultsController()
/// ```
///
/// The results controller receives text updates via
/// `AetherSearchContentController.searchTextUpdated(text:)`.
public final class AetherSearchController: NSObject, UITextFieldDelegate {

    /// Search bar placement mode, determined automatically.
    public enum Placement {
        /// Search pill in the nav bar (between title and content). Used when
        /// the view controller is inside a `AetherTabBarController`.
        case navBar
        /// Floating search pill at the bottom of the screen with edge effect.
        /// Used when there is no tab bar controller in the hierarchy.
        case bottom
    }

    // MARK: - Public Properties

    /// Placeholder text for the search field.
    public var placeholder: String = "Search" {
        didSet {
            searchBar.placeholder = placeholder
            bottomPillLabel?.text = placeholder
        }
    }

    /// Delegate for search lifecycle and text events.
    public weak var delegate: AetherSearchControllerDelegate?

    /// Whether search is currently active.
    public private(set) var isActive: Bool = false

    /// Current search text (empty when inactive).
    public var searchText: String {
        textField?.text ?? ""
    }

    /// Optional controller that displays search results.
    /// Its `searchTextUpdated(text:)` is called on every text change.
    public var searchResultsController: AetherSearchContentController?

    /// Size of the glass close button (default 36pt).
    public var closeButtonSize: CGFloat = 44.0

    /// Force search to bottom mode even when a tab bar controller is present.
    /// Default `false` — placement is determined automatically.
    public var prefersBottomPlacement: Bool = false

    /// Current placement (determined automatically when installed on a ViewController).
    public private(set) var placement: Placement = .navBar

    // MARK: - Internal Views

    /// The glass search pill shown in the nav bar (navBar mode only).
    let searchBar = AetherSearchBarContent()

    // MARK: - Private State

    private var textField: UITextField?
    private var closeButton: GlassBarButtonView?
    weak var viewController: AetherViewController?
    var savedNavigationBarContent: NavigationBarContentView?

    // Bottom mode views
    private static let bottomBarHeight: CGFloat = 42.0
    private var bottomPill: GlassBackgroundView?
    private var bottomPillIcon: UIImageView?
    private var bottomPillLabel: UILabel?
    private var bottomEdgeEffect: EdgeEffectView?

    // MARK: - Init

    public override init() {
        super.init()
        searchBar.onTap = { [weak self] in
            self?.activate()
        }
    }

    // MARK: - Installation

    /// Determines placement and installs bottom pill if needed.
    /// Called by `ViewController` when this controller is assigned.
    func install(on vc: AetherViewController) {
        viewController = vc

        // Resolve placement *synchronously* on the responder chain. The
        // previous implementation deferred this to `DispatchQueue.main.async`,
        // which on apps without a tab bar caused the search pill to flash
        // briefly inside the nav bar (default placement = `.navBar`)
        // before snapping down to the bottom — visible jump on every
        // launch.
        let hasTabBarSync = Self.responderChainContainsTabBar(starting: vc)
        placement = (hasTabBarSync && !prefersBottomPlacement) ? .navBar : .bottom
        if placement == .bottom {
            installBottomPill(on: vc)
        }

        // Edge case — the VC may not be wired into a parent yet at install
        // time (e.g. early init from outside `viewWillAppear`), in which
        // case the sync chain walk finds nothing. Re-check on the next
        // runloop tick so a late-attaching tab bar still routes the pill
        // up into the nav bar.
        if !hasTabBarSync {
            DispatchQueue.main.async { [weak self, weak vc] in
                guard let self, let vc else { return }
                guard self.placement == .bottom, !self.prefersBottomPlacement else { return }
                guard Self.responderChainContainsTabBar(starting: vc) else { return }
                // Promote to nav bar placement: tear down the bottom pill
                // and let the VC rebuild its accessory with the search pill.
                self.removeBottomPill()
                self.placement = .navBar
                vc.rebuildTopBarAccessory()
            }
        }
    }

    private static func responderChainContainsTabBar(starting responder: UIResponder) -> Bool {
        var current: UIResponder? = responder
        while let next = current?.next {
            if next is AetherTabBarController { return true }
            current = next
        }
        return false
    }

    /// Remove bottom pill if present.
    func uninstall() {
        removeBottomPill()
        viewController = nil
    }

    // MARK: - Activation

    /// Activate search mode. Behavior depends on `placement`:
    /// - `.navBar`: pill becomes text field in nav bar, title fades
    /// - `.bottom`: pill shrinks, close button appears, keyboard lifts pill
    public func activate() {
        guard !isActive, let vc = viewController else { return }
        isActive = true
        delegate?.searchControllerWillActivate(self)

        switch placement {
        case .navBar:
            activateNavBar(vc: vc)
        case .bottom:
            activateBottom(vc: vc)
        }
    }

    /// Deactivate search. Keyboard and UI restore simultaneously.
    public func deactivate() {
        guard isActive, let vc = viewController else { return }
        isActive = false
        delegate?.searchControllerWillDeactivate(self)

        switch placement {
        case .navBar:
            deactivateNavBar(vc: vc)
        case .bottom:
            deactivateBottom(vc: vc)
        }
    }

    // MARK: - Nav Bar Mode

    private func activateNavBar(vc: AetherViewController) {
        guard let navBar = vc.navigationBarView else { return }

        searchBar.setSearchActive(true)
        searchBar.rightExtraInset = closeButtonSize + 8.0

        let tf = makeTextField()
        searchBar.pillView.contentView.addSubview(tf)
        tf.frame = searchBar.pillView.bounds.insetBy(dx: 12, dy: 0)
        tf.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textField = tf

        let close = makeCloseButton()
        if let parent = searchBar.superview {
            parent.addSubview(close)
        } else {
            navBar.addSubview(close)
        }
        closeButton = close

        navBar.setSearchMode(true, animated: true)
        tf.becomeFirstResponder()

        DispatchQueue.main.async { [weak self] in
            self?.layoutNavBarCloseButton()
        }

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            close.alpha = 1
            close.transform = .identity
        } completion: { [weak self] _ in
            guard let self else { return }
            self.delegate?.searchControllerDidActivate(self)
        }
    }

    private func deactivateNavBar(vc: AetherViewController) {
        textField?.resignFirstResponder()
        textField?.removeFromSuperview()
        textField = nil

        searchBar.setSearchActive(false)
        searchBar.rightExtraInset = 0
        vc.navigationBarView?.setSearchMode(false, animated: true)

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.closeButton?.alpha = 0
            self.closeButton?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        } completion: { [weak self] _ in
            guard let self else { return }
            self.closeButton?.removeFromSuperview()
            self.closeButton = nil
            self.delegate?.searchControllerDidDeactivate(self)
        }
    }

    private func layoutNavBarCloseButton() {
        guard let close = closeButton else { return }
        let s = closeButtonSize
        let pillFrame = searchBar.frame
        let parentBounds = searchBar.superview?.bounds ?? .zero
        let x = parentBounds.width - s - searchBar.horizontalInset
        let y = pillFrame.midY - s / 2
        close.frame = CGRect(x: x, y: y, width: s, height: s)
    }

    // MARK: - Bottom Mode

    private func installBottomPill(on vc: AetherViewController) {
        let edge = EdgeEffectView()
        edge.isUserInteractionEnabled = false
        vc.view.addSubview(edge)
        bottomEdgeEffect = edge

        let pill = GlassBackgroundView(style: .regular)
        pill.isUserInteractionEnabled = true
        // We `bringSubviewToFront` again from the VC's `viewDidLayoutSubviews`
        // (see AetherUI ViewController) so the pill stays on top even if
        // the host adds the collection / scroll view AFTER it. Without
        // that, sync `install` called from `viewDidLoad` ends up placing
        // the pill below content the host adds later in viewDidLoad.
        // Attach the tap gesture to `pill.contentView`, NOT to the
        // `pill` itself. `GlassBackgroundView.hitTest` forwards into
        // `contentContainer.hitTest`, which deliberately returns nil
        // when none of its descendants accept the touch AND the
        // container itself has no gesture recognisers — that's the
        // "glass surface should pass touches through" behaviour the
        // class was designed for. Adding the gesture on the bare pill
        // therefore got swallowed by that filter, which is why the
        // bottom pill appeared but couldn't be tapped after the
        // initial layout settled. Putting the gesture on the
        // `contentContainer` makes the filter find a recogniser and
        // capture the touch.
        pill.contentView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(bottomPillTapped))
        )
        vc.view.addSubview(pill)
        bottomPill = pill

        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))?.withRenderingMode(.alwaysTemplate))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .center
        pill.contentView.addSubview(icon)
        bottomPillIcon = icon

        let label = UILabel()
        label.text = placeholder
        label.font = .systemFont(ofSize: 17)
        label.textColor = .secondaryLabel
        pill.contentView.addSubview(label)
        bottomPillLabel = label

        layoutBottomPill(in: vc.view)
    }

    private func removeBottomPill() {
        bottomPill?.removeFromSuperview()
        bottomEdgeEffect?.removeFromSuperview()
        bottomPill = nil
        bottomPillIcon = nil
        bottomPillLabel = nil
        bottomEdgeEffect = nil
    }

    private func bottomPillY(in view: UIView) -> CGFloat {
        let safeBottom = view.safeAreaInsets.bottom
        return view.bounds.height - max(25.0, safeBottom + 8.0) - Self.bottomBarHeight
    }

    func layoutBottomPill(in view: UIView) {
        guard let pill = bottomPill, !isActive else { return }
        let h = Self.bottomBarHeight
        let side: CGFloat = 16.0
        let y = bottomPillY(in: view)
        let isDark = view.traitCollection.userInterfaceStyle == .dark

        // Keep the pill + frost above content the host adds after the
        // search controller was installed. Sync placement (post-fix)
        // can land the pill in the view hierarchy *before* the host
        // VC adds its scroll/collection view in `viewDidLoad`, so the
        // collection ends up on top by default. Re-asserting z-order
        // on each layout keeps the pill tappable and visible.
        if let edge = bottomEdgeEffect {
            view.bringSubviewToFront(edge)
        }
        view.bringSubviewToFront(pill)

        if let edge = bottomEdgeEffect {
            let edgeH: CGFloat = 48.0
            let edgeFrame = CGRect(x: 0, y: y - edgeH + 72, width: view.bounds.width, height: 72)
            edge.frame = edgeFrame
            let searchAppearance = viewController?.resolvedSearchAppearance(
                surface: .bottomSearch,
                placement: .standaloneBottom
            ) ?? AetherSearchAppearanceResolver.resolve(
                context: AetherAppearanceResolutionContext(
                    appearance: AetherAppearance.runtimeCurrent,
                    surface: .bottomSearch,
                    placement: .standaloneBottom,
                    traitCollection: view.traitCollection
                )
            )
            let edgeAppearance = searchAppearance.edgeEffect
            let hasVisibleEdgeEffect = edgeAppearance.alpha > 0.001
                || edgeAppearance.blurRadiusAtEdge > 0.001
                || edgeAppearance.blurRadiusAtFade > 0.001
            let content: UIColor = edgeAppearance.tintColor ?? .systemBackground
            edge.clipsToBounds = edgeAppearance.style != .regular
            let usesProgressiveBlur = edgeAppearance.style == .regular
            edge.update(
                content: hasVisibleEdgeEffect ? content : .clear,
                blur: hasVisibleEdgeEffect,
                alpha: edgeAppearance.alpha,
                rect: CGRect(origin: .zero, size: edgeFrame.size),
                edge: .bottom,
                edgeSize: usesProgressiveBlur ? edgeH : 0.0,
                blurRadiusAtEdge: edgeAppearance.blurRadiusAtEdge,
                blurRadiusAtFade: usesProgressiveBlur ? 0.0 : edgeAppearance.blurRadiusAtEdge,
                solidBlur: !usesProgressiveBlur,
                minimumFadeAlpha: usesProgressiveBlur ? 0.0 : 0.04,
                transition: .immediate
            )
            edge.isHidden = !hasVisibleEdgeEffect
        }

        let frame = CGRect(x: side, y: y, width: view.bounds.width - side * 2, height: h)
        pill.frame = frame
        pill.update(size: frame.size, cornerRadius: h / 2, isDark: isDark,
                    tintColor: .init(kind: .panel), isInteractive: false, isVisible: true, transition: .immediate)
        bottomPillIcon?.frame = CGRect(x: 14, y: (h - 18) / 2, width: 18, height: 18)
        bottomPillLabel?.frame = CGRect(x: 38, y: 0, width: frame.width - 48, height: h)
    }
    
    public func updateEdgeEffect(color: UIColor) {
        if let edge = bottomEdgeEffect {
            edge.updateColor(color: color, transition: .immediate)
        }
    }

    @objc private func bottomPillTapped() {
        activate()
    }

    private func activateBottom(vc: AetherViewController) {
        guard let pill = bottomPill else { return }
        let h = Self.bottomBarHeight

        bottomPillIcon?.isHidden = true
        bottomPillLabel?.isHidden = true

        let tf = makeTextField()
        pill.contentView.addSubview(tf)
        tf.frame = CGRect(x: 8, y: 0, width: pill.bounds.width - 16, height: h)
        textField = tf

        let close = makeCloseButton()
        vc.view.addSubview(close)
        let pillFrame = pill.frame
        close.frame = CGRect(x: pillFrame.maxX, y: pillFrame.minY, width: h, height: h)
        closeButton = close

        tf.becomeFirstResponder()

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.2, options: [.beginFromCurrentState]) {
            self.layoutBottomSearchActive(in: vc.view)
            close.alpha = 1
            close.transform = .identity
        } completion: { [weak self] _ in
            guard let self else { return }
            self.delegate?.searchControllerDidActivate(self)
        }
    }

    private func deactivateBottom(vc: AetherViewController) {
        textField?.resignFirstResponder()

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.closeButton?.alpha = 0
            self.closeButton?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            self.layoutBottomPill(in: vc.view)
        } completion: { [weak self] _ in
            guard let self else { return }
            self.textField?.removeFromSuperview()
            self.textField = nil
            self.closeButton?.removeFromSuperview()
            self.closeButton = nil
            self.bottomPillIcon?.isHidden = false
            self.bottomPillLabel?.isHidden = false
            self.delegate?.searchControllerDidDeactivate(self)
        }
    }

    func layoutBottomSearchActive(in view: UIView, keyboardHeight: CGFloat? = nil) {
        guard let pill = bottomPill else { return }
        let h = Self.bottomBarHeight
        let side: CGFloat = 16.0
        let isDark = view.traitCollection.userInterfaceStyle == .dark
        let kbH = keyboardHeight ?? 0
        let baseY = kbH > 0 ? view.bounds.height - kbH - h - 8 : bottomPillY(in: view)
        let closeX = view.bounds.width - side - h
        let pillWidth = closeX - side - 8

        closeButton?.frame = CGRect(x: closeX, y: baseY, width: h, height: h)
        let pillFrame = CGRect(x: side, y: baseY, width: pillWidth, height: h)
        pill.frame = pillFrame
        pill.update(size: pillFrame.size, cornerRadius: h / 2, isDark: isDark,
                    tintColor: .init(kind: .panel), isInteractive: false, isVisible: true, transition: .immediate)
        textField?.frame = CGRect(x: 8, y: 0, width: pillWidth - 16, height: h)

        if let edge = bottomEdgeEffect {
            let edgeH: CGFloat = 48.0
            let edgeFrame = CGRect(x: 0, y: baseY - edgeH, width: view.bounds.width, height: view.bounds.height - baseY + edgeH)
            edge.frame = edgeFrame
            let searchAppearance = viewController?.resolvedSearchAppearance(
                surface: .bottomSearch,
                placement: .standaloneBottom
            ) ?? AetherSearchAppearanceResolver.resolve(
                context: AetherAppearanceResolutionContext(
                    appearance: AetherAppearance.runtimeCurrent,
                    surface: .bottomSearch,
                    placement: .standaloneBottom,
                    traitCollection: view.traitCollection
                )
            )
            let edgeAppearance = searchAppearance.edgeEffect
            let hasVisibleEdgeEffect = edgeAppearance.alpha > 0.001
                || edgeAppearance.blurRadiusAtEdge > 0.001
                || edgeAppearance.blurRadiusAtFade > 0.001
            let content = edgeAppearance.tintColor ?? .systemBackground
            edge.clipsToBounds = edgeAppearance.style != .regular
            let usesProgressiveBlur = edgeAppearance.style == .regular
            edge.update(
                content: hasVisibleEdgeEffect ? content : .clear,
                blur: hasVisibleEdgeEffect,
                alpha: edgeAppearance.alpha,
                rect: CGRect(origin: .zero, size: edgeFrame.size),
                edge: .bottom,
                edgeSize: usesProgressiveBlur ? edgeH : 0.0,
                blurRadiusAtEdge: edgeAppearance.blurRadiusAtEdge,
                blurRadiusAtFade: usesProgressiveBlur ? 0.0 : edgeAppearance.blurRadiusAtEdge,
                solidBlur: !usesProgressiveBlur,
                minimumFadeAlpha: usesProgressiveBlur ? 0.0 : 0.04,
                transition: .immediate
            )
            edge.isHidden = !hasVisibleEdgeEffect
        }
    }

    // MARK: - UITextFieldDelegate

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        delegate?.searchController(self, didSubmitText: text)
        searchResultsController?.searchTextUpdated(text: text)
        return true
    }

    // MARK: - Private

    private func makeTextField() -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.font = .systemFont(ofSize: 17)
        tf.textColor = .label
        tf.tintColor = .systemBlue
        tf.returnKeyType = .search
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.clearButtonMode = .whileEditing
        tf.delegate = self

        // Wrapper that pins the icon to the LEFT edge so the "after
        // icon" gap controls visible padding between glyph and
        // placeholder. Matches TabBarView search field's leftView.
        let leftViewWrapper = UIView(frame: CGRect(x: 0, y: 0, width: 28, height: 20))
        let iconImage = UIImage(
            systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        )
        let icon = UIImageView(image: iconImage)
        icon.tintColor = .secondaryLabel
        icon.frame = CGRect(x: 2, y: 0, width: 16, height: 20)
        icon.contentMode = .center
        leftViewWrapper.addSubview(icon)
        tf.leftView = leftViewWrapper
        tf.leftViewMode = .always

        tf.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        return tf
    }

    private func makeCloseButton() -> GlassBarButtonView {
        let icon = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        )
        let btn = GlassBarButtonView(icon: icon, state: .glass)
        btn.contentTintColor = .label
        btn.alpha = 0
        btn.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        btn.action = { [weak self] _ in self?.closeTapped() }
        return btn
    }

    private func closeTapped() {
        deactivate()
    }

    @objc private func textDidChange() {
        let text = textField?.text ?? ""
        delegate?.searchController(self, didChangeText: text)
        searchResultsController?.searchTextUpdated(text: text)
    }
}
