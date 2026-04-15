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

        let chatsController = ChatListExampleController()
        chatsController.tabBarItem = UITabBarItem(
            title: "Чаты",
            image: UIImage(systemName: "message.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
            selectedImage: UIImage(systemName: "message.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))
        )
        chatsController.tabBarItem.badgeValue = "4"

        let callsController = CallsExampleController()
        callsController.tabBarItem = UITabBarItem(
            title: "Звонки",
            image: UIImage(systemName: "phone.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
            selectedImage: UIImage(systemName: "phone.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))
        )

        let contactsController = ContactsExampleController()
        contactsController.tabBarItem = UITabBarItem(
            title: "Контакты",
            image: UIImage(systemName: "person.crop.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
            selectedImage: UIImage(systemName: "person.crop.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))
        )

        let settingsController = SettingsExampleController()
        settingsController.tabBarItem = UITabBarItem(
            title: "Настройки",
            image: UIImage(systemName: "gearshape.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
            selectedImage: UIImage(systemName: "gearshape.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))
        )

        let tabs = TelegramTabBarController(
            navigationBarPresentationData: NavigationBarPresentationData(theme: .liquidGlass()),
            tabBarTheme: TabBarView.Theme(
                tabBarSelectedIconColor: .systemBlue,
                tabBarSelectedTextColor: .systemBlue,
                style: .liquidGlass
            )
        )
        tabs.setControllers([contactsController, callsController, chatsController, settingsController], selectedIndex: 2)
        // iOS 26-style search showcase capsule sitting next to the tab pill.
        tabs.searchShowcase = TabBarView.SearchShowcase {
            // Hook up to an actual search presentation in real apps.
            print("Search showcase tapped")
        }

        let navigation = TelegramNavigationController(
            mode: .single,
            theme: .liquidGlass()
        )
        navigation.setViewControllers([tabs], animated: false)

        window.rootViewController = navigation
        window.makeKeyAndVisible()
        self.window = window

        // Demo-only: auto-push a detail screen after launch so screenshots can
        // verify the back-button glass capsule layout without UI automation.
        if ProcessInfo.processInfo.environment["TG_NAV_DEMO_PUSH"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak navigation] in
                navigation?.pushViewController(
                    ChatDetailExampleController(title: "Pool Duck"),
                    animated: true
                )
            }
        }

        // Demo-only: auto-present the sticker-pack modal to verify the sheet
        // transition and Figma-style modal nav bar.
        if ProcessInfo.processInfo.environment["TG_NAV_DEMO_MODAL"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak navigation] in
                let modal = StickerPackModalController(
                    navigationBarPresentationData: NavigationBarPresentationData(theme: .liquidGlass())
                )
                navigation?.presentModal(modal, animated: true)
            }
        }

    }
}
