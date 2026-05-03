import UIKit

public struct AetherSkeletonTheme: Equatable {
    /// Base fill color of the placeholder shape.
    public let baseColor: UIColor
    /// Highlight color that sweeps across during shimmer.
    public let highlightColor: UIColor
    /// Cycle length (one full sweep). Defaults to 1.3s.
    public let shimmerDuration: TimeInterval
    /// Horizontal fraction of the view the highlight gradient occupies.
    public let shimmerWidthFraction: CGFloat

    public init(
        baseColor: UIColor,
        highlightColor: UIColor,
        shimmerDuration: TimeInterval = 1.3,
        shimmerWidthFraction: CGFloat = 0.45
    ) {
        self.baseColor = baseColor
        self.highlightColor = highlightColor
        self.shimmerDuration = shimmerDuration
        self.shimmerWidthFraction = shimmerWidthFraction
    }

    public static let light = AetherSkeletonTheme(
        baseColor: UIColor(white: 0.9, alpha: 1.0),
        highlightColor: UIColor(white: 0.97, alpha: 1.0)
    )

    public static let dark = AetherSkeletonTheme(
        baseColor: UIColor(white: 0.18, alpha: 1.0),
        highlightColor: UIColor(white: 0.32, alpha: 1.0)
    )

    /// Adapts to the current `UITraitCollection.userInterfaceStyle`.
    /// Use this when you want the skeleton to follow the system theme
    /// without the caller having to listen for trait changes themselves
    /// — `AetherSkeletonView.traitCollectionDidChange` re-resolves the
    /// underlying CGColors when iOS flips light↔dark.
    public static let system = AetherSkeletonTheme(
        baseColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.18, alpha: 1.0)
                : UIColor(white: 0.9, alpha: 1.0)
        },
        highlightColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.32, alpha: 1.0)
                : UIColor(white: 0.97, alpha: 1.0)
        }
    )
}

/// Base class for a single shimmer-animated placeholder rectangle.
/// Cornering + mask configuration is delegated to subclasses or applied
/// directly by the caller via `layer.cornerRadius` / `layer.mask`.
open class AetherSkeletonView: UIView {
    public var theme: AetherSkeletonTheme {
        didSet {
            applyTheme()
            // Theme can change `shimmerDuration` — that's a parameter of
            // the animation itself, so we MUST rebuild it. `force: true`
            // skips the "same width, same animation" early-out.
            restartShimmerIfNeeded(force: true)
        }
    }

    /// Pause the shimmer (e.g. when the view scrolls off-screen) to save
    /// Core Animation work. Defaults to `true` once the view is visible.
    public var isAnimating: Bool = false {
        didSet { if oldValue != isAnimating { restartShimmerIfNeeded(force: true) } }
    }

    private let gradientLayer = CAGradientLayer()
    private var currentSweepAnimation: CABasicAnimation?
    /// Width the currently-attached `"sweep"` animation was built for.
    /// Used to short-circuit `layoutSubviews()` calls that didn't actually
    /// change our width — without this, every parent re-layout (and there
    /// are a lot of them) would tear down + rebuild the animation, which
    /// snaps the highlight back to the start of the loop and looks like
    /// a one-frame stutter.
    private var lastSweepWidth: CGFloat = 0
    /// Set when we've subscribed to lifecycle notifications. Stored so
    /// we can `removeObserver` in `deinit`.
    private var lifecycleObservers: [NSObjectProtocol] = []

    public init(theme: AetherSkeletonTheme = .light) {
        self.theme = theme
        super.init(frame: .zero)

        layer.masksToBounds = true
        layer.addSublayer(gradientLayer)
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        applyTheme()

        // Core Animation strips animations from off-screen layers when
        // the app backgrounds. On the way back up we listen on TWO
        // notifications, both with an async hop, because:
        //
        //   • `willEnterForegroundNotification` fires early — the scene
        //     is unlocking but the window isn't necessarily key yet,
        //     and on iOS 13+ scene-based apps the layer tree time can
        //     still be paused at this point. Adding an animation here
        //     sometimes "takes" but doesn't actually advance.
        //   • `didBecomeActiveNotification` fires once the scene is
        //     fully live — re-attaching here is the reliable path.
        //
        // The `DispatchQueue.main.async` defers the actual restart to
        // the next runloop tick, by which point CA's render server has
        // re-armed the layer's local time and `convertTime(0, from: nil)`
        // returns a sane reference. Without that hop the freshly-added
        // animation can sit there at frame 0 and never advance.
        let restart: () -> Void = { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.restartShimmerIfNeeded(force: true)
            }
        }
        let willForeground = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in restart() }
        let didActivate = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in restart() }
        lifecycleObservers = [willForeground, didActivate]
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func applyTheme() {
        // Set the dynamic UIColor on the view directly so UIView's own
        // trait-tracking machinery can refresh `backgroundColor` for
        // free on light↔dark flips.
        backgroundColor = theme.baseColor
        // For the gradient layer we have to resolve to a concrete
        // CGColor for OUR trait collection. Reading `.cgColor` directly
        // would resolve via `UITraitCollection.current` — a thread-local
        // value that's only set inside specific UIKit callbacks (draw
        // rect, layout, etc.) and is `unspecified` outside them. That
        // means a dynamic color read from a notification handler or
        // initializer can land on the WRONG branch (light variant in
        // dark mode). `resolvedColor(with:)` skips the thread-local
        // and uses the trait collection we hand it.
        let resolvedBase = theme.baseColor.resolvedColor(with: traitCollection)
        let resolvedHighlight = theme.highlightColor.resolvedColor(with: traitCollection)
        gradientLayer.colors = [
            resolvedBase.cgColor,
            resolvedHighlight.cgColor,
            resolvedBase.cgColor
        ]
        let fraction = max(0.1, min(0.9, theme.shimmerWidthFraction))
        let mid = 0.5 as NSNumber
        let half = NSNumber(value: Double(fraction) / 2)
        gradientLayer.locations = [
            NSNumber(value: 0.5 - Double(truncating: half)),
            mid,
            NSNumber(value: 0.5 + Double(truncating: half))
        ]
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        // Gradient sweeps horizontally; we render at 2× width so the slide
        // from -width to +width stays smooth at the edges.
        let sweepWidth = bounds.width * 2
        let newFrame = CGRect(x: -bounds.width, y: 0, width: sweepWidth, height: bounds.height)
        if gradientLayer.frame != newFrame {
            // Setting `frame` on a CALayer normally triggers an *implicit*
            // animation (CABasicAnimation on `bounds`/`position`), which
            // would visibly slide the gradient layer when the view
            // resizes — distinct from, and on top of, our own shimmer
            // animation. Disabling actions for this assignment keeps the
            // resize crisp.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradientLayer.frame = newFrame
            CATransaction.commit()
        }
        restartShimmerIfNeeded(force: false)
    }

    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        isAnimating = newWindow != nil
    }

    open override func didMoveToWindow() {
        super.didMoveToWindow()
        // Failsafe for the foreground-recovery path: if the scene was
        // detached from a window while backgrounded and re-attached
        // later, our notification observers may have already fired
        // (and bailed early because `bounds.width == 0` or
        // `isAnimating == false`). Re-arming here, after the view is
        // demonstrably back in a real hierarchy, catches that case.
        if window != nil {
            restartShimmerIfNeeded(force: true)
        }
    }

    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // `gradientLayer.colors` is `[CGColor]` — CGColor is a
        // statically-resolved value, NOT a dynamic UIColor. So when
        // iOS flips light↔dark (or accessibility contrast changes),
        // `view.backgroundColor` automatically refreshes (UIView
        // re-resolves its dynamic UIColor), but our gradient stays
        // frozen at the old colors until we re-resolve them ourselves.
        //
        // `hasDifferentColorAppearance(comparedTo:)` covers both the
        // light/dark switch AND the accessibility contrast toggle.
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyTheme()
        }
    }

    /// (Re)build the shimmer animation.
    ///
    /// - Parameter force: if `false`, the call is a no-op when an
    ///   animation is already attached AND the width hasn't changed —
    ///   used by `layoutSubviews()` to avoid the "rebuild on every
    ///   layout pass" stutter. Pass `true` from anywhere that genuinely
    ///   needs a fresh animation: theme change (duration may differ),
    ///   isAnimating toggle, foreground re-arming.
    private func restartShimmerIfNeeded(force: Bool) {
        let currentWidth = bounds.width
        let animationAttached = gradientLayer.animation(forKey: "sweep") != nil

        // Soft-skip path. The two checks together catch the common case
        // ("our width is fine, our animation is fine, leave us alone")
        // without breaking any of the genuine restart paths.
        if !force,
           isAnimating,
           animationAttached,
           abs(lastSweepWidth - currentWidth) < 0.5 {
            return
        }

        gradientLayer.removeAnimation(forKey: "sweep")
        currentSweepAnimation = nil

        guard isAnimating, currentWidth > 0 else {
            lastSweepWidth = 0
            return
        }

        // Geometry recap (with `bounds.width = W`):
        //   • `gradientLayer` is twice as wide as the view (`2W`),
        //     parked at origin `(-W, 0)` — its center sits at parent's
        //     `x = 0`, and the gradient's middle (highlight) stop lives
        //     at the layer's local `x = W`, i.e. parent's `x = position.x`.
        //   • So whatever we set as `position.x` is literally the X of
        //     the highlight band in the view's coordinate space.
        //
        // Endpoints chosen for a *seamless* repeat:
        //   • `fromValue = -W`  → highlight fully off the LEFT edge.
        //   • `toValue   =  2W` → highlight fully off the RIGHT edge.
        // Both endpoints render identical pixels (pure base color), so
        // the implicit snap from `toValue` back to `fromValue` between
        // repeat cycles is invisible — the shimmer reads as a single
        // continuous loop instead of a "blink → restart from left".
        //
        // Picking `0..2W` (the previous values) put the highlight ON
        // the left edge at `t = 0`, which made every repeat look like
        // the band teleported back into view.
        let anim = CABasicAnimation(keyPath: "position.x")
        anim.fromValue = -currentWidth
        anim.toValue = currentWidth * 2
        anim.duration = theme.shimmerDuration
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        // Cross-instance phase sync. `convertTime(0, from: nil)` returns
        // the layer-local time that corresponds to global Mach time 0
        // — a fixed reference point shared by every layer in the app.
        // Anchoring `beginTime` there means any two skeletons with the
        // same `shimmerDuration` will display the same highlight position
        // at any wall-clock moment, regardless of when each one was
        // attached to the screen. Five rows of placeholders read as ONE
        // coherent loading state instead of a noisy field of out-of-phase
        // stripes.
        anim.beginTime = gradientLayer.convertTime(0, from: nil)
        gradientLayer.add(anim, forKey: "sweep")
        currentSweepAnimation = anim

        lastSweepWidth = currentWidth
    }
}

/// Convenience: a capsule-shaped skeleton (for single-line text placeholders).
public final class AetherSkeletonLineView: AetherSkeletonView {
    /// Height of the capsule. Width is inferred from auto-layout or frame.
    public var lineHeight: CGFloat = 12.0 {
        didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    public override init(theme: AetherSkeletonTheme = .light) {
        super.init(theme: theme)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        applyCornerRadius(min(bounds.height / 2, bounds.width / 2))
        super.layoutSubviews()
    }

    public override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: lineHeight)
    }
}

/// Convenience: a rounded-rect skeleton (for card / avatar placeholders).
public final class AetherSkeletonBlockView: AetherSkeletonView {
    /// Corner radius applied after layout. Defaults to 10pt.
    public var cornerRadius: CGFloat = 10.0 {
        didSet { setNeedsLayout() }
    }

    public override init(theme: AetherSkeletonTheme = .light) {
        super.init(theme: theme)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        applyCornerRadius(cornerRadius)
        super.layoutSubviews()
    }
}

/// Convenience: a circular skeleton (for avatar placeholders).
public final class AetherSkeletonCircleView: AetherSkeletonView {
    public override init(theme: AetherSkeletonTheme = .light) {
        super.init(theme: theme)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        applyCornerRadius(min(bounds.width, bounds.height) / 2)
        super.layoutSubviews()
    }
}
