# SegmentedControl

iOS-style segmented control с настраиваемой темой, async-validation
перед commit'ом и smooth thumb-анимацией.

## Overview

``AetherSegmentedControl`` — UIControl-аналог `UISegmentedControl` с
расширенным функционалом:

- Items с title + опциональным image.
- Кастомизируемая тема (colors, fonts, sizing).
- Async validation перед commit'ом selected index.
- Smooth thumb-анимация.

## Базовый шаблон

```swift
let segmented = AetherSegmentedControl(
    items: [
        .init(title: "All"),
        .init(title: "Photos"),
        .init(title: "Videos")
    ],
    selectedIndex: 0,
    theme: AetherSegmentedControl.Theme()
)
segmented.selectedIndexChanged = { index in
    print("Selected: \(index)")
}
view.addSubview(segmented)
```

## Item

```swift
public struct Item: Equatable {
    public let title: String
    public let image: UIImage?
    // ...
}
```

## Theme

```swift
public final class Theme: Equatable {
    // backgroundColor, thumbColor, textColor, selectedTextColor,
    // disabledTextColor, font, selectedFont, ...
}
```

## Async validation

Перед commit'ом нового selected index выполняется async-validation:

```swift
segmented.selectedIndexShouldChange = { newIndex, commit in
    // commit(true) — разрешить переключение
    // commit(false) — заблокировать (selected index не меняется)

    Task {
        let isAllowed = await checkPermission()
        await MainActor.run {
            commit(isAllowed)
        }
    }
}
```

Если `selectedIndexShouldChange` не установлен, переключение разрешено
по default. После commit вызывается `selectedIndexChanged`.

## Layout

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `cornerRadius` | `CGFloat?` | `nil` | `nil` — capsule (height/2). |
| `thumbInset` | `CGFloat` | `2.0` | Inset thumb'а от border'ов. |
| `preferredHeight` | `CGFloat` | `36.0` | Preferred высота (используется в `intrinsicContentSize`). |

## Программное управление

```swift
segmented.items = [...]                            // обновление items
segmented.selectedIndex = 1                         // мгновенно
segmented.setSelectedIndex(2, animated: true)       // анимировано

segmented.updateTheme(newTheme)                     // динамическая смена темы
```

## API

### ``AetherSegmentedControl``

| Свойство / метод | Назначение |
|---|---|
| `init(items:selectedIndex:theme:)` | Создание. |
| `items` | Items (read-write). |
| `selectedIndex` | Selected index (read-write). |
| `setSelectedIndex(_:animated:)` | Animated переключение. |
| `selectedIndexChanged` | Callback после commit'а. |
| `selectedIndexShouldChange` | Async validation closure. |
| `cornerRadius` | Corner radius (`nil` → capsule). |
| `thumbInset` | Inset thumb'а. |
| `preferredHeight` | Default `intrinsicContentSize.height`. |
| `updateTheme(_:)` | Динамическая смена темы. |

### ``AetherSegmentedControl/Item``

См. структуру выше.

### ``AetherSegmentedControl/Theme``

См. свойства выше.

## Edge cases

- **`selectedIndex` out of bounds.** При `items.count == 0` или
  `selectedIndex >= items.count` value clamps к valid range; thumb
  скрывается при пустых items.
- **Async validation timeout.** При отсутствии вызова `commit(_:)`
  внутри `selectedIndexShouldChange` selected index остаётся в исходном
  state. UI feedback (thumb position) не возвращается; рекомендуется
  явный `commit(false)` для cancel-ов.
- **Theme смена во время animated transition'а.** `updateTheme(_:)`
  применяется immediately; in-flight thumb animation продолжается с
  новыми цветами.

## See Also

- <doc:Glass>
- <doc:NavigationBar>
