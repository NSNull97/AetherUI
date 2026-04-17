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

    private static let morphDuration: TimeInterval = 0.72
    private static let morphDamping: CGFloat = 0.52  // slightly more damped to keep the slower morph clean
    private static let dismissDuration: TimeInterval = 0.6
    private static let dismissDamping: CGFloat = 0.68
    /// Peak gaussian-blur radius applied to the SNAPSHOT view (not the
    /// glass host) during the morph. Smears the button visual as it
    /// dissolves into the menu — sells the lens transition.
    private static let snapshotBlurPeak: CGFloat = 22.0
    private static let snapshotBlurDuration: TimeInterval = 0.44
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

    /// Two presentation flavours.
    ///   - `.morph` (default): the source view fades and the menu morphs
    ///     out of its rect — ideal for nav-bar buttons and pills (Phase 1).
    ///   - `.preview`: the source view stays as a "lifted" snapshot (a
    ///     scaled-up copy with shadow) and the menu appears beneath it —
    ///     ideal for long-press on cards / list rows where the user wants
    ///     a peek of the source content while choosing an action.
    public enum PresentationStyle {
        case morph
        case preview(verticalSpacing: CGFloat = 12.0, lift: CGFloat = 1.04)
    }

    // MARK: - State

    private let source: Source
    private let items: [ContextMenuItem]
    private let presentationStyle: PresentationStyle
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
    /// Inline submenu overlay (Yandex Music style). When non-nil, the parent
    /// `actionsView` is dimmed + disabled and `submenuCard` is overlaid on
    /// the parent menu, anchored to the source row's Y position. Tap on the
    /// card's header chevron OR on the dimmed parent collapses it.
    private var submenuCard: UIVisualEffectView?
    private var submenuActions: ContextMenuActionsView?
    /// Transparent hit-target placed inside `sdfHost` while a submenu is
    /// open: catches taps that miss the submenu card and collapses instead
    /// of dismissing the entire menu.
    private var submenuCollapseHitView: UIView?

    /// Lifted snapshot of the source view, only created in `.preview` style.
    /// Lives in `host` next to `dim` and `sdfHost`; positioned at the source's
    /// screen rect, scaled by `PresentationStyle.preview.lift`.
    private var previewView: UIView?

    private var menuFrameInHost: CGRect = .zero
    private var sourceRectInHost: CGRect = .zero
    private var sourceCornerRadius: CGFloat = 0

    private var isPresented: Bool = false
    private var dismissHandle: ContextMenuDismissHandle?

    // MARK: - Init

    public init(
        source: Source,
        items: [ContextMenuItem],
        presentationStyle: PresentationStyle = .morph,
        onDismiss: (() -> Void)? = nil
    ) {
        self.source = source
        self.items = items
        self.presentationStyle = presentationStyle
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

        // sdfHost: the morphing entity. Initial frame depends on style:
        //   .morph    — starts at source rect, lens-morphs to menu rect
        //   .preview  — already at menu rect; spring scale-in only
        let isPreview: Bool
        switch presentationStyle {
        case .morph: isPreview = false
        case .preview: isPreview = true
        }

        let initialHostFrame = isPreview ? menuFrame : sourceRectInHost
        let initialCornerRadius = isPreview ? ContextMenuActionsView.cornerRadius : sourceCornerRadius

        let sdfHost = UIView(frame: initialHostFrame)
        sdfHost.layer.cornerRadius = initialCornerRadius
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

        // Install SDF lens filter (iOS 26+). Only meaningful for .morph —
        // .preview doesn't morph the host, just scales it.
        if !isPreview, #available(iOS 26.0, *), let filter = LensSDFFilter() {
            filter.install(on: sdfHost.layer, size: sourceRectInHost.size, cornerRadius: sourceCornerRadius)
            self.sdfFilter = filter
        }

        // Snapshot of the source view. Placement depends on style:
        //   .morph    — inside menuContainer.contentView at top-left, source
        //               size. Cross-fades into actionsView during morph.
        //   .preview  — wrapped in a previewView added directly to host at
        //               sourceRect. Springs up by `lift` factor, stays
        //               visible above the menu the whole time it's open.
        let snapshot = makeSourceSnapshot(source: source)
        switch presentationStyle {
        case .morph:
            snapshot.frame = CGRect(origin: .zero, size: sourceRectInHost.size)
            snapshot.autoresizingMask = []
            menuContainer.contentView.addSubview(snapshot)
            self.snapshotView = snapshot
        case .preview:
            let preview = UIView(frame: sourceRectInHost)
            snapshot.frame = preview.bounds
            snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            preview.addSubview(snapshot)
            // Soft drop-shadow to sell the lift.
            preview.layer.shadowColor = UIColor.black.cgColor
            preview.layer.shadowOpacity = 0.18
            preview.layer.shadowRadius = 18.0
            preview.layer.shadowOffset = CGSize(width: 0, height: 8)
            host.addSubview(preview)
            self.previewView = preview
            self.snapshotView = snapshot
        }

        // Actions view layout depends on style:
        //   .morph   — sized to MENU at top-left, alpha 0 (cross-faded in)
        //   .preview — sized to MENU at top-left, alpha 1 from start
        actionsView.frame = CGRect(origin: .zero, size: menuFrame.size)
        actionsView.autoresizingMask = []
        actionsView.alpha = isPreview ? 1.0 : 0.0
        menuContainer.contentView.addSubview(actionsView)
        self.actionsView = actionsView

        if isPreview {
            // Pre-stage sdfHost for spring-in.
            sdfHost.alpha = 0.0
            sdfHost.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }

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
            self?.previewView?.removeFromSuperview()
            host?.removeFromSuperview()
            self?.hostView = nil
            self?.dimView = nil
            self?.sdfHost = nil
            self?.sdfFilter = nil
            self?.menuContainer = nil
            self?.snapshotView = nil
            self?.previewView = nil
            self?.actionsView = nil
            self?.submenuCard?.removeFromSuperview()
            self?.submenuCard = nil
            self?.submenuActions = nil
            self?.submenuCollapseHitView?.removeFromSuperview()
            self?.submenuCollapseHitView = nil
            self?.onDismiss?()
            if let strongSelf = self {
                ContextMenuController.presentedControllers.remove(strongSelf.retainBox)
            }
        }

        guard animated, let sdfHost else { cleanup(); return }

        switch presentationStyle {
        case .morph:
            animateOutMorph(
                sdfHost: sdfHost, sourceRect: sourceRect,
                dim: dim, snapshot: snapshot, actionsView: actionsView
            )
        case .preview:
            animateOutPreview(
                sdfHost: sdfHost,
                dim: dim, preview: previewView
            )
        }

        // Cleanup at the end of the dismiss animation. Both .morph and
        // .preview reverse paths above run for `dismissDuration`. The
        // reentrancy-guard inside `cleanup` makes the +0.2 safety timer
        // a no-op if the primary fire happens first.
        DispatchQueue.main.asyncAfter(deadline: .now() + ContextMenuController.dismissDuration) { cleanup() }
        DispatchQueue.main.asyncAfter(deadline: .now() + ContextMenuController.dismissDuration + 0.2) { cleanup() }
    }

    /// Reverse the .morph presentation: lens shrinks back to source rect.
    private func animateOutMorph(
        sdfHost: UIView,
        sourceRect: CGRect,
        dim: UIView?,
        snapshot: UIView?,
        actionsView: ContextMenuActionsView?
    ) {
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
            completion: nil
        )

        if #available(iOS 26.0, *), let filter = sdfFilter as? LensSDFFilter {
            let minSide = min(sourceRect.width, sourceRect.height)
            filter.animateDisplacement(
                fromHeight: minSide * 0.25, toHeight: 0.001,
                duration: ContextMenuController.dismissDuration
            )
            filter.animateBlur(duration: ContextMenuController.dismissDuration)
        }

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
    }

    /// Reverse the .preview presentation: lifted preview drops back to
    /// identity scale; menu chrome scales/fades out.
    private func animateOutPreview(
        sdfHost: UIView,
        dim: UIView?,
        preview: UIView?
    ) {
        UIView.animate(
            withDuration: ContextMenuController.dismissDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.dismissDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                sdfHost.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                sdfHost.alpha = 0.0
                preview?.transform = .identity
                dim?.alpha = 0.0
            },
            completion: nil
        )
    }

    // MARK: - Animate in

    private func animateIn(
        dim: UIView,
        sdfHost: UIView,
        snapshot: UIView,
        actionsView: ContextMenuActionsView,
        sourceMinSide: CGFloat
    ) {
        // Dim fades in either way.
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut], animations: {
            dim.alpha = 1.0
        })

        switch presentationStyle {
        case .morph:
            animateInMorph(sdfHost: sdfHost, snapshot: snapshot, actionsView: actionsView, sourceMinSide: sourceMinSide)
        case let .preview(_, lift):
            animateInPreview(sdfHost: sdfHost, lift: lift)
        }
    }

    /// Source rect → menu rect lens morph with cross-fading snapshot.
    private func animateInMorph(
        sdfHost: UIView,
        snapshot: UIView,
        actionsView: ContextMenuActionsView,
        sourceMinSide: CGFloat
    ) {
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

        // SDF wobble (iOS 26 only).
        if #available(iOS 26.0, *), let filter = sdfFilter as? LensSDFFilter {
            filter.animateDisplacement(
                fromHeight: sourceMinSide * 0.25, toHeight: 0.001,
                duration: ContextMenuController.morphDuration
            )
            filter.animateBlur(duration: ContextMenuController.morphDuration)
        }

        // Lens-feel overlay: scale wobble on the host + gaussian smear on
        // the snapshot.
        applyLensFeelOverlay(
            host: sdfHost,
            snapshot: snapshot,
            duration: ContextMenuController.morphDuration,
            reversed: false
        )

        // Cross-fade snapshot → actions view.
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

    /// Lifted preview + below-source menu spring-in (no morph).
    private func animateInPreview(sdfHost: UIView, lift: CGFloat) {
        // sdfHost was pre-staged at scale 0.9 + alpha 0; spring it to
        // identity. Menu chrome reads as "appearing fresh below the lifted
        // preview".
        UIView.animate(
            withDuration: ContextMenuController.morphDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.morphDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                sdfHost.transform = .identity
                sdfHost.alpha = 1.0
            },
            completion: nil
        )

        // Lifted preview: scale up by `lift` from identity, with the same
        // spring so it lands in sync with the menu.
        if let preview = previewView {
            preview.transform = .identity
            UIView.animate(
                withDuration: ContextMenuController.morphDuration,
                delay: 0,
                usingSpringWithDamping: ContextMenuController.morphDamping,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    preview.transform = CGAffineTransform(scaleX: lift, y: lift)
                },
                completion: nil
            )
        }
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

    /// Two layouts depending on `presentationStyle`:
    ///   - `.morph`: menu top-anchored to source.top — the lens visibly
    ///     grows downward + outward FROM the button.
    ///   - `.preview`: menu placed BELOW the source rect with a gap so the
    ///     lifted preview snapshot has room to show. Falls back to placing
    ///     menu above if there's not enough room below.
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

        let initialY: CGFloat
        switch presentationStyle {
        case .morph:
            initialY = sourceRect.minY
        case let .preview(spacing, _):
            initialY = sourceRect.maxY + spacing
        }

        var y = initialY
        if y + menuSize.height > hostBounds.maxY - safeBottom {
            let upward = sourceRect.minY - (menuSize.height + (initialY - sourceRect.maxY).magnitude)
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
        sdfHost: UIView,
        isSubmenu: Bool = false
    ) {
        view.onActionSelected = { [weak self] actionItem in
            guard let self else { return }
            let shouldAutoDismiss = actionItem.action == nil
            actionItem.action?(actionItem, handle)
            if shouldAutoDismiss { self.dismiss(animated: true) }
        }
        view.onSubmenuRequested = { [weak self] actionItem in
            self?.openInlineSubmenu(from: actionItem)
        }
        view.onHeaderTapped = { [weak self] in
            // The submenu card's header (down-chevron) collapses the card.
            // The root actions view never has a header, so this only fires
            // for submenu cards.
            self?.collapseInlineSubmenu()
        }
        view.onStretchUpdate = { [weak self, weak sdfHost, weak view] point in
            guard let self, let sdfHost, let view else { return }
            // Stretch only the parent host. Submenu cards don't carry the
            // SDF lens — they're a lightweight popover.
            if isSubmenu { return }
            self.applyStretch(toContainer: sdfHost, touchInActions: point, actionsBounds: view.bounds, animated: false)
        }
        view.onStretchRelease = { [weak self, weak sdfHost] in
            guard let self, let sdfHost, !isSubmenu else { return }
            self.releaseStretch(onContainer: sdfHost)
        }
    }

    // MARK: - Inline submenu (Yandex-Music-style overlay)

    private static let submenuTransitionDuration: TimeInterval = 0.42
    private static let submenuTransitionDamping: CGFloat = 0.85
    /// Alpha applied to the parent actions view while a submenu card is open.
    /// The dimmed parent stays visible so the user has visual context, but
    /// becomes secondary to the popped-out submenu.
    private static let submenuParentDimAlpha: CGFloat = 0.32

    /// Open an inline submenu card overlaid on the parent menu, anchored to
    /// the source row's Y position. The parent actions view dims behind it;
    /// taps that miss the card collapse it (caught by `submenuCollapseHitView`).
    private func openInlineSubmenu(from item: ContextMenuActionItem) {
        guard
            let submenu = item.submenu,
            let host = self.hostView,
            let sdfHost = self.sdfHost,
            let menuContainer = self.menuContainer,
            let parentActions = self.actionsView,
            let handle = self.dismissHandle
        else { return }

        // If a submenu is already open, collapse it first (we don't stack
        // inline submenus — only one card at a time).
        if submenuCard != nil {
            collapseInlineSubmenu(animated: false)
        }

        // Build the card.
        let isDark = sdfHost.traitCollection.userInterfaceStyle == .dark
        let card = UIVisualEffectView(effect: ContextMenuController.makeMenuEffect(isDark: isDark))
        card.layer.cornerRadius = ContextMenuActionsView.cornerRadius
        card.layer.masksToBounds = true
        if #available(iOS 13.0, *) {
            card.layer.cornerCurve = .continuous
        }

        let submenuActions = ContextMenuActionsView(
            items: submenu,
            headerStyle: .disclosure(title: item.title)
        )
        let cardWidth = sdfHost.bounds.width
        let cardSize = submenuActions.preferredSize(maxWidth: cardWidth)
        submenuActions.frame = CGRect(origin: .zero, size: cardSize)
        submenuActions.autoresizingMask = [.flexibleWidth]
        card.contentView.addSubview(submenuActions)
        wireActionsView(submenuActions, handle: handle, sdfHost: sdfHost, isSubmenu: true)

        // Anchor card.minY to the source row's Y in screen coords. We can
        // approximate by finding the touched item's row in `parentActions`
        // — but a simpler robust path is "use the source row's frame directly".
        let cardOriginInParent = sourceRowFrame(for: item, in: parentActions)?.origin ?? .zero
        let cardOriginInHost = parentActions.convert(cardOriginInParent, to: host)
        let cardFrame = CGRect(
            x: sdfHost.frame.minX,
            y: cardOriginInHost.y,
            width: cardWidth,
            height: cardSize.height
        )
        card.frame = cardFrame
        host.addSubview(card)
        self.submenuCard = card
        self.submenuActions = submenuActions

        // Hit-target inside sdfHost that catches taps which miss the card.
        // Lives BELOW the card in the host hierarchy (sdfHost is below the
        // card sibling), so card touches still go to the card first.
        let hitView = UIView(frame: sdfHost.bounds)
        hitView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hitView.backgroundColor = .clear
        let collapseTap = UITapGestureRecognizer(target: self, action: #selector(handleCollapseTap))
        hitView.addGestureRecognizer(collapseTap)
        sdfHost.addSubview(hitView)
        self.submenuCollapseHitView = hitView

        // Dim parent + disable its touches so the card / hit-view interaction
        // model cleanly takes over.
        parentActions.isUserInteractionEnabled = false

        // Spring + fade-in. Card scales from 0.96 to 1.0 anchored at its
        // header center to match where the source row is — visually it pops
        // out of the row.
        card.alpha = 0.0
        card.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        UIView.animate(
            withDuration: ContextMenuController.submenuTransitionDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.submenuTransitionDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                card.alpha = 1.0
                card.transform = .identity
                parentActions.alpha = ContextMenuController.submenuParentDimAlpha
            },
            completion: nil
        )
    }

    /// Walk the parent actions view's subview tree and return the frame
    /// (in `parent`'s own coordinates) of the row whose item matches `item`.
    /// Used to anchor the submenu card's Y position to the row that
    /// triggered the open.
    private func sourceRowFrame(for item: ContextMenuActionItem, in parent: UIView) -> CGRect? {
        guard let row = findActionRow(matching: item, in: parent) else { return nil }
        return row.convert(row.bounds, to: parent)
    }

    private func findActionRow(matching item: ContextMenuActionItem, in view: UIView) -> ContextMenuActionItemView? {
        if let row = view as? ContextMenuActionItemView, row.item.id == item.id {
            return row
        }
        for subview in view.subviews {
            if let found = findActionRow(matching: item, in: subview) {
                return found
            }
        }
        return nil
    }

    /// Close the inline submenu card. Reverses the open animation; restores
    /// parent alpha + interaction.
    @discardableResult
    private func collapseInlineSubmenu(animated: Bool = true) -> Bool {
        guard let card = submenuCard else { return false }
        let parentActions = self.actionsView
        let hitView = self.submenuCollapseHitView

        let teardown = {
            card.removeFromSuperview()
            hitView?.removeFromSuperview()
            parentActions?.isUserInteractionEnabled = true
            self.submenuCard = nil
            self.submenuActions = nil
            self.submenuCollapseHitView = nil
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        guard animated else {
            parentActions?.alpha = 1.0
            teardown()
            return true
        }

        UIView.animate(
            withDuration: ContextMenuController.submenuTransitionDuration,
            delay: 0,
            usingSpringWithDamping: 0.95,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                card.alpha = 0.0
                card.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
                parentActions?.alpha = 1.0
            },
            completion: { _ in teardown() }
        )
        return true
    }

    @objc private func handleCollapseTap() {
        collapseInlineSubmenu()
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
        presentationStyle: PresentationStyle = .morph,
        onDismiss: (() -> Void)? = nil
    ) -> ContextMenuController {
        let controller = ContextMenuController(
            source: Source(view: source, cornerRadius: cornerRadius),
            items: items,
            presentationStyle: presentationStyle,
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
