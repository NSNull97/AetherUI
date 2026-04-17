import UIKit

// MARK: - ContextMenuController

/// Presents a `ContextMenuActionsView` with a single-container morph: a
/// `UIVisualEffectView` (UIGlassEffect on iOS 26+, UIBlurEffect fallback)
/// starts sized + cornered like the source button, springs to the menu
/// rect + corner radius, and inside cross-fades a snapshot of the source
/// over to the actions view. Visually the button literally "unfolds" —
/// its glass surface expands into the menu and its content is swapped
/// with the menu rows in one unified animation.
///
/// `LensTransitionContainer` is still in the codebase (it powers the more
/// complex SDF-displacement morph used by Telegram's ContextController),
/// but for context menus opened from glass nav-bar buttons the unified
/// container morph reads cleaner — no separate snapshot floating outside
/// the morphing entity, no double-glass overlap.
public final class ContextMenuController {
    // MARK: - Animation constants

    private static let morphDuration: TimeInterval = 0.5
    private static let morphDamping: CGFloat = 0.78
    private static let dismissDuration: TimeInterval = 0.36
    private static let dismissDamping: CGFloat = 0.95
    private static let dimAlpha: CGFloat = 0.12
    private static let menuCornerRadius: CGFloat = 27.0

    /// Rubber-band stretch metrics for the WHOLE menu container.
    private static let stretchFollow: CGFloat = 0.06
    private static let pressScale: CGFloat = 1.012

    // MARK: - Self-retention

    private static var presentedControllers: Set<ContextMenuControllerBox> = []
    private lazy var retainBox = ContextMenuControllerBox(controller: self)

    // MARK: - Inputs

    public struct Source {
        public weak var view: UIView?
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
    private var menuContainer: UIVisualEffectView?
    private var snapshotView: UIView?
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

        // Dim layer + tap-to-dismiss target.
        let dim = UIView(frame: host.bounds)
        dim.backgroundColor = UIColor.black.withAlphaComponent(ContextMenuController.dimAlpha)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.alpha = 0
        dim.isUserInteractionEnabled = true
        host.addSubview(dim)
        self.dimView = dim

        // Compute menu metrics.
        let actionsView = ContextMenuActionsView(items: items)
        let maxWidth = min(host.bounds.width - 24.0, ContextMenuActionsView.preferredWidth)
        let menuSize = actionsView.preferredSize(maxWidth: maxWidth)
        let sourceRectInHost = source.convert(source.bounds, to: host)
        let menuFrame = computeMenuFrame(sourceRect: sourceRectInHost, menuSize: menuSize, hostBounds: host.bounds)
        let sourceCornerRadius = self.source.cornerRadius ?? source.layer.cornerRadius
        self.menuFrameInHost = menuFrame
        self.sourceRectInHost = sourceRectInHost
        self.sourceCornerRadius = sourceCornerRadius

        // SINGLE morphing container: one glass surface that starts as the
        // button's shape (sourceRect + sourceCornerRadius) and animates to
        // the menu's shape (menuFrame + menuCornerRadius). No external lens,
        // no separate source-effect-view — everything lives inside this one
        // entity, so the morph reads as a single unfolding action.
        let menuContainer = UIVisualEffectView(effect: ContextMenuController.makeMenuEffect(
            isDark: source.traitCollection.userInterfaceStyle == .dark
        ))
        menuContainer.frame = sourceRectInHost
        menuContainer.layer.cornerRadius = sourceCornerRadius
        menuContainer.layer.masksToBounds = true
        if #available(iOS 13.0, *) {
            menuContainer.layer.cornerCurve = .continuous
        }
        host.addSubview(menuContainer)
        self.menuContainer = menuContainer

        // Capture the source button's pixels BEFORE we hide it. The snapshot
        // sits at top-left of the container at source size — at t=0 it
        // perfectly overlaps the source's screen position so the user sees
        // "the button" inside the morphing container even though the original
        // is alpha 0. As the container grows, the snapshot stays at top-left
        // (= same screen position as the original button) and cross-fades to
        // the menu content.
        let snapshot = makeSourceSnapshot(source: source)
        snapshot.frame = CGRect(origin: .zero, size: sourceRectInHost.size)
        snapshot.autoresizingMask = []
        menuContainer.contentView.addSubview(snapshot)
        self.snapshotView = snapshot

        // Actions view sized to the FINAL menu rect, also at top-left.
        // Initially clipped (container is still source-sized) and alpha 0
        // so only the snapshot is visible. As the container grows, more of
        // the actions becomes visible behind the fading snapshot.
        actionsView.frame = CGRect(origin: .zero, size: menuFrame.size)
        actionsView.autoresizingMask = []
        actionsView.alpha = 0.0
        menuContainer.contentView.addSubview(actionsView)
        self.actionsView = actionsView

        // Tap-outside to dismiss.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        dim.addGestureRecognizer(tap)
        self.tapRecognizer = tap

        // Wire actions.
        let handle = ContextMenuDismissHandle(dismiss: { [weak self] animated in self?.dismiss(animated: animated) })
        self.dismissHandle = handle
        actionsView.onActionSelected = { [weak self] actionItem in
            guard let self else { return }
            let shouldAutoDismiss = actionItem.action == nil
            actionItem.action?(actionItem, handle)
            if shouldAutoDismiss { self.dismiss(animated: true) }
        }

        // Stretch the WHOLE menu container toward active touch.
        actionsView.onStretchUpdate = { [weak self, weak menuContainer, weak actionsView] point in
            guard let self, let menuContainer, let actionsView else { return }
            self.applyStretch(toContainer: menuContainer, touchInActions: point, actionsBounds: actionsView.bounds, animated: false)
        }
        actionsView.onStretchRelease = { [weak self, weak menuContainer] in
            guard let self, let menuContainer else { return }
            self.releaseStretch(onContainer: menuContainer)
        }

        // Haptic.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Hide source INSTANTLY — the snapshot is now at the same screen
        // position with the same shape, so visually the button is "still
        // there" but it's actually inside the morphing container.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        source.alpha = 0.0
        CATransaction.commit()
        CATransaction.flush()

        animateIn(dim: dim, container: menuContainer, snapshot: snapshot, actionsView: actionsView)
    }

    public func dismiss(animated: Bool = true) {
        guard isPresented else { return }
        isPresented = false

        let host = hostView
        let dim = dimView
        let container = menuContainer
        let snapshot = snapshotView
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
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sourceView?.alpha = 1.0
            CATransaction.commit()
            dim?.removeFromSuperview()
            container?.removeFromSuperview()
            actionsView?.removeFromSuperview()
            snapshot?.removeFromSuperview()
            host?.removeFromSuperview()
            self?.hostView = nil
            self?.dimView = nil
            self?.menuContainer = nil
            self?.snapshotView = nil
            self?.actionsView = nil
            self?.onDismiss?()
            if let strongSelf = self {
                ContextMenuController.presentedControllers.remove(strongSelf.retainBox)
            }
        }

        guard animated, let container else { cleanup(); return }

        // Reverse: container shrinks back to source rect + corner, actions
        // fade out, snapshot fades back in so the final visible thing at
        // sourceRect is identical to the original source button.
        let radiusAnim = CABasicAnimation(keyPath: "cornerRadius")
        radiusAnim.fromValue = container.layer.cornerRadius
        radiusAnim.toValue = sourceCornerRadius
        radiusAnim.duration = ContextMenuController.dismissDuration
        radiusAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        container.layer.cornerRadius = sourceCornerRadius
        container.layer.add(radiusAnim, forKey: "cornerRadius")

        UIView.animate(
            withDuration: ContextMenuController.dismissDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.dismissDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                container.frame = sourceRect
                container.transform = .identity
                dim?.alpha = 0.0
            },
            completion: { _ in cleanup() }
        )

        UIView.animate(
            withDuration: ContextMenuController.dismissDuration * 0.4,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState],
            animations: { actionsView?.alpha = 0.0 },
            completion: nil
        )
        UIView.animate(
            withDuration: ContextMenuController.dismissDuration * 0.6,
            delay: ContextMenuController.dismissDuration * 0.2,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: { snapshot?.alpha = 1.0 },
            completion: nil
        )

        // Defensive cleanup timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + ContextMenuController.dismissDuration + 0.2) { cleanup() }
    }

    // MARK: - Animate in

    private func animateIn(dim: UIView, container: UIVisualEffectView, snapshot: UIView, actionsView: ContextMenuActionsView) {
        // 1) Dim fades in.
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut], animations: {
            dim.alpha = 1.0
        })

        // 2) Container morphs from source rect → menu rect with spring.
        // CornerRadius animates via CABasicAnimation on the same curve.
        let radiusAnim = CABasicAnimation(keyPath: "cornerRadius")
        radiusAnim.fromValue = sourceCornerRadius
        radiusAnim.toValue = ContextMenuActionsView.cornerRadius
        radiusAnim.duration = ContextMenuController.morphDuration
        radiusAnim.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0.4, 1.0)
        container.layer.cornerRadius = ContextMenuActionsView.cornerRadius
        container.layer.add(radiusAnim, forKey: "cornerRadius")

        UIView.animate(
            withDuration: ContextMenuController.morphDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.morphDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                container.frame = self.menuFrameInHost
            },
            completion: nil
        )

        // 3) Cross-fade snapshot → actions view.
        // Snapshot fades out fast (most of it gone in the first ~30% of morph)
        // so by the time the container is large enough to look "menu-like",
        // the actions content has taken over.
        UIView.animate(
            withDuration: ContextMenuController.morphDuration * 0.35,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState],
            animations: { snapshot.alpha = 0.0 },
            completion: nil
        )
        UIView.animate(
            withDuration: ContextMenuController.morphDuration * 0.5,
            delay: ContextMenuController.morphDuration * 0.25,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: { actionsView.alpha = 1.0 },
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

    // MARK: - Source snapshot

    private func makeSourceSnapshot(source: UIView) -> UIView {
        if let snap = source.snapshotView(afterScreenUpdates: false) {
            snap.frame = CGRect(origin: .zero, size: source.bounds.size)
            return snap
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: source.bounds, format: format).image { _ in
            source.drawHierarchy(in: source.bounds, afterScreenUpdates: true)
        }
        let view = UIImageView(image: image)
        view.frame = CGRect(origin: .zero, size: source.bounds.size)
        return view
    }

    // MARK: - Menu placement

    /// Top-anchored: menu's top edge = source's top edge so the morph
    /// visibly grows downward + outward FROM the button rather than
    /// appearing below it with a gap.
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

        var y = sourceRect.minY
        if y + menuSize.height > hostBounds.maxY - safeBottom {
            let upward = sourceRect.maxY - menuSize.height
            if upward >= safeTop {
                y = upward
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

    // MARK: - Rubber-band stretch

    private func applyStretch(toContainer container: UIView, touchInActions point: CGPoint, actionsBounds: CGRect, animated: Bool) {
        let center = CGPoint(x: actionsBounds.midX, y: actionsBounds.midY)
        let delta = CGPoint(x: point.x - center.x, y: point.y - center.y)
        let target = CGAffineTransform(
            translationX: delta.x * ContextMenuController.stretchFollow,
            y: delta.y * ContextMenuController.stretchFollow
        ).scaledBy(x: ContextMenuController.pressScale, y: ContextMenuController.pressScale)

        if animated {
            UIView.animate(
                withDuration: 0.28, delay: 0,
                usingSpringWithDamping: 0.78, initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: { container.transform = target },
                completion: nil
            )
        } else {
            container.transform = target
        }
    }

    private func releaseStretch(onContainer container: UIView) {
        UIView.animate(
            withDuration: 0.42, delay: 0,
            usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: { container.transform = .identity },
            completion: nil
        )
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
