# Search

Поисковые controllers и компоненты AetherUI: glass-pill в nav bar,
плавающий bottom-pill, активный search bar и tab-bar search item.

## Overview

AetherUI предоставляет несколько вариантов поисковых интерфейсов:

- ``AetherSearchController`` — основной API. Управляется через
  ``AetherViewController/searchController``. Автоматически выбирает
  размещение (`.navBar` или `.bottom`) в зависимости от наличия tab bar
  в иерархии.
- ``AetherSearchBarContent`` — статический glass-pill для размещения в
  ``AetherViewController/topBarAccessory`` без активного поведения.
- ``AetherActiveSearchBar`` — активный search bar с встроенным
  `UITextField` и cancel-кнопкой; используется как
  `NavigationBarContentView` в `.replacement` режиме.
- ``SearchTabItem`` — search-кружок рядом с tab bar pill'ом
  в стиле Apple Music; запускает поиск во весь экран.

## AetherSearchController

Основной поисковый controller с двумя режимами размещения и полным
жизненным циклом активации.

### Базовое использование

```swift
final class HomeController: AetherViewController {

    private let search = AetherSearchController()

    init() {
        super.init(navigationBarPresentationData: .liquidGlass())
        navigationItem.title = "Чаты"

        search.placeholder = "Поиск"
        search.delegate = self
        searchController = search
    }
    required init?(coder: NSCoder) { fatalError() }
}

extension HomeController: AetherSearchControllerDelegate {
    func searchController(_ controller: AetherSearchController, didChangeText text: String) {
        // Фильтрация данных по введённому тексту.
    }

    func searchController(_ controller: AetherSearchController, didSubmitText text: String) {
        // Submit по нажатию return.
    }
}
```

### Placement

Размещение определяется автоматически при `install`-вызове:

| Placement | Условие | Поведение |
|---|---|---|
| `.navBar` | ViewController внутри ``AetherTabBarController`` | Glass-pill в nav bar (`expansion`-зона). |
| `.bottom` | ViewController **не** внутри ``AetherTabBarController`` | Плавающий glass-pill внизу экрана с edge-effect. |

Принудительное использование `.bottom`:

```swift
search.prefersBottomPlacement = true
searchController = search
```

> Note: Placement определяется синхронно через walk по responder chain.
> При late-attaching tab bar (контроллер ещё не добавлен в иерархию на
> момент `install`) выполняется повторная проверка на следующем runloop
> tick с автоматическим promote'ом из `.bottom` в `.navBar`.

### Жизненный цикл активации (.navBar mode)

1. Тап по pill'у в nav bar.
2. Title и кнопки скрываются через alpha (easeInOut, 0.3с).
3. Filter chips (если присутствуют) скрываются; nav bar сжимается.
4. Pill смещается в title-position.
5. Iconка и placeholder pill'а скрываются; внутри появляется
   `UITextField`.
6. Glass close-кнопка (44pt по умолчанию) появляется справа от pill'а.
7. Клавиатура отображается; контент сдвигается вверх.

### Жизненный цикл деактивации

1. Тап по close-кнопке (или вызов
   ``AetherSearchController/deactivate()``).
2. Клавиатура скрывается одновременно с restore UI.
3. Close-кнопка scale-down + fade.
4. Text field удаляется; icon и placeholder восстанавливаются.
5. Nav bar расширяется; title, кнопки, filter chips появляются.
6. Контент сдвигается вниз.

### Программное управление

```swift
search.activate()    // активация без user interaction
search.deactivate()  // деактивация
search.isActive      // текущее состояние
search.searchText    // текущий текст (пустая строка при !isActive)
```

### Search results controller

Для отдельного экрана с результатами поиска:

```swift
class SearchResultsController: AetherViewController, AetherSearchContentController {
    func searchTextUpdated(text: String) {
        // Обновить отображаемые результаты.
    }
}

search.searchResultsController = SearchResultsController()
```

`AetherSearchContentController`-протокол требует только реализации
`searchTextUpdated(text:)`. Метод вызывается на каждое изменение текста и
при submit.

### Bottom mode

В `.bottom` mode pill размещается в плавающей нижней позиции с edge-effect
frost'ом, цвет/blur которого автоматически согласуются с nav bar темой:

```swift
search.placeholder = "Поиск"
search.prefersBottomPlacement = true
searchController = search
```

При активации pill сжимается, появляется close-кнопка справа, клавиатура
поднимает pill над собой.

#### Кастомный edge-effect

```swift
search.updateEdgeEffect(color: .systemGray6)
```

### Tab bar integration

Если ViewController находится внутри ``AetherTabBarController``, а один из
переданных контроллеров имеет `tabBarItem is SearchTabItem`, search-кружок
tab bar'а может триггерить активацию поиска через override:

```swift
class HomeController: AetherViewController {
    override func tabBarActivateSearch() {
        searchController?.activate()
    }
}
```

### Delegate

```swift
public protocol AetherSearchControllerDelegate: AnyObject {
    func searchControllerWillActivate(_ controller: AetherSearchController)
    func searchControllerDidActivate(_ controller: AetherSearchController)
    func searchController(_ controller: AetherSearchController, didChangeText text: String)
    func searchController(_ controller: AetherSearchController, didSubmitText text: String)
    func searchControllerWillDeactivate(_ controller: AetherSearchController)
    func searchControllerDidDeactivate(_ controller: AetherSearchController)
}
```

Все методы имеют default-имплементации (пустые), реализация только нужных
методов опциональна.

## AetherSearchBarContent

Статический glass-pill для случаев, когда нужен только визуальный
search-pill без полного жизненного цикла:

```swift
let searchPill = AetherSearchBarContent()
searchPill.placeholder = "Поиск"
searchPill.onTap = { [weak self] in
    self?.openCustomSearchScreen()
}
viewController.topBarAccessory = searchPill
```

`onTap`-callback срабатывает по тапу. Pill отображается в `.expansion`
режиме.

### Свойства

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `placeholder` | `String` | `"Search"` | Placeholder text. |
| `onTap` | `(() -> Void)?` | `nil` | Callback на тап по pill'у. |
| `isDark` | `Bool` | `false` | Принудительное dark-оформление. |
| `pillHeight` | `CGFloat` | `44.0` | Высота pill'а. |
| `horizontalInset` | `CGFloat` | `16.0` | Горизонтальный inset до pill'а. |
| `rightExtraInset` | `CGFloat` | `0.0` | Дополнительный right inset (для размещения close-кнопки в active state). |

### setSearchActive

```swift
searchPill.setSearchActive(true)   // скрыть icon и placeholder
searchPill.setSearchActive(false)  // восстановить
```

Используется ``AetherSearchController`` для управления видимостью при
активации; не предназначен для прямого использования.

## AetherActiveSearchBar

Активный search bar с встроенным `UITextField` и cancel-кнопкой:

```swift
let activeBar = AetherActiveSearchBar()
activeBar.placeholder = "Поиск"
activeBar.cancelTitle = "Отмена"
activeBar.onTextChanged = { text in
    print("Text: \(text)")
}
activeBar.onCancel = { [weak self] in
    self?.dismissSearch()
}
viewController.topBarAccessory = activeBar
```

Bar отображается в `.replacement` режиме (заменяет title row). При
добавлении автоматически становится first responder, если
`activatesOnAppear = true` (default).

### Свойства

| Свойство | Тип | По умолчанию | Назначение |
|---|---|---|---|
| `placeholder` | `String` | `"Search"` | Placeholder text. |
| `text` | `String` | `""` | Текущий текст (read-write). |
| `cancelTitle` | `String` | `"Cancel"` | Title cancel-кнопки. |
| `pillHeight` | `CGFloat` | `44.0` | Высота pill'а. |
| `horizontalInset` | `CGFloat` | `16.0` | Горизонтальный inset до pill'а. |
| `activatesOnAppear` | `Bool` | `true` | Автоматический становление first responder при добавлении. |
| `onTextChanged` | `((String) -> Void)?` | `nil` | Callback на изменение текста. |
| `onReturn` | `((String) -> Void)?` | `nil` | Callback на нажатие return. |
| `onCancel` | `(() -> Void)?` | `nil` | Callback на тап по cancel-кнопке. |

### Программное управление

```swift
activeBar.activate()    // become first responder
activeBar.deactivate()  // resign first responder
```

## SearchTabItem

Кружок поиска рядом с tab bar pill'ом (Apple Music style):

```swift
let search = UIViewController()
search.tabBarItem = SearchTabItem(image: UIImage(systemName: "magnifyingglass")!)

tabs.setControllers([home, settings, search], selectedIndex: 0)
```

При вызове ``AetherTabBarController/activateSearch()``:

1. Tab bar pill сжимается до иконки активной вкладки.
2. Search-кружок расширяется в горизонтальную glass-капсулу с
   встроенным `UITextField`.
3. Поле не становится first responder автоматически; это только
   pre-focus morph. Клавиатура появляется после явного тапа в поле.
4. Spring-анимация с glassmorphism scale-эффектами.

Деактивация (``AetherTabBarController/deactivateSearch()``):

1. Reverse-морф: капсула fade + scale-down обратно в кружок.
2. Tab bar pill восстанавливает pre-search состояние: полный layout,
   если до поиска он был полным, или остается minimized, если поиск
   открыт из minimized chrome.

ViewController может реагировать на активацию через override:

```swift
override func tabBarActivateSearch() {
    // Поиск открыт из tab bar — подготовить search UI без auto-focus.
}

override func tabBarDeactivateSearch() {
    // Поиск деактивирован.
}
```

Подробнее об интеграции с tab bar — <doc:TabBar>.

## API сводка

### ``AetherSearchController``

| Свойство / метод | Назначение |
|---|---|
| `placeholder` | Placeholder text. |
| `delegate` | Delegate. |
| `isActive` | Текущее состояние (read-only). |
| `searchText` | Текущий текст (read-only). |
| `searchResultsController` | Опциональный controller с результатами. |
| `closeButtonSize` | Размер close-кнопки (default 44pt). |
| `prefersBottomPlacement` | Принудительное использование `.bottom` placement. |
| `placement` | Текущее placement (read-only). |
| `activate()` | Программная активация. |
| `deactivate()` | Программная деактивация. |
| `updateEdgeEffect(color:)` | Обновление цвета bottom-edge-effect. |

### ``AetherSearchBarContent``

См. таблицу свойств выше.

### ``AetherActiveSearchBar``

См. таблицу свойств выше.

## Edge cases

- **Search pill «прыгает» при первом отображении.** Может произойти при
  late-attaching tab bar: placement определяется как `.bottom`, затем
  promote'ся в `.navBar`. Решение: добавить ViewController в иерархию
  до установки `searchController`.
- **Bottom pill не реагирует на тапы.** Tap recognizer подключается к
  `pill.contentView`, **не** к самому pill'у. ``GlassBackgroundView/hitTest(_:with:)``
  forwards в `contentContainer.hitTest`, который возвращает `nil`, если
  на контейнере нет gesture recognizers — это намеренное поведение для
  glass-«проходимых» поверхностей. Подключение recognizer'а на
  `contentView` обходит этот фильтр.
- **Search pill отображается под scroll content.** При установке
  `searchController` в `viewDidLoad` до добавления scroll/collection
  view, последний может оказаться поверх pill'а. ``AetherSearchController``
  выполняет `bringSubviewToFront` при каждом layout pass'е, что
  поддерживает корректный z-order.
- **Two-stage cancel в bottom mode.** При активации в bottom mode pill
  сжимается параллельно с появлением клавиатуры. Если отмена
  выполняется до завершения spring-анимации, текст поля очищается, но
  визуальная anim не прерывается — состояние корректное.

## See Also

- <doc:ViewController>
- <doc:NavigationBar>
- <doc:TabBar>
- <doc:Glass>
