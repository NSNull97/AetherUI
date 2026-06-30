import UIKit

/// Modal sheet that hosts a `AetherNavigationController` inside its
/// content area — gives consumers `pushViewController` / `popViewController` /
/// `viewControllers` and a navbar at the top of the sheet without
/// the boilerplate of wiring nav + form + embed by hand.
///
/// Use it the way you'd use a vanilla `UINavigationController`:
///
/// ```swift
/// final class MyModal: AetherModalNavigationController {
///     init() {
///         super.init(rootViewController: MyFormVC(), config: .init(...))
///     }
///     override func viewDidLoad() {
///         super.viewDidLoad()
///         footerView = sendButton
///         footerHeight = 98
///         primaryScrollView = (rootViewController as? MyFormVC)?.scroll
///     }
/// }
/// ```
///
/// The internal `AetherNavigationController` is exposed read-only as
/// `internalNavigationController` for callers that need its specific API
/// (overlay containers, popover hosts, etc.). Otherwise the forwarded
/// methods on this class cover the standard navigation surface —
/// `viewControllers`, `pushViewController(_:animated:)`,
/// `popViewController(animated:)`, `popToRoot(animated:)`,
/// `setViewControllers(_:animated:)`.
///
/// The navigation bar absorbs the grabber strip (its `statusBarHeight`
/// is overridden to `grabberContainerHeight` when hosted in a modal —
/// see `AetherNavigationController.updateContainerLayout`), so the
/// chrome reads as a single rounded sheet with its own bar rather than
/// as a navbar grafted onto a separate container.
open class AetherModalNavigationController: AetherModalController {
    /// Internal navigation controller. Exposed for advanced cases where
    /// the caller needs its full surface (minimized container, custom
    /// transitions). Most consumers should use the forwarded methods on
    /// this class instead.
    public let internalNavigationController: AetherNavigationController

    /// Convenience for "the VC at the bottom of the stack" — what a
    /// vanilla `UINavigationController` calls `viewControllers.first`.
    public var rootViewController: AetherViewController? {
        internalNavigationController.viewControllerStack.first
    }

    public var topViewController: AetherViewController? {
        internalNavigationController.topController
    }

    public var viewControllers: [AetherViewController] {
        get { internalNavigationController.viewControllerStack }
        set { internalNavigationController.setViewControllers(newValue, animated: false) }
    }

    /// Initialize an empty navigation stack. Add VCs via `viewControllers`
    /// or `pushViewController` after construction.
    public init(
        config: Config = Config(),
        navigationMode: NavigationControllerMode = .single
    ) {
        self.internalNavigationController = AetherNavigationController(mode: navigationMode)
        super.init(config: config)
        internalNavigationController.view.backgroundColor = .clear
    }

    /// Initialize with a root VC — the navigation controller is seeded
    /// with `[rootViewController]` so `topViewController` / `rootViewController`
    /// are valid the moment `init` returns. Both flavours of init are
    /// `designated`: a subclass `init` can call either as its `super.init`.
    /// (A `convenience` super-init would force an awkward
    /// `self.init(config:)` + `setViewControllers([root])` two-step in
    /// the subclass.)
    public init(
        rootViewController: AetherViewController,
        config: Config = Config(),
        navigationMode: NavigationControllerMode = .single
    ) {
        self.internalNavigationController = AetherNavigationController(mode: navigationMode)
        super.init(config: config)
        internalNavigationController.view.backgroundColor = .clear
        internalNavigationController.setViewControllers([rootViewController], animated: false)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        // Embed the nav inside the content host. Subclass overrides of
        // `viewDidLoad` should always call `super.viewDidLoad()` first
        // so the nav is mounted before they reach for `topViewController`
        // / `viewControllers` to wire footer / scroll / etc.
        embedContent(internalNavigationController)
        // The embed step above loads the nav's view, which loads the
        // root VC's view, which runs its `viewDidLoad`. By this point
        // any lazy-initialized properties on the root (send buttons,
        // scroll views) are set, so we can safely query the
        // `AetherModalContent` protocol for footer / scroll prefs.
        applyRootContentConfiguration()
    }

    private func applyRootContentConfiguration() {
        guard let content = rootViewController as? AetherModalContent else { return }
        if let footer = content.modalFooterView, content.modalFooterHeight > 0 {
            footerView = footer
            footerHeight = content.modalFooterHeight
            footerEdgeFadeHeight = content.modalFooterEdgeFadeHeight
            if let tint = content.modalFooterEdgeTintColor {
                footerEdgeTintColor = tint
            }
            footerEdgeBlurRadius = content.modalFooterEdgeBlurRadius
        }
        if let scroll = content.modalPrimaryScrollView {
            primaryScrollView = scroll
        }
    }

    // MARK: - Forwarded navigation API

    public func pushViewController(_ controller: AetherViewController, animated: Bool = true) {
        internalNavigationController.pushViewController(controller, animated: animated)
    }

    @discardableResult
    public func popViewController(animated: Bool = true) -> AetherViewController? {
        internalNavigationController.popViewController(animated: animated)
    }

    public func popToRoot(animated: Bool = true) {
        internalNavigationController.popToRoot(animated: animated)
    }

    public func setViewControllers(_ viewControllers: [AetherViewController], animated: Bool = true) {
        internalNavigationController.setViewControllers(viewControllers, animated: animated)
    }

    public func replaceTopController(_ controller: AetherViewController, animated: Bool = true) {
        internalNavigationController.replaceTopController(controller, animated: animated)
    }
}
