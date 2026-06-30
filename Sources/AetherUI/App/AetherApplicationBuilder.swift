import UIKit

@resultBuilder
public enum AetherApplicationBuilder {
    public static func buildBlock() -> AetherApplicationGroup {
        AetherApplicationGroup([])
    }

    public static func buildBlock<Component: AetherApplicationNode>(_ component: Component) -> Component {
        component
    }

    public static func buildBlock(_ components: any AetherApplicationNode...) -> AetherApplicationGroup {
        AetherApplicationGroup(components)
    }

    public static func buildOptional(_ component: AetherApplicationGroup?) -> AetherApplicationGroup {
        component ?? AetherApplicationGroup([])
    }

    public static func buildEither(first component: AetherApplicationGroup) -> AetherApplicationGroup {
        component
    }

    public static func buildEither(second component: AetherApplicationGroup) -> AetherApplicationGroup {
        component
    }

    public static func buildArray(_ components: [AetherApplicationGroup]) -> AetherApplicationGroup {
        AetherApplicationGroup(components)
    }

    public static func buildExpression<Component: AetherApplicationNode>(_ expression: Component) -> Component {
        expression
    }

    public static func buildFinalResult<Component: AetherApplicationNode>(_ component: Component) -> Component {
        component
    }

    public static func buildPartialBlock<Component: AetherApplicationNode>(first: Component) -> AetherApplicationGroup {
        AetherApplicationGroup([first])
    }

    public static func buildPartialBlock<Component: AetherApplicationNode>(
        accumulated: AetherApplicationGroup,
        next: Component
    ) -> AetherApplicationGroup {
        AetherApplicationGroup(accumulated.components + [next])
    }

    public static func buildLimitedAvailability(_ component: AetherApplicationGroup) -> AetherApplicationGroup {
        component
    }

    public static func buildExpression(_ expression: any AetherApplicationNode) -> AetherApplicationGroup {
        AetherApplicationGroup([expression])
    }

    public static func buildArray(_ components: [any AetherApplicationNode]) -> AetherApplicationGroup {
        AetherApplicationGroup(components)
    }
}

public struct AetherApplication: AetherApplicationNode {
    private let content: any AetherApplicationNode

    public init(@AetherApplicationBuilder _ content: () -> any AetherApplicationNode) {
        self.content = content()
    }

    public func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        content.install(into: &configuration)
    }

    public func appearanceStyle(_ style: AetherAppearanceStyle) -> AetherApplicationGroup {
        AetherApplicationGroup([self, AppearanceStyle(style)])
    }
}

public struct AetherApplicationGroup: AetherApplicationNode {
    public var components: [any AetherApplicationNode]

    public init(_ components: [any AetherApplicationNode]) {
        self.components = components
    }

    public func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        for component in components {
            component.install(into: &configuration)
        }
    }
}

public struct AppearanceStyle: AetherApplicationNode {
    public var style: AetherAppearanceStyle

    public init(_ style: AetherAppearanceStyle) {
        self.style = style
    }

    public func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        configuration.environment.appearanceStyle = style
        configuration.environment.appearance = AetherAppearance(style: style)
    }
}

public struct AetherApplicationRuntimeConfiguration {
    public var scenes: [AetherSceneDefinition] = []
    public var appLifecycleHandlers = AetherAppLifecycleHandlers()
    public var sceneLifecycleHandlers = AetherSceneLifecycleHandlers()
    public var urlRoutingHandlers = AetherURLRoutingHandlers()
    public var userActivityHandlers = AetherUserActivityHandlers()
    public var remoteNotificationHandlers = AetherRemoteNotificationHandlers()
    public var backgroundEventHandlers = AetherBackgroundEventHandlers()
    public var stateRestorationHandlers = AetherStateRestorationHandlers()
    public var selectorRegistry = AetherDelegateMethodRegistry()
    public var environment = AetherAppEnvironmentValues()
    public var diagnostics = AetherAppRuntimeDiagnostics()
    public var legacyAppDelegates: [AetherLegacyAppDelegateBridgeDefinition] = []

    public init() {}

    public mutating func finalize() {
        var seen: Set<AetherSceneID> = []
        for scene in scenes {
            if seen.contains(scene.id) {
                assertionFailure("Duplicate Aether scene id: \(scene.id)")
            }
            seen.insert(scene.id)
        }

        if !scenes.isEmpty {
            selectorRegistry.require(.applicationConfigurationForConnecting)
            selectorRegistry.require(.applicationDidDiscardSceneSessions)
            selectorRegistry.require(.sceneWillConnect)
            selectorRegistry.require(.sceneDidDisconnect)
            selectorRegistry.require(.sceneDidBecomeActive)
            selectorRegistry.require(.sceneWillResignActive)
            selectorRegistry.require(.sceneWillEnterForeground)
            selectorRegistry.require(.sceneDidEnterBackground)
            selectorRegistry.require(.windowSceneDidUpdateCoordinateSpace)
        }

        if !urlRoutingHandlers.openURL.isEmpty || scenes.contains(where: { !$0.urlPredicates.isEmpty || !$0.handlers.openURL.isEmpty }) {
            selectorRegistry.require(.sceneOpenURLContexts)
        }
    }
}

public struct AetherAppLifecycleHandlers {
    public var willFinishLaunching: [(AetherLaunchContext) -> Bool] = []
    public var didFinishLaunching: [(AetherLaunchContext) -> Bool] = []
    public var didBecomeActive: [(AetherApplicationContext) -> Void] = []
    public var willResignActive: [(AetherApplicationContext) -> Void] = []
    public var didEnterBackground: [(AetherApplicationContext) -> Void] = []
    public var willEnterForeground: [(AetherApplicationContext) -> Void] = []
    public var willTerminate: [(AetherApplicationContext) -> Void] = []
    public var didReceiveMemoryWarning: [(AetherApplicationContext) -> Void] = []
    public var significantTimeChange: [(AetherApplicationContext) -> Void] = []

    public init() {}
}

public struct AetherSceneLifecycleHandlers {
    public var onConnect: [(AetherSceneConnectionContext) -> Void] = []
    public var onDisconnect: [(AetherWindowSceneContext) -> Void] = []
    public var onBecomeActive: [(AetherWindowSceneContext) -> Void] = []
    public var onResignActive: [(AetherWindowSceneContext) -> Void] = []
    public var onEnterForeground: [(AetherWindowSceneContext) -> Void] = []
    public var onEnterBackground: [(AetherWindowSceneContext) -> Void] = []
    public var onPhaseChange: [(AetherScenePhaseContext) -> Void] = []
    public var onRender: [(AetherSceneRenderContext) -> Void] = []
    public var openURL: [(AetherSceneOpenURLContext) -> Bool] = []

    public init() {}

    mutating func append(_ other: AetherSceneLifecycleHandlers) {
        onConnect.append(contentsOf: other.onConnect)
        onDisconnect.append(contentsOf: other.onDisconnect)
        onBecomeActive.append(contentsOf: other.onBecomeActive)
        onResignActive.append(contentsOf: other.onResignActive)
        onEnterForeground.append(contentsOf: other.onEnterForeground)
        onEnterBackground.append(contentsOf: other.onEnterBackground)
        onPhaseChange.append(contentsOf: other.onPhaseChange)
        onRender.append(contentsOf: other.onRender)
        openURL.append(contentsOf: other.openURL)
    }
}

public struct AetherURLRoutingHandlers {
    public var strategy: AetherBoolHandlerStrategy = .firstHandled
    public var openURL: [(AetherOpenURLContext) -> Bool] = []

    public init() {}
}

public struct AetherUserActivityHandlers {
    public var willContinue: [(AetherUserActivityTypeContext) -> Bool] = []
    public var didContinue: [(AetherUserActivityContext) -> Bool] = []
    public var didFail: [(AetherUserActivityFailureContext) -> Void] = []
    public var didUpdate: [(AetherUserActivityContext) -> Void] = []

    public init() {}
}

public struct AetherRemoteNotificationHandlers {
    public var didRegisterDeviceToken: [(AetherRemoteNotificationRegistrationContext) -> Void] = []
    public var didFailToRegister: [(AetherRemoteNotificationFailureContext) -> Void] = []
    public var didReceive: [(AetherRemoteNotificationContext) -> Void] = []

    public init() {}
}

public struct AetherBackgroundEventHandlers {
    public var fetch: [(AetherBackgroundFetchContext) -> Void] = []
    public var backgroundURLSession: [(AetherBackgroundURLSessionContext) -> Void] = []

    public init() {}
}

public struct AetherStateRestorationHandlers {
    public var shouldSaveSecureApplicationState: [(UIApplication, NSCoder) -> Bool] = []
    public var shouldRestoreSecureApplicationState: [(UIApplication, NSCoder) -> Bool] = []
    public var viewControllerWithRestorationPath: [(UIApplication, [String], NSCoder) -> UIViewController?] = []
    public var willEncodeRestorableState: [(UIApplication, NSCoder) -> Void] = []
    public var didDecodeRestorableState: [(UIApplication, NSCoder) -> Void] = []
    public var sceneRestorationActivity: [(AetherWindowSceneContext) -> NSUserActivity?] = []
    public var sceneRestoreInteractionState: [(AetherWindowSceneContext, NSUserActivity) -> Void] = []

    public init() {}
}

public struct AetherSceneDefinition {
    public var id: AetherSceneID
    public var role: UISceneSession.Role
    public var priority: Int
    public var configurationNames: Set<String>
    public var userActivityTypes: Set<String>
    public var urlPredicates: [(URL) -> Bool]
    public var handlers: AetherSceneLifecycleHandlers
    public var render: (AetherSceneRenderContext) -> UIViewController

    public init(
        id: AetherSceneID,
        role: UISceneSession.Role,
        priority: Int = 0,
        configurationNames: Set<String> = [],
        userActivityTypes: Set<String> = [],
        urlPredicates: [(URL) -> Bool] = [],
        handlers: AetherSceneLifecycleHandlers = AetherSceneLifecycleHandlers(),
        render: @escaping (AetherSceneRenderContext) -> UIViewController
    ) {
        self.id = id
        self.role = role
        self.priority = priority
        self.configurationNames = configurationNames
        self.userActivityTypes = userActivityTypes
        self.urlPredicates = urlPredicates
        self.handlers = handlers
        self.render = render
    }
}

public struct AetherWindowScene: AetherApplicationNode {
    private var definition: AetherSceneDefinition

    public init(
        id: String,
        role: UISceneSession.Role = .windowApplication,
        priority: Int = 0,
        render: @escaping (AetherSceneRenderContext) -> UIViewController
    ) {
        self.definition = AetherSceneDefinition(
            id: AetherSceneID(rawValue: id),
            role: role,
            priority: priority,
            configurationNames: [id],
            render: render
        )
    }

    public func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        configuration.scenes.append(definition)
    }

    public func matchesConfigurationName(_ name: String) -> Self {
        var copy = self
        copy.definition.configurationNames.insert(name)
        return copy
    }

    public func matchesUserActivityType(_ type: String) -> Self {
        var copy = self
        copy.definition.userActivityTypes.insert(type)
        return copy
    }

    public func matchesURL(_ predicate: @escaping (URL) -> Bool) -> Self {
        var copy = self
        copy.definition.urlPredicates.append(predicate)
        return copy
    }

    public func onConnect(_ handler: @escaping (AetherSceneConnectionContext) -> Void) -> Self {
        var copy = self
        copy.definition.handlers.onConnect.append(handler)
        return copy
    }

    public func onDisconnect(_ handler: @escaping (AetherWindowSceneContext) -> Void) -> Self {
        var copy = self
        copy.definition.handlers.onDisconnect.append(handler)
        return copy
    }

    public func onBecomeActive(_ handler: @escaping (AetherWindowSceneContext) -> Void) -> Self {
        var copy = self
        copy.definition.handlers.onBecomeActive.append(handler)
        return copy
    }

    public func onResignActive(_ handler: @escaping (AetherWindowSceneContext) -> Void) -> Self {
        var copy = self
        copy.definition.handlers.onResignActive.append(handler)
        return copy
    }

    public func onEnterForeground(_ handler: @escaping (AetherWindowSceneContext) -> Void) -> Self {
        var copy = self
        copy.definition.handlers.onEnterForeground.append(handler)
        return copy
    }

    public func onEnterBackground(_ handler: @escaping (AetherWindowSceneContext) -> Void) -> Self {
        var copy = self
        copy.definition.handlers.onEnterBackground.append(handler)
        return copy
    }

    public func onPhaseChange(_ handler: @escaping (AetherScenePhaseContext) -> Void) -> Self {
        var copy = self
        copy.definition.handlers.onPhaseChange.append(handler)
        return copy
    }

    public func onRender(_ handler: @escaping (AetherSceneRenderContext) -> Void) -> Self {
        var copy = self
        copy.definition.handlers.onRender.append(handler)
        return copy
    }

    public func onOpenURL(_ handler: @escaping (AetherSceneOpenURLContext) -> Bool) -> Self {
        var copy = self
        copy.definition.handlers.openURL.append(handler)
        return copy
    }
}

public typealias WindowScene = AetherWindowScene

public struct AppLifecycle: AetherApplicationNode {
    private var handlers = AetherAppLifecycleHandlers()

    public init() {}

    public func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        configuration.appLifecycleHandlers.willFinishLaunching.append(contentsOf: handlers.willFinishLaunching)
        configuration.appLifecycleHandlers.didFinishLaunching.append(contentsOf: handlers.didFinishLaunching)
        configuration.appLifecycleHandlers.didBecomeActive.append(contentsOf: handlers.didBecomeActive)
        configuration.appLifecycleHandlers.willResignActive.append(contentsOf: handlers.willResignActive)
        configuration.appLifecycleHandlers.didEnterBackground.append(contentsOf: handlers.didEnterBackground)
        configuration.appLifecycleHandlers.willEnterForeground.append(contentsOf: handlers.willEnterForeground)
        configuration.appLifecycleHandlers.willTerminate.append(contentsOf: handlers.willTerminate)
        configuration.appLifecycleHandlers.didReceiveMemoryWarning.append(contentsOf: handlers.didReceiveMemoryWarning)
        configuration.appLifecycleHandlers.significantTimeChange.append(contentsOf: handlers.significantTimeChange)

        if !handlers.willFinishLaunching.isEmpty { configuration.selectorRegistry.enable(.applicationWillFinishLaunching) }
        if !handlers.didFinishLaunching.isEmpty { configuration.selectorRegistry.enable(.applicationDidFinishLaunching) }
        if !handlers.didBecomeActive.isEmpty { configuration.selectorRegistry.enable(.applicationDidBecomeActive) }
        if !handlers.willResignActive.isEmpty { configuration.selectorRegistry.enable(.applicationWillResignActive) }
        if !handlers.didEnterBackground.isEmpty { configuration.selectorRegistry.enable(.applicationDidEnterBackground) }
        if !handlers.willEnterForeground.isEmpty { configuration.selectorRegistry.enable(.applicationWillEnterForeground) }
        if !handlers.willTerminate.isEmpty { configuration.selectorRegistry.enable(.applicationWillTerminate) }
        if !handlers.didReceiveMemoryWarning.isEmpty { configuration.selectorRegistry.enable(.applicationDidReceiveMemoryWarning) }
        if !handlers.significantTimeChange.isEmpty { configuration.selectorRegistry.enable(.applicationSignificantTimeChange) }
    }

    public func onWillFinishLaunching(_ handler: @escaping (AetherLaunchContext) -> Bool) -> Self {
        var copy = self
        copy.handlers.willFinishLaunching.append(handler)
        return copy
    }

    public func onDidFinishLaunching(_ handler: @escaping (AetherLaunchContext) -> Bool) -> Self {
        var copy = self
        copy.handlers.didFinishLaunching.append(handler)
        return copy
    }

    public func onDidBecomeActive(_ handler: @escaping (AetherApplicationContext) -> Void) -> Self {
        var copy = self
        copy.handlers.didBecomeActive.append(handler)
        return copy
    }

    public func onWillResignActive(_ handler: @escaping (AetherApplicationContext) -> Void) -> Self {
        var copy = self
        copy.handlers.willResignActive.append(handler)
        return copy
    }

    public func onDidEnterBackground(_ handler: @escaping (AetherApplicationContext) -> Void) -> Self {
        var copy = self
        copy.handlers.didEnterBackground.append(handler)
        return copy
    }

    public func onWillEnterForeground(_ handler: @escaping (AetherApplicationContext) -> Void) -> Self {
        var copy = self
        copy.handlers.willEnterForeground.append(handler)
        return copy
    }

    public func onWillTerminate(_ handler: @escaping (AetherApplicationContext) -> Void) -> Self {
        var copy = self
        copy.handlers.willTerminate.append(handler)
        return copy
    }

    public func onDidReceiveMemoryWarning(_ handler: @escaping (AetherApplicationContext) -> Void) -> Self {
        var copy = self
        copy.handlers.didReceiveMemoryWarning.append(handler)
        return copy
    }

    public func onSignificantTimeChange(_ handler: @escaping (AetherApplicationContext) -> Void) -> Self {
        var copy = self
        copy.handlers.significantTimeChange.append(handler)
        return copy
    }
}

public struct SceneLifecycle: AetherApplicationNode {
    private var handlers = AetherSceneLifecycleHandlers()

    public init() {}

    public func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        configuration.sceneLifecycleHandlers.append(handlers)
    }

    public func onConnect(_ handler: @escaping (AetherSceneConnectionContext) -> Void) -> Self {
        var copy = self
        copy.handlers.onConnect.append(handler)
        return copy
    }

    public func onDisconnect(_ handler: @escaping (AetherWindowSceneContext) -> Void) -> Self {
        var copy = self
        copy.handlers.onDisconnect.append(handler)
        return copy
    }

    public func onBecomeActive(_ handler: @escaping (AetherWindowSceneContext) -> Void) -> Self {
        var copy = self
        copy.handlers.onBecomeActive.append(handler)
        return copy
    }

    public func onResignActive(_ handler: @escaping (AetherWindowSceneContext) -> Void) -> Self {
        var copy = self
        copy.handlers.onResignActive.append(handler)
        return copy
    }

    public func onEnterForeground(_ handler: @escaping (AetherWindowSceneContext) -> Void) -> Self {
        var copy = self
        copy.handlers.onEnterForeground.append(handler)
        return copy
    }

    public func onEnterBackground(_ handler: @escaping (AetherWindowSceneContext) -> Void) -> Self {
        var copy = self
        copy.handlers.onEnterBackground.append(handler)
        return copy
    }

    public func onPhaseChange(_ handler: @escaping (AetherScenePhaseContext) -> Void) -> Self {
        var copy = self
        copy.handlers.onPhaseChange.append(handler)
        return copy
    }
}

public struct URLRouting: AetherApplicationNode {
    private var handlers = AetherURLRoutingHandlers()

    public init() {}

    public func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        configuration.urlRoutingHandlers.strategy = handlers.strategy
        configuration.urlRoutingHandlers.openURL.append(contentsOf: handlers.openURL)
        if !handlers.openURL.isEmpty {
            configuration.selectorRegistry.enable(.applicationOpenURL)
            configuration.selectorRegistry.require(.sceneOpenURLContexts)
        }
    }

    public func strategy(_ strategy: AetherBoolHandlerStrategy) -> Self {
        var copy = self
        copy.handlers.strategy = strategy
        return copy
    }

    public func onOpenURL(_ handler: @escaping (AetherOpenURLContext) -> Bool) -> Self {
        var copy = self
        copy.handlers.openURL.append(handler)
        return copy
    }
}

public struct UserActivityRouting: AetherApplicationNode {
    private var handlers = AetherUserActivityHandlers()

    public init() {}

    public func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        configuration.userActivityHandlers.willContinue.append(contentsOf: handlers.willContinue)
        configuration.userActivityHandlers.didContinue.append(contentsOf: handlers.didContinue)
        configuration.userActivityHandlers.didFail.append(contentsOf: handlers.didFail)
        configuration.userActivityHandlers.didUpdate.append(contentsOf: handlers.didUpdate)
        if !handlers.willContinue.isEmpty {
            configuration.selectorRegistry.enable(.applicationWillContinueUserActivity)
            configuration.selectorRegistry.require(.sceneWillContinueUserActivity)
        }
        if !handlers.didContinue.isEmpty {
            configuration.selectorRegistry.enable(.applicationContinueUserActivity)
            configuration.selectorRegistry.require(.sceneContinueUserActivity)
        }
        if !handlers.didFail.isEmpty {
            configuration.selectorRegistry.enable(.applicationDidFailContinueUserActivity)
            configuration.selectorRegistry.require(.sceneDidFailContinueUserActivity)
        }
        if !handlers.didUpdate.isEmpty {
            configuration.selectorRegistry.enable(.applicationDidUpdateUserActivity)
            configuration.selectorRegistry.require(.sceneDidUpdateUserActivity)
        }
    }

    public func onWillContinue(_ handler: @escaping (AetherUserActivityTypeContext) -> Bool) -> Self {
        var copy = self
        copy.handlers.willContinue.append(handler)
        return copy
    }

    public func onContinue(_ handler: @escaping (AetherUserActivityContext) -> Bool) -> Self {
        var copy = self
        copy.handlers.didContinue.append(handler)
        return copy
    }

    public func onFailToContinue(_ handler: @escaping (AetherUserActivityFailureContext) -> Void) -> Self {
        var copy = self
        copy.handlers.didFail.append(handler)
        return copy
    }

    public func onUpdate(_ handler: @escaping (AetherUserActivityContext) -> Void) -> Self {
        var copy = self
        copy.handlers.didUpdate.append(handler)
        return copy
    }
}

public struct RemoteNotifications: AetherApplicationNode {
    private var handlers = AetherRemoteNotificationHandlers()

    public init() {}

    public func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        configuration.remoteNotificationHandlers.didRegisterDeviceToken.append(contentsOf: handlers.didRegisterDeviceToken)
        configuration.remoteNotificationHandlers.didFailToRegister.append(contentsOf: handlers.didFailToRegister)
        configuration.remoteNotificationHandlers.didReceive.append(contentsOf: handlers.didReceive)
        if !handlers.didRegisterDeviceToken.isEmpty {
            configuration.selectorRegistry.enable(.applicationDidRegisterForRemoteNotifications)
        }
        if !handlers.didFailToRegister.isEmpty {
            configuration.selectorRegistry.enable(.applicationDidFailToRegisterForRemoteNotifications)
        }
        if !handlers.didReceive.isEmpty {
            configuration.selectorRegistry.enable(.applicationDidReceiveRemoteNotification)
            configuration.selectorRegistry.enable(.applicationDidReceiveRemoteNotificationFetch)
        }
    }

    public func onRegisterDeviceToken(_ handler: @escaping (AetherRemoteNotificationRegistrationContext) -> Void) -> Self {
        var copy = self
        copy.handlers.didRegisterDeviceToken.append(handler)
        return copy
    }

    public func onFailToRegister(_ handler: @escaping (AetherRemoteNotificationFailureContext) -> Void) -> Self {
        var copy = self
        copy.handlers.didFailToRegister.append(handler)
        return copy
    }

    public func onReceive(_ handler: @escaping (AetherRemoteNotificationContext) -> Void) -> Self {
        var copy = self
        copy.handlers.didReceive.append(handler)
        return copy
    }
}

public struct BackgroundEvents: AetherApplicationNode {
    private var handlers = AetherBackgroundEventHandlers()

    public init() {}

    public func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        configuration.backgroundEventHandlers.fetch.append(contentsOf: handlers.fetch)
        configuration.backgroundEventHandlers.backgroundURLSession.append(contentsOf: handlers.backgroundURLSession)
        if !handlers.fetch.isEmpty {
            configuration.selectorRegistry.enable(.applicationPerformFetch)
        }
        if !handlers.backgroundURLSession.isEmpty {
            configuration.selectorRegistry.enable(.applicationHandleBackgroundURLSession)
        }
    }

    public func onFetch(_ handler: @escaping (AetherBackgroundFetchContext) -> Void) -> Self {
        var copy = self
        copy.handlers.fetch.append(handler)
        return copy
    }

    public func onBackgroundURLSession(_ handler: @escaping (AetherBackgroundURLSessionContext) -> Void) -> Self {
        var copy = self
        copy.handlers.backgroundURLSession.append(handler)
        return copy
    }
}

public struct Diagnostics: AetherApplicationNode {
    private var diagnostics = AetherAppRuntimeDiagnostics()

    public init() {}

    public func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        configuration.diagnostics = diagnostics
    }

    public func enableRuntimeDump() -> Self {
        var copy = self
        copy.diagnostics.runtimeDumpEnabled = true
        return copy
    }

    public func enableSignposts() -> Self {
        var copy = self
        copy.diagnostics.signpostsEnabled = true
        return copy
    }
}

public struct LegacyAppDelegateBridge: AetherApplicationNode {
    private let definition: AetherLegacyAppDelegateBridgeDefinition

    public init(existing: any UIApplicationDelegate, order: AetherLegacyBridgeOrder = .beforeAether) {
        self.definition = AetherLegacyAppDelegateBridgeDefinition(existing: existing, order: order)
    }

    public func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        configuration.legacyAppDelegates.append(definition)
        for selector in AetherDelegateSelector.allCases where definition.responds(to: selector.selector) {
            configuration.selectorRegistry.enable(selector)
        }
    }
}

public struct AetherLegacyAppDelegateBridgeDefinition {
    public let existing: any UIApplicationDelegate
    public let order: AetherLegacyBridgeOrder

    public init(existing: any UIApplicationDelegate, order: AetherLegacyBridgeOrder) {
        self.existing = existing
        self.order = order
    }

    public func responds(to selector: Selector) -> Bool {
        (existing as AnyObject).responds(to: selector)
    }
}

public func onLaunch(_ handler: @escaping (AetherLaunchContext) -> Bool) -> AppLifecycle {
    AppLifecycle().onDidFinishLaunching(handler)
}

public func onOpenURL(_ handler: @escaping (AetherOpenURLContext) -> Bool) -> URLRouting {
    URLRouting().onOpenURL(handler)
}

public func onRemoteNotification(_ handler: @escaping (AetherRemoteNotificationContext) -> Void) -> RemoteNotifications {
    RemoteNotifications().onReceive(handler)
}
