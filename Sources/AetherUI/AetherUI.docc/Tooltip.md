# Tooltip

Pop-up tooltip с указателем-стрелкой к source view. Поддерживает text,
icon + text, custom layout. Автоматически выбирает направление стрелки
для оптимального позиционирования.

## Overview

``AetherTooltipController`` — controller для отображения контекстных
подсказок:

- Text-only или icon + text content.
- Автоматический выбор направления стрелки (.up, .down, .left, .right).
- Темы `.dark`, `.light`, или кастомная ``AetherTooltipTheme``.
- Auto-dismiss через `timeout` (default 2с).
- Презентация анкорно к source view с настраиваемым source rect.

## Базовый шаблон

### Text-only

```swift
let tooltip = AetherTooltipController(
    content: .text("Эта кнопка отправляет сообщение"),
    theme: .dark
)
tooltip.timeout = 3.0
tooltip.present(from: sendButton)
```

### Icon + text

```swift
let tooltip = AetherTooltipController(
    content: .iconText(
        icon: UIImage(systemName: "info.circle"),
        text: "Подробная информация"
    )
)
tooltip.present(from: infoButton)
```

### Custom source rect

По умолчанию tooltip анкорится к `sourceView.bounds`. Кастомный rect:

```swift
tooltip.present(
    from: containerView,
    sourceRect: CGRect(x: 100, y: 50, width: 30, height: 30)
)
```

## AetherTooltipContent

```swift
public enum AetherTooltipContent: Equatable {
    case text(String)
    case iconText(icon: UIImage?, text: String)
}
```

## AetherTooltipArrowDirection

```swift
public enum AetherTooltipArrowDirection {
    case up
    case down
    case left
    case right
}
```

Направление выбирается автоматически на основе позиции source view
относительно safe area:

- Source в top half → стрелка вверх (tooltip снизу от source).
- Source в bottom half → стрелка вниз (tooltip сверху от source).
- Source у leading/trailing edge → горизонтальные направления.

Перекрытия корректно избегаются.

## Theme

```swift
public struct AetherTooltipTheme: Equatable {
    public let backgroundColor: UIColor
    public let textColor: UIColor
    public let iconTintColor: UIColor?
    public let cornerRadius: CGFloat
    public let font: UIFont
    public let shadowColor: UIColor
    public let shadowOpacity: Float
}
```

### Built-in темы

```swift
AetherTooltipTheme.dark    // тёмный фон, светлый текст (default)
AetherTooltipTheme.light   // светлый фон, тёмный текст
```

## Программное управление

```swift
tooltip.dismiss(animated: true)
tooltip.timeout = 5.0
tooltip.theme = .light
tooltip.dismissed = { /* completion */ }
```

## API

### ``AetherTooltipController``

| Свойство / метод | Назначение |
|---|---|
| `init(content:theme:)` | Создание. |
| `theme` | Текущая тема (read-write). |
| `content` | Read-only content. |
| `timeout` | Длительность показа (default 2с). |
| `dismissed` | Completion. |
| `present(from:sourceRect:)` | Презентация анкорно к source view. |
| `dismiss(animated:)` | Программное закрытие. |

### ``AetherTooltipContent``

См. enum cases выше.

### ``AetherTooltipArrowDirection``

См. enum cases выше.

### ``AetherTooltipTheme``

См. таблицу свойств выше.

## Edge cases

- **Source view не в window.** Tooltip требует source view, добавленный
  в активную window (через parent hierarchy). При отсутствии window
  presentation no-op.
- **Custom sourceRect outside source bounds.** sourceRect интерпретируется
  в координатах source view. Точки за пределами `sourceView.bounds`
  допустимы, но могут привести к несогласованному позиционированию
  стрелки.
- **Tooltip во время layout-transition'а.** Tooltip кэширует initial
  position; при resize/rotation должен быть закрыт явно
  (`dismiss(animated: false)`) и перепрезентован с новым sourceRect.
- **`timeout = 0`.** Tooltip не закрывается автоматически; требуется
  explicit `dismiss(animated:)`.

## See Also

- <doc:Toast>
- <doc:ContextMenu>
