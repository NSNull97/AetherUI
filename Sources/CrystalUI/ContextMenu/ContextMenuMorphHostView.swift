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
            phaseValue = max(0, min(1, newValue))
            updateForProgress(surfaceProgress: newValue, phaseProgress: phaseValue)
        }
    }

    // MARK: - Private state

    private var progressValue: CGFloat = 0
    private var phaseValue: CGFloat = 0

    private var displayLink: CADisplayLink?
    private var animStart: CFTimeInterval = 0
    private var animDuration: TimeInterval = 0
    private var animFrom: CGFloat = 0
    private var animTo: CGFloat = 0
    private var animDamping: CGFloat = 0.78
    private var animStep: ((CGFloat) -> Void)?
    private var animCompletion: ((Bool) -> Void)?
    private let shapeMaskLayer = CAShapeLayer()

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

        // Top anchor (y=0). X-anchor is resolved per-presentation in
        // `configure(metrics:)` based on which edge (left / center /
        // right) the menu shares with the source button. That way the
        // spring scale transform and frame lerp pivot around the edge
        // that's visually anchored to the source — a right-side
        // button's menu unfolds leftward from the source's right
        // edge, a left-side button's menu unfolds rightward from its
        // left edge, a centered button expands symmetrically.
        // Default is top-center until metrics are supplied.
        layer.anchorPoint = CGPoint(x: 0.5, y: 0)

        // Host itself is transparent and unmasked so the drop shadow below
        // the glass is visible. Glass inside clips to its own rounded
        // corners.
        backgroundColor = .clear
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = Self.shadowOffset
        layer.shadowRadius = Self.collapsedShadowRadius
        layer.shadowOpacity = Self.collapsedShadowOpacity

        glass.clipsToBounds = false
        if #available(iOS 13.0, *) {
            glass.layer.cornerCurve = .continuous
        }
        shapeMaskLayer.fillColor = UIColor.black.cgColor
        glass.layer.mask = shapeMaskLayer
        addSubview(glass)

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

    /// Horizontal anchor resolved from source ↔ menu alignment. Used
    /// both for the CALayer `anchorPoint.x` (so transform scale pivots
    /// from the right edge) and for computing `layer.position.x`
    /// during animation. Reset on every `configure(metrics:)` call.
    private var xAnchor: CGFloat = 0.5

    /// Set the collapsed (source button) and expanded (menu) rects + corner
    /// radii. Once configured, the host's visual state at any `progress`
    /// value is well-defined. Safe to call repeatedly; the next
    /// `updateForProgress(...)` picks up the new metrics.
    func configure(metrics: Metrics) {
        self.metrics = metrics

        // Pick the horizontal anchor by matching which horizontal edge
        // source and menu share:
        //   - Same left edge → anchor x = 0 (shape grows rightward
        //     from the shared left edge)
        //   - Same right edge → anchor x = 1 (shape grows leftward
        //     from the shared right edge)
        //   - Neither → fall back to center so scale at least pivots
        //     from the midpoint.
        // Tolerance of 1pt handles rounding differences between
        // caller-computed source / menu rects.
        let srcMinX = metrics.collapsedFrame.minX
        let srcMaxX = metrics.collapsedFrame.maxX
        let expMinX = metrics.expandedFrame.minX
        let expMaxX = metrics.expandedFrame.maxX
        if abs(srcMinX - expMinX) <= 1.0 {
            xAnchor = 0.0
        } else if abs(srcMaxX - expMaxX) <= 1.0 {
            xAnchor = 1.0
        } else {
            xAnchor = 0.5
        }
        layer.anchorPoint = CGPoint(x: xAnchor, y: 0)

        // Content containers stay at their own full size throughout the
        // morph — the glass host clips them to its (changing) bounds. The
        // containers sit at the top-left (origin .zero) so the button
        // snapshot lines up with the source rect, and the menu sits at the
        // top of the expanded rect which is where the actions view is
        // anchored.
        sourceContent.frame = CGRect(origin: .zero, size: metrics.collapsedFrame.size)
        destinationContent.frame = CGRect(origin: .zero, size: metrics.expandedFrame.size)
        updateForProgress(surfaceProgress: progressValue, phaseProgress: phaseValue)
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
            phaseValue = max(0, min(1, target))
            updateForProgress(surfaceProgress: target, phaseProgress: phaseValue)
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
        let phaseFrom = max(0, min(1, animFrom))
        let phaseTo = max(0, min(1, animTo))
        let phase = phaseFrom + (phaseTo - phaseFrom) * tClamped
        progressValue = value
        phaseValue = phase
        updateForProgress(surfaceProgress: value, phaseProgress: phase)
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
    private func updateForProgress(surfaceProgress: CGFloat, phaseProgress: CGFloat) {
        guard let metrics else { return }

        // Frame lerp uses CLAMPED progress. An earlier revision passed
        // raw (unclamped) progress through so the spring overshoot
        // extrapolated the frame past the endpoints — but the
        // extrapolation is per-axis, scaled by each axis's delta. For a
        // button→menu morph with height delta (~290pt) much bigger than
        // width delta (~80pt), 12% overshoot meant +35pt height /
        // +10pt width — an isotropic spring would bulge ~proportional
        // in both dimensions, but our frame-lerp version gave a tall
        // stretchy shape ("squish") that didn't read as spring.
        //
        // Now: frame is the pristine lerp 0…1. Spring overshoot is
        // applied SEPARATELY as an isotropic `transform.scale` below,
        // which expands / shrinks equally in both dimensions — a real
        // spring wobble. Combined with the top-anchor point (set in
        // init), the bounce expands downward + outward from the source
        // top edge, matching the menu's natural unfold direction.
        let gt = max(0, min(1, surfaceProgress))
        let phaseT = max(0, min(1, phaseProgress))
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
        let blob = Self.sinWindow(phaseT, 0.10, 0.58)

        // Blob pulse: small symmetric ADDITIVE delta on top of the
        // lerped size, centered on the lerped frame. Kept small and
        // symmetric to stay monotonic (shape only grows on open, only
        // shrinks on close) and because an earlier asymmetric
        // droplet-extension attempt read as "weird" rather than
        // liquid — plain uniform puff is less showy but visually
        // cleaner.
        let widthBulge = blob * min(18, lerpFrame.width * 0.10)
        let heightBulge = blob * min(22, lerpFrame.height * 0.12)
        let bulgedSize = CGSize(
            width: lerpFrame.width + widthBulge,
            height: lerpFrame.height + heightBulge
        )
        let bulgedFrame = CGRect(
            x: lerpFrame.midX - bulgedSize.width / 2,
            y: lerpFrame.midY - bulgedSize.height / 2,
            width: bulgedSize.width,
            height: bulgedSize.height
        )

        // Uniform corner-radius pulse during the blob phase — the
        // shape reads slightly chubbier at the midpoint without any
        // of the asymmetric / asymmetric-mask complexity (that needed
        // a parent-UIView mask to clip the VEF's backdrop, which
        // added moving parts for a visual gain the user preferred to
        // drop).
        let cornerPulse = blob * baseCorner * 0.18
        let cornerRadius = baseCorner + cornerPulse

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
        let sourceFadeOut = Self.smoothstep(0.03, 0.20, phaseT)
        let sourceAlpha = max(0, 1 - sourceFadeOut)
        let sourceScale = 0.95 + 0.05 * (1 - sourceFadeOut)

        // Destination content (menu rows): late fade-in on 0.38…0.54, with
        // an 8pt translateY slide. The gap between source-out (≤0.14) and
        // destination-in (≥0.38) is a full ~0.24 slice where ONLY the
        // blob is visible — no button label, no menu rows. That's the
        // "pure glass droplet" phase the user asked for.
        let destFadeIn = Self.smoothstep(0.48, 0.74, phaseT)
        let destAlpha = destFadeIn
        let destTranslateY = (1 - destFadeIn) * 10

        // Spring overshoot as an isotropic scale transform around the
        // top-anchor. `t` can exceed 1 (open overshoot) or go below 0
        // (close undershoot) — the corresponding `springExcess` feeds
        // the scale: peak open = +12% size, peak close = −12% size.
        // Both directions scale uniformly in x + y, centered at the
        // view's top edge (anchorPoint set in init), so the bounce
        // reads as a true spring wobble instead of a one-axis squish.
        let springExcess: CGFloat
        if surfaceProgress > 1 {
            springExcess = surfaceProgress - 1
        } else if surfaceProgress < 0 {
            springExcess = surfaceProgress
        } else {
            springExcess = 0
        }
        let springScale = 1 + springExcess

        // Batch all implicit-animation-prone writes inside one disabled
        // transaction. Per-frame property changes on CALayer default to
        // the 0.25s fade/position animation, which would stutter on top
        // of our display-link driver.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Bounds + position directly (avoids `frame` getter/setter
        // gymnastics with the non-default anchorPoint). `position` is
        // the anchor-point location in the parent:
        //   anchor x = 0.0 → position.x = bulgedFrame.minX  (left edge)
        //   anchor x = 1.0 → position.x = bulgedFrame.maxX  (right edge)
        //   anchor x = 0.5 → position.x = bulgedFrame.midX  (centre)
        // `xAnchor` was resolved in `configure(metrics:)` and applied
        // to `layer.anchorPoint`; using the matching formula here
        // keeps the visible frame aligned to bulgedFrame regardless
        // of which edge the shape is pivoting from.
        let anchorPositionX = bulgedFrame.minX + bulgedFrame.width * xAnchor
        self.bounds = CGRect(origin: .zero, size: bulgedFrame.size)
        self.layer.position = CGPoint(x: anchorPositionX, y: bulgedFrame.minY)
        self.transform = CGAffineTransform(scaleX: springScale, y: springScale)
        glass.frame = bounds
        glass.layer.cornerRadius = cornerRadius

        let shapePath = Self.makeMorphPath(
            in: bounds,
            cornerRadius: cornerRadius,
            blob: blob,
            xAnchor: xAnchor
        )
        shapeMaskLayer.frame = bounds
        shapeMaskLayer.path = shapePath

        // Explicit shadowPath derived from the rounded rect stays in
        // sync with the visible silhouette each tick.
        layer.shadowPath = shapePath
        layer.shadowRadius = shadowRadius
        layer.shadowOpacity = shadowOpacity

        sourceContent.alpha = sourceAlpha
        sourceContent.transform = CGAffineTransform(scaleX: sourceScale, y: sourceScale)

        destinationContent.alpha = destAlpha
        destinationContent.transform = CGAffineTransform(translationX: 0, y: destTranslateY)

        CATransaction.commit()
    }

    // MARK: - Blob shape builders

    /// Rounded rect at rest; during the blob window the top edge pinches
    /// toward the source anchor and the lower half swells into a drop. This
    /// keeps the shared edge visually attached to the source button while
    /// still resolving to a clean rounded menu container at the endpoints.
    private static func makeMorphPath(
        in rect: CGRect,
        cornerRadius: CGFloat,
        blob: CGFloat,
        xAnchor: CGFloat
    ) -> CGPath {
        guard rect.width > 0, rect.height > 0 else {
            return UIBezierPath(rect: rect).cgPath
        }
        guard blob > 0.001 else {
            return UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath
        }

        let width = rect.width
        let height = rect.height
        let pinch = min(width * 0.34, 44.0) * blob
        let leftPinch = pinch * xAnchor
        let rightPinch = pinch * (1.0 - xAnchor)
        let topLeftX = rect.minX + leftPinch
        let topRightX = rect.maxX - rightPinch
        let topRadius = min(cornerRadius * (1.0 - blob * 0.34), (topRightX - topLeftX) * 0.5)
        let bottomRadius = min(cornerRadius * (1.0 + blob * 0.22), width * 0.5 - 1.0)
        let neckY = rect.minY + topRadius + height * 0.03 * blob
        let bodyBottomY = rect.maxY - max(1.0, cornerRadius * 0.14 * blob)
        let centerShift = (xAnchor - 0.5) * pinch * 0.46

        let path = UIBezierPath()
        path.move(to: CGPoint(x: topLeftX + topRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: topRightX - topRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: topRightX, y: neckY),
            controlPoint: CGPoint(x: topRightX, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX - bottomRadius, y: bodyBottomY),
            controlPoint1: CGPoint(
                x: min(rect.maxX, topRightX + rightPinch * 0.12),
                y: rect.minY + max(14.0, height * 0.22)
            ),
            controlPoint2: CGPoint(
                x: rect.maxX + width * 0.02 * blob,
                y: rect.minY + height * 0.64
            )
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + bottomRadius, y: bodyBottomY),
            controlPoint1: CGPoint(
                x: rect.minX + width * 0.82 + centerShift,
                y: rect.maxY + height * 0.04 * blob
            ),
            controlPoint2: CGPoint(
                x: rect.minX + width * 0.18 + centerShift,
                y: rect.maxY + height * 0.04 * blob
            )
        )
        path.addCurve(
            to: CGPoint(x: topLeftX, y: neckY),
            controlPoint1: CGPoint(
                x: rect.minX - width * 0.02 * blob,
                y: rect.minY + height * 0.64
            ),
            controlPoint2: CGPoint(
                x: max(rect.minX, topLeftX - leftPinch * 0.12),
                y: rect.minY + max(14.0, height * 0.22)
            )
        )
        path.addQuadCurve(
            to: CGPoint(x: topLeftX + topRadius, y: rect.minY),
            controlPoint: CGPoint(x: topLeftX, y: rect.minY)
        )
        path.close()
        return path.cgPath
    }

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

    // MARK: - Easing helpers

    /// Cubic ease-out + half-sine spring bump. The bump is the key:
    /// it's an ADDITIVE pulse that activates only in the last ~45% of
    /// the animation, so the user sees the shape ARRIVE at the target
    /// via the ease-out alone, THEN a visible kick-up-and-settle
    /// happens at the end. Previous bezier-only tunings produced a
    /// monotonic curve that read as "smooth with a slight hump in the
    /// middle" — the bump needed to be a clearly separate event.
    ///
    /// Timeline (damping = 0.50, duration 0.25s):
    ///   0.00  Y=0.00   (start)
    ///   0.10  Y=0.27   (fast rise)
    ///   0.30  Y=0.66
    ///   0.55  Y=0.91   (bump window begins; curve ≈ ease-out value)
    ///   0.70  Y=1.07   (ease-out near 1 + bump adding 8%)
    ///   0.775 Y=1.11   (PEAK — bump at its sin(π/2)=1 maximum)
    ///   0.85  Y=1.08
    ///   0.95  Y=1.03
    ///   1.00  Y=1.00   (clean end; bump returns to 0)
    ///
    /// The pulse shape — sin(π·localT) — is 0 at both ends of its
    /// window and peaks at its midpoint, so y(1) is exactly 1.00 and
    /// y is value-continuous at t=0.55. Velocity has a small kink at
    /// t=0.55 where the bump starts — but that kink is the POINT,
    /// it's what makes the bump read as a distinct spring rather than
    /// blending invisibly into the ease-out.
    ///
    /// `damping`: 0 = big bump (amplitude 0.25 → ~18% peak), 1 = flat
    /// ease-out with no bump. Controller passes 0.50 for the standard
    /// "light spring" feel.
    private static func springProgress(_ t: CGFloat, damping: CGFloat) -> CGFloat {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }

        // THREE phases, rise compressed into the first third so the
        // pulse dominates the remaining ~58% of the duration — makes
        // the spring feel slower and more expansive relative to the
        // snap-up phase.
        //
        //   Rise  (0…0.34)   cubic ease-out 0 → 1.0
        //   Hold  (0.34…0.42) plateau at 1.0 (brief stop between rise
        //                      and pulse so the spring reads distinct)
        //   Pulse (0.42…1.0)  half-sine around 1.0, peak at t=0.71
        //
        // At 0.26s duration:
        //   rise   88ms
        //   hold   21ms
        //   pulse  151ms  (peak at t≈185ms)
        //
        // `damping`: 0 → big pulse (amp 0.40), 1 → no pulse. 0.50 →
        // 20% peak overshoot.
        let riseEnd: CGFloat = 0.34
        let holdEnd: CGFloat = 0.42

        if t < riseEnd {
            // ease-in-out quadratic: slow start, accelerating through
            // the middle, decelerating into the hold. Unlike cubic
            // ease-out (velocity=3 at t=0, then decreasing) this gives
            // the shape a gentle onset — important for right-side
            // buttons whose left edge would otherwise "whip" leftward
            // at the first couple of frames.
            let p = t / riseEnd
            if p < 0.5 {
                return 2 * p * p
            } else {
                let inv = 1 - p
                return 1 - 2 * inv * inv
            }
        }

        if t < holdEnd {
            return 1.0
        }

        // Pulse phase spans the whole back half so the spring has
        // the full second-half duration to rise, peak, and settle
        // back to 1.0 — slower feel per user's ask.
        let bounce = max(0, 1 - damping)
        let amplitude = bounce * 0.2
        let localT = (t - holdEnd) / (1 - holdEnd)
        let pulse = sin(localT * .pi)
        return 1.0 + amplitude * pulse
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
