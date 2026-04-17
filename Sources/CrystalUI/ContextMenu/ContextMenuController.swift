import UIKit

// MARK: - ContextMenuController

/// Presents a `ContextMenuActionsView` with a Telegram / iOS 26 native style
/// morph-in animation rooted at a source view.
///
/// **Architecture (v3, post‑lens experiment).** The earlier lens-based path
/// (`LensTransitionContainer` driving `CASDFGlassDisplacementEffect` keyframes)
/// looked broken in practice because the lens animates internal layers that
/// the menu content never actually rendered into — so the user saw a series
/// of scaled, semi-transparent ghosts and no glass at all. This version
/// drops the lens for the morph and uses a single `UIVisualEffectView`
/// (`UIGlassEffect` on iOS 26+, `UIBlurEffect` fallback) as the visible
/// menu container. The container is sized to the source rect at t=0 and
/// spring-animated to the final menu rect; the actions view fills it via
/// autoresizing so the rows visibly grow with the glass.
public final class ContextMenuController {
    // MARK: - Animation constants

    private static let morphDuration: TimeInterval = 0.5
    private static let morphDamping: CGFloat = 0.78
    private static let dimAlpha: CGFloat = 0.12
    private static let menuSpacing: CGFloat = 10.0
    private static let menuCornerRadius: CGFloat = 27.0

    // MARK: - Self-retention

    private static var presentedControllers: Set<ContextMenuControllerBox> = []
    private lazy var retainBox = ContextMenuControllerBox(controller: self)

    // MARK: - Inputs

    public struct Source {
        /// View the menu will animate out of. Used for position, size and a snapshot.
        public weak var view: UIView?
        /// Optional preferred corner radius of the source; defaults to source.layer.cornerRadius.
        public var cornerRadius: CGFloat?

        public init(view: UIView, cornerRadius: CGFloat? = nil) {
            self.view = view
            self.cornerRadius = cornerRadius
        }
    }

    // MARK: - State

    private let source: Source
    private let items: [ContextMenuItem]
    private let onDismiss: (() -> Void)?

    private weak var hostView: UIView?
    private var dimView: UIView?
    /// Outer glass container that morphs from sourceRect to menuRect. Holds
    /// `actionsView` inside its `contentView`, so corner clipping naturally
    /// applies to the rows too.
    private var menuContainer: UIVisualEffectView?
    private var actionsView: ContextMenuActionsView?
    private var tapRecognizer: UITapGestureRecognizer?

    private var menuFrameInHost: CGRect = .zero
    private var sourceRectInHost: CGRect = .zero
    private var sourceCornerRadius: CGFloat = 0

    private var isPresented: Bool = false
    private var dismissHandle: ContextMenuDismissHandle?

    // MARK: - Init

    public init(source: Source, items: [ContextMenuItem], onDismiss: (() -> Void)? = nil) {
        self.source = source
        self.items = items
        self.onDismiss = onDismiss
    }

    // MARK: - Public entry points

    /// Present the menu as an overlay on the window hosting the source view.
    public func present() {
        guard !isPresented, let source = source.view, let window = source.window else { return }
        isPresented = true
        ContextMenuController.presentedControllers.insert(retainBox)

        let host = UIView(frame: window.bounds)
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(host)
        self.hostView = host

        // Dim layer — sits under everything else AND owns the tap-to-dismiss
        // recognizer. Touches that hit the menu container go to the menu first
        // (it's z-above), so anything that lands on dim is by definition
        // outside the menu.
        let dim = UIView(frame: host.bounds)
        dim.backgroundColor = UIColor.black.withAlphaComponent(ContextMenuController.dimAlpha)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.alpha = 0
        dim.isUserInteractionEnabled = true
        host.addSubview(dim)
        self.dimView = dim

        // Build the actions view to know its preferred size before sizing the
        // glass container.
        let actionsView = ContextMenuActionsView(items: items)
        let maxWidth = min(host.bounds.width - 24.0, ContextMenuActionsView.preferredWidth)
        let menuSize = actionsView.preferredSize(maxWidth: maxWidth)

        let sourceRectInHost = source.convert(source.bounds, to: host)
        let menuFrame = computeMenuFrame(sourceRect: sourceRectInHost, menuSize: menuSize, hostBounds: host.bounds)
        let sourceCornerRadius = self.source.cornerRadius ?? source.layer.cornerRadius
        self.menuFrameInHost = menuFrame
        self.sourceRectInHost = sourceRectInHost
        self.sourceCornerRadius = sourceCornerRadius

        // Glass menu container — UIVisualEffectView with UIGlassEffect on
        // iOS 26+, otherwise systemMaterial UIBlurEffect. The container starts
        // sized + cornered like the source button so the morph reads as
        // "button expands into menu".
        let menuContainer = UIVisualEffectView(effect: ContextMenuController.makeMenuEffect(isDark: source.traitCollection.userInterfaceStyle == .dark))
        menuContainer.frame = sourceRectInHost
        menuContainer.layer.cornerRadius = sourceCornerRadius
        menuContainer.layer.masksToBounds = true
        if #available(iOS 13.0, *) {
            menuContainer.layer.cornerCurve = .continuous
        }
        host.addSubview(menuContainer)
        self.menuContainer = menuContainer

        // Actions fill the container; auto-resize as the container morphs.
        actionsView.frame = menuContainer.bounds
        actionsView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        menuContainer.contentView.addSubview(actionsView)
        self.actionsView = actionsView

        // Tap-outside to dismiss.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        dim.addGestureRecognizer(tap)
        self.tapRecognizer = tap

        // Wire up the actions.
        let handle = ContextMenuDismissHandle(dismiss: { [weak self] animated in self?.dismiss(animated: animated) })
        self.dismissHandle = handle
        actionsView.onActionSelected = { [weak self] actionItem in
            guard let self else { return }
            let shouldAutoDismiss = actionItem.action == nil
            actionItem.action?(actionItem, handle)
            if shouldAutoDismiss { self.dismiss(animated: true) }
        }

        // Haptic.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // IMPORTANT: do NOT hide the source view. It lives inside the navbar
        // (or another collection) where hiding it would collapse the layout
        // and shift its siblings. Instead, the menu container starts at the
        // source's exact rect and corner radius, perfectly overlapping the
        // source. To the user this reads as the button itself "expanding"
        // into the menu — no disappear, no layout shift.

        animateIn(host: host, dim: dim, menuContainer: menuContainer, actionsView: actionsView)
    }

    public func dismiss(animated: Bool = true) {
        guard isPresented else { return }
        isPresented = false

        let host = hostView
        let dim = dimView
        let menuContainer = self.menuContainer
        let actionsView = self.actionsView
        let sourceView = source.view
        let sourceRect: CGRect
        if let sourceView, let host {
            sourceRect = sourceView.convert(sourceView.bounds, to: host)
        } else {
            sourceRect = self.sourceRectInHost
        }

        var didClean = false
        let cleanup: () -> Void = { [weak self] in
            if didClean { return }
            didClean = true
            dim?.removeFromSuperview()
            menuContainer?.removeFromSuperview()
            actionsView?.removeFromSuperview()
            host?.removeFromSuperview()
            self?.hostView = nil
            self?.dimView = nil
            self?.menuContainer = nil
            self?.actionsView = nil
            self?.onDismiss?()
            // Drop the self-retain — last reference, controller deallocates next.
            if let strongSelf = self {
                ContextMenuController.presentedControllers.remove(strongSelf.retainBox)
            }
        }

        guard animated, let menuContainer else { cleanup(); return }

        // Reverse morph: spring container back to source rect with shrinking
        // corner radius + alpha decay. Dim fades in parallel.
        let radiusAnim = CABasicAnimation(keyPath: "cornerRadius")
        radiusAnim.fromValue = menuContainer.layer.cornerRadius
        radiusAnim.toValue = sourceCornerRadius
        radiusAnim.duration = ContextMenuController.morphDuration * 0.6
        radiusAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        menuContainer.layer.cornerRadius = sourceCornerRadius
        menuContainer.layer.add(radiusAnim, forKey: "cornerRadius")

        UIView.animate(
            withDuration: ContextMenuController.morphDuration * 0.6,
            delay: 0,
            usingSpringWithDamping: 0.95,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                menuContainer.frame = sourceRect
                menuContainer.alpha = 0.0
                dim?.alpha = 0.0
                actionsView?.alpha = 0.0
            },
            completion: { _ in cleanup() }
        )

        // Defensive timer in case the animation completion is starved.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { cleanup() }
    }

    // MARK: - Animate in

    private func animateIn(
        host: UIView,
        dim: UIView,
        menuContainer: UIVisualEffectView,
        actionsView: ContextMenuActionsView
    ) {
        // 1) Dim fades in quickly.
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut], animations: {
            dim.alpha = 1.0
        })

        // 2) Spring the menu container from source rect → menu rect, plus
        // cornerRadius from sourceCornerRadius → menuCornerRadius. This is
        // the visible morph: the glass surface grows out of the source button.
        let radiusAnim = CABasicAnimation(keyPath: "cornerRadius")
        radiusAnim.fromValue = sourceCornerRadius
        radiusAnim.toValue = ContextMenuActionsView.cornerRadius
        radiusAnim.duration = ContextMenuController.morphDuration
        radiusAnim.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0.4, 1.0)
        menuContainer.layer.cornerRadius = ContextMenuActionsView.cornerRadius
        menuContainer.layer.add(radiusAnim, forKey: "cornerRadius")

        UIView.animate(
            withDuration: ContextMenuController.morphDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.morphDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                menuContainer.frame = self.menuFrameInHost
            },
            completion: nil
        )
    }

    // MARK: - Effect builder

    private static func makeMenuEffect(isDark: Bool) -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            return UIGlassEffect(style: .regular)
        }
        return UIBlurEffect(style: isDark ? .systemMaterialDark : .systemMaterialLight)
    }

    // MARK: - Menu placement

    private func computeMenuFrame(sourceRect: CGRect, menuSize: CGSize, hostBounds: CGRect) -> CGRect {
        let sideInset: CGFloat = 12.0
        let window = source.view?.window
        let safeTop: CGFloat = max(window?.safeAreaInsets.top ?? hostView?.safeAreaInsets.top ?? 0.0, 12.0)
        let safeBottom: CGFloat = max(window?.safeAreaInsets.bottom ?? hostView?.safeAreaInsets.bottom ?? 0.0, 12.0)

        var x = sourceRect.minX
        if x + menuSize.width > hostBounds.maxX - sideInset {
            x = hostBounds.maxX - sideInset - menuSize.width
        }
        x = max(sideInset, x)

        var y = sourceRect.maxY + ContextMenuController.menuSpacing
        if y + menuSize.height > hostBounds.maxY - safeBottom {
            let above = sourceRect.minY - ContextMenuController.menuSpacing - menuSize.height
            if above >= safeTop {
                y = above
            } else {
                y = hostBounds.maxY - safeBottom - menuSize.height
            }
        }

        return CGRect(x: x, y: y, width: menuSize.width, height: menuSize.height)
    }

    // MARK: - Gestures

    @objc private func handleBackgroundTap(_ recognizer: UITapGestureRecognizer) {
        dismiss()
    }
}

// MARK: - Presentation convenience

public extension ContextMenuController {
    @discardableResult
    static func present(
        source: UIView,
        cornerRadius: CGFloat? = nil,
        items: [ContextMenuItem],
        onDismiss: (() -> Void)? = nil
    ) -> ContextMenuController {
        let controller = ContextMenuController(
            source: Source(view: source, cornerRadius: cornerRadius),
            items: items,
            onDismiss: onDismiss
        )
        controller.present()
        return controller
    }
}

// MARK: - Self-retain box

private final class ContextMenuControllerBox: Hashable {
    let controller: ContextMenuController

    init(controller: ContextMenuController) {
        self.controller = controller
    }

    static func == (lhs: ContextMenuControllerBox, rhs: ContextMenuControllerBox) -> Bool {
        return lhs.controller === rhs.controller
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(controller))
    }
}
