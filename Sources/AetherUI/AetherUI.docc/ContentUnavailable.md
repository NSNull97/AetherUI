# ContentUnavailable

UIKit-style overlay для empty / loading / error состояний. Аналог
`UIViewController.aetherContentUnavailableConfiguration` (iOS 17+) с
поддержкой iOS 13+.

## Overview

AetherUI предоставляет полнофункциональный content-unavailable
overlay, работающий на iOS 13+:

- ``AetherContentUnavailableConfiguration`` — value-type конфигурация
  (image, text, secondary text, button, loading indicator, background).
- ``AetherContentUnavailableView`` — view, отображающий конфигурацию.
- Готовые presets: `.empty()`, `.loading()`, `.error()`.
- Cross-fade анимация при изменении конфигурации.
- Интеграция через ``AetherViewController/aetherContentUnavailableConfiguration``.

> Note: Префикс `aether` намеренный — UIKit на iOS 17+ ввёл собственный
> `contentUnavailableConfiguration`. Префикс предотвращает коллизию имён.

## Базовый шаблон

### Через ViewController

```swift
class HomeController: AetherViewController {
    func showEmptyState() {
        var config = AetherContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: "tray")
        config.text = "Здесь пока пусто"
        config.secondaryText = "При появлении данных они будут отображены"
        aetherContentUnavailableConfiguration = config
    }

    func hideEmptyState() {
        aetherContentUnavailableConfiguration = nil
    }
}
```

Подробнее об интеграции — <doc:ViewController> (раздел
«Content-unavailable overlay»).

### Прямое использование

```swift
let view = AetherContentUnavailableView()
view.frame = parentView.bounds
parentView.addSubview(view)

var config = AetherContentUnavailableConfiguration.error()
config.text = "Ошибка загрузки"
config.secondaryText = "Проверьте соединение с интернетом"
config.button.title = "Повторить"
config.button.handler = { /* retry */ }

view.configuration = config
```

## Presets

### empty()

```swift
let config = AetherContentUnavailableConfiguration.empty()
// image, text, secondaryText — пустые; button — пустой
// Кастомизируйте необходимые свойства.
```

### loading()

```swift
let config = AetherContentUnavailableConfiguration.loading()
// loadingIndicator активен; используется в loading-states
```

### error()

```swift
let config = AetherContentUnavailableConfiguration.error()
// Стандартизированный error visual (warning icon + цвет)
```

## Configuration

```swift
public struct AetherContentUnavailableConfiguration {
    public var image: UIImage?
    public var imageProperties: ImageProperties
    public var text: String?
    public var textProperties: TextProperties
    public var secondaryText: String?
    public var secondaryTextProperties: TextProperties
    public var button: ButtonProperties
    public var loadingIndicator: LoadingIndicatorProperties?
    public var background: BackgroundProperties
    public var directionalLayoutMargins: NSDirectionalEdgeInsets
    public var imageToTextPadding: CGFloat
    public var textToSecondaryTextPadding: CGFloat
    public var textToButtonPadding: CGFloat
}
```

### ImageProperties

```swift
public struct ImageProperties {
    // tintColor, contentMode, accessibilityLabel, ...
}
```

### TextProperties

```swift
public struct TextProperties {
    // font, color, alignment, numberOfLines, lineBreakMode, ...
}
```

### ButtonProperties

```swift
public struct ButtonProperties {
    public var title: String?
    public var handler: (() -> Void)?
    // backgroundColor, titleColor, font, cornerRadius, ...
}
```

### LoadingIndicatorProperties

```swift
public struct LoadingIndicatorProperties {
    // style, color, ...
}
```

### BackgroundProperties

```swift
public struct BackgroundProperties {
    // backgroundColor, blur, ...
}
```

## Сценарии использования

### Empty list state

```swift
override func viewDidLoad() {
    super.viewDidLoad()
    fetchItems()
}

func handleFetchResult(_ items: [Item]) {
    if items.isEmpty {
        var config = AetherContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: "tray")
        config.text = "Список пуст"
        config.button.title = "Создать"
        config.button.handler = { [weak self] in
            self?.openCreate()
        }
        aetherContentUnavailableConfiguration = config
    } else {
        aetherContentUnavailableConfiguration = nil
        // Отображение items
    }
}
```

### Loading → success / error transition

```swift
// Loading:
setAetherContentUnavailableConfiguration(.loading(), animated: true)

Task {
    do {
        let data = try await fetchData()
        await MainActor.run {
            setAetherContentUnavailableConfiguration(nil, animated: true)
            displayData(data)
        }
    } catch {
        var config = AetherContentUnavailableConfiguration.error()
        config.text = "Ошибка"
        config.secondaryText = error.localizedDescription
        config.button.title = "Повторить"
        config.button.handler = { /* retry */ }
        await MainActor.run {
            setAetherContentUnavailableConfiguration(config, animated: true)
        }
    }
}
```

### Search results empty

```swift
func updateSearchResults(_ results: [SearchResult], query: String) {
    if results.isEmpty {
        var config = AetherContentUnavailableConfiguration.empty()
        config.image = UIImage(systemName: "magnifyingglass")
        config.text = "Ничего не найдено"
        config.secondaryText = "Попробуйте другой запрос для «\(query)»"
        aetherContentUnavailableConfiguration = config
    } else {
        aetherContentUnavailableConfiguration = nil
    }
}
```

## API

### ``AetherContentUnavailableConfiguration``

| Свойство | Тип | Назначение |
|---|---|---|
| `image` | `UIImage?` | Главное изображение / icon. |
| `imageProperties` | `ImageProperties` | Свойства image (tint, content mode). |
| `text` | `String?` | Главный text. |
| `textProperties` | `TextProperties` | Свойства text (font, color). |
| `secondaryText` | `String?` | Subtitle. |
| `secondaryTextProperties` | `TextProperties` | Свойства subtitle. |
| `button` | `ButtonProperties` | Optional кнопка. |
| `loadingIndicator` | `LoadingIndicatorProperties?` | Activity indicator. |
| `background` | `BackgroundProperties` | Background overlay. |
| `directionalLayoutMargins` | `NSDirectionalEdgeInsets` | Внешние margins. |
| `imageToTextPadding` | `CGFloat` | Gap между image и text. |
| `textToSecondaryTextPadding` | `CGFloat` | Gap между text и subtitle. |
| `textToButtonPadding` | `CGFloat` | Gap между text/subtitle и кнопкой. |

### Static presets

| Preset | Назначение |
|---|---|
| `.empty()` | Empty state (без icon/text). |
| `.loading()` | Loading state (activity indicator). |
| `.error()` | Error state (warning icon, цвет). |

### ``AetherContentUnavailableView``

| Свойство / метод | Назначение |
|---|---|
| `init(configuration:)` | Создание с initial configuration. |
| `configuration` | Текущая конфигурация (read-write). |
| `setConfiguration(_:animated:)` | Animated смена. |
| `transitionDuration` | Длительность cross-fade (default 0.18с). |

### Интеграция с ViewController

| Свойство / метод | Назначение |
|---|---|
| `ViewController.aetherContentUnavailableConfiguration` | Установка/чтение конфигурации. |
| `ViewController.setAetherContentUnavailableConfiguration(_:animated:)` | Animated смена. |

## Edge cases

- **Configuration без image/text/button.** View остаётся пустым; height
  collapses к sum margin'ов. Это допустимое state — например, для
  «hidden» режима без отображения чего-либо visible.
- **Hit-testing через overlay.** Overlay блокирует touch events своего
  region'а. Chrome (nav bar, tab bar, floating toolbar) остаётся
  интерактивным благодаря z-order'у внутри ``AetherViewController``: overlay
  размещается **под** chrome.
- **Cross-fade с одинаковой текущей и new конфигурацией.** При
  передаче эквивалентной конфигурации `setConfiguration(_:animated:)`
  no-op'ится; transition не выполняется.
- **Background blur.** При `background.blur = true` overlay использует
  `UIVisualEffectView` для затенения content под overlay'ем. По default
  background прозрачный.

## See Also

- <doc:ViewController>
- <doc:Skeleton>
