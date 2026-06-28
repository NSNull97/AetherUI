# Aether Window Migration Guide

## Create The Window

Use `AetherNativeWindow` for new code. `AetherWindow` remains a source-compatible typealias.

```swift
let window = AetherNativeWindow(windowScene: windowScene)
window.contentController = rootController
window.makeKeyAndVisible()
```

Do not replace `rootViewController` directly. The window owns `AetherWindowRootViewController` for status bar, orientation, home indicator, screen-edge gestures, VoiceOver, and layout propagation.

## Present Aether Controllers

For existing `UIViewController` or `AetherViewController` overlays:

```swift
window.present(controller, on: .overlay, blockInteraction: true) {
    // ready
}
```

Custom levels are supported:

```swift
let level = AetherPresentationSurfaceLevel(rawValue: 450)
```

## Present Global Overlays

```swift
window.presentInGlobalOverlay(controller, animated: true)
window.dismissGlobalOverlay(controller, animated: true)
```

Global overlays are hosted in the Aether window. They are not rehosted into UIKit keyboard internals.

## Keyboard Manager

Use `AetherKeyboardManager` for public keyboard state:

```swift
let keyboard = AetherKeyboardManager(window: window)
keyboard.stateChanged = { state, transition in
    // state.frameInWindow, state.height, state.isVisible
}
keyboard.start()
```

Interactive Aether layout uses `ContainerViewLayout.inputHeight` and `inputHeightIsInteractivellyChanging`. When the window-level pan is enabled, AetherUI also applies the legacy Telegram-style keyboard offset internally so the native keyboard tracks the gesture in external apps. The keyboard lookup is not exposed as public API.

For legacy keyboard/container transitions:

```swift
let keyboard = AetherKeyboardManager(window: window)
keyboard.setSurfaces([
    AetherKeyboardSurface(hostView: controller.view)
])

controller.view.aetherKeyboardAutomaticHandlingOptions = [.disableForward]
```

Use `AetherKeyboardAutocorrection.apply(to:)` before reading committed text from a `UITextView`.

## TGHacks Replacements

AetherUI does not expose `TGHacks` or globally swizzle `UIView`. Use explicit Aether APIs instead:

| Telegram | AetherUI |
|---|---|
| `TGHacks.setApplicationKeyboardOffset` | Internal to `AetherNativeWindow` / `AetherKeyboardManager` |
| `TGHacks.applicationKeyboardWindow` | Not public; keyboard lookup remains inside AetherUI |
| `TGHacks.applyCurrentKeyboardAutocorrectionVariant` | `AetherKeyboardAutocorrection.apply(to:)` |
| `UIScrollView.stopScrollingAnimation` | `UIScrollView.aetherStopScrollingAnimation()` |
| `TGHacks.setAnimationDurationFactor` | `AetherLegacyAnimation.animationDurationFactor` with explicit Aether animations |

## Window Layout

Use `window.currentLayout` for the existing `ContainerViewLayout` path. New runtime components use `AetherWindowLayout`, which includes size, safe area, keyboard frame/height, status bar, orientation, system gesture, and transition metadata.

## Status Bar

```swift
window.updateStatusBar(style: .lightContent, hidden: false, transition: .animated(duration: 0.2, curve: .easeInOut))
```

Presented controllers can also drive the status bar through their normal UIKit overrides.

## Orientation

Defaults:

- iPad: `.all`
- iPhone: `.allButUpsideDown`

iOS 16+ uses `UIWindowScene.requestGeometryUpdate`. Older systems use orientation invalidation only; AetherUI does not force device orientation with KVC.

## Home Indicator And Screen Edges

Update controller preferences, then invalidate:

```swift
window.invalidatePrefersOnScreenNavigationHidden()
window.invalidateDeferScreenEdgeGestures()
```

## Portal Fallback

Use `AetherPortalSourceView` and `AetherPortalView`. The implementation is snapshot/display-link based and avoids private portal classes.

```swift
source.needsGlobalPortal = true
```

## Debug Overlay

```swift
let instrumentation = AetherWindowDebugInstrumentation()
instrumentation.installDebugOverlay(in: rootController.hostView)
```

## Runtime String Checks

Recommended source/binary scan terms for the window runtime:

```bash
rg -n "_UIPortalView|_UICustomBlurEffect|_updateToInterfaceOrientation|_update\\(toInterfaceOrientation|UIInputSet|contentsSwizzle|internalGetKeyboard" Sources/AetherUI/Window
```

The wider AetherUI repository has pre-existing glass/lens private API experiments outside the window runtime. Audit those separately before applying whole-product distribution gates.
