# ActionSheet

Action sheet с группами items: button, text, switch, checkbox.
Презентуется снизу с blur background и dim overlay.

## Overview

``AetherActionSheetController`` — модальный controller для отображения
групп действий в стиле iOS Action Sheet с расширенной поддержкой:

- Группы из ``AetherActionSheetItemGroup``.
- Item-типы: ``AetherActionSheetButtonItem``,
  ``AetherActionSheetTextItem``,
  ``AetherActionSheetSwitchItem``,
  ``AetherActionSheetCheckboxItem``.
- Кастомные item-views через ``AetherActionSheetItemView``-подкласс.
- Темы `.light` и `.dark`, или кастомная ``AetherActionSheetTheme``.

## Базовый шаблон

```swift
let sheet = AetherActionSheetController(theme: .light)
sheet.setItemGroups([
    AetherActionSheetItemGroup(items: [
        AetherActionSheetTextItem(title: "Действия"),
        AetherActionSheetButtonItem(title: "Поделиться", action: { /* ... */ }),
        AetherActionSheetButtonItem(
            title: "Удалить",
            color: .destructive,
            action: { /* ... */ }
        )
    ]),
    AetherActionSheetItemGroup(items: [
        AetherActionSheetButtonItem(
            title: "Отмена",
            font: .bold,
            action: { sheet.dismissAnimated() }
        )
    ])
])
sheet.dismissed = { /* completion */ }
present(sheet, animated: true)
```

## Item типы

### AetherActionSheetButtonItem

Tappable button с цветом и шрифтом:

```swift
AetherActionSheetButtonItem(
    title: "Удалить",
    color: .destructive,    // .accent | .destructive | .disabled
    font: .default,         // .default | .bold
    enabled: true,
    action: { /* ... */ }
)
```

#### Color

| Color | Использует тему |
|---|---|
| `.accent` | `controlAccentColor` |
| `.destructive` | `destructiveActionTextColor` |
| `.disabled` | `disabledActionTextColor` |

#### Font

| Font | Описание |
|---|---|
| `.default` | Regular system font. |
| `.bold` | Semibold system font. |

### AetherActionSheetTextItem

Static label, обычно используется как header группы:

```swift
AetherActionSheetTextItem(
    title: "Выберите действие",
    font: .default     // .default | .small
)
```

### AetherActionSheetSwitchItem

Toggle switch с label:

```swift
AetherActionSheetSwitchItem(
    title: "Включить уведомления",
    isOn: true,
    action: { newValue in
        print("Switch: \(newValue)")
    }
)
```

### AetherActionSheetCheckboxItem

Checkbox с label и value text:

```swift
AetherActionSheetCheckboxItem(
    title: "Получать обновления",
    label: "ежедневно",
    value: true,
    style: .check,         // .check | .alternative
    action: { newValue in
        print("Checkbox: \(newValue)")
    }
)
```

#### CheckboxStyle

| Style | Описание |
|---|---|
| `.check` | Стандартный checkmark. |
| `.alternative` | Альтернативный visual style. |

## Кастомный item

Реализация custom item требует пары: structure conforming
``AetherActionSheetItem`` + UIView-подкласс
``AetherActionSheetItemView``:

```swift
public final class MyCustomItem: AetherActionSheetItem {
    public func makeView(theme: AetherActionSheetTheme) -> AetherActionSheetItemView {
        return MyCustomItemView(theme: theme)
    }

    public func updateView(_ view: AetherActionSheetItemView) {
        guard let view = view as? MyCustomItemView else { return }
        // Обновить state
    }
}

public final class MyCustomItemView: AetherActionSheetItemView {
    public override init(theme: AetherActionSheetTheme) {
        super.init(theme: theme)
        // Setup subviews
    }

    public required init?(coder: NSCoder) { fatalError() }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Layout subviews
    }

    public override func performAction() {
        // Tap handling
    }
}
```

## Theme

```swift
public struct AetherActionSheetTheme: Equatable {
    public let dimColor: UIColor
    public let backgroundType: AetherActionSheetBackgroundType
    public let itemBackgroundColor: UIColor
    public let itemHighlightedBackgroundColor: UIColor
    public let standardActionTextColor: UIColor
    public let destructiveActionTextColor: UIColor
    public let disabledActionTextColor: UIColor
    public let primaryTextColor: UIColor
    public let secondaryTextColor: UIColor
    public let controlAccentColor: UIColor
    public let controlColor: UIColor
    public let separatorColor: UIColor
    public let baseFontSize: CGFloat
}
```

### Built-in темы

```swift
AetherActionSheetTheme.light    // светлая
AetherActionSheetTheme.dark     // тёмная
```

### AetherActionSheetBackgroundType

| Type | Описание |
|---|---|
| `.blur` | Системный blur background. |
| `.solid(UIColor)` | Сплошной цвет. |

## Программное управление

```swift
sheet.dismissAnimated()                    // программное закрытие
sheet.theme = .dark                        // динамическая смена темы
sheet.dismissed = { isDismissedByUser in
    // completion (true — если closed by tap outside)
}

// Обновление item:
sheet.updateItem(groupIndex: 0, itemIndex: 1) { oldItem in
    return AetherActionSheetButtonItem(
        title: "Updated",
        action: { /* ... */ }
    )
}
```

## API

### ``AetherActionSheetController``

| Свойство / метод | Назначение |
|---|---|
| `init(theme:)` | Создание (default theme = `.light`). |
| `theme` | Текущая тема (read-write). |
| `dismissed` | Closure после dismiss. |
| `setItemGroups(_:)` | Установка групп items. |
| `updateItem(groupIndex:itemIndex:_:)` | Обновление конкретного item. |
| `dismissAnimated()` | Программное закрытие. |

### ``AetherActionSheetItem`` (протокол)

| Метод | Назначение |
|---|---|
| `makeView(theme:)` | Создание view для item'а. |
| `updateView(_:)` | Обновление существующего view. |

### ``AetherActionSheetItemGroup``

| Свойство | Тип | Назначение |
|---|---|---|
| `items` | `[AetherActionSheetItem]` | Items группы. |

### ``AetherActionSheetItemView`` (базовый класс)

| Свойство / метод | Назначение |
|---|---|
| `theme` | Тема. |
| `backgroundView` | Background view (highlighted state). |
| `separatorView` | Separator view (между items). |
| `hasSeparator` | Управление видимостью separator'а. |
| `defaultItemHeight` (static) | 57pt. |
| `preferredHeight(constrainedWidth:)` | Override для custom высоты. |
| `setHighlighted(_:animated:)` | Управление highlight (override). |
| `performAction()` | Tap-action (override). |

### Item type details

См. таблицы свойств выше для каждого типа.

## Edge cases

- **Tap outside dismisses the sheet.** По default tap по dim region'у
  закрывает sheet. `dismissed`-callback получает `isDismissedByUser = true`.
  Чтобы блокировать tap-outside dismiss, программно management нужно
  override controller.
- **Custom item с нестандартной высотой.** Override
  `preferredHeight(constrainedWidth:)` в подклассе
  ``AetherActionSheetItemView``. Default — 57pt.
- **Cancel-кнопка идиома.** Стандартная iOS-конвенция: cancel-кнопка в
  отдельной (последней) группе с жирным шрифтом (`.bold`).

## See Also

- <doc:Alert>
- <doc:Modal>
- <doc:Glass>
