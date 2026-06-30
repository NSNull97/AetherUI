import UIKit
import AetherUI

final class DemoApplication: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            WindowScene(id: "main") { scene in
                DemoRootController(title: "Main", sceneID: scene.sceneID.rawValue)
            }
            .onConnect { context in
                print("main scene connected", context.sceneID)
            }
            .onRender { context in
                print("render", context.sceneID, context.phase)
            }

            WindowScene(id: "details", priority: 10) { scene in
                DemoRootController(title: "Details", sceneID: scene.sceneID.rawValue)
            }
            .matchesURL { url in
                url.scheme == "aether-demo" && url.host == "details"
            }

            AppLifecycle()
                .onDidFinishLaunching { context in
                    print("did finish launching", context.launchOptions ?? [:])
                    return true
                }
                .onDidBecomeActive { _ in
                    print("app active")
                }
                .onDidEnterBackground { _ in
                    print("app background")
                }

            URLRouting()
                .strategy(.firstHandled)
                .onOpenURL { context in
                    print("open url", context.url)
                    return false
                }

            RemoteNotifications()
                .onReceive { context in
                    print("remote notification", context.userInfo)
                    context.completion?(.noData)
                }

            BackgroundEvents()
                .onFetch { context in
                    print("background fetch")
                    context.completion(.noData)
                }

            Diagnostics()
                .enableRuntimeDump()
                .enableSignposts()
        }
    }
}

@main
final class DemoAppDelegate: AetherApplicationDelegateProxy<DemoApplication> {}

final class DemoRootController: UIViewController {
    private let label = UILabel()
    private let titleText: String
    private let sceneID: String

    init(title: String, sceneID: String) {
        self.titleText = title
        self.sceneID = sceneID
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "\(titleText) scene: \(sceneID)"
        label.font = .preferredFont(forTextStyle: .title2)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
