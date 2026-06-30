# AetherAppearance Runtime Overview

`AetherAppearance` is the app-level visual source for navigation, tab, search, and input chrome. Apps select one fixed style:

```swift
AetherApplication {
    AppearanceStyle(.iOS27)
    WindowScene(id: "main") { context in
        AetherNavigationController(rootViewController: RootController())
    }
}
```

The default is `.iOS26`. The runtime stores both `environment.appearanceStyle` and the resolved `environment.appearance`, so app and scene handlers receive the same visual contract.

Runtime changes are explicit:

```swift
AetherApplicationRuntime.shared?.updateAppearanceStyle(.iOS27)
```

That updates existing visible nav/tab chrome in place. It does not rebuild windows or root controllers.

## Surface Pipeline

- App style produces `AetherAppearance`.
- Surface resolvers produce `AetherNavigationBarResolvedAppearance`, `AetherTabBarResolvedAppearance`, `AetherSearchResolvedAppearance`, and `AetherInputBarResolvedAppearance`.
- Existing UIKit renderers temporarily consume legacy adapter themes derived from those resolved values.
- Screen-local changes use `AetherControllerAppearanceProviding` and partial `AetherAppearanceOverride` values.
