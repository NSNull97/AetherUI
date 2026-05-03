import UIKit
import AetherUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = AetherWindow(windowScene: windowScene)
        window.backgroundColor = .systemBackground

        // Native-iOS shape:
        //   AetherTabBarController  (window root, owns tab bar, no nav bar)
        //     └─ AetherNavigationController per tab
        //         └─ root screen (plus any pushed details)
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 21)

        let componentsTab = makeTab(
            root: makeComponentsRoot(),
            title: "Components",
            symbolName: "rectangle.grid.2x2",
            symbolConfig: symbolConfig
        )
        let statesTab = makeTab(
            root: makeStatesRoot(),
            title: "States",
            symbolName: "sparkles",
            symbolConfig: symbolConfig
        )
        let collectionTab = makeTab(
            root: ListDemoController(),
            title: "ListView",
            symbolName: "list.bullet.rectangle",
            symbolConfig: symbolConfig
        )
        let settingsRoot = SettingsController()
        let settingsTab = makeTab(
            root: settingsRoot,
            title: "Settings",
            symbolName: "gearshape.fill",
            symbolConfig: symbolConfig
        )

        let tabs = AetherTabBarController(
            tabBarTheme: TabBarView.Theme(
                tabBarSelectedIconColor: .systemBlue,
                tabBarSelectedTextColor: .systemBlue,
                style: .liquidGlass
            )
        )
        tabs.setControllers([componentsTab, statesTab, collectionTab, settingsTab], selectedIndex: 0)
        tabs.searchShowcase = TabBarView.SearchShowcase(
            icon: UIImage(systemName: "magnifyingglass", withConfiguration: symbolConfig),
            action: { [weak tabs] in tabs?.activateSearch() }
        )

        // SettingsController drives the tab bar's chrome — wire the
        // back-reference now so toggles inside Settings find it.
        settingsRoot.hostTabBar = tabs

        window.contentController = tabs
        window.makeKeyAndVisible()
        self.window = window
    }

    private func makeTab(
        root: AetherViewController,
        title: String,
        symbolName: String,
        symbolConfig: UIImage.SymbolConfiguration
    ) -> AetherNavigationController {
        let icon = UIImage(systemName: symbolName, withConfiguration: symbolConfig)
        let item = UITabBarItem(title: title, image: icon, selectedImage: icon)
        root.tabBarItem = item
        let nav = AetherNavigationController(mode: .single, theme: .liquidGlass())
        nav.setViewControllers([root], animated: false)
        nav.tabBarItem = item
        return nav
    }
}
