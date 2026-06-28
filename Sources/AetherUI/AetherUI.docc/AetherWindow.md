# ``AetherWindow``

`AetherWindow` is a source-compatible alias for ``AetherNativeWindow``.
It provides keyboard tracking, layout-interactive keyboard dismissal,
status bar dispatch, system gesture coordination, and a single
``ContainerViewLayout`` propagation path.

## Overview

`AetherNativeWindow` — корневое окно для всех приложений на AetherUI. Без него
теряется значительная часть функциональности фреймворка: keyboard frame не
отслеживается, status bar не управляется централизованно, безопасные insets
не передаются по цепочке `containerLayoutUpdated`.

Основные функции окна:

1. Подписка на `keyboardWillChangeFrameNotification` и вычисление реальной
   высоты клавиатуры с учётом split-screen, Slide Over и внешней
   клавиатуры; результат записывается в ``ContainerViewLayout/inputHeight``.
2. Активация `AetherWindowPanRecognizer` для свайпа вниз по контенту,
   публикующего interactive input bound в layout. AetherUI внутри
   фреймворка применяет legacy offset к системной keyboard surface, когда
   UIKit предоставляет keyboard host view.
3. Содержит root-controller, проксирующий `preferredStatusBarStyle`,
   `supportedInterfaceOrientations`, `prefersHomeIndicatorAutoHidden` и
   `preferredScreenEdgesDeferringSystemGestures` от contentController к UIKit.
4. Распространение ``ContainerViewLayout`` на дочерний контроллер с выбором
   соответствующего метода (TabBar, Navigation, ViewController).

> Important: Корневым окном должен быть **именно** `AetherNativeWindow`
> или совместимый `AetherWindow`, а не
> `UIWindow`. Контент присваивается через ``AetherWindow/contentController``,
> **не** через `rootViewController`.

## Базовая установка

В `SceneDelegate.swift`:

```swift
import UIKit
import AetherUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = AetherNativeWindow(windowScene: windowScene)
        window.contentController = makeRootController()
        window.makeKeyAndVisible()

        self.window = window
    }
}
```

Тип переменной может быть объявлен как `UIWindow?` (для совместимости с
шаблонами Apple), однако создаваться должен **только** `AetherNativeWindow`
или совместимый `AetherWindow`.

## contentController

Основной слот окна. Принимает `UIViewController?`, но корректно работает с
тремя типами:

| Тип | Назначение |
|---|---|
| ``AetherTabBarController`` | Многотабовое приложение (типовой случай). |
| ``AetherNavigationController`` | Однотабовое приложение со стеком экранов. |
| ``AetherViewController`` | Минимальный сценарий — один экран без навигации. |

При присваивании окно выполняет следующие действия автоматически:

- Удаление предыдущего contentController из иерархии
- Вызов `addChild` и `didMove(toParent:)` для нового контроллера
- Добавление его `view` в root
- Вызов `containerLayoutUpdated` при наличии установленного размера

```swift
window.contentController = newRootController   // мгновенная замена
```

> Tip: Для смены root в login-flow или при переходе с launch-screen
> достаточно повторного присваивания `contentController`. Использование
> `UIView.transition(with:duration:)` не требуется. Для cross-fade-эффекта
> присваивание может быть обёрнуто в `UIView.transition` поверх `window`.

## Keyboard

### Автоматический tracking

Размещение контента в `AetherWindow` достаточно для активации tracking'а;
дополнительная настройка не требуется. Высота клавиатуры доступна через
``ContainerViewLayout/inputHeight`` во всех контроллерах.

```swift
override func containerLayoutUpdated(_ layout: ContainerViewLayout,
                                     transition: ContainedViewLayoutTransition) {
    super.containerLayoutUpdated(layout, transition: transition)

    let keyboardHeight = layout.inputHeight ?? 0
    let inputBarBottomY = layout.size.height - keyboardHeight
    transition.updateFrame(view: inputBar, frame: CGRect(
        x: 0, y: inputBarBottomY - 50,
        width: layout.size.width, height: 50
    ))
}
```

В этом контексте `transition` уже **анимирован** — `duration` и `curve`
извлекаются из системных `UIResponder.keyboardAnimationDurationUserInfoKey`
и `…CurveUserInfoKey`, что обеспечивает синхронизацию перемещения input bar
с анимацией клавиатуры.

> Note: На iOS 26+ окно использует оригинальный `duration` системы (как
> правило, ~0.38с со spring curve). На iOS 13–25 принудительно
> устанавливается значение 0.5с, поскольку система иногда возвращает `0`,
> что приводит к мгновенному изменению.

### Interactive dismiss

Свайп вниз по контенту инициирует interactive layout update: app-owned
input bars получают промежуточный `ContainerViewLayout` и могут следовать
за пальцем. Одновременно окно использует внутренний legacy bridge, чтобы
двигать native keyboard surface через тот же offset. При отпускании ниже
порога окно resign-ит first responder, и UIKit завершает скрытие
клавиатуры.

Внешние приложения не получают доступ к `keyboardWindow`/`keyboardView` и
ничего не настраивают отдельно: поведение единое для всех через
`AetherNativeWindow` / `AetherWindow`.

Для контейнеров, которые во время transition должны смещать keyboard surface
по горизонтали, используйте `AetherKeyboardManager.setSurfaces(_:)` и
``UIView/aetherKeyboardAutomaticHandlingOptions``. Это replacement для
Telegram `disableAutomaticKeyboardHandling` / `KeyboardViewManager.update`.

По умолчанию активно **только** на iPhone. На iPad жест отключён, поскольку
размер клавиатуры меньше, а поведение конфликтует со Stage Manager.

Управление:

```swift
// Полное отключение (например, для экрана с ScrollView и
// keyboardDismissMode = .interactive — управление передаётся скроллу).
window.setInteractiveKeyboardPanEnabled(false)

// Программная отмена начатого жеста.
window.cancelInteractiveKeyboardGestures()
```

### Manual accessory height

Если input bar реализован как **обычный** subview (а не как
`inputAccessoryView`), окно не может определить его высоту автоматически,
и жест будет потягивать клавиатуру от нижнего края, а не от верхнего.
Высота должна быть указана явно:

```swift
window.setManualKeyboardGestureAccessoryHeight(56.0)   // высота input bar

// При закрытии экрана:
window.setManualKeyboardGestureAccessoryHeight(nil)
```

## Status bar

Изменение стиля через окно целесообразно, когда требуется обновление
независимо от текущего top-контроллера (например, при отображении
fullscreen overlay):

```swift
window.updateStatusBar(
    style: .lightContent,
    hidden: false,
    transition: .animated(duration: 0.3, curve: .easeInOut)
)
```

В типовых сценариях рекомендуется изменение
``AetherViewController/statusBarStyle`` на текущем контроллере.

## Orientation, home indicator, edge gestures

При изменении дочерним контроллером supportedOrientations необходимо
вызвать соответствующий invalidate-метод для повторного чтения значений
UIKit'ом:

```swift
window.invalidateSupportedOrientations()
window.invalidateDeferScreenEdgeGestures()
window.invalidatePrefersOnScreenNavigationHidden()
```

## Covering view (snapshot protection)

iOS отображает snapshot приложения в App Switcher. Для приложений с
sensitive data рекомендуется размещение covering view, скрывающего контент:

```swift
final class PrivacyCover: AetherWindowCoveringView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        let logo = UIImageView(image: UIImage(named: "AppLogo"))
        addSubview(logo)
        // Раскладка выполняется в updateLayout(_:).
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateLayout(_ size: CGSize) {
        // Центрирование логотипа.
    }
}

// При переходе в background:
window.coveringView = PrivacyCover(frame: .zero)

// При возврате:
window.coveringView = nil   // плавное скрытие за 0.2с
```

## Debug tap

Скрытая отладочная панель, активируемая 10 тапами в верхней части за
0.4 секунды:

```swift
window.debugAction = { [weak self] in
    let debug = DebugMenuController()
    self?.window?.contentController?.present(debug, animated: true)
}
```

## API

| Свойство / метод | Назначение |
|---|---|
| ``AetherWindow/contentController`` | Главный контроллер (Tab/Nav/ViewController). |
| ``AetherWindow/currentLayout`` | Текущий computed `ContainerViewLayout`. Может быть прочитан в произвольный момент. |
| ``AetherWindow/coveringView`` | Snapshot-protect overlay. |
| ``AetherWindow/debugAction`` | Closure для 10-tap debug gesture. |
| ``AetherWindow/updateStatusBar(style:hidden:transition:)`` | Программное обновление status bar. |
| ``AetherWindow/invalidateSupportedOrientations()`` | Повторное чтение ориентаций с дочернего контроллера. |
| ``AetherWindow/invalidateDeferScreenEdgeGestures()`` | Повторное чтение deferred screen edge gestures. |
| ``AetherWindow/invalidatePrefersOnScreenNavigationHidden()`` | Повторное чтение home-indicator visibility. |
| ``AetherWindow/setInteractiveKeyboardPanEnabled(_:)`` | Управление window-level pan recognizer для keyboard dismiss. |
| ``AetherWindow/setManualKeyboardGestureAccessoryHeight(_:)`` | Установка высоты input bar для случая, когда он не является `inputAccessoryView`. |
| ``AetherWindow/cancelInteractiveKeyboardGestures()`` | Отмена in-flight жеста. |
| ``AetherWindow/doNotAnimateLikelyKeyboardAutocorrectionSwitch()`` | Подавление анимации для следующего изменения высоты ≤44pt (autocorrection bar). |

## Edge cases

- **Не выполняйте присваивание `window.rootViewController = ...`.**
  Корневой контроллер используется ``AetherWindowRootViewController``.
  Любое присваивание нарушит работу status bar и
  orientation. Используйте ``AetherWindow/contentController``.
- **Конфликт двух keyboard-pan recognizer'ов.** При использовании на
  экране `UIScrollView.keyboardDismissMode = .interactive` отключите
  window-level pan через
  ``AetherWindow/setInteractiveKeyboardPanEnabled(_:)``: одновременная
  работа двух механизмов приводит к рассинхронизации движения клавиатуры.
- **Артефакт `inputAccessoryView` при pop.** UIKit оставляет accessory
  view в нижней части экрана на несколько кадров после `popViewController`.
  Альтернативный подход: реализация input bar как обычного subview с
  передачей высоты через
  ``AetherWindow/setManualKeyboardGestureAccessoryHeight(_:)``.
- **`safeAreaInsets` равны `.zero` в первом цикле.** При создании окна и
  немедленном чтении `currentLayout.safeInsets` значение может быть
  `.zero` — UIKit ещё не выполнил расчёт. Окно пересчитает значения при
  первом `layoutSubviews` и вызовет последующий `containerLayoutUpdated`.

## See Also

- <doc:ViewController>
- <doc:NavigationController>
- <doc:TabBar>
