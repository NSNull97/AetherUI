import XCTest
import UIKit
@testable import AetherUI

final class NavigationBarButtonLayerTests: XCTestCase {
    override func tearDown() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer
        super.tearDown()
    }

    func testSeparatedButtonLayerHostsCustomButtonOutsideContentHierarchy() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)
        let customView = UIButton(type: .system)
        customView.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 32.0)

        let item = NavigationBarItem()
        item.leftBarButtonItems = [UIBarButtonItem(customView: customView)]

        bar.item = item
        layout(bar)

        XCTAssertIdentical(bar.debugButtonLayer.superview, hostView)
        XCTAssertFalse(bar.debugButtonLayer.isDescendant(of: bar))
        XCTAssertTrue(customView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertFalse(customView.isDescendant(of: bar.debugButtonsContainerView))
        XCTAssertIdentical(customView, item.leftBarButtonItems?.first?.customView)
    }

    func testLegacyInlineModeStillAvailableForComparison() {
        NavigationBarImpl.defaultButtonHostingMode = .legacyInline

        let bar = makeBar()
        let customView = UIButton(type: .system)
        customView.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 32.0)

        let item = NavigationBarItem()
        item.leftBarButtonItems = [UIBarButtonItem(customView: customView)]

        bar.item = item
        layout(bar)

        XCTAssertFalse(customView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertTrue(customView.isDescendant(of: bar.debugButtonsContainerView))
    }

    func testCustomButtonViewIdentitySurvivesRelayoutAndIsRemovedWithItem() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)
        let customView = UIButton(type: .system)
        customView.frame = CGRect(x: 0.0, y: 0.0, width: 44.0, height: 32.0)

        let item = NavigationBarItem()
        item.rightBarButtonItems = [UIBarButtonItem(customView: customView)]

        bar.item = item
        layout(bar)
        let firstSuperview = customView.superview

        layout(bar)

        XCTAssertIdentical(customView, item.rightBarButtonItems?.first?.customView)
        XCTAssertIdentical(customView.superview, firstSuperview)
        XCTAssertTrue(customView.isDescendant(of: bar.debugButtonLayer))

        let replacement = NavigationBarItem()
        bar.item = replacement
        layout(bar)

        XCTAssertNil(customView.superview)
    }

    func testCustomTitleViewMovesToButtonLayerButPlainTitleStaysInline() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)
        let titleView = UILabel()
        titleView.text = "Custom"
        titleView.frame = CGRect(x: 0.0, y: 0.0, width: 80.0, height: 24.0)

        let customTitleItem = NavigationBarItem()
        customTitleItem.titleView = titleView

        bar.item = customTitleItem
        layout(bar)

        XCTAssertTrue(titleView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertFalse(titleView.isDescendant(of: bar.debugButtonsContainerView))
        XCTAssertIdentical(titleView, customTitleItem.titleView)

        let plainTitleItem = NavigationBarItem()
        plainTitleItem.title = "Plain"
        plainTitleItem.subtitle = "Subtitle"

        bar.item = plainTitleItem
        layout(bar)

        XCTAssertNil(titleView.superview)
        XCTAssertNil(bar.debugButtonLayer.descendantLabel(text: "Plain"))
        XCTAssertNil(bar.debugButtonLayer.descendantLabel(text: "Subtitle"))
        XCTAssertNotNil(bar.debugButtonsContainerView.descendantLabel(text: "Plain"))
        XCTAssertNotNil(bar.debugButtonsContainerView.descendantLabel(text: "Subtitle"))
    }

    func testLegacyRightButtonMorphAppearsAnchoredAtFinalRightEdge() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)

        let sourceItem = NavigationBarItem()
        sourceItem.rightBarButtonItems = [UIBarButtonItem(title: "Old", style: .plain, target: nil, action: nil)]
        bar.item = sourceItem
        layout(bar)

        let oldButton = bar.debugButtonLayer.descendantButton(title: "Old")
        XCTAssertNotNil(oldButton)

        let targetItem = NavigationBarItem()
        targetItem.rightBarButtonItems = [UIBarButtonItem(title: "New", style: .plain, target: nil, action: nil)]

        bar.withButtonMorphTransition(morphTransition()) {
            bar.item = targetItem
            layout(bar, transition: morphTransition())
        }

        let newButton = bar.debugButtonLayer.descendantButton(title: "New")
        XCTAssertNotNil(newButton)
        XCTAssertNotNil(oldButton?.superview)

        guard let newButton, let container = newButton.superview else {
            return
        }
        XCTAssertEqual(container.frame.maxX, 312.0, accuracy: 0.5)
        XCTAssertEqual(newButton.frame.maxX, container.bounds.width, accuracy: 0.5)
    }

    func testCustomTitleViewMorphUsesButtonLayerForOutgoingAndIncomingViews() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)
        let sourceTitleView = UILabel()
        sourceTitleView.text = "Source Custom"
        sourceTitleView.frame = CGRect(x: 0.0, y: 0.0, width: 110.0, height: 24.0)

        let sourceItem = NavigationBarItem()
        sourceItem.titleView = sourceTitleView
        bar.item = sourceItem
        layout(bar)

        let targetTitleView = UILabel()
        targetTitleView.text = "Target Custom"
        targetTitleView.frame = CGRect(x: 0.0, y: 0.0, width: 110.0, height: 24.0)
        let targetItem = NavigationBarItem()
        targetItem.titleView = targetTitleView

        bar.withButtonMorphTransition(morphTransition()) {
            bar.item = targetItem
            layout(bar)
        }

        XCTAssertTrue(sourceTitleView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertTrue(targetTitleView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertFalse(targetTitleView.isDescendant(of: bar.debugButtonsContainerView))
    }

    func testCustomTitleViewIsHiddenInTitleTransitionMode() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)
        let titleView = UILabel()
        titleView.text = "Custom"
        titleView.frame = CGRect(x: 0.0, y: 0.0, width: 80.0, height: 24.0)

        let item = NavigationBarItem()
        item.titleView = titleView

        bar.item = item
        layout(bar)
        bar.setTitleTransitionMode(true)
        layout(bar)

        XCTAssertTrue(titleView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertEqual(titleView.alpha, 0.0, accuracy: 0.001)
    }

    func testTransitionTitleBarDoesNotStealCustomTitleViewFromButtonLayer() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let sharedHostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let sharedBar = makeBar(hostView: sharedHostView)
        let titleView = UILabel()
        titleView.text = "Custom"
        titleView.frame = CGRect(x: 0.0, y: 0.0, width: 80.0, height: 24.0)

        let item = NavigationBarItem()
        item.titleView = titleView

        sharedBar.item = item
        layout(sharedBar)

        let transitionHostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let transitionBar = makeBar(hostView: transitionHostView)
        transitionBar.hostsNavigationItemTitleView = false
        transitionBar.setTitleTransitionMode(true)
        transitionBar.item = item
        layout(transitionBar)

        XCTAssertTrue(titleView.isDescendant(of: sharedBar.debugButtonLayer))
        XCTAssertFalse(titleView.isDescendant(of: transitionBar.debugButtonLayer))
        XCTAssertFalse(titleView.isDescendant(of: transitionBar.debugButtonsContainerView))
        XCTAssertIdentical(titleView, item.titleView)
    }

    func testTallCustomTitleHeightIsAvailableBeforeFirstLayoutAndIncludesAccessory() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let titleView = FixedSizeView(size: CGSize(width: 120.0, height: 92.0))
        let item = NavigationBarItem()
        item.titleView = titleView

        let bar = makeBar()
        bar.item = item
        bar.setContentView(FixedExpansionContentView(height: 34.0), animated: false)
        bar.updateMeasuredTitleHeight(
            titleView: item.titleView,
            size: CGSize(width: 320.0, height: 104.0),
            defaultHeight: 60.0,
            leftInset: 0.0,
            rightInset: 0.0,
            requestLayoutIfNeeded: false
        )

        XCTAssertEqual(bar.contentHeight(defaultHeight: 60.0), 126.0, accuracy: 0.5)

        let transitionBar = makeBar()
        transitionBar.hostsNavigationItemTitleView = false
        transitionBar.item = item
        transitionBar.setContentView(FixedExpansionContentView(height: 34.0), animated: false)
        transitionBar.updateMeasuredTitleHeight(
            titleView: item.titleView,
            size: CGSize(width: 320.0, height: 104.0),
            defaultHeight: 60.0,
            leftInset: 0.0,
            rightInset: 0.0,
            requestLayoutIfNeeded: false
        )

        XCTAssertEqual(transitionBar.contentHeight(defaultHeight: 60.0), 126.0, accuracy: 0.5)
        XCTAssertIdentical(titleView, item.titleView)
        XCTAssertFalse(titleView.isDescendant(of: transitionBar.debugButtonLayer))
    }

    func testAppearingTallCustomTitleKeepsFinalBoundsDuringMorphSetup() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 140.0))
        let bar = makeBar(hostView: hostView)

        let sourceItem = NavigationBarItem()
        sourceItem.titleView = FixedSizeView(size: CGSize(width: 120.0, height: 92.0))
        bar.item = sourceItem
        layout(bar, height: 140.0)

        let targetTitleView = FixedSizeView(size: CGSize(width: 120.0, height: 92.0))
        let targetItem = NavigationBarItem()
        targetItem.titleView = targetTitleView

        bar.withButtonMorphTransition(morphTransition()) {
            bar.item = targetItem
            layout(bar, height: 140.0, transition: morphTransition())
        }

        XCTAssertTrue(targetTitleView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertEqual(targetTitleView.bounds.width, 120.0, accuracy: 0.5)
        XCTAssertEqual(targetTitleView.bounds.height, 92.0, accuracy: 0.5)
        XCTAssertEqual(targetTitleView.center.y, 46.0, accuracy: 0.5)
    }

    func testButtonOnlyHeightOverrideKeepsTallCustomTitleInTitleRow() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 180.0))
        let bar = makeBar(hostView: hostView)
        let titleView = FixedSizeView(size: CGSize(width: 120.0, height: 92.0))
        let item = NavigationBarItem()
        item.titleView = titleView

        bar.item = item
        bar.setContentHeightOverride(126.0)
        bar.updateMeasuredTitleHeight(
            titleView: item.titleView,
            size: CGSize(width: 320.0, height: 180.0),
            defaultHeight: 60.0,
            leftInset: 0.0,
            rightInset: 0.0,
            requestLayoutIfNeeded: false
        )
        layout(bar, height: 180.0)

        XCTAssertTrue(titleView.isDescendant(of: bar.debugButtonLayer))
        XCTAssertEqual(titleView.bounds.height, 92.0, accuracy: 0.5)
        XCTAssertEqual(titleView.center.y, 46.0, accuracy: 0.5)
    }

    func testURLImageCustomButtonKeepsExplicitSizeAfterLargeImageLoads() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView, style: .glass)
        let target = BarButtonActionTarget()
        let barButtonItem = UIBarButtonItem(
            imageURL: nil,
            placeholderImage: makeImage(size: CGSize(width: 180.0, height: 180.0)),
            target: target,
            action: #selector(BarButtonActionTarget.invoke(_:))
        )
        guard let button = barButtonItem.customView as? UIButton else {
            XCTFail("URL image bar button should be backed by a UIButton custom view")
            return
        }

        let item = NavigationBarItem()
        item.rightBarButtonItems = [barButtonItem]
        bar.item = item
        layout(bar)

        button.setImage(makeImage(size: CGSize(width: 180.0, height: 180.0)), for: .normal)
        layout(bar)
        button.layoutIfNeeded()

        let glassGroup = bar.debugButtonLayer.descendant(ofType: GlassControlGroup.self)
        XCTAssertTrue(button.isDescendant(of: bar.debugButtonLayer))
        XCTAssertNotNil(glassGroup)
        XCTAssertTrue(glassGroup.map { button.isDescendant(of: $0) } ?? false)
        XCTAssertTrue(glassGroup?.isUserInteractionEnabled ?? false)
        XCTAssertTrue(button.superview?.isUserInteractionEnabled ?? false)
        XCTAssertIdentical(button, barButtonItem.customView)
        XCTAssertEqual(button.bounds.width, 38.0, accuracy: 0.5)
        XCTAssertEqual(button.bounds.height, 38.0, accuracy: 0.5)
        XCTAssertEqual(button.frame.width, 38.0, accuracy: 0.5)
        XCTAssertEqual(button.frame.height, 38.0, accuracy: 0.5)
        XCTAssertEqual(button.imageView?.frame.width ?? 0.0, 38.0, accuracy: 0.5)
        XCTAssertEqual(button.imageView?.frame.height ?? 0.0, 38.0, accuracy: 0.5)
        XCTAssertFalse(button.adjustsImageWhenHighlighted)
        XCTAssertFalse(button.adjustsImageWhenDisabled)
        XCTAssertFalse(button.showsTouchWhenHighlighted)
        XCTAssertEqual(
            button.actions(forTarget: target, forControlEvent: .touchUpInside),
            ["invoke:"]
        )
    }

    func testTargetActionStillWiredFromBarButtonItem() {
        NavigationBarImpl.defaultButtonHostingMode = .separatedLayer

        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0))
        let bar = makeBar(hostView: hostView)
        let target = BarButtonActionTarget()

        let item = NavigationBarItem()
        item.rightBarButtonItems = [
            UIBarButtonItem(
                title: "Tap",
                style: .plain,
                target: target,
                action: #selector(BarButtonActionTarget.invoke(_:))
            )
        ]

        bar.item = item
        layout(bar)

        let button = bar.debugButtonLayer.descendantButton(title: "Tap")
        XCTAssertNotNil(button)

        XCTAssertEqual(
            button?.actions(forTarget: target, forControlEvent: .touchUpInside),
            ["invoke:"]
        )
    }

    func testButtonLayerHitTestingReturnsButtonsAndPassesThroughEmptySpace() {
        let layer = AetherNavigationBarButtonLayer(frame: CGRect(x: 0.0, y: 0.0, width: 240.0, height: 60.0))
        let button = UIButton(type: .system)

        layer.applyButtonPlacements(
            [
                AetherNavigationBarButtonPlacement(
                    id: "button",
                    view: button,
                    frame: CGRect(x: 12.0, y: 10.0, width: 44.0, height: 40.0),
                    hitTestInsets: UIEdgeInsets(top: 4.0, left: 4.0, bottom: 4.0, right: 4.0)
                )
            ],
            transition: .existing(.immediate)
        )

        XCTAssertIdentical(layer.hitTest(CGPoint(x: 20.0, y: 20.0), with: nil), button)
        XCTAssertIdentical(layer.hitTest(CGPoint(x: 9.0, y: 20.0), with: nil), button)
        XCTAssertNil(layer.hitTest(CGPoint(x: 120.0, y: 20.0), with: nil))
    }

    private func makeBar(hostView: UIView? = nil, style: NavigationBarStyle = .legacy) -> NavigationBarImpl {
        let bar = NavigationBarImpl(
            presentationData: NavigationBarPresentationData(
                theme: NavigationBarTheme(style: style)
            )
        )
        bar.frame = CGRect(x: 0.0, y: 0.0, width: 320.0, height: 104.0)
        if let hostView {
            hostView.addSubview(bar)
            bar.buttonLayerHostView = hostView
        }
        return bar
    }

    private func layout(_ bar: NavigationBarImpl, height: CGFloat = 104.0, transition: ContainedViewLayoutTransition = .immediate) {
        bar.updateLayout(
            size: CGSize(width: 320.0, height: height),
            defaultHeight: 60.0,
            additionalTopHeight: 0.0,
            additionalContentHeight: 0.0,
            additionalBackgroundHeight: 0.0,
            leftInset: 0.0,
            rightInset: 0.0,
            appearsHidden: false,
            isLandscape: false,
            transition: transition
        )
    }

    private func morphTransition() -> ContainedViewLayoutTransition {
        .animated(duration: 0.44, curve: .custom(0.16, 1.0, 0.30, 1.0))
    }

    private func makeImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private final class BarButtonActionTarget: NSObject {
    @objc func invoke(_ sender: Any?) {
    }
}

private final class FixedSizeView: UIView {
    let fixedSize: CGSize

    init(size: CGSize) {
        self.fixedSize = size
        super.init(frame: CGRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        fixedSize
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        fixedSize
    }
}

private final class FixedExpansionContentView: NavigationBarContentView {
    let fixedHeight: CGFloat

    init(height: CGFloat) {
        self.fixedHeight = height
        super.init(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: height))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var nominalHeight: CGFloat {
        fixedHeight
    }

    override var mode: NavigationBarContentMode {
        .expansion
    }
}

private extension UIView {
    func descendant<T: UIView>(ofType type: T.Type) -> T? {
        if let view = self as? T {
            return view
        }
        for subview in subviews {
            if let view = subview.descendant(ofType: type) {
                return view
            }
        }
        return nil
    }

    func descendantButton(title: String) -> UIButton? {
        if let button = self as? UIButton, button.title(for: .normal) == title {
            return button
        }
        for subview in subviews {
            if let button = subview.descendantButton(title: title) {
                return button
            }
        }
        return nil
    }

    func descendantLabel(text: String) -> UILabel? {
        if let label = self as? UILabel, label.text == text {
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
