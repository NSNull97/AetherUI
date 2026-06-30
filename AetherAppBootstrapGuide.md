# AetherApp Bootstrap Guide

`AetherApp` is a declarative description of app and scene lifecycle. UIKit still owns process launch and scene delivery.

## New UIKit App

```swift
import UIKit
import AetherUI

final class Application: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            WindowScene(id: "main") { scene in
                MainRootController(sceneID: scene.sceneID)
            }

            AppLifecycle()
                .onDidFinishLaunching { context in
                    AppBootstrap.start(context.launchOptions)
                    return true
                }
        }
    }
}

@main
final class AppDelegate: AetherApplicationDelegateProxy<Application> {}
```

Configure `UIApplicationSceneManifest` so the scene delegate class is `$(PRODUCT_MODULE_NAME).AetherSceneDelegateProxy`, or rely on `application(_:configurationForConnecting:options:)` from the proxy to return that delegate dynamically.

## Existing UIKit App

Keep your current `@main AppDelegate`, then migrate when ready:

```swift
@main
final class AppDelegate: AetherApplicationDelegateProxy<Application> {}
```

Move old lifecycle code into `AppLifecycle`, `URLRouting`, `UserActivityRouting`, `RemoteNotifications`, and `BackgroundEvents`. If code cannot move yet, register:

```swift
LegacyAppDelegateBridge(existing: OldAppDelegate(), order: .beforeAether)
```

## Scene Setup

`WindowScene` creates an `AetherWindow(windowScene:)`, sets the rendered controller as `contentController`, and calls `makeKeyAndVisible()`.

```swift
WindowScene(id: "details") { scene in
    DetailRootController(payload: scene.connectionPayload)
}
.matchesURL { $0.host == "details" }
```

The window is not recreated during render invalidation.
