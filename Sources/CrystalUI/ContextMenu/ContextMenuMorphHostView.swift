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

        glass.clipsToBounds = true
        if #available(iOS 13.0, *) {
            glass.layer.cornerCurve = .continuous
        }
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
    /// source fade, destination fade + slide) is computed as a pure
    /// function of `t ∈ [0, 1]`. No separate timers, no concurrent
    /// `UIView.animate` calls fighting for the same property.
    private func updateForProgress(_ t: CGFloat) {
        guard let metrics else { return }

        // Geometry uses the clamped progress so the frame never overshoots
        // the expanded rect even if the spring-eased value momentarily
        // exceeds 1.0 — overshoot is for material (shadow / content
        // choreography) where it adds life, not for the hard bounds.
        let gt = max(0, min(1, t))
        let targetFrame = Self.lerpRect(metrics.collapsedFrame, metrics.expandedFrame, gt)
        let cornerRadius = Self.lerp(metrics.collapsedCornerRadius, metrics.expandedCornerRadius, gt)

        // Material "thickens" with size — per the rec, Liquid Glass
        // behaves like a heavier material when larger. Shadow radius and
        // opacity grow with the morph, selling the depth change.
        let shadowRadius = Self.lerp(Self.collapsedShadowRadius, Self.expandedShadowRadius, gt)
        let shadowOpacity = Float(Self.lerp(CGFloat(Self.collapsedShadowOpacity), CGFloat(Self.expandedShadowOpacity), gt))

        // Source content (button snapshot): fades out on 0.02…0.16 with a
        // slight scale-down, so the label visibly loses structure BEFORE
        // the shape is done moving. Per the rec this timing is the single
        // most important choreography detail — it's what turns "popover
        // appears over button" into "button dissolves into menu".
        let sourceFadeOut = Self.smoothstep(0.02, 0.16, t)
        let sourceAlpha = max(0, 1 - sourceFadeOut)
        let sourceScale = 0.96 + 0.04 * (1 - sourceFadeOut)

        // Destination content (menu rows): late fade-in on 0.28…0.42, with
        // an 8pt translateY slide. The gap between source-out (≤0.16) and
        // destination-in (≥0.28) is what creates the "blob" stage where
        // the surface is just glass — no readable content on either side.
        let destFadeIn = Self.smoothstep(0.28, 0.42, t)
        let destAlpha = destFadeIn
        let destTranslateY = (1 - destFadeIn) * 8

        // Batch all implicit-animation-prone writes inside one disabled
        // transaction. Per-frame property changes on CALayer default to
        // the 0.25s fade/position animation, which would stutter on top
        // of our display-link driver.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        self.frame = targetFrame
        glass.frame = bounds
        glass.layer.cornerRadius = cornerRadius

        // Explicit shadowPath means CA doesn't trace the alpha of the
        // subtree on every frame (expensive for blurred glass) — we feed
        // the exact rounded-rect silhouette each tick.
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        layer.shadowRadius = shadowRadius
        layer.shadowOpacity = shadowOpacity

        sourceContent.alpha = sourceAlpha
        sourceContent.transform = CGAffineTransform(scaleX: sourceScale, y: sourceScale)

        destinationContent.alpha = destAlpha
        destinationContent.transform = CGAffineTransform(translationX: 0, y: destTranslateY)

        CATransaction.commit()
    }

    // MARK: - Easing helpers

    /// Damped-sinusoidal approximation of `UISpringTimingParameters` —
    /// sweeps 0→1 with a slight overshoot that settles by t≈1.0. Not
    /// mathematically identical to UIKit's native spring, but visually
    /// indistinguishable at the ~0.5s durations used by the morph. Built
    /// in-line instead of via `UIViewPropertyAnimator` so we can read
    /// progress from a display link without round-tripping through an
    /// off-screen UIView's presentation layer.
    private static func springProgress(_ t: CGFloat, damping: CGFloat) -> CGFloat {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        let scaled = t * 4.5
        let decay = exp(-damping * scaled)
        let osc = cos(2.0 * scaled)
        let s = 1 - decay * osc
        // Keep the overshoot modest — too much and the content
        // choreography visibly re-wiggles at the tail.
        return min(1.12, max(-0.04, s))
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
