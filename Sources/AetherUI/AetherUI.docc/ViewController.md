# ``AetherViewController``

Базовый класс для всех экранов AetherUI: владеет собственным nav bar'ом,
выполняет диспетчеризацию layout через ``ContainerViewLayout``, предоставляет
точки расширения для accessory-зон, search, content-unavailable, floating
toolbar.

## Overview

`ViewController` представляет собой `UIViewController`-подкласс, расширяющий
стандартный UIKit-API. Ключевые отличия от `UIViewController`:

- **Собственный nav bar.** Каждый экран отображает собственный
  ``NavigationBarView``; бар размещается внутри `view` контроллера и
  перемещается с ним при push/pop. Это обеспечивает glass-morph переход
  между экранами.
- **Единая точка раскладки.** Метод
  ``AetherViewController/containerLayoutUpdated(_:transition:)`` получает
  ``ContainerViewLayout`` (size, safe insets, status bar, keyboard) и
  ``ContainedViewLayoutTransition``, корректно отражающий характер
  изменения. Любая системная операция (rotation, keyboard, push, modal
  detent change) приводит к вызову этого метода — других путей раскладки
  не предусмотрено.
- **Стандартизированные слоты.** ``AetherViewController/topBarAccessory``,
  ``AetherViewController/searchController``,
  ``AetherViewController/floatingToolbar``,
  ``AetherViewController/aetherContentUnavailableConfiguration`` — типовые
  компоненты, размещаемые в фиксированных позициях иерархии.
- **Утилиты.** ``AetherViewController/push(_:animated:)``,
  ``AetherViewController/pop(animated:)``,
  ``AetherViewController/navigationController``,
  ``AetherViewController/tabBarController`` — поднимаются по родительской
  цепочке, что устраняет необходимость передачи ссылок через всю иерархию.

> Tip: Все перечисленные возможности являются **опциональными**. Минимальный
> экран без их использования эквивалентен обычному `UIViewController` и
> требует только наследования от ``AetherViewController`` и инициализации через
> `super.init(navigationBarPresentationData:)`.

## Базовый шаблон

```swift
import AetherUI

final class ProfileController: AetherViewController {

    init() {
        super.init(navigationBarPresentationData: NavigationBarPresentationData(
            theme: NavigationBarTheme.liquidGlass()
        ))
        navigationItem.title = "Профиль"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            style: .plain, target: self, action: #selector(showMenu)
        )
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // Здесь выполняется добавление subview-объектов.
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout,
                                         transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        // Раскладка subview-объектов выполняется только в этом методе.
    }

    @objc private func showMenu() { /* ... */ }
}
```

> Important: `super.init(navigationBarPresentationData: nil)` создаёт
> контроллер **без** nav bar — для fullscreen, splash, camera экранов.
> Если nav bar требуется, передайте ``NavigationBarPresentationData``.
> Для замены presentationData во время работы используется
> ``AetherViewController/setNavigationBarPresentationData(_:animated:)``.

## Жизненный цикл

`ViewController` поддерживает стандартные хуки `viewDidLoad`,
`viewWillAppear`, `viewDidAppear`, `viewWillDisappear`, `viewDidDisappear`.
Дополнительно предоставляются:

| Хук | Условие вызова |
|---|---|
| ``AetherViewController/containerLayoutUpdated(_:transition:)`` | Любое изменение размера, safe area, keyboard, push, modal detent. Основная точка раскладки. |
| ``AetherViewController/inFocusUpdated(isInFocus:)`` | Контроллер становится или перестаёт быть «верхним» в стеке. Предпочтителен по сравнению с `viewDidAppear`, поскольку не активируется при modal-презентации. |
| ``AetherViewController/setReady(_:)`` | Сигнализирует контейнеру о готовности данных к отображению. NavigationController откладывает коммит push до `isReady = true`. |
| ``AetherViewController/tabBarItemContextAction(sourceView:gesture:)`` | Long-press по tab-bar-item (при ``AetherViewController/tabBarItemContextActionType`` ≠ `.none`). |

### Повторный bind nav bar в viewWillAppear

Внутри `viewWillAppear` фреймворк выполняет повторное присваивание
`bar.item = navigationItem`. Это необходимо для случая, когда
`setViewControllers` вызывается до `viewDidLoad`, а `navigationItem.title`
устанавливается уже внутри `viewDidLoad`. Операция идемпотентна и не
вызывает дополнительных перерасчётов.

## Layout: основной принцип

Раскладка subview-объектов должна выполняться **исключительно** в
``AetherViewController/containerLayoutUpdated(_:transition:)``. Не в
`viewDidLayoutSubviews`, не в кастомных хуках, не в KVO-обработчиках на
`bounds`. Причина: только в `containerLayoutUpdated` доступен корректный
``ContainedViewLayoutTransition`` — анимированный, если изменения вызваны
системной операцией (push, keyboard, rotate), и `.immediate` в остальных
случаях. Использование альтернативных entry-point'ов приводит к потере
этой информации и рассинхронизации переходов.

```swift
override func containerLayoutUpdated(_ layout: ContainerViewLayout,
                                     transition: ContainedViewLayoutTransition) {
    super.containerLayoutUpdated(layout, transition: transition)

    // Нижняя граница nav bar (с учётом safe area).
    let topInset = cleanNavigationHeight

    // Нижний inset учитывает safe area и additional insets от
    // tab bar / toolbar.
    let bottomInset = max(layout.safeInsets.bottom,
                          layout.additionalInsets.bottom)

    let contentFrame = CGRect(
        x: layout.safeInsets.left,
        y: topInset,
        width: layout.size.width - layout.safeInsets.left - layout.safeInsets.right,
        height: layout.size.height - topInset - bottomInset
    )
    transition.updateFrame(view: contentView, frame: contentFrame)
}
```

> Tip: При работе с scroll view не устанавливайте `contentInset` напрямую;
> используйте ``ContainedViewLayoutTransition/updateContentInset(scrollView:insets:completion:)``
> и ``ContainedViewLayoutTransition/updateScrollIndicatorInsets(scrollView:insets:completion:)``.
> Они выполняют корректную компенсацию `contentOffset`, предотвращая
> рассинхронизацию скролла при изменении инсетов.

## Top-bar accessory

Под title row nav bar'а может быть размещён произвольный
``NavigationBarContentView`` — например, фильтр-чипы, segmented control,
поисковая строка.

```swift
final class FilterBar: NavigationBarContentView {
    override init() {
        super.init()
        // Конфигурация UI: чипы, scrollView и т.д.
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        // Раскладка subview-объектов в области (size.width × size.height).
    }
}

// В ViewController:
topBarAccessory = FilterBar()
setTopBarAccessory(FilterBar(), animated: true)
```

Присваивание `nil` удаляет accessory мгновенно. Для появления/исчезновения
через framework-private blur-crossfade используйте
`setTopBarAccessory(nil, animated: true)`.

> Note: При одновременной установке accessory и
> ``AetherViewController/searchController`` AetherUI автоматически
> размещает их через ``AetherStackedBarContent``: поисковый pill сверху,
> accessory снизу. Ручное добавление search pill в `topBarAccessory` не
> требуется.

## Search controller

Glass-pill поиска внутри nav bar с активацией, деактивацией и поддержкой
результатов:

```swift
let search = AetherSearchController()
search.placeholder = "Поиск"
search.delegate = self
searchController = search
```

Подробнее — <doc:Search>.

## Floating toolbar

Плавающий glass-pill в нижней части экрана (стиль Safari, Mail, Messages):

```swift
let toolbar = AetherFloatingToolbarView()
toolbar.setItems([
    AetherFloatingToolbarItem(icon: UIImage(systemName: "square.and.arrow.up")!) { [weak self] in
        self?.share()
    },
    .flexibleSpace,
    AetherFloatingToolbarItem(icon: UIImage(systemName: "trash")!) { [weak self] in
        self?.delete()
    }
])
floatingToolbar = toolbar
```

Toolbar автоматически позиционируется поверх tab-bar pill'а (при его
наличии) либо над home indicator (при его отсутствии) и добавляет себя в
`additionalSafeAreaInsets.bottom`, обеспечивая корректный отступ для
scroll-контента.

Подробнее — <doc:Toolbar>.

## Content-unavailable overlay

UIKit-style overlay для empty / loading / error состояний, поддерживающий
iOS 13+ (нативный `UIViewController.aetherContentUnavailableConfiguration`
доступен только с iOS 17):

```swift
var config = AetherContentUnavailableConfiguration.empty()
config.image = UIImage(systemName: "tray")
config.text = "Здесь пока пусто"
config.secondaryText = "При появлении новых данных они будут отображены здесь"
aetherContentUnavailableConfiguration = config
```

Cross-fade между состояниями:

```swift
setAetherContentUnavailableConfiguration(loadingConfig, animated: true)
// После загрузки данных:
setAetherContentUnavailableConfiguration(nil, animated: true)
```

Overlay располагается **под** nav bar и floating toolbar, что обеспечивает
интерактивность chrome. Подробнее — <doc:ContentUnavailable>.

> Note: Префикс `aether` используется для предотвращения коллизии имён.
> На iOS 17+ UIKit ввёл собственный `contentUnavailableConfiguration` с
> аналогичной семантикой; во избежание конфликта свойство в AetherUI
> названо ``AetherViewController/aetherContentUnavailableConfiguration``.

## Push / Pop

`ViewController` поднимается по родительской цепочке и определяет
ближайший ``AetherNavigationController``:

```swift
push(DetailController(), animated: true)   // эквивалент navigationController?.pushViewController
pop(animated: true)                         // эквивалент navigationController?.popViewController
```

При отсутствии AetherNavigationController в иерархии используется
fallback на стандартный `self.navigationController`. Это обеспечивает
работу единого `push` API как внутри `UINavigationController`, так и
внутри `AetherNavigationController`.

### Интерактивный edge-swipe

По умолчанию активен левый edge-swipe шириной ~20pt. Для расширения
или отключения для конкретного экрана:

```swift
override var interactiveNavivationGestureEdgeWidth: InteractiveTransitionGestureRecognizerEdgeWidth? {
    return .constant(40.0)         // расширение до 40pt
    // return .constant(0.0)       // полное отключение для данного экрана
    // return nil                  // значение по умолчанию (~20pt)
}
```

> Tip: Для центральных свайпов (карточные жесты, кастомные slider'ы внутри
> контента) фреймворк автоматически передаёт событие во внутренние слои
> через Obj-C bridge (`AetherViewTreeDisablesInteractiveTransitionGesture`).
> Если subview содержит специализированный жест, рассмотрите установку
> `disablesInteractiveTransitionGestureRecognizer = true` на нём, что
> предотвратит конфликт с edge-pop.

## Status bar

```swift
statusBarStyle = .lightContent     // didSet вызывает setNeedsStatusBarAppearanceUpdate
```

Не следует переопределять `preferredStatusBarStyle`: эта задача выполняется
базовым классом и проксируется через ``AetherWindow``-root.

## Ориентация

```swift
supportedOrientations = AetherViewController.SupportedOrientations(
    regularSize: .all,                  // iPad / split view
    compactSize: .portrait              // iPhone — только portrait
)

// Блокировка ориентации на время презентации:
lockedOrientation = .portrait
```

## API: основные свойства

### Layout

| Свойство | Тип | Назначение |
|---|---|---|
| ``AetherViewController/currentlyAppliedLayout`` | `ContainerViewLayout?` | Последний применённый layout. Может быть прочитан в произвольной точке для синхронного вычисления размеров. |
| ``AetherViewController/cleanNavigationHeight`` | `CGFloat` | `bar.frame.maxY` — нижняя граница nav bar (с учётом status bar и safe area). Основной источник top inset. |
| ``AetherViewController/additionalSideInsets`` | `UIEdgeInsets` | Дополнительные горизонтальные insets, добавляемые к safe area (split-view сценарии). |

### Bars и accessory

| Свойство | Тип | Назначение |
|---|---|---|
| ``AetherViewController/navigationBarView`` | `NavigationBarView?` | Сам бар; прямое обращение, как правило, не требуется. |
| ``AetherViewController/displayNavigationBar`` | `Bool` | Управление видимостью бара без удаления. При `false` бар смещается за верхнюю границу. |
| ``AetherViewController/topBarAccessory`` | `NavigationBarContentView?` | Контент под title row (фильтры, segmented control). |
| ``AetherViewController/setTopBarAccessory(_:animated:)`` | method | Анимированная установка/удаление top accessory через внутренний blur-crossfade. |
| ``AetherViewController/searchController`` | `AetherSearchController?` | Поисковый pill в nav bar. |
| ``AetherViewController/floatingToolbar`` | `AetherFloatingToolbarView?` | Плавающий toolbar в нижней части экрана. |
| ``AetherViewController/inputBarAccessoryView`` | `UIView?` | Bottom input accessory над клавиатурой, tab-bar chrome или нижним экранным inset. |
| ``AetherViewController/inputBarAccessoryBottomInset`` | `CGFloat` | Visual gap для standalone input accessory без клавиатуры и tab-bar chrome. Default: 28pt. |

### Контент-стейт

| Свойство | Тип | Назначение |
|---|---|---|
| ``AetherViewController/aetherContentUnavailableConfiguration`` | `AetherContentUnavailableConfiguration?` | Empty/loading/error overlay. |
| ``AetherViewController/setAetherContentUnavailableConfiguration(_:animated:)`` | `()` | Cross-fade при изменении конфигурации. |

### Tab bar

| Свойство / метод | Назначение |
|---|---|
| ``AetherViewController/tabBarItemDebugTapAction`` | Closure для long-press по tab item. |
| ``AetherViewController/tabBarItemContextActionType`` | Условие активации context-action: `.none` / `.always` / `.whenActive`. |
| ``AetherViewController/tabBarSearchState`` | Текущее состояние tab-bar-search (для экранов, реализующих собственный поиск). |
| ``AetherViewController/tabBarItemHasDoubleTapAction()`` / ``AetherViewController/tabBarItemPerformDoubleTapAction()`` | Двойной тап по собственному tab item (Telegram-style scroll-to-top). |

### Жизненный цикл

| Хук | Назначение |
|---|---|
| ``AetherViewController/containerLayoutUpdated(_:transition:)`` | Основная точка раскладки. |
| ``AetherViewController/inFocusUpdated(isInFocus:)`` | Контроллер становится или перестаёт быть «верхним». |
| ``AetherViewController/setReady(_:)`` / ``AetherViewController/isReady`` / ``AetherViewController/readyChanged`` | Сигнал готовности данных. NavigationController ожидает его перед push. |

### Презентация

| Свойство | Назначение |
|---|---|
| ``AetherViewController/navigationPresentation`` | `.default` / `.master` — поведение при split-view презентации. |
| ``AetherViewController/attemptNavigation`` | Closure-перехватчик, позволяющий запросить подтверждение перед pop. |

## Edge cases

- **Не присваивайте `view.backgroundColor` в `init`.** На момент init'а
  `view` ещё не загружено; обращение к нему вызовет преждевременный `loadView`,
  что нарушит порядок выполнения `super.init(navigationBarPresentationData:)`.
- **Не переопределяйте `viewDidLayoutSubviews` для собственной раскладки.**
  Все необходимые данные передаются через
  ``AetherViewController/containerLayoutUpdated(_:transition:)``, и только этот
  вызов содержит корректный transition.
- **`preferredStatusBarStyle` зарезервирован.** Используйте
  ``AetherViewController/statusBarStyle`` (свойство) вместо override.
- **Кастомный жест внутри content view, конфликтующий с edge-pop.**
  Установите `disablesInteractiveTransitionGestureRecognizer = true`
  на жесте (доступно через Obj-C bridge — см.
  `Sources/AetherUIBridging/UIView+AetherNavigation.h`).

## See Also

- <doc:AetherWindow>
- <doc:NavigationController>
- <doc:NavigationBar>
- <doc:Search>
- <doc:Toolbar>
- <doc:ContentUnavailable>
