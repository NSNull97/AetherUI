# Toast

Краткое всплывающее уведомление с автоматическим скрытием. Поддерживает
text, icon, action-кнопку. Анкорится над tab bar (если присутствует) или
над home indicator.

## Overview

``AetherToastController`` — лёгкий toast-controller с поддержкой:

- Text-only, icon + text, или text + action.
- Темы `.light`, `.dark`, или кастомная ``AetherToastTheme``.
- Автоматическое скрытие через `timeout` (default 3с).
- Tap-to-dismiss (опционально).
- Анкоринг к chrome (tab bar) или к safe area.

## Базовый шаблон

### Text-only

```swift
let toast = AetherToastController(
    content: .text("Сообщение скопировано"),
    theme: .dark
)
toast.timeout = 2.0
toast.present()
```

### Icon + text

```swift
let toast = AetherToastController(
    content: .iconText(
        icon: UIImage(systemName: "checkmark.circle.fill")!,
        text: "Файл загружен"
    )
)
toast.present()
```

### Text + action

```swift
let toast = AetherToastController(
    content: .textWithAction(
        text: "Сообщение удалено",
        action: AetherToastAction(title: "Восстановить") {
            // Undo logic
        }
    )
)
toast.timeout = 5.0
toast.present()
```

## AetherToastContent

```swift
public enum AetherToastContent {
    case text(String)
    case iconText(icon: UIImage, text: String)
    case textWithAction(text: String, action: AetherToastAction)
    case iconTextWithAction(icon: UIImage, text: String, action: AetherToastAction)
}
```

## AetherToastAction

```swift
public struct AetherToastAction: Equatable {
    public let title: String
    public let handler: () -> Void
}
```

При тапе на action toast автоматически закрывается, после чего
вызывается `handler`.

## Theme

```swift
public struct AetherToastTheme: Equatable {
    public let backgroundColor: UIColor
    public let textColor: UIColor
    public let actionColor: UIColor
    public let iconTintColor: UIColor?
    public let cornerRadius: CGFloat
    public let textFont: UIFont
    public let actionFont: UIFont
}
```

### Built-in темы

```swift
AetherToastTheme.dark       // тёмный фон, светлый текст (default)
AetherToastTheme.light      // светлый фон, тёмный текст
```

## Интеграция с NavigationController

```swift
let toast = AetherToastController(content: .text("Готово"))
aetherNavigationController?.presentOverlay(toast, animated: true)
```

При таком вызове toast становится overlay-контейнером nav controller'а
(см. <doc:NavigationController>) и автоматически закрывается через
timeout.

### Direct present

```swift
toast.present(in: someParentView)   // presentation на конкретный view
```

При `parent: nil` toast presents в key window.

## Программное управление

```swift
toast.dismiss(animated: true)              // программное закрытие

toast.timeout = 5.0                        // изменение timeout
toast.theme = .light                       // динамическая смена темы
toast.dismissed = { /* completion */ }
```

## Анкоринг

Toast автоматически анкорится:

- Над ``AetherTabBarController/chromeTopY(in:)`` (если внутри
  tab bar controller'а).
- Над home indicator (через `safeAreaInsets.bottom`).

Side margin: 16pt от боковых границ. Bottom gap: 12pt над chrome.

## API

### ``AetherToastController``

| Свойство / метод | Назначение |
|---|---|
| `init(content:theme:)` | Создание. |
| `theme` | Текущая тема (read-write). |
| `content` | Read-only content. |
| `timeout` | Длительность показа (default 3с). |
| `dismissed` | Completion. |
| `present(in:)` | Презентация (default — key window). |
| `dismiss(animated:)` | Программное закрытие. |

### ``AetherToastContent``

См. enum cases выше.

### ``AetherToastAction``

См. struct выше.

### ``AetherToastTheme``

См. таблицу свойств выше.

## Edge cases

- **Два toast'а одновременно.** Каждый toast — независимый controller;
  при presents второго первый не закрывается автоматически. Они
  накладываются (z-order по очерёдности present'а).
- **Toast во время push/pop.** При активном transition'е toast корректно
  rebinds к новому top controller'у при использовании
  `presentOverlay(_:animated:)`. Toast при direct `present(in:)` остаётся
  в исходном view tree.
- **Action handler во время dismiss.** Action handler вызывается **после**
  завершения dismiss-анимации; safe для presentation нового UI.
- **`timeout = 0`.** Toast не закрывается автоматически; требуется
  explicit `dismiss(animated:)` или tap по action.

## See Also

- <doc:Tooltip>
- <doc:Alert>
- <doc:NavigationController>
