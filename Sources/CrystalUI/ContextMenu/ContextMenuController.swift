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
    private static let dimAlpha: CGFloat = 0.22
    private static let menuSpacing: CGFloat = 10.0

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

        let host = UIView(frame: window.bounds)
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(host)
        self.hostView = host

        // Dim layer — sits under everything else.
        let dim = UIView(frame: host.bounds)
        dim.backgroundColor = UIColor.black.withAlphaComponent(ContextMenuController.dimAlpha)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.alpha = 0
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

        // Tap-outside to dismiss.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        tap.cancelsTouchesInView = false
        host.addGestureRecognizer(tap)
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

        // Hide the source so it doesn't fight the lens's source effect view.
        source.isHidden = true

        animateIn(host: host, dim: dim, lens: lens, actionsView: actionsView, source: source)
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

        let cleanup: () -> Void = { [weak self] in
            sourceView?.isHidden = false
            dim?.removeFromSuperview()
            lens?.removeFromSuperview()
            actionsView?.removeFromSuperview()
            host?.removeFromSuperview()
            self?.hostView = nil
            self?.dimView = nil
            self?.lensContainer = nil
            self?.actionsView = nil
            self?.onDismiss?()
        }

        guard animated, let lens, let sourceView else { cleanup(); return }

        // Drive the lens out: a fresh source effect view (with the current source
        // snapshot) is what the lens animates toward.
        let sourceSnapshotView = makeSourceSnapshot(source: sourceView)
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
    }

    // MARK: - Animate in

    private func animateIn(
        host: UIView,
        dim: UIView,
        lens: LensTransitionContainer,
        actionsView: ContextMenuActionsView,
        source: UIView
    ) {
        // 1) Dim fades in quickly.
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut], animations: {
            dim.alpha = 1.0
        })

        // 2) Build the source effect view: a snapshot wrapped in a glass effect
        // that the lens will absorb during the morph. The lens internally
        // positions / sizes / blurs this view via baked SDF keyframes.
        let sourceSnapshotView = makeSourceSnapshot(source: source)
        let sourceEffectView = LensEffectView(contentView: sourceSnapshotView)
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

        // 4) Cosmetic actions fade-in over the lens (the actions view is parked
        // at the menu rect and just needs to become visible once the morph
        // starts settling). The lens itself drives the glass surface morph.
        actionsView.alpha = 0.0
        UIView.animate(withDuration: 0.18, delay: 0.16, options: [.curveEaseOut], animations: {
            actionsView.alpha = 1.0
        })
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
        guard let host = hostView else { dismiss(); return }
        let location = recognizer.location(in: host)
        // actionsView lives inside the lens.contentsView; the menu rect in
        // host coordinates is the lens container's frame.
        if !menuFrameInHost.contains(location) {
            dismiss()
        }
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
