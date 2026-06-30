# NavigationController

Стек экранов с per-screen nav bar, glass-morph переходами при push/pop,
интерактивным edge-swipe pop'ом, поддержкой split-view и overlay-контейнеров.

## Overview

`AetherNavigationController` — полноценная замена `UINavigationController`
с расширенным набором возможностей:

- **Per-screen nav bar.** Каждый ``AetherViewController`` владеет собственным
  ``NavigationBarView`` (см. <doc:NavigationBar>). Бар перемещается с
  контроллером во время push/pop, что обеспечивает glass-morph переход
  между двумя одновременно видимыми барами.
- **Интерактивный edge-pop.** Левый edge-swipe (~20 pt) выполняет pop с
  параллаксом 30%; реализован через `AetherWindowPanRecognizer` + Obj-C
  bridge для пробрасывания внутрь content view.
- **Split-view (master/detail).** Режим `.automaticMasterDetail`
  активирует двухколоночный layout на iPad'ах в regular size class с
  автоматическим распределением экранов между master и detail.
- **Overlay-контейнеры.** ``AetherNavigationController/presentOverlay(_:blocksInteractionUntilReady:animated:completion:)``
  добавляет ViewController поверх стека (toast, tooltip, sheet) без
  взаимодействия с push/pop.
- **Минимизация (Picture-in-Picture-style).** Контроллеры могут быть
  свернуты в нижнюю «полку» с возможностью разворота.
- **App appearance + local overrides.**
  ``AetherNavigationController`` берёт базовый вид из ``AppearanceStyle`` и
  перечитывает ``AetherControllerAppearanceProviding`` у верхнего экрана.

## Базовый шаблон

```swift
let nav = AetherNavigationController(mode: .single)
nav.setViewControllers([HomeController()], animated: false)
```

Дальнейшее использование идентично `UINavigationController`:

```swift
nav.pushViewController(DetailController(), animated: true)
nav.popViewController(animated: true)
nav.popToRoot(animated: true)
nav.replaceTopController(NewController(), animated: true)
```

## Mode

Режим работы задаётся через ``NavigationControllerMode``:

| Значение | Поведение |
|---|---|
| `.single` | Однопанельный стек (типовой случай). |
| `.automaticMasterDetail` | Двухколоночный split-view на устройствах в regular size class. На iPhone и в compact size class работает как `.single`. |

В `.automaticMasterDetail` распределение экранов между master и detail
определяется свойством ``AetherViewController/navigationPresentation``:

```swift
class ProfileController: AetherViewController {
    init() {
        super.init()
        navigationPresentation = .master   // прижимается к master-колонке
    }
}

class MessageController: AetherViewController {
    init() {
        super.init()
        navigationPresentation = .default  // отображается в detail
    }
}
```

## Appearance

```swift
final class ProfileController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .navigation else { return nil }
        return AetherAppearanceOverride(
            navigationBar: AetherNavigationBarAppearanceOverride(
                buttonColor: .systemPink
            )
        )
    }
}
```

Если состояние override меняется во время жизни экрана, вызовите
``AetherNavigationController/invalidateAppearance()``.

## Стек контроллеров

### Чтение состояния

```swift
nav.viewControllerStack    // [AetherViewController] — полный стек
nav.topController          // верхний контроллер (включая overlay'и)
```

### Модификация стека

| Метод | Назначение |
|---|---|
| ``AetherNavigationController/setViewControllers(_:animated:)`` | Полная замена стека. Дубликаты тихо отбрасываются. |
| ``AetherNavigationController/pushViewController(_:animated:)`` | Push нового контроллера. |
| ``AetherNavigationController/popViewController(animated:)`` | Pop верхнего контроллера. Возвращает удалённый ViewController. |
| ``AetherNavigationController/popToRoot(animated:)`` | Pop до корневого контроллера. |
| ``AetherNavigationController/replaceTopController(_:animated:)`` | Замена верхнего контроллера без удаления нижних. |

> Note: `setViewControllers` выполняет дедупликацию по reference identity —
> повторные вхождения одного и того же контроллера тихо удаляются.
> Это соответствует поведению Telegram-iOS и предотвращает некорректное
> состояние back-stack.

## Overlay-контейнеры

Overlay'и располагаются поверх navigation stack, но не входят в него.
Используются для toast'ов, tooltip'ов, action sheet'ов:

```swift
let toast = AetherToastController(text: "Готово")
nav.presentOverlay(toast, animated: true)

// Закрытие конкретного overlay:
nav.dismissOverlay(toast, animated: true)

// Закрытие верхнего overlay:
nav.dismissOverlay(animated: true)
```

### blocksInteractionUntilReady

```swift
nav.presentOverlay(loadingScreen, blocksInteractionUntilReady: true, animated: true)
loadingScreen.setReady(true)   // снимает блокировку взаимодействия
```

При `blocksInteractionUntilReady: true` overlay блокирует все touch-события
до вызова ``AetherViewController/setReady(_:)`` с `true`. Применяется для
loading-экранов и confirmation-диалогов.

### Чтение overlay-состояния

```swift
nav.overlayControllers      // [AetherViewController] — все активные overlay'и
nav.topOverlayController    // верхний активный overlay
```

## Минимизация

Контроллер может быть свёрнут в нижнюю «полку» (по образцу
Picture-in-Picture в iOS):

```swift
final class VideoPlayerController: AetherViewController, MinimizableController {
    // ... реализация MinimizableController протокола
}

let player = VideoPlayerController()
nav.minimizeViewController(
    player,
    topEdgeOffset: nil,
    beforeMaximize: { nav, completion in
        // Подготовка перед разворотом (опционально)
        completion()
    },
    setupContainer: { existing in
        existing ?? CustomMinimizedContainer()
    },
    animated: true
)

// Разворот обратно:
nav.maximizeViewController(player, animated: true) { success in
    print("Maximized: \(success)")
}

// Закрытие всех минимизированных:
nav.dismissMinimizedControllers {
    print("All dismissed")
}
```

> Note: Реализация `MinimizableController` и `MinimizedContainerProtocol`
> выходит за рамки данной статьи. См. исходные файлы
> `MinimizedContainer.swift` для деталей.

## Layout

`AetherNavigationController` сам реализует
``AetherNavigationController/containerLayoutUpdated(_:transition:)``,
получая ``ContainerViewLayout`` от ``AetherWindow`` или
``AetherTabBarController``. Раскладка распространяется на:

- Текущий root container (flat или split)
- Все active overlay-контейнеры
- Минимизированный контейнер (если присутствует)

Для принудительного перерасчёта raskладки используется
``AetherNavigationController/requestLayout(transition:)``:

```swift
nav.requestLayout(transition: .animated(duration: 0.3, curve: .easeInOut))
```

## Status bar

`childForStatusBarStyle` и `childForStatusBarHidden` указывают на
``AetherNavigationController/topController``, что обеспечивает
автоматическое следование за стилем верхнего контроллера. Базовый стиль
определяется app-level ``AppearanceStyle``:

| Значение | UIStatusBarStyle |
|---|---|
| `.black` | `.darkContent` |
| `.white` | `.lightContent` |

После изменения app appearance runtime вызывает ``AetherNavigationController/updateAppearance(_:)``.

## API

### Init

| Метод | Назначение |
|---|---|
| `init(mode:theme:)` | Создание с режимом и темой. |

### Стек

| Свойство / метод | Назначение |
|---|---|
| ``AetherNavigationController/viewControllerStack`` | Текущий стек. |
| ``AetherNavigationController/topController`` | Верхний контроллер (включая overlay'и). |
| ``AetherNavigationController/setViewControllers(_:animated:)`` | Замена стека. |
| ``AetherNavigationController/pushViewController(_:animated:)`` | Push. |
| ``AetherNavigationController/popViewController(animated:)`` | Pop. |
| ``AetherNavigationController/popToRoot(animated:)`` | Pop до корня. |
| ``AetherNavigationController/replaceTopController(_:animated:)`` | Замена верхнего. |

### Overlay

| Свойство / метод | Назначение |
|---|---|
| ``AetherNavigationController/overlayControllers`` | Все активные overlay'и. |
| ``AetherNavigationController/topOverlayController`` | Верхний overlay. |
| ``AetherNavigationController/presentOverlay(_:blocksInteractionUntilReady:animated:completion:)`` | Презентация overlay. |
| ``AetherNavigationController/dismissOverlay(_:animated:completion:)`` | Закрытие overlay. |

### Минимизация

| Метод | Назначение |
|---|---|
| ``AetherNavigationController/minimizedContainer`` | Контейнер свёрнутых контроллеров. |
| ``AetherNavigationController/minimizeViewController(_:topEdgeOffset:beforeMaximize:setupContainer:animated:)`` | Свернуть контроллер. |
| ``AetherNavigationController/maximizeViewController(_:animated:completion:)`` | Развернуть свёрнутый. |
| ``AetherNavigationController/dismissMinimizedControllers(completion:)`` | Закрыть все свёрнутые. |

### Layout

| Метод | Назначение |
|---|---|
| ``AetherNavigationController/containerLayoutUpdated(_:transition:)`` | Внешний entry-point раскладки. Вызывается родителем. |
| ``AetherNavigationController/requestLayout(transition:)`` | Принудительный перерасчёт раскладки. |

### Theme

| Метод | Назначение |
|---|---|
| ``AetherNavigationController/updateTheme(_:)`` | Динамическая смена темы. |

## Edge cases

- **`setViewControllers` с дубликатами.** Повторные вхождения одного и
  того же контроллера тихо отбрасываются. Это предотвращает разрушение
  back-stack state.
- **Push контроллера из не-AetherUI стека.** Стандартный
  `UIViewController.push` через `self.navigationController?` работает,
  поскольку `AetherNavigationController` наследуется от
  `UIViewController`. Однако glass-morph переход доступен только при
  использовании ``AetherViewController/push(_:animated:)`` или прямого вызова
  ``AetherNavigationController/pushViewController(_:animated:)``.
- **Конфликт edge-swipe с custom-жестами.** Для предотвращения конфликта
  установите на конкурирующем жесте
  `disablesInteractiveTransitionGestureRecognizer = true` (через Obj-C
  bridge — см. `Sources/AetherUIBridging/UIView+AetherNavigation.h`).
  Альтернативно — расширьте edge через
  ``AetherViewController/interactiveNavivationGestureEdgeWidth``.
- **Modal hosting.** При размещении `AetherNavigationController` внутри
  ``AetherModalController`` status bar height заменяется на высоту
  grabber-полосы, что обеспечивает правильное позиционирование nav bar
  под grabber'ом.

## See Also

- <doc:ViewController>
- <doc:NavigationBar>
- <doc:AetherWindow>
- <doc:TabBar>
- <doc:Modal>
