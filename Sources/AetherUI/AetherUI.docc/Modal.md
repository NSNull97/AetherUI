# Modal

Двухдетентный glass-sheet с поддержкой sticky-footer, scroll
arbitration, keyboard handling, embedded navigation stack.

## Overview

``AetherModalController`` — модальный sheet, презентуемый через
стандартный UIKit `present(_:animated:)`:

- Два detent'а: `.stage1` (компактный с боковыми insets, glass виден
  с обеих сторон) и `.stage2` (full-width, edge-to-edge tint).
- Top corners 27pt, bottom corners — соответствие display radius
  устройства в `.stage2`.
- Cooperation с inner scroll view (gesture arbitration: drag по scroll
  content переключает control между sheet drag и scroll).
- Sticky footer с автоматическим edge-effect frost'ом.
- Keyboard handling: автоматический подъём footer'а над клавиатурой;
  `primaryScrollView.contentInset.bottom` обновляется на keyboard
  overlap.
- Custom transition animations: source-to-modal morph из кнопки
  или полностью свой `UIViewControllerAnimatedTransitioning`.
- ``AetherModalNavigationController`` — wrapper с встроенным
  ``AetherNavigationController`` для модалок со стеком.

## Базовый шаблон

```swift
let content = MyContentController()

let modal = AetherModalController()
modal.embedContent(content)
modal.primaryScrollView = content.scrollView   // (опц.) кооперация со scroll
present(modal, animated: true)

// Программное переключение detent'а:
modal.setDetent(.stage2, animated: true)

// Закрытие через стандартный UIKit:
dismiss(animated: true)
```

## Detents

```swift
public enum Detent: Hashable {
    case stage1   // компактный
    case stage2   // full-height
}
```

При drag'е sheet snap'ится к ближайшему допустимому detent'у. По
умолчанию доступны оба:

```swift
let config = AetherModalController.Config(
    detents: [.stage1, .stage2],
    initialDetent: .stage1
)
```

### Single-detent mode

```swift
// Только stage2, drag к stage1 заблокирован, dismiss только сильным
// downward swipe'ом:
let config = AetherModalController.Config(
    detents: [.stage2]
)
```

## Config

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `sideInset` | `CGFloat` | `8.0` | Боковой inset sheet'а в `.stage1`. |
| `bottomInsetStage1` | `CGFloat` | `8.0` | Расстояние от bottom edge до screen bottom в `.stage1`. |
| `bottomInsetStage2` | `CGFloat` | `0.0` | То же в `.stage2` (sheet flush с bottom). |
| `topInsetStage1` | `CGFloat` | `UIScreenHeight / 2` | Расстояние от top edge до status bar в `.stage1`. |
| `topInsetStage2` | `CGFloat` | `10.0` | То же в `.stage2`. |
| `topCornerRadius` | `CGFloat` | `34.0` | Top corner radius. |
| `dimAlphaStage1` | `CGFloat` | `0.25` | Dim alpha над presenter в `.stage1`. |
| `dimAlphaStage2` | `CGFloat` | `0.4` | То же в `.stage2`. |
| `dimTintColor` | `UIColor` | `.systemBackground` | Цвет dim layer'а. |
| `detents` | `Set<Detent>` | `[.stage1, .stage2]` | Допустимые detent'ы. |
| `initialDetent` | `Detent?` | `nil` | Detent при открытии. `nil` → первый из allowed. |

```swift
let config = AetherModalController.Config(
    sideInset: 16,
    topInsetStage1: 200,
    topCornerRadius: 24,
    dimAlphaStage2: 0.5,
    detents: [.stage2],
    initialDetent: .stage2
)
let modal = AetherModalController(config: config)
```

## Embed content

### Через child controller

```swift
let content = ContentController()
modal.embedContent(content)
```

`embedContent` выполняет:

- `addChild(content)`
- Добавление `content.view` в `modal.contentView`
- `didMove(toParent: modal)`

### Через прямую subview

```swift
let label = UILabel()
modal.contentView.addSubview(label)
// Раскладка label в layoutSubviews подкласса modal'а
```

> Important: `contentView` остаётся фиксированным размером (равным
> `.stage2` size) на всё время существования modal'а. При drag'е
> меняется только outer `presentedView.frame`. Inner content не
> re-layouts на каждом pan tick, что даёт высокую производительность.

## Sticky footer

```swift
let sendButton = UIButton(type: .system)
sendButton.setTitle("Отправить", for: .normal)
modal.footerView = sendButton
modal.footerHeight = 56            // обязательно — auto-layout-only footer'ы вернут 0
```

Footer:

- Закреплён к bottom modal'а; следует за sheet через detent'ы.
- Над footer'ом рендерится edge-effect frost (`footerEdgeFadeHeight = 28pt`
  по умолчанию).
- `footerHeight` добавляется в `additionalSafeAreaInsets.bottom`
  content area, что обеспечивает scroll content прохождение под
  footer'ом.

### Кастомизация frost'а

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `footerEdgeFadeHeight` | `CGFloat` | `28.0` | Высота gradient fade зоны. |
| `footerEdgeTintColor` | `UIColor?` | `nil` | Tint frost'а (nil → `config.dimTintColor` × 0.86 alpha). |
| `footerEdgeBlurRadius` | `CGFloat` | `2.0` | Blur radius. |

## Scroll arbitration

```swift
modal.primaryScrollView = content.tableView
```

При установке `primaryScrollView`:

1. **Gesture arbitration**: drag, начатый внутри scroll content, отдаётся
   scroll view (если scroll НЕ at top). При scroll at top drag
   переключается на sheet (sheet начинает двигаться).
2. **Keyboard handling**: модальный controller наблюдает
   `keyboardWillChangeFrame`; обнаруженный overlap с keyboard
   добавляется в `primaryScrollView.contentInset.bottom` и
   `verticalScrollIndicatorInsets.bottom`. Active first responder
   автоматически scrolls в visible area.

> Tip: При смене `primaryScrollView` keyboard contribution автоматически
> переносится со старого scroll view на новый.

## Keyboard handling

Без дополнительной настройки модальный controller:

- Подъёмает footer над keyboard (footer follows keyboard top edge).
- Обновляет `primaryScrollView.contentInset.bottom` на keyboard overlap.
- Scrolls active first responder в visible область.
- Реагирует на keyboard show/hide/resize/dismiss с системной длительностью
  и curve.

Никакого кода со стороны caller'а не требуется — достаточно установить
`primaryScrollView`.

## Программное управление

```swift
modal.currentDetent              // .stage1 | .stage2
modal.currentDetentProgress      // CGFloat — прогресс drag'а

modal.setDetent(.stage2, animated: true)

// Закрытие — стандартный UIKit:
dismiss(animated: true)
```

## Custom transition animations

По умолчанию модалка открывается как bottom sheet снизу. Для morph
из конкретной кнопки в модальное окно используйте встроенный source
transition:

```swift
let modal = AetherModalNavigationController(
    rootViewController: AttachmentsController(),
    config: .init(detents: [.stage1], initialDetent: .stage1)
)
modal.useSourceTransition(from: attachmentButton)
present(modal, animated: true)
```

Если source view живёт не дольше самой кнопки или frame уже рассчитан,
можно передать frame в window coordinates:

```swift
let frame = attachmentButton.convert(attachmentButton.bounds, to: nil)
modal.useSourceTransition(sourceFrameInWindow: frame)
```

Тонкая настройка:

```swift
modal.useSourceTransition(
    from: attachmentButton,
    configuration: .init(
        presentationDuration: 0.5,
        dismissalDuration: 0.24,
        overscaleAmount: 0.018,
        sourceCornerRadius: 22,
        targetCornerRadius: 34
    )
)
```

Для полностью своей анимации присвойте объект, реализующий
``AetherModalTransitionAnimation``:

```swift
final class MyModalTransition: AetherModalTransitionAnimation {
    func makePresentationAnimator(
        for modalController: AetherModalController
    ) -> UIViewControllerAnimatedTransitioning? {
        MyPresentAnimator()
    }

    func makeDismissalAnimator(
        for modalController: AetherModalController
    ) -> UIViewControllerAnimatedTransitioning? {
        MyDismissAnimator()
    }
}

modal.transitionAnimation = MyModalTransition()
```

## Delegate

```swift
public protocol AetherModalControllerDelegate: AnyObject {
    func modalControllerWillChangeDetent(_ controller: AetherModalController, to detent: AetherModalController.Detent)
    func modalControllerDidChangeDetent(_ controller: AetherModalController, to detent: AetherModalController.Detent)
    func modalControllerDidDismiss(_ controller: AetherModalController)
}
```

Все методы default-имплементацией пустые.

```swift
modal.delegate = self
```

## AetherModalNavigationController

Wrapper над ``AetherModalController`` со встроенным
``AetherNavigationController``:

```swift
let root = SettingsController()
let modal = AetherModalNavigationController(
    rootViewController: root,
    config: .init(detents: [.stage1, .stage2], initialDetent: .stage2)
)
present(modal, animated: true)
```

Поддерживает push/pop внутри модалки:

```swift
modal.pushViewController(ProfileController(), animated: true)
modal.popViewController(animated: true)
modal.popToRoot(animated: true)
modal.setViewControllers([root, profile], animated: false)
modal.replaceTopController(newRoot, animated: true)

modal.rootViewController     // root controller (read-only)
modal.topViewController      // верхний controller стека
modal.viewControllers        // полный стек
```

Доступ к встроенному nav controller:

```swift
modal.internalNavigationController   // AetherNavigationController
```

> Note: Nav bar контроллеров внутри модалки автоматически адаптирован
> под grabber-полосу: `statusBarHeight` заменяется на
> ``AetherModalController/grabberContainerHeight`` (17pt), что
> обеспечивает правильное позиционирование bar content под grabber'ом.
> Edge-effect frost nav bar'а расширяется вверх для покрытия grabber
> region'а.

## AetherModalContent protocol

Опциональный протокол для ViewController'ов, презентуемых внутри
``AetherModalNavigationController``. Позволяет content'у объявить свои
footer / scroll preferences без явного кода со стороны caller'а:

```swift
final class SendPushViewController: AetherViewController, AetherModalContent {
    private(set) lazy var sendButton: UIButton = ...
    private(set) var scroll: UIScrollView?

    var modalFooterView: UIView? { sendButton }
    var modalFooterHeight: CGFloat { 98 }
    var modalPrimaryScrollView: UIScrollView? { scroll }
}

// Caller:
let modal = AetherModalNavigationController(
    rootViewController: SendPushViewController(),
    config: .init(detents: [.stage1, .stage2], initialDetent: .stage2)
)
present(modal, animated: true)
```

### Свойства протокола

| Свойство | Тип | Default | Назначение |
|---|---|---|---|
| `modalFooterView` | `UIView?` | `nil` | View для footer slot'а. |
| `modalFooterHeight` | `CGFloat` | `0` | Полная высота footer'а. |
| `modalFooterEdgeFadeHeight` | `CGFloat` | `28` | Высота gradient fade. |
| `modalFooterEdgeTintColor` | `UIColor?` | `nil` | Tint frost'а. |
| `modalFooterEdgeBlurRadius` | `CGFloat` | `2` | Blur radius. |
| `modalPrimaryScrollView` | `UIScrollView?` | `nil` | Scroll view для arbitration. |

Все свойства — opt-in. Conformance протоколу необязательна; VC, не
конформирующий протоколу, презентуется as-is (без footer slot, без
scroll arbitration).

## API сводка

### ``AetherModalController``

| Свойство / метод | Назначение |
|---|---|
| `init(config:)` | Создание. |
| `config` | Конфигурация (read-only после init). |
| `contentView` | Host для контента. |
| `embedContent(_:)` | Embed UIViewController. |
| `footerView` | Sticky footer. |
| `footerHeight` | Высота footer'а (обязательно при использовании). |
| `footerEdgeFadeHeight` / `footerEdgeTintColor` / `footerEdgeBlurRadius` | Кастомизация frost'а. |
| `primaryScrollView` | Scroll view для arbitration + keyboard handling. |
| `delegate` | Delegate. |
| `transitionAnimation` | Optional custom present/dismiss animation provider. |
| `currentDetent` | Текущий detent (read-only). |
| `currentDetentProgress` | Прогресс drag'а. |
| `setDetent(_:animated:)` | Программное переключение. |
| `useSourceTransition(from:)` | Source-to-modal morph из `UIView`. |
| `useSourceTransition(sourceFrameInWindow:)` | Source-to-modal morph из frame в window coordinates. |
| `grabberContainerHeight` (static) | Высота grabber-полосы (17pt). |

### ``AetherModalControllerDelegate``

См. протокол выше.

### ``AetherModalNavigationController``

| Свойство / метод | Назначение |
|---|---|
| `init(rootViewController:config:)` | Создание с root. |
| `init(viewControllers:config:)` | Создание со стеком. |
| `internalNavigationController` | Встроенный nav controller. |
| `rootViewController` / `topViewController` / `viewControllers` | Доступ к стеку. |
| `pushViewController(_:animated:)` | Push. |
| `popViewController(animated:)` | Pop. |
| `popToRoot(animated:)` | Pop до корня. |
| `setViewControllers(_:animated:)` | Замена стека. |
| `replaceTopController(_:animated:)` | Замена верхнего. |

### ``AetherModalContent`` (протокол)

См. таблицу свойств выше.

### ``AetherModalTransitionAnimation`` (протокол)

Фабрика для кастомных `UIViewControllerAnimatedTransitioning` на
presentation и dismissal. Верните `nil` для стороны, где нужно оставить
default bottom-sheet animation.

### ``AetherModalSourceTransition``

Готовая реализация ``AetherModalTransitionAnimation`` для morph-а
source view/frame в модалку и закрытия обратно в source.

## Edge cases

- **`footerHeight = 0` при наличии `footerView`.** Footer не отображается;
  edge-effect frost не создаётся. Auto-layout-only footer'ы возвращают
  `intrinsicContentSize.height == 0`, поэтому `footerHeight` обязательно
  устанавливается явно.
- **`primaryScrollView` не at top, drag вниз.** Sheet НЕ двигается —
  scroll arbitration отдаёт touch scroll view. Только когда scroll
  достигает top edge, sheet начинает двигаться.
- **Keyboard hide во время drag'а.** Keyboard observer корректно
  сбрасывает overlap; footer возвращается в position без
  glitch'а. Если `primaryScrollView` was scrolled во время keyboard
  shown, `contentInset.bottom` корректно восстанавливается.
- **Smashing detent boundary.** Strong downward velocity на drag end
  вызывает dismiss модалки даже из `.stage2` (минуя `.stage1`).
  Threshold velocity конфигурируется в imp; визуально соответствует
  стандартному UIKit-поведению.
- **Embedded nav controller status bar.** При размещении
  ``AetherNavigationController`` внутри ``AetherModalController``
  status bar height заменяется на `grabberContainerHeight = 17pt`.
  Nav bar bar content laid out под grabber'ом; edge-effect frost
  покрывает grabber region.
- **Push в модалке во время keyboard shown.** Keyboard observer
  перенаправляется на новый top controller; transition корректно
  координируется с keyboard animation.

## See Also

- <doc:NavigationController>
- <doc:NavigationBar>
- <doc:Glass>
- <doc:EdgeEffect>
