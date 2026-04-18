import UIKit

// MARK: - ContextMenuController

/// Presents a `ContextMenuActionsView` with a single-surface morph: a
/// `ContextMenuMorphHostView` starts sized + cornered like the source
/// button, then morphs to the menu rect under a single progress-driven
/// timeline. Source-button snapshot fades out early, menu rows slide in
/// late, shadow thickens with size, all choreographed off the same
/// `progress: 0…1` the morph host exposes. Visually the button literally
/// "unfolds" into the menu — no cross-fading two independent views.
///
/// Two presentation flavours:
///   - `.morph`   (default) — uses `ContextMenuMorphHostView`.
///   - `.preview` — static glass menu + a lifted snapshot of the source
///                  above it; for long-press on cards where you want to
///                  keep the source visible while choosing an action.
///
/// `LensTransitionContainer` and `LensSDFFilter` remain in the codebase.
/// The SDF filter is installed on top of the morph host on iOS 26 for an
/// extra refraction kick during the transition ("Premium" option from the
/// architecture doc); it's optional polish and the morph reads fine on
/// older systems without it.
public final class ContextMenuController {
    // MARK: - Animation constants

    private static let morphDuration: TimeInterval = 0.44  // critically-damped settles quickly; short duration keeps feel snappy
    private static let dismissDuration: TimeInterval = 0.32 // close faster than open
    private static let dismissDamping: CGFloat = 0.78       // slightly less elastic than open

    private static let dimAlpha: CGFloat = 0.08  // very faint separation layer (rec: ≤0.06-0.10)
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
    /// For `.morph` style: the single-surface morph host — one view that
    /// holds glass + shadow + source/destination content containers and
    /// morphs between source-rect and menu-rect under `progress: 0…1`.
    /// For `.preview` style: left `nil`; `sdfHost` is used as the outer
    /// wrapper instead.
    private var morphHost: ContextMenuMorphHostView?
    /// For `.preview` style only: the outer wrapper holding the (static-
    /// size) glass menu. Left `nil` for `.morph` — morphHost plays that role.
    private var sdfHost: UIView?
    private var sdfFilter: AnyObject?  // erased LensSDFFilter? for pre-iOS-26 build
    private var menuContainer: UIVisualEffectView?
    private var snapshotView: UIView?
    private var actionsView: ContextMenuActionsView?
    private var tapRecognizer: UITapGestureRecognizer?
    /// The view that plays the role of "the glass surface hit-test target"
    /// for submenu + stretch purposes. For `.morph` this is `morphHost`;
    /// for `.preview` it's `sdfHost`. Collapsed into a single property so
    /// downstream wiring code doesn't have to branch on presentation style.
    private var surfaceView: UIView? { morphHost ?? sdfHost }
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

        // Branch on style — they're different enough (morph = progress-
        // driven single surface; preview = static glass + lifted snapshot)
        // that a shared setup path stopped paying its way.
        let isDark = source.traitCollection.userInterfaceStyle == .dark
        let effect = ContextMenuController.makeMenuEffect(isDark: isDark)
        let snapshot = makeSourceSnapshot(source: source)
        self.snapshotView = snapshot

        switch presentationStyle {
        case .morph:
            setupMorphStyle(
                host: host,
                source: source,
                effect: effect,
                snapshot: snapshot,
                actionsView: actionsView,
                sourceRectInHost: sourceRectInHost,
                sourceCornerRadius: sourceCornerRadius,
                menuFrame: menuFrame
            )
        case .preview:
            setupPreviewStyle(
                host: host,
                source: source,
                effect: effect,
                snapshot: snapshot,
                actionsView: actionsView,
                sourceRectInHost: sourceRectInHost,
                menuFrame: menuFrame
            )
        }
        self.actionsView = actionsView

        // Tap-outside to dismiss.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
        dim.addGestureRecognizer(tap)
        self.tapRecognizer = tap

        // Wire root actions view (callbacks + stretch hooks). `surfaceView`
        // is the view that both stretch and submenu positioning anchor to
        // — morphHost for .morph, sdfHost for .preview.
        let handle = ContextMenuDismissHandle(dismiss: { [weak self] animated in self?.dismiss(animated: animated) })
        self.dismissHandle = handle
        if let surface = surfaceView {
            wireActionsView(actionsView, handle: handle, sdfHost: surface)
        }

        // Haptic.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Hide source INVISIBLY — not via `isHidden`, which would trigger
        // parent re-layout in UIStackView / self-sizing collection cells,
        // and not via `alpha = 0.0`, which GlassBarButtonView's press-
        // release `UIView.animate` slams back to 1.0 on the .tap path.
        //
        // Instead: attach a fully-transparent `CALayer` as the source
        // layer's mask. A mask's alpha gates the host's visibility —
        // clear mask → fully hidden. Crucially this is layer-level and
        // has no UIView-API counterpart, so UIView.animate can't touch
        // it; the source stays invisible regardless of what press
        // animations fire. Layout-wise the source view stays at its
        // normal `frame` / `isHidden = false`, so the surrounding
        // stack / collection doesn't shift — a "view ghost" sits in
        // the button's slot.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let hideMask = CALayer()
        hideMask.frame = source.layer.bounds
        hideMask.backgroundColor = UIColor.clear.cgColor
        source.layer.mask = hideMask
        CATransaction.commit()
        CATransaction.flush()

        animateIn(
            dim: dim,
            sourceMinSide: min(sourceRectInHost.width, sourceRectInHost.height)
        )
    }

    // MARK: - Style-specific setup

    /// Wires up the `.morph` path: single-surface `ContextMenuMorphHostView`
    /// starting at source-rect, morphing to menu-rect driven by `progress`.
    /// Source snapshot lives inside `sourceContent`, actions view inside
    /// `destinationContent` — the host owns all cross-fade / shadow / shape
    /// choreography internally.
    private func setupMorphStyle(
        host: UIView,
        source: UIView,
        effect: UIVisualEffect,
        snapshot: UIView,
        actionsView: ContextMenuActionsView,
        sourceRectInHost: CGRect,
        sourceCornerRadius: CGFloat,
        menuFrame: CGRect
    ) {
        let morphHost = ContextMenuMorphHostView(effect: effect)
        morphHost.frame = sourceRectInHost
        host.addSubview(morphHost)
        morphHost.configure(metrics: ContextMenuMorphHostView.Metrics(
            collapsedFrame: sourceRectInHost,
            collapsedCornerRadius: sourceCornerRadius,
            expandedFrame: menuFrame,
            expandedCornerRadius: ContextMenuActionsView.cornerRadius
        ))
        morphHost.progress = 0

        // Snapshot: sits at (0,0) inside sourceContent, full source size.
        // It rides along when the host grows because it's inside the
        // container's content; the container itself stays source-sized
        // (it fades out before the host finishes expanding, so never
        // visibly stretches).
        snapshot.frame = CGRect(origin: .zero, size: sourceRectInHost.size)
        snapshot.autoresizingMask = []
        morphHost.sourceContent.addSubview(snapshot)

        // Actions view: (0,0), expanded size. Morph host handles alpha
        // + translateY per-progress internally.
        actionsView.frame = CGRect(origin: .zero, size: menuFrame.size)
        actionsView.autoresizingMask = []
        morphHost.destinationContent.addSubview(actionsView)

        self.morphHost = morphHost
        self.menuContainer = morphHost.glass

        // SDF lens (iOS 26+): installs on the morph host's layer so the
        // liquid refraction follows the morphing bounds. Updates per
        // progress-tick via the `animateProgress(step:)` callback in
        // `animateInMorph` / `animateOutMorph`.
        if #available(iOS 26.0, *), let filter = LensSDFFilter() {
            filter.install(on: morphHost.layer, size: sourceRectInHost.size, cornerRadius: sourceCornerRadius)
            self.sdfFilter = filter
        }
    }

    /// Wires up the `.preview` path: static glass menu + a lifted snapshot
    /// of the source above it. No morph — just a spring-in and the snapshot
    /// scaling up by `lift`.
    private func setupPreviewStyle(
        host: UIView,
        source: UIView,
        effect: UIVisualEffect,
        snapshot: UIView,
        actionsView: ContextMenuActionsView,
        sourceRectInHost: CGRect,
        menuFrame: CGRect
    ) {
        let sdfHost = UIView(frame: menuFrame)
        sdfHost.layer.cornerRadius = ContextMenuActionsView.cornerRadius
        sdfHost.layer.masksToBounds = true
        if #available(iOS 13.0, *) {
            sdfHost.layer.cornerCurve = .continuous
        }
        host.addSubview(sdfHost)
        self.sdfHost = sdfHost

        let menuContainer = UIVisualEffectView(effect: effect)
        menuContainer.frame = sdfHost.bounds
        menuContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sdfHost.addSubview(menuContainer)
        self.menuContainer = menuContainer

        // Lifted snapshot: its own wrapper at source rect with a soft
        // drop-shadow. Stays visible for the whole menu's lifetime.
        let preview = UIView(frame: sourceRectInHost)
        snapshot.frame = preview.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        preview.addSubview(snapshot)
        preview.layer.shadowColor = UIColor.black.cgColor
        preview.layer.shadowOpacity = 0.18
        preview.layer.shadowRadius = 18.0
        preview.layer.shadowOffset = CGSize(width: 0, height: 8)
        host.addSubview(preview)
        self.previewView = preview

        // Actions view fills the menu container.
        actionsView.frame = CGRect(origin: .zero, size: menuFrame.size)
        actionsView.autoresizingMask = []
        actionsView.alpha = 1.0
        menuContainer.contentView.addSubview(actionsView)

        // Pre-stage for spring-in.
        sdfHost.alpha = 0.0
        sdfHost.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
    }

    public func dismiss(animated: Bool = true) {
        guard isPresented else { return }
        isPresented = false

        let host = hostView
        let dim = dimView
        let morphHost = self.morphHost
        let sdfHost = self.sdfHost
        let container = menuContainer
        let snapshot = snapshotView
        let actionsView = self.actionsView
        let sourceView = source.view

        var didClean = false
        let cleanup: () -> Void = { [weak self] in
            if didClean { return }
            didClean = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Drop the transparent hide-mask (paired with `present`'s
            // `source.layer.mask = hideMask`). The source becomes visible
            // again with its original layout + frame intact — no isHidden
            // / alpha to restore because we never touched either.
            sourceView?.layer.mask = nil
            CATransaction.commit()
            if #available(iOS 26.0, *), let filter = self?.sdfFilter as? LensSDFFilter {
                filter.uninstall()
            }
            dim?.removeFromSuperview()
            morphHost?.removeFromSuperview()
            sdfHost?.removeFromSuperview()
            container?.removeFromSuperview()
            actionsView?.removeFromSuperview()
            snapshot?.removeFromSuperview()
            self?.previewView?.removeFromSuperview()
            host?.removeFromSuperview()
            self?.hostView = nil
            self?.dimView = nil
            self?.morphHost = nil
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

        guard animated else { cleanup(); return }

        switch presentationStyle {
        case .morph:
            animateOutMorph(dim: dim, cleanup: cleanup)
        case .preview:
            if let sdfHost {
                animateOutPreview(sdfHost: sdfHost, dim: dim, preview: previewView)
                // preview close doesn't currently wire a completion-cleanup
                // callback; fire cleanup on the expected duration + safety.
                DispatchQueue.main.asyncAfter(deadline: .now() + ContextMenuController.dismissDuration) { cleanup() }
                DispatchQueue.main.asyncAfter(deadline: .now() + ContextMenuController.dismissDuration + 0.2) { cleanup() }
            } else {
                cleanup()
            }
        }
    }

    /// Reverse the `.morph` presentation: drive `progress` back to 0 with
    /// a shorter duration (per the rec: "closing should be quicker and
    /// less elastic than opening"). The smoothstep windows inside the
    /// morph host handle the asymmetry automatically — destination fades
    /// out first (t drops past 0.42→0.28), source re-materialises only at
    /// the tail (t past 0.16→0.02). No separate ab-symmetric animators.
    private func animateOutMorph(
        dim: UIView?,
        cleanup: @escaping () -> Void
    ) {
        guard let morphHost else { cleanup(); return }

        // Reset any active stretch transform instantly so the reverse
        // morph doesn't fight with a scale/translate left over from the
        // user's last action-row touch.
        morphHost.transform = .identity

        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn], animations: {
            dim?.alpha = 0.0
        })

        morphHost.animateProgress(
            to: 0,
            duration: ContextMenuController.dismissDuration,
            damping: 1.0,  // critically damped: no bounce either direction
            step: { [weak self] _ in
                guard let self, let filter = self.sdfFilter else { return }
                if #available(iOS 26.0, *), let sdfFilter = filter as? LensSDFFilter {
                    sdfFilter.updateLayout(
                        size: morphHost.bounds.size,
                        cornerRadius: morphHost.glass.layer.cornerRadius
                    )
                }
            },
            completion: { _ in cleanup() }
        )

        // SDF lens displacement during the shrink — small tail wobble that
        // sells the "liquid stretches back" feeling without overdoing it.
        if #available(iOS 26.0, *), let filter = sdfFilter as? LensSDFFilter {
            let minSide = min(sourceRectInHost.width, sourceRectInHost.height)
            filter.animateDisplacement(
                fromHeight: 0.001, toHeight: minSide * 0.18,
                duration: ContextMenuController.dismissDuration
            )
            filter.animateBlur(duration: ContextMenuController.dismissDuration)
        }
    }

    /// Reverse the `.preview` presentation: lifted preview drops back to
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
        sourceMinSide: CGFloat
    ) {
        // Dim fades in either way. Shallow alpha per the rec ("very faint
        // separation layer, not a modal black overlay").
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut], animations: {
            dim.alpha = 1.0
        })

        switch presentationStyle {
        case .morph:
            animateInMorph(sourceMinSide: sourceMinSide)
        case let .preview(_, lift):
            if let sdfHost { animateInPreview(sdfHost: sdfHost, lift: lift) }
        }
    }

    /// Drive the morph host's `progress` from 0 → 1. Everything else —
    /// source snapshot fading out at t=0.02…0.16, menu fading in at
    /// t=0.28…0.42 with a 8pt translateY, shadow thickening, corner
    /// radius interpolation — is owned by the host's `updateForProgress`
    /// and driven off a single display-link timeline.
    private func animateInMorph(sourceMinSide: CGFloat) {
        guard let morphHost else { return }

        morphHost.animateProgress(
            to: 1,
            duration: ContextMenuController.morphDuration,
            // Critically damped — `damping = 1.0` is now a proper
            // damping ratio, which means zero overshoot, no oscillation,
            // just a monotonic soft settle into the final menu rect.
            // User feedback: "спринг всё ещё сильный" → kill the bounce
            // entirely. The blob phase still reads as liquid because the
            // size + corner pulse are driven off progress (which is now
            // smoother / non-oscillating), not off the spring itself.
            damping: 1.0,
            step: { [weak self] _ in
                guard let self, let filter = self.sdfFilter else { return }
                if #available(iOS 26.0, *), let sdfFilter = filter as? LensSDFFilter {
                    sdfFilter.updateLayout(
                        size: morphHost.bounds.size,
                        cornerRadius: morphHost.glass.layer.cornerRadius
                    )
                }
            },
            completion: nil
        )

        // SDF wobble (iOS 26 only) — extra "lens" kick layered on top of
        // the geometric morph. The recommendation lists this as the
        // "Premium" option; we already have the filter from previous work
        // so it's free to keep.
        if #available(iOS 26.0, *), let filter = sdfFilter as? LensSDFFilter {
            filter.animateDisplacement(
                fromHeight: sourceMinSide * 0.25, toHeight: 0.001,
                duration: ContextMenuController.morphDuration
            )
            filter.animateBlur(duration: ContextMenuController.morphDuration)
        }
    }

    /// Lifted preview + below-source menu spring-in (no morph).
    private func animateInPreview(sdfHost: UIView, lift: CGFloat) {
        // sdfHost was pre-staged at scale 0.9 + alpha 0; spring it to
        // identity. Menu chrome reads as "appearing fresh below the lifted
        // preview".
        UIView.animate(
            withDuration: ContextMenuController.morphDuration,
            delay: 0,
            usingSpringWithDamping: 0.72,
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
                usingSpringWithDamping: 0.72,
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
