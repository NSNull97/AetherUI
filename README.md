# TelegramNavigationKit

UIKit-only navigation, modal, tab bar, and Liquid Glass primitives ported from Telegram iOS patterns.

## Install

Add the package to an iOS target:

```swift
.package(path: "/Users/nsnull/Documents/TelegramNavigationKit")
```

Then import it:

```swift
import TelegramNavigationKit
```

## Navigation

Create screens by subclassing `ViewController`. Pass `NavigationBarPresentationData` when the screen needs the built-in Telegram-style navigation bar.

```swift
final class ChatListController: ViewController {
    init() {
        let barTheme = NavigationBarTheme.liquidGlass()
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: barTheme))
        navigationItem.title = "Chats"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

let root = ChatListController()
let navigation = TelegramNavigationController(
    mode: .single,
    theme: .liquidGlass()
)
navigation.setViewControllers([root], animated: false)
window.rootViewController = navigation
```

Use stack APIs directly or from inside a `ViewController`:

```swift
navigation.pushViewController(details, animated: true)
navigation.popViewController(animated: true)

// Inside ViewController:
push(details)
pop()
```

Use `.automaticMasterDetail` and mark controllers with `navigationPresentation = .master` for regular-width split navigation.

## Tabs

Use `TelegramTabBarController` as a regular `ViewController`. The default tab bar theme is `liquidGlass`, with a floating `LiquidLensView` selection. Use `.legacy` only if you need the old full-width bar.

```swift
let tabs = TelegramTabBarController(
    navigationBarPresentationData: nil,
    tabBarTheme: TabBarView.Theme(
        tabBarSelectedIconColor: .systemBlue,
        tabBarSelectedTextColor: .systemBlue,
        style: .liquidGlass
    )
)

chats.tabBarItem = UITabBarItem(title: "Chats", image: chatsIcon, selectedImage: chatsSelectedIcon)
settings.tabBarItem = UITabBarItem(title: "Settings", image: settingsIcon, selectedImage: settingsSelectedIcon)

tabs.setControllers([chats, settings], selectedIndex: 0)
navigation.setViewControllers([tabs], animated: false)
```

Supported tab interactions:

```swift
override func tabBarItemHasDoubleTapAction() -> Bool { true }
override func tabBarItemPerformDoubleTapAction() {}
override func tabBarItemContextAction(sourceView: UIView, gesture: UIGestureRecognizer) {}
override func tabBarItemSwipeAction(direction: TabBarItemSwipeDirection) {}
```

## Modals And Overlays

Modal controllers are still part of the navigation stack. Set a presentation mode and push or call `presentModal`.

```swift
let compose = ComposeController(navigationBarPresentationData: data)
compose.navigationPresentation = .modal
navigation.presentModal(compose, animated: true)

navigation.dismissModal(animated: true)
```

Flat full-screen modals:

```swift
controller.navigationPresentation = .flatModal
```

Non-stack overlays live above root and modal containers:

```swift
navigation.presentOverlay(toastController, blocksInteractionUntilReady: false, animated: true)
navigation.dismissOverlay(toastController, animated: true)
```

## Minimized Controllers

Provide your own `MinimizedContainerProtocol` implementation and pass it through `setupContainer`.

```swift
navigation.minimizeViewController(
    callController,
    topEdgeOffset: nil,
    beforeMaximize: { navigation, complete in
        complete()
    },
    setupContainer: { current in
        current ?? CallMinimizedContainer()
    },
    animated: true
)
```

Use:

```swift
navigation.maximizeViewController(callController, animated: true) { dismissed in }
navigation.dismissMinimizedControllers()
```

## Glass Primitives

Reusable UIKit glass components:

```swift
let glass = GlassBackgroundView(style: .regular)
let button = GlassBarButtonView(icon: icon, title: nil, state: .glass)
let controls = GlassControlGroup()
controls.update(items: [])
let lens = LiquidLensView(kind: .externalContainer)
```

`LiquidLensView` uses the private native `_UILiquidLensView` when present on the OS and falls back to the bundled UIKit blur/mask implementation.

## Legacy Mode

Use legacy visual style explicitly:

```swift
let legacyBarTheme = NavigationBarTheme(style: .legacy)
let legacyTabs = TabBarView.Theme(style: .legacy)
```
