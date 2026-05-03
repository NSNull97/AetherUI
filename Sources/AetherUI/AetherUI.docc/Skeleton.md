# Skeleton

Skeleton placeholder view с shimmer-анимацией для loading-состояний.
Включает специализированные подклассы для строк, блоков и кругов.

## Overview

AetherUI предоставляет skeleton-views для отображения loading-state'ов:

- ``AetherSkeletonView`` — базовый класс с shimmer-анимацией.
- ``AetherSkeletonLineView`` — горизонтальная строка фиксированной высоты.
- ``AetherSkeletonBlockView`` — прямоугольный блок с corner radius.
- ``AetherSkeletonCircleView`` — круг (для аватарок и иконок).

Все подклассы поддерживают темы `.light`, `.dark`, `.system` и
кастомную ``AetherSkeletonTheme``.

## Базовый шаблон

### Skeleton row для list item'а

```swift
class ChatItemSkeleton: UIView {
    private let avatar = AetherSkeletonCircleView(theme: .system)
    private let titleLine = AetherSkeletonLineView(theme: .system)
    private let subtitleLine = AetherSkeletonLineView(theme: .system)

    init() {
        super.init(frame: .zero)
        addSubview(avatar)
        addSubview(titleLine)
        addSubview(subtitleLine)

        avatar.startAnimating()
        titleLine.startAnimating()
        subtitleLine.startAnimating()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        avatar.frame = CGRect(x: 16, y: 12, width: 44, height: 44)
        titleLine.frame = CGRect(x: 70, y: 16, width: bounds.width - 86, height: 14)
        subtitleLine.frame = CGRect(x: 70, y: 36, width: bounds.width - 100, height: 12)
    }
}
```

## AetherSkeletonTheme

```swift
public struct AetherSkeletonTheme: Equatable {
    public let baseColor: UIColor              // основной цвет skeleton'а
    public let highlightColor: UIColor          // цвет shimmer-блика
    public let shimmerDuration: TimeInterval    // длительность одного цикла
    public let shimmerWidthFraction: CGFloat    // ширина блика как fraction width'а
}
```

### Built-in темы

```swift
AetherSkeletonTheme.light     // светлая
AetherSkeletonTheme.dark      // тёмная
AetherSkeletonTheme.system    // адаптивная (light/dark)
```

## AetherSkeletonView (базовый класс)

```swift
let skeleton = AetherSkeletonView(theme: .system)
skeleton.frame = CGRect(x: 0, y: 0, width: 200, height: 50)
view.addSubview(skeleton)

skeleton.isAnimating = true   // запуск shimmer
```

| Свойство | Тип | Назначение |
|---|---|---|
| `theme` | `AetherSkeletonTheme` | Тема (read-write). |
| `isAnimating` | `Bool` | Запуск/остановка shimmer (read-write). |

> Note: `startAnimating()` / `stopAnimating()` не предусмотрены —
> используйте `isAnimating` setter напрямую.

### Auto-pause при removeFromSuperview

При `willMove(toWindow:)` с `nil` shimmer-анимация автоматически
приостанавливается (для оптимизации); восстанавливается при
`didMoveToWindow` обратно в ненулевое window.

## AetherSkeletonLineView

Горизонтальная строка фиксированной высоты. По умолчанию используется
для placeholder'ов текстовых строк.

```swift
let line = AetherSkeletonLineView(theme: .system)
line.lineHeight = 14.0          // высота line (default 12pt)
line.isAnimating = true
view.addSubview(line)
```

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `lineHeight` | `CGFloat` | `12.0` | Высота line. |

`intrinsicContentSize.height` равен `lineHeight`. `intrinsicContentSize.width`
не определён — управляется родительским layout'ом.

## AetherSkeletonBlockView

Прямоугольный блок с настраиваемым corner radius. Используется для
placeholder'ов карточек, изображений, кнопок.

```swift
let block = AetherSkeletonBlockView(theme: .system)
block.cornerRadius = 12         // default 10pt
block.frame = CGRect(x: 16, y: 100, width: 200, height: 120)
block.isAnimating = true
view.addSubview(block)
```

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `cornerRadius` | `CGFloat` | `10.0` | Corner radius блока. |

## AetherSkeletonCircleView

Круг (corner radius = `min(width, height) / 2`). Используется для
placeholder'ов аватарок, иконок.

```swift
let circle = AetherSkeletonCircleView(theme: .system)
circle.frame = CGRect(x: 16, y: 12, width: 44, height: 44)
circle.isAnimating = true
view.addSubview(circle)
```

## API

### ``AetherSkeletonView``

| Свойство / метод | Назначение |
|---|---|
| `init(theme:)` | Создание (default theme = `.light`). |
| `theme` | Тема (read-write). |
| `isAnimating` | Управление shimmer-анимацией. |

### ``AetherSkeletonLineView``

См. таблицу свойств выше.

### ``AetherSkeletonBlockView``

См. таблицу свойств выше.

### ``AetherSkeletonCircleView``

См. описание выше (без дополнительных свойств).

### ``AetherSkeletonTheme``

См. таблицу свойств выше.

## Edge cases

- **Skeleton view вне window.** Shimmer автоматически pauses при
  `willMove(toWindow: nil)` для оптимизации. Не требует явного
  `isAnimating = false`.
- **Theme смена во время анимации.** `theme` setter применяется
  immediately; in-flight shimmer продолжается с новыми цветами без
  перезапуска цикла.
- **Trait collection change.** При смене dark/light system mode
  (`traitCollectionDidChange`) `system` тема автоматически переключается.
  Manually-set `light`/`dark` темы остаются неизменными.
- **`shimmerDuration = 0`.** Shimmer не анимируется; skeleton отображается
  статически (только `baseColor`).

## See Also

- <doc:ContentUnavailable>
- <doc:ListView>
