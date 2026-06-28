import UIKit

// MARK: - ContextMenuController

/// Presents a `ContextMenuActionsView` as a glass-owned interaction. The
/// default `.morph` path keeps the older rounded-rect morph, while
/// `.fluidMorph` uses a source-to-platter bloom: one visible glass surface
/// expands from the source frame through a soft bubble into the final menu.
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

    /// Open / close timings. Tuned for the `.fluidMorph` spring — deliberately
    /// longer than a typical tap response so the overshoot is actually visible
    /// and the cross-fade has room to breathe. `.morph` uses the same numbers
    /// as a convenient fallback (its internal progress driver reshapes them
    /// into its own phase budget).
    ///
    ///   open    ~ 0.36s  soft spring-driven ease-out; the overshoot lives in
    ///                    the main geometry curve, not as a late extra pulse.
    ///   dismiss ~ 0.28s  inverse curve: decisive start, soft source settle.
    private static let morphDuration: TimeInterval = 0.36
    private static let dismissDuration: TimeInterval = 0.28
    private static let previewDismissDuration: TimeInterval = 0.34
    private static let previewDismissMenuScale: CGFloat = 0.82
    private static let previewDismissMenuOffsetY: CGFloat = 14.0
    private static let previewDismissAccessoryScale: CGFloat = 0.84
    /// `damping` is the spring's damping ratio for the display-link solvers.
    ///   1.0 = critically damped (no bounce, just glides in)
    ///   0.7 = noticeable overshoot, ~one settle cycle — "fluid"
    ///   0.5 = lots of wobble
    /// 0.72 is the sweet spot for "tactile, playful, but not silly".
    /// Close uses 0.86 — much firmer, just enough give to not feel
    /// snap-to-invisibility.
    private static let morphDamping: CGFloat = 0.72
    private static let dismissDamping: CGFloat = 0.84

    private static let dimAlpha: CGFloat = 0.08  // very faint separation veil (rec: ≤0.06-0.12)
    /// Radius of the backdrop blur applied to the dim layer, in points.
    /// Uses a raw CABackdropLayer + CAFilter("gaussianBlur"), so any
    /// non-negative radius works (unlike UIBlurEffect which snaps to
    /// a few fixed styles). 0 disables the blur and falls back to a
    /// plain tint. 2pt is the "barely-there" default — enough to
    /// soften the edges of background content without making it
    /// unreadable.
    public static var dimBlurRadius: CGFloat = 0.05
    public static var previewBlurRadius: CGFloat {
        get { dimBlurRadius }
        set { dimBlurRadius = newValue }
    }
    private static let menuCornerRadius: CGFloat = 34.0

    // MARK: - Glass lift metrics
    //
    // "Glass lift" = the expressive press feedback on the menu surface
    // (borrowed from Telegram's Display-framework `TouchEffect`). Three
    // components:
    //
    //   1. Base lift — uniform scale up by `pressedSizeIncrease` on the
    //      shorter axis, so the whole glass surface visibly rises on
    //      press. For a 260×200 menu, 14pt on the short axis = +7%
    //      scale — clearly visible without being cartoonish.
    //   2. Anisotropic stretch — biased scale along the axis of the
    //      finger's pull-direction (drag→right-bottom stretches Y and
    //      slightly squishes X, etc.). Gives soft-body physics feel.
    //   3. Translation — the surface shifts up to `stretchMaxOffset`
    //      toward the finger, adding to the "drawn to the touch" feel.
    //
    // The old rubber-band (`stretchFollow = 0.06`, `pressScale = 1.012`)
    // was too subtle to read as "glass lift" — it was more of a
    // micro-nudge. Bumped to TouchEffect-style math for expressive
    // iOS 26-style glass feedback.
    private static let stretchPressedSizeIncrease: CGFloat = 14.0
    private static let stretchMaxOffset: CGFloat = 20.0

    // MARK: - Self-retention

    private static var presentedControllers: Set<ContextMenuControllerBox> = []
    private lazy var retainBox = ContextMenuControllerBox(controller: self)

    // MARK: - Inputs

    public struct Source {
        public weak var view: UIView?
        public var cornerRadius: CGFloat?
        /// Legacy opt-in for anchors that explicitly need the real source
        /// hidden while the snapshot inside the morph surface replaces it.
        /// Layout doesn't shift either way — we drive alpha, not `isHidden`.
        public var hidesDuringPresentation: Bool

        public init(view: UIView, cornerRadius: CGFloat? = nil, hidesDuringPresentation: Bool = false) {
            self.view = view
            self.cornerRadius = cornerRadius
            self.hidesDuringPresentation = hidesDuringPresentation
        }
    }

    public struct PreviewContent {
        public let view: UIView
        public let preferredSize: CGSize

        public init(view: UIView, preferredSize: CGSize) {
            self.view = view
            self.preferredSize = preferredSize
        }
    }

    public struct PreviewAccessory {
        public let view: UIView
        public let preferredSize: CGSize?
        public let spacing: CGFloat

        public init(view: UIView, preferredSize: CGSize? = nil, spacing: CGFloat = 8.0) {
            self.view = view
            self.preferredSize = preferredSize
            self.spacing = spacing
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
        case preview(
            verticalSpacing: CGFloat = 8.0,
            lift: CGFloat = 1.04,
            content: PreviewContent? = nil,
            accessory: PreviewAccessory? = nil
        )
        /// Lens-bloom presentation. A small optical seed appears near the
        /// future menu anchor, expands as a circular/oval lens, then rectifies
        /// into the final rounded menu platter.
        case fluidMorph
    }

    // MARK: - State

    private let source: Source
    private let items: [ContextMenuItem]
    private let presentationStyle: PresentationStyle
    private let onWillRemoveOverlay: (() -> Void)?
    private let onDismiss: (() -> Void)?
    private let catchTapsOutside: Bool
    private let hasHapticFeedback: Bool
    private let blurred: Bool
    private let isDark: Bool?
    private let skipCoordinateConversion: Bool

    private weak var hostView: UIView?
    private var dimView: UIView?
    /// For `.morph` style: the single-surface morph host — one view that
    /// holds glass + shadow + source/destination content containers and
    /// morphs between source-rect and menu-rect under `progress: 0…1`.
    /// For `.preview` style: left `nil`; `sdfHost` is used as the outer
    /// wrapper instead.
    private var morphHost: ContextMenuMorphHostView?
    /// For `.fluidMorph` style: source-to-platter bloom host. The host itself
    /// is transparent; its single visible glass surface animates frame and
    /// corner radius from source to menu.
    private var platterBloomHost: ContextMenuSourcePlatterBloomTransitionView?
    /// For `.preview` style only: the outer wrapper holding the (static-
    /// size) glass menu. Left `nil` for `.morph` — morphHost plays that role.
    private var sdfHost: UIView?
    private var sdfFilter: AnyObject?  // erased LensSDFFilter? for pre-iOS-26 build
    private var menuContainer: MenuGlassSurfaceView?
    private var snapshotView: UIView?
    private var actionsView: ContextMenuActionsView?
    private var tapRecognizer: UITapGestureRecognizer?
    private var sourcePresentationLease: SourcePresentationLease?
    /// The view that plays the role of "the glass surface hit-test target"
    /// for submenu + stretch purposes. For `.morph` this is `morphHost`;
    /// for `.fluidMorph` it's the platter bloom glass surface; for `.preview` it's
    /// `sdfHost`. Collapsed into a single property so downstream wiring
    /// code doesn't have to branch on presentation style.
    private var surfaceView: UIView? { morphHost ?? platterBloomHost?.finalMenuGlassSurfaceView ?? sdfHost }
    private var surfaceOverlayView: UIView? { surfaceView }
    /// Inline submenu overlay (Yandex Music style). When non-nil, the parent
    /// `actionsView` is dimmed + disabled and `submenuCard` is overlaid on
    /// the parent menu, anchored to the source row's Y position. Tap on the
    /// card's header chevron OR on the dimmed parent collapses it.
    private var submenuCard: MenuGlassSurfaceView?
    private var submenuActions: ContextMenuActionsView?
    /// Transparent hit-target placed inside the active menu surface while a
    /// submenu is open: catches taps that miss the submenu card and collapses
    /// instead of dismissing the entire menu.
    private var submenuCollapseHitView: UIView?

    /// Lifted snapshot of the source view, only created in `.preview` style.
    /// Lives in `host` next to `dim` and `sdfHost`; positioned at the source's
    /// screen rect, scaled by `PresentationStyle.preview.lift`.
    private var previewView: UIView?
    private var previewAccessoryContainer: UIView?
    private var previewInitialCenterInHost: CGPoint?
    private var previewFinalCenterInHost: CGPoint?

    private var menuFrameInHost: CGRect = .zero
    private var sourceRectInHost: CGRect = .zero
    private var sourceCornerRadius: CGFloat = 0

    private var isPresented: Bool = false
    /// Whether the glass-lift stretch is currently applied to the
    /// surface (parent menu pressed). Tracked so the first touch-down
    /// runs as a proper spring animation (identity → lifted pose) and
    /// subsequent drag updates just snap the transform (hi-frequency
    /// tracking needs no additional smoothing — the UIView animation
    /// machinery would fight the finger otherwise).
    private var isStretchActive: Bool = false
    private var dismissHandle: ContextMenuDismissHandle?
    /// Original `source.layer.opacity` captured on present when
    /// `Source.hidesDuringPresentation == true`, so dismiss can restore it.
    private var savedSourceOpacity: Float?
    /// Original source transform captured while the menu owns the source
    /// fade/scale. Restored on dismiss so anchors that already had a custom
    /// transform are not flattened to identity.
    private var savedSourceTransform: CGAffineTransform?
    private var savedSourceIsUserInteractionEnabled: Bool?

    // MARK: - Init

    public init(
        source: Source,
        items: [ContextMenuItem],
        presentationStyle: PresentationStyle = .morph,
        catchTapsOutside: Bool = true,
        hasHapticFeedback: Bool = true,
        blurred: Bool = true,
        isDark: Bool? = nil,
        skipCoordinateConversion: Bool = false,
        onWillRemoveOverlay: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.source = source
        self.items = items
        self.presentationStyle = presentationStyle
        self.catchTapsOutside = catchTapsOutside
        self.hasHapticFeedback = hasHapticFeedback
        self.blurred = blurred
        self.isDark = isDark
        self.skipCoordinateConversion = skipCoordinateConversion
        self.onWillRemoveOverlay = onWillRemoveOverlay
        self.onDismiss = onDismiss
    }

    // MARK: - Public entry points

    /// Present the menu as an overlay on the window hosting the source view.
    public func present() {
        guard !isPresented, let source = source.view, let window = source.window else { return }
        isPresented = true
        ContextMenuController.presentedControllers.insert(retainBox)
        if hasHapticFeedback {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        let host = UIView(frame: window.bounds)
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(host)
        self.hostView = host

        // Dim layer + tap-to-dismiss target. Uses a custom
        // CABackdropLayer-based blur (see `ContextMenuDimBlurView`)
        // so the radius is continuously configurable via
        // `dimBlurRadius`. At the default 2pt radius the background
        // is just barely softened, not frosted.
        let dim: UIView
        if blurred {
            dim = ContextMenuDimBlurView(
                blurRadius: ContextMenuController.dimBlurRadius,
                tintAlpha: ContextMenuController.dimAlpha
            )
        } else {
            let plainDim = UIView()
            plainDim.backgroundColor = UIColor.black.withAlphaComponent(ContextMenuController.dimAlpha)
            dim = plainDim
        }
        dim.frame = host.bounds
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.alpha = 0
        dim.isUserInteractionEnabled = catchTapsOutside
        host.addSubview(dim)
        self.dimView = dim

        // Compute menu metrics.
        let actionsView = ContextMenuActionsView(items: items)
        let maxWidth = min(host.bounds.width - 24.0, ContextMenuActionsView.preferredWidth)
        let menuSize = actionsView.preferredSize(maxWidth: maxWidth)
        var sourceCornerRadius = self.source.cornerRadius ?? source.layer.cornerRadius
        let activeSourceLease: SourcePresentationLease?
        let sourceVisualMode: ContextMenuSourceVisualMode?
        let sourceRectInHost: CGRect

        if case .fluidMorph = presentationStyle {
            guard let descriptor = makeSourceDescriptor(hitView: source, overlayView: host) else {
                host.removeFromSuperview()
                isPresented = false
                ContextMenuController.presentedControllers.remove(retainBox)
                return
            }
            let mode = descriptor.sourceMode
            let transitionMode: ContextMenuSourceVisualMode = .leasedGlassSource
            #if DEBUG
            print("ContextMenu source mode:", mode, "hit:", descriptor.hitView, "visual:", descriptor.visualView)
            #endif
            sourceVisualMode = transitionMode
            sourceCornerRadius = descriptor.sourceCornerRadius
            guard let lease = SourcePresentationLease(
                sourceID: ObjectIdentifier(descriptor.visualView),
                descriptor: descriptor,
                overlayView: host
            ) else {
                host.removeFromSuperview()
                isPresented = false
                ContextMenuController.presentedControllers.remove(retainBox)
                return
            }
            lease.acquire()
            self.sourcePresentationLease = lease
            activeSourceLease = lease
            sourceRectInHost = lease.sourceFrameInOverlay
            if sourceCornerRadius <= 0.0, Self.isGlassContextMenuSource(descriptor.visualView) || Self.isGlassContextMenuSource(descriptor.hitView) {
                sourceCornerRadius = min(sourceRectInHost.width, sourceRectInHost.height) / 2.0
            }
        } else if skipCoordinateConversion {
            activeSourceLease = nil
            sourceVisualMode = nil
            sourceRectInHost = source.frame
        } else {
            activeSourceLease = nil
            sourceVisualMode = nil
            sourceRectInHost = source.convert(source.bounds, to: host)
        }
        let previewLayout: PreviewLayout?
        let menuFrame: CGRect
        if case let .preview(verticalSpacing, lift, content, accessory) = presentationStyle {
            let layout = computePreviewLayout(
                sourceRect: sourceRectInHost,
                menuSize: menuSize,
                hostBounds: host.bounds,
                verticalSpacing: verticalSpacing,
                lift: lift,
                content: content,
                accessory: accessory
            )
            previewLayout = layout
            menuFrame = layout.menuFrame
        } else {
            previewLayout = nil
            menuFrame = computeMenuFrame(sourceRect: sourceRectInHost, menuSize: menuSize, hostBounds: host.bounds)
        }
        #if DEBUG
        if case .fluidMorph = presentationStyle {
            assert(menuFrame.width <= host.bounds.width - 32.0 || host.bounds.width < 64.0, "Context menu target frame must be menu-sized, not overlay-sized.")
            assert(menuFrame.height < host.bounds.height * 0.75 || host.bounds.height < 64.0, "Context menu target frame is too tall for platter bloom geometry.")
            assert(menuFrame != host.bounds, "Context menu target frame must not equal overlay bounds.")
        }
        #endif
        self.menuFrameInHost = menuFrame
        self.sourceRectInHost = sourceRectInHost
        self.sourceCornerRadius = sourceCornerRadius

        // Branch on style — they're different enough (morph = progress-
        // driven single surface; preview = static glass + lifted snapshot)
        // that a shared setup path stopped paying its way.
        let isDark = self.isDark ?? (source.traitCollection.userInterfaceStyle == .dark)
        let snapshot: UIView?
        if case .fluidMorph = presentationStyle {
            snapshot = nil
        } else {
            snapshot = makeSourceSnapshot(
                source: source,
                preferRenderedImage: {
                    if #available(iOS 26.0, *) {
                        switch presentationStyle {
                        case .morph, .fluidMorph:
                            return true
                        case .preview:
                            return false
                        }
                    } else {
                        return false
                    }
                }()
            )
        }
        self.snapshotView = snapshot

        switch presentationStyle {
        case .morph:
            guard let snapshot else { return }
            setupMorphStyle(
                host: host,
                source: source,
                isDark: isDark,
                snapshot: snapshot,
                actionsView: actionsView,
                sourceRectInHost: sourceRectInHost,
                sourceCornerRadius: sourceCornerRadius,
                menuFrame: menuFrame
            )
        case .fluidMorph:
            guard let sourceVisualMode else { return }
            setupFluidMorphStyle(
                host: host,
                isDark: isDark,
                sourceLease: activeSourceLease,
                sourceMode: sourceVisualMode,
                actionsView: actionsView,
                sourceRectInHost: sourceRectInHost,
                sourceCornerRadius: sourceCornerRadius,
                menuFrame: menuFrame
            )
        case .preview:
            guard let snapshot else { return }
            guard let previewLayout else { return }
            setupPreviewStyle(
                host: host,
                source: source,
                isDark: isDark,
                snapshot: snapshot,
                actionsView: actionsView,
                previewLayout: previewLayout
            )
        }
        self.actionsView = actionsView

        // Tap-outside to dismiss.
        if catchTapsOutside {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleBackgroundTap(_:)))
            dim.addGestureRecognizer(tap)
            self.tapRecognizer = tap
        }

        // Wire root actions view (callbacks + stretch hooks). `surfaceView`
        // is the view that both stretch and submenu positioning anchor to
        // — morphHost for .morph, sdfHost for .preview.
        let handle = ContextMenuDismissHandle(dismiss: { [weak self] animated in self?.dismiss(animated: animated) })
        self.dismissHandle = handle
        if let surface = surfaceView {
            wireActionsView(actionsView, handle: handle, surfaceView: surface)
        }

        // Haptic.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Preview hides the real source immediately because the lifted
        // snapshot replaces it visually. Morph-style menus hide the source
        // inside `animateInMorph`, in sync with the glass expansion, so the
        // source does not sit there unchanged under the menu.
        if case .preview = presentationStyle {
            // Drive `UIView.alpha` (not `CALayer.opacity` directly) so
            // UIKit observers see the change — iOS 26's glass-effect
            // pipeline tracks alpha through the UIView setter, and a
            // direct `layer.opacity` write bypasses that and leaves
            // the shared `UIGlassContainerEffect` in a half-broken
            // "interactive but invisible" state where sibling glass
            // views in the same container also stop reacting to touch.
            self.savedSourceOpacity = Float(source.alpha)
            self.savedSourceTransform = source.transform
            UIView.animate(
                withDuration: ContextMenuController.morphDuration * 0.42,
                delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
            ) {
                source.alpha = 0
            }
        }

        animateIn(
            dim: dim,
            sourceMinSide: min(sourceRectInHost.width, sourceRectInHost.height)
        )
    }

    private func makeSourceDescriptor(hitView: UIView, overlayView: UIView) -> ContextMenuSourceDescriptor? {
        let visualView = Self.visualContextMenuSource(for: hitView)
        let mode = resolvedContextMenuSourceMode(hitView: hitView, visualView: visualView)
        let frame = visualView.convert(visualView.bounds, to: overlayView)
        var radius = source.cornerRadius ?? visualView.layer.cornerRadius
        if radius <= 0.0, mode == .leasedGlassSource {
            radius = min(frame.width, frame.height) / 2.0
        }
        return ContextMenuSourceDescriptor(
            sourceID: ObjectIdentifier(visualView),
            hitView: hitView,
            visualView: visualView,
            overlayView: overlayView,
            sourceCornerRadius: radius,
            sourceMode: mode
        )
    }

    private func resolvedContextMenuSourceMode(hitView: UIView, visualView: UIView) -> ContextMenuSourceVisualMode {
        if source.hidesDuringPresentation {
            return .leasedGlassSource
        }
        return Self.isGlassContextMenuSource(visualView) || Self.isGlassContextMenuSource(hitView) ? .leasedGlassSource : .persistentSource
    }

    private static func visualContextMenuSource(for hitView: UIView) -> UIView {
        var current: UIView? = hitView
        while let view = current {
            if let group = view as? GlassControlGroup,
               let visual = group.visualSourceView(containing: hitView) {
                return visual
            }
            if let group = view.superview as? GlassControlGroup,
               let visual = group.visualSourceView(containing: hitView) {
                return visual
            }
            if isGlassVisualOwner(view) {
                return view
            }
            current = view.superview
        }
        return hitView
    }

    private static func isGlassVisualOwner(_ view: UIView) -> Bool {
        if view is GlassBarButtonView
            || view is GlassButton
            || view is GlassButtonView
            || view is GlassControlGroup
            || view is GlassControlPanel
            || view is GlassContextExtractableContainerView
            || view is GlassBackgroundView
            || view is GlassBackgroundContainerView
            || view is LiquidLensView
            || view is MenuGlassSurfaceView {
            return true
        }

        if #available(iOS 26.0, *),
           let effectView = view as? UIVisualEffectView,
           effectView.effect is UIGlassEffect {
            return true
        }

        let className = NSStringFromClass(type(of: view))
        return className.localizedCaseInsensitiveContains("Glass")
    }

    private static func isGlassContextMenuSource(_ view: UIView) -> Bool {
        if view is GlassBarButtonView
            || view is GlassButton
            || view is GlassButtonView
            || view is GlassControlGroup
            || view is GlassControlPanel
            || view is GlassContextExtractableContainerView
            || view is GlassBackgroundView
            || view is GlassBackgroundContainerView
            || view is LiquidLensView
            || view is MenuGlassSurfaceView {
            return true
        }

        if #available(iOS 26.0, *),
           let effectView = view as? UIVisualEffectView,
           effectView.effect is UIGlassEffect {
            return true
        }

        let className = NSStringFromClass(type(of: view))
        if className.localizedCaseInsensitiveContains("Glass") {
            return true
        }

        for subview in view.subviews {
            if isGlassContextMenuSource(subview) {
                return true
            }
        }
        return false
    }

    // MARK: - Style-specific setup

    /// Wires up the `.morph` path: single-surface `ContextMenuMorphHostView`
    /// starting at source-rect, morphing to menu-rect driven by `progress`.
    /// Source snapshot lives inside `sourceContent`, actions view inside
    /// `destinationContent` — the host owns all cross-fade / shadow / shape
    /// choreography internally.
    private func setupMorphStyle(
        host: UIView,
        source _: UIView,
        isDark: Bool,
        snapshot: UIView,
        actionsView: ContextMenuActionsView,
        sourceRectInHost: CGRect,
        sourceCornerRadius: CGFloat,
        menuFrame: CGRect
    ) {
        let morphHost = ContextMenuMorphHostView(isDark: isDark)
        morphHost.frame = sourceRectInHost
        host.addSubview(morphHost)

        let collapsedCornerRadius: CGFloat = sourceCornerRadius > 0 ? sourceCornerRadius : min(sourceRectInHost.width, sourceRectInHost.height) / 2
        morphHost.configure(metrics: ContextMenuMorphHostView.Metrics(
            collapsedFrame: sourceRectInHost,
            collapsedCornerRadius: collapsedCornerRadius,
            expandedFrame: menuFrame,
            expandedCornerRadius: ContextMenuActionsView.cornerRadius
        ))
        morphHost.progress = 0

        // Source snapshot is the visual seed: the user sees the tapped
        // glass/source continue inside the morph surface immediately,
        // then fade after the surface has started expanding.
        snapshot.frame = morphHost.sourceContent.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        morphHost.sourceContent.addSubview(snapshot)

        // Actions view: (0,0), expanded size. Morph host handles alpha
        // + translateY per-progress internally.
        actionsView.frame = CGRect(origin: .zero, size: menuFrame.size)
        actionsView.autoresizingMask = []
        actionsView.setRevealProgress(0)
        morphHost.destinationContent.addSubview(actionsView)
        morphHost.destinationRevealProgressChanged = { [weak actionsView] progress in
            actionsView?.setRevealProgress(progress)
        }

        self.morphHost = morphHost
        self.menuContainer = morphHost.glass

        // SDF lens (iOS 26+) on the `lensContainer` layer — the
        // known-working path. The prior attempt to locate the private
        // `_UIVisualEffectBackdropView`'s `CABackdropLayer` and append
        // our displacement filter to its chain silently produced no
        // visible distortion on iOS 26.5 (Apple's private visual-
        // effect pipeline seems to reject user-added filters). The
        // plain-view `lensContainer` path reliably composites the SDF
        // over the morph surface and lets `displacementMap` warp the
        // backdrop + foreground content. Menu content does pick up
        // the distortion mid-morph, but since the pulse decays to 0
        // well before the morph settles (see
        // `animateDisplacementPulse`), the action rows render crisp
        // at rest.
        if #available(iOS 26.0, *), let filter = LensSDFFilter() {
            filter.install(
                on: morphHost.lensContainer.layer,
                size: sourceRectInHost.size,
                cornerRadius: collapsedCornerRadius
            )
            self.sdfFilter = filter
        }
    }

    /// Walk `root`'s layer subtree and return the first `CABackdropLayer`
    /// instance. Used to locate the private backdrop layer inside a
    /// `UIVisualEffectView`'s `_UIVisualEffectBackdropView` without
    /// referencing private class names in Swift.
    private static func findBackdropLayer(in root: CALayer) -> CALayer? {
        let className = NSStringFromClass(type(of: root))
        if className.contains(ObfuscatedSymbols.caBackdropClass) {
            return root
        }
        guard let sublayers = root.sublayers else { return nil }
        for sublayer in sublayers {
            if let found = findBackdropLayer(in: sublayer) {
                return found
            }
        }
        return nil
    }

    /// Wires up the `.fluidMorph` path. One glass surface starts at the
    /// source frame, blooms into a bubble, then settles as the menu platter.
    private func setupFluidMorphStyle(
        host: UIView,
        isDark: Bool,
        sourceLease: SourcePresentationLease?,
        sourceMode: ContextMenuSourceVisualMode,
        actionsView: ContextMenuActionsView,
        sourceRectInHost: CGRect,
        sourceCornerRadius: CGFloat,
        menuFrame: CGRect
    ) {
        let platterHost = ContextMenuSourcePlatterBloomTransitionView(
            sourceFrameInOverlay: sourceRectInHost,
            targetMenuFrameInOverlay: menuFrame,
            finalCornerRadius: ContextMenuActionsView.cornerRadius,
            sourceCornerRadius: sourceCornerRadius,
            sourceMode: sourceMode,
            isDark: isDark
        )
        platterHost.frame = host.bounds
        platterHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(platterHost)

        // The platter bloom always owns the visual source while presented:
        // glass and plain/content sources are represented by the leased proxy,
        // so the real source never remains visible/interactive underneath.
        sourceLease?.attachProxy(to: platterHost.sourceProxyContainer)

        // Destination content is laid out at its final menu rect from the
        // beginning. The lens mask reveals it as the bloom grows/sharpens.
        actionsView.frame = platterHost.liveMenuContentView.bounds
        actionsView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        actionsView.setRevealProgress(1)
        platterHost.liveMenuContentView.addSubview(actionsView)
        platterHost.prepareMenuContentSnapshots(from: actionsView)
        actionsView.setRevealProgress(0)
        platterHost.contentRevealProgressChanged = { [weak actionsView] progress in
            actionsView?.setRevealProgress(progress)
        }

        self.platterBloomHost = platterHost
        self.menuContainer = platterHost.finalMenuGlassSurfaceView
    }

    private struct PreviewLayout {
        let initialPreviewFrame: CGRect
        let previewFrame: CGRect
        let menuFrame: CGRect
        let accessory: PreviewAccessory?
        let accessoryFrame: CGRect?
        let content: PreviewContent?
    }

    /// Wires up the `.preview` path: static glass menu + a lifted snapshot
    /// of the source above it. No morph — just a spring-in and the snapshot
    /// scaling up by `lift`.
    private func setupPreviewStyle(
        host: UIView,
        source _: UIView,
        isDark: Bool,
        snapshot: UIView,
        actionsView: ContextMenuActionsView,
        previewLayout: PreviewLayout
    ) {
        let menuFrame = previewLayout.menuFrame
        let sdfHost = UIView(frame: menuFrame)
        sdfHost.applyCornerRadius(ContextMenuActionsView.cornerRadius)
        host.addSubview(sdfHost)
        self.sdfHost = sdfHost

        let menuContainer = MenuGlassSurfaceView(isDark: isDark)
        menuContainer.frame = sdfHost.bounds
        menuContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sdfHost.addSubview(menuContainer)
        self.menuContainer = menuContainer

        // Lifted snapshot: its own wrapper at source rect with a soft
        // drop-shadow. Stays visible for the whole menu's lifetime.
        let preview = UIView(frame: previewLayout.initialPreviewFrame)
        let previewContentView = previewLayout.content?.view ?? snapshot
        previewContentView.frame = preview.bounds
        previewContentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        preview.addSubview(previewContentView)
        preview.layer.shadowColor = UIColor.black.cgColor
        preview.layer.shadowOpacity = 0.18
        preview.layer.shadowRadius = 18.0
        preview.layer.shadowOffset = CGSize(width: 0, height: 8)
        host.addSubview(preview)
        self.previewView = preview
        self.previewInitialCenterInHost = CGPoint(
            x: previewLayout.initialPreviewFrame.midX,
            y: previewLayout.initialPreviewFrame.midY
        )
        self.previewFinalCenterInHost = CGPoint(
            x: previewLayout.previewFrame.midX,
            y: previewLayout.previewFrame.midY
        )

        if let accessory = previewLayout.accessory,
           let accessoryFrame = previewLayout.accessoryFrame {
            let accessoryContainer = UIView(frame: accessoryFrame)
            accessoryContainer.clipsToBounds = false
            accessory.view.frame = accessoryContainer.bounds
            accessory.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            accessoryContainer.addSubview(accessory.view)
            host.addSubview(accessoryContainer)
            self.previewAccessoryContainer = accessoryContainer

            accessoryContainer.alpha = 0.0
            accessoryContainer.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }

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

        let sourceRestoreAlpha = savedSourceOpacity.map(CGFloat.init) ?? 1.0
        let sourceRestoreTransform = savedSourceTransform ?? .identity
        let sourceRestoreInteractionEnabled = savedSourceIsUserInteractionEnabled

        let host = hostView
        let dim = dimView
        let morphHost = self.morphHost
        let platterBloomHost = self.platterBloomHost
        let sdfHost = self.sdfHost
        let container = menuContainer
        let snapshot = snapshotView
        let actionsView = self.actionsView
        let sourceView = source.view
        let sourcePresentationLease = self.sourcePresentationLease
        let previewAccessoryContainer = self.previewAccessoryContainer

        var didClean = false
        let cleanup: () -> Void = { [weak self] in
            if didClean { return }
            didClean = true
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Defensive: clear any mask the source might carry. Prior
            // versions applied a transparent CALayer mask on `present`
            // to hide the source; current version keeps it visible for
            // SDF backdrop distortion and never sets a mask — this is
            // a no-op on the current path but stays as a safety net for
            // any future path that might re-introduce hiding.
            if sourcePresentationLease == nil {
                sourceView?.layer.mask = nil
            }
            // Defensive: restore transform/alpha in case the dismiss
            // path was non-animated (animated: false) or interrupted
            // before the spring finished — otherwise the source would
            // stay collapsed after a rapid dismiss.
            if sourcePresentationLease == nil {
                sourceView?.transform = sourceRestoreTransform
                sourceView?.alpha = sourceRestoreAlpha
                if let sourceRestoreInteractionEnabled {
                    sourceView?.isUserInteractionEnabled = sourceRestoreInteractionEnabled
                }
            }
            CATransaction.commit()
            self?.savedSourceOpacity = nil
            self?.savedSourceTransform = nil
            self?.savedSourceIsUserInteractionEnabled = nil
            if #available(iOS 26.0, *), let filter = self?.sdfFilter as? LensSDFFilter {
                filter.uninstall()
            }
            // Restore the leased source while the bloom surface is still
            // present at the source frame. Removing the host first leaves a
            // one-frame hole where the original button flashes back late.
            sourcePresentationLease?.release()
            // Tear down `UIGlassEffect` registrations BEFORE removing
            // the views from their superviews. iOS 26's
            // `UIGlassContainerEffect` keeps a list of registered
            // `UIGlassEffect`-bearing views, and `removeFromSuperview`
            // alone doesn't always remove them from that list — the
            // leak leaves the global container in a state where
            // `UIGlassEffect.isInteractive` deformation no longer plays
            // on other glass views in the same window after our menu
            // cycle. Setting `effect = nil` on each `UIVisualEffectView`
            // we own deregisters cleanly.
            container?.tearDownGlassEffect()
            self?.submenuCard?.tearDownGlassEffect()
            morphHost?.glass.tearDownGlassEffect()
            platterBloomHost?.finalMenuGlassSurfaceView.tearDownGlassEffect()
            self?.onWillRemoveOverlay?()
            dim?.removeFromSuperview()
            morphHost?.removeFromSuperview()
            platterBloomHost?.removeFromSuperview()
            sdfHost?.removeFromSuperview()
            container?.removeFromSuperview()
            actionsView?.removeFromSuperview()
            snapshot?.removeFromSuperview()
            self?.previewView?.removeFromSuperview()
            previewAccessoryContainer?.removeFromSuperview()
            host?.removeFromSuperview()
            self?.hostView = nil
            self?.dimView = nil
            self?.morphHost = nil
            self?.platterBloomHost = nil
            self?.sourcePresentationLease = nil
            self?.sdfHost = nil
            self?.sdfFilter = nil
            self?.menuContainer = nil
            self?.snapshotView = nil
            self?.previewView = nil
            self?.previewAccessoryContainer = nil
            self?.previewInitialCenterInHost = nil
            self?.previewFinalCenterInHost = nil
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

        // If an inline submenu card is open, fade it out *in parallel* with
        // the main menu's dismiss morph — otherwise it would stay fully
        // visible through the morph and then snap to invisible inside
        // `cleanup` (which runs `removeFromSuperview` synchronously). The
        // submenu's hit-target view is non-visual; nothing to animate there.
        if let submenuCard {
            UIView.animate(
                withDuration: ContextMenuController.dismissDuration,
                delay: 0,
                usingSpringWithDamping: 0.95,
                initialSpringVelocity: 0,
                options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction],
                animations: {
                    submenuCard.alpha = 0.0
                    submenuCard.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
                },
                completion: nil
            )
        }

        switch presentationStyle {
        case .morph:
            animateOutMorph(dim: dim, cleanup: cleanup)
        case .fluidMorph:
            animateOutFluidMorph(dim: dim, cleanup: cleanup)
        case .preview:
            if let sdfHost {
                animateOutPreview(
                    sdfHost: sdfHost,
                    dim: dim,
                    preview: previewView,
                    accessory: previewAccessoryContainer,
                    completion: cleanup
                )
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

        // Reset any active stretch transform instantly inside a
        // disabled-actions transaction so it doesn't trigger an
        // implicit 0.25 s animation that would race with the
        // dismiss animator. Without this wrap, the implicit anim
        // captured the previous `transform` value (e.g., last
        // value of the open's end-bounce keyframe) and tried to
        // animate to identity over its own timeline — which read
        // as the morph "snapping" to a state and the dismiss
        // animator running on top, perceived as instant by the
        // user.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        morphHost.transform = .identity
        CATransaction.commit()

        // Suppress the droplet silhouette on close — per the design
        // rec, the menu should just return to the button as a plain
        // rounded-rect shrink while the content cross-fades back to
        // the source snapshot. No droplet, no SDF lens.
        morphHost.suppressBlob = true

        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn], animations: {
            dim?.alpha = 0.0
        })

        let dismissDuration = ContextMenuController.dismissDuration

        // Morph anchors fade/scale out on open. Restore them with a single
        // UIKit animation instead of mutating the source from the morph
        // display-link; that keeps the source view out of the hot path that
        // also drives the SDF/filter layout.
        let shouldRestoreSourceView = savedSourceOpacity != nil || savedSourceTransform != nil || source.hidesDuringPresentation
        let sourceView = shouldRestoreSourceView ? source.view : nil
        let sourceTargetAlpha = savedSourceOpacity.map(CGFloat.init) ?? 1.0
        let sourceTargetTransform = savedSourceTransform ?? .identity
        sourceView?.layer.removeAllAnimations()
        if let sourceView {
            UIView.animate(
                withDuration: dismissDuration * 0.42,
                delay: dismissDuration * 0.34,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0.0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    sourceView.alpha = sourceTargetAlpha
                    sourceView.transform = sourceTargetTransform
                },
                completion: nil
            )
        }

        // CADisplayLink-driven progress: 1 → 0 over dismiss duration.
        // The progress passed into `step` is the spring-eased value
        // (== `progressValue`), which decreases 1 → 0 as the menu
        // collapses. For the SOURCE RESTORE we want a 0 → 1 ramp,
        // so we invert via `1 - progress`.
        morphHost.animateProgress(
            to: 0,
            duration: dismissDuration,
            damping: ContextMenuController.dismissDamping,
            step: { [weak self] progress in
                guard let self else { return }

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                defer { CATransaction.commit() }

                if #available(iOS 26.0, *),
                   let sdfFilter = self.sdfFilter as? LensSDFFilter {
                    sdfFilter.updateLayout(
                        size: morphHost.bounds.size,
                        cornerRadius: morphHost.glass.layer.cornerRadius
                    )
                }
            },
            completion: { _ in cleanup() }
        )

        // SDF pulse on dismiss too — `reversed: true` makes the
        // displacement rise from 0 → peak as the menu collapses
        // (mirror of the open path's HOLD-then-DECAY shape). Same
        // amplitude as the open so the lens reads symmetric on both
        // halves of the morph cycle.
        if #available(iOS 26.0, *), let filter = sdfFilter as? LensSDFFilter {
            let menuMinSide: CGFloat = {
                guard let metrics = morphHost.metrics else { return 1 }
                return min(metrics.expandedFrame.width, metrics.expandedFrame.height)
            }()
            filter.animateDisplacementPulse(
                peakHeight: menuMinSide * 0.16,
                duration: dismissDuration,
                reversed: true
            )
            filter.animateBlur(duration: dismissDuration)
        }
    }

    /// Reverse the `.preview` presentation: lifted preview drops back to
    /// identity scale; menu chrome scales/fades out.
    private func animateOutPreview(
        sdfHost: UIView,
        dim: UIView?,
        preview: UIView?,
        accessory: UIView?,
        completion: @escaping () -> Void
    ) {
        let sourceView = self.source.view
        let previewInitialCenter = self.previewInitialCenterInHost
        let menuDismissTransform = CGAffineTransform(
            translationX: 0,
            y: ContextMenuController.previewDismissMenuOffsetY
        ).scaledBy(
            x: ContextMenuController.previewDismissMenuScale,
            y: ContextMenuController.previewDismissMenuScale
        )
        let accessoryDismissTransform = CGAffineTransform(
            scaleX: ContextMenuController.previewDismissAccessoryScale,
            y: ContextMenuController.previewDismissAccessoryScale
        )

        UIView.animate(
            withDuration: ContextMenuController.previewDismissDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.dismissDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                // Make the close read as a real return: preview travels
                // back to the source while the menu visibly contracts.
                if let previewInitialCenter {
                    preview?.center = previewInitialCenter
                }
                sdfHost.transform = menuDismissTransform
                preview?.transform = .identity
                accessory?.transform = accessoryDismissTransform
            },
            completion: { _ in completion() }
        )

        UIView.animate(
            withDuration: ContextMenuController.previewDismissDuration * 0.58,
            delay: ContextMenuController.previewDismissDuration * 0.22,
            options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction],
            animations: {
                // Delayed fade keeps the geometry visible long enough to
                // read before the snapshot hands back to the real source.
                sdfHost.alpha = 0.0
                preview?.alpha = 0.0
                accessory?.alpha = 0.0
                sourceView?.alpha = 1.0
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
        case .fluidMorph:
            animateInFluidMorph()
        case let .preview(_, lift, _, _):
            if let sdfHost { animateInPreview(sdfHost: sdfHost, lift: lift) }
        }
    }

    /// Parallel open: the morph host owns all menu geometry. The real
    /// source view is faded/scaled once with UIKit, outside the progress
    /// display-link, so it visually disappears without becoming another
    /// per-frame moving target.
    private func animateInMorph(sourceMinSide: CGFloat) {
        guard let morphHost else { return }

        if source.hidesDuringPresentation, let sourceView = source.view {
            if savedSourceOpacity == nil {
                savedSourceOpacity = Float(sourceView.alpha)
            }
            if savedSourceTransform == nil {
                savedSourceTransform = sourceView.transform
            }
            sourceView.layer.removeAllAnimations()
            let baseTransform = savedSourceTransform ?? sourceView.transform
            UIView.animate(
                withDuration: ContextMenuController.morphDuration * 0.20,
                delay: ContextMenuController.morphDuration * 0.08,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: {
                    sourceView.alpha = 0.0
                    sourceView.transform = baseTransform.scaledBy(x: 0.985, y: 0.985)
                },
                completion: nil
            )
        }

        // Menu expansion starts IMMEDIATELY at t=0. The display-link step
        // is kept strictly to filter/layout updates; source animation runs
        // on a separate UIKit animator above.
        morphHost.alpha = 1
        morphHost.animateProgress(
            to: 1,
            duration: ContextMenuController.morphDuration,
            damping: ContextMenuController.morphDamping,
            step: { [weak self] progress in
                guard let self else { return }

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                defer { CATransaction.commit() }

                if #available(iOS 26.0, *),
                   let sdfFilter = self.sdfFilter as? LensSDFFilter {
                    sdfFilter.updateLayout(
                        size: morphHost.bounds.size,
                        cornerRadius: morphHost.glass.layer.cornerRadius
                    )
                }
            },
            completion: nil
        )

        // SDF pulse runs over the full morph duration. The pulse is
        // strongest in the first ~55 % and decays to 0 by ~88 %, so
        // the settled menu has no residual distortion.
        if #available(iOS 26.0, *), let filter = sdfFilter as? LensSDFFilter {
            let menuMinSide: CGFloat = {
                guard let metrics = morphHost.metrics else { return sourceMinSide }
                return min(metrics.expandedFrame.width, metrics.expandedFrame.height)
            }()
            filter.animateDisplacementPulse(
                peakHeight: menuMinSide * 0.16,
                duration: ContextMenuController.morphDuration
            )
            filter.animateBlur(duration: ContextMenuController.morphDuration)
        }
    }

    /// Drive the `.fluidMorph` host as one source-to-platter surface.
    private func animateInFluidMorph() {
        guard let platterBloomHost else { return }
        platterBloomHost.animateExpand(
            duration: ContextMenuController.morphDuration,
            damping: ContextMenuController.morphDamping,
            completion: nil
        )
    }

    /// Reverse of `animateInFluidMorph`: the menu platter shrinks back
    /// through the bubble/source path before cleanup restores the source.
    private func animateOutFluidMorph(
        dim: UIView?,
        cleanup: @escaping () -> Void
    ) {
        guard let platterBloomHost else { cleanup(); return }

        // Reset any active stretch transform first so the reverse morph
        // starts from identity, not from a press-release stretch left
        // over from the last touch.
        platterBloomHost.finalMenuGlassSurfaceView.resetGlassInteractionTransform()

        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn], animations: {
            dim?.alpha = 0.0
        })

        platterBloomHost.animateCollapse(
            duration: ContextMenuController.dismissDuration,
            damping: ContextMenuController.dismissDamping,
            completion: { cleanup() }
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
            let finalCenter = previewFinalCenterInHost ?? preview.center
            preview.transform = .identity
            UIView.animate(
                withDuration: ContextMenuController.morphDuration,
                delay: 0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    preview.center = finalCenter
                    preview.transform = CGAffineTransform(scaleX: lift, y: lift)
                },
                completion: nil
            )
        }

        if let accessory = previewAccessoryContainer {
            UIView.animate(
                withDuration: ContextMenuController.morphDuration,
                delay: 0,
                usingSpringWithDamping: 0.72,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    accessory.transform = .identity
                    accessory.alpha = 1.0
                },
                completion: nil
            )
        }
    }

    // MARK: - Source snapshot

    private func makeSourceSnapshot(source: UIView, preferRenderedImage: Bool = false) -> UIView {
        if !preferRenderedImage, let snap = source.snapshotView(afterScreenUpdates: false) {
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

    /// Non-preview menu placement. `.preview` uses `computePreviewLayout`
    /// because it owns a full vertical stack: accessory, preview, menu.
    ///
    /// Two layouts depending on `presentationStyle`:
    ///   - `.morph`: menu top-anchored to source.top — the lens visibly
    ///     grows downward + outward FROM the button.
    ///   - `.fluidMorph`: menu may cover the original trigger, matching
    ///     UIKit's menu-platter behavior.
    private func computeMenuFrame(sourceRect: CGRect, menuSize: CGSize, hostBounds: CGRect) -> CGRect {
        let window = source.view?.window
        let safeTop: CGFloat = max(window?.safeAreaInsets.top ?? hostView?.safeAreaInsets.top ?? 0.0, 12.0)
        let safeBottom: CGFloat = max(window?.safeAreaInsets.bottom ?? hostView?.safeAreaInsets.bottom ?? 0.0, 12.0)
        let x = computeMenuX(sourceRect: sourceRect, menuSize: menuSize, hostBounds: hostBounds)

        let initialY: CGFloat
        switch presentationStyle {
        case .morph:
            initialY = sourceRect.minY
        case .fluidMorph:
            // Lens bloom behaves like UIKit's menu platter: it may cover the
            // original trigger. Keeping a source gap makes the lens look like
            // a detached popover and also leaves the trigger awkwardly visible
            // beside the menu.
            let downward = sourceRect.minY
            let upward = sourceRect.maxY - menuSize.height
            if downward + menuSize.height <= hostBounds.maxY - safeBottom {
                initialY = downward
            } else if upward >= safeTop {
                initialY = upward
            } else {
                initialY = min(
                    max(safeTop, downward),
                    hostBounds.maxY - safeBottom - menuSize.height
                )
            }
        case let .preview(spacing, _, _, _):
            initialY = sourceRect.maxY + spacing
        }

        var y = initialY
        if y + menuSize.height > hostBounds.maxY - safeBottom {
            let upward: CGFloat
            if case let .preview(spacing, _, _, _) = presentationStyle {
                upward = sourceRect.minY - max(0.0, spacing) - menuSize.height
            } else {
                upward = sourceRect.maxY - menuSize.height
            }
            if upward >= safeTop {
                y = upward
            } else {
                y = hostBounds.maxY - safeBottom - menuSize.height
            }
        }

        return CGRect(x: x, y: y, width: menuSize.width, height: menuSize.height)
    }

    private func computePreviewLayout(
        sourceRect: CGRect,
        menuSize: CGSize,
        hostBounds: CGRect,
        verticalSpacing: CGFloat,
        lift: CGFloat,
        content: PreviewContent?,
        accessory: PreviewAccessory?
    ) -> PreviewLayout {
        let sideInset: CGFloat = 12.0
        let window = source.view?.window
        let safeTop: CGFloat = max(window?.safeAreaInsets.top ?? hostView?.safeAreaInsets.top ?? 0.0, 12.0)
        let safeBottom: CGFloat = max(window?.safeAreaInsets.bottom ?? hostView?.safeAreaInsets.bottom ?? 0.0, 12.0)
        let maxContentWidth = max(0.0, hostBounds.width - sideInset * 2.0)
        let safeBottomY = hostBounds.maxY - safeBottom
        let spacing = max(0.0, verticalSpacing)

        let previewSize = content?.preferredSize ?? sourceRect.size
        let effectiveLift = max(0.01, lift)

        let accessorySize = resolvedPreviewAccessorySize(
            accessory,
            maxWidth: maxContentWidth,
            fallbackWidth: min(max(previewSize.width, menuSize.width), maxContentWidth)
        )
        let hasAccessory = accessory != nil && accessorySize.width > 0.0 && accessorySize.height > 0.0
        let accessorySpacing = hasAccessory ? max(0.0, accessory?.spacing ?? 0.0) : 0.0
        let topBlockHeight = hasAccessory ? accessorySpacing + accessorySize.height : 0.0

        let initialPreviewFrame: CGRect
        if content == nil {
            initialPreviewFrame = sourceRect
        } else {
            initialPreviewFrame = CGRect(
                x: sourceRect.midX - previewSize.width / 2.0,
                y: sourceRect.midY - previewSize.height / 2.0,
                width: previewSize.width,
                height: previewSize.height
            )
        }
        let initialLiftedPreviewFrame = initialPreviewFrame.insetBy(
            dx: -initialPreviewFrame.width * (effectiveLift - 1.0) / 2.0,
            dy: -initialPreviewFrame.height * (effectiveLift - 1.0) / 2.0
        )
        let requiredBottomOverflow = max(
            0.0,
            initialLiftedPreviewFrame.maxY + spacing + menuSize.height - safeBottomY
        )
        let maxUpwardShift = max(
            0.0,
            initialLiftedPreviewFrame.minY - topBlockHeight - safeTop
        )
        let upwardShift = min(requiredBottomOverflow, maxUpwardShift)
        let previewFrame = initialPreviewFrame.offsetBy(dx: 0.0, dy: -upwardShift)
        let liftedPreviewFrame = previewFrame.insetBy(
            dx: -previewFrame.width * (effectiveLift - 1.0) / 2.0,
            dy: -previewFrame.height * (effectiveLift - 1.0) / 2.0
        )

        let accessoryFrame: CGRect?
        if hasAccessory {
            var accessoryX = liftedPreviewFrame.midX - accessorySize.width / 2.0
            accessoryX = max(sideInset, min(accessoryX, hostBounds.maxX - sideInset - accessorySize.width))
            accessoryFrame = CGRect(
                x: accessoryX,
                y: liftedPreviewFrame.minY - accessorySpacing - accessorySize.height,
                width: accessorySize.width,
                height: accessorySize.height
            )
        } else {
            accessoryFrame = nil
        }

        let menuX = computePreviewMenuX(sourceRect: previewFrame, menuSize: menuSize, hostBounds: hostBounds)
        let menuY = liftedPreviewFrame.maxY + spacing

        return PreviewLayout(
            initialPreviewFrame: initialPreviewFrame,
            previewFrame: previewFrame,
            menuFrame: CGRect(x: menuX, y: menuY, width: menuSize.width, height: menuSize.height),
            accessory: accessory,
            accessoryFrame: accessoryFrame,
            content: content
        )
    }

    private func resolvedPreviewAccessorySize(
        _ accessory: PreviewAccessory?,
        maxWidth: CGFloat,
        fallbackWidth: CGFloat
    ) -> CGSize {
        guard let accessory else { return .zero }
        if let preferredSize = accessory.preferredSize {
            return CGSize(
                width: min(maxWidth, max(0.0, preferredSize.width)),
                height: max(0.0, preferredSize.height)
            )
        }

        let fittingTarget = CGSize(width: maxWidth, height: UIView.layoutFittingCompressedSize.height)
        let fittingSize = accessory.view.systemLayoutSizeFitting(
            fittingTarget,
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
        let sizeThatFits = accessory.view.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        let intrinsicSize = accessory.view.intrinsicContentSize

        let width = firstPositive(
            fittingSize.width,
            accessory.view.bounds.width,
            sizeThatFits.width,
            intrinsicSize.width == UIView.noIntrinsicMetric ? 0.0 : intrinsicSize.width,
            fallbackWidth
        )
        let height = firstPositive(
            fittingSize.height,
            accessory.view.bounds.height,
            sizeThatFits.height,
            intrinsicSize.height == UIView.noIntrinsicMetric ? 0.0 : intrinsicSize.height
        )

        return CGSize(width: min(maxWidth, width), height: height)
    }

    private func firstPositive(_ values: CGFloat...) -> CGFloat {
        for value in values where value > 0.0 && value.isFinite {
            return value
        }
        return 0.0
    }

    private func computePreviewMenuX(sourceRect: CGRect, menuSize: CGSize, hostBounds: CGRect) -> CGFloat {
        let sideInset: CGFloat = 12.0
        let centerTolerance: CGFloat = 24.0
        let leftAlignedX = sourceRect.minX
        let rightAlignedX = sourceRect.maxX - menuSize.width
        let centerAlignedX = sourceRect.midX - menuSize.width / 2.0

        let preferredX: CGFloat
        if abs(sourceRect.midX - hostBounds.midX) <= centerTolerance {
            preferredX = centerAlignedX
        } else if sourceRect.midX < hostBounds.midX {
            preferredX = leftAlignedX
        } else {
            preferredX = rightAlignedX
        }

        let maxX = max(sideInset, hostBounds.maxX - sideInset - menuSize.width)
        return min(max(sideInset, preferredX), maxX)
    }

    private func computeMenuX(sourceRect: CGRect, menuSize: CGSize, hostBounds: CGRect) -> CGFloat {
        let sideInset: CGFloat = 12.0

        // Horizontal alignment strategy (restored — rolled back the
        // "always centre on source" attempt). The menu picks an
        // edge-aligned position that fits on screen; the animation
        // bubble is then placed at the menu's own midpoint (see
        // `setupMorphStyle`'s droplet), so the morph is a pure
        // bilateral expansion out of the menu's centre with no
        // cross-animation drift — regardless of how far that centre
        // ends up from the source.
        let leftAlignedX = sourceRect.minX
        let rightAlignedX = sourceRect.maxX - menuSize.width
        let centreAlignedX = sourceRect.midX - menuSize.width / 2

        let fitsLeftAligned = leftAlignedX >= sideInset
            && leftAlignedX + menuSize.width <= hostBounds.maxX - sideInset
        let fitsRightAligned = rightAlignedX >= sideInset
            && rightAlignedX + menuSize.width <= hostBounds.maxX - sideInset
        let fitsCentreAligned = centreAlignedX >= sideInset
            && centreAlignedX + menuSize.width <= hostBounds.maxX - sideInset

        let sourceCentreIsOnRight = sourceRect.midX > hostBounds.midX

        var x: CGFloat
        if fitsCentreAligned {
            x = centreAlignedX
        } else if sourceCentreIsOnRight && fitsRightAligned {
            x = rightAlignedX
        } else if !sourceCentreIsOnRight && fitsLeftAligned {
            x = leftAlignedX
        } else if fitsRightAligned {
            x = rightAlignedX
        } else {
            x = leftAlignedX
        }
        x = max(sideInset, x)
        if x + menuSize.width > hostBounds.maxX - sideInset {
            x = hostBounds.maxX - sideInset - menuSize.width
        }
        return x
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
        surfaceView: UIView,
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
        view.onStretchUpdate = nil
        view.onStretchRelease = nil

        if let glassSurface = surfaceView as? MenuGlassSurfaceView {
            glassSurface.gestureRecognizers?
                .compactMap { $0 as? ContextMenuSurfaceInteractionGestureRecognizer }
                .forEach { glassSurface.removeGestureRecognizer($0) }
            glassSurface.routesTouchesToGlassSurface = true

            // Selection/highlight is now driven by a recognizer installed on
            // the glass surface itself. The actions view stays visual-only so
            // iOS 26 `UIGlassEffect.isInteractive` and the legacy fallback
            // stretch the menu container, not row labels/icons.
            view.isUserInteractionEnabled = false
            glassSurface.addGestureRecognizer(ContextMenuSurfaceInteractionGestureRecognizer(actionsView: view))
        } else {
            view.isUserInteractionEnabled = true
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
            let surfaceView = self.surfaceView,
            let surfaceOverlayView = self.surfaceOverlayView,
            let parentActions = self.actionsView,
            let handle = self.dismissHandle
        else { return }

        // If a submenu is already open, collapse it first (we don't stack
        // inline submenus — only one card at a time).
        if submenuCard != nil {
            collapseInlineSubmenu(animated: false)
        }

        // Build the card.
        let isDark = surfaceView.traitCollection.userInterfaceStyle == .dark
        let card = MenuGlassSurfaceView(isDark: isDark)
        card.applyCornerRadius(ContextMenuActionsView.cornerRadius)

        let submenuActions = ContextMenuActionsView(
            items: submenu,
            headerStyle: .disclosure(title: item.title)
        )
        let cardWidth = surfaceView.bounds.width
        let cardSize = submenuActions.preferredSize(maxWidth: cardWidth)
        submenuActions.frame = CGRect(origin: .zero, size: cardSize)
        submenuActions.autoresizingMask = [.flexibleWidth]
        card.contentView.addSubview(submenuActions)
        wireActionsView(submenuActions, handle: handle, surfaceView: card, isSubmenu: true)

        // Anchor card.minY to the source row's Y in screen coords. We can
        // approximate by finding the touched item's row in `parentActions`
        // — but a simpler robust path is "use the source row's frame directly".
        let cardOriginInParent = sourceRowFrame(for: item, in: parentActions)?.origin ?? .zero
        let cardOriginInHost = parentActions.convert(cardOriginInParent, to: host)
        let cardFrame = CGRect(
            x: surfaceView.frame.minX,
            y: cardOriginInHost.y,
            width: cardWidth,
            height: cardSize.height
        )
        card.frame = cardFrame
        host.addSubview(card)
        self.submenuCard = card
        self.submenuActions = submenuActions

        // Hit-target inside the active menu surface that catches taps which
        // miss the card. Lives BELOW the card in the host hierarchy (the
        // surface is below the card sibling), so card touches still go to
        // the card first.
        let hitView = UIView(frame: surfaceOverlayView.bounds)
        hitView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hitView.backgroundColor = .clear
        let collapseTap = UITapGestureRecognizer(target: self, action: #selector(handleCollapseTap))
        hitView.addGestureRecognizer(collapseTap)
        surfaceOverlayView.addSubview(hitView)
        self.submenuCollapseHitView = hitView

        // Dim parent + disable its touches so the card / hit-view interaction
        // model cleanly takes over. Also fade out the parent's sliding
        // highlight lens — `commitTouch` intentionally leaves it visible
        // after a tap (so regular actions can dismiss the whole menu with
        // the highlight still showing the "you tapped this row" state), but
        // for submenu opens we need to clear it here: otherwise when the
        // submenu closes and parent alpha returns to 1.0, a stale lens pops
        // back into view on the submenu-trigger row.
        parentActions.isUserInteractionEnabled = false
        parentActions.clearHighlight(animated: true)

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
            parentActions?.isUserInteractionEnabled = !(self.surfaceView is MenuGlassSurfaceView)
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

    private func applyStretch(toContainer container: UIView, touchInActions point: CGPoint, actionsBounds: CGRect, animated _: Bool) {
        let target = Self.computeStretchTransform(point: point, in: actionsBounds)

        // First touch-down: animate the lift-in (identity → stretched)
        // so the surface visibly rises into place. Subsequent drag
        // updates snap the transform because the touch events already
        // fire at ~60-120Hz — UIView.animate at each tick would fight
        // the finger and introduce lag.
        if !isStretchActive {
            isStretchActive = true
            UIView.animate(
                withDuration: 0.28, delay: 0,
                usingSpringWithDamping: 0.72, initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: { self.setStretchTransform(target, on: container) },
                completion: nil
            )
        } else {
            setStretchTransform(target, on: container)
        }
    }

    private func releaseStretch(onContainer container: UIView) {
        isStretchActive = false
        UIView.animate(
            withDuration: 0.42, delay: 0,
            usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: { self.setStretchTransform(.identity, on: container) },
            completion: nil
        )
    }

    private func setStretchTransform(_ transform: CGAffineTransform, on container: UIView) {
        if let glassSurface = container as? MenuGlassSurfaceView {
            glassSurface.setGlassInteractionTransform(transform)
        } else {
            container.transform = transform
        }
    }

    // MARK: - Glass-lift transform math
    //
    // Port of Telegram Display framework's `TouchEffect.currentTransform`
    // (see `GlassTouchEffect.swift`), adapted for the menu surface —
    // smaller lift magnitude + translation offset because the menu is a
    // much bigger surface than the buttons that math was tuned for.
    //
    // Given the finger's point in `actionsBounds` coords, returns the
    // affine transform that positions the menu surface in its "lifted
    // and stretched" pose:
    //
    //   • Base lift (uniform scale) — surface rises uniformly on press.
    //   • Anisotropic bias along the drag direction — the side of the
    //     surface the finger pulls gets scaled up, the perpendicular
    //     side gets squished (soft-body physics feel).
    //   • Translation offset up to `stretchMaxOffset` toward the
    //     finger — surface shifts into the drag direction.
    //
    // Composition (read right-to-left per CGAffineTransform semantics):
    // `translate(tx, ty) * scale(sx, sy)`. Matches the original
    // CATransform3D stack `translate then scale`.
    private static func computeStretchTransform(point: CGPoint, in bounds: CGRect) -> CGAffineTransform {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let stretch = CGPoint(x: point.x - center.x, y: point.y - center.y)

        let w = max(1.0, bounds.width)
        let h = max(1.0, bounds.height)
        let aspect = w / h
        let shorterSide = min(w, h)
        let baseScale = 1.0 + stretchPressedSizeIncrease / shorterSide

        let adjustedX = stretch.x / aspect
        let length = sqrt(adjustedX * adjustedX + stretch.y * stretch.y)

        // No directional stretch if the finger's on centre — pure lift.
        guard length > 0.5 else {
            return CGAffineTransform(scaleX: baseScale, y: baseScale)
        }

        let normal = CGPoint(x: adjustedX / length, y: stretch.y / length)
        // `k` tapers the stretch off the further the finger is pulled,
        // so the surface doesn't infinitely distort on edge-drags.
        let k: CGFloat = -1.0 / ((length / h) / (5.0 * aspect) + 1.0) + 1.0
        let additionalMaxScale = (h + 16.0 / aspect) / h - 1.0
        let t = additionalMaxScale * k * aspect

        let scaleX: CGFloat
        let scaleY: CGFloat
        if abs(normal.x) > abs(normal.y) {
            // Horizontal-dominant drag: X stretches, Y compresses.
            let diff = abs(normal.x) - abs(normal.y)
            scaleX = baseScale * (1.0 + t * diff)
            scaleY = baseScale * (1.0 / (1.0 + t * diff))
        } else {
            // Vertical-dominant drag: Y stretches, X compresses.
            let diff = abs(normal.y) - abs(normal.x)
            scaleX = baseScale * (1.0 / (1.0 + t * diff))
            scaleY = baseScale * (1.0 + t * diff)
        }

        return CGAffineTransform(
            translationX: normal.x * stretchMaxOffset * k,
            y: normal.y * stretchMaxOffset * k
        ).scaledBy(x: scaleX, y: scaleY)
    }
}

private final class ContextMenuSurfaceInteractionGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var actionsView: ContextMenuActionsView?
    private var trackedTouch: UITouch?

    init(actionsView: ContextMenuActionsView) {
        self.actionsView = actionsView
        super.init(target: nil, action: nil)
        delegate = self
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    override func reset() {
        trackedTouch = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first, let actionsView else {
            state = .failed
            return
        }
        trackedTouch = touch
        actionsView.beginExternalInteraction(at: touch.location(in: actionsView))
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), let actionsView else { return }
        actionsView.updateExternalInteraction(at: trackedTouch.location(in: actionsView))
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), let actionsView else {
            state = .ended
            return
        }
        actionsView.endExternalInteraction(at: trackedTouch.location(in: actionsView))
        self.trackedTouch = nil
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if trackedTouch != nil {
            actionsView?.cancelExternalInteraction()
        }
        trackedTouch = nil
        state = .cancelled
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
        catchTapsOutside: Bool = true,
        hasHapticFeedback: Bool = true,
        blurred: Bool = true,
        isDark: Bool? = nil,
        skipCoordinateConversion: Bool = false,
        onWillRemoveOverlay: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> ContextMenuController {
        let controller = ContextMenuController(
            source: Source(view: source, cornerRadius: cornerRadius),
            items: items,
            presentationStyle: presentationStyle,
            catchTapsOutside: catchTapsOutside,
            hasHapticFeedback: hasHapticFeedback,
            blurred: blurred,
            isDark: isDark,
            skipCoordinateConversion: skipCoordinateConversion,
            onWillRemoveOverlay: onWillRemoveOverlay,
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
