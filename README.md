# AetherUI

Pure UIKit navigation framework with glass morphism, liquid transitions, and floating tab bar. iOS 13+.

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/nicko170/AetherUI.git", from: "1.0.0")
]
```

## Quick Start

```swift
import AetherUI

// 1. Create a AetherWindow (keyboard-aware, status bar managed)
let window = AetherWindow(windowScene: windowScene)

// 2. Create navigation controllers for each tab
func makeTab(_ root: ViewController, item: UITabBarItem) -> AetherNavigationController {
    let nav = AetherNavigationController(mode: .single, theme: .liquidGlass())
    nav.setViewControllers([root], animated: false)
    nav.tabBarItem = item
    return nav
}

let chats = makeTab(ChatListController(), item: UITabBarItem(
    title: "Chats",
    image: UIImage(systemName: "message.fill"),
    tag: 0
))

// 3. Create tab bar controller
let tabs = AetherTabBarController(
    tabBarTheme: TabBarView.Theme(
        tabBarSelectedIconColor: .systemBlue,
        tabBarSelectedTextColor: .systemBlue,
        style: .liquidGlass
    )
)
tabs.setControllers([chats, settings], selectedIndex: 0)

// 4. Tab bar search button (morph animation)
tabs.searchShowcase = TabBarView.SearchShowcase(
    icon: UIImage(systemName: "magnifyingglass")!,
    action: { [weak tabs] in tabs?.activateSearch() }
)

// 5. Use AetherWindow instead of plain UIWindow
window.contentController = tabs
window.makeKeyAndVisible()
```

## Architecture

```
AetherWindow                          // UIWindow subclass: keyboard, status bar
  └── AetherTabBarController          // Window root, floating glass tab bar
        ├── AetherNavigationController // Per tab, manages push/pop stack
        │     ├── RootViewController    // Each controller owns its nav bar
        │     └── DetailViewController  // Pushed screen with back button
        └── TabBarView                  // Floating glass pill + search circle
```

Each `ViewController` owns its own `NavigationBarImpl`. Bars slide naturally with their controllers during push/pop — no shared bar, no floating titles.

## View Controllers

Subclass `ViewController` (not `UIViewController`):

```swift
class MyController: ViewController {
    init() {
        super.init(navigationBarPresentationData: nil) // nav bar created automatically
        navigationItem.title = "My Screen"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gear"),
            style: .plain, target: self, action: #selector(settingsTapped)
        )
    }
}
```

### Content View (Filter Bar)

Expandable content below the nav bar title:

```swift
let filterBar = ChatFilterBarContent() // subclass NavigationBarContentView
topBarAccessory = filterBar            // positioned below title automatically
```

Modes: `.expansion` (below title, bar grows) or `.replacement` (replaces title row).

## Navigation

```swift
// Push / Pop
navigationController?.pushViewController(detail, animated: true)
navigationController?.popViewController(animated: true)

// From ViewController:
push(detail)
pop()

// Stack management
navigationController?.popToRoot(animated: true)
navigationController?.replaceTopController(newController, animated: true)
```

### Back Button

Glass mode: chevron icon inside the left `GlassControlGroup`. Appears automatically when there's a controller below in the stack.

### Interactive Pop

Built-in left-edge swipe (20pt edge). Parallax: bottom view at 30%.

```swift
// Customize edge width per controller
override var interactiveNavivationGestureEdgeWidth: InteractiveTransitionGestureRecognizerEdgeWidth? {
    return .constant(40.0)  // or .constant(0) to disable
}
```

## Modals

Two-detent glass sheet, presented via plain UIKit `present(_:animated:)`.
Top corners 27pt, bottom corners match the device screen radius. Stage 1 —
compact with side insets (glass visible). Stage 2 — edge-to-edge, fully
tinted. Inner scroll cooperates with the sheet drag.

```swift
let content = MyContentController()
let modal = AetherModalController(content: content)
modal.primaryScrollView = content.scrollView   // optional
present(modal, animated: true)

// Programmatic detent change:
modal.setDetent(.stage2, animated: true)

// Dismiss via standard UIKit:
dismiss(animated: true)
```

## Overlays

```swift
navigation.presentOverlay(toast, animated: true)
navigation.dismissOverlay(toast, animated: true)
```

## Customization

### Navigation Bar

```swift
let barTheme = NavigationBarTheme(
    buttonColor: .label,
    primaryTextColor: .label,
    backgroundColor: .clear,
    enableBackgroundBlur: true,
    style: .glass,                    // .legacy | .glass
    glassStyle: .default,             // .default | .clear

    // Edge effect (scroll-content frost at nav bar boundary)
    edgeEffectAlpha: 0.65,            // 0 = invisible, 1 = opaque
    edgeEffectBlurRadius: 3.0,        // blur strength
    defaultContentHeight: 60.0        // nav bar content area height
)

// Factory with sensible defaults:
let barTheme = NavigationBarTheme.liquidGlass()

// Navigation controller theme:
let navTheme = NavigationControllerTheme(
    statusBar: .black,                // .black | .white
    navigationBar: barTheme,
    emptyAreaColor: .systemBackground
)
// or:
let navTheme = NavigationControllerTheme.liquidGlass()
```

#### Full NavigationBarTheme Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `overallDarkAppearance` | `Bool` | `false` | Dark mode flag for glass tint |
| `buttonColor` | `UIColor` | `.systemBlue` | Bar button tint |
| `primaryTextColor` | `UIColor` | `.black` | Title text color |
| `backgroundColor` | `UIColor` | `.white` | Bar background |
| `enableBackgroundBlur` | `Bool` | `true` | Blur behind bar |
| `separatorColor` | `UIColor` | `(0,0,0,0.3)` | Bottom separator |
| `badgeBackgroundColor` | `UIColor` | `.systemRed` | Badge circle color |
| `edgeEffectColor` | `UIColor?` | `nil` | Edge frost tint |
| `style` | `NavigationBarStyle` | `.legacy` | `.legacy` or `.glass` |
| `glassStyle` | `NavigationBarGlassStyle` | `.default` | `.default` or `.clear` |
| `edgeEffectAlpha` | `CGFloat` | `0.65` | Frost opacity |
| `edgeEffectBlurRadius` | `CGFloat` | `3.0` | Frost blur strength |
| `defaultContentHeight` | `CGFloat` | `60.0` | Content area height |

### Tab Bar

```swift
let tabTheme = TabBarView.Theme(
    tabBarSelectedIconColor: .systemBlue,
    tabBarSelectedTextColor: .systemBlue,
    style: .liquidGlass,

    // Layout
    pillHeight: 62.0,              // glass pill height
    totalHeight: 103.0,            // total view height (max, safe area inside)
    bottomInset: 25.0,             // pill distance from bottom
    sideInset: 16.0,               // horizontal margin
    innerPadding: 2.0,             // padding inside pill edges
    showcaseSpacing: 7.0,          // gap between pill and search circle

    // Edge effect
    edgeEffectAlpha: 0.65,         // frost opacity
    edgeEffectBlurRadius: 3.0,     // frost blur strength
    edgeEffectTintColor: nil       // tint (nil = use tabBarBackgroundColor)
)
```

#### Full TabBarView.Theme Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `tabBarBackgroundColor` | `UIColor` | `.systemBackground` | Background fill |
| `tabBarIconColor` | `UIColor` | `.label` | Unselected icon |
| `tabBarSelectedIconColor` | `UIColor` | `.systemBlue` | Selected icon |
| `tabBarTextColor` | `UIColor` | `.label` | Unselected label |
| `tabBarSelectedTextColor` | `UIColor` | `.systemBlue` | Selected label |
| `tabBarBadgeBackgroundColor` | `UIColor` | `.systemRed` | Badge circle |
| `enableBlur` | `Bool` | `true` | Blur behind tab bar |
| `style` | `Style` | `.liquidGlass` | `.legacy` or `.liquidGlass` |
| `pillHeight` | `CGFloat` | `62.0` | Glass pill height |
| `totalHeight` | `CGFloat` | `103.0` | Total tab bar view height |
| `bottomInset` | `CGFloat` | `25.0` | Pill bottom margin |
| `sideInset` | `CGFloat` | `16.0` | Pill horizontal margin |
| `innerPadding` | `CGFloat` | `2.0` | Content padding inside pill |
| `showcaseSpacing` | `CGFloat` | `7.0` | Gap: pill ↔ search circle |
| `edgeEffectAlpha` | `CGFloat` | `0.65` | Scroll-frost opacity |
| `edgeEffectBlurRadius` | `CGFloat` | `3.0` | Scroll-frost blur |
| `edgeEffectTintColor` | `UIColor?` | `nil` | Scroll-frost tint |

### Edge Effect

The edge effect creates a scroll-content frost zone where content dissolves as it approaches the nav bar or tab bar:

```swift
// Stronger frost (more opaque, heavier blur)
edgeEffectAlpha: 0.85,
edgeEffectBlurRadius: 6.0

// Subtle frost
edgeEffectAlpha: 0.3,
edgeEffectBlurRadius: 1.5

// Disable frost entirely
edgeEffectAlpha: 0.0
```

### Glass Primitives

Reusable glass components:

```swift
let glass = GlassBackgroundView(style: .regular)  // .regular | .clear | .prominent
let button = GlassBarButtonView(icon: icon, title: nil, state: .glass)
let controls = GlassControlGroup()
let lens = LiquidLensView(kind: .externalContainer)
```

`GlassControlGroup` supports icon, text, and custom view items. Items morph automatically (0.2s fade) when the set changes.

## Layout System

### ContainerViewLayout

```swift
override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
    super.containerLayoutUpdated(layout, transition: transition)
    // layout.size, layout.safeInsets, layout.additionalInsets, layout.statusBarHeight
}
```

### Transitions

```swift
.immediate                                              // no animation
.animated(duration: 0.3, curve: .easeInOut)             // standard
.animated(duration: 0.5, curve: .spring)                // spring
.animated(duration: 0.3, curve: .customSpring(damping: 0.8, initialVelocity: 0.5))
.animated(duration: 0.3, curve: .custom(0.33, 0.52, 0.25, 0.99))  // cubic bezier
```

## AetherWindow

`AetherWindow` replaces `UIWindow` with keyboard tracking, interactive keyboard dismissal, and layout propagation.

```swift
let window = AetherWindow(windowScene: windowScene)
window.contentController = tabs   // not rootViewController
window.makeKeyAndVisible()
```

Features:
- **Keyboard tracking** via `keyboardWillChangeFrameNotification` — `inputHeight` propagates through the entire controller hierarchy via `ContainerViewLayout`
- **Interactive keyboard dismiss** — pan gesture drags keyboard down, snaps back or dismisses based on velocity
- **Status bar management** via internal root controller
- **Orientation / edge gestures / home indicator** management
- **Covering view** for app snapshot protection: `window.coveringView = MyCoveringView()`
- **Debug gesture** — 10 taps in 0.4s triggers `window.debugAction`

## Search

### Nav Bar Search (AetherSearchController)

Glass search pill in the nav bar with full activation flow:

```swift
let search = AetherSearchController()
search.placeholder = "Search"
search.delegate = self
searchController = search  // on your ViewController
```

**Activation flow:** pill tap -> title/buttons fade out -> pill slides up -> text field appears inside pill -> glass X button appears -> keyboard shows -> collection animates up

**Deactivation:** X tap -> everything reverses simultaneously (keyboard + UI)

#### Delegate

```swift
extension MyController: AetherSearchControllerDelegate {
    func searchControllerWillActivate(_ controller: AetherSearchController) { }
    func searchControllerDidActivate(_ controller: AetherSearchController) { }
    func searchController(_ controller: AetherSearchController, didChangeText text: String) {
        // filter your data
    }
    func searchController(_ controller: AetherSearchController, didSubmitText text: String) {
        // perform search
    }
    func searchControllerWillDeactivate(_ controller: AetherSearchController) { }
    func searchControllerDidDeactivate(_ controller: AetherSearchController) { }
}
```

#### Results Controller

```swift
search.searchResultsController = MySearchResultsController()
// MySearchResultsController receives searchTextUpdated(text:) automatically
```

### Tab Bar Search (Morph Animation)

The tab bar search button morphs into a search capsule:

```swift
tabs.searchShowcase = TabBarView.SearchShowcase(
    icon: UIImage(systemName: "magnifyingglass")!,
    action: { [weak tabs] in tabs?.activateSearch() }
)
```

**Opening:** tab bar pill collapses to active-tab circle icon + search button expands into glass capsule with text field. Spring animation with glassmorphism scale effects.

**Closing:** reverse morph with fade + scale-down.

### Stacked Content

Stack search pill + filter chips in the nav bar:

```swift
let stacked = AetherStackedBarContent(views: [searchPill, filterBar])
topBarAccessory = stacked
```

## AetherListView

Virtualized list ported from Telegram's `ListView`. Transaction-based API for all modifications.

```swift
let listView = AetherListView()

// Insert items
listView.transaction(
    insertIndicesAndItems: items.enumerated().map { i, item in
        AetherListInsertItem(index: i, item: item)
    },
    options: [.animateInsertions]
)

// Delete + insert in one transaction
listView.transaction(
    deleteIndices: [AetherListDeleteItem(index: 2)],
    insertIndicesAndItems: [AetherListInsertItem(index: 5, item: newItem)],
    options: [.animateInsertions],
    scrollToItem: AetherListScrollToItem(index: 5, position: .visible)
)
```

### Item Protocol

```swift
class MyChatItem: AetherListItem {
    var approximateHeight: CGFloat { 72.0 }

    func createNode(params: AetherListItemLayoutParams, ...) -> (AetherListItemNode, AetherListItemNodeLayout) {
        let node = MyChatNode()
        node.configure(with: data)
        return (node, AetherListItemNodeLayout(contentSize: CGSize(width: params.width, height: 72)))
    }

    func updateNode(_ node: AetherListItemNode, ...) -> AetherListItemNodeLayout {
        (node as? MyChatNode)?.configure(with: newData)
        return AetherListItemNodeLayout(contentSize: CGSize(width: params.width, height: 72))
    }
}
```

### Node Lifecycle

```swift
class MyChatNode: AetherListItemNode {
    override func animateInsertion(duration: Double) { /* custom insert animation */ }
    override func animateRemoval(duration: Double, completion: @escaping () -> Void) { /* ... */ }
    override func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) { /* ... */ }
}
```

### Features

- **Virtualization** — only visible + preload buffer items in memory
- **Binary search** for visible range computation
- **Transaction queue** — serialized batch updates
- **Scroll-to-item** with `.top`, `.bottom`, `.center`, `.visible` positions
- **Callbacks** — `displayedItemRangeChanged`, `visibleContentOffsetChanged`, `didEndScrolling`

## Requirements

- iOS 13.0+
- Swift 5.9+
