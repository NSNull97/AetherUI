import UIKit

// MARK: - ContextMenuMorphAnchor

/// Which corner of the source rect coincides with a corner of the menu
/// rect. Detected by matching shared edges — a right-side button's menu
/// unfolds from the button's top-right (or bottom-right when flipped
/// upward) corner; a left-side button's from the top-left; and so on.
///
/// Threaded into `ContextMenuFluidMorphHostView.configure` so the
/// content subviews pin themselves to that corner via `autoresizingMask`.
/// When the glass envelope grows from source-size to menu-size, an
/// autoresized subview's frame is recomputed such that the two fixed
/// margins (opposite to the flexible ones) stay constant. That keeps
/// the anchored corner of the subview locked to the same glass-local
/// coordinate throughout the animation.
///
/// Combined with the fact that `ContextMenuController.computeMenuFrame`
/// pins the glass's own anchor corner on-screen (e.g. `menu.maxX ==
/// source.maxX` for right-aligned layouts), the result is: both content
/// containers (source snapshot + actions view) stay *stationary in
/// absolute screen coordinates* throughout the morph. Only the glass
/// envelope moves, revealing or clipping more of the actions view as
/// it grows.
///
/// No left-jumping, no unfolding from the wrong edge — the animation
/// quite literally unfolds the menu out of the button.
enum ContextMenuMorphAnchor {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    /// Infer the anchor from the relationship between source and menu
    /// rects. `computeMenuFrame` places them so either their right
    /// edges or their left edges coincide, and similarly on the
    /// vertical axis; we use a 1pt tolerance for float jitter.
    static func detect(source: CGRect, menu: CGRect) -> ContextMenuMorphAnchor {
        let tolerance: CGFloat = 1
        let isTrailing = abs(menu.maxX - source.maxX) < tolerance
        let isBottom = abs(menu.maxY - source.maxY) < tolerance
        switch (isBottom, isTrailing) {
        case (true, true):   return .bottomTrailing
        case (true, false):  return .bottomLeading
        case (false, true):  return .topTrailing
        case (false, false): return .topLeading
        }
    }

    /// Autoresizing mask that pins a subview to this anchor corner as
    /// its parent resizes. The two margins OPPOSITE to the anchor are
    /// flexible (they absorb all of the parent's growth); the anchor-
    /// adjacent margins (plus the subview's own width/height) stay
    /// fixed.
    var autoresizingMask: UIView.AutoresizingMask {
        switch self {
        case .topLeading:     return [.flexibleRightMargin, .flexibleBottomMargin]
        case .topTrailing:    return [.flexibleLeftMargin,  .flexibleBottomMargin]
        case .bottomLeading:  return [.flexibleRightMargin, .flexibleTopMargin]
        case .bottomTrailing: return [.flexibleLeftMargin,  .flexibleTopMargin]
        }
    }
}

// MARK: - ContextMenuFluidMorphHostView

/// Fluid morph host for the `.fluidMorph` presentation style. Three
/// design pillars:
///
/// ## 1. Spring on `self.frame` via `UIViewPropertyAnimator`
///
/// The host's own `frame` animates from `sourceFrameInHost` to
/// `menuFrameInHost` under a `UISpringTimingParameters` curve. Because
/// `computeMenuFrame` pins one on-screen edge of menu to source (e.g.
/// `menu.maxX == source.maxX` for right-aligned), that edge stays
/// invariant throughout the spring — a direct consequence of linear
/// interpolation of `position.x` and `bounds.width` combined. No
/// anchor-point gymnastics, no custom timeline — just math.
///
/// ## 2. Content containers anchored via `autoresizingMask`
///
/// `sourceContent` and `actionsContainer` live inside `glass.contentView`
/// and are positioned so that in ABSOLUTE host-level coordinates each
/// sits exactly where it wants to visually end up:
///
///   - `sourceContent` at `sourceFrameInHost` — the real button's rect.
///   - `actionsContainer` at `menuFrameInHost` — the final menu rect.
///
/// When the glass is at source size, `actionsContainer` extends past
/// glass on three sides and is clipped to a tiny source-sized window
/// at the shared anchor corner. As glass grows, the clip opens up and
/// the actions view is revealed — but the actions view itself never
/// physically moves in absolute coords. Ditto for the source snapshot
/// (which fades out before the glass grows past it anyway).
///
/// ## 3. Corner radius + shadow path via `CABasicAnimation`
///
/// `UIViewPropertyAnimator` can't carry layer-only properties, so
/// `cornerRadius` and `shadowPath` get their own CA animations, sharing
/// the duration but on an ease-out curve (not a spring — the perceptual
/// bounce comes from the frame animation alone, and layer softening
/// matches better with ease-out).
///
/// ## Fluid cross-fade
///
/// Source snapshot fades out over the first ~35% of the morph. Actions
/// container fades in from ~30% to ~85%. The 5% overlap prevents any
/// "bald glass" frame between the two. Fades use `UIViewPropertyAnimator`
/// so they're interruptible alongside the geometry animation — a dismiss
/// mid-open stops all three animators at `.current` and a fresh collapse
/// animator springs back from wherever they happen to be.
final class ContextMenuFluidMorphHostView: UIView {
    struct Metrics {
        let sourceFrameInHost: CGRect
        let sourceCornerRadius: CGFloat
        let menuFrameInHost: CGRect
        let menuCornerRadius: CGFloat
        let anchor: ContextMenuMorphAnchor
    }

    let glass: MenuGlassSurfaceView
    /// Container for the source-button snapshot. Sized to source size,
    /// pinned to the anchor corner of `glass.contentView` via
    /// autoresizing. Fades out in the first ~35% of the morph.
    let sourceContent = UIView()
    /// Container for the `ContextMenuActionsView`. Sized to menu size,
    /// positioned inside `glass.contentView` such that its absolute
    /// rect (in host coords) equals `menuFrameInHost` throughout the
    /// morph. Fades in over the last ~55% of the morph.
    let actionsContainer = UIView()
    var actionsRevealProgressChanged: ((CGFloat) -> Void)?

    private(set) var metrics: Metrics?
    private var runningAnimators: [UIViewPropertyAnimator] = []
    private var progressDisplayLink: CADisplayLink?
    private var progressStart: CFTimeInterval = 0
    private var progressDuration: TimeInterval = 0
    private var progressReversed = false

    // MARK: - Cross-fade curves

    /// "Emphasized accelerate" — lingers gently for a breath, then
    /// exits sharply. Used on actions-view fade-out during collapse,
    /// where the rows should stay visible while glass is still big
    /// and only vanish when it's shrunk back near button size.
    ///
    /// Deliberately NOT used on source fade-out during expand: there
    /// the tap-target content must read as "gone" from the first
    /// frame of the morph (see that call site), so we use a standard
    /// `.easeOut` instead of this linger-then-exit curve.
    private static let fadeOutCurve = UICubicTimingParameters(
        controlPoint1: CGPoint(x: 0.30, y: 0.00),
        controlPoint2: CGPoint(x: 0.85, y: 0.20)
    )

    /// "Emphasized decelerate" — comes in fast, lands slowly. Used on
    /// actions-view fade-in during expand (and source fade-in during
    /// collapse). Pairs with the spring's settling overshoot — content
    /// is visually "in place" well before the spring finishes wobbling,
    /// so the bounce reads as part of a single fluid arrival.
    private static let fadeInCurve = UICubicTimingParameters(
        controlPoint1: CGPoint(x: 0.05, y: 0.70),
        controlPoint2: CGPoint(x: 0.10, y: 1.00)
    )

    // MARK: - Shadow opacity keyframes

    /// Shadow opacity at rest — set at init and the base value the
    /// CAKeyframeAnimation returns to at the end of the morph.
    private static let shadowOpacityStart: Float = 0.04
    private static let shadowOpacityRest: Float = 0.12
    /// Peak shadow opacity reached mid-morph (40% in). Simulates the
    /// motion-heaviness of a real object being pushed through space —
    /// as the surface accelerates, it casts a briefly-darker shadow.
    /// Subtle, but it adds a ton of perceived "weight" / fluid-ness.
    private static let shadowOpacityPeak: Float = 0.18

    // MARK: - Elastic curve

    /// Fraction of `|menu.center − source.center|` added as a
    /// perpendicular-to-motion bulge at mid-morph. 0.08 = 8% of the
    /// straight-line distance. For a typical 135pt source→menu
    /// traversal that's ~11pt of visible arc — enough to clearly
    /// read as "not a straight line" without looking cartoonish.
    /// Scale up for a more pronounced swoop, down for subtler.
    private static let elasticCurveMagnitude: CGFloat = 0.08

    /// Perpendicular-to-motion translation vector applied via keyframe
    /// animation to the host's `layer.transform`. Computed from the
    /// source/menu centres in `configure` and reused by both
    /// `animateExpand` and `animateCollapse` so the arc hugs the same
    /// curve for open and close (just traversed in opposite
    /// directions — A→B via the curve on open, B→A via the same curve
    /// on close). Net visual: the menu swoops rather than slides.
    private var elasticCurvePeak: CGPoint = .zero

    // MARK: - Init

    init(isDark: Bool) {
        self.glass = MenuGlassSurfaceView(isDark: isDark)
        super.init(frame: .zero)

        backgroundColor = .clear
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 10
        layer.shadowOpacity = Self.shadowOpacityStart

        glass.clipsToBounds = true
        if #available(iOS 13.0, *) {
            glass.layer.cornerCurve = .continuous
        }
        // Glass fills the host via autoresizing — when we animate `self`'s
        // frame, glass.bounds follow automatically, and the content
        // subviews inside glass.contentView then autoresize off the new
        // glass.bounds via THEIR own masks. Single source of truth: the
        // host's frame animator.
        glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(glass)

        sourceContent.backgroundColor = .clear
        sourceContent.isUserInteractionEnabled = false
        glass.contentView.addSubview(sourceContent)

        actionsContainer.backgroundColor = .clear
        actionsContainer.isUserInteractionEnabled = true
        actionsContainer.alpha = 0
        glass.contentView.addSubview(actionsContainer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        progressDisplayLink?.invalidate()
    }

    // MARK: - Configuration

    /// Lay everything out at t=0: host sits at source rect, glass fills
    /// host, source snapshot pinned to the anchor corner, actions
    /// container positioned so its absolute rect equals
    /// `menuFrameInHost`. Alphas set for the initial state (source=1,
    /// actions=0).
    func configure(metrics: Metrics) {
        self.metrics = metrics
        self.elasticCurvePeak = Self.computeElasticCurvePeak(
            sourceCentre: CGPoint(
                x: metrics.sourceFrameInHost.midX,
                y: metrics.sourceFrameInHost.midY
            ),
            menuCentre: CGPoint(
                x: metrics.menuFrameInHost.midX,
                y: metrics.menuFrameInHost.midY
            )
        )
        cancelRunningAnimators()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Host sits at source rect; glass fills host bounds.
        self.frame = metrics.sourceFrameInHost
        glass.frame = CGRect(origin: .zero, size: metrics.sourceFrameInHost.size)
        glass.layer.cornerRadius = metrics.sourceCornerRadius
        glass.updateMaterialThickness(0.0)
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 10
        layer.shadowOpacity = Self.shadowOpacityStart
        layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: metrics.sourceFrameInHost.size),
            cornerRadius: metrics.sourceCornerRadius
        ).cgPath

        // sourceContent: sized to source, pinned at the anchor corner of
        // glass.contentView (which currently has the same size as the
        // content, so origin is (0,0) — but we compute it generically
        // because we use the same helper for sizes that DON'T match).
        sourceContent.frame = CGRect(
            origin: cornerOrigin(
                container: metrics.sourceFrameInHost.size,
                content: metrics.sourceFrameInHost.size,
                anchor: metrics.anchor
            ),
            size: metrics.sourceFrameInHost.size
        )
        sourceContent.autoresizingMask = metrics.anchor.autoresizingMask
        sourceContent.alpha = 1
        sourceContent.transform = .identity

        // actionsContainer starts anchored to the same corner as the
        // source and autoresizes into `origin == .zero` when the host
        // reaches `menuFrameInHost`. The previous source-relative
        // origin (`menu.min - source.min`) kept absolute coordinates
        // fixed during the morph, but left a permanent local offset in
        // the settled menu, so rows rendered shifted inside the glass.
        actionsContainer.frame = CGRect(
            origin: cornerOrigin(
                container: metrics.sourceFrameInHost.size,
                content: metrics.menuFrameInHost.size,
                anchor: metrics.anchor
            ),
            size: metrics.menuFrameInHost.size
        )
        actionsContainer.autoresizingMask = metrics.anchor.autoresizingMask
        actionsContainer.alpha = 0
        actionsContainer.transform = CGAffineTransform(translationX: 0, y: 6)
        actionsRevealProgressChanged?(0)

        CATransaction.commit()
    }

    /// Origin for a `content`-sized rect sitting in the given `anchor`
    /// corner of a `container`-sized parent. For sourceContent we pass
    /// container == content, giving (0,0) for topLeading, (0,0) for
    /// the other corners too at t=0 because the two sizes are equal;
    /// once the parent grows, autoresizing recomputes the origin.
    private func cornerOrigin(container: CGSize, content: CGSize, anchor: ContextMenuMorphAnchor) -> CGPoint {
        let dx = container.width - content.width
        let dy = container.height - content.height
        switch anchor {
        case .topLeading:     return CGPoint(x: 0,  y: 0)
        case .topTrailing:    return CGPoint(x: dx, y: 0)
        case .bottomLeading:  return CGPoint(x: 0,  y: dy)
        case .bottomTrailing: return CGPoint(x: dx, y: dy)
        }
    }

    // MARK: - Animate expand

    /// Drive `self.frame` from source to menu with a spring
    /// `UIViewPropertyAnimator`. Glass auto-tracks via flexible-width/
    /// height. Content containers stay stationary in absolute coords
    /// (see type doc). Source cross-fades out early with emphasized
    /// accelerate, actions fades in late with emphasized decelerate,
    /// corner radius settles with a matching CASpringAnimation, and
    /// shadow opacity briefly thickens mid-morph for extra "weight".
    func animateExpand(
        duration: TimeInterval,
        damping: CGFloat,
        completion: (() -> Void)? = nil
    ) {
        guard let metrics else { completion?(); return }

        cancelRunningAnimators()

        // Layer-level animations — corner radius (spring), shadow path
        // (cubic bezier), shadow opacity (keyframe w/ mid-morph peak).
        // Shares the frame spring's `damping` so the corner's wobble
        // arrives in phase with the frame's overshoot.
        addLayerAnimations(
            fromCornerRadius: metrics.sourceCornerRadius,
            toCornerRadius: metrics.menuCornerRadius,
            fromSize: metrics.sourceFrameInHost.size,
            toSize: metrics.menuFrameInHost.size,
            duration: duration,
            springDampingRatio: damping
        )

        // Core geometry: spring on host.frame. Glass auto-follows via
        // its [.flexibleWidth, .flexibleHeight] mask. Content containers
        // auto-follow via their corner-anchored masks, staying stationary
        // in absolute coords.
        let timing = UISpringTimingParameters(dampingRatio: damping, initialVelocity: .zero)
        let geometry = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        geometry.isInterruptible = true
        geometry.addAnimations {
            self.frame = metrics.menuFrameInHost
        }

        let sourceFade = UIViewPropertyAnimator(
            duration: duration * 0.20,
            curve: .easeOut
        ) {
            self.sourceContent.alpha = 0
            self.sourceContent.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }

        let actionsFade = UIViewPropertyAnimator(
            duration: duration * 0.50,
            timingParameters: Self.fadeInCurve
        )
        actionsFade.addAnimations {
            self.actionsContainer.alpha = 1
            self.actionsContainer.transform = .identity
        }

        geometry.addCompletion { [weak self] _ in
            self?.runningAnimators.removeAll { $0 === geometry }
            completion?()
        }
        sourceFade.addCompletion { [weak self] _ in
            self?.runningAnimators.removeAll { $0 === sourceFade }
        }
        actionsFade.addCompletion { [weak self] _ in
            self?.runningAnimators.removeAll { $0 === actionsFade }
        }

        runningAnimators.append(geometry)
        runningAnimators.append(sourceFade)
        runningAnimators.append(actionsFade)

        startProgressDisplayLink(duration: duration, reversed: false)
        geometry.startAnimation()
        sourceFade.startAnimation(afterDelay: duration * 0.08)
        actionsFade.startAnimation(afterDelay: duration * 0.18)
    }

    // MARK: - Animate collapse

    /// Mirror of `animateExpand` for dismissal. Frame springs back to
    /// source, actions fades out first, source re-materialises at the
    /// tail (never flashed full-alpha while glass is still big).
    func animateCollapse(
        duration: TimeInterval,
        damping: CGFloat,
        completion: (() -> Void)? = nil
    ) {
        guard let metrics else { completion?(); return }

        cancelRunningAnimators()

        addLayerAnimations(
            fromCornerRadius: metrics.menuCornerRadius,
            toCornerRadius: metrics.sourceCornerRadius,
            fromSize: metrics.menuFrameInHost.size,
            toSize: metrics.sourceFrameInHost.size,
            duration: duration,
            springDampingRatio: damping
        )

        let timing = UISpringTimingParameters(dampingRatio: damping, initialVelocity: .zero)
        let geometry = UIViewPropertyAnimator(duration: duration, timingParameters: timing)
        geometry.isInterruptible = true
        geometry.addAnimations {
            self.frame = metrics.sourceFrameInHost
        }

        // Actions fades out in the first ~40% — emphasized accelerate
        // matches the "getting out of the way" feel from expand,
        // just in reverse direction.
        let actionsFade = UIViewPropertyAnimator(
            duration: duration * 0.40,
            timingParameters: Self.fadeOutCurve
        )
        actionsFade.addAnimations {
            self.actionsContainer.alpha = 0
            self.actionsContainer.transform = CGAffineTransform(translationX: 0, y: 6)
        }

        // Source re-emerges in the tail half — emphasized decelerate
        // so it "lands" back into the button shape.
        let sourceFade = UIViewPropertyAnimator(
            duration: duration * 0.45,
            timingParameters: Self.fadeInCurve
        )
        sourceFade.addAnimations {
            self.sourceContent.alpha = 1
            self.sourceContent.transform = .identity
        }

        geometry.addCompletion { [weak self] _ in
            self?.runningAnimators.removeAll { $0 === geometry }
            completion?()
        }
        actionsFade.addCompletion { [weak self] _ in
            self?.runningAnimators.removeAll { $0 === actionsFade }
        }
        sourceFade.addCompletion { [weak self] _ in
            self?.runningAnimators.removeAll { $0 === sourceFade }
        }

        runningAnimators.append(geometry)
        runningAnimators.append(actionsFade)
        runningAnimators.append(sourceFade)

        startProgressDisplayLink(duration: duration, reversed: true)
        geometry.startAnimation()
        actionsFade.startAnimation()
        sourceFade.startAnimation(afterDelay: duration * 0.60)
    }

    // MARK: - Helpers

    /// Halt any in-flight expand/collapse animators, parking the view
    /// at the CURRENT presentation state. A fresh animator started
    /// immediately after will spring from that stopping point — key
    /// for interrupting an in-progress open with a dismiss (and vice
    /// versa) without teleports.
    ///
    /// Also tears down the elastic curve keyframe animations on the
    /// layer — those are CA-level and not managed by
    /// `UIViewPropertyAnimator`. On cancellation the transform snaps
    /// back to identity (model value), which may cause a small 1-
    /// frame glitch if interrupted mid-arc. The replacement collapse
    /// animation re-adds its own curve immediately, so the recovery
    /// blends in fast.
    private func cancelRunningAnimators() {
        for animator in runningAnimators where animator.state != .inactive {
            animator.stopAnimation(false)
            animator.finishAnimation(at: .current)
        }
        runningAnimators.removeAll()
        progressDisplayLink?.invalidate()
        progressDisplayLink = nil
        layer.removeAnimation(forKey: "elasticCurveX")
        layer.removeAnimation(forKey: "elasticCurveY")
    }

    private func startProgressDisplayLink(duration: TimeInterval, reversed: Bool) {
        progressDisplayLink?.invalidate()
        progressStart = CACurrentMediaTime()
        progressDuration = duration
        progressReversed = reversed

        let link = CADisplayLink(target: self, selector: #selector(handleProgressDisplayLink(_:)))
        let maximumFramesPerSecond = max(60, UIScreen.main.maximumFramesPerSecond)
        if #available(iOS 15.0, *) {
            let preferredFrameRate = Float(min(120, maximumFramesPerSecond))
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: min(80, preferredFrameRate),
                maximum: preferredFrameRate,
                preferred: preferredFrameRate
            )
        } else {
            link.preferredFramesPerSecond = maximumFramesPerSecond
        }
        link.add(to: .main, forMode: .common)
        progressDisplayLink = link
        updateProgressDrivenEffects(reversed ? 1 : 0)
    }

    @objc
    private func handleProgressDisplayLink(_ link: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - progressStart
        let rawT = progressDuration > 0 ? CGFloat(elapsed / progressDuration) : 1.0
        let t = max(0.0, min(1.0, rawT))
        updateProgressDrivenEffects(progressReversed ? (1.0 - t) : t)

        if rawT >= 1.0 {
            link.invalidate()
            progressDisplayLink = nil
        }
    }

    private func updateProgressDrivenEffects(_ phase: CGFloat) {
        let phaseT = max(0.0, min(1.0, phase))
        let materialT = Self.smootherstep(0.08, 0.72, phaseT)
        glass.updateMaterialThickness(materialT)
        actionsRevealProgressChanged?(Self.smootherstep(0.18, 0.68, phaseT))
    }

    private static func smootherstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x <= edge0 ? 0 : 1 }
        let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * t * (t * (6.0 * t - 15.0) + 10.0)
    }

    // MARK: - Elastic curve

    /// Compute the perpendicular-to-motion peak offset for the
    /// elastic curve. The arc peaks at mid-morph by this much —
    /// biased CCW (rotate motion vector 90° counter-clockwise, then
    /// scale) so the path bows toward the "outward" side of the
    /// source→menu diagonal rather than cutting across it.
    ///
    /// Using CCW (instead of CW) was a visual call — for the typical
    /// right-side-button, menu-unfolds-down-left layout, CCW arcs
    /// through the upper-left of the straight line, reading as
    /// "menu swings out wide before settling". CW would dip the
    /// opposite way; flipping the sign of this vector would swap.
    private static func computeElasticCurvePeak(
        sourceCentre: CGPoint,
        menuCentre: CGPoint
    ) -> CGPoint {
        let dx = menuCentre.x - sourceCentre.x
        let dy = menuCentre.y - sourceCentre.y
        let distance = hypot(dx, dy)
        guard distance > 1 else { return .zero }
        // Perpendicular CCW: rotate (dx, dy) by +90° → (-dy, dx).
        // Then normalise and scale by 8% of straight-line distance.
        let magnitude = distance * elasticCurveMagnitude
        return CGPoint(
            x: -dy / distance * magnitude,
            y:  dx / distance * magnitude
        )
    }

    /// Add `CAKeyframeAnimation`s on `transform.translation.{x,y}`
    /// that trace a smooth sinusoidal arc — offset starts at 0,
    /// peaks at `elasticCurvePeak` at t=0.5, returns to 0 at t=1.
    ///
    /// 17 keyframes (sampled `sin(πt)`) give a visibly-smooth curve
    /// without the triangular kink a 3-keyframe `[0, peak, 0]`
    /// linear interpolation produces. `.easeInEaseOut` on the curve
    /// timing softens the ramp-in/ramp-out further.
    ///
    /// `isAdditive = true` means the animated translation is ADDED
    /// to whatever the layer's model transform already has — so a
    /// user-applied stretch transform (from the rubber-band touch
    /// interaction) doesn't get clobbered mid-morph.
    private func addElasticCurveAnimation(duration: TimeInterval) {
        let peak = elasticCurvePeak
        guard peak.x != 0 || peak.y != 0 else { return }

        let steps = 16
        var xValues: [CGFloat] = []
        var yValues: [CGFloat] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let factor = sin(t * .pi)  // 0 at ends, 1 at midpoint
            xValues.append(peak.x * factor)
            yValues.append(peak.y * factor)
        }

        let timing = CAMediaTimingFunction(name: .easeInEaseOut)

        let xAnim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        xAnim.values = xValues
        xAnim.duration = duration
        xAnim.timingFunction = timing
        xAnim.isAdditive = true
        layer.add(xAnim, forKey: "elasticCurveX")

        let yAnim = CAKeyframeAnimation(keyPath: "transform.translation.y")
        yAnim.values = yValues
        yAnim.duration = duration
        yAnim.timingFunction = timing
        yAnim.isAdditive = true
        layer.add(yAnim, forKey: "elasticCurveY")
    }

    /// Layer-level animations that the `UIViewPropertyAnimator` can't
    /// carry directly (it doesn't touch `CALayer.cornerRadius`, path
    /// values, or opacity keyframes). Three parts:
    ///
    ///   1. **Corner radius** — `CASpringAnimation` parameterised from
    ///      the same damping ratio as the frame spring, so corners
    ///      wobble in phase with the bounds. Feels organic — the
    ///      surface is ONE fluid thing, not a rectangle + separate
    ///      corner-radius timeline.
    ///
    ///   2. **Shadow path** — `CABasicAnimation` with a warm-decelerate
    ///      bezier (soft, no overshoot). Paths can't drive
    ///      `CASpringAnimation` (only scalars can), so this is where
    ///      we accept a small timing mismatch with the frame spring —
    ///      the shadow is soft enough that the drift isn't
    ///      perceptible.
    ///
    ///   3. **Shadow opacity** — `CAKeyframeAnimation` that peaks at
    ///      40% of duration (0.14 → 0.20 → 0.14). Simulates the motion-
    ///      weight of a real object casting a darker shadow as it
    ///      accelerates through space. Cheap but high-impact — this
    ///      is 70% of the "fluid weight" feeling.
    private func addLayerAnimations(
        fromCornerRadius: CGFloat,
        toCornerRadius: CGFloat,
        fromSize: CGSize,
        toSize: CGSize,
        duration: TimeInterval,
        springDampingRatio: CGFloat
    ) {
        // ─── 1. Corner radius: spring ────────────────────────────────
        //
        // Stiffness is tuned so the spring's natural period ~= the
        // animator's `duration`. Damping follows from the ratio:
        //   ω_n  = 2π / duration          (natural angular frequency)
        //   k    = ω_n²                   (stiffness, mass = 1)
        //   c    = 2 * ζ * √k             (damping)
        // with ζ = `springDampingRatio`. This matches the CA spring's
        // settling character to the UIViewPropertyAnimator's frame
        // spring — corners arrive in phase with bounds.
        let omega = 2 * CGFloat.pi / CGFloat(duration)
        let stiffness = omega * omega
        let cornerSpring = CASpringAnimation(keyPath: "cornerRadius")
        cornerSpring.mass = 1
        cornerSpring.stiffness = stiffness
        cornerSpring.damping = 2 * springDampingRatio * sqrt(stiffness)
        cornerSpring.initialVelocity = 0
        cornerSpring.fromValue = fromCornerRadius
        cornerSpring.toValue = toCornerRadius
        // `settlingDuration` is the time for the spring to settle within
        // ~1% of its rest value. Use that as the CA animation duration
        // so the wobble fully plays out instead of being cut off.
        cornerSpring.duration = cornerSpring.settlingDuration
        glass.layer.cornerRadius = toCornerRadius
        glass.layer.add(cornerSpring, forKey: "fluidMorphCorner")

        // ─── 2. Shadow path: cubic bezier (soft decelerate) ─────────
        let softDecel = CAMediaTimingFunction(controlPoints: 0.15, 0.55, 0.20, 1.00)
        let fromPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: fromSize),
            cornerRadius: fromCornerRadius
        ).cgPath
        let toPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: toSize),
            cornerRadius: toCornerRadius
        ).cgPath
        let shadowAnim = CABasicAnimation(keyPath: "shadowPath")
        shadowAnim.fromValue = fromPath
        shadowAnim.toValue = toPath
        shadowAnim.duration = duration
        shadowAnim.timingFunction = softDecel
        layer.shadowPath = toPath
        layer.add(shadowAnim, forKey: "fluidMorphShadow")

        // ─── 3. Shadow opacity: keyframe with mid-morph peak ────────
        let shadowOpacityAnim = CAKeyframeAnimation(keyPath: "shadowOpacity")
        let expanding = toSize.width * toSize.height >= fromSize.width * fromSize.height
        let fromOpacity = expanding ? Self.shadowOpacityStart : Self.shadowOpacityRest
        let toOpacity = expanding ? Self.shadowOpacityRest : Self.shadowOpacityStart
        shadowOpacityAnim.values = [
            fromOpacity,
            Self.shadowOpacityPeak,
            toOpacity
        ]
        shadowOpacityAnim.keyTimes = [0.0, 0.45, 1.0]
        shadowOpacityAnim.duration = duration
        shadowOpacityAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.shadowOpacity = toOpacity
        layer.add(shadowOpacityAnim, forKey: "fluidMorphShadowOpacity")

        let radiusAnim = CAKeyframeAnimation(keyPath: "shadowRadius")
        radiusAnim.values = expanding ? [10.0, 28.0, 22.0] : [22.0, 18.0, 10.0]
        radiusAnim.keyTimes = [0.0, 0.45, 1.0]
        radiusAnim.duration = duration
        radiusAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.shadowRadius = expanding ? 22.0 : 10.0
        layer.add(radiusAnim, forKey: "fluidMorphShadowRadius")

        let offsetAnim = CAKeyframeAnimation(keyPath: "shadowOffset")
        let offsetValues: [CGSize] = expanding
            ? [CGSize(width: 0, height: 3), CGSize(width: 0, height: 12), CGSize(width: 0, height: 8)]
            : [CGSize(width: 0, height: 8), CGSize(width: 0, height: 7), CGSize(width: 0, height: 3)]
        offsetAnim.values = offsetValues.map { NSValue(cgSize: $0) }
        offsetAnim.keyTimes = [0.0, 0.45, 1.0]
        offsetAnim.duration = duration
        offsetAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.shadowOffset = expanding ? CGSize(width: 0, height: 8) : CGSize(width: 0, height: 3)
        layer.add(offsetAnim, forKey: "fluidMorphShadowOffset")
    }
}
