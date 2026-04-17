import UIKit

// MARK: - ContextMenuController

/// Presents a `ContextMenuActionsView` with a Telegram-style morph-in
/// animation rooted at a source view.
///
/// The morph itself is handled by `LensTransitionContainer` — a port of
/// Telegram's iOS-26 SDF lens container that drives the actual
/// `CASDFGlassDisplacementEffect` filter chain. On older systems the lens
/// degrades to a no-op container and the menu animates in with a
/// straightforward spring scale + alpha; the interaction model stays
/// identical.
///
/// The controller presents itself as a transparent, full-screen overlay
/// view attached to the source window so it covers navigation bars and the
/// status bar without needing a separate window.
public final class ContextMenuController {
    // MARK: - Animation constants (mirror ContextControllerExtractedPresentationNode)

    private static let lensDuration: TimeInterval = 0.5
    private static let dimAlpha: CGFloat = 0.12
    private static let menuSpacing: CGFloat = 10.0
    private static let menuCornerRadius: CGFloat = 27.0

    /// Rubber-band stretch metrics for the WHOLE menu container (the lens),
    /// not just the inner rows. The lens leans toward the touch point with a
    /// fraction of the touch's offset from menu center, plus a small press
    /// scale-up — the same trick `UIGlassEffect` does for navbar buttons.
    private static let stretchFollow: CGFloat = 0.06
    private static let pressScale: CGFloat = 1.012

    // MARK: - Self-retention
    //
    // Callers store the returned `ContextMenuController` in a `weak` ivar by
    // convention (it doesn't make sense to keep a context menu around longer
    // than its presentation lifetime). To survive long enough to handle
    // dismissal taps, the controller adds itself to this set on `present()`
    // and removes itself once `dismiss()` has finished cleanup.
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
    private var lensContainer: LensTransitionContainer?
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

        // Dim layer — sits under everything else, AND owns the tap-to-dismiss
        // handler. Anything inside the lens (= the menu) intercepts touches
        // before they reach dim, so a tap on dim by definition lives outside
        // the menu rect.
        let dim = UIView(frame: host.bounds)
        dim.backgroundColor = UIColor.black.withAlphaComponent(ContextMenuController.dimAlpha)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.alpha = 0
        dim.isUserInteractionEnabled = true
        host.addSubview(dim)
        self.dimView = dim

        // Build the actions view to know its preferred size before placing the lens.
        let actionsView = ContextMenuActionsView(items: items)
        let maxWidth = min(host.bounds.width - 24.0, ContextMenuActionsView.preferredWidth)
        let menuSize = actionsView.preferredSize(maxWidth: maxWidth)

        let sourceRectInHost = source.convert(source.bounds, to: host)
        let menuFrame = computeMenuFrame(sourceRect: sourceRectInHost, menuSize: menuSize, hostBounds: host.bounds)
        self.menuFrameInHost = menuFrame
        self.sourceRectInHost = sourceRectInHost
        self.sourceCornerRadius = self.source.cornerRadius ?? source.layer.cornerRadius

        // Lens container is sized to the final menu rect — that's what Telegram
        // does so the SDF keyframes work in lens-local coords. The lens does
        // not clip, so the morphing blob can extend beyond the menu rect (e.g.
        // up to the source button) without being cut off.
        let lensEffectView = LensEffectView(contentView: nil)
        lensEffectView.updateAppearance(isDark: source.traitCollection.userInterfaceStyle == .dark)
        let lens = LensTransitionContainer(effectView: lensEffectView)
        lens.frame = menuFrame
        host.addSubview(lens)
        self.lensContainer = lens

        // Lens internal layout — model values that the keyframes settle back to.
        lens.update(
            size: menuFrame.size,
            cornerRadius: ContextMenuActionsView.cornerRadius,
            isDark: source.traitCollection.userInterfaceStyle == .dark,
            transition: .immediate
        )

        // Place the actions inside the lens contentsView in local coords.
        actionsView.frame = CGRect(origin: .zero, size: menuFrame.size)
        lens.contentsView.addSubview(actionsView)
        self.actionsView = actionsView

        // Tap-outside to dismiss — attached to dim so it only fires when the
        // touch missed the lens. (Touches inside the lens are intercepted by
        // the lens / actions view earlier in the hit-test chain and never
        // reach dim.)
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

        // Stretch the WHOLE lens container (= the entire menu chrome including
        // its glass surface) toward the active touch. The actionsView reports
        // the touch in its own coords; we apply the transform on the lens.
        actionsView.onStretchUpdate = { [weak self, weak lens, weak actionsView] point in
            guard let self, let lens, let actionsView else { return }
            self.applyStretch(toLens: lens, touchInActions: point, actionsBounds: actionsView.bounds, animated: false)
        }
        actionsView.onStretchRelease = { [weak self, weak lens] in
            guard let self, let lens else { return }
            self.releaseStretch(onLens: lens)
        }

        // Haptic.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Capture the source snapshot while it's still visible.
        let sourceSnapshot = makeSourceSnapshot(source: source)

        // Smoothly fade the source button instead of snapping it invisible.
        // Sync timing with the lens's source-effect-view fade (which runs its
        // own 0.2s setTransitionFraction inside animateIn) so the original
        // button and the lens's snapshot fade as a single unit — visually the
        // button "unfolds" into the morphing menu instead of disappearing
        // before the morph starts.
        // Important: we still keep the source in layout — only `alpha`
        // changes, never `isHidden`, so the navbar's GlassControlGroup (or
        // whichever collection the source lives in) doesn't reflow.
        UIView.animate(
            withDuration: 0.2, delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: { source.alpha = 0.0 },
            completion: nil
        )

        animateIn(
            host: host,
            dim: dim,
            lens: lens,
            actionsView: actionsView,
            source: source,
            sourceSnapshot: sourceSnapshot
        )
    }

    public func dismiss(animated: Bool = true) {
        guard isPresented else { return }
        isPresented = false

        let host = hostView
        let dim = dimView
        let lens = lensContainer
        let actionsView = self.actionsView
        let sourceView = source.view
        let sourceRect: CGRect
        if let sourceView, let host { sourceRect = sourceView.convert(sourceView.bounds, to: host) }
        else { sourceRect = self.sourceRectInHost }

        // `cleanup` is reentrancy-guarded with a token so the timeout fallback
        // and the UIView.animate completion can't both run it.
        var didClean = false
        let cleanup: () -> Void = { [weak self] in
            if didClean { return }
            didClean = true
            // Snap the source back to fully visible — by the time cleanup
            // runs the dismiss animation has already faded the source-effect
            // view to invisible, so popping the original button to alpha 1
            // is invisible to the user.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sourceView?.alpha = 1.0
            CATransaction.commit()
            dim?.removeFromSuperview()
            lens?.removeFromSuperview()
            actionsView?.removeFromSuperview()
            host?.removeFromSuperview()
            self?.hostView = nil
            self?.dimView = nil
            self?.lensContainer = nil
            self?.actionsView = nil
            self?.onDismiss?()
            // Drop the self-retain — last reference, controller deallocates next.
            if let strongSelf = self {
                ContextMenuController.presentedControllers.remove(strongSelf.retainBox)
            }
        }

        // Fade the source back in over the morph-out so the button visibly
        // re-materialises in sync with the menu shrinking. Total morph-out is
        // ~0.32s; ramp source.alpha 0→1 over the tail of it.
        if let sourceView {
            UIView.animate(
                withDuration: 0.22, delay: 0.05,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: { sourceView.alpha = 1.0 },
                completion: nil
            )
        }

        guard animated, let lens, let sourceView else { cleanup(); return }

        // Drive the lens out: a fresh source effect view (with the current source
        // snapshot) is what the lens animates toward. Source is currently at
        // alpha 0 — temporarily restore it so snapshotView captures real pixels.
        let savedAlpha = sourceView.alpha
        sourceView.alpha = 1.0
        let sourceSnapshotView = makeSourceSnapshot(source: sourceView)
        sourceView.alpha = savedAlpha
        let sourceEffectView = LensEffectView(contentView: sourceSnapshotView)
        sourceEffectView.updateAppearance(isDark: sourceView.traitCollection.userInterfaceStyle == .dark)

        let fromRectInLens = CGRect(origin: .zero, size: menuFrameInHost.size)
        let toRectInLens = sourceRect.offsetBy(dx: -menuFrameInHost.minX, dy: -menuFrameInHost.minY)
        lens.animateOut(
            fromRect: fromRectInLens,
            toRect: toRectInLens,
            fromCornerRadius: ContextMenuActionsView.cornerRadius,
            toCornerRadius: sourceCornerRadius,
            isDark: sourceView.traitCollection.userInterfaceStyle == .dark,
            sourceEffectView: sourceEffectView
        )

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn], animations: {
            dim?.alpha = 0.0
            actionsView?.alpha = 0.0
        }, completion: { _ in cleanup() })

        // Defensive timer: even if the alpha animation's completion is starved
        // (interrupted by a higher-priority animation, app backgrounded, etc.),
        // the menu still tears down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { cleanup() }
    }

    // MARK: - Animate in

    private func animateIn(
        host: UIView,
        dim: UIView,
        lens: LensTransitionContainer,
        actionsView: ContextMenuActionsView,
        source: UIView,
        sourceSnapshot: UIView
    ) {
        // 1) Dim fades in quickly.
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut], animations: {
            dim.alpha = 1.0
        })

        // 2) Wrap the pre-captured snapshot in a lens effect view; the lens
        // internally positions / sizes / blurs this view via baked SDF keyframes.
        let sourceEffectView = LensEffectView(contentView: sourceSnapshot)
        sourceEffectView.updateAppearance(isDark: source.traitCollection.userInterfaceStyle == .dark)

        // 3) Hand off to the lens. fromRect / toRect must be in the lens
        // container's own coordinate space — Telegram does this by offsetting
        // the source rect by `-actionsContainerNode.frame.minX/.minY`.
        let fromRectInLens = sourceRectInHost.offsetBy(dx: -menuFrameInHost.minX, dy: -menuFrameInHost.minY)
        let toRectInLens = CGRect(origin: .zero, size: menuFrameInHost.size)
        lens.animateIn(
            fromRect: fromRectInLens,
            toRect: toRectInLens,
            fromCornerRadius: sourceCornerRadius,
            toCornerRadius: ContextMenuActionsView.cornerRadius,
            isDark: source.traitCollection.userInterfaceStyle == .dark,
            sourceEffectView: sourceEffectView
        )

        // 4) The lens already animates its `contentsView.layer` alpha 0→1 over
        // 0.15s on the iOS-26 path (and the fallback impl drives the glass
        // alpha for us too). DO NOT gate the actions view with a separate
        // alpha — that used to leave the morph completely transparent until
        // 0.16s, hiding the lens-glass effect entirely.
        actionsView.alpha = 1.0
    }

    // MARK: - Source snapshot

    /// Captures the source view as a UIView (snapshotView preferred for live
    /// content; falls back to a rasterised image if snapshotting fails — e.g.
    /// for views containing UIVisualEffectView pipelines that can't snapshot
    /// natively).
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

    private func computeMenuFrame(sourceRect: CGRect, menuSize: CGSize, hostBounds: CGRect) -> CGRect {
        let sideInset: CGFloat = 12.0
        // Prefer the hosting window's insets — the freshly-attached host view
        // hasn't been laid out yet so its safeAreaInsets are still zero.
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
        // Recognizer lives on the dim view, which only receives touches that
        // missed the lens. Therefore any fired tap is always outside the menu.
        dismiss()
    }

    // MARK: - Rubber-band stretch (applied to the whole lens container)

    private func applyStretch(toLens lens: LensTransitionContainer, touchInActions point: CGPoint, actionsBounds: CGRect, animated: Bool) {
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
                animations: { lens.transform = target },
                completion: nil
            )
        } else {
            // During an active drag, follow the finger directly so it feels
            // physical — spring resampling on every move event would feel laggy.
            lens.transform = target
        }
    }

    private func releaseStretch(onLens lens: LensTransitionContainer) {
        UIView.animate(
            withDuration: 0.42, delay: 0,
            usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: { lens.transform = .identity },
            completion: nil
        )
    }
}

// MARK: - Presentation convenience

public extension ContextMenuController {
    /// Convenience entry point: present a menu out of `source`, wiring in the
    /// standard lifecycle. Returns the controller so callers can dismiss it
    /// programmatically if needed.
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

/// Wrapper that gives a `ContextMenuController` value-style identity inside a
/// `Set` while strongly retaining it. Equality / hashing are reference-based
/// so two boxes for the same controller collapse to a single entry.
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
