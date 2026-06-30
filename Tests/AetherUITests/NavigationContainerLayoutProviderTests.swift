import XCTest
import UIKit
@testable import AetherUI

final class NavigationContainerLayoutProviderTests: XCTestCase {
    private final class LayoutProbeController: AetherViewController {
        var receivedLayouts: [ContainerViewLayout] = []

        override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
            receivedLayouts.append(layout)
            super.containerLayoutUpdated(layout, transition: transition)
        }
    }

    private final class InteractivePopDisabledController: AetherViewController {
        override var interactiveNavivationGestureEdgeWidth: InteractiveTransitionGestureRecognizerEdgeWidth? {
            return .constant(0.0)
        }
    }

    private final class TransitionProbeAccessoryView: NavigationBarContentView {
        var receivedTransitions: [ContainedViewLayoutTransition] = []

        override var nominalHeight: CGFloat {
            return 36.0
        }

        override var mode: NavigationBarContentMode {
            return .expansion
        }

        override func updateLayout(
            size: CGSize,
            leftInset: CGFloat,
            rightInset: CGFloat,
            transition: ContainedViewLayoutTransition
        ) -> CGSize {
            receivedTransitions.append(transition)
            return CGSize(width: size.width, height: nominalHeight)
        }
    }

    func testIncomingPushReceivesControllerSpecificLayoutAtTransitionStart() {
        let source = LayoutProbeController()
        let target = LayoutProbeController()
        let container = NavigationContainer(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        let baseLayout = ContainerViewLayout(
            size: CGSize(width: 320.0, height: 640.0),
            safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
            additionalInsets: UIEdgeInsets(top: 0.0, left: 0.0, bottom: 69.0, right: 0.0),
            statusBarHeight: 47.0
        )

        container.layoutForController = { controller, layout in
            var additionalInsets = layout.additionalInsets
            if controller === target {
                additionalInsets.bottom = 0.0
            }
            return layout.withUpdatedAdditionalInsets(additionalInsets)
        }

        container.setControllers([source], animated: false)
        container.containerLayoutUpdated(baseLayout, transition: .immediate)
        target.receivedLayouts.removeAll()

        container.setControllers([source, target], animated: true)

        guard let firstTargetLayout = target.receivedLayouts.first else {
            XCTFail("Incoming controller did not receive an initial layout")
            return
        }
        XCTAssertEqual(firstTargetLayout.additionalInsets.bottom, 0.0, accuracy: 0.5)
        XCTAssertEqual(target.view.frame.minX, baseLayout.size.width, accuracy: 0.5)
    }

    func testNonInteractivePushUsesTargetBottomBarSafeAreaImmediately() {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        let root = LayoutProbeController()
        root.displayNavigationBar = false
        let navigationController = AetherNavigationController(rootViewController: root)
        let tabBarController = AetherTabBarController()
        tabBarController.setControllers([navigationController], selectedIndex: 0)

        window.rootViewController = tabBarController
        window.isHidden = false
        tabBarController.loadViewIfNeeded()
        tabBarController.view.frame = window.bounds
        tabBarController.containerLayoutUpdated(
            ContainerViewLayout(size: window.bounds.size, safeInsets: .zero, additionalInsets: .zero),
            transition: .immediate
        )

        XCTAssertGreaterThan(tabBarController.additionalSafeAreaInsets.bottom, 60.0)

        let target = LayoutProbeController()
        target.displayNavigationBar = false
        target.hidesBottomBarWhenPushed = true
        navigationController.pushViewController(target, animated: true)

        XCTAssertEqual(tabBarController.additionalSafeAreaInsets.bottom, 0.0, accuracy: 0.5)
        XCTAssertEqual(target.receivedLayouts.first?.additionalInsets.bottom ?? -1.0, 0.0, accuracy: 0.5)

        window.isHidden = true
    }

    func testKeyboardOnlyLayoutDoesNotAnimateSharedNavigationBarChrome() {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        let root = LayoutProbeController()
        let accessory = TransitionProbeAccessoryView()
        root.topBarAccessory = accessory
        let navigationController = AetherNavigationController(rootViewController: root)
        window.rootViewController = navigationController
        window.isHidden = false
        navigationController.loadViewIfNeeded()
        navigationController.view.frame = window.bounds

        let baseLayout = ContainerViewLayout(
            size: window.bounds.size,
            safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
            statusBarHeight: 47.0
        )
        navigationController.containerLayoutUpdated(baseLayout, transition: .immediate)
        accessory.receivedTransitions.removeAll()

        let keyboardLayout = ContainerViewLayout(
            size: baseLayout.size,
            safeInsets: baseLayout.safeInsets,
            statusBarHeight: baseLayout.statusBarHeight,
            inputHeight: 291.0
        )
        navigationController.containerLayoutUpdated(
            keyboardLayout,
            transition: .animated(duration: 0.25, curve: .spring)
        )

        XCTAssertEqual(root.receivedLayouts.last?.inputHeight ?? -1.0, 291.0, accuracy: 0.5)
        XCTAssertFalse(accessory.receivedTransitions.last?.isAnimated ?? true)

        window.isHidden = true
    }

    func testBottomInsetOnlyLayoutDoesNotAnimateSharedNavigationBarChrome() {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        let root = LayoutProbeController()
        let accessory = TransitionProbeAccessoryView()
        root.topBarAccessory = accessory
        let navigationController = AetherNavigationController(rootViewController: root)
        window.rootViewController = navigationController
        window.isHidden = false
        navigationController.loadViewIfNeeded()
        navigationController.view.frame = window.bounds

        let baseLayout = ContainerViewLayout(
            size: window.bounds.size,
            safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
            additionalInsets: UIEdgeInsets(top: 0.0, left: 0.0, bottom: 69.0, right: 0.0),
            statusBarHeight: 47.0
        )
        navigationController.containerLayoutUpdated(baseLayout, transition: .immediate)
        accessory.receivedTransitions.removeAll()

        let bottomAccessoryLayout = baseLayout.withUpdatedAdditionalInsets(
            UIEdgeInsets(top: 0.0, left: 0.0, bottom: 133.0, right: 0.0)
        )
        navigationController.containerLayoutUpdated(
            bottomAccessoryLayout,
            transition: .animated(duration: 0.32, curve: .easeInOut)
        )

        XCTAssertEqual(root.receivedLayouts.last?.additionalInsets.bottom ?? -1.0, 133.0, accuracy: 0.5)
        XCTAssertFalse(accessory.receivedTransitions.last?.isAnimated ?? true)

        window.isHidden = true
    }

    func testInteractivePopGestureDirectionsIncludeFullWidthRightPan() {
        let container = NavigationContainer(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        container.setControllers([AetherViewController(), AetherViewController()], animated: false)

        let directions = container.interactivePopGestureDirections(at: CGPoint(x: 160.0, y: 320.0))

        XCTAssertTrue(directions.contains(.right))
        XCTAssertTrue(directions.contains(.leftEdge))
    }

    func testInteractivePopGestureDirectionsRespectZeroWidthOptOut() {
        let container = NavigationContainer(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 640.0))
        container.setControllers([AetherViewController(), InteractivePopDisabledController()], animated: false)

        let directions = container.interactivePopGestureDirections(at: CGPoint(x: 1.0, y: 320.0))

        XCTAssertTrue(directions.isEmpty)
    }
}
