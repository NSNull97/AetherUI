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

    /// Open / close timings. Tuned for the `.fluidMorph` spring — deliberately
    /// longer than a typical tap response so the overshoot is actually visible
    /// and the cross-fade has room to breathe. `.morph` uses the same numbers
    /// as a convenient fallback (its internal progress driver reshapes them
    /// into its own phase budget).
    ///
    ///   open    ~ 0.42s   spring with 0.72 damping → ~8% overshoot,
    ///                     settles by ~0.36s, actions arrival curve
    ///                     lands into place over the back half.
    ///   dismiss ~ 0.30s   firmer (damping 0.86) so close feels decisive
    ///                     without being stiff.
    private static let morphDuration: TimeInterval = 0.475
    // Dismiss is a literal time-reverse of the open. Same duration +
    // damping keeps source/dest cross-fade windows and the geometry
    // spring symmetric — no asymmetric "snappier close".
    private static let dismissDuration: TimeInterval = 0.475
    /// `damping` is the spring's damping ratio for
    /// `UISpringTimingParameters` (see `ContextMenuFluidMorphHostView`).
    ///   1.0 = critically damped (no bounce, just glides in)
    ///   0.7 = noticeable overshoot, ~one settle cycle — "fluid"
    ///   0.5 = lots of wobble
    /// 0.72 is the sweet spot for "tactile, playful, but not silly".
    /// Close uses 0.86 — much firmer, just enough give to not feel
    /// snap-to-invisibility.
    private static let morphDamping: CGFloat = 0.68
    private static let dismissDamping: CGFloat = 0.68

    private static let dimAlpha: CGFloat = 0.0  // very faint separation layer (rec: ≤0.06-0.10)
    /// Radius of the backdrop blur applied to the dim layer, in points.
    /// Uses a raw CABackdropLayer + CAFilter("gaussianBlur"), so any
    /// non-negative radius works (unlike UIBlurEffect which snaps to
    /// a few fixed styles). 0 disables the blur and falls back to a
    /// plain tint. 2pt is the "barely-there" default — enough to
    /// soften the edges of background content without making it
    /// unreadable.
    public static var dimBlurRadius: CGFloat = 0.05
    private static let menuCornerRadius: CGFloat = 34.0
    /// Diameter of the initial "droplet bubble" for `.morph`. Smaller
    /// values read as a "point" emerging → the menu inflates from a
    /// dot rather than from a visible disc. 24 pt is small enough
    /// that the start reads as a concentrated spark / drop, with
    /// just enough size for the glass effect to be perceptible.
    private static let dropletSize: CGFloat = 24.0

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
        /// When `true`, the source view fades out as the menu morphs in
        /// and fades back in on dismiss. The default (`false`) keeps the
        /// source visible underneath the morph — that's what you want
        /// for liquid-glass cards / list rows where the menu reads as a
        /// lens magnifying the source.
        ///
        /// Set this to `true` for nav-bar buttons and similar capsule
        /// cells: their own glass background reads as a duplicate of
        /// the menu's morph, and visually it should "lift off" the bar
        /// while the menu is up. Layout doesn't shift either way — we
        /// drive `layer.opacity`, not `isHidden`.
        public var hidesDuringPresentation: Bool

        public init(view: UIView, cornerRadius: CGFloat? = nil, hidesDuringPresentation: Bool = false) {
            self.view = view
            self.cornerRadius = cornerRadius
            self.hidesDuringPresentation = hidesDuringPresentation
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
        /// Fresh fluid morph using `UIViewPropertyAnimator` + spring
        /// timing on `self.frame`, corner-anchored content containers
        /// via `autoresizingMask`, and `CABasicAnimation` for layer-
        /// only properties (`cornerRadius` / `shadowPath`).
        ///
        /// Directional correctness (right-side button's menu unfolds
        /// leftward from the button's right edge; left-side unfolds
        /// rightward from the left edge; vertical is handled the same
        /// way for flip-upward) is STRUCTURAL, not hand-tuned:
        ///
        ///   - `computeMenuFrame` pins one on-screen edge of menu to
        ///     source (e.g. `menu.maxX == source.maxX` right-aligned).
        ///   - The host's `frame` spring then keeps that edge
        ///     invariant — `frame.maxX(t) = source.maxX` for all `t`,
        ///     mathematically, because position.x(t) and bounds.w(t)
        ///     interpolate linearly and their derivatives cancel on
        ///     the pinned edge.
        ///   - Content containers (source snapshot, actions view) are
        ///     pinned to the same anchor corner via `autoresizingMask`,
        ///     so they stay STATIONARY in absolute screen coords while
        ///     the glass envelope grows around them.
        ///
        /// Net result: no left-jumping, no unfolding from the wrong
        /// side, and the source content and actions content never
        /// physically move in absolute coords — only the glass moves.
        /// See `ContextMenuFluidMorphHostView`.
        case fluidMorph
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
    /// For `.fluidMorph` style: the minimal host with UIViewPropertyAnimator
    /// spring driving the frame morph, and corner-anchored content.
    /// Independent of `morphHost` so both implementations can coexist
    /// for A/B comparison.
    private var fluidMorphHost: ContextMenuFluidMorphHostView?
    /// For `.preview` style only: the outer wrapper holding the (static-
    /// size) glass menu. Left `nil` for `.morph` — morphHost plays that role.
    private var sdfHost: UIView?
    private var sdfFilter: AnyObject?  // erased LensSDFFilter? for pre-iOS-26 build
    private var menuContainer: MenuGlassSurfaceView?
    private var snapshotView: UIView?
    private var actionsView: ContextMenuActionsView?
    private var tapRecognizer: UITapGestureRecognizer?
    /// The view that plays the role of "the glass surface hit-test target"
    /// for submenu + stretch purposes. For `.morph` this is `morphHost`;
    /// for `.fluidMorph` it's `fluidMorphHost`; for `.preview` it's
    /// `sdfHost`. Collapsed into a single property so downstream wiring
    /// code doesn't have to branch on presentation style.
    private var surfaceView: UIView? { morphHost ?? fluidMorphHost ?? sdfHost }
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

        // Dim layer + tap-to-dismiss target. Uses a custom
        // CABackdropLayer-based blur (see `ContextMenuDimBlurView`)
        // so the radius is continuously configurable via
        // `dimBlurRadius`. At the default 2pt radius the background
        // is just barely softened, not frosted.
        let dim = ContextMenuDimBlurView(
            blurRadius: ContextMenuController.dimBlurRadius,
            tintAlpha: ContextMenuController.dimAlpha
        )
        dim.frame = host.bounds
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
        let snapshot = makeSourceSnapshot(
            source: source,
            preferRenderedImage: {
                if case .morph = presentationStyle, #available(iOS 26.0, *) {
                    return true
                } else {
                    return false
                }
            }()
        )
        self.snapshotView = snapshot

        switch presentationStyle {
        case .morph, .fluidMorph:
            // `.fluidMorph` aliased to `.morph` — both use the same
            // droplet-at-source → travel-to-menu-centre → bilateral
            // expand timeline. The older `ContextMenuFluidMorphHost-
            // View` with its UIViewPropertyAnimator + frame-spring
            // approach produced a different (edge-anchored) visual
            // the user didn't want, so routing both styles through
            // `setupMorphStyle` keeps behaviour identical.
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
        case .preview:
            setupPreviewStyle(
                host: host,
                source: source,
                isDark: isDark,
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
            wireActionsView(actionsView, handle: handle, surfaceView: surface)
        }

        // Haptic.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Default: keep the source view visible — the SDF lens relies on
        // `backgroundFilters` (i.e. the glass pill distorts whatever is
        // rendered BEHIND it). If we hide the source, the lens has
        // nothing to magnify and the glass reads as a flat pill growing
        // over empty space. Layout stays untouched (no `isHidden` games)
        // so the surrounding stack/collection doesn't shift.
        //
        // Exception: `.preview()` ALWAYS hides the source. The preview
        // shape lifts the cell as its own snapshot — leaving the
        // original visible behind the menu reads as a duplicate of
        // the chat bubble (or whatever was tapped). Morph-style menus
        // need the original for SDF backdrop magic, so we only fade
        // for preview here; morph callers can still opt in via
        // `Source.hidesDuringPresentation = true` per anchor.
        let shouldFadeSource: Bool
        if case .preview = presentationStyle {
            shouldFadeSource = true
        } else {
            shouldFadeSource = self.source.hidesDuringPresentation
        }
        if shouldFadeSource {
            // Drive `UIView.alpha` (not `CALayer.opacity` directly) so
            // UIKit observers see the change — iOS 26's glass-effect
            // pipeline tracks alpha through the UIView setter, and a
            // direct `layer.opacity` write bypasses that and leaves
            // the shared `UIGlassContainerEffect` in a half-broken
            // "interactive but invisible" state where sibling glass
            // views in the same container also stop reacting to touch.
            self.savedSourceOpacity = Float(source.alpha)
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                source.alpha = 0
            }
        }

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
        source _: UIView,
        isDark: Bool,
        snapshot: UIView,
        actionsView: ContextMenuActionsView,
        sourceRectInHost: CGRect,
        sourceCornerRadius: CGFloat,
        menuFrame: CGRect
    ) {
        // Collapsed state is a small `dropletSize`pt circle at the
        // menu's near edge, NOT the source button's rect. Matches
        // iOS 26 native context-menu behaviour: a small bubble
        // emerges in the gap between source and menu, then grows
        // into the full menu. Starting from the full source rect
        // (as the previous implementation did) looked wrong for any
        // wide source — the morph appeared to "already be the menu
        // width" from t=0 and only grew vertically.
        //
        // Droplet is centred horizontally on the source. Vertically
        // it anchors to the menu-side closest to the source:
        //   * menu below/overlapping source → droplet at menu.minY
        //     (so it grows downward as the menu unfolds)
        //   * menu flipped above source      → droplet at menu.maxY
        //     (so it grows upward from the menu's bottom edge)
        // Droplet centred on the SOURCE. The morph host then uses
        // two separate time curves for position and size (see
        // `updateForProgress`): position quickly lerps from
        // `source.midX/midY` to `menu.midX/midY` in the first ~30 %
        // of the animation, size expands bilaterally afterwards at
        // the menu's midpoint. Net effect — the bubble emerges at
        // the source, travels to the menu's landing spot, then
        // inflates from there. No drift during the growth phase
        // because by the time size is meaningfully lerping, the
        // position has already arrived at menu.mid.
        let dropletSize = Self.dropletSize
        let dropletFrame = CGRect(
            x: sourceRectInHost.midX - dropletSize / 2,
            y: sourceRectInHost.midY - dropletSize / 2,
            width: dropletSize,
            height: dropletSize
        )

        let morphHost = ContextMenuMorphHostView(isDark: isDark)
        morphHost.frame = dropletFrame
        host.addSubview(morphHost)
        morphHost.configure(metrics: ContextMenuMorphHostView.Metrics(
            collapsedFrame: dropletFrame,
            collapsedCornerRadius: dropletSize / 2,
            expandedFrame: menuFrame,
            expandedCornerRadius: ContextMenuActionsView.cornerRadius
        ))
        morphHost.progress = 0

        // Source snapshot is INTENTIONALLY NOT embedded in the morph
        // host. With the droplet pattern the source view stays
        // visible in its original position — the bubble emerges
        // NEXT TO the source, not out of it. `snapshot` is kept
        // alive only because the preview style uses it; morph
        // doesn't need it. Mark as unused to avoid warnings.
        _ = snapshot

        // Actions view: (0,0), expanded size. Morph host handles alpha
        // + translateY per-progress internally.
        actionsView.frame = CGRect(origin: .zero, size: menuFrame.size)
        actionsView.autoresizingMask = []
        morphHost.destinationContent.addSubview(actionsView)

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
                size: dropletFrame.size,
                cornerRadius: dropletSize / 2
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
        if className.contains("BackdropLayer") {
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

    /// Wires up the `.fluidMorph` path:
    ///
    ///   1. Detect the anchor corner from source/menu geometry (which
    ///      edges coincide — right for right-aligned, left for left-
    ///      aligned, and similarly top vs. bottom when menu flips up).
    ///
    ///   2. Position the fluid host at source rect, glass fills host
    ///      via autoresizing, and content containers are corner-pinned
    ///      so they stay stationary in absolute coords while glass
    ///      grows around them (see type doc on
    ///      `ContextMenuFluidMorphHostView`).
    ///
    ///   3. Embed the source snapshot (filling `sourceContent`) and the
    ///      actions view (filling `actionsContainer`). Both fill their
    ///      parents via `[.flexibleWidth, .flexibleHeight]` — the
    ///      parents themselves are the ones with the corner-anchor
    ///      masks.
    private func setupFluidMorphStyle(
        host: UIView,
        isDark: Bool,
        snapshot: UIView,
        actionsView: ContextMenuActionsView,
        sourceRectInHost: CGRect,
        sourceCornerRadius: CGFloat,
        menuFrame: CGRect
    ) {
        let anchor = ContextMenuMorphAnchor.detect(source: sourceRectInHost, menu: menuFrame)

        let fluidHost = ContextMenuFluidMorphHostView(isDark: isDark)
        host.addSubview(fluidHost)
        fluidHost.configure(metrics: ContextMenuFluidMorphHostView.Metrics(
            sourceFrameInHost: sourceRectInHost,
            sourceCornerRadius: sourceCornerRadius,
            menuFrameInHost: menuFrame,
            menuCornerRadius: ContextMenuActionsView.cornerRadius,
            anchor: anchor
        ))

        // Snapshot fills sourceContent — parent is what's corner-anchored.
        snapshot.frame = fluidHost.sourceContent.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fluidHost.sourceContent.addSubview(snapshot)

        // Actions view fills actionsContainer — same deal.
        actionsView.frame = fluidHost.actionsContainer.bounds
        actionsView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        fluidHost.actionsContainer.addSubview(actionsView)

        self.fluidMorphHost = fluidHost
        self.menuContainer = fluidHost.glass
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
        sourceRectInHost: CGRect,
        menuFrame: CGRect
    ) {
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

        // Source visibility is restored inside the `cleanup` block
        // below — that block runs at the END of the close animation,
        // when our preview snapshot has already been removed. A
        // parallel fade-in here was racing the snapshot's slide-back
        // and leaving both visible for a few frames — exactly the
        // "preview held" symptom. Clear the saved-opacity bookmark
        // so any later interruption still finds it nil and skips
        // the restore.
        self.savedSourceOpacity = nil

        let host = hostView
        let dim = dimView
        let morphHost = self.morphHost
        let fluidMorphHost = self.fluidMorphHost
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
            // Defensive: clear any mask the source might carry. Prior
            // versions applied a transparent CALayer mask on `present`
            // to hide the source; current version keeps it visible for
            // SDF backdrop distortion and never sets a mask — this is
            // a no-op on the current path but stays as a safety net for
            // any future path that might re-introduce hiding.
            sourceView?.layer.mask = nil
            // Defensive: restore transform/alpha in case the dismiss
            // path was non-animated (animated: false) or interrupted
            // before the spring finished — otherwise the source would
            // stay collapsed after a rapid dismiss.
            sourceView?.transform = .identity
            sourceView?.alpha = 1.0
            CATransaction.commit()
            if #available(iOS 26.0, *), let filter = self?.sdfFilter as? LensSDFFilter {
                filter.uninstall()
            }
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
            (morphHost as? ContextMenuMorphHostView)?.glass.tearDownGlassEffect()
            (fluidMorphHost as? ContextMenuFluidMorphHostView)?.glass.tearDownGlassEffect()
            dim?.removeFromSuperview()
            morphHost?.removeFromSuperview()
            fluidMorphHost?.removeFromSuperview()
            sdfHost?.removeFromSuperview()
            container?.removeFromSuperview()
            actionsView?.removeFromSuperview()
            snapshot?.removeFromSuperview()
            self?.previewView?.removeFromSuperview()
            host?.removeFromSuperview()
            self?.hostView = nil
            self?.dimView = nil
            self?.morphHost = nil
            self?.fluidMorphHost = nil
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
        case .morph, .fluidMorph:
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

        // Read the source's current transform + alpha at the moment
        // dismiss starts — the source is sitting in its "collapsed
        // into droplet" pose from the open-time animation. The
        // step-callback below interpolates from THIS pose back to
        // identity/alpha=1 using the same spring progress that
        // drives the morph collapse.
        let sourceView = source.view
        let startTransform = sourceView?.transform ?? .identity
        let startAlpha = sourceView?.alpha ?? 1.0
        sourceView?.layer.removeAllAnimations()

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

                if let sv = sourceView {
                    // Mirror of the open-time fast-hide: source
                    // re-materialises in the SECOND half of the
                    // dismiss. `progress ∈ [0.5, 0]` (it falls 1 →
                    // 0 over dismiss) maps to `t = 1` only after
                    // progress drops below 0.5, so the menu has
                    // already collapsed past the half-way point
                    // before the source becomes visible again. No
                    // overlap of the still-shrinking menu and the
                    // re-emerging source button.
                    let raw = max(0, min(1, (0.5 - progress) / 0.5))
                    let t = raw * raw * raw * (raw * (6 * raw - 15) + 10)
                    let s = startTransform
                    // Real wobble: rising-amplitude oscillation
                    // with explicit overshoot AND undershoot.
                    // `bumpRaw ∈ [0, 1]` over `t ∈ [0.4, 1.0]`.
                    // Three half-cycles of `sin(3π·bumpRaw)` give
                    // peak / dip / peak at bumpRaw = 1/6, 1/2,
                    // 5/6, multiplied by a linearly rising
                    // envelope (`bumpRaw`) so each successive
                    // swing is bigger than the previous. Values:
                    //   bumpRaw=0.167 → +0.025 (small overshoot)
                    //   bumpRaw=0.5   → -0.075 (visible dip)
                    //   bumpRaw=0.833 → +0.125 (big overshoot)
                    // Reads as a button on a spring that swings
                    // back and forth, gathering amplitude before
                    // settling. The dip below 1.0 is what makes
                    // it read as oscillation instead of a series
                    // of taps.
                    let bumpRaw = max(0, min(1, (t - 0.4) / 0.6))
                    let envelope = bumpRaw
                    let oscillation = sin(3 * .pi * bumpRaw)
                    let amp: CGFloat = 0.15
                    let bump = 1 + amp * envelope * oscillation
                    sv.transform = CGAffineTransform(
                        a: s.a + (1 - s.a) * t,
                        b: s.b + (0 - s.b) * t,
                        c: s.c + (0 - s.c) * t,
                        d: s.d + (1 - s.d) * t,
                        tx: s.tx + (0 - s.tx) * t,
                        ty: s.ty + (0 - s.ty) * t
                    ).scaledBy(x: bump, y: bump)
                    sv.alpha = startAlpha + (1 - startAlpha) * t
                }

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
                peakHeight: menuMinSide * 0.22,
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
        preview: UIView?
    ) {
        let sourceView = self.source.view
        UIView.animate(
            withDuration: ContextMenuController.dismissDuration,
            delay: 0,
            usingSpringWithDamping: ContextMenuController.dismissDamping,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                sdfHost.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                sdfHost.alpha = 0.0
                // Crossfade: preview fades to 0 while the original
                // source view fades back to 1 in lockstep. Without
                // this, the snapshot would shrink back onto an
                // invisible source and stay visible for the gap
                // between this animation finishing and the cleanup
                // dispatch firing — exactly the "preview held"
                // glitch users see.
                preview?.transform = .identity
                preview?.alpha = 0.0
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
        case .morph, .fluidMorph:
            animateInMorph(sourceMinSide: sourceMinSide)
        case let .preview(_, lift):
            if let sdfHost { animateInPreview(sdfHost: sdfHost, lift: lift) }
        }
    }

    /// Parallel open:
    ///
    ///   - **Source view**: scales + translates toward the droplet
    ///     centre and fades alpha 1 → 0 over the FIRST ~30 % of the
    ///     morph duration. Uses `CGAffineTransform`, so the real
    ///     source view stays in its parent hierarchy untouched
    ///     (Auto Layout doesn't fight us). The motion reads as the
    ///     button "imploding" into the spot where the menu is about
    ///     to emerge from.
    ///
    ///   - **morphHost**: visible from t=0 as a small droplet circle
    ///     at the anchor position, spring-expands to the full menu
    ///     rect over the ENTIRE duration. SDF pulse runs over the
    ///     same window.
    ///
    /// Both animations start at t=0 — the source doesn't block the
    /// menu from beginning to unfold. By the time the menu is
    /// meaningfully large (~30 %), the source has already faded to
    /// zero, so the two visuals never compete for the user's
    /// attention.
    private func animateInMorph(sourceMinSide: CGFloat) {
        guard let morphHost else { return }

        let dropletFrame = morphHost.metrics?.collapsedFrame ?? morphHost.frame
        let sourceRect = self.sourceRectInHost

        // Source-view collapse: scale + fade IN PLACE. No horizontal
        // or vertical translation — the source stays pinned to its
        // original position while shrinking + fading out. The morph
        // bubble appears separately at the menu's centre (see
        // `setupMorphStyle`'s droplet placement) and grows from
        // there. Translating the source toward the droplet caused a
        // visible "source slides to a different spot" effect the
        // user explicitly rejected.
        _ = dropletFrame  // kept as a parameter signal but unused here
        _ = sourceRect    // ditto
        let sourceView = source.view
        let finalScale = Self.dropletSize / max(sourceRect.width, sourceRect.height, 1)

        sourceView?.layer.removeAllAnimations()

        // Menu expansion starts IMMEDIATELY at t=0, in parallel with
        // the source collapse. `step` drives both SDF layout AND
        // source transform from the same spring-eased progress
        // value — one animation clock, one settle moment.
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

                if let sv = sourceView {
                    // Source vanishes inside the FIRST half of the
                    // morph: `progress ∈ [0, 0.5]` ramps `t` from 0
                    // → 1 via smootherstep, so by the time the
                    // bubble is meaningfully large the source is
                    // already gone. Smootherstep keeps the fade
                    // C²-smooth at both ends — no kink at the
                    // moment the source disappears.
                    let raw = max(0, min(1, progress / 0.5))
                    let t = raw * raw * raw * (raw * (6 * raw - 15) + 10)
                    let scale = 1 + (finalScale - 1) * t
                    sv.transform = CGAffineTransform(scaleX: scale, y: scale)
                    sv.alpha = 1 - t
                }

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
                peakHeight: menuMinSide * 0.22,
                duration: ContextMenuController.morphDuration
            )
            filter.animateBlur(duration: ContextMenuController.morphDuration)
        }
    }

    /// Drive the `.fluidMorph` host from source → menu via
    /// `UIViewPropertyAnimator` + spring on `self.frame`. Cross-fade
    /// and layer-property (corner + shadow) animations all live inside
    /// `ContextMenuFluidMorphHostView.animateExpand`.
    ///
    /// The key structural property that makes this "fluid" and fixes
    /// the old left-jump bug: both content containers inside the host
    /// are stationary in absolute screen coords throughout the morph.
    /// Only the glass envelope moves, revealing or clipping more of
    /// the actions view as it springs out.
    private func animateInFluidMorph() {
        guard let fluidMorphHost else { return }
        fluidMorphHost.animateExpand(
            duration: ContextMenuController.morphDuration,
            damping: ContextMenuController.morphDamping,
            completion: nil
        )
    }

    /// Reverse of `animateInFluidMorph`: spring the frame back to
    /// source rect with a shorter duration and a less-elastic damping.
    /// Cleanup fires on the geometry animator's completion. If the
    /// open animation is still running, the host's own
    /// `cancelRunningAnimators` stops it at `.current` before the
    /// collapse starts — no teleport.
    private func animateOutFluidMorph(
        dim: UIView?,
        cleanup: @escaping () -> Void
    ) {
        guard let fluidMorphHost else { cleanup(); return }

        // Reset any active stretch transform first so the reverse morph
        // starts from identity, not from a press-release stretch left
        // over from the last touch.
        fluidMorphHost.transform = .identity

        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseIn], animations: {
            dim?.alpha = 0.0
        })

        fluidMorphHost.animateCollapse(
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

        let initialY: CGFloat
        switch presentationStyle {
        case .morph, .fluidMorph:
            initialY = sourceRect.minY
        case let .preview(spacing, _):
            initialY = sourceRect.maxY + spacing
        }

        var y = initialY
        if y + menuSize.height > hostBounds.maxY - safeBottom {
            let menuToSourceGap: CGFloat = 12.0
            let upward = sourceRect.minY - menuSize.height - menuToSourceGap
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
        view.onStretchUpdate = { [weak self, weak surfaceView, weak view] point in
            guard let self, let surfaceView, let view else { return }
            // Stretch only the parent host. Submenu cards don't carry the
            // SDF lens — they're a lightweight popover.
            if isSubmenu { return }
            self.applyStretch(toContainer: surfaceView, touchInActions: point, actionsBounds: view.bounds, animated: false)
        }
        view.onStretchRelease = { [weak self, weak surfaceView] in
            guard let self, let surfaceView, !isSubmenu else { return }
            self.releaseStretch(onContainer: surfaceView)
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
        wireActionsView(submenuActions, handle: handle, surfaceView: surfaceView, isSubmenu: true)

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
                animations: { container.transform = target },
                completion: nil
            )
        } else {
            container.transform = target
        }
    }

    private func releaseStretch(onContainer container: UIView) {
        isStretchActive = false
        UIView.animate(
            withDuration: 0.42, delay: 0,
            usingSpringWithDamping: 0.7, initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: { container.transform = .identity },
            completion: nil
        )
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
