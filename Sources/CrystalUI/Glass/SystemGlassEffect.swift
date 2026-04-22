import UIKit

/// Shared helper that returns the right `UIVisualEffect` for "glass" chrome
/// in dialog / toolbar / tooltip surfaces. On iOS 26+ with the liquid
/// design enabled (see `GlassCompatibility.isLiquidDesignAvailable`) this
/// returns a `UIGlassEffect` so surfaces pick up the native Liquid Glass
/// pipeline (refraction, specular, interactive shimmer). On older iOS /
/// compatibility mode it falls back to `UIBlurEffect` with the matching
/// system-material style.
public enum SystemGlassEffectStyle {
    /// Dialog/card surface. Regular opacity.
    case regular
    /// Clear overlay — use for tooltips / pills where we want max
    /// transparency and rely on shadow for edge definition.
    case clear
}

public enum SystemGlassEffect {
    public static func make(style: SystemGlassEffectStyle, isDark: Bool) -> UIVisualEffect {
        if GlassCompatibility.isLiquidDesignAvailable, #available(iOS 26.0, *) {
            switch style {
            case .regular: return UIGlassEffect(style: .regular)
            case .clear:   return UIGlassEffect(style: .clear)
            }
        }
        let blurStyle: UIBlurEffect.Style
        switch style {
        case .regular:
            blurStyle = isDark ? .systemMaterialDark : .systemMaterialLight
        case .clear:
            blurStyle = isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight
        }
        return UIBlurEffect(style: blurStyle)
    }
}

extension UIColor {
    /// Cheap luminance classifier — good enough to pick a dark/light variant
    /// of a material style. Not colorspace-correct (uses sRGB components
    /// directly) but the threshold is forgiving.
    var isDarkApprox: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 0.5
    }
}
