import UIKit

public struct CrystalSkeletonTheme: Equatable {
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

    public static let light = CrystalSkeletonTheme(
        baseColor: UIColor(white: 0.9, alpha: 1.0),
        highlightColor: UIColor(white: 0.97, alpha: 1.0)
    )

    public static let dark = CrystalSkeletonTheme(
        baseColor: UIColor(white: 0.18, alpha: 1.0),
        highlightColor: UIColor(white: 0.32, alpha: 1.0)
    )
}

/// Base class for a single shimmer-animated placeholder rectangle.
/// Cornering + mask configuration is delegated to subclasses or applied
/// directly by the caller via `layer.cornerRadius` / `layer.mask`.
open class CrystalSkeletonView: UIView {
    public var theme: CrystalSkeletonTheme {
        didSet { applyTheme(); restartShimmerIfNeeded() }
    }

    /// Pause the shimmer (e.g. when the view scrolls off-screen) to save
    /// Core Animation work. Defaults to `true` once the view is visible.
    public var isAnimating: Bool = false {
        didSet { if oldValue != isAnimating { restartShimmerIfNeeded() } }
    }

    private let gradientLayer = CAGradientLayer()
    private var currentSweepAnimation: CABasicAnimation?

    public init(theme: CrystalSkeletonTheme = .light) {
        self.theme = theme
        super.init(frame: .zero)

        layer.masksToBounds = true
        layer.addSublayer(gradientLayer)
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        applyTheme()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyTheme() {
        backgroundColor = theme.baseColor
        gradientLayer.colors = [
            theme.baseColor.cgColor,
            theme.highlightColor.cgColor,
            theme.baseColor.cgColor
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
        gradientLayer.frame = CGRect(x: -bounds.width, y: 0, width: sweepWidth, height: bounds.height)
        restartShimmerIfNeeded()
    }

    open override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        isAnimating = newWindow != nil
    }

    private func restartShimmerIfNeeded() {
        gradientLayer.removeAnimation(forKey: "sweep")
        currentSweepAnimation = nil
        guard isAnimating, bounds.width > 0 else { return }

        let anim = CABasicAnimation(keyPath: "position.x")
        anim.fromValue = gradientLayer.bounds.width / 2 - bounds.width
        anim.toValue = gradientLayer.bounds.width / 2 + bounds.width
        anim.duration = theme.shimmerDuration
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        gradientLayer.add(anim, forKey: "sweep")
        currentSweepAnimation = anim
    }
}

/// Convenience: a capsule-shaped skeleton (for single-line text placeholders).
public final class CrystalSkeletonLineView: CrystalSkeletonView {
    /// Height of the capsule. Width is inferred from auto-layout or frame.
    public var lineHeight: CGFloat = 12.0 {
        didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    public override init(theme: CrystalSkeletonTheme = .light) {
        super.init(theme: theme)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        layer.cornerRadius = min(bounds.height / 2, bounds.width / 2)
        layer.cornerCurve = .continuous
        super.layoutSubviews()
    }

    public override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: lineHeight)
    }
}

/// Convenience: a rounded-rect skeleton (for card / avatar placeholders).
public final class CrystalSkeletonBlockView: CrystalSkeletonView {
    /// Corner radius applied after layout. Defaults to 10pt.
    public var cornerRadius: CGFloat = 10.0 {
        didSet { setNeedsLayout() }
    }

    public override init(theme: CrystalSkeletonTheme = .light) {
        super.init(theme: theme)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        super.layoutSubviews()
    }
}

/// Convenience: a circular skeleton (for avatar placeholders).
public final class CrystalSkeletonCircleView: CrystalSkeletonView {
    public override init(theme: CrystalSkeletonTheme = .light) {
        super.init(theme: theme)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        super.layoutSubviews()
    }
}
