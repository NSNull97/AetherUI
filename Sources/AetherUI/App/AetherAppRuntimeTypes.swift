import UIKit
import os.log

public typealias ApplicationBuilder = AetherApplicationNode

public protocol AetherApp: AnyObject {
    associatedtype Current: AetherApplicationNode

    @AetherApplicationBuilder
    var current: Current { get }

    init()
}

public protocol AetherApplicationNode {
    func install(into configuration: inout AetherApplicationRuntimeConfiguration)
}

public protocol AetherAppPlugin: AetherApplicationNode {}

public protocol AetherWindowContent: AnyObject {
    var aetherWindowContentController: UIViewController { get }
}

extension UIViewController: AetherWindowContent {
    public var aetherWindowContentController: UIViewController {
        self
    }
}

public struct AetherSceneID: RawRepresentable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }
}

public enum AetherAppRuntimeMode: Hashable {
    case production
    case diagnostics
    case compatibility
}

public enum AetherAppPhase: Hashable {
    case notLaunched
    case launching
    case active
    case inactive
    case background
    case terminating
}

public enum AetherScenePhase: Hashable {
    case disconnected
    case connecting
    case foregroundInactive
    case foregroundActive
    case background
}

public enum AetherBoolHandlerStrategy: Hashable {
    case firstHandled
    case allMustReturnTrue
    case anyTrue
    case lastResult
}

public enum AetherLegacyBridgeOrder: Hashable {
    case beforeAether
    case afterAether
}

public enum AetherAppRuntimeError: Error, Hashable {
    case noMatchingSceneDefinition
    case duplicateSceneDefinition(AetherSceneID)
    case invalidSceneRole(String)
    case handlerTimeout(String)
    case completionCalledMultipleTimes(String)
    case windowSceneExpectedButGotDifferentScene
    case legacyBridgeConflict(String)
}

public final class AetherDependencyContainer {
    private var storage: [ObjectIdentifier: Any] = [:]

    public init() {}

    public subscript<T>(_ type: T.Type) -> T? {
        get {
            storage[ObjectIdentifier(type)] as? T
        }
        set {
            storage[ObjectIdentifier(type)] = newValue
        }
    }
}

public struct AetherAppEnvironmentValues {
    public var appPhase: AetherAppPhase
    public var scenePhase: AetherScenePhase?
    public var launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    public var dependencies: AetherDependencyContainer
    public var runtimeMode: AetherAppRuntimeMode
    public var appearanceStyle: AetherAppearanceStyle
    public var appearance: AetherAppearance

    public init(
        appPhase: AetherAppPhase = .notLaunched,
        scenePhase: AetherScenePhase? = nil,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil,
        dependencies: AetherDependencyContainer = AetherDependencyContainer(),
        runtimeMode: AetherAppRuntimeMode = .production,
        appearanceStyle: AetherAppearanceStyle = .iOS26,
        appearance: AetherAppearance? = nil
    ) {
        self.appPhase = appPhase
        self.scenePhase = scenePhase
        self.launchOptions = launchOptions
        self.dependencies = dependencies
        self.runtimeMode = runtimeMode
        self.appearanceStyle = appearanceStyle
        self.appearance = appearance ?? AetherAppearance(style: appearanceStyle)
    }
}

public struct AetherLaunchContext {
    public let application: UIApplication
    public let launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    public let environment: AetherAppEnvironmentValues
}

public struct AetherApplicationContext {
    public let application: UIApplication
    public let environment: AetherAppEnvironmentValues
}

public struct AetherOpenURLContext {
    public let application: UIApplication
    public let url: URL
    public let options: [UIApplication.OpenURLOptionsKey: Any]
    public let environment: AetherAppEnvironmentValues
}

public struct AetherUserActivityContext {
    public let application: UIApplication?
    public let sceneID: AetherSceneID?
    public let userActivity: NSUserActivity
    public let restorationHandler: (([any UIUserActivityRestoring]?) -> Void)?
    public let environment: AetherAppEnvironmentValues
}

public struct AetherUserActivityTypeContext {
    public let application: UIApplication?
    public let sceneID: AetherSceneID?
    public let userActivityType: String
    public let environment: AetherAppEnvironmentValues
}

public struct AetherUserActivityFailureContext {
    public let application: UIApplication?
    public let sceneID: AetherSceneID?
    public let userActivityType: String
    public let error: Error
    public let environment: AetherAppEnvironmentValues
}

public struct AetherRemoteNotificationContext {
    public let application: UIApplication
    public let userInfo: [AnyHashable: Any]
    public let completion: ((UIBackgroundFetchResult) -> Void)?
    public let environment: AetherAppEnvironmentValues
}

public struct AetherRemoteNotificationRegistrationContext {
    public let application: UIApplication
    public let deviceToken: Data
    public let environment: AetherAppEnvironmentValues
}

public struct AetherRemoteNotificationFailureContext {
    public let application: UIApplication
    public let error: Error
    public let environment: AetherAppEnvironmentValues
}

public struct AetherBackgroundFetchContext {
    public let application: UIApplication
    public let completion: (UIBackgroundFetchResult) -> Void
    public let environment: AetherAppEnvironmentValues
}

public struct AetherBackgroundURLSessionContext {
    public let application: UIApplication
    public let identifier: String
    public let completion: () -> Void
    public let environment: AetherAppEnvironmentValues
}

public struct AetherShortcutItemContext {
    public let application: UIApplication?
    public let sceneID: AetherSceneID?
    public let shortcutItem: UIApplicationShortcutItem
    public let completion: (Bool) -> Void
    public let environment: AetherAppEnvironmentValues
}

public struct AetherSceneConnectionPayload {
    public let options: UIScene.ConnectionOptions
    public let urlContexts: Set<UIOpenURLContext>
    public let userActivities: Set<NSUserActivity>
    public let shortcutItem: UIApplicationShortcutItem?
    public let restorationActivity: NSUserActivity?

    public init(options: UIScene.ConnectionOptions, session: UISceneSession) {
        self.options = options
        self.urlContexts = options.urlContexts
        self.userActivities = options.userActivities
        self.shortcutItem = options.shortcutItem
        self.restorationActivity = session.stateRestorationActivity
    }
}

public struct AetherSceneConnectionContext {
    public let scene: UIScene
    public let session: UISceneSession
    public let options: UIScene.ConnectionOptions
    public let sceneID: AetherSceneID
    public let environment: AetherAppEnvironmentValues
}

public struct AetherWindowSceneContext {
    public let windowScene: UIWindowScene
    public let session: UISceneSession
    public let sceneID: AetherSceneID
    public let window: UIWindow?
    public let environment: AetherAppEnvironmentValues
}

public struct AetherScenePhaseContext {
    public let sceneID: AetherSceneID
    public let oldPhase: AetherScenePhase
    public let newPhase: AetherScenePhase
    public let environment: AetherAppEnvironmentValues
}

public struct AetherSceneOpenURLContext {
    public let sceneID: AetherSceneID
    public let urlContext: UIOpenURLContext
    public let environment: AetherAppEnvironmentValues
}

public struct AetherSceneRenderContext {
    public let sceneID: AetherSceneID
    public let phase: AetherScenePhase
    public let session: UISceneSession
    public let windowScene: UIWindowScene
    public let connectionPayload: AetherSceneConnectionPayload
    public let traitCollection: UITraitCollection
    public let safeAreaInsets: UIEdgeInsets
    public let environment: AetherAppEnvironmentValues

    private let invalidateAction: () -> Void

    public init(
        sceneID: AetherSceneID,
        phase: AetherScenePhase,
        session: UISceneSession,
        windowScene: UIWindowScene,
        connectionPayload: AetherSceneConnectionPayload,
        traitCollection: UITraitCollection,
        safeAreaInsets: UIEdgeInsets,
        environment: AetherAppEnvironmentValues,
        invalidate: @escaping () -> Void
    ) {
        self.sceneID = sceneID
        self.phase = phase
        self.session = session
        self.windowScene = windowScene
        self.connectionPayload = connectionPayload
        self.traitCollection = traitCollection
        self.safeAreaInsets = safeAreaInsets
        self.environment = environment
        self.invalidateAction = invalidate
    }

    public func invalidate() {
        invalidateAction()
    }
}

public enum AetherDelegateSelector: String, CaseIterable, Hashable, CustomStringConvertible {
    case applicationWillFinishLaunching
    case applicationDidFinishLaunching
    case applicationDidBecomeActive
    case applicationWillResignActive
    case applicationDidEnterBackground
    case applicationWillEnterForeground
    case applicationWillTerminate
    case applicationDidReceiveMemoryWarning
    case applicationSignificantTimeChange
    case applicationOpenURL
    case applicationDidRegisterForRemoteNotifications
    case applicationDidFailToRegisterForRemoteNotifications
    case applicationDidReceiveRemoteNotification
    case applicationDidReceiveRemoteNotificationFetch
    case applicationPerformFetch
    case applicationHandleBackgroundURLSession
    case applicationPerformShortcutAction
    case applicationProtectedDataWillBecomeUnavailable
    case applicationProtectedDataDidBecomeAvailable
    case applicationSupportedInterfaceOrientations
    case applicationShouldAllowExtensionPoint
    case applicationShouldSaveSecureState
    case applicationShouldRestoreSecureState
    case applicationViewControllerWithRestorationPath
    case applicationWillEncodeRestorableState
    case applicationDidDecodeRestorableState
    case applicationWillContinueUserActivity
    case applicationContinueUserActivity
    case applicationDidFailContinueUserActivity
    case applicationDidUpdateUserActivity
    case applicationConfigurationForConnecting
    case applicationDidDiscardSceneSessions
    case applicationShouldAutomaticallyLocalizeKeyCommands
    case sceneWillConnect
    case sceneDidDisconnect
    case sceneDidBecomeActive
    case sceneWillResignActive
    case sceneWillEnterForeground
    case sceneDidEnterBackground
    case sceneOpenURLContexts
    case sceneStateRestorationActivity
    case sceneRestoreInteractionState
    case sceneWillContinueUserActivity
    case sceneContinueUserActivity
    case sceneDidFailContinueUserActivity
    case sceneDidUpdateUserActivity
    case windowSceneDidUpdateCoordinateSpace
    case windowScenePerformShortcutAction

    public var description: String {
        rawValue
    }

    public var selector: Selector {
        switch self {
        case .applicationWillFinishLaunching:
            return #selector(UIApplicationDelegate.application(_:willFinishLaunchingWithOptions:))
        case .applicationDidFinishLaunching:
            return #selector(UIApplicationDelegate.application(_:didFinishLaunchingWithOptions:))
        case .applicationDidBecomeActive:
            return #selector(UIApplicationDelegate.applicationDidBecomeActive(_:))
        case .applicationWillResignActive:
            return #selector(UIApplicationDelegate.applicationWillResignActive(_:))
        case .applicationDidEnterBackground:
            return #selector(UIApplicationDelegate.applicationDidEnterBackground(_:))
        case .applicationWillEnterForeground:
            return #selector(UIApplicationDelegate.applicationWillEnterForeground(_:))
        case .applicationWillTerminate:
            return #selector(UIApplicationDelegate.applicationWillTerminate(_:))
        case .applicationDidReceiveMemoryWarning:
            return #selector(UIApplicationDelegate.applicationDidReceiveMemoryWarning(_:))
        case .applicationSignificantTimeChange:
            return #selector(UIApplicationDelegate.applicationSignificantTimeChange(_:))
        case .applicationOpenURL:
            return #selector(UIApplicationDelegate.application(_:open:options:))
        case .applicationDidRegisterForRemoteNotifications:
            return #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
        case .applicationDidFailToRegisterForRemoteNotifications:
            return #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
        case .applicationDidReceiveRemoteNotification:
            return Self.selector(named: "application:didReceiveRemoteNotification:")
        case .applicationDidReceiveRemoteNotificationFetch:
            return #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))
        case .applicationPerformFetch:
            return Self.selector(named: "application:performFetchWithCompletionHandler:")
        case .applicationHandleBackgroundURLSession:
            return #selector(UIApplicationDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:))
        case .applicationPerformShortcutAction:
            return #selector(UIApplicationDelegate.application(_:performActionFor:completionHandler:))
        case .applicationProtectedDataWillBecomeUnavailable:
            return #selector(UIApplicationDelegate.applicationProtectedDataWillBecomeUnavailable(_:))
        case .applicationProtectedDataDidBecomeAvailable:
            return #selector(UIApplicationDelegate.applicationProtectedDataDidBecomeAvailable(_:))
        case .applicationSupportedInterfaceOrientations:
            return #selector(UIApplicationDelegate.application(_:supportedInterfaceOrientationsFor:))
        case .applicationShouldAllowExtensionPoint:
            return #selector(UIApplicationDelegate.application(_:shouldAllowExtensionPointIdentifier:))
        case .applicationShouldSaveSecureState:
            return Self.selector(named: "application:shouldSaveSecureApplicationState:")
        case .applicationShouldRestoreSecureState:
            return Self.selector(named: "application:shouldRestoreSecureApplicationState:")
        case .applicationViewControllerWithRestorationPath:
            return #selector(UIApplicationDelegate.application(_:viewControllerWithRestorationIdentifierPath:coder:))
        case .applicationWillEncodeRestorableState:
            return #selector(UIApplicationDelegate.application(_:willEncodeRestorableStateWith:))
        case .applicationDidDecodeRestorableState:
            return #selector(UIApplicationDelegate.application(_:didDecodeRestorableStateWith:))
        case .applicationWillContinueUserActivity:
            return #selector(UIApplicationDelegate.application(_:willContinueUserActivityWithType:))
        case .applicationContinueUserActivity:
            return #selector(UIApplicationDelegate.application(_:continue:restorationHandler:))
        case .applicationDidFailContinueUserActivity:
            return #selector(UIApplicationDelegate.application(_:didFailToContinueUserActivityWithType:error:))
        case .applicationDidUpdateUserActivity:
            return #selector(UIApplicationDelegate.application(_:didUpdate:))
        case .applicationConfigurationForConnecting:
            return #selector(UIApplicationDelegate.application(_:configurationForConnecting:options:))
        case .applicationDidDiscardSceneSessions:
            return #selector(UIApplicationDelegate.application(_:didDiscardSceneSessions:))
        case .applicationShouldAutomaticallyLocalizeKeyCommands:
            return Self.selector(named: "applicationShouldAutomaticallyLocalizeKeyCommands:")
        case .sceneWillConnect:
            return #selector(UISceneDelegate.scene(_:willConnectTo:options:))
        case .sceneDidDisconnect:
            return #selector(UISceneDelegate.sceneDidDisconnect(_:))
        case .sceneDidBecomeActive:
            return #selector(UISceneDelegate.sceneDidBecomeActive(_:))
        case .sceneWillResignActive:
            return #selector(UISceneDelegate.sceneWillResignActive(_:))
        case .sceneWillEnterForeground:
            return #selector(UISceneDelegate.sceneWillEnterForeground(_:))
        case .sceneDidEnterBackground:
            return #selector(UISceneDelegate.sceneDidEnterBackground(_:))
        case .sceneOpenURLContexts:
            return #selector(UISceneDelegate.scene(_:openURLContexts:))
        case .sceneStateRestorationActivity:
            return #selector(UISceneDelegate.stateRestorationActivity(for:))
        case .sceneRestoreInteractionState:
            return #selector(UISceneDelegate.scene(_:restoreInteractionStateWith:))
        case .sceneWillContinueUserActivity:
            return #selector(UISceneDelegate.scene(_:willContinueUserActivityWithType:))
        case .sceneContinueUserActivity:
            return #selector(UISceneDelegate.scene(_:continue:))
        case .sceneDidFailContinueUserActivity:
            return #selector(UISceneDelegate.scene(_:didFailToContinueUserActivityWithType:error:))
        case .sceneDidUpdateUserActivity:
            return #selector(UISceneDelegate.scene(_:didUpdate:))
        case .windowSceneDidUpdateCoordinateSpace:
            return #selector(UIWindowSceneDelegate.windowScene(_:didUpdate:interfaceOrientation:traitCollection:))
        case .windowScenePerformShortcutAction:
            return #selector(UIWindowSceneDelegate.windowScene(_:performActionFor:completionHandler:))
        }
    }

    public init?(selector: Selector) {
        if let value = Self.selectorMap[NSStringFromSelector(selector)] {
            self = value
        } else {
            return nil
        }
    }

    private static let selectorMap: [String: AetherDelegateSelector] = {
        Dictionary(uniqueKeysWithValues: allCases.map { (NSStringFromSelector($0.selector), $0) })
    }()

    private static func selector(named name: String) -> Selector {
        Selector(name)
    }
}

public struct AetherDelegateMethodRegistry {
    private var userEnabled: Set<AetherDelegateSelector> = []
    private var runtimeRequired: Set<AetherDelegateSelector> = []
    private var compatibilityEnabled: Set<AetherDelegateSelector> = []

    public init() {}

    public var enabledSelectors: Set<AetherDelegateSelector> {
        userEnabled.union(runtimeRequired).union(compatibilityEnabled)
    }

    public mutating func enable(_ selector: AetherDelegateSelector) {
        userEnabled.insert(selector)
    }

    public mutating func require(_ selector: AetherDelegateSelector) {
        runtimeRequired.insert(selector)
    }

    public mutating func enableForCompatibility(_ selector: AetherDelegateSelector) {
        compatibilityEnabled.insert(selector)
    }

    public func shouldRespond(to selector: Selector) -> Bool {
        guard let mapped = AetherDelegateSelector(selector: selector) else {
            return false
        }
        return enabledSelectors.contains(mapped)
    }

    public func shouldRespond(to selector: AetherDelegateSelector) -> Bool {
        enabledSelectors.contains(selector)
    }
}

public struct AetherAppRuntimeDiagnostics {
    public var signpostsEnabled: Bool
    public var runtimeDumpEnabled: Bool
    public var logger: OSLog

    public init(
        signpostsEnabled: Bool = false,
        runtimeDumpEnabled: Bool = false,
        logger: OSLog = OSLog(subsystem: "AetherUI", category: "AetherAppRuntime")
    ) {
        self.signpostsEnabled = signpostsEnabled
        self.runtimeDumpEnabled = runtimeDumpEnabled
        self.logger = logger
    }
}
