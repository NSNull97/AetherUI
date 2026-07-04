import UIKit

public protocol AetherModalControllerDelegate: AnyObject {
    /// Fires continuously (per-frame during drag and during the settle
    /// animation) as the sheet scrolls between detents. Progress is 0 at
    /// stage1 and 1 at stage2; values are clamped to `0...1`.
    func modalController(
        _ controller: AetherModalController,
        didUpdateDetentProgress progress: CGFloat
    )
    /// Fires when the sheet commits to a detent — at the start of a settle
    /// animation, a programmatic `setDetent`, or on a live drag crossing
    /// to a different nearest detent.
    func modalController(
        _ controller: AetherModalController,
        didChangeDetent detent: AetherModalController.Detent
    )
    /// Fires the moment the sheet starts moving — pan `.began` (when the
    /// sheet decides it owns the gesture) or the start of a settle /
    /// programmatic-`setDetent` animation. Bracketed with a matching
    /// `didEndInteractiveResize` once motion has fully stopped.
    ///
    /// Use this to freeze expensive in-content layout for the duration of
    /// the resize — e.g. snapshot the form, toggle `shouldRasterize`, or
    /// suspend custom timers — so the per-frame layout cascade isn't
    /// fighting the drag/settle animation.
    func modalControllerWillBeginInteractiveResize(
        _ controller: AetherModalController
    )
    /// Fires once interactive resize has fully stopped — pan ended without
    /// triggering settle, or the settle animation completed/was cancelled.
    /// Always paired with a prior `willBeginInteractiveResize`.
    func modalControllerDidEndInteractiveResize(
        _ controller: AetherModalController
    )
}

public extension AetherModalControllerDelegate {
    func modalController(
        _ controller: AetherModalController,
        didUpdateDetentProgress progress: CGFloat
    ) {}
    func modalController(
        _ controller: AetherModalController,
        didChangeDetent detent: AetherModalController.Detent
    ) {}
    func modalControllerWillBeginInteractiveResize(
        _ controller: AetherModalController
    ) {}
    func modalControllerDidEndInteractiveResize(
        _ controller: AetherModalController
    ) {}
}

open class AetherModalController: UIViewController {
    public enum Detent: Hashable {
        case stage1
        case stage2
    }

    public struct Config: Equatable {
        public var sideInset: CGFloat
        /// Distance from the sheet's bottom edge to the screen bottom at
        /// stage1. Default 8pt — the sheet floats above the home indicator.
        public var bottomInsetStage1: CGFloat
        /// Distance from the sheet's bottom edge to the screen bottom at
        /// stage2. Default 0 — the sheet nestles into the device corners.
        public var bottomInsetStage2: CGFloat
        public var topInsetStage1: CGFloat
        public var topInsetStage2: CGFloat
        public var topCornerRadius: CGFloat
        /// Dim alpha applied over the presenting view at stage1.
        public var dimAlphaStage1: CGFloat
        /// Dim alpha applied over the presenting view at stage2.
        public var dimAlphaStage2: CGFloat
        public var dimTintColor: UIColor
        /// Detents the sheet is allowed to rest at. When a single detent
        /// is specified the sheet opens at that detent and drags toward
        /// the other detent are blocked — only a strong downward drag can
        /// dismiss the sheet. Must contain at least one detent.
        public var detents: Set<Detent>
        /// Detent the sheet opens at. Must be contained in `detents`.
        /// Nil → pick the first allowed detent (stage1 preferred).
        public var initialDetent: Detent?

        public init(
            sideInset: CGFloat = 8.0,
            bottomInsetStage1: CGFloat = 8.0,
            bottomInsetStage2: CGFloat = 0.0,
            topInsetStage1: CGFloat = UIScreenHeight / 2,
            topInsetStage2: CGFloat = 10.0,
            topCornerRadius: CGFloat = 34.0,
            dimAlphaStage1: CGFloat = 0.25,
            dimAlphaStage2: CGFloat = 0.4,
            dimTintColor: UIColor = .systemBackground,
            detents: Set<Detent> = [.stage1, .stage2],
            initialDetent: Detent? = nil
        ) {
            self.sideInset = sideInset
            self.bottomInsetStage1 = bottomInsetStage1
            self.bottomInsetStage2 = bottomInsetStage2
            self.topInsetStage1 = topInsetStage1
            self.topInsetStage2 = topInsetStage2
            self.topCornerRadius = topCornerRadius
            self.dimAlphaStage1 = dimAlphaStage1
            self.dimAlphaStage2 = dimAlphaStage2
            self.dimTintColor = dimTintColor
            self.detents = detents.isEmpty ? [.stage1, .stage2] : detents
            self.initialDetent = initialDetent
        }

        /// Resolved opening detent — `initialDetent` if allowed,
        /// otherwise stage1 (if allowed), otherwise stage2.
        public var resolvedInitialDetent: Detent {
            if let requested = initialDetent, detents.contains(requested) {
                return requested
            }
            return detents.contains(.stage1) ? .stage1 : .stage2
        }
    }

    public let config: Config

    /// Public host for your sheet's content. Subclasses populate this
    /// in `viewDidLoad` (`contentView.addSubview(...)` or `embedContent(_:)`).
    ///
    /// **Stays at fixed (stage2) size for the lifetime of the modal** —
    /// only resizes when the container bounds change (rotation, scene
    /// resize). This is the central perf trick: drag changes only the
    /// outer `presentedView.frame`, the inner content host's bounds stay
    /// constant, so the auto-layout solver inside the content subtree
    /// doesn't re-run on every pan tick. When the sheet is at stage1
    /// the bottom of `contentView` simply hangs below the visible modal
    /// and is clipped by the rounded mask.
    public let contentView: UIView

    /// Optional sticky footer — anchored to the bottom of the visible
    /// modal so it follows the sheet across detents (i.e. it lives in
    /// `presentedView` coordinates, not in `contentView` coordinates).
    /// Setting this:
    ///   * positions `footerView` at `(0, footerEdgeFadeHeight, modal.width, footerHeight)`
    ///     inside an internal host
    ///   * applies a scroll-edge frost that fades upward into the
    ///     content area (`footerEdgeFadeHeight`)
    ///   * adds `footerHeight` to `additionalSafeAreaInsets.bottom` so
    ///     scroll content inside `contentView` scrolls past the footer
    ///
    /// Use `footerHeight` to declare the footer's total height (the
    /// modal can't reliably ask the view itself — auto-layout-only
    /// footers without intrinsic height would report 0).
    public var footerView: UIView? {
        didSet {
            if oldValue !== footerView {
                oldValue?.removeFromSuperview()
                if let footerView { footerHost.addSubview(footerView) }
                if isViewLoaded { view.setNeedsLayout() }
            }
        }
    }

    /// Total height (in points) of the contents of `footerView`. Drives
    /// both the visible footer band and the bottom safe-area inset added
    /// onto the content host. Does NOT include the edge-effect fade
    /// height — that's `footerEdgeFadeHeight`.
    public var footerHeight: CGFloat = 0 {
        didSet {
            if oldValue != footerHeight, isViewLoaded {
                view.setNeedsLayout()
            }
        }
    }

    /// Height of the gradient fade that sits above the footer and
    /// dissolves the scroll content into the frost. 28pt by default —
    /// matches the look used by the original Telegram-style modal.
    public var footerEdgeFadeHeight: CGFloat = 28 {
        didSet {
            if oldValue != footerEdgeFadeHeight, isViewLoaded {
                view.setNeedsLayout()
            }
        }
    }

    /// Tint colour drawn behind the footer. `nil` → derive from
    /// `config.dimTintColor` with 0.86 alpha (sensible default that
    /// matches the modal background).
    public var footerEdgeTintColor: UIColor? {
        didSet { invalidateFooterEdgeCache() }
    }

    /// Blur radius behind the footer band. 2pt by default — same as
    /// the legacy edge-effect setting.
    public var footerEdgeBlurRadius: CGFloat = 2 {
        didSet { invalidateFooterEdgeCache() }
    }

    /// Scroll view inside the modal that should cooperate with sheet drag.
    /// Subclasses set this in `viewDidLoad` to opt into:
    ///   * gesture arbitration — the modal yields to scroll when the
    ///     touch starts inside scroll content and scroll isn't at top;
    ///   * automatic keyboard adjustment — the modal observes
    ///     `keyboardWillChangeFrame` and pushes the on-screen keyboard
    ///     overlap into `primaryScrollView.contentInset.bottom` (and
    ///     scroll-indicator inset), then scrolls the active first
    ///     responder into the visible area.
    public weak var primaryScrollView: UIScrollView? {
        didSet {
            guard oldValue !== primaryScrollView else { return }
            // Move our keyboard contribution from the old scroll view to
            // the new one — otherwise the previous scroll keeps a stale
            // bottom inset and the new one starts without ours.
            if lastKeyboardScrollInset != 0 {
                oldValue?.contentInset.bottom -= lastKeyboardScrollInset
                oldValue?.verticalScrollIndicatorInsets.bottom -= lastKeyboardScrollInset
                primaryScrollView?.contentInset.bottom += lastKeyboardScrollInset
                primaryScrollView?.verticalScrollIndicatorInsets.bottom += lastKeyboardScrollInset
            }
        }
    }

    public weak var delegate: AetherModalControllerDelegate?

    /// Optional presentation/dismissal animation provider.
    ///
    /// `nil` keeps the default bottom-sheet slide animation. Set this to
    /// `AetherModalSourceTransition(sourceView:)` for Telegram-style
    /// expansion from a button, or provide your own
    /// `AetherModalTransitionAnimation` implementation for fully custom
    /// UIKit transition animators.
    public var transitionAnimation: AetherModalTransitionAnimation?

    public private(set) var currentDetent: Detent = .stage1
    public var currentDetentProgress: CGFloat { detentProgress }

    private let glassBackground = GlassBackgroundView(style: .regular)
    private let grabberContainer = UIView()
    private let grabberView = UIView()
    private let footerHost = UIView()
    private let maskLayer = CAShapeLayer()

    /// Last footer-host height the edge-effect attachment was applied at.
    /// `setEdgeEffect` re-creates the underlying `EdgeEffectView` (and its
    /// `CABackdropLayer` + filters), so we apply only when the height
    /// shifts by more than 2pt — rotation / dynamic-type / mode flip,
    /// not every drag tick.
    private var lastAppliedFooterHostHeight: CGFloat = -1
    /// Footer's contribution to `additionalSafeAreaInsets.bottom`.
    /// Tracked separately so subclasses can add to the same bottom inset
    /// without us overwriting their delta.
    private var lastFooterBottomInset: CGFloat = 0
    /// Current keyboard overlap (in modal's coordinate space). Updated
    /// from `UIResponder.keyboardWillChangeFrameNotification` so the
    /// footer slides up over the keyboard and `primaryScrollView`'s
    /// `contentInset.bottom` includes the obscured area. The didSet
    /// marks layout dirty so the next `view.layoutIfNeeded()` call
    /// (driven from inside the keyboard animation block) actually
    /// reaches `layoutFooter()` and slides the footer over the
    /// keyboard — without it the call would be a no-op and the
    /// footer would stay flush against the modal's bottom edge.
    private var keyboardOverlap: CGFloat = 0 {
        didSet {
            if oldValue != keyboardOverlap, isViewLoaded {
                view.setNeedsLayout()
            }
        }
    }
    /// Our contribution to `primaryScrollView.contentInset.bottom` for
    /// keyboard handling. Delta-tracked so the caller's baseline
    /// `contentInset.bottom` (anything they set themselves before the
    /// keyboard appears) survives our adjustments.
    private var lastKeyboardScrollInset: CGFloat = 0
    private var keyboardObserversInstalled = false

    private func invalidateFooterEdgeCache() {
        lastAppliedFooterHostHeight = -1
        if isViewLoaded {
            view.setNeedsLayout()
        }
    }

    /// stage2 frame size pushed in by `AetherModalPresentationController`
    /// once per container layout. Drives the immutable size of `contentView`.
    /// `.zero` until the first `setExpectedContentSize` call — `layoutChrome`
    /// falls back to `view.bounds.size` for that initial pass.
    private var expectedContentSize: CGSize = .zero

    /// Height of the grabber container area at the top of the sheet.
    /// Content anchored to `view.safeAreaLayoutGuide.topAnchor` ends up
    /// below this strip — the modal pushes a matching top inset onto
    /// `additionalSafeAreaInsets` for the entire content subtree.
    public static let grabberContainerHeight: CGFloat = 17.0
    private static let grabberSize: CGSize = CGSize(width: 36.0, height: 5.0)

    private let modalTransitioningDelegate: AetherModalTransitioningDelegate

    public init(config: Config = Config()) {
        self.config = config
        self.contentView = UIView()
        self.modalTransitioningDelegate = AetherModalTransitioningDelegate()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = modalTransitioningDelegate
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Notification-center observers retain self until removed.
        // Footer keyboard observation is the only one we install — drop
        // it unconditionally; it's a no-op if we never registered.
        NotificationCenter.default.removeObserver(self)
    }

    /// Composition helper — embeds an existing VC inside `contentView`.
    /// Equivalent to wiring up `addChild` + `addSubview` + `didMove`
    /// manually with full-bounds auto-resizing. Safe to call before
    /// `viewDidLoad`; the embed is queued and flushed when the view
    /// loads. Use this for "I have an existing VC, please host it"
    /// — for fully-custom layouts, just add subviews to `contentView`
    /// directly inside `viewDidLoad`.
    public func embedContent(_ child: UIViewController) {
        pendingEmbed = child
        if isViewLoaded {
            flushPendingEmbed()
        }
    }

    private var pendingEmbed: UIViewController?

    private func flushPendingEmbed() {
        guard let child = pendingEmbed else { return }
        pendingEmbed = nil
        addChild(child)
        child.view.frame = contentView.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(child.view)
        child.didMove(toParent: self)
    }

    open override func loadView() {
        let root = RootView()
        root.backgroundColor = .clear
        // On iOS 26+ we shape the sheet via `cornerConfiguration` directly
        // on the native glass view — see `updateCornerShape()`. On legacy
        // we no longer install the CAShapeLayer mask up front: when top
        // and bottom radii are equal (chamfer-less device) `updateMaskPath`
        // takes the cheap `layer.cornerRadius` path; only when asymmetric
        // (iPhone X+ with a chamfer-matching bottom radius) does it
        // attach `maskLayer` lazily.

        root.addSubview(glassBackground)

        // Public content host first (lower z-order) so chrome (grabber,
        // footer) sits visually above the form. Everything below sits
        // inside the rounded glass clip — the legacy CAShapeLayer mask
        // on root (or `cornerConfiguration` on the native glass) clips
        // overflow when `contentView`'s stage2-sized bounds extend past
        // the modal's current visible bounds.
        glassBackground.contentView.addSubview(contentView)
        // Footer host overlays content. It anchors to the BOTTOM of the
        // current `view.bounds` (i.e. the modal's visible bottom edge),
        // so it follows the sheet across detents instead of staying
        // pinned to the fixed-size content host.
        glassBackground.contentView.addSubview(footerHost)
        glassBackground.contentView.addSubview(grabberContainer)
        glassBackground.glassIsInteractive = true

        grabberView.backgroundColor = UIColor.label.withAlphaComponent(0.28)
        grabberView.layer.cornerRadius = Self.grabberSize.height / 2.0
        grabberView.layer.cornerCurve = .continuous
        grabberView.isUserInteractionEnabled = false
        grabberContainer.isUserInteractionEnabled = false
        grabberContainer.addSubview(grabberView)

        view = root
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        flushPendingEmbed()
        // Always observe the keyboard — even modals with no footer
        // benefit from the automatic `primaryScrollView.contentInset`
        // adjustment so subclasses don't have to roll their own
        // `keyboardWillChangeFrame` observer.
        installKeyboardObserversIfNeeded()
    }

    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        compensatePhantomSafeArea()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutChrome()
        updateCornerShape()
    }

    /// Pre-warm the top safe area for the upcoming frame change.
    /// Reads `RootView.safeAreaInsets.top` so UIKit caches the new value
    /// before our caller (`AetherModalPresentationController.applyDrag`
    /// / `tickSettleLink`) snaps the frame, which avoids a one-frame
    /// seam between the navbar (anchored to `safeAreaLayoutGuide`) and
    /// the rest of the content.
    ///
    /// `RootView.safeAreaInsets.top` is computed from the view's current
    /// position in the window plus the grabber strip — so the prior
    /// `additionalSafeAreaInsets`-based "compensation" formula is no
    /// longer needed. (It was actually a no-op against the override
    /// anyway: `view.safeAreaInsets.top - additionalSafeAreaInsets.top`
    /// doesn't isolate the inherited-only contribution when the override
    /// returns a value that ignores additional.)
    private func compensatePhantomSafeArea() {
        _ = view.safeAreaInsets
    }

    func compensateSafeAreaForUpcomingFrame(_ frame: CGRect, in container: UIView) {
        _ = view.safeAreaInsets
    }

    public func setDetent(_ detent: Detent, animated: Bool) {
        guard let presentation = presentationController as? AetherModalPresentationController else {
            return
        }
        presentation.setDetent(detent, animated: animated)
    }

    private var detentProgress: CGFloat = 0.0

    func applyDetentProgress(_ progress: CGFloat) {
        let clamped = max(0.0, min(1.0, progress))

        // The native UIGlassEffect tint animates cheaply on iOS 26+ — the
        // tint ramps from 0.6→1.0 alpha as the sheet climbs to stage2.
        // On the legacy path the same setter forces `setNeedsLayout` →
        // GlassBackgroundView.update(...) → full `generateLegacyGlassImage`
        // redraw of foregroundView/shadowView every frame, which made the
        // 60–120Hz settle animation stutter. The solid tint layer below
        // already darkens the glass content view as `clamped` rises —
        // that's enough on legacy.
        //
        // Mirror the EXACT conditions GlassBackgroundView uses to pick the
        // native vs custom backend. Plain `#available(iOS 26.0, *)` isn't
        // enough — when the host app sets `isLiquidDesignAvailable=false`
        // (Info.plist flag) we're on iOS 26 hardware but still routed
        // through the custom legacy backend, and the per-tick setter pegs
        // the CPU at ~160% during drag because every pan tick re-renders
        // the gradient/border bitmap via `generateLegacyGlassImage`.
        if GlassCompatibility.isLiquidDesignAvailable,
           #available(iOS 26.0, *),
           !GlassBackgroundView.useCustomGlassImpl {
            let minTintAlpha: CGFloat = 0.6
            let tintAlpha = minTintAlpha + (1.0 - minTintAlpha) * clamped
            glassBackground.glassTintColor = .init(
                kind: .custom(style: .default, color: config.dimTintColor.withAlphaComponent(tintAlpha))
            )
        }
        // Solid tint layer on the glass content view ramps from clear
        // (stage1, glass shows through) to opaque (stage2, sheet hides
        // the presenter). On iOS 26+ this layer is shaped by the
        // `cornerConfiguration` we install on `contentView` in
        // `applyCornerConfiguration`, so the colour no longer bleeds past
        // the rounded outline. On iOS<26 the CAShapeLayer mask on root
        // clips it as before.
        //
        // Floor on legacy. Without one, stage1 had `alpha=0` so the
        // glass blur sampled raw presenter pixels — over a saturated
        // chat-list (chips photos, accent bubbles) the legacy
        // CABackdropLayer "burned" those colours through. A 0.5 alpha
        // floor flattens the sample to mostly `dimTintColor` =
        // `systemBackground`, giving the blur soft glass material to
        // work with regardless of what's behind. iOS 26+ doesn't need
        // this because the native UIGlassEffect handles its own
        // material density.
        // Same gate as the glassTintColor branch above — `isLiquidDesignAvailable=false`
        // on an iOS 26 device still routes through the legacy CABackdropLayer
        // backend, which needs the 0.5 floor to keep saturated content from
        // burning through the blur sample.
        let effectiveAlpha: CGFloat
        if GlassCompatibility.isLiquidDesignAvailable,
           #available(iOS 26.0, *),
           !GlassBackgroundView.useCustomGlassImpl {
            effectiveAlpha = clamped
        } else {
            let legacyFloor: CGFloat = 0.5
            effectiveAlpha = max(legacyFloor, clamped)
        }
        glassBackground.contentView.backgroundColor = config.dimTintColor.withAlphaComponent(effectiveAlpha)

        guard abs(detentProgress - clamped) > 0.0001 else { return }
        detentProgress = clamped
        updateCornerShape()
        delegate?.modalController(self, didUpdateDetentProgress: clamped)
    }

    func applyCurrentDetent(_ detent: Detent) {
        guard currentDetent != detent else { return }
        currentDetent = detent
        delegate?.modalController(self, didChangeDetent: detent)
    }

    /// 0 when the host device has no physical screen chamfer.
    func deviceCornerRadius() -> CGFloat {
        if let presentation = presentationController as? AetherModalPresentationController {
            return presentation.deviceCornerRadius
        }
        return 0
    }

    private func layoutChrome() {
        // Disable implicit CALayer actions for the entire chrome layout
        // pass. `glassBackground.update` and `legacyView.update` underneath
        // hit `CALayer.frame` setters directly (via the `.immediate`
        // ContainedViewLayoutTransition), which still queue implicit
        // animations on the BACKING layer because UIView's actionForLayer
        // suppression only covers properties UIView itself sets through
        // its own setters — not direct CALayer.frame writes against
        // child layers like `CABackdropLayer`. Without this wrap, every
        // pan tick stacks a default 0.25s layer animation onto each glass
        // / grabber / footer sublayer; on a slow drag they edge-chase
        // each other into visible jitter.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // `.immediate` inside an outer UIView.animate is the right call:
        // it just sets frames/cornerRadius directly, and those direct sets
        // are captured by the enclosing CA transaction — so they inherit
        // the outer spring timing. A non-immediate transition here would
        // spawn a nested UIView.animate with its own damping (500 for
        // `.spring`), which doesn't match the caller's curve and makes
        // the glass race ahead of (or lag behind) the root frame.
        glassBackground.frame = view.bounds
        // cornerRadius=0 here: on iOS 26+ the shape comes from
        // `cornerConfiguration` installed on the native glass view (see
        // `applyCornerConfiguration`). On iOS<26 the legacy backdrop is
        // shaped by the CAShapeLayer mask on root. Passing a non-zero
        // cornerRadius to the native pipeline is now a no-op anyway —
        // `update(...)` skips `layer.cornerRadius`/`masksToBounds` when
        // a `cornerConfiguration` is set, so the deformation isn't clipped.
        glassBackground.update(size: view.bounds.size, cornerRadius: 0.0, transition: .immediate)

        let grabberHeight = Self.grabberContainerHeight
        grabberContainer.frame = CGRect(
            x: 0.0,
            y: 0.0,
            width: view.bounds.width,
            height: grabberHeight
        )
        grabberView.frame = CGRect(
            x: (view.bounds.width - Self.grabberSize.width) / 2.0,
            y: (grabberHeight - Self.grabberSize.height) / 2.0,
            width: Self.grabberSize.width,
            height: Self.grabberSize.height
        )

        // Width tracks the modal frame so the navbar / content stretch
        // to the actual sheet width at every detent (config.sideInset
        // differs between stage1 and stage2). Height is pinned to the
        // stage2 maximum — that's the half whose change is expensive
        // for an auto-layout subtree (scroll content reflow, sticky-
        // bottom alignment), and pinning it skips the per-tick solver
        // pass during a drag. At stage1 the bottom of `contentView`
        // simply hangs below the visible modal and is clipped by the
        // rounded outline mask.
        let hostHeight = expectedContentSize == .zero
            ? view.bounds.height
            : expectedContentSize.height
        let hostFrame = CGRect(
            x: 0,
            y: 0,
            width: view.bounds.width,
            height: hostHeight
        )
        if contentView.frame != hostFrame {
            contentView.frame = hostFrame
        }

        layoutFooter()
    }

    private func layoutFooter() {
        let hasFooter = footerView != nil && footerHeight > 0
        let fade = footerEdgeFadeHeight
        let totalH = hasFooter ? (footerHeight + fade) : 0

        // Footer slides up over the keyboard so it stays accessible while
        // a text input has focus. `keyboardOverlap` is in our coordinate
        // space; subtracting it from the bottom edge raises the footer by
        // exactly the obscured amount.
        let footerHostFrame = CGRect(
            x: 0,
            y: view.bounds.height - keyboardOverlap - totalH,
            width: view.bounds.width,
            height: totalH
        )
        // footerHost.frame change is just origin + width sliding; height
        // delta only happens when the footer is enabled/disabled or the
        // sheet's `view.bounds.width` shifts (stage1 sideInset vs stage2).
        // We re-set unconditionally because UIView frame setters short-
        // circuit on equality.
        if footerHost.frame != footerHostFrame {
            footerHost.frame = footerHostFrame
        }

        if let footerView, hasFooter {
            footerView.frame = CGRect(
                x: 0,
                y: fade,
                width: view.bounds.width,
                height: footerHeight
            )
        }

        if hasFooter, abs(totalH - lastAppliedFooterHostHeight) > 2.0 {
            let tint = footerEdgeTintColor
                ?? config.dimTintColor.withAlphaComponent(0.86)
            footerHost.setEdgeEffect(.init(
                edge: .bottom,
                thickness: totalH,
                fadeHeight: fade,
                tintColor: tint,
                tintAlpha: 1.0,
                blurRadius: footerEdgeBlurRadius
            ))
            lastAppliedFooterHostHeight = totalH
        } else if !hasFooter, lastAppliedFooterHostHeight != 0 {
            footerHost.setEdgeEffect(nil)
            lastAppliedFooterHostHeight = 0
        }

        // `setEdgeEffect` does `addSubview(effect)`, which puts the
        // frosted band ON TOP of any subviews already in `footerHost`
        // (i.e. the user's `footerView`). Promote the footer so it sits
        // above the frost — otherwise the button is faded/blurred by
        // its own edge effect.
        if let footerView, footerView.superview === footerHost {
            footerHost.bringSubviewToFront(footerView)
        }

        // Push only the footer's height onto the bottom safe-area inset
        // via a delta. Keyboard overlap is handled separately via direct
        // `primaryScrollView.contentInset.bottom` adjustment in
        // `syncPrimaryScrollViewKeyboardInset()` — adding it to the safe
        // area would double-inset any scroll inside the modal that uses
        // `contentInsetAdjustmentBehavior = .automatic` (the default),
        // because UIKit auto-adds safe area into `adjustedContentInset`
        // on top of our explicit `contentInset` write.
        let target = hasFooter ? footerHeight : 0
        if abs(target - lastFooterBottomInset) > 0.5 {
            let delta = target - lastFooterBottomInset
            lastFooterBottomInset = target
            additionalSafeAreaInsets.bottom += delta
        }
    }

    // MARK: - Keyboard observation

    private func installKeyboardObserversIfNeeded() {
        guard !keyboardObserversInstalled else { return }
        keyboardObserversInstalled = true
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(handleKeyboardWillChange(_:)),
                       name: UIResponder.keyboardWillChangeFrameNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(handleKeyboardWillHide(_:)),
                       name: UIResponder.keyboardWillHideNotification,
                       object: nil)
    }

    @objc private func handleKeyboardWillChange(_ note: Notification) {
        guard
            let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
            let window = view.window
        else { return }
        let converted = view.convert(end, from: window)
        let overlap = max(0.0, view.bounds.maxY - converted.origin.y)
        applyKeyboardOverlap(overlap, using: note)
    }

    @objc private func handleKeyboardWillHide(_ note: Notification) {
        applyKeyboardOverlap(0, using: note)
    }

    private func applyKeyboardOverlap(_ overlap: CGFloat, using note: Notification) {
        guard abs(keyboardOverlap - overlap) > 0.5 else { return }
        keyboardOverlap = overlap
        let duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curveRaw = (note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)
        // Drive layout + scroll-inset adjustment inside the keyboard's
        // own animation curve so the footer rides up flush with the
        // keyboard top and `primaryScrollView` content drifts up in
        // lockstep — instead of either catching up a frame later.
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
            self.syncPrimaryScrollViewKeyboardInset()
        }
        // Pull the active first responder into view AFTER its containing
        // scroll has been resized for the keyboard. `scrollRectToVisible`
        // is a no-op when the rect is already inside the visible area,
        // so this is harmless when the responder is above the keyboard.
        if overlap > 0 {
            scrollFirstResponderIntoView()
        }
    }

    /// Moves our keyboard contribution into `primaryScrollView.contentInset.bottom`
    /// (and the scroll-indicator inset) via a delta. Caller-set baselines
    /// on the scroll view's bottom inset survive — we only add/remove our
    /// own contribution.
    private func syncPrimaryScrollViewKeyboardInset() {
        guard let scroll = primaryScrollView else { return }
        let target = keyboardOverlap
        guard abs(target - lastKeyboardScrollInset) > 0.5 else { return }
        let delta = target - lastKeyboardScrollInset
        lastKeyboardScrollInset = target
        scroll.contentInset.bottom += delta
        scroll.verticalScrollIndicatorInsets.bottom += delta
    }

    /// Walks `primaryScrollView`'s subview tree, finds the active first
    /// responder, and scrolls a small padded rect around it into the
    /// visible area. No-op if no responder lives inside the scroll, or
    /// the responder is already on-screen.
    private func scrollFirstResponderIntoView() {
        guard let scroll = primaryScrollView,
              let responder = Self.findFirstResponder(in: scroll) else { return }
        var rect = responder.convert(responder.bounds, to: scroll)
        // Small breathing margin above + below the responder so the
        // caret sits a little inside the visible area, not flush against
        // the keyboard edge.
        rect = rect.insetBy(dx: 0, dy: -16)
        scroll.scrollRectToVisible(rect, animated: false)
    }

    private static func findFirstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let r = findFirstResponder(in: sub) { return r }
        }
        return nil
    }

    /// Pushed in by `AetherModalPresentationController` once per container
    /// layout pass — the size we want `contentView` (and everything inside)
    /// to lay out for. Drag does NOT call this; only orientation / scene
    /// resize does.
    func setExpectedContentSize(_ size: CGSize) {
        guard expectedContentSize != size else { return }
        expectedContentSize = size
        if isViewLoaded {
            view.setNeedsLayout()
        }
    }

    private struct MaskSignature: Equatable {
        let bounds: CGRect
        let topRadius: CGFloat
        let bottomRadius: CGFloat
    }
    private var lastMaskSignature: MaskSignature?
    private var lastCornerSignature: MaskSignature?

    /// Top corners are fixed at `config.topCornerRadius` (34 by default)
    /// on every device. Bottom corners depend on whether the physical
    /// screen has a chamfer:
    ///   - `deviceRadius > 0` (iPhone X and newer): bottom matches the
    ///     device's own corner radius (read via the private
    ///     `_displayCornerRadius`) so the sheet nests into the bezel.
    ///   - `deviceRadius == 0` (pre-iPhone X, iPad, anything without
    ///     a chamfer): bottom matches the top radius. We *used to* ramp
    ///     it from `topCornerRadius` to 0 over `detentProgress` so the
    ///     bottom flattened against the device edge at stage2, but on
    ///     legacy that ramp meant the `CAShapeLayer` mask path rebuilt
    ///     every settle tick — sustained ~60% CPU on iPhone 7. Symmetric
    ///     corners let `updateMaskPath` route through `layer.cornerRadius`
    ///     instead, which is GPU-rendered and free per-frame.
    private func resolvedCornerRadii() -> (top: CGFloat, bottom: CGFloat) {
        let deviceRadius = deviceCornerRadius()
        let topRadius = config.topCornerRadius
        let bottomRadius: CGFloat
        if deviceRadius > 0 {
            bottomRadius = deviceRadius
        } else {
            bottomRadius = topRadius
        }
        return (topRadius, bottomRadius)
    }

    private func updateCornerShape() {
        // iOS 26+: use native `cornerConfiguration` — GPU-rounded with
        // O(1) layer property updates per pan tick (no path build / no
        // CAShapeLayer rasterization). Whether we ALSO clip the root's
        // children depends on the glass backend:
        //
        //   * Native glass (`isLiquidDesignAvailable && !useCustomGlassImpl`):
        //     leave `view.clipsToBounds = false` so the elastic
        //     deformation can bulge past the rounded outline. The native
        //     glass view itself carries an identical `cornerConfiguration`
        //     via `setNativeCornerConfiguration`, which shapes the
        //     deformation without clipping the floating feel.
        //   * Legacy glass (everything else on iOS 26 — including the
        //     compat-flag path on iPhone 17 Pro): clip the root. The
        //     legacy backend's `foregroundView` carries a flat-cornered
        //     border image that leaks past the rounded outline if the
        //     root doesn't clip — and there's no elastic deformation to
        //     preserve.
        //
        // Pre-iOS 26 lacks `cornerConfiguration` entirely, so we fall
        // back to the CAShapeLayer mask. That path rebuilds a
        // `UIBezierPath` per pan tick on chamfered devices, which is
        // measurable in Instruments — but the device is older anyway.
        if #available(iOS 26.0, *) {
            let usingNativeGlass = GlassCompatibility.isLiquidDesignAvailable
                && !GlassBackgroundView.useCustomGlassImpl
            applyCornerConfiguration(clipRoot: !usingNativeGlass)
        } else {
            updateMaskPath()
        }
    }

    @available(iOS 26.0, *)
    private func applyCornerConfiguration(clipRoot: Bool) {
        let bounds = view.bounds
        let (topRadius, bottomRadius) = resolvedCornerRadii()
        let signature = MaskSignature(bounds: bounds, topRadius: topRadius, bottomRadius: bottomRadius)
        if signature == lastCornerSignature, view.clipsToBounds == clipRoot { return }
        lastCornerSignature = signature

        let configuration = UICornerConfiguration.uniformEdges(
            topRadius: .fixed(topRadius),
            bottomRadius: .fixed(bottomRadius)
        )
        // Disable implicit CALayer animations on the property writes —
        // `cornerConfiguration` setters can otherwise kick off a default
        // animation between successive pan ticks, which on a 120Hz slow
        // drag stack into visible jitter as the modal frame edges chase
        // their own animated values.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Apply to the root so child views (content, grabber, footer)
        // participate in the rounded outline. Apply to the native glass
        // too so the interactive deformation is shaped by the same
        // per-corner config — that's what restores the floating feel
        // a CAShapeLayer mask was clipping.
        view.cornerConfiguration = configuration
        glassBackground.setNativeCornerConfiguration(configuration)
        glassBackground.contentView.cornerConfiguration = configuration
        glassBackground.contentView.clipsToBounds = true
        // `clipsToBounds` on root is the difference between the legacy
        // backend (clip the foregroundView's flat-cornered border) and
        // the native backend (don't clip — preserve elastic deformation).
        view.clipsToBounds = clipRoot
        // The mask layer is the alternate, expensive path — drop it so
        // we don't end up with both a corner-config shape AND a stale
        // CAShapeLayer mask competing.
        if view.layer.mask === maskLayer {
            view.layer.mask = nil
        }
        view.layer.cornerRadius = 0
        CATransaction.commit()
    }

    private func updateMaskPath() {
        let bounds = view.bounds
        let (topRadius, bottomRadius) = resolvedCornerRadii()

        // Symmetric top/bottom corners — let CALayer round them via
        // `cornerRadius` (GPU path, no per-frame CPU cost). The
        // CAShapeLayer mask path was the dominant CPU bottleneck on
        // iPhone 7 / iOS 15: every settle tick rebuilt a UIBezierPath
        // and re-rasterised the mask layer, holding the device at
        // ~60–70% CPU through the entire animation. cornerRadius costs
        // nothing once set.
        if topRadius == bottomRadius {
            if view.layer.mask != nil {
                view.layer.mask = nil
            }
            view.layer.cornerCurve = .continuous
            view.layer.masksToBounds = true
            if abs(view.layer.cornerRadius - topRadius) > 0.01 {
                view.layer.cornerRadius = topRadius
            }
            // Drop the cached path signature — the next time corners go
            // asymmetric again (theme switch?), updateMaskPath will
            // re-wire the CAShapeLayer mask from scratch.
            lastMaskSignature = nil
            return
        }

        // Asymmetric corners — fall back to the CAShapeLayer mask.
        // Reached on devices with a screen chamfer (iPhone X+), where
        // the bottom radius matches `_displayCornerRadius` and stays
        // fixed across detent changes, so the path signature cache
        // below catches the no-op cases.
        if view.layer.mask !== maskLayer {
            view.layer.cornerRadius = 0.0
            view.layer.masksToBounds = false
            view.layer.mask = maskLayer
        }

        let signature = MaskSignature(bounds: bounds, topRadius: topRadius, bottomRadius: bottomRadius)
        if signature == lastMaskSignature {
            return
        }
        lastMaskSignature = signature

        let newPath = Self.roundedRectPath(
            in: bounds,
            topLeftRadius: topRadius,
            topRightRadius: topRadius,
            bottomLeftRadius: bottomRadius,
            bottomRightRadius: bottomRadius
        ).cgPath

        let oldPath = maskLayer.path
        maskLayer.frame = bounds
        maskLayer.path = newPath

        if UIView.inheritedAnimationDuration <= 0, oldPath != newPath {
            maskLayer.removeAnimation(forKey: "path")
        }
    }

    /// Root view for the presented modal. UIKit propagates the window's
    /// full safe area (including the status bar) to the presented view even
    /// when the sheet frame doesn't overlap the status bar — this override
    /// computes the top inset from the sheet's actual position in the
    /// window so content anchored to `view.safeAreaLayoutGuide.topAnchor`
    /// doesn't get a phantom status-bar-sized gap at the top.
    private final class RootView: UIView {
        override var safeAreaInsets: UIEdgeInsets {
            let inherited = super.safeAreaInsets
            let topInWindow = convert(CGPoint.zero, to: nil).y
            let windowSafeTop = window?.safeAreaInsets.top ?? 0.0
            let overlap = max(0.0, windowSafeTop - topInWindow)
            // Reserve the grabber strip as the modal's top safe area —
            // subclass content (or any embedded child VC) anchored to
            // `safeAreaLayoutGuide.topAnchor` ends up below the grabber
            // pill. Bundling it here (as opposed to into
            // `additionalSafeAreaInsets`) keeps `applyCompensatedSafeAreaTop`'s
            // formula a stable fixed-point — adding `additional` would
            // grow without bound because this override discards the
            // additional-derived top that the formula tries to subtract.
            return UIEdgeInsets(
                top: overlap + AetherModalController.grabberContainerHeight,
                left: inherited.left,
                bottom: inherited.bottom,
                right: inherited.right
            )
        }
    }

    private static func roundedRectPath(
        in rect: CGRect,
        topLeftRadius tl: CGFloat,
        topRightRadius tr: CGFloat,
        bottomLeftRadius bl: CGFloat,
        bottomRightRadius br: CGFloat
    ) -> UIBezierPath {
        let path = UIBezierPath()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: tl, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(
            withCenter: CGPoint(x: w - tr, y: tr),
            radius: tr,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(
            withCenter: CGPoint(x: w - br, y: h - br),
            radius: br,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(
            withCenter: CGPoint(x: bl, y: h - bl),
            radius: bl,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(
            withCenter: CGPoint(x: tl, y: tl),
            radius: tl,
            startAngle: .pi,
            endAngle: 3 * .pi / 2,
            clockwise: true
        )
        path.close()
        return path
    }
}
