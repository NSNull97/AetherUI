import XCTest
import UIKit
@testable import AetherUI

final class AetherPageViewControllerTests: XCTestCase {
    func testPagerViewSegmentedControlFillsDefaultAccessoryHeight() {
        let pagerView = AetherPageViewController.PagerView(
            items: [
                AetherSegmentedControl.Item(title: "Для Вас"),
                AetherSegmentedControl.Item(title: "Читаю")
            ],
            selectedIndex: 0
        )
        let size = CGSize(width: 320.0, height: pagerView.height)

        let returnedSize = pagerView.updateLayout(
            size: size,
            leftInset: 0.0,
            rightInset: 0.0,
            transition: .immediate
        )

        XCTAssertEqual(returnedSize.height, pagerView.height, accuracy: 0.5)
        XCTAssertEqual(pagerView.segmentedControl.frame.minY, 0.0, accuracy: 0.5)
        XCTAssertEqual(pagerView.segmentedControl.frame.height, pagerView.height, accuracy: 0.5)
        XCTAssertEqual(pagerView.segmentedControl.frame.minX, 0.0, accuracy: 0.5)
        XCTAssertEqual(pagerView.segmentedControl.frame.width, 320.0, accuracy: 0.5)
    }

    func testPagerViewSegmentedControlFillsProvidedHeight() {
        let pagerView = AetherPageViewController.PagerView(
            items: [
                AetherSegmentedControl.Item(title: "Для Вас"),
                AetherSegmentedControl.Item(title: "Читаю")
            ],
            selectedIndex: 0
        )

        let _ = pagerView.updateLayout(
            size: CGSize(width: 320.0, height: 50.0),
            leftInset: 0.0,
            rightInset: 0.0,
            transition: .immediate
        )

        XCTAssertEqual(pagerView.segmentedControl.frame.minY, 0.0, accuracy: 0.5)
        XCTAssertEqual(pagerView.segmentedControl.frame.height, 50.0, accuracy: 0.5)
        XCTAssertEqual(pagerView.segmentedControl.frame.minX, 0.0, accuracy: 0.5)
        XCTAssertEqual(pagerView.segmentedControl.frame.width, 320.0, accuracy: 0.5)
    }

    func testTopBarAccessoryPagerUsesSixteenPointHorizontalInsets() {
        let controller = AetherPageViewController(
            pages: [
                AetherPageViewController.Page(title: "Для Вас", viewController: UIViewController()),
                AetherPageViewController.Page(title: "Читаю", viewController: UIViewController())
            ]
        )
        let pagerView = controller.viewPager

        let _ = pagerView.updateLayout(
            size: CGSize(width: 320.0, height: pagerView.height),
            leftInset: 0.0,
            rightInset: 0.0,
            transition: .immediate
        )

        XCTAssertTrue(controller.topBarAccessory === pagerView)
        XCTAssertEqual(pagerView.contentInsets.left, 16.0, accuracy: 0.5)
        XCTAssertEqual(pagerView.contentInsets.right, 16.0, accuracy: 0.5)
        XCTAssertEqual(pagerView.segmentedControl.frame.minX, 16.0, accuracy: 0.5)
        XCTAssertEqual(pagerView.segmentedControl.frame.width, 288.0, accuracy: 0.5)
    }

    func testPagerViewMaximumContentWidthCapsFullWidthLayout() {
        let pagerView = AetherPageViewController.PagerView(
            items: [
                AetherSegmentedControl.Item(title: "Для Вас"),
                AetherSegmentedControl.Item(title: "Читаю")
            ],
            selectedIndex: 0,
            maximumContentWidth: 180.0
        )

        let _ = pagerView.updateLayout(
            size: CGSize(width: 320.0, height: pagerView.height),
            leftInset: 0.0,
            rightInset: 0.0,
            transition: .immediate
        )

        XCTAssertEqual(pagerView.segmentedControl.frame.minX, 70.0, accuracy: 0.5)
        XCTAssertEqual(pagerView.segmentedControl.frame.width, 180.0, accuracy: 0.5)
    }

    func testPagerViewShowsSegmentBadgesOnBothLensLayers() {
        let pagerView = AetherPageViewController.PagerView(
            items: [
                AetherSegmentedControl.Item(title: "Для Вас", badgeValue: "3"),
                AetherSegmentedControl.Item(title: "Читаю")
            ],
            selectedIndex: 0
        )

        let _ = pagerView.updateLayout(
            size: CGSize(width: 320.0, height: pagerView.height),
            leftInset: 0.0,
            rightInset: 0.0,
            transition: .immediate
        )

        let badges = pagerView.segmentedControl.descendants(ofType: NavigationBarBadgeView.self)
            .filter { !$0.isHidden }
        XCTAssertEqual(badges.count, 2)
        XCTAssertTrue(badges.allSatisfy { $0.text == "3" })
    }

    func testChildPageItemUpdatesSegmentTitleAndBadge() {
        let first = AetherViewController()
        first.pageItem.title = "Initial"
        first.pageItem.badgeValue = "1"
        let second = AetherViewController()
        second.pageItem.title = "Second"
        let controller = AetherPageViewController(
            pages: [
                AetherPageViewController.Page(viewController: first),
                AetherPageViewController.Page(viewController: second)
            ],
            installViewPagerAsTopBarAccessory: false
        )

        XCTAssertEqual(controller.viewPager.segmentedControl.items[0], AetherSegmentedControl.Item(title: "Initial", badgeValue: "1"))

        first.pageItem.title = "Updated"
        first.pageItem.badgeValue = "2"

        XCTAssertEqual(controller.viewPager.segmentedControl.items[0], AetherSegmentedControl.Item(title: "Updated", badgeValue: "2"))
    }

    func testChildPageItemCanRequestSelection() {
        let first = AetherViewController()
        first.pageItem.title = "First"
        let second = AetherViewController()
        second.pageItem.title = "Second"
        let controller = AetherPageViewController(
            pages: [
                AetherPageViewController.Page(viewController: first),
                AetherPageViewController.Page(viewController: second)
            ],
            installViewPagerAsTopBarAccessory: false
        )

        second.pageItem.select(animated: false)

        XCTAssertEqual(controller.selectedIndex, 1)
        XCTAssertFalse(first.pageItem.isSelected)
        XCTAssertTrue(second.pageItem.isSelected)
    }

    func testEmbeddedAetherPageDoesNotHostItsOwnNavigationBar() {
        let child = AetherViewController(
            navigationBarPresentationData: NavigationBarPresentationData(theme: .overhaulGlass(accentButtonColor: .systemBlue))
        )
        let controller = AetherPageViewController(
            pages: [
                AetherPageViewController.Page(title: "Child", viewController: child)
            ],
            installViewPagerAsTopBarAccessory: false
        )

        controller.loadViewIfNeeded()
        controller.containerLayoutUpdated(
            ContainerViewLayout(
                size: CGSize(width: 320.0, height: 640.0),
                safeInsets: UIEdgeInsets(top: 47.0, left: 0.0, bottom: 34.0, right: 0.0),
                statusBarHeight: 47.0
            ),
            transition: .immediate
        )

        XCTAssertTrue(child.navigationBarIsExternallyHosted)
        XCTAssertEqual(child.externalNavigationBarHeight ?? -1.0, 0.0, accuracy: 0.5)
        XCTAssertEqual(child.additionalSafeAreaInsets.top, 0.0, accuracy: 0.5)
        XCTAssertFalse(child.navigationBarView?.superview === child.view)
    }

    func testPreloadedEmbeddedAetherPageRemovesLocalNavigationBar() {
        let child = AetherViewController(
            navigationBarPresentationData: NavigationBarPresentationData(theme: .overhaulGlass(accentButtonColor: .systemBlue))
        )
        child.loadViewIfNeeded()
        XCTAssertTrue(child.navigationBarView?.superview === child.view)

        let controller = AetherPageViewController(
            pages: [
                AetherPageViewController.Page(title: "Child", viewController: child)
            ],
            installViewPagerAsTopBarAccessory: false
        )
        controller.loadViewIfNeeded()

        XCTAssertTrue(child.navigationBarIsExternallyHosted)
        XCTAssertEqual(child.externalNavigationBarHeight ?? -1.0, 0.0, accuracy: 0.5)
        XCTAssertFalse(child.navigationBarView?.superview === child.view)
    }

    func testPagerAllowsFullWidthInteractivePopOnlyOnFirstPage() {
        let controller = AetherPageViewController(
            pages: [
                AetherPageViewController.Page(title: "First", viewController: UIViewController()),
                AetherPageViewController.Page(title: "Second", viewController: UIViewController())
            ],
            selectedIndex: 0,
            installViewPagerAsTopBarAccessory: false
        )

        XCTAssertEqual(controller.interactiveNavivationGestureEdgeWidth?.effectiveWidth(for: 320.0) ?? -1.0, 320.0, accuracy: 0.5)

        controller.setSelectedIndex(1, animated: false)

        XCTAssertEqual(controller.interactiveNavivationGestureEdgeWidth?.effectiveWidth(for: 320.0) ?? -1.0, 0.0, accuracy: 0.5)
    }

    func testPagerPagePanYieldsRightSwipeToInteractivePopOnFirstPage() {
        let controller = AetherPageViewController(
            pages: [
                AetherPageViewController.Page(title: "First", viewController: UIViewController()),
                AetherPageViewController.Page(title: "Second", viewController: UIViewController())
            ],
            selectedIndex: 0,
            installViewPagerAsTopBarAccessory: false
        )

        XCTAssertFalse(controller.shouldBeginPagePan(for: CGPoint(x: 120.0, y: 4.0)))
        XCTAssertTrue(controller.shouldBeginPagePan(for: CGPoint(x: -120.0, y: 4.0)))
        XCTAssertTrue(controller.shouldBeginPagePan(for: CGPoint(x: 4.0, y: 120.0)))

        controller.setSelectedIndex(1, animated: false)

        XCTAssertTrue(controller.shouldBeginPagePan(for: CGPoint(x: 120.0, y: 4.0)))
    }

    func testScrollProgressMovesPagerLensContinuously() throws {
        let controller = AetherPageViewController(
            pages: [
                AetherPageViewController.Page(title: "Для Вас", viewController: UIViewController()),
                AetherPageViewController.Page(title: "Читаю", viewController: UIViewController())
            ],
            installViewPagerAsTopBarAccessory: false
        )
        let pagerView = controller.viewPager
        let _ = pagerView.updateLayout(
            size: CGSize(width: 320.0, height: pagerView.height),
            leftInset: 0.0,
            rightInset: 0.0,
            transition: .immediate
        )

        controller.scrollView.bounds = CGRect(x: 0.0, y: 0.0, width: 320.0, height: 480.0)
        controller.scrollView.contentOffset = CGPoint(x: 160.0, y: 0.0)
        controller.scrollViewDidScroll(controller.scrollView)

        let firstFrame = try XCTUnwrap(pagerView.segmentedControl.debugItemFrame(at: 0))
        let secondFrame = try XCTUnwrap(pagerView.segmentedControl.debugItemFrame(at: 1))
        let selectionFrame = pagerView.segmentedControl.debugSelectionFrame
        XCTAssertEqual(selectionFrame?.minX ?? -1.0, firstFrame.minX + (secondFrame.minX - firstFrame.minX) * 0.5, accuracy: 0.5)
        XCTAssertEqual(selectionFrame?.width ?? 0.0, firstFrame.width + (secondFrame.width - firstFrame.width) * 0.5, accuracy: 0.5)
        XCTAssertEqual(controller.selectedIndex, 0)
    }

    func testCommittingSelectionWithoutProgressUpdatePreservesCurrentLensPosition() {
        let control = AetherSegmentedControl(
            items: [
                AetherSegmentedControl.Item(title: "Для Вас"),
                AetherSegmentedControl.Item(title: "Читаю")
            ],
            selectedIndex: 0
        )
        control.frame = CGRect(x: 0.0, y: 0.0, width: 320.0, height: 36.0)
        control.layoutIfNeeded()

        let initialFrame = control.debugSelectionFrame
        control.setSelectedIndex(1, animated: false, updatesSelectionProgress: false)
        control.layoutIfNeeded()

        XCTAssertEqual(control.selectedIndex, 1)
        XCTAssertEqual(control.debugSelectionFrame?.minX ?? -1.0, initialFrame?.minX ?? -2.0, accuracy: 0.5)
    }

    func testSegmentedControlKeepsAtLeastTwelvePointsOfHorizontalPaddingPerSegment() throws {
        let control = AetherSegmentedControl(
            items: [
                AetherSegmentedControl.Item(title: "A"),
                AetherSegmentedControl.Item(title: "B")
            ],
            selectedIndex: 0
        )
        control.frame = CGRect(x: 0.0, y: 0.0, width: 140.0, height: 36.0)
        control.layoutIfNeeded()

        let firstFrame = try XCTUnwrap(control.debugItemFrame(at: 0))
        let firstLabel = try XCTUnwrap(control.descendantLabel(text: "A"))
        XCTAssertGreaterThanOrEqual(firstFrame.width, firstLabel.intrinsicContentSize.width + 24.0 - 0.5)
    }

    func testSegmentedControlScrollsWhenSegmentsExceedAvailableWidth() throws {
        let control = AetherSegmentedControl(
            items: (0..<8).map { AetherSegmentedControl.Item(title: "Segment \($0)") },
            selectedIndex: 0
        )
        control.frame = CGRect(x: 0.0, y: 0.0, width: 180.0, height: 36.0)
        control.layoutIfNeeded()

        let lensView = try XCTUnwrap(control.descendants(ofType: LiquidLensView.self).first)
        XCTAssertGreaterThan(control.debugScrollView.contentSize.width, control.bounds.width)
        XCTAssertTrue(control.debugScrollView.alwaysBounceHorizontal)
        XCTAssertEqual(lensView.bounds.width, control.bounds.width, accuracy: 0.5)
    }

    func testSegmentedControlKeepsGlassViewportFixedWhileContentScrolls() throws {
        let control = AetherSegmentedControl(
            items: (0..<8).map { AetherSegmentedControl.Item(title: "Segment \($0)") },
            selectedIndex: 6
        )
        control.frame = CGRect(x: 0.0, y: 0.0, width: 180.0, height: 36.0)
        control.layoutIfNeeded()

        let lensView = try XCTUnwrap(control.descendants(ofType: LiquidLensView.self).first)
        XCTAssertGreaterThan(control.debugScrollView.contentOffset.x, 0.0)
        XCTAssertEqual(lensView.frame, control.bounds)
        XCTAssertLessThanOrEqual(control.debugSelectionFrame?.maxX ?? .greatestFiniteMagnitude, control.bounds.maxX + 0.5)
    }
}

private extension UIView {
    func descendants<T: UIView>(ofType type: T.Type) -> [T] {
        var result: [T] = []
        if let view = self as? T {
            result.append(view)
        }
        for subview in subviews {
            result.append(contentsOf: subview.descendants(ofType: type))
        }
        return result
    }

    func descendantLabel(text: String) -> UILabel? {
        if let label = self as? UILabel, label.text == text || label.attributedText?.string == text {
            return label
        }
        for subview in subviews {
            if let label = subview.descendantLabel(text: text) {
                return label
            }
        }
        return nil
    }
}
