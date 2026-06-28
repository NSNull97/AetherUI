# NavigationBar

Per-screen navigation bar с glass-фоном, edge-эффектом, accessory-зонами,
поддержкой стандартного `UINavigationItem` и custom titleView.

## Overview

Каждый ``AetherViewController`` владеет собственным ``NavigationBarView`` —
протоколом, реализуемым классом ``NavigationBarImpl``. Бар размещается
внутри `view` контроллера и перемещается с ним при push/pop, что
обеспечивает glass-morph переход между двумя барами при анимации.

Бар поддерживает:

- Стандартный `UINavigationItem` с `title`, `titleView`, `leftBarButtonItems`,
  `rightBarButtonItems`.
- Тему ``NavigationBarTheme`` с двумя стилями: `.legacy` (UIKit-style) и
  `.glass` (iOS 26 liquid glass).
- Edge-эффект: scroll-content frost на границе бара, исчезающий при
  скролле к началу контента.
- Accessory-контент через ``AetherViewController/topBarAccessory`` —
  ``NavigationBarContentView`` под title row (`.expansion`) или вместо
  него (`.replacement`).
- Glass-кнопки в едином `GlassControlGroup`-контейнере с автоматическим
  морфом при изменении состава.
- Контекстное меню на bar button через
  ``UIBarButtonItem/contextMenuItemsProvider``.

> Tip: Бар автоматически создаётся при инициализации ``AetherViewController`` с
> ненулевым `navigationBarPresentationData`. Прямой доступ к
> ``AetherViewController/navigationBarView`` требуется редко: типовая
> конфигурация выполняется через `navigationItem` (стандартный UIKit API)
> и через свойства ``AetherViewController``.

## Создание бара

Бар создаётся внутри `super.init(navigationBarPresentationData:)`:

```swift
final class HomeController: AetherViewController {
    init() {
        super.init(navigationBarPresentationData: NavigationBarPresentationData(
            theme: NavigationBarTheme.liquidGlass()
        ))
        navigationItem.title = "Главная"
    }
    required init?(coder: NSCoder) { fatalError() }
}
```

Передача `nil` в `navigationBarPresentationData` создаёт контроллер без
бара (для fullscreen-экранов).

## NavigationBarTheme

Тема бара полностью описывается классом ``NavigationBarTheme``. Все
свойства иммутабельны после инициализации; для динамической смены —
``AetherViewController/setNavigationBarPresentationData(_:animated:)``.

### Полный список свойств

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `overallDarkAppearance` | `Bool` | `false` | Принудительно тёмное оформление glass-эффекта. Если `false`, тёмный режим определяется по `traitCollection.userInterfaceStyle`. |
| `buttonColor` | `UIColor` | `.systemBlue` | Tint бар-кнопок. |
| `disabledButtonColor` | `UIColor` | `.gray` | Tint disabled-кнопок. |
| `primaryTextColor` | `UIColor` | `.black` | Цвет title text. |
| `backgroundColor` | `UIColor` | `.white` | Фон бара (используется в `.legacy` стиле). |
| `opaqueBackgroundColor` | `UIColor` | = `backgroundColor` | Непрозрачный fallback для случаев, когда blur недоступен. |
| `enableBackgroundBlur` | `Bool` | `true` | Включение системного blur за фоном (`.legacy` стиль). |
| `separatorColor` | `UIColor` | `(0,0,0,0.3)` | Цвет нижнего separator-strip. |
| `badgeBackgroundColor` | `UIColor` | `.systemRed` | Цвет круга badge на bar button. |
| `badgeStrokeColor` | `UIColor` | `.white` | Цвет обводки badge. |
| `badgeTextColor` | `UIColor` | `.white` | Цвет текста badge. |
| `edgeEffectColor` | `UIColor?` | `nil` | Цвет scroll-edge frost. `nil` — использует `opaqueBackgroundColor`. |
| `accentButtonColor` | `UIColor` | `.systemBlue` | Цвет accent-кнопок. |
| `accentForegroundColor` | `UIColor` | `.white` | Цвет foreground accent-кнопок. |
| `style` | ``NavigationBarStyle`` | `.legacy` | `.legacy` (UIKit) или `.glass` (iOS 26). |
| `glassStyle` | ``NavigationBarGlassStyle`` | `.default` | `.default` (panel tint) или `.clear` (без tint). |
| `edgeEffectAlpha` | `CGFloat` | `0.75` | Opacity scroll-edge frost. |
| `edgeEffectBlurRadiusAtEdge` | `CGFloat` | `2.0` | Blur radius на границе экрана. |
| `edgeEffectBlurRadiusAtFade` | `CGFloat` | `0.0` | Blur radius на границе с контентом. |
| `defaultContentHeight` | `CGFloat` | `60.0` | Высота content-area (область кнопок и title). |

### Preset для liquid glass

Для типового iOS 26 glass-look используется factory:

```swift
let theme = NavigationBarTheme.liquidGlass(
    overallDarkAppearance: false,
    buttonColor: .label,
    primaryTextColor: .label,
    accentButtonColor: .systemBlue,
    accentForegroundColor: .white,
    glassStyle: .default            // или .clear
)
```

Эквивалент:

```swift
let theme = NavigationBarTheme(
    overallDarkAppearance: false,
    buttonColor: .label,
    primaryTextColor: .label,
    backgroundColor: .clear,
    opaqueBackgroundColor: .clear,
    enableBackgroundBlur: true,
    separatorColor: .clear,
    edgeEffectColor: .systemBackground,
    style: .glass,
    glassStyle: .default,
    edgeEffectAlpha: 0.75
)
```

### Стили

#### `.legacy`

Классический UIKit-style: непрозрачный фон, separator-strip снизу,
no-glass кнопки. Подходит для приложений, которым нужно сохранить
deployment target ниже iOS 26 без glass-эффектов.

```swift
NavigationBarTheme(
    backgroundColor: .systemBackground,
    enableBackgroundBlur: true,
    style: .legacy
)
```

#### `.glass`

iOS 26 liquid glass: прозрачный фон с системным `UIGlassEffect`, кнопки
в едином `GlassControlGroup`-капсуле с автоматическим морфом.

| `glassStyle` | Описание |
|---|---|
| `.default` | Panel-tinted glass (заметная подложка для читаемости поверх любого фона). |
| `.clear` | Без panel tint, только системный glass refraction. Подходит для ярких/насыщенных фонов. |

> Note: На iOS < 26 `.glass` стиль работает с fallback-реализацией
> (`UIVisualEffectView` с тонированными слоями); морф glass-кнопок
> сохраняется, но без системного refraction-эффекта.

### Динамическая смена темы

```swift
let darkTheme = NavigationBarPresentationData(
    theme: NavigationBarTheme.liquidGlass(overallDarkAppearance: true)
)
viewController.setNavigationBarPresentationData(darkTheme, animated: true)
```

Также доступны withUpdated-методы для частичных изменений:

```swift
let updated = currentTheme
    .withUpdatedBackgroundColor(.systemGray6)
    .withUpdatedSeparatorColor(.clear)
```

## Edge effect

Edge effect — frost-зона на верхней границе бара, в которой scroll-контент
плавно растворяется. Управляется через свойства темы:

```swift
NavigationBarTheme(
    edgeEffectColor: .systemBackground,    // цвет (nil → opaqueBackgroundColor)
    edgeEffectAlpha: 0.85,                 // opacity (0…1)
    edgeEffectBlurRadiusAtEdge: 3.0,       // blur у верхней границы
    edgeEffectBlurRadiusAtFade: 0.0        // blur у нижней границы (контент)
)
```

Полное отключение:

```swift
edgeEffectAlpha: 0.0
```

Подробнее об архитектуре edge-effect — <doc:EdgeEffect>.

## Title

### Стандартный текст

```swift
navigationItem.title = "Профиль"
```

Шрифт фиксирован: `UIFont.systemFont(ofSize: 17.0, weight: .semibold)`.
Цвет — ``NavigationBarTheme/primaryTextColor``.

### Custom titleView

```swift
let titleView = ProfileTitleView(name: "Анна", subtitle: "online")
navigationItem.titleView = titleView
```

Бар автоматически измеряет естественную высоту titleView и расширяет
content-area, если она превышает `defaultContentHeight`. Используется
последовательность:

1. `systemLayoutSizeFitting` (Auto Layout) — для wrapper-views без
   intrinsic size (HypeUI `.padding()`, `GlassBackgroundView`).
2. `sizeThatFits` — fallback для классического sizing.
3. `bounds.size` — если первые два возвращают ноль.
4. `intrinsicContentSize` — финальный fallback.

После мутаций titleView, изменяющих его высоту, вызывается:

```swift
viewController.navigationBarView?.invalidateTitleViewLayout()
```

Это сбрасывает кэшированную высоту и инициирует повторное измерение.

## Bar buttons

### Стандартные UIBarButtonItem

```swift
navigationItem.rightBarButtonItem = UIBarButtonItem(
    image: UIImage(systemName: "ellipsis"),
    style: .plain, target: self, action: #selector(menu)
)

navigationItem.leftBarButtonItems = [
    UIBarButtonItem(image: UIImage(systemName: "plus"), ...),
    UIBarButtonItem(title: "Edit", style: .plain, ...)
]
```

В `.glass` стиле кнопки автоматически объединяются в единый
``GlassControlGroup``-капсулы (левый и правый), с межкнопочным
spacing'ом 6pt и pill cornerRadius. При изменении состава кнопок
капсула выполняет морф (fade old / fade new) длительностью 0.2с.

### Кастомный customView

Если bar button содержит `customView`, бар проверяет два сценария:

1. **Все кнопки имеют `customView`** и нет авто-back-кнопки — кнопки
   размещаются непосредственно в контейнере (без обёртки в
   `GlassControlGroup`). Это предотвращает double-glass проблему,
   когда `GlassButton` внутри group отрисовывается с искажённым tint.
2. **Смешанный набор** — все кнопки оборачиваются в `GlassControlGroup`,
   `customView` отображается через `Item.Content.customView`.

```swift
let customButton = GlassBarButtonView(
    icon: UIImage(systemName: "bell"),
    title: nil,
    state: .glass
)
navigationItem.rightBarButtonItem = UIBarButtonItem(customView: customButton)
```

### Context menu на bar button

AetherUI добавляет к `UIBarButtonItem` свойство
``UIBarButtonItem/contextMenuItemsProvider``, которое позволяет
открыть ``AetherContextMenuController`` при тапе:

```swift
navigationItem.rightBarButtonItem = UIBarButtonItem(
    title: nil,
    image: UIImage(systemName: "ellipsis"),
    contextMenuItemsProvider: {
        return [
            ContextMenuItem.action(.init(text: "Поделиться",
                                         icon: UIImage(systemName: "square.and.arrow.up"),
                                         action: { /* ... */ })),
            ContextMenuItem.action(.init(text: "Удалить",
                                         icon: UIImage(systemName: "trash"),
                                         isDestructive: true,
                                         action: { /* ... */ }))
        ]
    }
)
```

При тапе menu открывается анкорным к капсуле кнопки. На iOS 14+ trigger
срабатывает по `.touchDown` (мгновенно), что соответствует поведению
системного `UIButton.menu` с `showsMenuAsPrimaryAction = true`. На iOS 13
fallback на `.touchUpInside`.

> Note: Предоставление обоих параметров — `primaryAction` и
> `contextMenuItemsProvider` — допустимо. `primaryAction` сохраняется на
> bar item для поддержки accessibility и menu-builder сценариев, однако
> tap dispatcher routes через menu provider.

## Top-bar accessory

Под title row может быть размещён произвольный
``NavigationBarContentView`` через ``AetherViewController/topBarAccessory``:

```swift
final class FilterChipsBar: NavigationBarContentView {
    private let scrollView = UIScrollView()
    // ...

    override var nominalHeight: CGFloat { 44.0 }
    override var mode: NavigationBarContentMode { .expansion }

    override func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat,
                               transition: ContainedViewLayoutTransition) -> CGSize {
        // Раскладка subview-объектов в области (size.width × nominalHeight).
        return size
    }
}

// В ViewController:
topBarAccessory = FilterChipsBar()
setTopBarAccessory(FilterChipsBar(), animated: true)
```

Direct assignment применяется мгновенно. `setTopBarAccessory(_:animated:)`
использует внутренний blur-crossfade и фиксирует frame accessory до
визуального fade, чтобы появление/исчезновение не давало скачка геометрии.

### Mode

| Значение | Поведение |
|---|---|
| `.expansion` | Accessory размещается **под** title row. Бар расширяется на `nominalHeight` accessory. |
| `.replacement` | Accessory **заменяет** title row (title и кнопки скрываются). |

### Динамическое изменение размера

Когда subview accessory меняют свой sizing (например, добавление chip'а
в фильтр-бар), вызывается:

```swift
filterChipsBar.invalidateLayout(transition: .animated(duration: 0.3, curve: .spring))
```

Это инициирует повторный layout-pass с новой `nominalHeight`.

## AetherStackedBarContent

Для composition нескольких ``NavigationBarContentView`` в единую
expansion-зону используется ``AetherStackedBarContent``:

```swift
let searchPill = mySearchBarContent     // NavigationBarContentView
let filterBar = myFilterChipsBar        // NavigationBarContentView

let stacked = AetherStackedBarContent(views: [searchPill, filterBar])
viewController.topBarAccessory = stacked
```

Контент размещается вертикально в порядке передачи; общая
`nominalHeight` равна сумме `nominalHeight` всех children.

> Note: При установке ``AetherViewController/searchController`` стэкинг
> выполняется автоматически: search pill размещается сверху, accessory
> снизу. Ручное создание `AetherStackedBarContent` для этого случая не
> требуется.

## Поиск (Search)

Glass-pill поиска внутри nav bar:

```swift
let search = AetherSearchController()
search.placeholder = "Поиск"
search.delegate = self
viewController.searchController = search
```

При активации поиска `setSearchMode(true, animated:)` скрывает title row
и кнопки через alpha, оставляя только search pill в title-position.
Подробнее — <doc:Search>.

## Скрытие и показ

```swift
viewController.displayNavigationBar = false   // бар уезжает за верхний край
viewController.displayNavigationBar = true    // возвращается
```

Прямое управление через бар:

```swift
viewController.navigationBarView?.setHidden(true, animated: true)
```

Поведение: при `false` бар получает `frame.origin.y = -frame.height`,
вынося его за пределы экрана. `cleanNavigationHeight` возвращает 0, что
позволяет контенту заполнить освободившееся пространство.

## Background alpha

Для частичного скрытия фона (например, при scroll-to-top индикации):

```swift
viewController.navigationBarView?.updateBackgroundAlpha(
    0.5, transition: .animated(duration: 0.2, curve: .easeInOut)
)
```

В `.glass` стиле метод не имеет эффекта (всегда `0`, поскольку фон
прозрачный по дизайну).

## Passthrough touches

Для бар, который должен пропускать тапы в content view (за исключением
кнопок и title):

```swift
viewController.navigationBarView?.passthroughTouches = true
```

При активации `hitTest` возвращает `nil` для тапов вне интерактивных
элементов.

## API

### ``NavigationBarTheme``

См. таблицу свойств выше. Конструктор принимает все параметры с
defaults; factory `liquidGlass(...)` — preset для типового использования.

### ``NavigationBarPresentationData``

| Свойство | Тип | Назначение |
|---|---|---|
| `theme` | `NavigationBarTheme` | Тема бара. |
| `strings` | `NavigationBarStrings` | Локализованные строки (`back`, `close`). |

### ``NavigationBarView`` (протокол)

| Свойство / метод | Назначение |
|---|---|
| `item` | Текущий `UINavigationItem`. |
| `previousItem` | Контекст для back-кнопки: `.item(navItem)` или `.close`. |
| `enableAutomaticBackButton` | Управление авто-генерацией back-кнопки. |
| `contentView` | Текущий accessory `NavigationBarContentView`. |
| `presentationData` | Read-only доступ к теме (для accessory views). |
| `setContentView(_:animated:)` | Установка accessory с blur-crossfade после фиксации финального frame. |
| `setHidden(_:animated:)` | Скрытие/показ. |
| `setSearchMode(_:animated:)` | Переключение в search mode. |
| `updateBackgroundAlpha(_:transition:)` | Частичное скрытие фона. |
| `updatePresentationData(_:transition:)` | Динамическая смена темы. |
| `executeBack()` | Программный triggering back-action. |
| `passthroughTouches` | Пропускание тапов в content view. |
| `intrinsicCanTransitionInline` | Разрешение inline-перехода между двумя барами. |
| `layoutSuspended` | Блокировка layout-pass'ов (при batched-updates). |

### ``NavigationBarContentView`` (базовый класс accessory)

| Свойство / метод | Назначение |
|---|---|
| `nominalHeight` | Естественная высота. Override для custom accessory. |
| `height` | Текущая высота (по умолчанию = `nominalHeight`). |
| `clippedHeight` | Высота с учётом clipping. |
| `mode` | `.replacement` (заменяет title row) или `.expansion` (под title row). |
| `updateLayout(size:leftInset:rightInset:transition:)` | Раскладка subview-объектов. Override для custom accessory. |
| `invalidateLayout(transition:)` | Запрос re-layout у hosting бара после изменения размера. |

### ``AetherStackedBarContent``

| Свойство / метод | Назначение |
|---|---|
| `init(views:)` | Создание с массивом children. |
| `views` | Read-only список children. |

## Edge cases

- **Title text не отображается при custom titleView.** При установке
  `navigationItem.titleView` стандартный `titleLabel` скрывается (`isHidden = true`).
  Текст из `navigationItem.title` игнорируется.
- **Clipping в `.glass` стиле.** В `.glass` стиле `clippingView.clipsToBounds = false`,
  что позволяет glass-кнопкам выходить за границы бара. В `.legacy`
  стиле включается clipping для предотвращения artefact'ов на старых
  iOS-версиях.
- **Bar item с одновременно `image` и `title`.** При наличии обоих
  отображается `image` (если он не `nil`); `title` игнорируется. Это
  соответствует поведению `UIBarButtonItem` в `.glass` стиле.
- **Custom titleView без intrinsic size.** Wrapper-views (HypeUI
  `.padding()`, `UIView` с Auto Layout subview-объектами) могут
  возвращать `bounds.size = .zero` до первого layout-pass. Бар использует
  `systemLayoutSizeFitting` как primary path для корректного измерения.
- **Context menu на bar button после theme-flip.** При смене dark/light
  mode бар выполняет `dismissPresentedBarButtonContextMenu()` перед
  rebuild'ом `GlassControlGroup`, предотвращая dangling weak reference в
  morph-back-to-source step.

## See Also

- <doc:ViewController>
- <doc:NavigationController>
- <doc:Search>
- <doc:Glass>
- <doc:EdgeEffect>
- <doc:ContextMenu>
