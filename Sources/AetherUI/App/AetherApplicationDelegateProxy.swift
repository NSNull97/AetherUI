import UIKit

open class AetherApplicationDelegateProxy<App: AetherApp>: UIResponder, UIApplicationDelegate {
    public let runtime: AetherApplicationRuntime
    public var window: UIWindow?

    public override init() {
        self.runtime = AetherApplicationRuntime.installShared(App.self)
        super.init()
    }

    open override func responds(to aSelector: Selector!) -> Bool {
        if let selector = AetherDelegateSelector(selector: aSelector) {
            return runtime.selectorGate.shouldRespond(to: selector)
        }
        return super.responds(to: aSelector)
    }

    open func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let before = legacyLaunchResult(application, launchOptions: launchOptions, order: .beforeAether, didFinish: false)
        let aether = runtime.applicationWillFinishLaunching(application, launchOptions: launchOptions)
        let after = legacyLaunchResult(application, launchOptions: launchOptions, order: .afterAether, didFinish: false)
        return before && aether && after
    }

    open func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let before = legacyLaunchResult(application, launchOptions: launchOptions, order: .beforeAether, didFinish: true)
        let aether = runtime.applicationDidFinishLaunching(application, launchOptions: launchOptions)
        let after = legacyLaunchResult(application, launchOptions: launchOptions, order: .afterAether, didFinish: true)
        return before && aether && after
    }

    open func applicationDidBecomeActive(_ application: UIApplication) {
        legacyDelegates(order: .beforeAether).forEach { $0.applicationDidBecomeActive?(application) }
        runtime.applicationDidBecomeActive(application)
        legacyDelegates(order: .afterAether).forEach { $0.applicationDidBecomeActive?(application) }
    }

    open func applicationWillResignActive(_ application: UIApplication) {
        legacyDelegates(order: .beforeAether).forEach { $0.applicationWillResignActive?(application) }
        runtime.applicationWillResignActive(application)
        legacyDelegates(order: .afterAether).forEach { $0.applicationWillResignActive?(application) }
    }

    open func applicationDidEnterBackground(_ application: UIApplication) {
        legacyDelegates(order: .beforeAether).forEach { $0.applicationDidEnterBackground?(application) }
        runtime.applicationDidEnterBackground(application)
        legacyDelegates(order: .afterAether).forEach { $0.applicationDidEnterBackground?(application) }
    }

    open func applicationWillEnterForeground(_ application: UIApplication) {
        legacyDelegates(order: .beforeAether).forEach { $0.applicationWillEnterForeground?(application) }
        runtime.applicationWillEnterForeground(application)
        legacyDelegates(order: .afterAether).forEach { $0.applicationWillEnterForeground?(application) }
    }

    open func applicationWillTerminate(_ application: UIApplication) {
        legacyDelegates(order: .beforeAether).forEach { $0.applicationWillTerminate?(application) }
        runtime.applicationWillTerminate(application)
        legacyDelegates(order: .afterAether).forEach { $0.applicationWillTerminate?(application) }
    }

    open func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        legacyDelegates(order: .beforeAether).forEach { $0.applicationDidReceiveMemoryWarning?(application) }
        runtime.applicationDidReceiveMemoryWarning(application)
        legacyDelegates(order: .afterAether).forEach { $0.applicationDidReceiveMemoryWarning?(application) }
    }

    open func applicationSignificantTimeChange(_ application: UIApplication) {
        legacyDelegates(order: .beforeAether).forEach { $0.applicationSignificantTimeChange?(application) }
        runtime.applicationSignificantTimeChange(application)
        legacyDelegates(order: .afterAether).forEach { $0.applicationSignificantTimeChange?(application) }
    }

    open func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if legacyDelegates(order: .beforeAether).contains(where: { $0.application?(app, open: url, options: options) == true }) {
            return true
        }
        if runtime.openURL(app, url: url, options: options) {
            return true
        }
        return legacyDelegates(order: .afterAether).contains { $0.application?(app, open: url, options: options) == true }
    }

    open func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        legacyDelegates(order: .beforeAether).forEach { $0.application?(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken) }
        runtime.didRegisterForRemoteNotifications(application, deviceToken: deviceToken)
        legacyDelegates(order: .afterAether).forEach { $0.application?(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken) }
    }

    open func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        legacyDelegates(order: .beforeAether).forEach { $0.application?(application, didFailToRegisterForRemoteNotificationsWithError: error) }
        runtime.didFailToRegisterForRemoteNotifications(application, error: error)
        legacyDelegates(order: .afterAether).forEach { $0.application?(application, didFailToRegisterForRemoteNotificationsWithError: error) }
    }

    @available(iOS, deprecated: 10.0, message: "Use application(_:didReceiveRemoteNotification:fetchCompletionHandler:) or UserNotifications.")
    open func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) {
        legacyDelegates(order: .beforeAether).forEach { $0.application?(application, didReceiveRemoteNotification: userInfo) }
        runtime.didReceiveRemoteNotification(application, userInfo: userInfo, completion: nil)
        legacyDelegates(order: .afterAether).forEach { $0.application?(application, didReceiveRemoteNotification: userInfo) }
    }

    open func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        runtime.didReceiveRemoteNotification(application, userInfo: userInfo, completion: completionHandler)
    }

    open func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        runtime.performFetch(application, completion: completionHandler)
    }

    open func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        runtime.handleBackgroundURLSession(application, identifier: identifier, completion: completionHandler)
    }

    open func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        runtime.performShortcutItem(application: application, sceneID: nil, shortcutItem: shortcutItem, completion: completionHandler)
    }

    open func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication) {
        legacyDelegates(order: .beforeAether).forEach { $0.applicationProtectedDataWillBecomeUnavailable?(application) }
        legacyDelegates(order: .afterAether).forEach { $0.applicationProtectedDataWillBecomeUnavailable?(application) }
    }

    open func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        legacyDelegates(order: .beforeAether).forEach { $0.applicationProtectedDataDidBecomeAvailable?(application) }
        legacyDelegates(order: .afterAether).forEach { $0.applicationProtectedDataDidBecomeAvailable?(application) }
    }

    open func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        if let aetherWindow = window as? AetherWindow {
            return aetherWindow.rootViewController?.supportedInterfaceOrientations ?? .allButUpsideDown
        }
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    open func application(
        _ application: UIApplication,
        shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier
    ) -> Bool {
        true
    }

    open func application(_ application: UIApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        runRestorationBoolHandlers(runtime.configuration.stateRestorationHandlers.shouldSaveSecureApplicationState, application: application, coder: coder)
    }

    open func application(_ application: UIApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        runRestorationBoolHandlers(runtime.configuration.stateRestorationHandlers.shouldRestoreSecureApplicationState, application: application, coder: coder)
    }

    open func application(
        _ application: UIApplication,
        viewControllerWithRestorationIdentifierPath identifierComponents: [String],
        coder: NSCoder
    ) -> UIViewController? {
        for handler in runtime.configuration.stateRestorationHandlers.viewControllerWithRestorationPath {
            if let controller = handler(application, identifierComponents, coder) {
                return controller
            }
        }
        return nil
    }

    open func application(_ application: UIApplication, willEncodeRestorableStateWith coder: NSCoder) {
        runtime.configuration.stateRestorationHandlers.willEncodeRestorableState.forEach { $0(application, coder) }
    }

    open func application(_ application: UIApplication, didDecodeRestorableStateWith coder: NSCoder) {
        runtime.configuration.stateRestorationHandlers.didDecodeRestorableState.forEach { $0(application, coder) }
    }

    open func application(_ application: UIApplication, willContinueUserActivityWithType userActivityType: String) -> Bool {
        let context = AetherUserActivityTypeContext(
            application: application,
            sceneID: nil,
            userActivityType: userActivityType,
            environment: runtime.currentEnvironment
        )
        return runtime.configuration.userActivityHandlers.willContinue.allSatisfy { $0(context) }
    }

    open func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        let context = AetherUserActivityContext(
            application: application,
            sceneID: nil,
            userActivity: userActivity,
            restorationHandler: restorationHandler,
            environment: runtime.currentEnvironment
        )
        return runtime.configuration.userActivityHandlers.didContinue.contains { $0(context) }
    }

    open func application(
        _ application: UIApplication,
        didFailToContinueUserActivityWithType userActivityType: String,
        error: Error
    ) {
        let context = AetherUserActivityFailureContext(
            application: application,
            sceneID: nil,
            userActivityType: userActivityType,
            error: error,
            environment: runtime.currentEnvironment
        )
        runtime.configuration.userActivityHandlers.didFail.forEach { $0(context) }
    }

    open func application(_ application: UIApplication, didUpdate userActivity: NSUserActivity) {
        let context = AetherUserActivityContext(
            application: application,
            sceneID: nil,
            userActivity: userActivity,
            restorationHandler: nil,
            environment: runtime.currentEnvironment
        )
        runtime.configuration.userActivityHandlers.didUpdate.forEach { $0(context) }
    }

    open func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if runtime.configuration.scenes.isEmpty {
            for delegate in legacyDelegates(order: .beforeAether) + legacyDelegates(order: .afterAether) {
                if let configuration = delegate.application?(
                    application,
                    configurationForConnecting: connectingSceneSession,
                    options: options
                ) {
                    return configuration
                }
            }
        }
        return runtime.sceneConfiguration(for: connectingSceneSession, options: options)
    }

    open func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        runtime.discardSceneSessions(sceneSessions)
    }

    @available(iOS 15.0, *)
    open func applicationShouldAutomaticallyLocalizeKeyCommands(_ application: UIApplication) -> Bool {
        true
    }

    private func legacyDelegates(order: AetherLegacyBridgeOrder) -> [any UIApplicationDelegate] {
        runtime.configuration.legacyAppDelegates
            .filter { $0.order == order }
            .map(\.existing)
    }

    private func legacyLaunchResult(
        _ application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?,
        order: AetherLegacyBridgeOrder,
        didFinish: Bool
    ) -> Bool {
        legacyDelegates(order: order).allSatisfy { delegate in
            if didFinish {
                return delegate.application?(application, didFinishLaunchingWithOptions: launchOptions) ?? true
            } else {
                return delegate.application?(application, willFinishLaunchingWithOptions: launchOptions) ?? true
            }
        }
    }

    private func runRestorationBoolHandlers(
        _ handlers: [(UIApplication, NSCoder) -> Bool],
        application: UIApplication,
        coder: NSCoder
    ) -> Bool {
        guard !handlers.isEmpty else {
            return false
        }
        return handlers.allSatisfy { $0(application, coder) }
    }
}
