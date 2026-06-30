import UIKit
import os.signpost

public final class AetherApplicationRuntime {
    public private(set) static var shared: AetherApplicationRuntime?

    public let configuration: AetherApplicationRuntimeConfiguration
    public let sceneRegistry: AetherSceneRegistry

    private var appPhase: AetherAppPhase
    private var environment: AetherAppEnvironmentValues
    private var scenesByIdentifier: [String: AetherSceneInstance] = [:]

    public static func installShared<App: AetherApp>(_ appType: App.Type) -> AetherApplicationRuntime {
        let runtime = AetherApplicationRuntime(appType: appType)
        shared = runtime
        return runtime
    }

    public static func makeConfiguration<App: AetherApp>(for appType: App.Type) -> AetherApplicationRuntimeConfiguration {
        let app = appType.init()
        var configuration = AetherApplicationRuntimeConfiguration()
        app.current.install(into: &configuration)
        configuration.finalize()
        return configuration
    }

    public init<App: AetherApp>(appType: App.Type) {
        var configuration = Self.makeConfiguration(for: appType)
        configuration.finalize()
        self.configuration = configuration
        self.sceneRegistry = AetherSceneRegistry(definitions: configuration.scenes)
        self.appPhase = configuration.environment.appPhase
        self.environment = configuration.environment
    }

    internal init(configuration: AetherApplicationRuntimeConfiguration) {
        var finalized = configuration
        finalized.finalize()
        self.configuration = finalized
        self.sceneRegistry = AetherSceneRegistry(definitions: finalized.scenes)
        self.appPhase = finalized.environment.appPhase
        self.environment = finalized.environment
    }

    public var selectorGate: AetherDelegateMethodRegistry {
        configuration.selectorRegistry
    }

    public var activeSceneIDs: [AetherSceneID] {
        scenesByIdentifier.values.map(\.definition.id)
    }

    public var currentEnvironment: AetherAppEnvironmentValues {
        environment
    }

    public var currentAppearance: AetherAppearance {
        environment.appearance
    }

    public func updateAppearanceStyle(_ style: AetherAppearanceStyle) {
        updateAppearance(AetherAppearance(style: style))
    }

    public func updateAppearance(_ appearance: AetherAppearance) {
        aetherAssertMainThread("Aether appearance updates must run on the main thread")
        guard environment.appearance.signature != appearance.signature else {
            return
        }
        environment.appearanceStyle = appearance.style
        environment.appearance = appearance
        applyAppearanceToConnectedScenes(appearance)
    }

    public func dumpConfiguration() -> String {
        let scenes = configuration.scenes
            .map { "\($0.id.rawValue): role=\($0.role.rawValue), priority=\($0.priority)" }
            .joined(separator: "\n")
        let selectors = configuration.selectorRegistry.enabledSelectors
            .map(\.rawValue)
            .sorted()
            .joined(separator: "\n")
        return """
        AetherApplicationRuntime
        appPhase: \(appPhase)
        scenes:
        \(scenes)
        enabled selectors:
        \(selectors)
        """
    }

    @discardableResult
    public func applicationWillFinishLaunching(
        _ application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        aetherAssertMainThread("Aether app launch handling must run on the main thread")
        setAppPhase(.launching)
        environment.launchOptions = launchOptions
        let context = AetherLaunchContext(application: application, launchOptions: launchOptions, environment: environment)
        return runBoolHandlers(configuration.appLifecycleHandlers.willFinishLaunching, context: context, strategy: .allMustReturnTrue, defaultValue: true)
    }

    @discardableResult
    public func applicationDidFinishLaunching(
        _ application: UIApplication,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        aetherAssertMainThread("Aether app launch handling must run on the main thread")
        setAppPhase(.launching)
        environment.launchOptions = launchOptions
        let context = AetherLaunchContext(application: application, launchOptions: launchOptions, environment: environment)
        let result = runBoolHandlers(configuration.appLifecycleHandlers.didFinishLaunching, context: context, strategy: .allMustReturnTrue, defaultValue: true)
        if configuration.diagnostics.runtimeDumpEnabled {
            print(dumpConfiguration())
        }
        return result
    }

    public func applicationDidBecomeActive(_ application: UIApplication) {
        guard setAppPhase(.active) else {
            return
        }
        let context = AetherApplicationContext(application: application, environment: environment)
        configuration.appLifecycleHandlers.didBecomeActive.forEach { $0(context) }
    }

    public func applicationWillResignActive(_ application: UIApplication) {
        guard setAppPhase(.inactive) else {
            return
        }
        let context = AetherApplicationContext(application: application, environment: environment)
        configuration.appLifecycleHandlers.willResignActive.forEach { $0(context) }
    }

    public func applicationDidEnterBackground(_ application: UIApplication) {
        guard setAppPhase(.background) else {
            return
        }
        let context = AetherApplicationContext(application: application, environment: environment)
        configuration.appLifecycleHandlers.didEnterBackground.forEach { $0(context) }
    }

    public func applicationWillEnterForeground(_ application: UIApplication) {
        guard setAppPhase(.inactive) else {
            return
        }
        let context = AetherApplicationContext(application: application, environment: environment)
        configuration.appLifecycleHandlers.willEnterForeground.forEach { $0(context) }
    }

    public func applicationWillTerminate(_ application: UIApplication) {
        guard setAppPhase(.terminating) else {
            return
        }
        let context = AetherApplicationContext(application: application, environment: environment)
        configuration.appLifecycleHandlers.willTerminate.forEach { $0(context) }
    }

    public func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        let context = AetherApplicationContext(application: application, environment: environment)
        configuration.appLifecycleHandlers.didReceiveMemoryWarning.forEach { $0(context) }
    }

    public func applicationSignificantTimeChange(_ application: UIApplication) {
        let context = AetherApplicationContext(application: application, environment: environment)
        configuration.appLifecycleHandlers.significantTimeChange.forEach { $0(context) }
    }

    public func openURL(_ application: UIApplication, url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) -> Bool {
        let context = AetherOpenURLContext(application: application, url: url, options: options, environment: environment)
        return runBoolHandlers(
            configuration.urlRoutingHandlers.openURL,
            context: context,
            strategy: configuration.urlRoutingHandlers.strategy,
            defaultValue: false
        )
    }

    public func didRegisterForRemoteNotifications(_ application: UIApplication, deviceToken: Data) {
        let context = AetherRemoteNotificationRegistrationContext(application: application, deviceToken: deviceToken, environment: environment)
        configuration.remoteNotificationHandlers.didRegisterDeviceToken.forEach { $0(context) }
    }

    public func didFailToRegisterForRemoteNotifications(_ application: UIApplication, error: Error) {
        let context = AetherRemoteNotificationFailureContext(application: application, error: error, environment: environment)
        configuration.remoteNotificationHandlers.didFailToRegister.forEach { $0(context) }
    }

    public func didReceiveRemoteNotification(
        _ application: UIApplication,
        userInfo: [AnyHashable: Any],
        completion: ((UIBackgroundFetchResult) -> Void)?
    ) {
        let guardedCompletion = completion.map { AetherOneShotCompletion(label: "remoteNotification", completion: $0) }
        let context = AetherRemoteNotificationContext(
            application: application,
            userInfo: userInfo,
            completion: guardedCompletion?.call,
            environment: environment
        )
        if configuration.remoteNotificationHandlers.didReceive.isEmpty {
            guardedCompletion?.call(.noData)
            return
        }
        configuration.remoteNotificationHandlers.didReceive.forEach { $0(context) }
        if completion != nil {
            guardedCompletion?.scheduleFallback(.noData)
        }
    }

    public func performFetch(_ application: UIApplication, completion: @escaping (UIBackgroundFetchResult) -> Void) {
        let guardedCompletion = AetherOneShotCompletion(label: "backgroundFetch", completion: completion)
        let context = AetherBackgroundFetchContext(application: application, completion: guardedCompletion.call, environment: environment)
        if configuration.backgroundEventHandlers.fetch.isEmpty {
            guardedCompletion.call(.noData)
            return
        }
        configuration.backgroundEventHandlers.fetch.forEach { $0(context) }
        guardedCompletion.scheduleFallback(.noData)
    }

    public func handleBackgroundURLSession(
        _ application: UIApplication,
        identifier: String,
        completion: @escaping () -> Void
    ) {
        let guardedCompletion = AetherOneShotVoidCompletion(label: "backgroundURLSession", completion: completion)
        let context = AetherBackgroundURLSessionContext(
            application: application,
            identifier: identifier,
            completion: guardedCompletion.call,
            environment: environment
        )
        if configuration.backgroundEventHandlers.backgroundURLSession.isEmpty {
            guardedCompletion.call()
            return
        }
        configuration.backgroundEventHandlers.backgroundURLSession.forEach { $0(context) }
        guardedCompletion.scheduleFallback()
    }

    public func performShortcutItem(
        application: UIApplication?,
        sceneID: AetherSceneID?,
        shortcutItem: UIApplicationShortcutItem,
        completion: @escaping (Bool) -> Void
    ) {
        let guardedCompletion = AetherOneShotCompletion(label: "shortcutItem", completion: completion)
        let context = AetherShortcutItemContext(
            application: application,
            sceneID: sceneID,
            shortcutItem: shortcutItem,
            completion: guardedCompletion.call,
            environment: environment
        )
        _ = context
        guardedCompletion.call(false)
    }

    public func sceneConfiguration(
        for session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let definition = sceneRegistry.definition(for: session, options: options)
        let name = definition?.id.rawValue ?? session.configuration.name ?? "AetherDefaultScene"
        let configuration = UISceneConfiguration(name: name, sessionRole: session.role)
        configuration.delegateClass = AetherSceneDelegateProxy.self
        return configuration
    }

    public func discardSceneSessions(_ sessions: Set<UISceneSession>) {
        for session in sessions {
            scenesByIdentifier.removeValue(forKey: session.persistentIdentifier)
        }
    }

    public func connectScene(
        _ scene: UIScene,
        session: UISceneSession,
        options: UIScene.ConnectionOptions,
        delegate: AetherSceneDelegateProxy
    ) {
        aetherAssertMainThread("Aether scene connection must run on the main thread")
        guard let windowScene = scene as? UIWindowScene else {
            assertionFailure("AetherWindowScene requires UIWindowScene")
            return
        }
        guard let definition = sceneRegistry.definition(for: session, options: options) else {
            assertionFailure("No Aether WindowScene definition matched \(session.role.rawValue)")
            return
        }

        let payload = AetherSceneConnectionPayload(options: options, session: session)
        let instance = AetherSceneInstance(
            definition: definition,
            session: session,
            windowScene: windowScene,
            connectionPayload: payload,
            runtime: self
        )
        scenesByIdentifier[session.persistentIdentifier] = instance
        delegate.window = instance.window
        delegate.sceneInstance = instance

        let connectContext = AetherSceneConnectionContext(
            scene: scene,
            session: session,
            options: options,
            sceneID: definition.id,
            environment: environment(for: instance)
        )
        configuration.sceneLifecycleHandlers.onConnect.forEach { $0(connectContext) }
        definition.handlers.onConnect.forEach { $0(connectContext) }

        instance.renderInitialContent()
        instance.window.makeKeyAndVisible()
    }

    public func disconnectScene(_ instance: AetherSceneInstance) {
        let context = instance.windowContext(environment: environment(for: instance))
        configuration.sceneLifecycleHandlers.onDisconnect.forEach { $0(context) }
        instance.definition.handlers.onDisconnect.forEach { $0(context) }
        instance.updatePhase(.disconnected)
        scenesByIdentifier.removeValue(forKey: instance.session.persistentIdentifier)
    }

    public func sceneDidBecomeActive(_ instance: AetherSceneInstance) {
        transitionScene(instance, to: .foregroundActive, handlers: \.onBecomeActive)
    }

    public func sceneWillResignActive(_ instance: AetherSceneInstance) {
        transitionScene(instance, to: .foregroundInactive, handlers: \.onResignActive)
    }

    public func sceneWillEnterForeground(_ instance: AetherSceneInstance) {
        transitionScene(instance, to: .foregroundInactive, handlers: \.onEnterForeground)
    }

    public func sceneDidEnterBackground(_ instance: AetherSceneInstance) {
        transitionScene(instance, to: .background, handlers: \.onEnterBackground)
    }

    public func sceneOpenURLContexts(_ instance: AetherSceneInstance, contexts: Set<UIOpenURLContext>) {
        for urlContext in contexts {
            let sceneContext = AetherSceneOpenURLContext(
                sceneID: instance.definition.id,
                urlContext: urlContext,
                environment: environment(for: instance)
            )
            let sceneHandled = instance.definition.handlers.openURL.contains { $0(sceneContext) }
            if !sceneHandled {
                _ = openURL(UIApplication.shared, url: urlContext.url, options: [:])
            }
        }
    }

    public func renderInvalidated(_ instance: AetherSceneInstance) {
        instance.renderUpdatedContent()
    }

    public func environment(forScene instance: AetherSceneInstance) -> AetherAppEnvironmentValues {
        environment(for: instance)
    }

    private func transitionScene(
        _ instance: AetherSceneInstance,
        to phase: AetherScenePhase,
        handlers keyPath: KeyPath<AetherSceneLifecycleHandlers, [(AetherWindowSceneContext) -> Void]>
    ) {
        let oldPhase = instance.phase
        guard oldPhase != phase else {
            return
        }
        instance.updatePhase(phase)
        let environment = environment(for: instance)
        let phaseContext = AetherScenePhaseContext(
            sceneID: instance.definition.id,
            oldPhase: oldPhase,
            newPhase: phase,
            environment: environment
        )
        configuration.sceneLifecycleHandlers.onPhaseChange.forEach { $0(phaseContext) }
        instance.definition.handlers.onPhaseChange.forEach { $0(phaseContext) }

        let context = instance.windowContext(environment: environment)
        configuration.sceneLifecycleHandlers[keyPath: keyPath].forEach { $0(context) }
        instance.definition.handlers[keyPath: keyPath].forEach { $0(context) }
        instance.renderUpdatedContent()
    }

    private func environment(for instance: AetherSceneInstance) -> AetherAppEnvironmentValues {
        var values = environment
        values.scenePhase = instance.phase
        return values
    }

    fileprivate func renderEnvironment(for instance: AetherSceneInstance) -> AetherAppEnvironmentValues {
        environment(for: instance)
    }

    private func applyAppearanceToConnectedScenes(_ appearance: AetherAppearance) {
        for instance in scenesByIdentifier.values {
            if let contentController = instance.window.contentController {
                applyAppearance(appearance, toRootController: contentController)
            }
        }
    }

    fileprivate func applyAppearance(_ appearance: AetherAppearance, toRootController controller: UIViewController) {
        var visited = Set<ObjectIdentifier>()
        applyAppearance(appearance, to: controller, visited: &visited)
    }

    private func applyAppearance(
        _ appearance: AetherAppearance,
        to controller: UIViewController,
        visited: inout Set<ObjectIdentifier>
    ) {
        let identifier = ObjectIdentifier(controller)
        guard !visited.contains(identifier) else {
            return
        }
        visited.insert(identifier)

        if let navigationController = controller as? AetherNavigationController {
            navigationController.updateAppearance(appearance)
        }
        if let tabBarController = controller as? AetherTabBarController {
            tabBarController.updateAppearance(appearance)
        }
        if let aetherController = controller as? AetherViewController,
           aetherController.explicitNavigationBarPresentationData == nil,
           let navigationBarView = aetherController.navigationBarView {
            let resolved = AetherAppearance.withRuntimeCurrent(appearance) {
                aetherController.resolvedNavigationBarAppearance()
            }
            navigationBarView.updatePresentationData(
                NavigationBarPresentationData(theme: NavigationBarTheme(aetherResolvedAppearance: resolved)),
                transition: .immediate
            )
        }

        for child in controller.children {
            applyAppearance(appearance, to: child, visited: &visited)
        }
        if let presentedViewController = controller.presentedViewController {
            applyAppearance(appearance, to: presentedViewController, visited: &visited)
        }
    }

    @discardableResult
    private func setAppPhase(_ phase: AetherAppPhase) -> Bool {
        guard appPhase != phase else {
            return false
        }
        appPhase = phase
        environment.appPhase = phase
        return true
    }

    private func runBoolHandlers<Context>(
        _ handlers: [(Context) -> Bool],
        context: Context,
        strategy: AetherBoolHandlerStrategy,
        defaultValue: Bool
    ) -> Bool {
        guard !handlers.isEmpty else {
            return defaultValue
        }
        switch strategy {
        case .firstHandled:
            return handlers.first { $0(context) } != nil
        case .allMustReturnTrue:
            return handlers.allSatisfy { $0(context) }
        case .anyTrue:
            return handlers.contains { $0(context) }
        case .lastResult:
            return handlers.reduce(defaultValue) { _, handler in handler(context) }
        }
    }
}

public final class AetherSceneRegistry {
    public let definitions: [AetherSceneDefinition]

    public init(definitions: [AetherSceneDefinition]) {
        self.definitions = definitions
    }

    public func definition(for session: UISceneSession, options: UIScene.ConnectionOptions) -> AetherSceneDefinition? {
        let configurationName = session.configuration.name
        let matchingRole = definitions.filter { $0.role == session.role }
        let candidates = matchingRole.isEmpty ? definitions : matchingRole

        if let configurationName,
           let byConfiguration = candidates
            .filter({ $0.configurationNames.contains(configurationName) || $0.id.rawValue == configurationName })
            .sorted(by: { $0.priority > $1.priority })
            .first {
            return byConfiguration
        }

        let urls = options.urlContexts.map(\.url)
        if !urls.isEmpty,
           let byURL = candidates
            .filter({ definition in urls.contains(where: { url in definition.urlPredicates.contains { $0(url) } }) })
            .sorted(by: { $0.priority > $1.priority })
            .first {
            return byURL
        }

        let activityTypes = Set(options.userActivities.map(\.activityType))
        if !activityTypes.isEmpty,
           let byActivity = candidates
            .filter({ !$0.userActivityTypes.isDisjoint(with: activityTypes) })
            .sorted(by: { $0.priority > $1.priority })
            .first {
            return byActivity
        }

        return candidates.sorted(by: { $0.priority > $1.priority }).first
    }
}

public final class AetherSceneInstance {
    public let definition: AetherSceneDefinition
    public let session: UISceneSession
    public let windowScene: UIWindowScene
    public let connectionPayload: AetherSceneConnectionPayload
    public let window: AetherWindow

    public private(set) var phase: AetherScenePhase = .connecting

    private weak var runtime: AetherApplicationRuntime?
    private var currentRootController: UIViewController?

    init(
        definition: AetherSceneDefinition,
        session: UISceneSession,
        windowScene: UIWindowScene,
        connectionPayload: AetherSceneConnectionPayload,
        runtime: AetherApplicationRuntime
    ) {
        self.definition = definition
        self.session = session
        self.windowScene = windowScene
        self.connectionPayload = connectionPayload
        self.runtime = runtime
        self.window = AetherWindow(windowScene: windowScene)
        self.window.backgroundColor = .clear
    }

    public func updatePhase(_ phase: AetherScenePhase) {
        self.phase = phase
    }

    public func renderInitialContent() {
        applyRenderedContent()
    }

    public func renderUpdatedContent() {
        applyRenderedContent()
    }

    public func windowContext(environment: AetherAppEnvironmentValues) -> AetherWindowSceneContext {
        AetherWindowSceneContext(
            windowScene: windowScene,
            session: session,
            sceneID: definition.id,
            window: window,
            environment: environment
        )
    }

    private func applyRenderedContent() {
        guard let runtime else {
            return
        }
        let context = makeRenderContext(runtime: runtime)
        runtime.configuration.sceneLifecycleHandlers.onRender.forEach { $0(context) }
        definition.handlers.onRender.forEach { $0(context) }
        let rendered = AetherAppearance.withRuntimeCurrent(context.environment.appearance) {
            definition.render(context)
        }
        if currentRootController !== rendered {
            currentRootController = rendered
            window.contentController = rendered
        }
        runtime.applyAppearance(context.environment.appearance, toRootController: rendered)
    }

    private func makeRenderContext(runtime: AetherApplicationRuntime) -> AetherSceneRenderContext {
        let environment = runtime.renderEnvironment(for: self)
        return AetherSceneRenderContext(
            sceneID: definition.id,
            phase: phase,
            session: session,
            windowScene: windowScene,
            connectionPayload: connectionPayload,
            traitCollection: windowScene.traitCollection,
            safeAreaInsets: window.safeAreaInsets,
            environment: environment,
            invalidate: { [weak runtime, weak self] in
                guard let runtime, let self else {
                    return
                }
                runtime.renderInvalidated(self)
            }
        )
    }
}

private final class AetherOneShotCompletion<Value> {
    private let label: String
    private let completion: (Value) -> Void
    private var didCall = false

    init(label: String, completion: @escaping (Value) -> Void) {
        self.label = label
        self.completion = completion
    }

    func call(_ value: Value) {
        guard !didCall else {
            assertionFailure("Aether completion called multiple times: \(label)")
            return
        }
        didCall = true
        completion(value)
    }

    func scheduleFallback(_ value: Value, timeout: TimeInterval = 25.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !self.didCall else {
                return
            }
            assertionFailure("Aether completion timed out: \(self.label)")
            self.call(value)
        }
    }
}

private final class AetherOneShotVoidCompletion {
    private let label: String
    private let completion: () -> Void
    private var didCall = false

    init(label: String, completion: @escaping () -> Void) {
        self.label = label
        self.completion = completion
    }

    func call() {
        guard !didCall else {
            assertionFailure("Aether completion called multiple times: \(label)")
            return
        }
        didCall = true
        completion()
    }

    func scheduleFallback(timeout: TimeInterval = 25.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !self.didCall else {
                return
            }
            assertionFailure("Aether completion timed out: \(self.label)")
            self.call()
        }
    }
}
