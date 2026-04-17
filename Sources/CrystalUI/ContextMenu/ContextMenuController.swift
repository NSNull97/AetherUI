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

    private static let morphDuration: TimeInterval = 0.55
    private static let morphDamping: CGFloat = 0.48  // very elastic overshoot (was 0.55)
    private static let dismissDuration: TimeInterval = 0.46
    private static let dismissDamping: CGFloat = 0.62
    /// Peak gaussian-blur radius applied to the SNAPSHOT view (not the
    /// glass host) during the morph. Smears the button visual as it
    /// dissolves into the menu — sells the lens transition.
    private static let snapshotBlurPeak: CGFloat = 22.0
    private static let snapshotBlurDuration: TimeInterval = 0.34
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
    /// Stack of menu pages. Index 0 is the root (built in present()); each
    /// submenu push appends, each back-tap pops. Top of stack is always the
    /// page receiving touches; lower pages are kept around so we can pop
    /// back to them without rebuilding.
    private var pageStack: [ContextMenuActionsView] = []

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
        self.pageStack = [actionsView]

        // Tap-outside to dismiss.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        dim.addGestureRecognizer(tap)
        self.tapRecognizer = tap

        // Wire root actions view (callbacks + stretch hooks).
        let handle = ContextMenuDismissHandle(dismiss: { [weak self] animated in self?.dismiss(animated: animated) })
        self.dismissHandle = handle
        wireActionsView(actionsView, handle: handle, sdfHost: sdfHost)

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
            self?.pageStack.removeAll()
            self?.onDismiss?()
            if let strongSelf = self {
                ContextMenuController.presentedControllers.remove(strongSelf.retainBox)
            }
        }

        guard animated, let sdfHost else { cleanup(); return }

        // Reverse morph on sdfHost (= the morphing entity carrying the SDF
        // filter). The internal menuContainer auto-resizes, snapshot stays at
        // top-left source size, actionsView fades out.
        let radiusAnim = CABasicAnimation(keyPath: "cornerRadius")
        radiusAnim.fromValue = sdfHost.layer.cornerRadius
        radiusAnim.toValue = sourceCornerRadius
        radiusAnim.duration = ContextMenuController.dismissDuration
        radiusAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        sdfHost.layer.cornerRadius = sourceCornerRadius
        sdfHost.layer.add(radiusAnim, forKey: "cornerRadius")

        UIView.animate(
            withDuration: ContextMenuController.dismissDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.dismissDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                sdfHost.frame = sourceRect
                sdfHost.transform = .identity
                dim?.alpha = 0.0
                if #available(iOS 26.0, *), let filter = self.sdfFilter as? LensSDFFilter {
                    filter.updateLayout(size: sourceRect.size, cornerRadius: self.sourceCornerRadius)
                }
            },
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

        // Same lens-feel overlay as animateIn but in reverse: scale wobble
        // contracts back, snapshot blur ramps UP to peak so the button
        // re-emerges with a "lens settle" instead of just popping back in.
        applyLensFeelOverlay(
            host: sdfHost,
            snapshot: snapshot,
            duration: ContextMenuController.dismissDuration,
            reversed: true
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

        // 2) sdfHost (= the morphing entity) morphs from source rect → menu
        // rect with spring. CornerRadius animates via CABasicAnimation, and
        // the SDF filter (if installed) is given matching keyframed
        // displacement + blur ramps so the lens wobble follows the morph.
        let radiusAnim = CABasicAnimation(keyPath: "cornerRadius")
        radiusAnim.fromValue = sourceCornerRadius
        radiusAnim.toValue = ContextMenuActionsView.cornerRadius
        radiusAnim.duration = ContextMenuController.morphDuration
        radiusAnim.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0.4, 1.0)
        sdfHost.layer.cornerRadius = ContextMenuActionsView.cornerRadius
        sdfHost.layer.add(radiusAnim, forKey: "cornerRadius")

        UIView.animate(
            withDuration: ContextMenuController.morphDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.morphDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                sdfHost.frame = self.menuFrameInHost
                if #available(iOS 26.0, *), let filter = self.sdfFilter as? LensSDFFilter {
                    filter.updateLayout(
                        size: self.menuFrameInHost.size,
                        cornerRadius: ContextMenuActionsView.cornerRadius
                    )
                }
            },
            completion: nil
        )

        // SDF wobble (iOS 26 only): hardware-accelerated displacement-map
        // distortion that gives the actual lens bulge. May silently no-op
        // on simulators where the private CASDFLayer / displacementMap
        // filter isn't supported.
        if #available(iOS 26.0, *), let filter = sdfFilter as? LensSDFFilter {
            filter.animateDisplacement(
                fromHeight: sourceMinSide * 0.25, toHeight: 0.001,
                duration: ContextMenuController.morphDuration
            )
            filter.animateBlur(duration: ContextMenuController.morphDuration)
        }

        // Lens FEEL augmentation: scale wobble on the host + gaussian smear
        // on the snapshot. Works on every platform and doesn't touch
        // frame/bounds (autoresizing + hit-testing keep working).
        applyLensFeelOverlay(
            host: sdfHost,
            snapshot: snapshot,
            duration: ContextMenuController.morphDuration,
            reversed: false
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

    // MARK: - Lens-feel overlay
    //
    // Two layered effects, each on a layer where it can't damage the
    // surrounding glass / hit-testing:
    //
    //   1. **Transform-scale wobble on the host.** 6-keyframe animation
    //      `1.0 → 1.10 → 0.97 → 1.025 → 0.995 → 1.0` for a strong elastic
    //      bulge with multiple settle oscillations. transform.* doesn't
    //      affect frame/bounds, so menuContainer's autoresizing + the
    //      actionsView's hit-testing keep working through the morph.
    //
    //   2. **Gaussian-blur smear on the SNAPSHOT view.** Peak radius 14pt
    //      decaying to 0 over `snapshotBlurDuration`. Only the button-
    //      snapshot pixels get blurred — `sdfHost.layer.filters` is left
    //      alone so it doesn't pile a second filter on top of
    //      `UIVisualEffectView`'s own glass pipeline (that combination
    //      tinted everything violet).
    //
    // Both run for both `animateIn` and `animateOut`; pass `reversed: true`
    // for the dismiss path so the snapshot blurs back IN as the menu
    // collapses to the source.
    private func applyLensFeelOverlay(
        host: UIView,
        snapshot: UIView?,
        duration: TimeInterval,
        reversed: Bool
    ) {
        let scaleValues: [CGFloat] = reversed
            ? [1.0, 1.04, 0.95, 1.14, 1.0]
            : [1.0, 1.14, 0.95, 1.04, 0.99, 1.0]
        let keyTimes: [NSNumber] = reversed
            ? [0.0, 0.18, 0.4, 0.72, 1.0]
            : [0.0, 0.28, 0.5, 0.72, 0.88, 1.0]

        let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnim.values = scaleValues
        scaleAnim.keyTimes = keyTimes
        scaleAnim.duration = duration * UIView.animationDurationFactor()
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        scaleAnim.isRemovedOnCompletion = true
        scaleAnim.fillMode = .both
        host.layer.add(scaleAnim, forKey: "lensWobble.scale")

        guard let snapshot, let blur = CALayer.blur() else { return }
        let peak = ContextMenuController.snapshotBlurPeak
        let blurDur = ContextMenuController.snapshotBlurDuration

        let initialRadius: CGFloat = reversed ? 0.0 : peak
        let finalRadius: CGFloat = reversed ? peak : 0.0
        blur.setValue(initialRadius as NSNumber, forKey: "inputRadius")
        snapshot.layer.filters = [blur]

        let blurAnim = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
        blurAnim.fromValue = initialRadius as NSNumber
        blurAnim.toValue = finalRadius as NSNumber
        blurAnim.duration = blurDur * UIView.animationDurationFactor()
        blurAnim.timingFunction = CAMediaTimingFunction(name: reversed ? .easeIn : .easeOut)
        blurAnim.isRemovedOnCompletion = true
        blurAnim.fillMode = .both
        snapshot.layer.add(blurAnim, forKey: "lensSmear.blur")

        // After the blur ramp, drop the filter so the snapshot doesn't carry
        // an idle gaussian filter (perf + cleanliness).
        DispatchQueue.main.asyncAfter(deadline: .now() + blurDur + 0.02) { [weak snapshot] in
            snapshot?.layer.filters = nil
        }
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

    // MARK: - Submenu page stack

    /// Hooks an actions view into the controller — action callbacks,
    /// submenu push, back-tap, and stretch reporting. Used for both the
    /// root page and pushed submenu pages.
    private func wireActionsView(
        _ view: ContextMenuActionsView,
        handle: ContextMenuDismissHandle,
        sdfHost: UIView
    ) {
        view.onActionSelected = { [weak self] actionItem in
            guard let self else { return }
            let shouldAutoDismiss = actionItem.action == nil
            actionItem.action?(actionItem, handle)
            if shouldAutoDismiss { self.dismiss(animated: true) }
        }
        view.onSubmenuRequested = { [weak self] actionItem in
            self?.pushSubmenu(from: actionItem)
        }
        view.onBackTapped = { [weak self] in
            self?.popSubmenu()
        }
        view.onStretchUpdate = { [weak self, weak sdfHost, weak view] point in
            guard let self, let sdfHost, let view else { return }
            self.applyStretch(toContainer: sdfHost, touchInActions: point, actionsBounds: view.bounds, animated: false)
        }
        view.onStretchRelease = { [weak self, weak sdfHost] in
            guard let self, let sdfHost else { return }
            self.releaseStretch(onContainer: sdfHost)
        }
    }

    private static let pageTransitionDuration: TimeInterval = 0.36
    private static let pageTransitionDamping: CGFloat = 0.78

    /// Push a submenu page. The current top slides slightly left + fades,
    /// the new page slides in from the right; the menu container resizes
    /// its height to fit the new page (top-anchored, so the menu's top
    /// edge stays put).
    private func pushSubmenu(from item: ContextMenuActionItem) {
        guard
            let submenu = item.submenu,
            let menuContainer = self.menuContainer,
            let sdfHost = self.sdfHost,
            let dismissHandle = self.dismissHandle,
            let topPage = pageStack.last
        else { return }

        let containerBounds = menuContainer.bounds
        let newPage = ContextMenuActionsView(items: submenu, backTitle: item.title)
        let newPageSize = newPage.preferredSize(maxWidth: containerBounds.width)
        newPage.frame = CGRect(
            x: containerBounds.width, y: 0,
            width: containerBounds.width, height: newPageSize.height
        )
        newPage.autoresizingMask = []
        menuContainer.contentView.addSubview(newPage)
        wireActionsView(newPage, handle: dismissHandle, sdfHost: sdfHost)

        pageStack.append(newPage)
        self.actionsView = newPage

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Resize host to the new page's height. Width unchanged.
        let newHostFrame = CGRect(
            x: sdfHost.frame.minX, y: sdfHost.frame.minY,
            width: sdfHost.frame.width, height: newPageSize.height
        )

        UIView.animate(
            withDuration: ContextMenuController.pageTransitionDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.pageTransitionDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                sdfHost.frame = newHostFrame
                topPage.transform = CGAffineTransform(translationX: -containerBounds.width * 0.25, y: 0)
                topPage.alpha = 0.0
                newPage.frame = CGRect(
                    x: 0, y: 0,
                    width: containerBounds.width, height: newPageSize.height
                )
            },
            completion: nil
        )
    }

    /// Pop the top submenu page. The top slides out to the right + fades;
    /// the page below restores; the container resizes back to that page's
    /// height. Does nothing if only the root page remains.
    private func popSubmenu() {
        guard pageStack.count > 1,
              let menuContainer = self.menuContainer,
              let sdfHost = self.sdfHost else { return }

        let topPage = pageStack.removeLast()
        let restorePage = pageStack.last!
        self.actionsView = restorePage

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        let containerBounds = menuContainer.bounds
        let restoreSize = restorePage.preferredSize(maxWidth: containerBounds.width)
        let newHostFrame = CGRect(
            x: sdfHost.frame.minX, y: sdfHost.frame.minY,
            width: sdfHost.frame.width, height: restoreSize.height
        )

        UIView.animate(
            withDuration: ContextMenuController.pageTransitionDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.pageTransitionDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                sdfHost.frame = newHostFrame
                topPage.transform = CGAffineTransform(translationX: containerBounds.width, y: 0)
                topPage.alpha = 0.0
                restorePage.transform = .identity
                restorePage.alpha = 1.0
                restorePage.frame = CGRect(
                    x: 0, y: 0,
                    width: containerBounds.width, height: restoreSize.height
                )
            },
            completion: { _ in
                topPage.removeFromSuperview()
            }
        )
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
