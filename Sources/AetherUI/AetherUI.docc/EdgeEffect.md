# EdgeEffect

Frost-зона на границе chrome (nav bar, tab bar, search-pill), в которой
scroll-контент плавно растворяется. Использует variable blur и градиент
opacity для создания «дыхания» glass-поверхности.

## Overview

Edge effect — визуальный эффект, расположенный между chrome
(navigation bar, tab bar, search-pill) и scroll-контентом. Реализует
плавный переход opacity и blur от полностью frosted-зоны (примыкающей к
chrome) до прозрачной/несфокусированной зоны (граничащей с контентом).

Основные классы:

- ``EdgeEffectView`` — основной view edge-эффекта. Используется внутри
  nav bar, tab bar, search-controller (bottom mode).
- ``EdgeEffectAttachment`` — декларативная конфигурация edge-эффекта,
  применяемая к UIView через extension.
- ``VariableBlurEffect`` — низкоуровневая реализация variable blur с
  градиентом radius'а.
- ``VariableBlurView`` — UIView-обёртка над VariableBlurEffect.

> Tip: В большинстве случаев edge effect не требует прямой работы — он
> автоматически создаётся nav bar'ом, tab bar'ом и search-controller'ом
> на основе соответствующих theme-параметров (`edgeEffectAlpha`,
> `edgeEffectBlurRadiusAtEdge`, `edgeEffectBlurRadiusAtFade`,
> `edgeEffectColor`).

## EdgeEffectView

### Создание и конфигурация

```swift
let edge = EdgeEffectView()
edge.isUserInteractionEnabled = false
view.addSubview(edge)

edge.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 100)
edge.update(
    content: .systemBackground,         // цвет frost
    blur: true,                          // включение blur
    alpha: 0.75,                         // opacity при максимуме
    rect: CGRect(origin: .zero, size: edge.frame.size),
    edge: .top,                          // .top | .bottom | .left | .right
    edgeSize: 48.0,                      // высота fade-зоны
    blurRadiusAtEdge: 3.0,               // blur у границы chrome
    blurRadiusAtFade: 0.0,               // blur у границы контента
    transition: .immediate
)
```

### Edge

| Edge | Описание |
|---|---|
| `.top` | Frost у верхней границы (для nav bar). |
| `.bottom` | Frost у нижней границы (для tab bar, bottom search). |
| `.left` | Frost у левой границы. |
| `.right` | Frost у правой границы. |

### Параметры update

| Параметр | Тип | Назначение |
|---|---|---|
| `content` | `UIColor` | Цвет frost-tint. |
| `blur` | `Bool` | Включение blur-эффекта. |
| `alpha` | `CGFloat` | Максимальная opacity tint'а. |
| `rect` | `CGRect` | Область рендеринга. |
| `edge` | `Edge` | Сторона chrome. |
| `edgeSize` | `CGFloat` | Высота fade-зоны (от полного frost до прозрачности). |
| `blurRadiusAtEdge` | `CGFloat` | Blur radius у границы chrome (полный frost). |
| `blurRadiusAtFade` | `CGFloat` | Blur radius у границы контента. |
| `transition` | `ContainedViewLayoutTransition` | Анимация изменения. |

### updateColor

Изменение только цвета без full re-update:

```swift
edge.updateColor(color: .systemGray6, transition: .animated(duration: 0.3, curve: .easeInOut))
```

### generateEdgeGradient

Утилитарный static-метод для генерации gradient-image:

```swift
let image = EdgeEffectView.generateEdgeGradient(
    baseHeight: 48,
    isInverted: false,
    extendsInwards: false
)
```

### generateEdgeGradientData

Генерация gradient data для прямого использования в
``VariableBlurEffect``:

```swift
let gradient = EdgeEffectView.generateEdgeGradientData(baseHeight: 48)
```

## Uniform vs Variable blur

AetherUI поддерживает два режима blur:

| Режим | Условие | Поведение |
|---|---|---|
| **Uniform** | `blurRadiusAtEdge == blurRadiusAtFade` | Backdrop blur на всей области с одинаковым radius'ом. Gradient мaska применяется как opacity. |
| **Variable** | `blurRadiusAtEdge != blurRadiusAtFade` | Per-pixel blur radius scale через gradient. Backdrop sample может пройти не-blurred через зону `radius ~ 0`. |

> Important: На некоторых сценариях (modal sheet detent change) variable
> blur приводит к visible gap'у между chrome и контентом, поскольку
> backdrop sample при `radius ~ 0` пропускает presenter dim. Решение —
> использовать uniform blur (одинаковый radius) или принимать
> `blurRadiusAtFade > 0`.

## EdgeEffectAttachment

Декларативная конфигурация edge-эффекта:

```swift
let attachment = EdgeEffectAttachment(
    edge: .bottom,                      // .top | .bottom | .left | .right
    thickness: 60,                       // полная высота attachment'а
    fadeHeight: 48,                      // fade-зона
    tintColor: .systemBackground,
    tintAlpha: 0.75,
    blurRadius: 3.0
)

view.applyEdgeEffect(attachment)
```

`applyEdgeEffect` — extension на `UIView`. Применяет attachment как
subview, корректно reapply'я его при изменении layout'а.

### Параметры

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `edge` | `Edge` | — | Сторона attachment'а. |
| `thickness` | `CGFloat` | — | Полная высота. |
| `fadeHeight` | `CGFloat` | `thickness` | Высота fade-зоны. |
| `tintColor` | `UIColor?` | `nil` | Цвет tint (nil → systemBackground). |
| `tintAlpha` | `CGFloat` | `0.75` | Opacity tint'а. |
| `blurRadius` | `CGFloat` | `3.0` | Blur radius (uniform). |
| `blurRadiusAtEdge` | `CGFloat` | = `blurRadius` | Blur у chrome border. |
| `blurRadiusAtFade` | `CGFloat` | = `blurRadius` | Blur у content border. |

## VariableBlurEffect

Низкоуровневая реализация variable blur. Используется внутри
``EdgeEffectView`` для случаев `blurRadiusAtEdge != blurRadiusAtFade`:

```swift
let layer = CALayer()
layer.frame = CGRect(x: 0, y: 0, width: 200, height: 200)

let effect = VariableBlurEffect(layer: layer, isTransparent: false, maxBlurRadius: 20.0)

let gradient = EdgeEffectView.generateEdgeGradientData(baseHeight: 48)
effect.update(
    gradient: gradient,
    placement: VariableBlurEffect.Placement(edge: .top, thickness: 60, fadeHeight: 48),
    transition: .immediate
)
```

### Параметры init

| Параметр | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `layer` | `CALayer` | — | Целевой layer, к которому применяется эффект. |
| `isTransparent` | `Bool` | `false` | Прозрачный backdrop без tint. |
| `maxBlurRadius` | `CGFloat` | `20.0` | Максимальный blur radius. |

## VariableBlurView

UIView-обёртка над VariableBlurEffect для прямого использования в
view-иерархии:

```swift
let blurView = VariableBlurView(maxBlurRadius: 20.0)
blurView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 60)
view.addSubview(blurView)

let gradient = EdgeEffectView.generateEdgeGradientData(baseHeight: 48)
blurView.update(
    gradient: gradient,
    placement: VariableBlurEffect.Placement(edge: .top, thickness: 60, fadeHeight: 48),
    transition: .immediate
)
```

## Использование в фреймворке

Edge effect автоматически создаётся в следующих компонентах:

### NavigationBarImpl

При style `.glass` создаётся `edgeEffectView` поверх nav bar:

```swift
NavigationBarTheme(
    edgeEffectColor: .systemBackground,    // цвет
    edgeEffectAlpha: 0.85,                 // opacity
    edgeEffectBlurRadiusAtEdge: 3.0,       // blur у status bar
    edgeEffectBlurRadiusAtFade: 0.0        // blur у контента
)
```

Frame edge-effect'а расширен относительно nav bar:
- `topInset = 8.0` — bleed выше nav bar для покрытия status bar.
- `bottomBleed = 4.0` — bleed ниже nav bar.
- `bandShift = 12.0` — дополнительное смещение band вверх для покрытия
  «просвета» между nav bar и status bar.

Подробнее — <doc:NavigationBar>.

### TabBarView

При style `.liquidGlass` создаётся `edgeEffectView` под tab bar:

```swift
TabBarView.Theme(
    edgeEffectAlpha: 0.65,
    edgeEffectBlurRadiusAtEdge: 3.0,
    edgeEffectBlurRadiusAtFade: 3.0,
    edgeEffectTintColor: nil   // nil → tabBarBackgroundColor
)
```

`bottomAccessoryReservedHeight` — дополнительная вертикальная область,
которую edge effect должен покрыть выше tab bar (для accessory pill'а).

Подробнее — <doc:TabBar>.

### AetherSearchController (bottom mode)

При placement `.bottom` создаётся `bottomEdgeEffect` под bottom-pill'ом.
Цвет/blur автоматически согласуются с nav bar темой.

Подробнее — <doc:Search>.

## Сценарии настройки

### Усиленный frost (для контрастных фонов)

```swift
NavigationBarTheme(
    edgeEffectAlpha: 0.95,
    edgeEffectBlurRadiusAtEdge: 6.0,
    edgeEffectBlurRadiusAtFade: 0.0
)
```

### Минимальный frost (для слабоконтрастных фонов)

```swift
NavigationBarTheme(
    edgeEffectAlpha: 0.30,
    edgeEffectBlurRadiusAtEdge: 1.0,
    edgeEffectBlurRadiusAtFade: 0.0
)
```

### Полное отключение

```swift
NavigationBarTheme(
    edgeEffectAlpha: 0.0
)

// Или:
NavigationBarTheme(
    edgeEffectColor: UIColor.clear   // alpha == 0 → edge.isHidden = true
)
```

### Custom tint

```swift
TabBarView.Theme(
    edgeEffectTintColor: UIColor.systemBlue.withAlphaComponent(0.3)
)
```

## API сводка

### ``EdgeEffectView``

| Свойство / метод | Назначение |
|---|---|
| `init(frame:)` | Создание view. |
| `update(content:blur:alpha:rect:edge:edgeSize:blurRadiusAtEdge:blurRadiusAtFade:transition:)` | Полное обновление. |
| `updateColor(color:transition:)` | Изменение только цвета. |
| `generateEdgeGradient(baseHeight:isInverted:extendsInwards:)` | Static-генерация gradient image. |
| `generateEdgeGradientData(baseHeight:)` | Static-генерация gradient data. |

### ``EdgeEffectAttachment``

См. таблицу свойств выше.

### ``VariableBlurEffect``

| Свойство / метод | Назначение |
|---|---|
| `init(layer:isTransparent:maxBlurRadius:)` | Создание эффекта. |
| `update(gradient:placement:transition:)` | Обновление параметров. |

### ``VariableBlurView``

| Свойство / метод | Назначение |
|---|---|
| `init(maxBlurRadius:)` | Создание view. |
| `update(gradient:placement:transition:)` | Обновление параметров. |

## Edge cases

- **Variable blur и presenter dim.** При `blurRadiusAtFade ~ 0` пиксель
  на content border передаёт unfiltered backdrop sample, что может
  показать presenter dim (для модальных sheet'ов). Решение —
  использовать uniform blur (`blurRadiusAtEdge == blurRadiusAtFade`)
  или установить `blurRadiusAtFade > 0`.
- **Frame snap при анимации.** При `.animated` transition frame
  edge-effect view интерполируется, что приводит к visible gap между
  chrome border и edge-effect. ``NavigationBarImpl`` решает это через
  принудительный `.immediate` для frame setter'ов внутри
  `edgeEffectView.update(...)`, оставляя анимированными только
  visual properties (color, blur radius).
- **Edge effect рендерится поверх контента.** EdgeEffectView должен быть
  размещён в view-иерархии **выше** scroll content, но **ниже** chrome
  (nav bar / tab bar). При неправильном z-order frost будет полностью
  скрывать chrome или прозрачно пропускать контент.
- **Отсутствие frost на iOS < 26.** Variable blur использует
  `CABackdropLayer` через KVC, который не доступен на старых iOS.
  Fallback — uniform `UIBlurEffect` с tinted overlay.

## See Also

- <doc:NavigationBar>
- <doc:TabBar>
- <doc:Glass>
- <doc:Search>
