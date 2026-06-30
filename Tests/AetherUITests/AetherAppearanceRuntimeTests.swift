import XCTest
import UIKit
@testable import AetherUI

final class AetherAppearanceRuntimeTests: XCTestCase {
    func testAppearancePresetsUseFixedSpecValues() {
        let iOS26 = AetherAppearance.iOS26
        XCTAssertEqual(iOS26.style, .iOS26)
        XCTAssertFalse(iOS26.overallDarkAppearance)
        XCTAssertEqual(iOS26.edgeEffectAlpha, 0.82)
        XCTAssertEqual(iOS26.edgeEffectBlurRadiusAtEdge, 2.0)
        XCTAssertEqual(iOS26.edgeEffectBlurRadiusAtFade, 0.0)
        XCTAssertEqual(iOS26.edgeEffectStyle, .regular)

        let iOS27 = AetherAppearance.iOS27
        XCTAssertEqual(iOS27.style, .iOS27)
        XCTAssertFalse(iOS27.overallDarkAppearance)
        XCTAssertEqual(iOS27.edgeEffectAlpha, 0.82)
        XCTAssertEqual(iOS27.edgeEffectBlurRadiusAtEdge, 5.0)
        XCTAssertEqual(iOS27.edgeEffectBlurRadiusAtFade, 5.0)
        XCTAssertEqual(iOS27.edgeEffectStyle, .strong)
    }

    func testAppearanceStyleNodeInstallsEnvironmentAppearance() {
        let configuration = AetherApplicationRuntime.makeConfiguration(for: AppearanceStyleApp.self)

        XCTAssertEqual(configuration.environment.appearanceStyle, .iOS27)
        XCTAssertEqual(configuration.environment.appearance.signature, AetherAppearance.iOS27.signature)
    }

    func testAppearanceStyleModifierInstallsEnvironmentAppearance() {
        let configuration = AetherApplicationRuntime.makeConfiguration(for: AppearanceStyleModifierApp.self)

        XCTAssertEqual(configuration.environment.appearanceStyle, .iOS27)
        XCTAssertEqual(configuration.environment.appearance.signature, AetherAppearance.iOS27.signature)
    }

    func testNavigationResolverAppliesPartialOverride() {
        let context = AetherAppearanceResolutionContext(
            appearance: .iOS27,
            surface: .navigation,
            placement: .navigation
        )
        let override = AetherNavigationBarAppearanceOverride(
            separator: .visible(color: .red, opacity: 0.5),
            edgeEffect: AetherEdgeEffectAppearance(
                tintColor: .green,
                alpha: 0.25,
                blurRadiusAtEdge: 9.0,
                blurRadiusAtFade: 4.0,
                style: .regular
            )
        )

        let resolved = AetherNavigationBarAppearanceResolver.resolve(context: context, override: override)

        if case let .visible(_, opacity) = resolved.separator {
            XCTAssertEqual(opacity, 0.5)
        } else {
            XCTFail("Expected visible separator override")
        }
        XCTAssertEqual(resolved.edgeEffect.alpha, 0.25)
        XCTAssertEqual(resolved.edgeEffect.blurRadiusAtEdge, 9.0)
        XCTAssertEqual(resolved.edgeEffect.blurRadiusAtFade, 4.0)
        XCTAssertFalse(resolved.edgeEffect.solidBlur)
        XCTAssertEqual(resolved.edgeEffect.style, .regular)
    }

    func testNavigationControllerConsumesRuntimeAppearanceWithoutThemeInit() {
        let navigationController = AetherNavigationController()

        navigationController.updateAppearance(.iOS27)

        let theme = navigationController.navigationBar.presentationData.theme
        XCTAssertEqual(theme.edgeEffectBlurRadiusAtEdge, 5.0)
        XCTAssertEqual(theme.edgeEffectBlurRadiusAtFade, 5.0)
        XCTAssertTrue(theme.edgeEffectSolidBlur)
        XCTAssertEqual(theme.edgeEffectStyle, .strong)
        XCTAssertEqual(theme.glassStyle, .strong)
    }

    func testNavigationControllerUsesScopedRenderAppearanceOnInit() {
        let navigationController = AetherAppearance.withRuntimeCurrent(.iOS27) {
            AetherNavigationController()
        }

        let theme = navigationController.navigationBar.presentationData.theme
        XCTAssertEqual(theme.edgeEffectBlurRadiusAtEdge, 5.0)
        XCTAssertEqual(theme.edgeEffectBlurRadiusAtFade, 5.0)
        XCTAssertTrue(theme.edgeEffectSolidBlur)
        XCTAssertEqual(theme.edgeEffectStyle, .strong)
        XCTAssertEqual(theme.glassStyle, .strong)
    }

    func testAetherPresentationDataUsesScopedAppearanceAndAccent() {
        let presentationData = AetherAppearance.withRuntimeCurrent(.iOS27) {
            NavigationBarPresentationData.aetherAppearance(accentButtonColor: .red)
        }

        XCTAssertEqual(presentationData.theme.edgeEffectBlurRadiusAtEdge, 5.0)
        XCTAssertEqual(presentationData.theme.edgeEffectBlurRadiusAtFade, 5.0)
        XCTAssertTrue(presentationData.theme.edgeEffectSolidBlur)
        XCTAssertEqual(presentationData.theme.edgeEffectStyle, .strong)
        XCTAssertEqual(presentationData.theme.glassStyle, .strong)
        XCTAssertEqual(presentationData.theme.accentButtonColor, .red)
    }

    func testStrongNavigationBarShowsScrollSeparator() {
        let strongData = AetherAppearance.withRuntimeCurrent(.iOS27) {
            NavigationBarPresentationData.aetherAppearance()
        }
        let strongBar = NavigationBarImpl(presentationData: strongData)
        strongBar.updateBackgroundAlpha(1.0, transition: .immediate)
        XCTAssertEqual(strongBar.stripeView.alpha, 1.0)

        let regularData = AetherAppearance.withRuntimeCurrent(.iOS26) {
            NavigationBarPresentationData.aetherAppearance()
        }
        let regularBar = NavigationBarImpl(presentationData: regularData)
        regularBar.updateBackgroundAlpha(1.0, transition: .immediate)
        XCTAssertEqual(regularBar.stripeView.alpha, 0.0)
    }

    func testRegularNavigationAppearanceNeverResolvesSeparator() {
        var appearance = AetherAppearance.iOS27
        appearance.edgeEffectStyle = .regular
        let resolved = AetherNavigationBarAppearanceResolver.resolve(context: AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .navigation,
            placement: .navigation
        ))

        if case .hidden = resolved.separator {
        } else {
            XCTFail("Regular navigation glass must not resolve a separator")
        }

        let theme = NavigationBarTheme(aetherResolvedAppearance: resolved)
        XCTAssertEqual(theme.separatorColor.cgColor.alpha, 0.0)
    }

    func testRegularNavigationEdgeEffectDoesNotBleedBelowBar() throws {
        var appearance = AetherAppearance.iOS27
        appearance.edgeEffectStyle = .regular
        let resolved = AetherNavigationBarAppearanceResolver.resolve(context: AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .navigation,
            placement: .navigation
        ))
        let bar = NavigationBarImpl(presentationData: NavigationBarPresentationData(
            theme: NavigationBarTheme(aetherResolvedAppearance: resolved)
        ))
        let size = CGSize(width: 320.0, height: 144.0)

        bar.updateLayout(
            size: size,
            defaultHeight: 60.0,
            additionalTopHeight: 0.0,
            additionalContentHeight: 0.0,
            additionalBackgroundHeight: 0.0,
            leftInset: 0.0,
            rightInset: 0.0,
            appearsHidden: false,
            isLandscape: false,
            transition: .immediate
        )

        let edgeEffectView = try XCTUnwrap(bar.debugEdgeEffectView)
        XCTAssertEqual(edgeEffectView.frame.maxY, size.height, accuracy: 0.1)
        XCTAssertEqual(edgeEffectView.debugLastEdgeSize ?? -1.0, edgeEffectView.bounds.height + 1.0, accuracy: 0.1)
        XCTAssertEqual(edgeEffectView.debugLastSolidBlur, false)
        XCTAssertGreaterThan(edgeEffectView.debugLastBlurRadiusAtEdge ?? -1.0, edgeEffectView.debugLastBlurRadiusAtFade ?? -2.0)
        XCTAssertEqual(edgeEffectView.debugLastBlurRadiusAtFade ?? -1.0, 0.0, accuracy: 0.001)
        XCTAssertEqual(edgeEffectView.debugLastPrefersStaticVariableBlurMask, true)
        XCTAssertNotEqual(edgeEffectView.debugLastContentRGBA, 0)
        XCTAssertEqual(edgeEffectView.debugLastFadeCurveExponent ?? -1.0, 2.0, accuracy: 0.001)
    }

    func testTabBarControllerConsumesRuntimeAppearanceWithoutThemeInit() {
        let tabBarController = AetherTabBarController()

        tabBarController.updateAppearance(.iOS27)

        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.alpha, 0.0)
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.blurRadiusAtEdge, 0.0)
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.blurRadiusAtFade, 0.0)
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.style, .strong)
    }

    func testIOS27MakesTabSearchAndInputEdgeEffectsTransparentByDefault() {
        let tab = AetherTabBarAppearanceResolver.resolve(context: AetherAppearanceResolutionContext(
            appearance: .iOS27,
            surface: .tab,
            placement: .tab
        ))
        let search = AetherSearchAppearanceResolver.resolve(context: AetherAppearanceResolutionContext(
            appearance: .iOS27,
            surface: .search,
            placement: .top
        ))
        let input = AetherInputBarAppearanceResolver.resolve(context: AetherAppearanceResolutionContext(
            appearance: .iOS27,
            surface: .inputBar,
            placement: .inputAccessory
        ))

        for edgeEffect in [tab.edgeEffect, search.edgeEffect, input.edgeEffect] {
            XCTAssertEqual(edgeEffect.alpha, 0.0)
            XCTAssertEqual(edgeEffect.blurRadiusAtEdge, 0.0)
            XCTAssertEqual(edgeEffect.blurRadiusAtFade, 0.0)
            XCTAssertTrue(edgeEffect.solidBlur)
            XCTAssertEqual(edgeEffect.style, .strong)
            XCTAssertEqual(edgeEffect.tintColor?.cgColor.alpha ?? -1.0, 0.0)
        }
    }

    func testTabBarControllerUsesTopControllerAppearanceOverride() {
        let content = TabBarOverrideController()
        let navigationController = AetherNavigationController(rootViewController: content)
        let tabBarController = AetherTabBarController()
        tabBarController.setControllers([navigationController], selectedIndex: 0)

        tabBarController.updateAppearance(.iOS27)

        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.alpha, 0.33)
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.blurRadiusAtEdge, 7.0)
        XCTAssertEqual(tabBarController.resolvedAppearance.edgeEffect.blurRadiusAtFade, 3.0)
    }

    func testTabBarControllerMergesOwnOverrideWithTopControllerOverride() {
        let content = TabBarSelectedTextOverrideController()
        let navigationController = AetherNavigationController(rootViewController: content)
        let tabBarController = BaseTabBarOverrideController()
        tabBarController.setControllers([navigationController], selectedIndex: 0)

        tabBarController.updateAppearance(.iOS27)

        XCTAssertEqual(tabBarController.resolvedAppearance.selectedIconColor, .red)
        XCTAssertEqual(tabBarController.resolvedAppearance.selectedTextColor, .green)
    }
}

private final class AppearanceStyleApp: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            AppearanceStyle(.iOS27)
        }
    }
}

private final class AppearanceStyleModifierApp: AetherApp {
    required init() {}

    var current: some ApplicationBuilder {
        AetherApplication {
            WindowScene(id: "main") { _ in UIViewController() }
        }
        .appearanceStyle(.iOS27)
    }
}

private final class TabBarOverrideController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .tab else {
            return nil
        }
        return AetherAppearanceOverride(
            tabBar: AetherTabBarAppearanceOverride(
                edgeEffect: AetherEdgeEffectAppearance(
                    tintColor: .green,
                    alpha: 0.33,
                    blurRadiusAtEdge: 7.0,
                    blurRadiusAtFade: 3.0,
                    style: .regular
                )
            )
        )
    }
}

private final class BaseTabBarOverrideController: AetherTabBarController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .tab else {
            return nil
        }
        return AetherAppearanceOverride(
            tabBar: AetherTabBarAppearanceOverride(
                selectedIconColor: .red,
                selectedTextColor: .red
            )
        )
    }
}

private final class TabBarSelectedTextOverrideController: AetherViewController, AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        guard context.surface == .tab else {
            return nil
        }
        return AetherAppearanceOverride(
            tabBar: AetherTabBarAppearanceOverride(
                selectedTextColor: .green
            )
        )
    }
}
