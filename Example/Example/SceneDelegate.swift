import UIKit
import TelegramNavigationKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)

        // Native-iOS shape:
        //   TelegramTabBarController  (window root, owns tab bar, no nav bar)
        //     └─ TelegramNavigationController per tab
        //         └─ root screen (plus any pushed details)
        //
        // Each tab's navigation controller manages its own stack and its
        // own nav bar. Push/pop inside a tab slides the screen + its bar
        // together; the tab bar stays visible.

        func makeTab(_ root: ViewController, tabBarItem: UITabBarItem) -> TelegramNavigationController {
            root.tabBarItem = tabBarItem
            let nav = TelegramNavigationController(mode: .single, theme: .liquidGlass())
            nav.setViewControllers([root], animated: false)
            // Propagate the tab bar item onto the nav controller itself —
            // that's the controller the tab bar sees and renders for.
            nav.tabBarItem = tabBarItem
            return nav
        }

        let contacts = makeTab(
            ContactsExampleController(),
            tabBarItem: UITabBarItem(
                title: "Контакты",
                image: UIImage(systemName: "person.crop.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
                selectedImage: UIImage(systemName: "person.crop.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))
            )
        )
        let calls = makeTab(
            CallsExampleController(),
            tabBarItem: UITabBarItem(
                title: "Звонки",
                image: UIImage(systemName: "phone.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
                selectedImage: UIImage(systemName: "phone.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))
            )
        )
        let chatsRoot = ChatListExampleController()
        let chats = makeTab(
            chatsRoot,
            tabBarItem: UITabBarItem(
                title: "Чаты",
                image: UIImage(systemName: "message.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
                selectedImage: UIImage(systemName: "message.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))
            )
        )
        chats.tabBarItem.badgeValue = "4"
        let settings = makeTab(
            SettingsExampleController(),
            tabBarItem: UITabBarItem(
                title: "Настройки",
                image: UIImage(systemName: "gearshape.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
                selectedImage: UIImage(systemName: "gearshape.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))
            )
        )

        let tabs = TelegramTabBarController(
            tabBarTheme: TabBarView.Theme(
                tabBarSelectedIconColor: .systemBlue,
                tabBarSelectedTextColor: .systemBlue,
                style: .liquidGlass
            )
        )
        tabs.setControllers([contacts, calls, chats, settings], selectedIndex: 2)
        tabs.searchShowcase = TabBarView.SearchShowcase(
            icon: UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))!,
            action: { print("Search tapped") }
        )

        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window

        // Demo-only: auto-push a detail screen after launch so screenshots can
        // verify the back-button glass capsule layout without UI automation.
        if ProcessInfo.processInfo.environment["TG_NAV_DEMO_PUSH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak chatsRoot] in
                guard let chatsRoot else { return }
                chatsRoot.push(ChatDetailExampleController(title: "Pool Duck"))
            }
        }

        // Demo-only: auto-present the sticker-pack modal to verify the sheet
        // transition and Figma-style modal nav bar.
        if ProcessInfo.processInfo.environment["TG_NAV_DEMO_MODAL"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak chats] in
                let modal = StickerPackModalController(
                    navigationBarPresentationData: NavigationBarPresentationData(theme: .liquidGlass())
                )
                chats?.presentModal(modal, animated: true)
            }
        }
    }
}
