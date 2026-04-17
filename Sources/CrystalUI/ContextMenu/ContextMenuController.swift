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
    /// Outer wrapper UIView that owns the SDF lens distortion filter (iOS 26+).
    /// `menuContainer` lives inside it as the visible glass surface; SDF filters
    /// applied to `sdfHost.layer` distort the rendering of everything inside.
    /// On older systems `sdfHost` is just a plain wrapper with no filters.
    private var sdfHost: UIView?
    private var sdfFilter: AnyObject?  // erased LensSDFFilter? for pre-iOS-26 build
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

        // Two-layer wrapper. `sdfHost` is the morphing entity that owns the
        // SDF lens distortion filter on iOS 26+ — its layer is what
        // CASDFGlassDisplacementEffect rewrites pixel positions on. The
        // visible glass (UIVisualEffectView) lives inside, auto-resizing to
        // fill the wrapper. Filters apply transitively to the rendered
        // glass + content.
        //
        // The wrapper carries the cornerRadius + clipping (the menuContainer
        // inside has its own corner-clipping disabled to avoid a double-clip
        // mismatch as cornerRadius animates).
        let sdfHost = UIView(frame: sourceRectInHost)
        sdfHost.layer.cornerRadius = sourceCornerRadius
        sdfHost.layer.masksToBounds = true
        if #available(iOS 13.0, *) {
            sdfHost.layer.cornerCurve = .continuous
        }
        host.addSubview(sdfHost)
        self.sdfHost = sdfHost

        let menuContainer = UIVisualEffectView(effect: ContextMenuController.makeMenuEffect(
            isDark: source.traitCollection.userInterfaceStyle == .dark
        ))
        menuContainer.frame = sdfHost.bounds
        menuContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sdfHost.addSubview(menuContainer)
        self.menuContainer = menuContainer

        // Install SDF lens filter (iOS 26+). On older systems we fall back to
        // a non-distorted morph — the cornerRadius + frame spring still gives
        // a clean "glass expanding" feel; the SDF just adds the wobbly bulge.
        if #available(iOS 26.0, *), let filter = LensSDFFilter() {
            filter.install(on: sdfHost.layer, size: sourceRectInHost.size, cornerRadius: sourceCornerRadius)
            self.sdfFilter = filter
        }

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

        // Stretch the WHOLE morphing entity (the sdfHost wrapper) toward
        // the active touch — translates the SDF host so the lens distortion
        // and glass surface lean as a single unit.
        actionsView.onStretchUpdate = { [weak self, weak sdfHost, weak actionsView] point in
            guard let self, let sdfHost, let actionsView else { return }
            self.applyStretch(toContainer: sdfHost, touchInActions: point, actionsBounds: actionsView.bounds, animated: false)
        }
        actionsView.onStretchRelease = { [weak self, weak sdfHost] in
            guard let self, let sdfHost else { return }
            self.releaseStretch(onContainer: sdfHost)
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

        animateIn(
            dim: dim,
            sdfHost: sdfHost,
            snapshot: snapshot,
            actionsView: actionsView,
            sourceMinSide: min(sourceRectInHost.width, sourceRectInHost.height)
        )
    }

    public func dismiss(animated: Bool = true) {
        guard isPresented else { return }
        isPresented = false

        let host = hostView
        let dim = dimView
        let sdfHost = self.sdfHost
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
            if #available(iOS 26.0, *), let filter = self?.sdfFilter as? LensSDFFilter {
                filter.uninstall()
            }
            dim?.removeFromSuperview()
            sdfHost?.removeFromSuperview()
            container?.removeFromSuperview()
            actionsView?.removeFromSuperview()
            snapshot?.removeFromSuperview()
            host?.removeFromSuperview()
            self?.hostView = nil
            self?.dimView = nil
            self?.sdfHost = nil
            self?.sdfFilter = nil
            self?.menuContainer = nil
            self?.snapshotView = nil
            self?.actionsView = nil
            self?.onDismiss?()
            if let strongSelf = self {
                ContextMenuController.presentedControllers.remove(strongSelf.retainBox)
            }
        }

        guard animated, let sdfHost else { cleanup(); return }

        // Reverse keyframed morph: sdfHost shrinks back to source via the
        // same lens easing curves used in animateIn (just from = menu →
        // to = source). menuContainer auto-resizes, snapshot/actions
        // cross-fade in reverse.
        let keyframes = ContextMenuController.computeMorphKeyframes(
            from: menuFrameInHost,
            to: sourceRect,
            fromCornerRadius: ContextMenuActionsView.cornerRadius,
            toCornerRadius: sourceCornerRadius
        )

        sdfHost.transform = .identity
        sdfHost.layer.bounds = CGRect(origin: .zero, size: sourceRect.size)
        sdfHost.layer.position = CGPoint(x: sourceRect.midX, y: sourceRect.midY)
        sdfHost.layer.cornerRadius = sourceCornerRadius

        let scaleFactor = UIView.animationDurationFactor()
        let durationScaled = ContextMenuController.dismissDuration * scaleFactor

        let sizeAnim = CAKeyframeAnimation(keyPath: "bounds.size")
        sizeAnim.duration = durationScaled
        sizeAnim.values = keyframes.sizes.map { NSValue(cgSize: $0) }
        sizeAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        sizeAnim.isRemovedOnCompletion = true
        sizeAnim.fillMode = .both
        sdfHost.layer.add(sizeAnim, forKey: "bounds.size")

        let posAnim = CAKeyframeAnimation(keyPath: "position")
        posAnim.duration = durationScaled
        posAnim.values = keyframes.positions.map { NSValue(cgPoint: $0) }
        posAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        posAnim.isRemovedOnCompletion = true
        posAnim.fillMode = .both
        sdfHost.layer.add(posAnim, forKey: "position")

        let radiusAnim = CAKeyframeAnimation(keyPath: "cornerRadius")
        radiusAnim.duration = durationScaled
        radiusAnim.values = keyframes.radii.map { $0 as NSNumber }
        radiusAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        radiusAnim.isRemovedOnCompletion = true
        radiusAnim.fillMode = .both
        sdfHost.layer.add(radiusAnim, forKey: "cornerRadius")

        if #available(iOS 26.0, *), let filter = self.sdfFilter as? LensSDFFilter {
            filter.updateLayout(size: sourceRect.size, cornerRadius: self.sourceCornerRadius)
        }

        UIView.animate(
            withDuration: ContextMenuController.dismissDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: { dim?.alpha = 0.0 },
            completion: { _ in cleanup() }
        )

        // Re-apply the SDF wobble for the morph-out (strong → none).
        if #available(iOS 26.0, *), let filter = sdfFilter as? LensSDFFilter {
            let minSide = min(sourceRect.width, sourceRect.height)
            filter.animateDisplacement(
                fromHeight: minSide * 0.25, toHeight: 0.001,
                duration: ContextMenuController.dismissDuration
            )
            filter.animateBlur(duration: ContextMenuController.dismissDuration)
        }

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

    private func animateIn(
        dim: UIView,
        sdfHost: UIView,
        snapshot: UIView,
        actionsView: ContextMenuActionsView,
        sourceMinSide: CGFloat
    ) {
        // 1) Dim fades in.
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut], animations: {
            dim.alpha = 1.0
        })

        // 2) sdfHost morphs source rect → menu rect via 30-sample
        // CAKeyframeAnimation using Telegram's lens easing curves
        // (springProgress for position with overshoot, sideFractionEase
        // for size, radiusFractionEase for cornerRadius). This is what
        // gives the morph its distinctive multi-stage "lens" feel — a plain
        // UIView spring is too smooth to read as the lens animation.
        let keyframes = ContextMenuController.computeMorphKeyframes(
            from: sourceRectInHost,
            to: menuFrameInHost,
            fromCornerRadius: sourceCornerRadius,
            toCornerRadius: ContextMenuActionsView.cornerRadius
        )

        // Settle model values to the END state so the keyframed presentation
        // returns there cleanly when the animations are removed.
        sdfHost.layer.bounds = CGRect(origin: .zero, size: menuFrameInHost.size)
        sdfHost.layer.position = CGPoint(x: menuFrameInHost.midX, y: menuFrameInHost.midY)
        sdfHost.layer.cornerRadius = ContextMenuActionsView.cornerRadius

        let scale = UIView.animationDurationFactor()
        let durationScaled = ContextMenuController.morphDuration * scale

        let sizeAnim = CAKeyframeAnimation(keyPath: "bounds.size")
        sizeAnim.duration = durationScaled
        sizeAnim.values = keyframes.sizes.map { NSValue(cgSize: $0) }
        sizeAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        sizeAnim.isRemovedOnCompletion = true
        sizeAnim.fillMode = .both
        sdfHost.layer.add(sizeAnim, forKey: "bounds.size")

        let posAnim = CAKeyframeAnimation(keyPath: "position")
        posAnim.duration = durationScaled
        posAnim.values = keyframes.positions.map { NSValue(cgPoint: $0) }
        posAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        posAnim.isRemovedOnCompletion = true
        posAnim.fillMode = .both
        sdfHost.layer.add(posAnim, forKey: "position")

        let radiusAnim = CAKeyframeAnimation(keyPath: "cornerRadius")
        radiusAnim.duration = durationScaled
        radiusAnim.values = keyframes.radii.map { $0 as NSNumber }
        radiusAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        radiusAnim.isRemovedOnCompletion = true
        radiusAnim.fillMode = .both
        sdfHost.layer.add(radiusAnim, forKey: "cornerRadius")

        // Update SDF layout to the final menu state — its bounds + corner
        // radius animate alongside via implicit CATransaction (the surrounding
        // CAKeyframeAnimations are scheduled in the same runloop tick).
        if #available(iOS 26.0, *), let filter = self.sdfFilter as? LensSDFFilter {
            filter.updateLayout(
                size: menuFrameInHost.size,
                cornerRadius: ContextMenuActionsView.cornerRadius
            )
        }

        // SDF wobble: strong displacement at t=0 decaying to none, and a
        // matching blur ramp. The displacement amount is rooted in the
        // source button's smaller side so smaller buttons get proportionally
        // smaller bulges.
        if #available(iOS 26.0, *), let filter = sdfFilter as? LensSDFFilter {
            filter.animateDisplacement(
                fromHeight: sourceMinSide * 0.25, toHeight: 0.001,
                duration: ContextMenuController.morphDuration
            )
            filter.animateBlur(duration: ContextMenuController.morphDuration)
        }

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

    // MARK: - Morph keyframes

    /// 30-sample bake of the lens-style morph from `from` rect → `to` rect.
    /// Uses Telegram's lens easing curves so the animation reads as the lens
    /// even on systems where the SDF displacement filter isn't available
    /// (simulator, iOS < 26): position uses `springProgress` (under-damped
    /// spring with subtle overshoot); size uses `sideFractionEase` (critically
    /// damped); cornerRadius uses `radiusFractionEase`.
    private static func computeMorphKeyframes(
        from: CGRect,
        to: CGRect,
        fromCornerRadius: CGFloat,
        toCornerRadius: CGFloat
    ) -> (sizes: [CGSize], positions: [CGPoint], radii: [CGFloat]) {
        let sampleCount = 30
        let endIdx = CGFloat(sampleCount - 1)
        let fromCenter = CGPoint(x: from.midX, y: from.midY)
        let toCenter = CGPoint(x: to.midX, y: to.midY)

        var sizes: [CGSize] = []
        var positions: [CGPoint] = []
        var radii: [CGFloat] = []
        sizes.reserveCapacity(sampleCount)
        positions.reserveCapacity(sampleCount)
        radii.reserveCapacity(sampleCount)

        for i in 0 ..< sampleCount {
            let t = endIdx > 0 ? CGFloat(i) / endIdx : 1.0

            let posF = CGFloat(springProgress(Double(t)))
            positions.append(CGPoint(
                x: (1.0 - posF) * fromCenter.x + posF * toCenter.x,
                y: (1.0 - posF) * fromCenter.y + posF * toCenter.y
            ))

            let sizeF = CGFloat(max(0.0, min(1.0, sideFractionEase(Double(t)))))
            sizes.append(CGSize(
                width: (1.0 - sizeF) * from.width + sizeF * to.width,
                height: (1.0 - sizeF) * from.height + sizeF * to.height
            ))

            let radiusF = CGFloat(max(0.0, min(1.0, radiusFractionEase(Double(t)))))
            radii.append((1.0 - radiusF) * fromCornerRadius + radiusF * toCornerRadius)
        }

        return (sizes, positions, radii)
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
