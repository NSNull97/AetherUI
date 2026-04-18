import UIKit

// MARK: - ContextMenuMorphHostView
//
// Single-surface morph host for the button → context-menu transition, port
// of the architecture described in the "Liquid Glass morph" write-up. The
// principle: one glass view which grows from the source-button rect into
// the menu rect, with everything else (source label fading, menu rows
// appearing, shadow thickening, dim layering) driven by a single
// `progress: CGFloat` in [0, 1]. The old two-object approach (button
// fades, separate menu pops) reads like a popover; this reads like the
// button *is* the menu.
//
//   MorphHost (UIView)                  ← outer: shadow + anchors
//     ├ glass (UIVisualEffectView)      ← the liquid surface, corner-
//     │   │                              radius animated per-frame
//     │   └ contentView:
//     │       ├ sourceContentContainer  ← snapshot of source button,
//     │       │   size = collapsed      early fade-out at t=0.02…0.16
//     │       └ destinationContentContainer
//     │           size = expanded       late  fade-in  at t=0.28…0.42
//     │                                 + 8pt translateY slide
//     (outer layer.shadow* scales with t: radius 12→28, opacity 0.10→0.16)
//
// Callers:
//   1. Build host with `init(effect:)`.
//   2. Put the source snapshot inside `sourceContent` (frame at .zero,
//      size = collapsed.size).
//   3. Put the actions view inside `destinationContent` (frame at .zero,
//      size = expanded.size).
//   4. `configure(metrics:)` with collapsed/expanded rects + corners.
//   5. `animateProgress(to: 1, duration: …)` to open;
//      `animateProgress(to: 0, duration: …)` to dismiss.
//
// Reverse-animation asymmetry (per the rec: "закрытие быстрее, menu rows
// уходят первыми, label проявляется в самом конце") is FREE in this
// architecture — the smoothstep windows naturally run in reverse when
// progress drops 1→0, which means destination fades out first (t dropping
// past 0.42→0.28) and source only re-appears much later (t dropping past
// 0.16→0.02). Just use a shorter duration on the dismiss call and the
// asymmetry emerges.
final class ContextMenuMorphHostView: UIView {
    // MARK: - Configuration

    struct Metrics: Equatable {
        let collapsedFrame: CGRect
        let collapsedCornerRadius: CGFloat
        let expandedFrame: CGRect
        let expandedCornerRadius: CGFloat
    }

    // MARK: - Subviews

    let glass: UIVisualEffectView
    let sourceContent = UIView()
    let destinationContent = UIView()

    /// Plain UIView that wraps the glass effect view and carries the
    /// shape-layer mask. An earlier attempt set `layer.mask` directly on
    /// the UIVisualEffectView, but its backdrop rendering bypassed the
    /// mask (final menu had flat, un-rounded corners). Putting the mask
    /// on a *parent* UIView instead clips all rendered children — the
    /// VEF's blur included — because that clipping happens at the
    /// parent's layer composition level, which IS respected by UIKit.
    private let clipContainer = UIView()

    /// Shape-layer mask on `clipContainer`. Renders the asymmetric
    /// rounded-rect path (top-narrower "neck" / bottom-rounder "belly")
    /// that gives the droplet silhouette during the blob phase. Both
    /// corner radii converge to the uniform `baseCorner` at t=0 and
    /// t=1, so the endpoints are pristine collapsed / expanded rects.
    private let clipMaskLayer = CAShapeLayer()

    // MARK: - State

    private(set) var metrics: Metrics?

    /// Current morph progress 0…1. Setting directly snaps without animation
    /// (also cancels any in-flight `animateProgress(...)`). The animation
    /// API is `animateProgress(to:duration:...)`.
    var progress: CGFloat {
        get { progressValue }
        set {
            cancelDisplayLink()
            progressValue = newValue
            updateForProgress(newValue)
        }
    }

    // MARK: - Private state

    private var progressValue: CGFloat = 0

    private var displayLink: CADisplayLink?
    private var animStart: CFTimeInterval = 0
    private var animDuration: TimeInterval = 0
    private var animFrom: CGFloat = 0
    private var animTo: CGFloat = 0
    private var animDamping: CGFloat = 0.78
    private var animStep: ((CGFloat) -> Void)?
    private var animCompletion: ((Bool) -> Void)?

    // Stored shadow constants (scaled per-progress).
    private static let collapsedShadowRadius: CGFloat = 12.0
    private static let expandedShadowRadius: CGFloat = 28.0
    private static let collapsedShadowOpacity: Float = 0.10
    private static let expandedShadowOpacity: Float = 0.16
    private static let shadowOffset = CGSize(width: 0, height: 6)

    // MARK: - Init

    init(effect: UIVisualEffect) {
        self.glass = UIVisualEffectView(effect: effect)
        super.init(frame: .zero)

        // Host itself is transparent and unmasked so the drop shadow below
        // the glass is visible. Glass inside clips to its own rounded
        // corners.
        backgroundColor = .clear
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = Self.shadowOffset
        layer.shadowRadius = Self.collapsedShadowRadius
        layer.shadowOpacity = Self.collapsedShadowOpacity

        // Clip container sits between `self` and the glass. Its mask
        // carries the droplet path; the glass fills it fully and
        // inherits the clipping visually.
        clipContainer.backgroundColor = .clear
        clipContainer.layer.mask = clipMaskLayer
        addSubview(clipContainer)

        glass.clipsToBounds = true  // belt-and-braces even though mask handles silhouette
        if #available(iOS 13.0, *) {
            glass.layer.cornerCurve = .continuous
        }
        clipContainer.addSubview(glass)

        sourceContent.backgroundColor = .clear
        sourceContent.isUserInteractionEnabled = false
        glass.contentView.addSubview(sourceContent)

        destinationContent.backgroundColor = .clear
        destinationContent.isUserInteractionEnabled = true
        glass.contentView.addSubview(destinationContent)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Configuration

    /// Set the collapsed (source button) and expanded (menu) rects + corner
    /// radii. Once configured, the host's visual state at any `progress`
    /// value is well-defined. Safe to call repeatedly; the next
    /// `updateForProgress(...)` picks up the new metrics.
    func configure(metrics: Metrics) {
        self.metrics = metrics
        // Content containers stay at their own full size throughout the
        // morph — the glass host clips them to its (changing) bounds. The
        // containers sit at the top-left (origin .zero) so the button
        // snapshot lines up with the source rect, and the menu sits at the
        // top of the expanded rect which is where the actions view is
        // anchored.
        sourceContent.frame = CGRect(origin: .zero, size: metrics.collapsedFrame.size)
        destinationContent.frame = CGRect(origin: .zero, size: metrics.expandedFrame.size)
        updateForProgress(progressValue)
    }

    // MARK: - Animation API

    /// Drive `progress` from the current value to `target` over `duration`
    /// using a damped-spring easing. `step` fires on every display-link
    /// tick with the current progress value — useful for side-effect
    /// animators (SDF filter layouts, dim overlays) that need to follow
    /// the morph.
    func animateProgress(
        to target: CGFloat,
        duration: TimeInterval,
        damping: CGFloat = 0.78,
        step: ((CGFloat) -> Void)? = nil,
        completion: ((Bool) -> Void)? = nil
    ) {
        // Cancel any in-flight anim — fire previous completion with false
        // so callers can distinguish "preempted" from "finished".
        let previousCompletion = animCompletion
        cancelDisplayLink()
        previousCompletion?(false)

        animStart = CACurrentMediaTime()
        animDuration = duration
        animFrom = progressValue
        animTo = target
        animDamping = damping
        animStep = step
        animCompletion = completion

        // Fire the initial step synchronously so callers can install their
        // side-effect animations in the same runloop turn the user's touch
        // lands in (visually feels more responsive than waiting for the
        // first display-link tick).
        step?(progressValue)

        if duration <= 0 {
            progressValue = target
            updateForProgress(target)
            step?(target)
            let c = animCompletion
            animCompletion = nil
            c?(true)
            return
        }

        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Stop any running animation without firing completion. Leaves
    /// `progress` at its current interpolated value.
    func cancelAnimation() {
        cancelDisplayLink()
    }

    private func cancelDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        animStep = nil
    }

    @objc private func handleDisplayLink(_ link: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - animStart
        let tRaw = CGFloat(elapsed / animDuration)
        let tClamped = max(0, min(1, tRaw))
        let eased = Self.springProgress(tClamped, damping: animDamping)
        let value = animFrom + (animTo - animFrom) * eased
        progressValue = value
        updateForProgress(value)
        animStep?(value)
        if tRaw >= 1 {
            link.invalidate()
            displayLink = nil
            let c = animCompletion
            animCompletion = nil
            animStep = nil
            c?(true)
        }
    }

    // MARK: - Progress → visuals

    /// The heart of the morph: every visual parameter (geometry, shadow,
    /// source fade, destination fade + slide, blob bulge) is computed as
    /// a pure function of `t ∈ [0, 1]`. No separate timers, no concurrent
    /// `UIView.animate` calls fighting for the same property.
    private func updateForProgress(_ t: CGFloat) {
        guard let metrics else { return }

        // Clamped progress drives the axis-aligned lerp targets. The
        // blob deformation is layered ON TOP of this and zeroes out at
        // the endpoints, so the start/end shapes remain exactly the
        // pristine source and menu rects.
        let gt = max(0, min(1, t))
        let lerpFrame = Self.lerpRect(metrics.collapsedFrame, metrics.expandedFrame, gt)
        let baseCorner = Self.lerp(metrics.collapsedCornerRadius, metrics.expandedCornerRadius, gt)

        // `blob` peaks at the midpoint of the intermediate phase (~t=0.26)
        // and decays to 0 at the phase edges. It's what sells the liquid
        // feel — the shape briefly swells outward, the corners go
        // asymmetric, THEN settles into the clean menu rect. The window
        // is deliberately placed BETWEEN the source fade-out (≤0.16) and
        // the destination fade-in (≥0.34) so there's a pure-blob slice
        // from ~0.20–0.30 with NO readable content on either side —
        // that's the frame the user sees as "a glass droplet".
        let blob = Self.sinWindow(t, 0.06, 0.46)

        // Blob pulse: ADDITIVE pixel delta on top of the lerped size.
        // Kept small enough to stay monotonic (shape only grows on
        // open, only shrinks on close — never reverses direction).
        //
        // Asymmetric axes for the droplet effect: tiny horizontal
        // bulge, LARGE vertical bulge. The shape reads as stretching
        // downward mid-morph (a liquid being pulled down by gravity),
        // not as an isotropic swelling. Caps scale off the total
        // delta between collapsed and expanded so small morphs get
        // small bulges and vice versa.
        let widthDelta = metrics.expandedFrame.width - metrics.collapsedFrame.width
        let heightDelta = metrics.expandedFrame.height - metrics.collapsedFrame.height
        let widthBulge = blob * min(6, max(0, widthDelta) * 0.05)   // barely noticeable
        let heightBulge = blob * min(36, max(0, heightDelta) * 0.18) // the droplet "drip"
        let bulgedSize = CGSize(
            width: lerpFrame.width + widthBulge,
            height: lerpFrame.height + heightBulge
        )
        // Anchor the bulge to the TOP edge of the lerped frame, not to
        // its centre. The shape then extends DOWNWARD during the blob
        // phase — a liquid being pulled down by gravity. Centering
        // would balloon the bulge upward AND downward symmetrically,
        // which reads as an isotropic swell rather than a drop.
        let bulgedFrame = CGRect(
            x: lerpFrame.midX - bulgedSize.width / 2,
            y: lerpFrame.minY,
            width: bulgedSize.width,
            height: bulgedSize.height
        )

        // Corner radii: asymmetric during the blob phase for a real
        // droplet silhouette — top narrower (the "neck"), bottom
        // rounder (the "belly"). Both converge back to `baseCorner`
        // at t=0 and t=1, so the endpoints are the pristine collapsed
        // / expanded rects.
        //
        // Applied via `clipContainer.layer.mask` (a CAShapeLayer),
        // NOT via `glass.layer.cornerRadius`. A scalar radius can't
        // express asymmetric corners, and the earlier mask-on-VEF
        // attempt failed because UIVisualEffectView's backdrop
        // bypasses its own layer mask — but placing the mask on a
        // parent UIView works because the parent's compositing does
        // respect the mask.
        let topNeck = blob * 0.18
        let bottomBelly = blob * 0.38
        let topCornerRadius = max(0, baseCorner * (1 - topNeck))
        let bottomCornerRadius = baseCorner * (1 + bottomBelly)

        // Material "thickens" with size — per the rec, Liquid Glass
        // behaves like a heavier material when larger. An extra kick
        // during the blob phase makes the drop feel three-dimensional.
        let shadowBulge = blob * 0.35
        let shadowRadius = Self.lerp(Self.collapsedShadowRadius, Self.expandedShadowRadius, gt)
            + Self.expandedShadowRadius * shadowBulge
        let shadowOpacity = Float(Self.lerp(
            CGFloat(Self.collapsedShadowOpacity),
            CGFloat(Self.expandedShadowOpacity),
            gt
        ) * (1 + shadowBulge * 0.4))

        // Source content (button snapshot): fades out on 0.02…0.14 with a
        // slight scale-down, so the label visibly loses structure BEFORE
        // the shape is done moving. Per the rec this timing is the single
        // most important choreography detail — it's what turns "popover
        // appears over button" into "button dissolves into menu".
        let sourceFadeOut = Self.smoothstep(0.02, 0.14, t)
        let sourceAlpha = max(0, 1 - sourceFadeOut)
        let sourceScale = 0.96 + 0.04 * (1 - sourceFadeOut)

        // Destination content (menu rows): late fade-in on 0.38…0.54, with
        // an 8pt translateY slide. The gap between source-out (≤0.14) and
        // destination-in (≥0.38) is a full ~0.24 slice where ONLY the
        // blob is visible — no button label, no menu rows. That's the
        // "pure glass droplet" phase the user asked for.
        let destFadeIn = Self.smoothstep(0.38, 0.54, t)
        let destAlpha = destFadeIn
        let destTranslateY = (1 - destFadeIn) * 8

        // Batch all implicit-animation-prone writes inside one disabled
        // transaction. Per-frame property changes on CALayer default to
        // the 0.25s fade/position animation, which would stutter on top
        // of our display-link driver.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        self.frame = bulgedFrame
        clipContainer.frame = bounds
        glass.frame = clipContainer.bounds

        // Build the asymmetric rounded-rect mask path for this tick.
        // Applied to clipContainer so it clips the glass inside.
        let path = Self.makeMorphPath(
            in: clipContainer.bounds,
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
        clipMaskLayer.frame = clipContainer.bounds
        clipMaskLayer.path = path

        // Shadow uses the same path so the silhouette under the glass
        // matches what's visible.
        layer.shadowPath = path
        layer.shadowRadius = shadowRadius
        layer.shadowOpacity = shadowOpacity

        sourceContent.alpha = sourceAlpha
        sourceContent.transform = CGAffineTransform(scaleX: sourceScale, y: sourceScale)

        destinationContent.alpha = destAlpha
        destinationContent.transform = CGAffineTransform(translationX: 0, y: destTranslateY)

        CATransaction.commit()
    }

    // MARK: - Blob shape builders

    /// Sinusoidal bump: `0` at `t ≤ a` and `t ≥ b`, peak `1` at the mid-
    /// point of `[a, b]`. Used to drive the blob deformation — the shape
    /// is only distorted during the intermediate transition phase, not at
    /// the start or end where the geometry has to match the clean source
    /// / menu rects.
    private static func sinWindow(_ t: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        guard t > a, t < b, b > a else { return 0 }
        let normalized = (t - a) / (b - a)       // 0…1 across the window
        return sin(normalized * .pi)             // 0 → 1 (at 0.5) → 0
    }

    /// Rounded-rect path with independent top and bottom corner radii.
    /// Used as the `clipContainer.layer.mask` path + `layer.shadowPath`
    /// on each display-link tick; gives the morph its droplet
    /// silhouette during the blob phase. At t=0 / t=1 the caller
    /// passes the same value for both radii, so endpoints are clean
    /// uniform rounded rects.
    private static func makeMorphPath(
        in rect: CGRect,
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat
    ) -> CGPath {
        // Clamp to half-side — otherwise neighbouring arc quadrants
        // overlap and produce a degenerate path.
        let halfW = rect.width * 0.5
        let halfH = rect.height * 0.5
        let topR = max(0, min(min(topCornerRadius, halfW), halfH))
        let bottomR = max(0, min(min(bottomCornerRadius, halfW), halfH))

        let path = UIBezierPath()
        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY

        path.move(to: CGPoint(x: minX + topR, y: minY))
        path.addLine(to: CGPoint(x: maxX - topR, y: minY))
        path.addArc(
            withCenter: CGPoint(x: maxX - topR, y: minY + topR),
            radius: topR,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: maxX, y: maxY - bottomR))
        path.addArc(
            withCenter: CGPoint(x: maxX - bottomR, y: maxY - bottomR),
            radius: bottomR,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: minX + bottomR, y: maxY))
        path.addArc(
            withCenter: CGPoint(x: minX + bottomR, y: maxY - bottomR),
            radius: bottomR,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: minX, y: minY + topR))
        path.addArc(
            withCenter: CGPoint(x: minX + topR, y: minY + topR),
            radius: topR,
            startAngle: .pi,
            endAngle: 3 * .pi / 2,
            clockwise: true
        )
        path.close()
        return path.cgPath
    }

    // MARK: - Easing helpers

    /// Damped second-order spring response. `damping` is interpreted as
    /// the canonical damping RATIO (ζ):
    ///   - `< 1` underdamped: oscillates, amplitude decays. Smaller = bouncier.
    ///   - `= 1` critically damped: monotonic approach, NO overshoot.
    ///   - `> 1` overdamped: slower monotonic approach.
    ///
    /// An earlier version used `exp(-damping * t) * cos(2t)` which always
    /// oscillated — `damping` was a decay rate, not a damping ratio, so
    /// no value of it could suppress the bounce. Users consistently
    /// reported "spring too strong" no matter how high the damping went.
    /// The form below is the proper analytical response, so passing
    /// `damping = 1.0` truly produces zero overshoot.
    ///
    /// `omega` (natural angular frequency) is fixed at a value that
    /// makes the curve reach ~98-99% by t=1.0 across typical damping
    /// ratios — keeps the settling feel responsive without requiring a
    /// per-call parameter.
    private static func springProgress(_ t: CGFloat, damping: CGFloat) -> CGFloat {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }

        let omega: CGFloat = 6.5
        let zeta = max(0.01, damping)
        let wt = omega * t

        if zeta < 1 {
            // Underdamped — closed-form cosine/sine envelope decaying
            // exponentially. Small overshoot, oscillates.
            let omegaD = omega * sqrt(1 - zeta * zeta)
            let decay = exp(-zeta * wt)
            let c = cos(omegaD * t)
            let s = sin(omegaD * t)
            let response = decay * (c + (zeta * omega / omegaD) * s)
            return 1 - response
        } else if zeta > 1 {
            // Overdamped — sum of two decaying exponentials, slow smooth
            // approach, no oscillation. Useful when the user wants the
            // absolute softest landing.
            let r = sqrt(zeta * zeta - 1)
            let a = -zeta + r
            let b = -zeta - r
            let A = b / (b - a)
            let B = -a / (b - a)
            let response = A * exp(a * wt) + B * exp(b * wt)
            return 1 - response
        } else {
            // Critically damped — (1 + ωt) exp(-ωt). Single monotonic
            // curve, zero overshoot, fastest possible settle without
            // oscillation. This is the default "soft spring" feel.
            return 1 - (1 + wt) * exp(-wt)
        }
    }

    private static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x <= edge0 ? 0 : 1 }
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        return a + (b - a) * t
    }

    private static func lerpRect(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        return CGRect(
            x: lerp(a.minX, b.minX, t),
            y: lerp(a.minY, b.minY, t),
            width: lerp(a.width, b.width, t),
            height: lerp(a.height, b.height, t)
        )
    }
}
