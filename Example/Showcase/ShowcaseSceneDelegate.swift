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

        let home = ShowcaseHomeController()
        let nav = CrystalNavigationController(mode: .single, theme: .liquidGlass())
        nav.setViewControllers([home], animated: false)

        window.contentController = nav
        window.makeKeyAndVisible()
        self.window = window
    }
}
