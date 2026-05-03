import UIKit

// MARK: - UIView + CornerConfiguration

/// Aether-wide helpers that route view-level corner outlines through
/// iOS 26+'s `cornerConfiguration` API and fall back to `layer.cornerRadius`
/// on older OSes.
///
/// `cornerConfiguration` is the modern modeled-shape API:
///   * GPU-rounded (no `CAShapeLayer` mask rebuild per layout pass).
///   * Plays nicely with `UIGlassEffect` — when set on a glass-bearing
///     `UIVisualEffectView` it shapes the deformation as well as the
///     outline, so the elastic warp follows the rounded edge instead
///     of being clipped flat by a `masksToBounds` mask.
///   * Supports per-corner radii natively (`.uniformEdges(topRadius:bottomRadius:)`).
///
/// Callers that need full per-corner control can keep using
/// `cornerConfiguration` directly inside an `if #available(iOS 26.0, *)`
/// block — these helpers cover the common "uniform" and "top vs bottom"
/// cases.
///
/// The helpers also drive `clipsToBounds` (vs no-op leaving caller in
/// charge): on iOS 26+ `cornerConfiguration` shapes the OUTLINE but
/// children only clip to that outline when `clipsToBounds = true`,
/// matching the pre-iOS-26 `layer.masksToBounds` semantics callers expect.
public extension UIView {
    /// Apply a uniform corner outline. On iOS 26+ uses `cornerConfiguration`;
    /// on older OSes falls back to `layer.cornerRadius` with continuous
    /// curve (`.continuous` matches Apple's modern card corners and is
    /// what `cornerConfiguration` produces by default).
    ///
    /// - Parameters:
    ///   - radius: Corner radius in points.
    ///   - clipsChildren: If `true`, children are clipped to the rounded
    ///     outline (`clipsToBounds` / `masksToBounds`). Defaults to `true`
    ///     — the common case for cards / pills / containers.
    func applyCornerRadius(
        _ radius: CGFloat,
        clipsChildren: Bool = true
    ) {
        if #available(iOS 26.0, *) {
            cornerConfiguration = UICornerConfiguration.uniformCorners(radius: .fixed(radius))
            clipsToBounds = clipsChildren
            // Drop legacy outline so the two paths don't compete — a
            // pre-26-style `layer.cornerRadius` left alongside
            // `cornerConfiguration` is benign on the layer level but
            // confuses readers.
            layer.cornerRadius = 0
        } else {
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
            layer.masksToBounds = clipsChildren
        }
    }

    /// Apply asymmetric top vs bottom corner outline. `cornerConfiguration`
    /// supports this natively on iOS 26+; older OSes get a uniform
    /// fallback (the bigger of the two radii) since `layer.cornerRadius`
    /// is uniform-only — for true per-edge corners on legacy OSes,
    /// callers need a `CAShapeLayer` mask, which is out of scope of
    /// this helper.
    func applyCornerRadii(
        topRadius: CGFloat,
        bottomRadius: CGFloat,
        clipsChildren: Bool = true
    ) {
        if #available(iOS 26.0, *) {
            cornerConfiguration = UICornerConfiguration.uniformEdges(
                topRadius: .fixed(topRadius),
                bottomRadius: .fixed(bottomRadius)
            )
            clipsToBounds = clipsChildren
            layer.cornerRadius = 0
        } else {
            layer.cornerRadius = max(topRadius, bottomRadius)
            layer.cornerCurve = .continuous
            layer.masksToBounds = clipsChildren
        }
    }

    /// Clear any modeled corner outline — undoes a prior call to either
    /// `applyCornerRadius` or `applyCornerRadii`. Resets
    /// to a zero-radius `cornerConfiguration` on iOS 26+ (there's no
    /// public empty initializer for `UICornerConfiguration`, so we use
    /// `.uniformCorners(radius: .fixed(0))` as the no-op equivalent)
    /// and to `layer.cornerRadius = 0` on older OSes.
    func clearCornerRadius() {
        if #available(iOS 26.0, *) {
            cornerConfiguration = UICornerConfiguration.uniformCorners(radius: .fixed(0))
        }
        layer.cornerRadius = 0
        layer.masksToBounds = false
    }
}
