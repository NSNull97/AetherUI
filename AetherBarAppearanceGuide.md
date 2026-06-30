# AetherBar Appearance Guide

All bar surfaces resolve through the same primitive vocabulary:

- `AetherBarBackgroundAppearance`: `.none`, `.transparent`, `.glass(SystemGlassEffectStyle)`, `.color(UIColor)`.
- `AetherGlassStrokeAppearance`: `.none`, `.hairline(color:opacity:)`.
- `AetherSeparatorAppearance`: `.hidden`, `.visible(color:opacity:)`, `.scrollActivated(threshold:hysteresis:color:)`.
- `AetherEdgeEffectAppearance`: tint, alpha, blur radii, glass style, and edge size.

## Current Consumers

- Navigation chrome resolves to `AetherNavigationBarResolvedAppearance`, then adapts to `NavigationBarTheme`.
- Tab chrome resolves to `AetherTabBarResolvedAppearance`, then adapts to `TabBarView.Theme`.
- Bottom search resolves to `AetherSearchResolvedAppearance` during layout.
- Input accessory hosting exposes `resolvedInputBarAppearance()` as the current contract; there is no dedicated input bar renderer yet.

This keeps existing UIKit renderers stable while moving ownership from init-time themes to app-level appearance.
