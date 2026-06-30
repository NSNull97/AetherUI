import UIKit

open class AetherSceneDelegateProxy: UIResponder, UIWindowSceneDelegate {
    public var window: UIWindow?
    public weak var sceneInstance: AetherSceneInstance?

    private var runtime: AetherApplicationRuntime? {
        AetherApplicationRuntime.shared
    }

    open override func responds(to aSelector: Selector!) -> Bool {
        if let selector = AetherDelegateSelector(selector: aSelector) {
            return runtime?.selectorGate.shouldRespond(to: selector) ?? false
        }
        return super.responds(to: aSelector)
    }

    open func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        runtime?.connectScene(scene, session: session, options: connectionOptions, delegate: self)
    }

    open func sceneDidDisconnect(_ scene: UIScene) {
        guard let instance = sceneInstance else {
            return
        }
        runtime?.disconnectScene(instance)
        window = nil
        sceneInstance = nil
    }

    open func sceneDidBecomeActive(_ scene: UIScene) {
        guard let instance = sceneInstance else {
            return
        }
        runtime?.sceneDidBecomeActive(instance)
    }

    open func sceneWillResignActive(_ scene: UIScene) {
        guard let instance = sceneInstance else {
            return
        }
        runtime?.sceneWillResignActive(instance)
    }

    open func sceneWillEnterForeground(_ scene: UIScene) {
        guard let instance = sceneInstance else {
            return
        }
        runtime?.sceneWillEnterForeground(instance)
    }

    open func sceneDidEnterBackground(_ scene: UIScene) {
        guard let instance = sceneInstance else {
            return
        }
        runtime?.sceneDidEnterBackground(instance)
    }

    open func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let instance = sceneInstance else {
            return
        }
        runtime?.sceneOpenURLContexts(instance, contexts: URLContexts)
    }

    open func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        guard let runtime, let instance = sceneInstance else {
            return nil
        }
        let context = instance.windowContext(environment: runtime.environment(forScene: instance))
        for handler in runtime.configuration.stateRestorationHandlers.sceneRestorationActivity {
            if let activity = handler(context) {
                return activity
            }
        }
        return nil
    }

    open func scene(_ scene: UIScene, restoreInteractionStateWith stateRestorationActivity: NSUserActivity) {
        guard let runtime, let instance = sceneInstance else {
            return
        }
        let context = instance.windowContext(environment: runtime.environment(forScene: instance))
        runtime.configuration.stateRestorationHandlers.sceneRestoreInteractionState.forEach {
            $0(context, stateRestorationActivity)
        }
    }

    open func scene(_ scene: UIScene, willContinueUserActivityWithType userActivityType: String) {
        guard let runtime, let instance = sceneInstance else {
            return
        }
        let context = AetherUserActivityTypeContext(
            application: nil,
            sceneID: instance.definition.id,
            userActivityType: userActivityType,
            environment: runtime.environment(forScene: instance)
        )
        _ = runtime.configuration.userActivityHandlers.willContinue.allSatisfy { $0(context) }
    }

    open func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let runtime, let instance = sceneInstance else {
            return
        }
        let context = AetherUserActivityContext(
            application: nil,
            sceneID: instance.definition.id,
            userActivity: userActivity,
            restorationHandler: nil,
            environment: runtime.environment(forScene: instance)
        )
        _ = runtime.configuration.userActivityHandlers.didContinue.contains { $0(context) }
    }

    open func scene(
        _ scene: UIScene,
        didFailToContinueUserActivityWithType userActivityType: String,
        error: Error
    ) {
        guard let runtime, let instance = sceneInstance else {
            return
        }
        let context = AetherUserActivityFailureContext(
            application: nil,
            sceneID: instance.definition.id,
            userActivityType: userActivityType,
            error: error,
            environment: runtime.environment(forScene: instance)
        )
        runtime.configuration.userActivityHandlers.didFail.forEach { $0(context) }
    }

    open func scene(_ scene: UIScene, didUpdate userActivity: NSUserActivity) {
        guard let runtime, let instance = sceneInstance else {
            return
        }
        let context = AetherUserActivityContext(
            application: nil,
            sceneID: instance.definition.id,
            userActivity: userActivity,
            restorationHandler: nil,
            environment: runtime.environment(forScene: instance)
        )
        runtime.configuration.userActivityHandlers.didUpdate.forEach { $0(context) }
    }

    open func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        sceneInstance?.renderUpdatedContent()
    }

    open func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let instance = sceneInstance else {
            completionHandler(false)
            return
        }
        runtime?.performShortcutItem(
            application: nil,
            sceneID: instance.definition.id,
            shortcutItem: shortcutItem,
            completion: completionHandler
        )
    }
}
