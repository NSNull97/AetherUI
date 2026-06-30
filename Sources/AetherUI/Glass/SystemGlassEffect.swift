import UIKit

/// Shared helper that returns the right `UIVisualEffect` for "glass" chrome
/// in dialog / toolbar / tooltip surfaces. On iOS 26+ with the liquid
/// design enabled (see `GlassCompatibility.isLiquidDesignAvailable`) this
/// returns a `UIGlassEffect` so surfaces pick up the native Liquid Glass
/// pipeline (refraction, specular, interactive shimmer). On older iOS /
/// compatibility mode it falls back to `UIBlurEffect` with the matching
/// system-material style.
public enum SystemGlassEffectStyle: Equatable, Sendable {
    /// Dialog/card surface. Regular opacity.
    case regular
    /// Denser chrome surface used by the iOS 27 appearance preset.
    case strong
    /// Clear overlay — use for tooltips / pills where we want max
    /// transparency and rely on shadow for edge definition.
    case clear
}

public enum SystemGlassEffect {
    public static func make(style: SystemGlassEffectStyle, isDark: Bool) -> UIVisualEffect {
        if GlassCompatibility.isLiquidDesignAvailable, #available(iOS 26.0, *) {
            // Default every UIGlassEffect to `isInteractive = true` so the
            // liquid-warp deformation under finger touch plays everywhere
            // glass is applied (toolbars, tooltips, action sheets, the
            // context-menu surface, the lens transition, etc.). Surfaces
            // that need a passive glass without the deformation can opt
            // out by writing `isInteractive = false` after `make(...)`.
            let effect: UIGlassEffect
            switch style {
            case .regular: effect = UIGlassEffect(style: .regular)
            case .strong:  effect = UIGlassEffect(style: .regular)
            case .clear:   effect = UIGlassEffect(style: .clear)
            }
            effect.isInteractive = true
            return effect
        }
        let blurStyle: UIBlurEffect.Style
        switch style {
        case .regular:
            // Was `.systemMaterial*` — that's the dense Apple "card"
            // material; on legacy it reads as a flat opaque pill rather
            // than glass (visible in the ContextMenu and ActionSheet
            // where the backdrop should clearly be blurred-through).
            // `.systemThinMaterial*` keeps the same vibrancy contract
            // but is roughly half the optical density, so the content
            // beneath now reads through the surface.
            blurStyle = isDark ? .systemThinMaterialDark : .systemThinMaterialLight
        case .strong:
            blurStyle = isDark ? .systemMaterialDark : .systemMaterialLight
        case .clear:
            blurStyle = isDark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight
        }
        return UIBlurEffect(style: blurStyle)
    }

    /// Config-aware variant: reads style from `AetherGlassConfig.current`.
    /// Components that don't need a fixed style (most of them) should use
    /// this and let the host app pick the look once via the global config.
    public static func make(isDark: Bool) -> UIVisualEffect {
        return make(style: AetherGlassConfig.current.style, isDark: isDark)
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
