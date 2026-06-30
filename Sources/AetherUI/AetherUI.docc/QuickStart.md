# Quick Start

Минимальное рабочее приложение на AetherUI: окно → tab bar → навигация → push.

## Overview

Данная статья проводит читателя через минимальный полнофункциональный скелет
приложения на AetherUI: установка пакета, настройка `SceneDelegate`,
корневой tab bar, два экрана, push к деталям и обратно. По её прочтении
рекомендуется ознакомиться с <doc:ViewController>, <doc:NavigationController>
и <doc:TabBar> для углублённого изучения.

> Tip: Для интерактивного ознакомления откройте Xcode-проект `Example/Showcase`
> в репозитории — он содержит работающие демонстрации каждого компонента.

## Установка

### Swift Package Manager

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/nicko170/AetherUI.git", from: "1.0.0")
]

// targets:
.target(
    name: "MyApp",
    dependencies: ["AetherUI"]
)
```

### Через Xcode

`File → Add Package Dependencies… → URL: https://github.com/nicko170/AetherUI.git`

### Импорт

```swift
import AetherUI
```

## Шаг 1. Окно

AetherUI требует, чтобы корневым view-объектом окна был ``AetherWindow``,
а не `UIWindow`. Это необходимо для работы keyboard tracking, status bar
dispatch и `containerLayoutUpdated`-цепочки: фреймворк опирается на
``ContainerViewLayout``, формирование которого происходит на уровне окна.

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

        // 1. Корневое окно — AetherWindow.
        let window = AetherWindow(windowScene: windowScene)

        // 2. Главный контроллер присваивается через `contentController`,
        //    а НЕ через `rootViewController` (он используется внутренним root).
        window.contentController = makeRootTabBarController()
        window.makeKeyAndVisible()

        self.window = window
    }
}
```

> Warning: Не присваивайте свой контроллер в `rootViewController` напрямую —
> это нарушит работу status bar, orientation и keyboard dispatch. Используйте
> ``AetherWindow/contentController``.

## Шаг 2. Базовый экран

Все экраны наследуются от ``AetherViewController`` (не `UIViewController`). Это
обеспечивает:

- Собственный ``NavigationBarView`` с корректным glass-фоном, edge-эффектом
  и back-кнопкой.
- Метод ``AetherViewController/containerLayoutUpdated(_:transition:)`` — единая
  точка раскладки, в которую поступают изменения размера и keyboard frame.
- Точки расширения для top-bar accessory, floating toolbar, search-controller
  и других компонентов.

```swift
import AetherUI

final class HomeController: AetherViewController {

    private let label = UILabel()

    init() {
        super.init()
        navigationItem.title = "Главная"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        label.text = "Содержимое экрана"
        label.textAlignment = .center
        view.addSubview(label)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout,
                                         transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        // cleanNavigationHeight — нижняя граница nav bar (с учётом safe area).
        let topInset = cleanNavigationHeight
        transition.updateFrame(
            view: label,
            frame: CGRect(x: 0, y: topInset,
                          width: layout.size.width,
                          height: layout.size.height - topInset)
        )
    }
}
```

Ключевые моменты:

- `super.init()` использует app-level appearance. Fullscreen-экраны могут
  отключить бар через ``AetherViewController/displayNavigationBar``.
- Стандартный `UINavigationItem` (`title`, `rightBarButtonItem` и т.д.)
  поддерживается напрямую — AetherUI отслеживает его изменения и
  перестраивает содержимое бара.
- Раскладка должна выполняться через ``ContainedViewLayoutTransition``,
  а не напрямую через `UIView.animate`. Это обеспечивает синхронизацию с
  системными анимациями (keyboard, push/pop, modal detent change).

## Шаг 3. Навигационный стек

Навигация осуществляется через ``AetherNavigationController``,
функционально эквивалентный `UINavigationController`, со следующими
отличиями:

- При push выполняется glass-morph переход между nav bar'ами вместо
  стандартного fade.
- Левый edge-swipe (~20 pt) активирует интерактивный pop с параллаксом 30%.
- Заголовок и кнопки переходят синхронно с баром.

```swift
let nav = AetherNavigationController(mode: .single)
nav.setViewControllers([HomeController()], animated: false)
```

Push/pop из `ViewController`:

```swift
final class HomeController: AetherViewController {
    @objc private func openDetail() {
        push(DetailController(), animated: true)
    }
}

final class DetailController: AetherViewController {
    init() {
        super.init()
        navigationItem.title = "Детали"

        // Стандартный UIBarButtonItem поддерживается напрямую.
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            style: .plain, target: self, action: #selector(menu)
        )
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func menu() { /* ... */ }
}
```

> Tip: ``AetherViewController/push(_:animated:)`` поднимается по родительской
> цепочке и определяет ближайший ``AetherNavigationController``. Метод
> может быть вызван из любого вложенного контроллера без необходимости
> передачи ссылки через всю иерархию.

## Шаг 4. Tab bar

``AetherTabBarController`` — корневой контейнер с плавающим pill'ом:

```swift
func makeRootTabBarController() -> AetherTabBarController {

    func makeTab(_ root: ViewController, item: UITabBarItem) -> AetherNavigationController {
        let nav = AetherNavigationController(mode: .single)
        nav.setViewControllers([root], animated: false)
        nav.tabBarItem = item
        return nav
    }

    let chats = makeTab(HomeController(), item: UITabBarItem(
        title: "Чаты",
        image: UIImage(systemName: "message.fill"),
        tag: 0
    ))

    let settings = makeTab(SettingsController(), item: UITabBarItem(
        title: "Настройки",
        image: UIImage(systemName: "gearshape.fill"),
        tag: 1
    ))

    let tabs = AetherTabBarController()
    tabs.setControllers([chats, settings], selectedIndex: 0)

    return tabs
}
```

> Important: `AetherTabBarController` ожидает в качестве дочерних
> контроллеров **именно** ``AetherNavigationController`` или
> ``AetherViewController``, а не `UINavigationController`. Использование
> `UINavigationController` нарушит layout dispatch.

### Search-кружок (Apple Music style)

Опциональный круглый control рядом с pill'ом: при тапе tab bar
сворачивается в active-tab 48×48, а search control разворачивается в
поле без автоматического focus:

```swift
let search = UIViewController()
search.tabBarItem = SearchTabItem(image: UIImage(systemName: "magnifyingglass")!)

tabs.setControllers([chats, settings, search], selectedIndex: 0)
```

Подробнее — <doc:Search>.

## Шаг 5. Modal

Двухдетентный glass-sheet, презентуемый через стандартный UIKit
`present(_:animated:)`:

```swift
let content = ContentController()
let modal = AetherModalController(content: content)
modal.primaryScrollView = content.scrollView    // (опц.) кооперация со скроллом
present(modal, animated: true)

// Программное переключение детента:
modal.setDetent(.stage2, animated: true)
```

Подробнее — <doc:Modal>.

## Шаг 6. Toast

Краткое всплывающее уведомление с автоматическим скрытием:

```swift
let toast = AetherToastController(text: "Сообщение скопировано")
aetherNavigationController?.presentOverlay(toast, animated: true)
```

Подробнее — <doc:Toast>.

## Итоговая структура приложения

```
SceneDelegate
 └── AetherWindow
      └── AetherTabBarController                // tabs
           ├── AetherNavigationController       // tab 1: «Чаты»
           │    └── HomeController              // ViewController
           │         (push) → DetailController  // ViewController
           └── AetherNavigationController       // tab 2: «Настройки»
                └── SettingsController          // ViewController
```

## Дальнейшее изучение

- <doc:ViewController> — жизненный цикл, layout, accessory-зоны, focus
- <doc:NavigationController> — push/pop, замена стека, edge-swipe, минимизация
- <doc:NavigationBar> — theme, title, accessory-контент, search
- <doc:TabBar> — theme pill'а, badges, accessory над tab bar'ом
- <doc:Glass> — низкоуровневые primitives
- <doc:Modal> — модальный sheet, детенты, glass dim
- <doc:ListView> — виртуализованный список с transactions

## Дополнительная информация

> Tip: Если nav bar или tab bar отображается некорректно (двойной safe-area
> отступ, рассинхронизация при анимации) — наиболее вероятная причина:
> `view.addSubview` выполнен вне раскладки AetherUI без учёта
> ``AetherViewController/cleanNavigationHeight`` и ``ContainerViewLayout/safeInsets``.
> Раскладка subview-объектов должна выполняться **исключительно** в
> ``AetherViewController/containerLayoutUpdated(_:transition:)``.
