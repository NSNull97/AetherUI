import XCTest
import UIKit
@testable import AetherUI

final class AetherWindowRuntimeTests: XCTestCase {
    func testPresentationContextOrdersControllersBySurfaceLevel() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let context = AetherPresentationContext(containerView: container)
        let lower = UIViewController()
        let higher = UIViewController()
        lower.view.backgroundColor = .red
        higher.view.backgroundColor = .blue

        context.present(higher, on: .overlay)
        context.present(lower, on: .modal)
        context.updateLayout(AetherWindowLayout(size: container.bounds.size), transition: .immediate)

        XCTAssertEqual(context.presentedControllers.map(\.level), [.modal, .overlay])
        XCTAssertEqual(container.subviews.first, lower.view)
        XCTAssertEqual(container.subviews.last, higher.view)
    }

    func testPresentationDismissIsIdempotentAndRestoresAccessibility() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let context = AetherPresentationContext(containerView: root)
        let lowerAccessibility = UIView()
        root.addSubview(lowerAccessibility)
        context.underlyingAccessibilityViews = [lowerAccessibility]

        let overlay = UIViewController()
        overlay.view.backgroundColor = .black
        context.present(overlay, on: .overlay, blockInteraction: true)

        XCTAssertTrue(lowerAccessibility.accessibilityElementsHidden)
        XCTAssertEqual(context.blockInteractionTokens.count, 0)

        context.dismiss(overlay)
        context.dismiss(overlay)

        XCTAssertFalse(lowerAccessibility.accessibilityElementsHidden)
        XCTAssertTrue(context.presentedControllers.isEmpty)
        XCTAssertNil(overlay.view.superview)
    }

    func testKeyboardNotificationParsingConvertsFrameToWindowHeight() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let notification = Notification(
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
            userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: CGRect(x: 0, y: 424, width: 320, height: 216)),
                UIResponder.keyboardAnimationDurationUserInfoKey: NSNumber(value: 0.25),
                UIResponder.keyboardAnimationCurveUserInfoKey: NSNumber(value: UIView.AnimationCurve.easeInOut.rawValue)
            ]
        )

        let parsed = AetherKeyboardManager.state(from: notification, in: window)

        XCTAssertTrue(parsed.0.isVisible)
        XCTAssertEqual(parsed.0.height, 216, accuracy: 0.5)
        XCTAssertEqual(parsed.0.frameInWindow.minY, 424, accuracy: 0.5)
        XCTAssertEqual(parsed.0.animationDuration, 0.25, accuracy: 0.001)
    }

    func testKeyboardAutocorrectionPreservesSelection() {
        let textView = UITextView()
        textView.text = "abcdef"
        textView.selectedRange = NSRange(location: 3, length: 0)

        AetherKeyboardAutocorrection.apply(to: textView)

        XCTAssertEqual(textView.selectedRange.location, 3)
        XCTAssertEqual(textView.selectedRange.length, 0)
    }

    func testKeyboardAutomaticHandlingOptionsAreStoredOnViews() {
        let view = UIView()

        view.aetherKeyboardAutomaticHandlingOptions = [.disableForward]

        XCTAssertEqual(view.aetherKeyboardAutomaticHandlingOptions, [.disableForward])
    }

    func testKeyboardSurfaceCancelTransitionDoesNotUseSpring() {
        let transition = AetherLegacyKeyboardRuntime.keyboardSurfaceTransition(
            targetOffset: 0.0,
            previousBoundsMinY: -120.0,
            transition: .animated(duration: 0.25, curve: .spring)
        )

        guard case let .animated(duration, curve) = transition else {
            XCTFail("Expected animated transition")
            return
        }
        XCTAssertEqual(duration, 0.25, accuracy: 0.001)
        guard case .easeInOut = curve else {
            XCTFail("Keyboard surface cancel should not use spring")
            return
        }
    }

    func testScrollViewStopScrollingAnimationPreservesState() {
        let scrollView = UIScrollView()
        scrollView.contentSize = CGSize(width: 100, height: 1000)
        scrollView.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        scrollView.contentOffset = CGPoint(x: 0, y: 120)
        scrollView.isScrollEnabled = true

        scrollView.aetherStopScrollingAnimation()

        XCTAssertEqual(scrollView.contentOffset.y, 120, accuracy: 0.5)
        XCTAssertTrue(scrollView.isScrollEnabled)
    }

    func testLegacyAnimationDurationFactorIsExplicit() {
        let previous = AetherLegacyAnimation.animationDurationFactor
        AetherLegacyAnimation.animationDurationFactor = 0.5
        defer {
            AetherLegacyAnimation.animationDurationFactor = previous
        }

        XCTAssertEqual(AetherLegacyAnimation.adjustedDuration(2.0), 1.0, accuracy: 0.001)
    }

    func testOrientationDefaultsMatchPhoneAndPadRules() {
        XCTAssertEqual(AetherOrientationCoordinator.defaultMask(userInterfaceIdiom: .phone), .allButUpsideDown)
        XCTAssertEqual(AetherOrientationCoordinator.defaultMask(userInterfaceIdiom: .pad), .all)
    }

    func testPortalFallbackTracksSourceFrameAndAvoidsAccessibilityDuplicate() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let source = AetherPortalSourceView(frame: CGRect(x: 20, y: 30, width: 80, height: 40))
        source.backgroundColor = .green
        root.addSubview(source)

        let portalHost = UIView(frame: root.bounds)
        root.addSubview(portalHost)
        let portal = AetherPortalView(sourceView: source)
        portalHost.addSubview(portal)
        portal.syncToSource()

        XCTAssertEqual(portal.frame, source.frame)
        XCTAssertTrue(portal.accessibilityElementsHidden)
        XCTAssertFalse(source.accessibilityElementsHidden)

        source.removeFromSuperview()
        portal.syncToSource()
        XCTAssertTrue(portal.isHidden)
    }
}
