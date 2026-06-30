# Aether App Migration Guide

## From Manual AppDelegate

Move launch code:

```swift
AppLifecycle()
    .onWillFinishLaunching { context in true }
    .onDidFinishLaunching { context in
        Bootstrap.start(context.launchOptions)
        return true
    }
```

Move URL handling:

```swift
URLRouting()
    .strategy(.firstHandled)
    .onOpenURL { Router.open($0.url, options: $0.options) }
```

## From Manual SceneDelegate

Replace manual window creation:

```swift
WindowScene(id: "main") { scene in
    MainRootController(sceneID: scene.sceneID)
}
```

The runtime creates `AetherWindow(windowScene:)`, sets `contentController`, and keeps the window alive through `AetherSceneInstance` and `AetherSceneDelegateProxy`.

## Coexistence

Use `LegacyAppDelegateBridge(existing:order:)` for staged migration. Keep ordering explicit to avoid double URL, push, or background handling.

Scene delegate coexistence should be treated carefully because both old and new code may create windows. Prefer moving scene window creation to `WindowScene` first.

## State Preservation

Render closures should return a stable root controller when navigation state must survive render invalidation. The runtime does not recreate `UIWindow`, but it will replace `contentController` if the closure returns a different controller instance.
