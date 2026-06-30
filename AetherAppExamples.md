# Aether App Examples

## Single Window

```swift
final class Application: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            WindowScene(id: "main") { scene in
                MainRootController(sceneID: scene.sceneID)
            }
        }
    }
}
```

## Multi-Scene Deep Link

```swift
AetherApplication {
    WindowScene(id: "main") { scene in
        MainRootController(sceneID: scene.sceneID)
    }

    WindowScene(id: "document", priority: 10) { scene in
        DocumentRootController(payload: scene.connectionPayload)
    }
    .matchesUserActivityType("com.example.document")
    .matchesURL { url in
        url.scheme == "example" && url.host == "doc"
    }
}
```

## Lifecycle And Plugins

```swift
AetherApplication {
    AnalyticsPlugin()

    AppLifecycle()
        .onDidBecomeActive { _ in Analytics.resume() }
        .onDidEnterBackground { _ in Analytics.pause() }

    RemoteNotifications()
        .onRegisterDeviceToken { Push.register($0.deviceToken) }
        .onReceive { context in
            Push.handle(context.userInfo)
            context.completion?(.newData)
        }
}
```

## Background Fetch

```swift
BackgroundEvents()
    .onFetch { context in
        Sync.run { result in
            context.completion(result)
        }
    }
```
