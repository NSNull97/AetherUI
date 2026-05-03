import UIKit

/// Global glass-effect configuration shared across AetherUI surfaces
/// that go through `SystemGlassEffect.make(...)` — `ContextMenu`,
/// `Toolbar`, `Tooltip`, `ActionSheet`, and the lens transition. Lets
/// the host app swap between `.regular` and `.clear` Liquid Glass
/// styles in one place instead of touching each component.
///
/// `GlassBackgroundView` (used by `Alert`) is intentionally NOT routed
/// through here — it ships its own per-instance `Style` enum
/// (`regular` / `clear` / `prominent`) plus a custom `tintColor`
/// pipeline, and its style choice is part of its public API rather
/// than a global default.
///
/// Usage:
/// ```
/// AetherGlassConfig.current = AetherGlassConfig(style: .clear)
/// ```
/// All freshly-presented glass surfaces will pick up the new style.
/// Already-presented surfaces continue with the style they were
/// built with — `UIVisualEffectView.effect` isn't observed.
public struct AetherGlassConfig: Equatable {
    /// Underlying `UIGlassEffect.Style` on iOS 26+ / `UIBlurEffect.Style`
    /// approximation on older systems. See `SystemGlassEffectStyle`.
    public var style: SystemGlassEffectStyle

    /// Backend selector for the legacy (pre-iOS-26) glass path used by
    /// `LegacyGlassBackdropView`. iOS 26+ is unaffected — the native
    /// `UIGlassEffect` pipeline always wins there.
    public var legacyBlurBackend: LegacyBlurBackend

    public init(
        style: SystemGlassEffectStyle = .regular,
        legacyBlurBackend: LegacyBlurBackend = .custom
    ) {
        self.style = style
        self.legacyBlurBackend = legacyBlurBackend
    }

    /// Process-wide default, read by `SystemGlassEffect.make(isDark:)`
    /// and friends. Mutable so the host app can override it once at
    /// startup or live-flip it for theme switches.
    public static var current = AetherGlassConfig()
}

/// Pre-iOS-26 glass backend.
public enum LegacyBlurBackend: Equatable {
    /// Hand-rolled `CABackdropLayer` + `CAFilter.blur` + `CAFilter.colorMatrix`
    /// (saturation+brightness boost) + the in-`GlassBackgroundView`
    /// specular highlight overlay. Default — gives precise control over
    /// the visual mix at the cost of the private CA API surface.
    case custom

    /// `efremidze/VisualEffectView` — wraps the private
    /// `_UICustomBlurEffect` and exposes `blurRadius` / `colorTint` /
    /// `saturation` / `scale` as live-tunable properties on a stock
    /// `UIVisualEffectView`. Lighter to integrate, but goes through a
    /// different private API surface than the custom backend.
    case visualEffectView(
        blurRadius: CGFloat = 14.0,
        tintColor: UIColor = .systemBackground.withAlphaComponent(0.2),
        tintColorAlpha: CGFloat = 0.2,
        saturation: CGFloat = 1.8
    )
}
