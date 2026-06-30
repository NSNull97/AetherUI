import XCTest
import UIKit
@testable import AetherUI

final class AetherAppRuntimeTests: XCTestCase {
    func testEmptyAppDoesNotExposeGatedOptionalSelectors() {
        let proxy = AetherApplicationDelegateProxy<EmptyApp>()

        XCTAssertFalse(proxy.responds(to: AetherDelegateSelector.applicationOpenURL.selector))
        XCTAssertFalse(proxy.responds(to: AetherDelegateSelector.applicationPerformFetch.selector))
        XCTAssertFalse(proxy.responds(to: AetherDelegateSelector.applicationDidFinishLaunching.selector))
    }

    func testRegisteredHandlersExposeSelectors() {
        let proxy = AetherApplicationDelegateProxy<LifecycleAndURLApp>()

        XCTAssertTrue(proxy.responds(to: AetherDelegateSelector.applicationDidFinishLaunching.selector))
        XCTAssertTrue(proxy.responds(to: AetherDelegateSelector.applicationOpenURL.selector))
        XCTAssertFalse(proxy.responds(to: AetherDelegateSelector.applicationPerformFetch.selector))
    }

    func testWindowSceneRegistersRuntimeRequiredSceneSelectors() {
        let runtime = AetherApplicationRuntime(appType: SingleSceneApp.self)

        XCTAssertEqual(runtime.configuration.scenes.map(\.id.rawValue), ["main"])
        XCTAssertTrue(runtime.selectorGate.shouldRespond(to: .applicationConfigurationForConnecting))
        XCTAssertTrue(runtime.selectorGate.shouldRespond(to: .sceneWillConnect))
        XCTAssertTrue(runtime.selectorGate.shouldRespond(to: .sceneDidDisconnect))
        XCTAssertTrue(runtime.selectorGate.shouldRespond(to: .windowSceneDidUpdateCoordinateSpace))
    }

    func testBuilderSupportsConditionalsAndArrays() {
        let configuration = AetherApplicationRuntime.makeConfiguration(for: ConditionalSceneApp.self)

        XCTAssertEqual(configuration.scenes.map(\.id.rawValue), ["main", "documents", "external"])
    }

    func testPluginInstallsHandlersAndSelectors() {
        let configuration = AetherApplicationRuntime.makeConfiguration(for: PluginApp.self)

        XCTAssertEqual(configuration.appLifecycleHandlers.didBecomeActive.count, 1)
        XCTAssertTrue(configuration.selectorRegistry.shouldRespond(to: .applicationDidBecomeActive))
    }

    func testURLRoutingUsesFirstHandledStrategyByDefault() {
        let runtime = AetherApplicationRuntime(appType: URLCompositionApp.self)
        var calls: [String] = []
        URLCompositionApp.calls = { calls.append($0) }

        let handled = runtime.openURL(
            UIApplication.shared,
            url: URL(string: "aether-test://handled")!,
            options: [:]
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(calls, ["first", "second"])
    }

    func testDuplicateAppPhaseCallbacksDoNotRepeatHandlers() {
        let runtime = AetherApplicationRuntime(appType: PhaseApp.self)
        PhaseApp.activeCount = 0

        runtime.applicationDidBecomeActive(UIApplication.shared)
        runtime.applicationDidBecomeActive(UIApplication.shared)

        XCTAssertEqual(PhaseApp.activeCount, 1)
    }

    func testSelectorEnumMapsEveryCaseBackFromSelector() {
        for selector in AetherDelegateSelector.allCases {
            XCTAssertEqual(AetherDelegateSelector(selector: selector.selector), selector)
        }
    }
}

private final class EmptyApp: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {}
    }
}

private final class LifecycleAndURLApp: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            AppLifecycle()
                .onDidFinishLaunching { _ in true }

            URLRouting()
                .onOpenURL { _ in true }
        }
    }
}

private final class SingleSceneApp: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            WindowScene(id: "main") { _ in UIViewController() }
        }
    }
}

private final class ConditionalSceneApp: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            WindowScene(id: "main") { _ in UIViewController() }

            if true {
                WindowScene(id: "documents") { _ in UIViewController() }
            }

            for id in ["external"] {
                WindowScene(id: id) { _ in UIViewController() }
            }
        }
    }
}

private struct TestPlugin: AetherAppPlugin {
    func install(into configuration: inout AetherApplicationRuntimeConfiguration) {
        AppLifecycle()
            .onDidBecomeActive { _ in }
            .install(into: &configuration)
    }
}

private final class PluginApp: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            TestPlugin()
        }
    }
}

private final class URLCompositionApp: AetherApp {
    static var calls: ((String) -> Void)?

    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            URLRouting()
                .onOpenURL { _ in
                    Self.calls?("first")
                    return false
                }
                .onOpenURL { _ in
                    Self.calls?("second")
                    return true
                }
                .onOpenURL { _ in
                    Self.calls?("third")
                    return true
                }
        }
    }
}

private final class PhaseApp: AetherApp {
    static var activeCount = 0

    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            AppLifecycle()
                .onDidBecomeActive { _ in
                    Self.activeCount += 1
                }
        }
    }
}
