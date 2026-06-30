# Aether App Runtime Overview

`AetherApp` adds a declarative facade over UIKit delegates without replacing UIKit lifecycle.

Core pieces:

- `AetherApp`: user-owned declarative entry point.
- `AetherApplicationBuilder`: result builder that installs runtime nodes.
- `AetherApplicationRuntime`: compiled configuration, scene registry, event dispatcher, active scene storage.
- `AetherApplicationDelegateProxy`: `UIApplicationDelegate` bridge with selector-gating.
- `AetherSceneDelegateProxy`: `UIWindowSceneDelegate` bridge with selector-gating.
- `AetherSceneRegistry`: selects `WindowScene` definitions by configuration name, role, URL, or user activity.
- `AetherSceneInstance`: one runtime object per connected scene; owns `AetherWindow` and root content.

Selector-gating is central. The proxies implement many delegate methods, but `responds(to:)` only returns `true` when the builder registered a handler or the runtime needs the method for scene/window operation.

Rendering is callback-oriented:

```swift
WindowScene(id: "main") { context in
    MainRootController(sceneID: context.sceneID, phase: context.phase)
}
```

The render closure returns a `UIViewController`. `AetherSceneInstance` installs it into an `AetherWindow` and only swaps the root controller when the returned instance changes.
