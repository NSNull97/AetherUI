# TabBar

Корневой плавающий tab bar с glass-pill, опциональным search-кружком,
bottomBarAccessory, минимизацией при скролле и Apple-Music-style
expanded accessory.

## Overview

``AetherTabBarController`` — root-контейнер приложения с плавающим
tab bar. В отличие от `UITabBarController`, не владеет nav bar'ом — каждая
вкладка содержит ``AetherNavigationController`` с собственным баром на
каждом экране (см. <doc:NavigationController>).

Основные возможности:

- ``TabBarView`` — плавающий glass-pill с item'ами, badges, edge-effect
  на скролле.
- ``AetherTabBarController/searchShowcase`` — опциональный search-кружок
  рядом с pill'ом.
- ``AetherTabBarController/bottomBarAccessory`` — accessory-полоса над
  pill'ом (Now Playing pill и аналогичные сценарии).
- ``AetherTabBarController/tabBarMinimizeBehavior`` — авто-минимизация
  при скролле вниз (iOS 26 `tabBarMinimizeBehavior` API surface).
- ``AetherTabBarController/presentExpandedAccessory(_:animated:)`` —
  Apple-Music-style морф accessory pill'а в fullscreen-карточку.
- ``AetherTabBarController/tabContextMenuItemsProvider`` — context-menu
  на long-press tab item'а.

## Базовый шаблон

```swift
func makeRootController() -> AetherTabBarController {

    func makeTab(_ root: ViewController, item: UITabBarItem) -> AetherNavigationController {
        let nav = AetherNavigationController(mode: .single, theme: .liquidGlass())
        nav.setViewControllers([root], animated: false)
        nav.tabBarItem = item
        return nav
    }

    let chats = makeTab(ChatsController(), item: UITabBarItem(
        title: "Чаты",
        image: UIImage(systemName: "message.fill"),
        tag: 0
    ))
    let settings = makeTab(SettingsController(), item: UITabBarItem(
        title: "Настройки",
        image: UIImage(systemName: "gearshape.fill"),
        tag: 1
    ))

    let tabs = AetherTabBarController(tabBarTheme: TabBarView.Theme(
        tabBarSelectedIconColor: .systemBlue,
        tabBarSelectedTextColor: .systemBlue,
        style: .liquidGlass
    ))
    tabs.setControllers([chats, settings], selectedIndex: 0)
    return tabs
}
```

> Important: `AetherTabBarController` ожидает в качестве дочерних
> контроллеров ``AetherNavigationController`` или ``AetherViewController``,
> **не** `UINavigationController`. Использование стандартного
> `UINavigationController` нарушит layout dispatch.

## Управление контроллерами

```swift
tabs.setControllers([chats, settings, profile], selectedIndex: 0)
tabs.controllers              // [UIViewController]
tabs.currentController        // UIViewController?
tabs.selectedIndex = 1        // программное переключение
```

## TabBarView.Theme

Полный список свойств темы:

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `tabBarBackgroundColor` | `UIColor` | `.clear` | Фон pill'а в `.legacy` стиле. |
| `tabBarSeparatorColor` | `UIColor` | `.separator` | Separator между tab bar и контентом. |
| `tabBarIconColor` | `UIColor` | `.label` | Tint неактивных иконок. |
| `tabBarSelectedIconColor` | `UIColor` | `.systemBlue` | Tint активной иконки. |
| `tabBarTextColor` | `UIColor` | `.label` | Цвет неактивного label. |
| `tabBarSelectedTextColor` | `UIColor` | `.systemBlue` | Цвет активного label. |
| `tabBarBadgeBackgroundColor` | `UIColor` | `.systemRed` | Фон badge. |
| `tabBarBadgeStrokeColor` | `UIColor` | `.white` | Обводка badge. |
| `tabBarBadgeTextColor` | `UIColor` | `.white` | Цвет текста в badge. |
| `enableBlur` | `Bool` | `true` | Системный blur за фоном (`.legacy`). |
| `isDark` | `Bool` | `false` | Принудительный dark-режим glass. |
| `style` | ``TabBarView/Style`` | `.liquidGlass` | `.legacy` или `.liquidGlass`. |
| `outerInsets` | `UIEdgeInsets` | `(4,25,4,25)` | Внешние insets контента. |
| `pillHeight` | `CGFloat` | `62.0` | Высота glass-pill'а. |
| `totalHeight` | `CGFloat` | `103.0` | Общая высота tab bar view (с учётом safe area). |
| `bottomInset` | `CGFloat` | `25.0` | Расстояние от низа экрана до pill'а (на устройствах с home indicator). |
| `sideInset` | `CGFloat` | `16.0` | Горизонтальный margin pill'а. |
| `innerPadding` | `CGFloat` | `2.0` | Внутренний padding pill'а. |
| `showcaseSpacing` | `CGFloat` | `7.0` | Gap между pill и search-кружком. |
| `edgeEffectAlpha` | `CGFloat` | `0.75` | Opacity scroll-edge frost. |
| `edgeEffectBlurRadiusAtEdge` | `CGFloat` | `2.0` | Blur radius на нижней границе. |
| `edgeEffectBlurRadiusAtFade` | `CGFloat` | `0.0` | Blur radius на верхней границе. |
| `edgeEffectTintColor` | `UIColor?` | `nil` | Tint frost (nil → tabBarBackgroundColor). |

### Стили

| Стиль | Описание |
|---|---|
| `.legacy` | Классический UIKit-style: непрозрачный фон, separator, no-glass. |
| `.liquidGlass` | iOS 26 liquid glass: системный `UIGlassEffect`, морф между состояниями. |

### Динамическая смена темы

```swift
tabs.tabBarTheme = TabBarView.Theme(
    tabBarSelectedIconColor: .systemPink,
    style: .liquidGlass
)
```

`didSet` автоматически вызывает `tabBarView.updateTheme(_:)`.

### Bottom inset на устройствах без home indicator

`effectiveBottomInset` автоматически корректирует `bottomInset` на
устройствах без home indicator: при `safeAreaInsets.bottom == 0` (старые
iPhone, iPod touch) значение коллапсируется до 16pt вместо
`theme.bottomInset` (25pt) для соответствия стандартному iOS-spacing.

## Search showcase

Search-кружок рядом с pill'ом (Apple Music style):

```swift
tabs.searchShowcase = TabBarView.SearchShowcase(
    icon: UIImage(systemName: "magnifyingglass")!,
    action: { [weak tabs] in
        tabs?.activateSearch()
    }
)
```

При вызове ``AetherTabBarController/activateSearch()``:

- Tab bar pill сжимается в иконку активной вкладки.
- Search-кружок расширяется в горизонтальную glass-капсулу с встроенным
  `UITextField`.
- Spring-анимация с glassmorphism scale-эффектами.
- На iOS 26+ обе капсулы share `UIGlassContainerEffect` через
  `GlassBackgroundContainerView`, что обеспечивает merge при сближении.

Деактивация — ``AetherTabBarController/deactivateSearch()``.

ViewController может реагировать на активацию через override:

```swift
override func tabBarActivateSearch() {
    searchController?.activate()
}

override func tabBarDeactivateSearch() {
    searchController?.deactivate()
}
```

Подробнее — <doc:Search>.

## Bottom bar accessory

Accessory-полоса над tab bar pill'ом (Now Playing, Mini Player и
аналогичные сценарии):

```swift
class NowPlayingAccessory: TabBarAccessoryView {
    override var nominalHeight: CGFloat { 56.0 }

    override func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        // Раскладка subview-объектов в области (size.width × nominalHeight).
    }
}

let accessory = NowPlayingAccessory()
tabs.bottomBarAccessory = accessory                              // мгновенное присваивание
tabs.setBottomBarAccessory(accessory, animated: true)            // crossfade 0.25с
```

Accessory:

- Оборачивается во внутренний `GlassBackgroundView`-wrapper.
- Позиционируется 8pt над pill'ом, `sideInset` = `tabBarTheme.sideInset`.
- Tab bar автоматически включает accessory в
  `additionalSafeAreaInsets.bottom` и childLayout.additionalInsets, что
  обеспечивает корректный отступ для scroll-контента.
- Edge-effect frost tab bar расширяется вверх для покрытия accessory:
  scroll content «растворяется» через accessory и tab bar как единая
  визуальная полоса.

### Динамическое изменение размера

```swift
class ExpandableAccessory: TabBarAccessoryView {
    var isExpanded = false

    override var nominalHeight: CGFloat {
        return isExpanded ? 96.0 : 56.0
    }

    func toggle() {
        isExpanded.toggle()
        invalidateLayout(transition: .animated(duration: 0.3, curve: .spring))
    }
}
```

### Expanded accessory (Apple Music morph)

Accessory может быть преобразован в fullscreen-карточку (стиль Apple
Music «открытие плеера») через `expandedViewControllerProvider`:

```swift
class NowPlayingAccessory: TabBarAccessoryView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        expandedViewControllerProvider = {
            return FullscreenPlayerController()
        }
    }
}
```

При тапе на glass-поверхность accessory вызывается provider; если он
возвращает не-`nil` controller, выполняется морф accessory pill'а в
fullscreen-карточку:

- Wrapper'а grows от accessory pill до full screen bounds через spring
  (0.55с, damping 0.78 — небольшой overshoot).
- Controller'а view fade-in поверх старого accessory content.
- Tab bar fade-out (карточка скрывает chrome).
- CornerRadius wrapper'а animates от capsule (~24pt) до accessory's
  capsule shape.
- Drag-to-dismiss pan на wrapper'е (с координацией со scroll views
  внутри controller'а).

Программное закрытие:

```swift
tabs.dismissExpandedAccessory(animated: true)
```

Чтение состояния:

```swift
tabs.expandedAccessoryViewController    // UIViewController?
```

## Минимизация (`tabBarMinimizeBehavior`)

iOS 26-style auto-минимизация tab bar при скролле:

```swift
tabs.tabBarMinimizeBehavior = .onScrollDown   // или .never (default)
```

При `.onScrollDown`:

- Скролл вниз (от верха) → tab bar коллапсируется: pill сжимается в
  48×48 active-tab кружок на leading edge, search showcase — в matching
  кружок на trailing edge. `bottomBarAccessory` reflows между ними.
- Скролл вверх (или достижение верха) → tab bar расширяется обратно.

Программное управление:

```swift
tabs.setTabBarMinimized(true, transition: .animated(
    duration: 0.35, curve: .customSpring(damping: 0.85, initialVelocity: 0)
))

tabs.isTabBarMinimized   // read-only состояние
```

> Note: При активном search mode минимизация подавляется: оба механизма
> управляют chrome и одновременная работа приведёт к рассинхронизации
> анимаций.

## Управление видимостью tab bar

Pushed-экран может скрыть tab bar для fullscreen-layout'а:

```swift
override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    aetherTabBarController?.updateIsTabBarHidden(true, transition: .animated(
        duration: 0.3, curve: .easeInOut
    ))
}

override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    aetherTabBarController?.updateIsTabBarHidden(false, transition: .animated(
        duration: 0.3, curve: .easeInOut
    ))
}
```

## Context menu на tab item

Long-press по tab item'у активирует ``AetherContextMenuController``,
если задан provider:

```swift
tabs.tabContextMenuItemsProvider = { tabIndex in
    switch tabIndex {
    case 0:  // Чаты
        return [
            ContextMenuItem.action(.init(text: "Новый чат",
                                         icon: UIImage(systemName: "square.and.pencil"),
                                         action: { /* ... */ })),
            ContextMenuItem.action(.init(text: "Новая группа",
                                         icon: UIImage(systemName: "person.2"),
                                         action: { /* ... */ }))
        ]
    default:
        return []  // подавление меню для других вкладок
    }
}
```

Альтернативно — override `contextMenuItems(forTabAt:)` в подклассе
`AetherTabBarController`.

ViewController также может реагировать на long-press через
``AetherViewController/tabBarItemContextActionType`` и
``AetherViewController/tabBarItemContextAction(sourceView:gesture:)``.

## Чтение pill / chrome geometry

Для размещения внешнего layout (floating toolbar, toast'ов):

```swift
tabs.pillFrame(in: someView)     // CGRect — frame pill'а в координатах someView
tabs.chromeTopY(in: someView)    // CGFloat? — верхняя Y-координата всего chrome (pill + accessory)
```

`chromeTopY` учитывает `bottomBarAccessory` (если есть) — это полная
верхняя граница visible chrome. ``AetherViewController/floatingToolbar``
автоматически использует её для anchor'инга.

## Public API сводка

### ``AetherTabBarController``

| Свойство / метод | Назначение |
|---|---|
| `init(tabBarTheme:)` | Создание с темой. |
| `controllers` | Массив дочерних контроллеров. |
| `currentController` | Контроллер активной вкладки. |
| `selectedIndex` | Индекс активной вкладки (read-write). |
| `setControllers(_:selectedIndex:)` | Установка контроллеров и активной вкладки. |
| `tabBarTheme` | Текущая тема tab bar (`didSet` → updateTheme). |
| `searchShowcase` | Search-кружок рядом с pill'ом. |
| `tabContextMenuItemsProvider` | Provider для long-press context menu. |
| `bottomBarAccessory` | Accessory над pill'ом. |
| `setBottomBarAccessory(_:animated:)` | Установка с crossfade. |
| `expandedAccessoryViewController` | Текущий expanded controller. |
| `presentExpandedAccessory(_:animated:)` | Морф accessory → fullscreen. |
| `dismissExpandedAccessory(animated:)` | Реверс морфа. |
| `tabBarMinimizeBehavior` | Авто-минимизация при скролле. |
| `isTabBarMinimized` | Текущее состояние минимизации. |
| `setTabBarMinimized(_:transition:)` | Программное переключение минимизации. |
| `updateIsTabBarHidden(_:transition:)` | Скрытие/показ tab bar. |
| `activateSearch()` / `deactivateSearch()` | Управление search-режимом. |
| `pillFrame(in:)` | Frame pill'а в координатах view. |
| `chromeTopY(in:)` | Верхняя Y-координата chrome. |

### ``TabBarView``

| Свойство / метод | Назначение |
|---|---|
| `init(theme:)` | Создание view. |
| `selectedIndex` | Индекс активной вкладки. |
| `searchShowcase` | Search-кружок. |
| `isMinimized` | Read-only состояние минимизации. |
| `setMinimized(_:transition:)` | Программная минимизация. |
| `bottomAccessoryReservedHeight` | Высота, которую edge-effect должен покрыть выше bar. |
| `updateTheme(_:)` | Динамическая смена темы. |

### ``TabBarAccessoryView``

| Свойство / метод | Назначение |
|---|---|
| `nominalHeight` | Естественная высота. Override в подклассе. |
| `height` | Текущая высота для layout (default = nominalHeight). |
| `updateLayout(size:transition:)` | Раскладка subview-объектов. |
| `requestLayout` | Closure для запроса re-layout (framework-level). |
| `expandedViewControllerProvider` | Provider для Apple-Music-морфа. |
| `invalidateLayout(transition:)` | Запрос re-layout после изменения размера. |

## Edge cases

- **Дочерние контроллеры — только `AetherNavigationController` или
  `ViewController`.** Использование `UINavigationController` нарушит
  layout dispatch (нет `containerLayoutUpdated` в стандартном API).
- **Минимизация vs search mode.** При активном search оба механизма
  управляют chrome; минимизация подавляется автоматически. При попытке
  минимизировать с активным search вызов `setMinimized(true, ...)` —
  no-op.
- **Expanded accessory + scroll observer.** При presentExpandedAccessory
  scroll observer автоматически отсоединяется (иначе случайный scroll
  tick во время morph'а вызовет race condition с минимизацией). Observer
  переподключается при dismiss.
- **`bottomBarAccessory` z-order.** В collapsed state wrapper accessory
  должен быть выше tab bar — иначе edge-effect frost tab bar (extending
  12pt над bar bounds через `bandShift`) перекроет accessory glass
  surface. После dismiss expanded accessory выполняется re-layout для
  восстановления corrct z-order.
- **`safeAreaInsets.bottom == 0` на старых устройствах.** На iPhone без
  home indicator `effectiveBottomInset` автоматически коллапсируется до
  16pt (вместо `theme.bottomInset`) для соответствия стандартному
  iOS-spacing'у.

## See Also

- <doc:ViewController>
- <doc:NavigationController>
- <doc:Search>
- <doc:Glass>
- <doc:EdgeEffect>
- <doc:ContextMenu>
