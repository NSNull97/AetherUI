# Aether Window Runtime Port Audit

Source discovery was run against:

- `/Users/nsnull/Documents/Telegram-iOS/submodules/Display/Source`
- `/Users/nsnull/Documents/Telegram-iOS/submodules/UIKitRuntimeUtils/Source/UIKitRuntimeUtils`
- local AetherUI sources under `Sources/AetherUI` and `Sources/AetherUIBridging`

Telegram is used as a behavioral reference only. AetherUI must keep the window runtime framework-native, UIKit-only, and independent of Telegram modules, ASDK/Texture, SwiftSignalKit, and UIKitRuntimeUtils.

## Source Map

| Area | Telegram source studied | AetherUI target |
|---|---|---|
| Native window host | `NativeWindowHostView.swift`, `WindowContent.swift` | `AetherNativeWindow`, `AetherWindowRootViewController`, `AetherWindowHostView` |
| Child host | `ChildWindowHostView.swift`, `WindowContent.swift` | `AetherChildWindowHostView` |
| Presentation surfaces | `PresentationContext.swift`, `GlobalOverlayPresentationContext.swift`, `ContainableController.swift`, `LegacyPresentedController.swift` | `AetherPresentationContext`, `AetherPresentedController`, `AetherGlobalOverlayManager` |
| Portal/global portal | `PortalView.swift`, `PortalSourceView.swift`, `GlobalPortalView.swift`, `UIKitUtils.*` | `AetherPortalSourceView`, `AetherPortalView`, `AetherGlobalPortalHost` |
| Keyboard runtime | `KeyboardManager.swift`, `Keyboard.swift`, `WindowContent.swift`, `UIViewController+Navigation.*` | `AetherKeyboardManager`, `AetherKeyboardState`, notification/layout-guide path plus internal legacy keyboard-surface bridge |
| Layout/animation | `ContainerViewLayout.swift`, `ContainedViewLayoutTransition.swift`, `DisplayLinkDispatcher.swift`, `DisplayLinkAnimator.swift`, `CAAnimationUtils.swift` | `AetherWindowLayout`, existing `ContainerViewLayout`, existing transitions |
| Status/orientation/system UI | `NativeWindowHostView.swift`, `WindowContent.swift`, `UIWindow+OrientationChange.*` | `AetherStatusBarCoordinator`, `AetherOrientationCoordinator`, `AetherSystemGestureCoordinator` |
| Hit testing/accessibility | `WindowContent.swift`, `PresentationContext.swift`, `GlobalOverlayPresentationContext.swift` | `AetherWindowHostView`, presentation accessibility isolation |
| Runtime utilities | `RuntimeUtils.swift`, `UIKitUtils.*`, `NotificationCenterUtils.*`, proxy categories | Not imported; safe pieces rewritten in Swift/UIKit |

## Behavior Classification

| Telegram behavior | Telegram source | Required in AetherUI | Public API equivalent | Private/risky API involved | Framework-safe? | Fallback | Status |
|---|---|---|---|---|---|---|---|
| Root window + root controller host | `NativeWindowHostView.swift`, `WindowContent.swift` | Yes | `UIWindow`, `UIViewController`, `UIWindowScene` | Old Telegram orientation KVC/private update hooks | Yes | `requestGeometryUpdate` on iOS 16+, `attemptRotationToDeviceOrientation` earlier | Implemented as `AetherNativeWindow` + `AetherWindowRootViewController` |
| Root view frame minY compensation | `WindowRootViewControllerView` in `NativeWindowHostView.swift` | Possibly | Custom root `UIView.frame` override | None | Yes | Keep only if UIKit offsets root view during bars/rotation | Documented; Aether root view clamps y to 0 |
| Flexible presentation levels | `PresentationContext.swift` | Yes | `RawRepresentable` + `Comparable` raw levels | None | Yes | Custom levels with raw `Int32` | Implemented as `AetherPresentationSurfaceLevel` |
| Presentation readiness timeout | `PresentationContext.swift` | Yes | closure/readiness callback with `DispatchWorkItem` timeout | SwiftSignalKit in Telegram | Yes | Timeout proceeds after 2s | Implemented without SwiftSignalKit |
| Presentation lifecycle calls | `PresentationContext.swift` | Yes | UIKit child containment + guarded appearance callbacks | Telegram `setIgnoreAppearanceMethodInvocations` | Mostly | Use parent child containment and idempotent insert/remove | Implemented; no UIKit swizzling |
| Accessibility hiding under opaque overlays | `PresentationContext.swift`, `NavigationController.swift` | Yes | `accessibilityElementsHidden`, `UIAccessibility.screenChanged` | None | Yes | Hide lower views while opaque/blocking overlay is topmost | Implemented |
| Global overlay above root | `GlobalOverlayPresentationContext.swift`, `WindowContent.swift` | Yes | custom container view stack | Telegram can move to keyboard window | Yes when kept in root window | Root-window global overlay; below-keyboard placement is not supported through public UIKit | Implemented with public APIs |
| Global overlay below/with keyboard window | `GlobalOverlayPresentationContext.swift` | Useful | No public keyboard-window host | Private keyboard window/view access | No | Keep overlay in Aether window and use keyboard layout insets | Not exposed |
| Portal view | `PortalView.swift`, `PortalSourceView.swift`, `UIKitUtils.makePortalView` | Yes | snapshot/mirror/reparent with display-link sync | `_UIPortalView` | No | Snapshot/replica `UIView` tracked by display link | Implemented public fallback |
| Child window host | `ChildWindowHostView.swift` | Yes | `UIView` implementing host protocol | None | Yes | Local presentation context; parent system UI proxy/no-op | Implemented |
| Current keyboard height | `KeyboardManager.swift`, `WindowContent.swift` | Yes | keyboard notifications and converted frames | Direct keyboard view access in Telegram | Yes | Notification-derived frame in window coordinates | Implemented in `AetherKeyboardManager` |
| Interactive input offset | `KeyboardManager.updateInteractiveInputOffset`, `WindowContent` | Yes | `AetherNativeWindow` pan + `ContainerViewLayout` updates | Keyboard view layer bounds | Contained inside framework | Move Aether layouts/input bars and, when UIKit exposes the legacy host view, move the native keyboard surface | Implemented with internal legacy bridge |
| Horizontal keyboard transform for split panes | `KeyboardManager.updateSurfaces`, `KeyboardViewManager.update(leftEdge:)` | Yes | `AetherKeyboardSurface`, `AetherKeyboardViewManager.update(leftEdge:)`, `UIView.aetherKeyboardAutomaticHandlingOptions` | Keyboard window layer transform | Contained inside framework | Reset to identity when no surface owns first responder | Implemented with internal legacy bridge |
| Dismiss editing without animation | `KeyboardViewManager.dismissEditingWithoutAnimation` | Yes | `view.endEditing(true)` + remove local view animations | Removing keyboard window subview animations | Contained inside framework | End editing and remove app-owned animations even if keyboard lookup fails | Implemented |
| First responder tracking | `UIResponder.currentFirst`, recursive traversal | Yes | Recursive view traversal, responder-chain helper | Private `_trap` selector pattern in Telegram | Public traversal is safe | Recursive app-view search | Implemented |
| Autocorrection apply | `Keyboard.swift`, `applyKeyboardAutocorrection` | Yes | `UITextView.unmarkText()` + selection nudge | None in final Aether implementation | Yes | Preserve selection when text storage changed | Implemented as `AetherKeyboardAutocorrection.apply(to:)` |
| TGHacks scroll animation cancel | `UIScrollView+TGHacks.stopScrollingAnimation` | Useful | `setContentOffset(_:animated:)` + scroll-enabled toggle | None | Yes | Preserve previous scroll-enabled state | Implemented as `UIScrollView.aetherStopScrollingAnimation()` |
| TGHacks animation duration factors | `TGHacks.hackSetAnimationDuration`, `setAnimationDurationFactor` | Useful without swizzling | Explicit helper API | Global UIView method swizzling in Telegram | Yes only without swizzling | Explicit `AetherLegacyAnimation` helper; no process-wide mutation | Implemented without global swizzle |
| Status bar aggregation | `PresentationContext.statusBar`, `WindowContent.updateStatusBar` | Yes | Root VC status bar overrides | None | Yes | Top presented controller wins | Implemented through coordinator/context |
| Orientation aggregation | `WindowContent`, `PresentationContext.combinedSupportedOrientations` | Yes | Root VC `supportedInterfaceOrientations`, iOS 16 scene geometry | KVC device orientation/private window update | Yes | Public masks only; no forced device orientation on old iOS | Implemented with public APIs |
| Home indicator and screen edge deferral | `NativeWindowHostView.swift`, `WindowContent` | Yes | Root VC overrides and invalidation methods | None | Yes | Aggregated values | Implemented through coordinator |
| Private rotation notifications | `UIWindow+OrientationChange.*`, `NativeWindowHostView._update` | No | `viewWillTransition`, scene geometry | `_updateToInterfaceOrientation`, `_update(toInterfaceOrientation...)` | No | Public transition callbacks | Not ported |
| UIKit proxy categories/swizzles | `UIViewController+Navigation.*`, proxy files | No direct dependency | Existing Aether UIKit code | swizzling/KVC/associated runtime | Mixed | Reimplement only needed associated-object features in AetherUIBridging | Not imported |
| ASDK/Texture nodes | Many Display sources | No | `UIView`/`CALayer`/Aether controllers | ASDK dependency | No for AetherUI core | UIView-backed implementation | Replaced |
| SwiftSignalKit promises/signals | `PresentationContext`, `NativeWindowHostView` | No direct dependency | Closures and `DispatchWorkItem` | dependency not present | Yes | Closure callbacks | Replaced |

## Private / Non-public API Risk Inventory

| Risk | Telegram use | Need in AetherUI | Public API path possible? | Loss without private API | External app availability |
|---|---|---|---|---|---|
| `_update(toInterfaceOrientation:duration:force:)` / `_updateToInterfaceOrientation` | Detect exact orientation update window and post rotate notifications | No | Yes, use `viewWillTransition` and scene callbacks | Less precise legacy rotation timing | Must be unavailable |
| `UIDevice.current.setValue(..., forKey: "orientation")` | Force portrait on older iOS when masks change | No | Mostly, via masks and `attemptRotationToDeviceOrientation` | Old iOS may not force immediate rotation | Must be unavailable |
| `_UIPortalView` | Zero-copy portal mirror | Useful, not required | Yes, snapshot/replica/display-link sync | Public fallback can be one-frame stale and not live-render all layer effects | Must be unavailable |
| `_UICustomBlurEffect` | Custom blur radius/effect internals | Not part of window runtime | Use `UIVisualEffectView` or existing audited glass layer | Less exact system blur tuning | Outside this window port; not introduced |
| `CAFilter` | Blur/variable blur/lens effects | Not part of window runtime | Use public blur/snapshot where possible | Less exact glass/lens visuals | Outside this window port; not introduced |
| `contentsSwizzle` / private layer KVC | Screenshot/security/layer effects | No | Use public snapshot protection view | Cannot reproduce layer-swapping tricks | Must be unavailable |
| Private keyboard window/view access | Move keyboard surface, host global overlays in keyboard window | Yes for interactive keyboard offset only | Layout state still uses notifications/layout guide | Without it, `AetherNativeWindow` pan moves input layout but the native keyboard does not track the finger | Internal to AetherUI; not a public API |
| `UIInputSet...` classes | Locate keyboard host view | Yes for interactive keyboard offset only | Use notifications/layout guide for state | No direct keyboard layer manipulation | Internal to AetherUI; not a public API |
| Private autocorrection calls | Force text autocorrection commit | Yes | Yes, public `UITextView.unmarkText()` and selected-range nudge | Less exact than hidden UIKit calls, but matches Telegram's current helper behavior | No private code used |
| Hidden status bar host access | Status-bar proxy rendering | No | Root VC status bar APIs | Less custom status-bar rendering | Must be unavailable |
| `highFrameRateReason` KVC | Performance/display tuning | No | Use public display link preferred frame rate APIs | Less private tuning | Must be unavailable |
| Secure text-field layer swapping | Screenshot prevention | No | Covering view before background/snapshot | No always-on screen capture prevention | Must be unavailable |
| Any selector beginning with `_` | Telegram runtime hacks | No default | Use public APIs | Some Telegram-specific polish omitted | Must be unavailable |

## AetherUI Decisions

- AetherUI exposes one unified window runtime behavior to all applications.
- There is no configuration-based runtime switch and no external private-compatibility API.
- The window runtime may contain the legacy keyboard-surface bridge required for Telegram-style interactive dismissal, but it must remain internal to the framework and unavailable as public app API.
- Existing non-window glass/lens code has its own private API surface and is not part of this port; it is noted as pre-existing and not expanded here.
- Keyboard interactive dismissal updates Aether layout and the native keyboard surface when UIKit exposes the legacy keyboard host view.
- TGHacks behavior is ported as explicit Aether-prefixed APIs and internal runtime helpers. AetherUI does not globally swizzle `UIView` animation methods.
- Global overlays stay in the Aether root window. Controllers must react to `AetherWindowLayout.keyboardFrameInWindow` / `ContainerViewLayout.inputHeight`.
- Portal fallback is snapshot/replica based and explicitly avoids non-public portal classes.

## Missing Or Partial Parity

- Keyboard-surface movement depends on UIKit continuing to expose `UIRemoteKeyboardWindow` and either `UIInputSetHostView` or `UIKeyboardItemContainerView`; if lookup fails, Aether still completes the gesture and falls back to layout-only movement.
- Global overlays cannot be rehosted into the keyboard window without private APIs.
- Old-iOS forced orientation is not reproduced with KVC.
- Telegram ASDK-specific lifecycle and display node opacity tracing is replaced with UIView-level flags.
- Status bar proxy rendering is not ported; Aether uses root VC status bar coordination.
