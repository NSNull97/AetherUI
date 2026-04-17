import UIKit

// MARK: - ContextMenuController

/// Port-inspired controller that presents a `ContextMenuActionsView` with a
/// Telegram-style morph-in animation rooted at a source view.
///
/// Unlike Telegram's full `ContextController` (reactions, preview nodes, paged
/// action stacks, Metal lens transitions), this implementation focuses on the
/// visual vocabulary you see when pressing a glass nav-bar button:
///   - dimmed backdrop that fades in,
///   - a "ghost" snapshot of the source button lifted out of its origin,
///   - a blurred transition over the growing menu during the first ~250ms,
///   - a spring-scaled menu anchored at the source's edge,
///   - reverse of the same on dismissal.
///
/// The controller presents itself as a transparent, full-screen overlay view
/// attached to the source window so it covers navigation bars and the status
/// bar without needing a separate window.
public final class ContextMenuController {
    // MARK: - Animation constants (mirror ContextControllerExtractedPresentationNode)

    private static let springDuration: TimeInterval = 0.42
    private static let springDamping: CGFloat = 0.78          // maps Telegram's 104 spring to UIKit parameterisation
    private static let dimAlpha: CGFloat = 0.22
    private static let menuSpacing: CGFloat = 10.0            // distance between source button and menu
    private static let ghostBlurDuration: TimeInterval = 0.22 // snapshot blur clears within this window

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
    private var ghostView: UIView?
    private var ghostBlurredImageView: UIImageView?
    private var actionsView: ContextMenuActionsView?
    private var tapRecognizer: UITapGestureRecognizer?

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

        // Actions container.
        let actionsView = ContextMenuActionsView(items: items)
        host.addSubview(actionsView)
        let maxWidth = min(host.bounds.width - 24.0, ContextMenuActionsView.preferredWidth)
        let menuSize = actionsView.preferredSize(maxWidth: maxWidth)

        let sourceRectInHost = source.convert(source.bounds, to: host)
        let menuFrame = computeMenuFrame(sourceRect: sourceRectInHost, menuSize: menuSize, hostBounds: host.bounds)
        actionsView.frame = menuFrame
        self.actionsView = actionsView

        // Ghost: a snapshot of the source view that will morph from source rect → menu rect.
        let ghost = buildGhostView(source: source, hostBounds: host.bounds, sourceRectInHost: sourceRectInHost)
        host.insertSubview(ghost, belowSubview: actionsView)
        self.ghostView = ghost

        // Tap-outside to dismiss. `cancelsTouchesInView = false` so taps inside
        // the menu still hit the row button's touchUpInside.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        tap.cancelsTouchesInView = false
        host.addGestureRecognizer(tap)
        self.tapRecognizer = tap

        // Wire the actions.
        let handle = ContextMenuDismissHandle(dismiss: { [weak self] animated in self?.dismiss(animated: animated) })
        self.dismissHandle = handle
        actionsView.onActionSelected = { [weak self] actionItem in
            guard let self else { return }
            let shouldAutoDismiss = actionItem.action == nil
            actionItem.action?(actionItem, handle)
            if shouldAutoDismiss { self.dismiss(animated: true) }
        }

        // Haptic.
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()

        // Hide the source so only the ghost is visible while animating.
        source.isHidden = true

        animateIn(
            host: host,
            dim: dim,
            ghost: ghost,
            actionsView: actionsView,
            sourceRectInHost: sourceRectInHost,
            menuFrame: menuFrame
        )
    }

    public func dismiss(animated: Bool = true) {
        guard isPresented else { return }
        isPresented = false

        let host = hostView
        let dim = dimView
        let ghost = ghostView
        let ghostBlur = ghostBlurredImageView
        let actionsView = self.actionsView
        let sourceView = source.view

        let sourceRectInHost: CGRect
        if let sourceView, let host { sourceRectInHost = sourceView.convert(sourceView.bounds, to: host) }
        else if let ghost { sourceRectInHost = ghost.frame }
        else { sourceRectInHost = .zero }

        let cleanup: () -> Void = { [weak self] in
            sourceView?.isHidden = false
            dim?.removeFromSuperview()
            ghost?.removeFromSuperview()
            actionsView?.removeFromSuperview()
            host?.removeFromSuperview()
            self?.hostView = nil
            self?.dimView = nil
            self?.ghostView = nil
            self?.ghostBlurredImageView = nil
            self?.actionsView = nil
            self?.onDismiss?()
        }

        guard animated, let host else { cleanup(); return }
        _ = host
        _ = ghostBlur

        let duration: TimeInterval = ContextMenuController.springDuration * 0.75

        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: 0.95,
            initialSpringVelocity: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                dim?.alpha = 0.0
                actionsView?.alpha = 0.0
                // Collapse the actions back into the source button origin.
                let center = CGPoint(x: sourceRectInHost.midX, y: sourceRectInHost.midY)
                if let actionsView {
                    let scale = min(sourceRectInHost.width / max(1, actionsView.bounds.width),
                                    sourceRectInHost.height / max(1, actionsView.bounds.height))
                    actionsView.transform = CGAffineTransform.identity
                        .translatedBy(x: center.x - actionsView.center.x, y: center.y - actionsView.center.y)
                        .scaledBy(x: max(0.05, scale), y: max(0.05, scale))
                }
                // Ghost shrinks back to source.
                if let ghost {
                    ghost.frame = sourceRectInHost
                    ghost.layer.cornerRadius = self.source.cornerRadius ?? (sourceRectInHost.height / 2.0)
                    ghost.alpha = 1.0
                    ghost.isHidden = false
                }
                self.ghostBlurredImageView?.alpha = 0.0
            },
            completion: { _ in cleanup() }
        )
    }

    // MARK: - Animate in

    private func animateIn(
        host: UIView,
        dim: UIView,
        ghost: UIView,
        actionsView: ContextMenuActionsView,
        sourceRectInHost: CGRect,
        menuFrame: CGRect
    ) {
        // Initial state: menu anchored at source center with scale 0.01 (matches Telegram value).
        let menuCenter = CGPoint(x: menuFrame.midX, y: menuFrame.midY)
        let sourceCenter = CGPoint(x: sourceRectInHost.midX, y: sourceRectInHost.midY)
        let deltaX = sourceCenter.x - menuCenter.x
        let deltaY = sourceCenter.y - menuCenter.y

        actionsView.alpha = 0.0
        actionsView.transform = CGAffineTransform(translationX: deltaX, y: deltaY)
            .scaledBy(x: 0.01, y: 0.01)

        // Dim fades in quickly.
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut], animations: {
            dim.alpha = 1.0
        })

        // Actions appear nearly immediately but spring-scale in.
        UIView.animate(withDuration: 0.05, delay: 0, options: [.curveLinear], animations: {
            actionsView.alpha = 1.0
        })
        UIView.animate(
            withDuration: ContextMenuController.springDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.springDamping,
            initialSpringVelocity: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                actionsView.transform = .identity
            },
            completion: nil
        )

        // Ghost morphs from source rect → menu rect. During the first ~250ms we
        // crossfade the sharp snapshot into a pre-blurred copy (so the user sees
        // the source "dissolve" into fog) and at the same time spring the frame.
        // The whole ghost then fades to reveal the real menu underneath.
        UIView.animate(
            withDuration: ContextMenuController.springDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.springDamping,
            initialSpringVelocity: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                ghost.frame = menuFrame
                ghost.layer.cornerRadius = ContextMenuActionsView.cornerRadius
            },
            completion: nil
        )

        // Sharp → blurred crossfade (fast, front-loaded).
        if let ghostBlur = ghostBlurredImageView {
            ghostBlur.alpha = 0.0
            UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut], animations: {
                ghostBlur.alpha = 1.0
            })
        }

        // Ghost fade-out over the tail of the spring; lets the real menu shine through.
        UIView.animate(
            withDuration: 0.22,
            delay: 0.08,
            options: [.curveEaseInOut],
            animations: {
                ghost.alpha = 0.0
            },
            completion: { _ in
                ghost.isHidden = true
            }
        )
    }

    // MARK: - Menu placement

    private func computeMenuFrame(sourceRect: CGRect, menuSize: CGSize, hostBounds: CGRect) -> CGRect {
        let sideInset: CGFloat = 12.0
        // Prefer the hosting window's insets over the freshly-attached host view:
        // the host hasn't been laid out yet when we ask, so its own
        // safeAreaInsets are still zero during the first present call.
        let window = source.view?.window
        let safeTop: CGFloat = max(window?.safeAreaInsets.top ?? hostView?.safeAreaInsets.top ?? 0.0, 12.0)
        let safeBottom: CGFloat = max(window?.safeAreaInsets.bottom ?? hostView?.safeAreaInsets.bottom ?? 0.0, 12.0)

        // Horizontal placement — anchor to the source's left edge, clamped.
        var x = sourceRect.minX
        if x + menuSize.width > hostBounds.maxX - sideInset {
            x = hostBounds.maxX - sideInset - menuSize.width
        }
        x = max(sideInset, x)

        // Vertical placement — below the source, or above if it doesn't fit.
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

    // MARK: - Ghost snapshot

    private func buildGhostView(source: UIView, hostBounds: CGRect, sourceRectInHost: CGRect) -> UIView {
        // Capture the source view twice: once sharp, once pre-blurred. The ghost
        // container holds both and crossfades between them during the morph-in.
        let cornerRadius = self.source.cornerRadius ?? source.layer.cornerRadius

        let ghost = UIView(frame: sourceRectInHost)
        ghost.layer.cornerRadius = cornerRadius
        ghost.layer.cornerCurve = .continuous
        ghost.clipsToBounds = true
        ghost.backgroundColor = .clear

        let sharpImage = renderViewToImage(source)
        if let sharpImage {
            let sharpView = UIImageView(image: sharpImage)
            sharpView.frame = ghost.bounds
            sharpView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            sharpView.contentMode = .scaleAspectFill
            ghost.addSubview(sharpView)
        }

        // Pre-blur via Core Image Gaussian. Hidden at t=0 and crossfaded in.
        if let sharpImage, let blurred = blurredImage(from: sharpImage, radius: 14.0) {
            let blurredView = UIImageView(image: blurred)
            blurredView.frame = ghost.bounds
            blurredView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blurredView.contentMode = .scaleAspectFill
            blurredView.alpha = 0.0
            ghost.addSubview(blurredView)
            self.ghostBlurredImageView = blurredView
        }

        return ghost
    }

    private func renderViewToImage(_ view: UIView) -> UIImage? {
        let bounds = view.bounds
        if bounds.isEmpty { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { _ in
            // `afterScreenUpdates: true` is required for UIVisualEffectView-backed
            // glass content to be captured instead of rendering as a black box.
            view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    private func blurredImage(from image: UIImage, radius: CGFloat) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let context = CIContext(options: nil)
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage.clampedToExtent(), forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter?.outputImage?.cropped(to: ciImage.extent),
              let cg = context.createCGImage(output, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Gestures

    @objc private func handleBackgroundTap(_ recognizer: UITapGestureRecognizer) {
        guard let actionsView, let host = hostView else {
            dismiss()
            return
        }
        let location = recognizer.location(in: host)
        if !actionsView.frame.contains(location) {
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
