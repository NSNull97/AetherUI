# Aether App Runtime Audit

Audit date: 2026-06-28.

SDK/source discovery used:

- `xcrun swift -print-target-info`
- `xcrun --show-sdk-path --sdk iphoneos` -> `iPhoneOS26.4.sdk`
- UIKit headers:
  - `UIKit.framework/Headers/UIApplication.h`
  - `UIKit.framework/Headers/UIScene.h`
  - `UIKit.framework/Headers/UIWindowScene.h`
- Project search:
  - `Example/Example/AppDelegate.swift`
  - `Example/Example/SceneDelegate.swift`
  - `Sources/AetherUI/Window`

The existing example app uses a classic `UIApplicationDelegate` plus `UIWindowSceneDelegate` and manually creates `AetherWindow(windowScene:)`. The new runtime keeps UIKit as the source of lifecycle truth and adds a declarative facade with selector-gated delegate proxies.

## Delegate Method Coverage

| Delegate method | Protocol | Availability | UIKit default if not implemented | Aether handler | Return type | Safe default | responds(to:) gated? | Notes |
|---|---|---:|---|---|---|---|---|---|
| `application(_:willFinishLaunchingWithOptions:)` | `UIApplicationDelegate` | iOS 6+ | Launch continues | `AppLifecycle.onWillFinishLaunching` | `Bool` | `true` | Yes | Return values compose with `allMustReturnTrue`. |
| `application(_:didFinishLaunchingWithOptions:)` | `UIApplicationDelegate` | iOS 3+ | Launch continues | `AppLifecycle.onDidFinishLaunching`, `onLaunch` | `Bool` | `true` | Yes | Runtime dump can run after this callback. |
| `applicationDidBecomeActive(_:)` | `UIApplicationDelegate` | iOS 2+, deprecated iOS 26 with scenes | No app-level callback | `AppLifecycle.onDidBecomeActive` | `Void` | no-op | Yes | Scene lifecycle is preferred when scenes are enabled. |
| `applicationWillResignActive(_:)` | `UIApplicationDelegate` | iOS 2+, deprecated iOS 26 with scenes | No app-level callback | `AppLifecycle.onWillResignActive` | `Void` | no-op | Yes | Gated to avoid changing app lifecycle behavior. |
| `applicationDidEnterBackground(_:)` | `UIApplicationDelegate` | iOS 4+, deprecated iOS 26 with scenes | No app-level callback | `AppLifecycle.onDidEnterBackground` | `Void` | no-op | Yes | App phase updates only when selector is exposed/called. |
| `applicationWillEnterForeground(_:)` | `UIApplicationDelegate` | iOS 4+, deprecated iOS 26 with scenes | No app-level callback | `AppLifecycle.onWillEnterForeground` | `Void` | no-op | Yes | Scene lifecycle remains primary. |
| `applicationWillTerminate(_:)` | `UIApplicationDelegate` | iOS 2+ | No callback | `AppLifecycle.onWillTerminate` | `Void` | no-op | Yes | Gated. |
| `applicationDidReceiveMemoryWarning(_:)` | `UIApplicationDelegate` | iOS 2+ | No callback | `AppLifecycle.onDidReceiveMemoryWarning` | `Void` | no-op | Yes | Gated. |
| `applicationSignificantTimeChange(_:)` | `UIApplicationDelegate` | iOS 2+ | No callback | `AppLifecycle.onSignificantTimeChange` | `Void` | no-op | Yes | Gated. |
| `application(_:open:options:)` | `UIApplicationDelegate` | iOS 9+, deprecated iOS 26 with scenes | URL is not app-handled | `URLRouting.onOpenURL`, `onOpenURL` | `Bool` | `false` | Yes | Default strategy is `firstHandled`. Scene URL contexts are preferred. |
| `application(_:handleOpenURL:)` | `UIApplicationDelegate` | iOS 2-9 deprecated | URL is not handled | Not enabled | `Bool` | `false` | Yes | Legacy-only; intentionally absent from proxy. |
| `application(_:open:sourceApplication:annotation:)` | `UIApplicationDelegate` | iOS 4.2-9 deprecated | URL is not handled | Not enabled | `Bool` | `false` | Yes | Legacy-only; intentionally absent from proxy. |
| `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` | `UIApplicationDelegate` | iOS 3+ | No callback | `RemoteNotifications.onRegisterDeviceToken` | `Void` | no-op | Yes | Gated. |
| `application(_:didFailToRegisterForRemoteNotificationsWithError:)` | `UIApplicationDelegate` | iOS 3+ | No callback | `RemoteNotifications.onFailToRegister` | `Void` | no-op | Yes | Gated. |
| `application(_:didReceiveRemoteNotification:)` | `UIApplicationDelegate` | iOS 3+, deprecated iOS 10 | No callback | `RemoteNotifications.onReceive` | `Void` | no-op | Yes | Exposed only when notification handler exists. |
| `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` | `UIApplicationDelegate` | iOS 7+ | Silent push not handled | `RemoteNotifications.onReceive` | completion | `.noData` fallback | Yes | Completion is one-shot with timeout fallback. |
| `application(_:performFetchWithCompletionHandler:)` | `UIApplicationDelegate` | iOS 7+, deprecated iOS 13 | No background fetch | `BackgroundEvents.onFetch` | completion | `.noData` fallback | Yes | Completion is one-shot. |
| `application(_:handleEventsForBackgroundURLSession:completionHandler:)` | `UIApplicationDelegate` | iOS 7+ | Session not delegated to app | `BackgroundEvents.onBackgroundURLSession` | completion | immediate fallback if no handler | Yes | Completion is one-shot. |
| `application(_:performActionFor:completionHandler:)` | `UIApplicationDelegate` | iOS 9+, deprecated iOS 26 with scenes | Shortcut not handled | Runtime shortcut path | completion `Bool` | `false` | Yes | Stubbed for app-level quick actions; scene callback preferred. |
| `applicationProtectedDataWillBecomeUnavailable(_:)` | `UIApplicationDelegate` | iOS 4+ | No callback | Legacy bridge only | `Void` | no-op | Yes | Handler DSL can be added without changing proxy policy. |
| `applicationProtectedDataDidBecomeAvailable(_:)` | `UIApplicationDelegate` | iOS 4+ | No callback | Legacy bridge only | `Void` | no-op | Yes | Handler DSL can be added without changing proxy policy. |
| `application(_:supportedInterfaceOrientationsFor:)` | `UIApplicationDelegate` | iOS 6+ | Info.plist/root VC decides | AetherWindow orientation fallback | mask | iPad `.all`, iPhone `.allButUpsideDown` | Yes | Exposed only when explicitly enabled; window runtime remains source of orientation. |
| `application(_:shouldAllowExtensionPointIdentifier:)` | `UIApplicationDelegate` | iOS 8+ | Allow extension point | Compatibility hook | `Bool` | `true` | Yes | Presence can affect keyboard extension policy, so gated. |
| `applicationShouldRequestHealthAuthorization(_:)` | `UIApplicationDelegate` | iOS 9+ | No callback | Not enabled | `Void` | no-op | Yes | Audited but not implemented in first slice. |
| `application(_:handlerFor:)` | `UIApplicationDelegate` | iOS 14+ | No intent handler | Not enabled | handler object | `nil` | Yes | Audited but not implemented in first slice. |
| `application(_:handle:completionHandler:)` | `UIApplicationDelegate` | iOS 11-14 deprecated | No intent response | Not enabled | completion | no-op | Yes | Legacy-only. |
| `application(_:viewControllerWithRestorationIdentifierPath:coder:)` | `UIApplicationDelegate` | iOS 6+ | UIKit cannot restore VC | State restoration handlers | `UIViewController?` | `nil` | Yes | Gated. |
| `application(_:shouldSaveSecureApplicationState:)` | `UIApplicationDelegate` | iOS 13.2+ | Do not save unless opted in | State restoration handlers | `Bool` | `false` | Yes | Selector literal used for iOS 13.0 deployment compatibility. |
| `application(_:shouldRestoreSecureApplicationState:)` | `UIApplicationDelegate` | iOS 13.2+ | Do not restore unless opted in | State restoration handlers | `Bool` | `false` | Yes | Selector literal used for iOS 13.0 deployment compatibility. |
| `application(_:willEncodeRestorableStateWith:)` | `UIApplicationDelegate` | iOS 6+ | No callback | State restoration handlers | `Void` | no-op | Yes | Gated. |
| `application(_:didDecodeRestorableStateWith:)` | `UIApplicationDelegate` | iOS 6+ | No callback | State restoration handlers | `Void` | no-op | Yes | Gated. |
| `application(_:shouldSaveApplicationState:)` | `UIApplicationDelegate` | iOS 6-13.2 deprecated | Do not save | Not enabled | `Bool` | `false` | Yes | Legacy-only; intentionally absent. |
| `application(_:shouldRestoreApplicationState:)` | `UIApplicationDelegate` | iOS 6-13.2 deprecated | Do not restore | Not enabled | `Bool` | `false` | Yes | Legacy-only; intentionally absent. |
| `application(_:willContinueUserActivityWithType:)` | `UIApplicationDelegate` | iOS 8+, deprecated iOS 26 with scenes | Activity not claimed | `UserActivityRouting.onWillContinue` | `Bool` | `false` | Yes | Scene version preferred. |
| `application(_:continue:restorationHandler:)` | `UIApplicationDelegate` | iOS 8+, deprecated iOS 26 with scenes | Activity not handled | `UserActivityRouting.onContinue` | `Bool` | `false` | Yes | Scene version preferred. |
| `application(_:didFailToContinueUserActivityWithType:error:)` | `UIApplicationDelegate` | iOS 8+, deprecated iOS 26 with scenes | No callback | `UserActivityRouting.onFailToContinue` | `Void` | no-op | Yes | Gated. |
| `application(_:didUpdate:)` | `UIApplicationDelegate` | iOS 8+, deprecated iOS 26 with scenes | No callback | `UserActivityRouting.onUpdate` | `Void` | no-op | Yes | Gated. |
| `application(_:userDidAcceptCloudKitShareWith:)` | `UIApplicationDelegate` | iOS 10+, deprecated iOS 26 with scenes | No callback | Not enabled | `Void` | no-op | Yes | Audited; scene API preferred. |
| `application(_:configurationForConnecting:options:)` | `UIApplicationDelegate` | iOS 13+ | Info.plist scene configuration | Runtime scene registry | `UISceneConfiguration` | Aether scene config | Runtime-required when scenes exist | Required to route `WindowScene` definitions. |
| `application(_:didDiscardSceneSessions:)` | `UIApplicationDelegate` | iOS 13+ | No callback | Runtime cleanup | `Void` | no-op | Runtime-required when scenes exist | Removes discarded scene instances. |
| `applicationShouldAutomaticallyLocalizeKeyCommands(_:)` | `UIApplicationDelegate` | iOS 15+ | SDK-dependent default | Compatibility hook | `Bool` | `true` | Yes | Selector literal used for deployment compatibility. |
| `scene(_:willConnectTo:options:)` | `UISceneDelegate` | iOS 13+ | Scene has no app window | `WindowScene`, `SceneLifecycle.onConnect` | `Void` | create AetherWindow | Runtime-required when scenes exist | Creates `AetherSceneInstance` and `AetherWindow`. |
| `sceneDidDisconnect(_:)` | `UISceneDelegate` | iOS 13+ | No cleanup callback | `SceneLifecycle.onDisconnect` | `Void` | release scene | Runtime-required when scenes exist | Releases window/root content references. |
| `sceneDidBecomeActive(_:)` | `UISceneDelegate` | iOS 13+ | No callback | `SceneLifecycle.onBecomeActive` | `Void` | no-op + phase update | Runtime-required when scenes exist | Updates `AetherScenePhase`. |
| `sceneWillResignActive(_:)` | `UISceneDelegate` | iOS 13+ | No callback | `SceneLifecycle.onResignActive` | `Void` | no-op + phase update | Runtime-required when scenes exist | Updates `AetherScenePhase`. |
| `sceneWillEnterForeground(_:)` | `UISceneDelegate` | iOS 13+ | No callback | `SceneLifecycle.onEnterForeground` | `Void` | no-op + phase update | Runtime-required when scenes exist | Updates `AetherScenePhase`. |
| `sceneDidEnterBackground(_:)` | `UISceneDelegate` | iOS 13+ | No callback | `SceneLifecycle.onEnterBackground` | `Void` | no-op + phase update | Runtime-required when scenes exist | Updates `AetherScenePhase`. |
| `scene(_:openURLContexts:)` | `UISceneDelegate` | iOS 13+ | URLs not scene-handled | `WindowScene.onOpenURL`, `URLRouting.onOpenURL` fallback | `Void` | no-op | Runtime-required when URL handlers exist | Per-scene handlers run before app URL routing. |
| `stateRestorationActivity(for:)` | `UISceneDelegate` | iOS 13+ | No scene restoration activity | State restoration handlers | `NSUserActivity?` | `nil` | Yes | Gated. |
| `scene(_:restoreInteractionStateWith:)` | `UISceneDelegate` | iOS 13+ | No restore callback | State restoration handlers | `Void` | no-op | Yes | Gated. |
| `scene(_:willContinueUserActivityWithType:)` | `UISceneDelegate` | iOS 13+ | Activity not claimed | `UserActivityRouting.onWillContinue` | `Void` | no-op | Runtime-required when handler exists | Scene-specific context. |
| `scene(_:continue:)` | `UISceneDelegate` | iOS 13+ | Activity not handled | `UserActivityRouting.onContinue` | `Void` | no-op | Runtime-required when handler exists | Scene-specific context. |
| `scene(_:didFailToContinueUserActivityWithType:error:)` | `UISceneDelegate` | iOS 13+ | No callback | `UserActivityRouting.onFailToContinue` | `Void` | no-op | Runtime-required when handler exists | Scene-specific context. |
| `scene(_:didUpdate:)` | `UISceneDelegate` | iOS 13+ | No callback | `UserActivityRouting.onUpdate` | `Void` | no-op | Runtime-required when handler exists | Scene-specific context. |
| `window` property | `UIWindowSceneDelegate` | iOS 13+ | UIKit does not retain app window | Runtime-owned `AetherWindow` | property | retained by proxy/instance | Runtime-required when scenes exist | Proxy stores the window. |
| `windowScene(_:didUpdate:interfaceOrientation:traitCollection:)` | `UIWindowSceneDelegate` | iOS 13+, deprecated iOS 26 | No callback | Render invalidation | `Void` | no-op | Runtime-required when scenes exist | Used for size/orientation/trait render invalidation on iOS 13-25. |
| `windowScene(_:didUpdateEffectiveGeometry:)` | `UIWindowSceneDelegate` | iOS 26+ | No callback | Planned render invalidation | `Void` | no-op | Yes | Audited; not implemented in first slice to keep iOS 13 deployment simple. |
| `windowScene(_:performActionFor:completionHandler:)` | `UIWindowSceneDelegate` | iOS 13+ | Shortcut not handled | Runtime shortcut path | completion `Bool` | `false` | Yes | Gated. |
| `windowScene(_:userDidAcceptCloudKitShareWith:)` | `UIWindowSceneDelegate` | iOS 13+ | No callback | Planned CloudKit routing | `Void` | no-op | Yes | Audited; not implemented in first slice. |
| `preferredWindowingControlStyleForScene(_:)` | `UIWindowSceneDelegate` | iOS 26+ | `.automaticStyle` | Planned windowing policy | object | system default | Yes | Audited; not implemented in first slice. |

## Selector-Gating Policy

- `AetherApplicationDelegateProxy` and `AetherSceneDelegateProxy` may physically implement methods, but `responds(to:)` returns `true` only when `AetherDelegateMethodRegistry` enables the mapped selector.
- Runtime-required selectors are enabled when at least one `WindowScene` is installed.
- URL/user activity/background/notification selectors are enabled only by corresponding DSL nodes.
- Deprecated selectors are disabled by default. Legacy callbacks that are not implemented in the proxy are documented as legacy-only.
- Secure state restoration selectors use public selector names instead of `#selector` because the package deploys to iOS 13.0 and those methods are iOS 13.2+.

## First-Slice Limitations

- The runtime covers the primary UIKit app, scene, URL, user activity, notification, background fetch/session, quick action, and restoration paths.
- Health authorization, Intents, CloudKit share callbacks, iOS 26 effective geometry, and preferred windowing control style are audited but not wired into the first implementation.
- `AetherApp` uses a documented `@main AppDelegate: AetherApplicationDelegateProxy<Application>` bootstrap. A macro/generated main can be added later without changing runtime internals.
- Render updates do not recreate `UIWindow`; they replace `contentController` only if the render closure returns a different controller instance.
