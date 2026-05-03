# Alert

Алерт-контроллер с title, message, текстовыми полями и actions.
Glass-стилизованный аналог `UIAlertController` с расширенным
функционалом.

## Overview

``AetherAlertController`` — модальный controller для отображения
alert-диалогов:

- Title и message (опциональные).
- Один или несколько ``AetherAlertAction`` (default, cancel, destructive).
- Опциональные ``AetherAlertTextField`` для ввода данных.
- Темы `.light`, `.dark`, `.system`, или кастомная
  ``AetherAlertTheme``.
- Tap-outside dismissal (опционально).
- Keyboard navigation (Cmd+. для cancel, Return для default).

## Базовый шаблон

### Простой alert

```swift
let alert = AetherAlertController(
    title: "Удалить элемент?",
    message: "Это действие нельзя отменить.",
    actions: [
        AetherAlertAction(title: "Удалить", style: .destructive) {
            // Удаление
        },
        AetherAlertAction(title: "Отмена", style: .cancel) { }
    ]
)
present(alert, animated: true)
```

### Alert с textField

```swift
let alert = AetherAlertController(
    title: "Введите имя",
    message: "Имя будет отображено в профиле",
    textFieldConfigs: [
        AetherAlertTextField(
            label: "Имя",
            placeholder: "Введите имя",
            initialText: "",
            isSecureTextEntry: false,
            keyboardType: .default,
            onChanged: { text in
                // Live validation
            }
        )
    ],
    actions: [
        AetherAlertAction(title: "Сохранить", style: .default) { [weak alert] in
            let name = alert?.textFieldValue(at: 0) ?? ""
            print("Name: \(name)")
        },
        AetherAlertAction(title: "Отмена", style: .cancel) { }
    ]
)
present(alert, animated: true)
```

## AetherAlertAction

```swift
public struct AetherAlertAction {
    public enum Style {
        case `default`     // основное действие
        case cancel        // отмена (кнопка слева/снизу)
        case destructive   // деструктивное (красный)
    }

    public let title: String
    public let style: Style
    public let enabled: Bool
    public let handler: () -> Void

    public init(title: String, style: Style = .default, enabled: Bool = true, handler: @escaping () -> Void)
}
```

### Style

| Style | Цвет | Поведение |
|---|---|---|
| `.default` | `accentColor` | Основное действие. Triggered Return. |
| `.cancel` | `primaryColor` | Отмена. Triggered Cmd+. |
| `.destructive` | `destructiveColor` | Опасное действие. |

> Note: Должна быть только одна `.cancel`-action в alert. При наличии
> нескольких UIKit-конвенция использует первую.

## AetherAlertTextField

```swift
public struct AetherAlertTextField {
    public let label: String?           // optional label выше textField
    public let placeholder: String
    public let initialText: String
    public let isSecureTextEntry: Bool
    public let keyboardType: UIKeyboardType
    public let onChanged: (String) -> Void
}
```

### Получение значения

```swift
let text = alert.textFieldValue(at: 0)   // String? — значение i-го textField
```

### Live validation

```swift
let alert = AetherAlertController(
    title: "Email",
    textFieldConfigs: [
        AetherAlertTextField(
            placeholder: "user@example.com",
            keyboardType: .emailAddress,
            onChanged: { text in
                let isValid = text.contains("@")
                // Динамическое включение/выключение save-кнопки
            }
        )
    ],
    actions: [
        AetherAlertAction(title: "Сохранить", enabled: false, ...)
        // ...
    ]
)
```

## Theme

```swift
public struct AetherAlertTheme: Equatable {
    public let backgroundType: AetherActionSheetBackgroundType
    public let backgroundColor: UIColor
    public let separatorColor: UIColor
    public let highlightedItemColor: UIColor
    public let primaryColor: UIColor
    public let secondaryColor: UIColor
    public let accentColor: UIColor
    public let destructiveColor: UIColor
    public let disabledColor: UIColor
    public let dimColor: UIColor
    public let pillFillColor: UIColor
    public let primaryFillColor: UIColor
    public let primaryTextColor: UIColor
    public let baseFontSize: CGFloat
}
```

### Built-in темы

```swift
AetherAlertTheme.light    // светлая
AetherAlertTheme.dark     // тёмная
AetherAlertTheme.system   // адаптивная (light/dark)
```

## Программное управление

```swift
alert.theme = .dark                     // динамическая смена темы
alert.dismissOnOutsideTap = false       // блокировка tap-outside
alert.dismissed = { isDismissedByUser in
    // completion
}

alert.dismissAnimated()                 // программное закрытие

// Чтение значений textField'ов:
alert.textFieldValue(at: 0)             // String?
```

## Convenience init

```swift
let alert = AetherAlertController(
    title: "Заголовок",
    message: "Сообщение",
    actions: [
        AetherAlertAction(title: "OK", style: .default) { /* ... */ }
    ]
)
```

Эквивалент:

```swift
AetherAlertController(
    title: "Заголовок",
    message: "Сообщение",
    actions: [...],
    textFieldConfigs: []
)
```

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Return` | Triggered первой `.default`-action. |
| `Cmd+.` | Triggered `.cancel`-action. |

## API

### ``AetherAlertController``

| Свойство / метод | Назначение |
|---|---|
| `init(title:message:textFieldConfigs:actions:theme:)` | Полная инициализация. |
| `init(title:message:actions:theme:)` | Convenience init без textField'ов. |
| `theme` | Текущая тема (read-write). |
| `alertTitle` / `alertMessage` | Read-only title/message. |
| `actions` | Read-only массив actions. |
| `textFieldConfigs` | Read-only массив textField configs. |
| `dismissOnOutsideTap` | Управление tap-outside dismiss (default `true`). |
| `dismissed` | Completion closure. |
| `textFieldValue(at:)` | Чтение значения i-го textField'а. |
| `dismissAnimated()` | Программное закрытие. |

### ``AetherAlertAction``

См. таблицу свойств выше.

### ``AetherAlertTextField``

См. таблицу свойств выше.

### ``AetherAlertTheme``

См. таблицу свойств выше.

## Edge cases

- **Two cancel-actions.** При наличии двух `.cancel`-actions UIKit
  конвенция использует первую для `Cmd+.` и tap-outside. Вторую
  treat'ится как `.default`.
- **Disabled action.** При `enabled: false` action отображается
  `disabledColor` и не реагирует на tap. Полезно для submit-кнопок,
  активирующихся только при validation pass.
- **textField без label.** `label: nil` рендерит textField без подписи
  выше; placeholder отображается внутри.
- **Tap on dim region with `dismissOnOutsideTap = false`.** Tap
  игнорируется; alert не закрывается. `dismissed` не вызывается.

## See Also

- <doc:ActionSheet>
- <doc:Modal>
- <doc:Glass>
