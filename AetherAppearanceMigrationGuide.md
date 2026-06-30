# AetherAppearance Migration Guide

## New App-Level Style

Old code often passed a theme directly into nav or tab controllers:

```swift
let nav = AetherNavigationController(mode: .single, theme: .liquidGlass())
let tabs = AetherTabBarController(tabBarTheme: TabBarView.Theme())
```

New code selects the app style once:

```swift
AetherApplication {
    AppearanceStyle(.iOS27)
    WindowScene(id: "main") { _ in
        AetherNavigationController(rootViewController: RootController())
    }
}
```

Controllers now have no-theme primary initializers:

```swift
let nav = AetherNavigationController(rootViewController: RootController())
let tabs = AetherTabBarController()
```

The old theme initializers still exist as deprecated compatibility shims. Use them only while migrating existing call sites.

## Local Overrides

For one screen, implement `AetherControllerAppearanceProviding` and return partial overrides:

```swift
final class DetailController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        AetherAppearanceOverride(
            navigationBar: AetherNavigationBarAppearanceOverride(
                separator: .visible(color: .separator, opacity: 0.4)
            )
        )
    }
}
```

Do not create app-wide custom style ids or OS-version fallback logic. The public app styles are only `.iOS26` and `.iOS27`.
