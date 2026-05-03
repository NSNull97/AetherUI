# Toolbar

Bottom toolbar и плавающий toolbar в стиле iOS 26 Safari/Mail/Messages:
``AetherToolbarView`` (классический bottom toolbar) и
``AetherFloatingToolbarView`` (плавающий glass-pill).

## Overview

AetherUI предоставляет два toolbar-компонента:

- ``AetherToolbarView`` — классический bottom-anchored toolbar с тремя
  слотами (left, middle, right). Используется для контента редактирования
  (например, mail compose).
- ``AetherFloatingToolbarView`` — плавающий glass-pill в нижней части
  экрана с горизонтальным layout'ом segments. Используется как
  ``AetherViewController/floatingToolbar``.

## AetherToolbarView

Bottom toolbar с тремя слотами:

```swift
let theme = AetherToolbarTheme.light
let toolbar = AetherToolbar(
    leftAction: AetherToolbarAction(title: "Cancel"),
    middleAction: nil,
    rightAction: AetherToolbarAction(title: "Send", color: .accent)
)

let toolbarView = AetherToolbarView(theme: theme, toolbar: toolbar)
toolbarView.leftTapped = { /* ... */ }
toolbarView.rightTapped = { /* ... */ }
view.addSubview(toolbarView)
```

### AetherToolbar

```swift
public struct AetherToolbar: Equatable {
    public let leftAction: AetherToolbarAction?
    public let middleAction: AetherToolbarAction?
    public let rightAction: AetherToolbarAction?
}
```

### AetherToolbarAction

```swift
public struct AetherToolbarAction: Equatable {
    public enum Color: Equatable {
        case accent
        case destructive
        case disabled
    }

    public let title: String
    public let isEnabled: Bool
    public let color: Color
}
```

### AetherToolbarTheme

```swift
public struct AetherToolbarTheme: Equatable {
    public let backgroundColor: UIColor
    public let separatorColor: UIColor
    public let textColor: UIColor
    public let accentColor: UIColor
    public let destructiveColor: UIColor
    public let disabledColor: UIColor
    public let font: UIFont
}
```

#### Built-in темы

```swift
AetherToolbarTheme.light   // светлая
AetherToolbarTheme.dark    // тёмная
```

### Свойства view

| Свойство | Тип | Назначение |
|---|---|---|
| `theme` | `AetherToolbarTheme` | Тема (read-write). |
| `toolbar` | `AetherToolbar` | Конфигурация (read-write). |
| `displayTopSeparator` | `Bool` | Top separator (default `true`). |
| `leftTapped` / `middleTapped` / `rightTapped` | `() -> Void` | Tap callbacks. |

### preferredHeight

```swift
let height = AetherToolbarView.preferredHeight(bottomSafeInset: view.safeAreaInsets.bottom)
```

Возвращает предпочтительную высоту toolbar'а с учётом safe area.

## AetherFloatingToolbarView

Плавающий glass-pill с горизонтальным layout'ом segments:

```swift
let toolbar = AetherFloatingToolbarView()
toolbar.segments = [
    .button(.init(icon: UIImage(systemName: "square.and.arrow.up"), action: { /* ... */ })),
    .flexibleSpace,
    .button(.init(icon: UIImage(systemName: "trash"), action: { /* ... */ }))
]

// Через ViewController:
floatingToolbar = toolbar
```

При установке ``AetherViewController/floatingToolbar`` toolbar
автоматически:

- Anchored выше tab bar pill'а или над home indicator.
- Side margin 12pt по умолчанию.
- Bottom gap 12pt над chrome.
- `additionalSafeAreaInsets.bottom` обновляется на toolbar height,
  что обеспечивает scroll content прохождение под toolbar'ом.

### Segment

```swift
public enum Segment {
    case button(Button)
    case flexibleSpace
    case search(SearchConfig)
    // ... и др.
}
```

#### Button

```swift
public struct Button {
    public let icon: UIImage?
    public let title: String?
    public let action: () -> Void
    // ...
}
```

#### SearchConfig

```swift
public struct SearchConfig {
    public let placeholder: String
    public let onTap: () -> Void
    // ...
}
```

### Theme

```swift
public struct Theme {
    // backgroundColor, contentColor, accentColor, font, ...
}
```

#### Built-in темы

```swift
AetherFloatingToolbarView.Theme.light
AetherFloatingToolbarView.Theme.dark
```

### Свойства

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `segments` | `[Segment]` | `[]` | Список segments. |
| `theme` | `Theme` | `.light` | Тема. |
| `pillHeight` | `CGFloat` | `49.0` | Высота pill'а. |
| `segmentSpacing` | `CGFloat` | `8.0` | Gap между segments. |
| `sideInset` | `CGFloat` | `12.0` | Side inset pill'а. |
| `pillButtonWidth` | `CGFloat` | `49.0` | Ширина button-segment'а. |
| `defaultHeight` (static) | `CGFloat` | `49.0` | Default toolbar height. |

## Интеграция с ViewController

### AetherFloatingToolbar

```swift
class HomeController: AetherViewController {
    override init() {
        super.init(navigationBarPresentationData: .liquidGlass())

        let toolbar = AetherFloatingToolbarView()
        toolbar.segments = [
            .button(.init(icon: UIImage(systemName: "plus"), action: { [weak self] in
                self?.add()
            })),
            .flexibleSpace,
            .search(.init(placeholder: "Search", onTap: { [weak self] in
                self?.openSearch()
            }))
        ]
        floatingToolbar = toolbar
    }
    required init?(coder: NSCoder) { fatalError() }
}
```

### Кастомная высота

Override ``AetherViewController/floatingToolbarHeight`` для toolbar'а с
нестандартной высотой:

```swift
override var floatingToolbarHeight: CGFloat {
    return 60.0   // вместо default 49.0
}
```

## API

### ``AetherToolbarView``

| Свойство / метод | Назначение |
|---|---|
| `init(theme:toolbar:)` | Создание. |
| `theme` / `toolbar` | Конфигурация (read-write). |
| `displayTopSeparator` | Top separator. |
| `leftTapped` / `middleTapped` / `rightTapped` | Tap callbacks. |
| `preferredHeight(bottomSafeInset:)` (static) | Preferred высота. |

### ``AetherToolbar``, ``AetherToolbarAction``, ``AetherToolbarTheme``

См. структуры выше.

### ``AetherFloatingToolbarView``

| Свойство / метод | Назначение |
|---|---|
| `init(segments:theme:)` | Создание. |
| `segments` | Segments (read-write). |
| `theme` | Тема. |
| `pillHeight` / `segmentSpacing` / `sideInset` / `pillButtonWidth` | Layout parameters. |
| `defaultHeight` (static) | 49.0. |

### ``AetherFloatingToolbarView/Segment``, ``Button``, ``SearchConfig``, ``Theme``

См. структуры выше.

## Edge cases

- **Толщина pill'а override через `pillHeight`.** При изменении
  `pillHeight` обязательно override
  ``AetherViewController/floatingToolbarHeight`` — иначе toolbar будет
  возвращать default (49pt) для расчёта `additionalSafeAreaInsets.bottom`,
  что приведёт к рассогласованию.
- **Segment `flexibleSpace`.** Распределяется equal-width между
  фиксированными segments. При наличии нескольких `flexibleSpace`'ов
  каждый получает равную долю оставшегося пространства.
- **Toolbar overflow.** При суммарной ширине segments больше
  available pill width segments truncate'ятся справа. Используйте меньше
  segments или меньший `pillButtonWidth`.

## See Also

- <doc:ViewController>
- <doc:NavigationBar>
- <doc:Glass>
- <doc:TabBar>
