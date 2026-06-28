import XCTest
import UIKit
@testable import AetherUI

final class AetherTabBarControllerTests: XCTestCase {
    func testActivateSearchMinimizesTabBarWithoutFocusingInput() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs

        XCTAssertFalse(tabs.isTabBarMinimized)

        tabs.activateSearch()

        XCTAssertTrue(tabs.isTabBarMinimized)
        let textField = tabs.view.firstDescendant(of: UITextField.self)
        XCTAssertNotNil(textField)
        XCTAssertFalse(textField?.isFirstResponder ?? true)

        fixture.window.isHidden = true
    }

    func testBottomAccessoryInstallDoesNotAnimateTrailingSearchButton() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        guard let searchButton = tabs.view.firstDescendant(of: GlassBarButtonView.self) else {
            XCTFail("Expected search showcase button")
            return
        }
        let initialFrame = searchButton.frame
        searchButton.layer.removeAllAnimations()

        tabs.setBottomBarAccessory(FixedBottomAccessoryView(height: 56.0), animated: true)
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(searchButton.frame.minX, initialFrame.minX, accuracy: 0.5)
        XCTAssertEqual(searchButton.frame.minY, initialFrame.minY, accuracy: 0.5)
        XCTAssertEqual(searchButton.frame.width, initialFrame.width, accuracy: 0.5)
        XCTAssertEqual(searchButton.frame.height, initialFrame.height, accuracy: 0.5)
        XCTAssertTrue(searchButton.layer.animationKeys()?.isEmpty ?? true)

        fixture.window.isHidden = true
    }

    func testBottomAccessoryRemovalDoesNotAnimateTrailingSearchButton() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs
        tabs.bottomBarAccessory = FixedBottomAccessoryView(height: 56.0)
        tabs.view.layoutIfNeeded()
        guard let searchButton = tabs.view.firstDescendant(of: GlassBarButtonView.self) else {
            XCTFail("Expected search showcase button")
            return
        }
        let initialFrame = searchButton.frame
        searchButton.layer.removeAllAnimations()

        tabs.setBottomBarAccessory(nil, animated: true)
        tabs.view.layoutIfNeeded()

        XCTAssertEqual(searchButton.frame.minX, initialFrame.minX, accuracy: 0.5)
        XCTAssertEqual(searchButton.frame.minY, initialFrame.minY, accuracy: 0.5)
        XCTAssertEqual(searchButton.frame.width, initialFrame.width, accuracy: 0.5)
        XCTAssertEqual(searchButton.frame.height, initialFrame.height, accuracy: 0.5)
        XCTAssertTrue(searchButton.layer.animationKeys()?.isEmpty ?? true)

        fixture.window.isHidden = true
    }

    #if DEBUG
    func testTapMinimizedActiveTabClosesSearchAndRestoresExpandedState() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs

        tabs.activateSearch()
        XCTAssertTrue(tabs.isTabBarMinimized)

        tabs.simulateMinimizedActiveTabTapForTests()

        XCTAssertFalse(tabs.isTabBarMinimized)

        fixture.window.isHidden = true
    }

    func testTapMinimizedActiveTabClosesSearchAndKeepsPreviouslyMinimizedState() {
        let fixture = makeTabBarFixture()
        let tabs = fixture.tabs

        tabs.setTabBarMinimized(true, transition: .immediate)
        XCTAssertTrue(tabs.isTabBarMinimized)

        tabs.activateSearch()
        tabs.simulateMinimizedActiveTabTapForTests()

        XCTAssertTrue(tabs.isTabBarMinimized)

        fixture.window.isHidden = true
    }
    #endif

    private func makeTabBarFixture() -> (window: UIWindow, tabs: AetherTabBarController) {
        let window = UIWindow(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let tabs = AetherTabBarController()
        tabs.searchShowcase = TabBarView.SearchShowcase(
            icon: UIImage(systemName: "magnifyingglass"),
            action: {}
        )
        tabs.setControllers([
            makeController(title: "One", image: "house"),
            makeController(title: "Two", image: "person")
        ], selectedIndex: 0)

        window.rootViewController = tabs
        window.isHidden = false
        tabs.loadViewIfNeeded()
        tabs.view.frame = window.bounds
        tabs.containerLayoutUpdated(
            ContainerViewLayout(size: window.bounds.size, safeInsets: .zero, additionalInsets: .zero),
            transition: .immediate
        )
        tabs.view.layoutIfNeeded()
        return (window, tabs)
    }

    private func makeController(title: String, image: String) -> AetherViewController {
        let controller = AetherViewController()
        let icon = UIImage(systemName: image)
        controller.tabBarItem = UITabBarItem(title: title, image: icon, selectedImage: icon)
        return controller
    }
}

private final class FixedBottomAccessoryView: TabBarAccessoryView {
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        self.fixedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var nominalHeight: CGFloat {
        fixedHeight
    }
}

private extension UIView {
    func firstDescendant<T: UIView>(of type: T.Type) -> T? {
        if let view = self as? T {
            return view
        }
        for subview in subviews {
            if let match = subview.firstDescendant(of: type) {
                return match
            }
        }
        return nil
    }
}
