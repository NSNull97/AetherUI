import UIKit
import CrystalUI

final class ShowcaseSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = CrystalWindow(windowScene: windowScene)
        window.backgroundColor = .systemBackground

        // Tab layout: one tab per theme area, each with its own nav
        // controller so push/pop is isolated. Each tab's root is a simple
        // list controller that routes into per-component demos.
        let dialogs = Self.makeTab(
            root: ShowcaseListController(
                title: "Диалоги",
                rows: [
                    ("ActionSheet", "кнопки / чекбоксы / свитчи / текст", { ActionSheetDemoController() }),
                    ("Alert", "title + message + кнопки + поле", { AlertDemoController() }),
                    ("Tooltip", "указывает на view", { TooltipDemoController() }),
                    ("Toast / Snackbar", "snackbar внизу", { ToastDemoController() })
                ]
            ),
            item: UITabBarItem(
                title: "Диалоги",
                image: UIImage(systemName: "bubble.left.and.bubble.right"),
                selectedImage: UIImage(systemName: "bubble.left.and.bubble.right.fill")
            )
        )

        let glass = Self.makeTab(
            root: ShowcaseListController(
                title: "Glass",
                rows: [
                    ("GlassButton", "icon / title / icon+title / лифт", { GlassButtonDemoController() }),
                    ("Context Menu", "morph + preview + submenu", { ContextMenuDemoController() }),
                    ("NavigationBar Search", "title ↔ search pill", { NavigationBarSearchDemoController() })
                ]
            ),
            item: UITabBarItem(
                title: "Glass",
                image: UIImage(systemName: "drop"),
                selectedImage: UIImage(systemName: "drop.fill")
            )
        )

        let states = Self.makeTab(
            root: ShowcaseListController(
                title: "Состояния",
                rows: [
                    ("Content State", "loading / empty / error", { ContentStateDemoController() }),
                    ("Skeletons", "shimmer-плейсхолдеры", { SkeletonDemoController() })
                ]
            ),
            item: UITabBarItem(
                title: "Состояния",
                image: UIImage(systemName: "square.stack"),
                selectedImage: UIImage(systemName: "square.stack.fill")
            )
        )

        let navigation = Self.makeTab(
            root: ShowcaseListController(
                title: "Навигация",
                rows: [
                    ("Toolbar", "нижняя панель кнопок", { ToolbarDemoController() }),
                    ("Modal", "bottom-sheet detents", { ModalDemoController() }),
                    ("Collection", "grid со скроллом (для тест тулбара)", { CollectionDemoController() }),
                    ("Keyboard dismiss", "интерактивное закрытие пальцем", { KeyboardDismissDemoController() })
                ]
            ),
            item: UITabBarItem(
                title: "Навигация",
                image: UIImage(systemName: "square.grid.3x3"),
                selectedImage: UIImage(systemName: "square.grid.3x3.fill")
            )
        )

        let tabs = CrystalTabBarController(
            tabBarTheme: TabBarView.Theme(
                tabBarSelectedIconColor: .systemBlue,
                tabBarSelectedTextColor: .systemBlue,
                style: .liquidGlass
            )
        )
        tabs.setControllers([dialogs, glass, states, navigation], selectedIndex: 0)

        // Floating search pill in the tab bar. Tap → expands into a full
        // search field (see `CrystalTabBarController.activateSearch`).
        // Useful for fine-tuning the expansion animation.
        let searchIcon = UIImage(
            systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)
        ) ?? UIImage()
        tabs.searchShowcase = TabBarView.SearchShowcase(
            icon: searchIcon,
            action: { [weak tabs] in tabs?.activateSearch() }
        )

        window.contentController = tabs
        window.makeKeyAndVisible()
        self.window = window
    }

    private static func makeTab(root: ViewController, item: UITabBarItem) -> CrystalNavigationController {
        root.tabBarItem = item
        let nav = CrystalNavigationController(mode: .single, theme: .liquidGlass())
        nav.setViewControllers([root], animated: false)
        nav.tabBarItem = item
        return nav
    }
}
