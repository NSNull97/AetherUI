import XCTest
import UIKit
@testable import AetherUI

final class AetherGooeyContextMenuTransitionTests: XCTestCase {
    func testDefaultConfigurationTracksAppearance() {
        let iOS26 = AetherGooeyContextMenuTransitionConfiguration.default(appearance: .iOS26)
        XCTAssertEqual(iOS26.glassStyle, .regular)
        XCTAssertEqual(iOS26.durationOpen, 0.58, accuracy: 0.001)
        XCTAssertEqual(iOS26.durationClose, 0.48, accuracy: 0.001)

        let iOS27 = AetherGooeyContextMenuTransitionConfiguration.default(appearance: .iOS27)
        XCTAssertEqual(iOS27.glassStyle, .strong)
        XCTAssertGreaterThan(iOS27.strokeAlpha, iOS26.strokeAlpha)
        XCTAssertGreaterThan(iOS27.connectorMaximumThickness, iOS26.connectorMaximumThickness)
    }

    func testGooeyTimingBezierMatchesRequestedCurveShape() {
        let early = AetherGooeyMath.cubicBezierProgress(
            0.20,
            x1: 0.2,
            y1: 0.8,
            x2: 0.2,
            y2: 1.0
        )
        let middle = AetherGooeyMath.cubicBezierProgress(
            0.50,
            x1: 0.2,
            y1: 0.8,
            x2: 0.2,
            y2: 1.0
        )

        XCTAssertGreaterThan(early, 0.55)
        XCTAssertGreaterThan(middle, 0.88)
        XCTAssertEqual(AetherGooeyMath.cubicBezierProgress(0.0, x1: 0.2, y1: 0.8, x2: 0.2, y2: 1.0), 0.0)
        XCTAssertEqual(AetherGooeyMath.cubicBezierProgress(1.0, x1: 0.2, y1: 0.8, x2: 0.2, y2: 1.0), 1.0)
    }

    func testCaptureGeometryBelowPlacement() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 160.0, y: 90.0, width: 44.0, height: 44.0))
        source.layer.cornerRadius = 22.0
        let menu = UIView(frame: CGRect(x: 80.0, y: 160.0, width: 260.0, height: 220.0))
        menu.layer.cornerRadius = 27.0
        container.addSubview(source)
        container.addSubview(menu)

        let geometry = captureGooeyGeometry(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .below
        )

        XCTAssertEqual(geometry.sourceFrameInContainer, source.frame)
        XCTAssertEqual(geometry.menuFrameInContainer, menu.frame)
        XCTAssertEqual(geometry.sourceCornerRadius, 22.0)
        XCTAssertEqual(geometry.menuCornerRadius, 27.0)
        XCTAssertEqual(geometry.placement, .below)
        XCTAssertEqual(geometry.distance, 26.0, accuracy: 0.001)
        XCTAssertEqual(geometry.connectorStartPoint.y, source.frame.maxY)
        XCTAssertEqual(geometry.connectorEndPoint.y, menu.frame.minY)
    }

    func testCaptureGeometryFallsBackWhenSourceIsNil() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let menu = UIView(frame: CGRect(x: 80.0, y: 160.0, width: 260.0, height: 220.0))
        container.addSubview(menu)

        let geometry = captureGooeyGeometry(
            sourceView: nil,
            menuView: menu,
            containerView: container,
            placement: .below
        )

        XCTAssertFalse(geometry.sourceFrameInContainer.isNull)
        XCTAssertGreaterThan(geometry.sourceFrameInContainer.width, 0.0)
        XCTAssertGreaterThan(geometry.sourceFrameInContainer.height, 0.0)
        XCTAssertEqual(geometry.connectorEndPoint.y, menu.frame.minY)
    }

    func testCaptureGeometryUsesCapsuleFallbackForSmallZeroRadiusSource() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 300.0, y: 64.0, width: 52.0, height: 52.0))
        let menu = UIView(frame: CGRect(x: 80.0, y: 160.0, width: 260.0, height: 220.0))
        container.addSubview(source)
        container.addSubview(menu)

        let geometry = captureGooeyGeometry(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .below
        )

        XCTAssertEqual(geometry.sourceCornerRadius, 26.0, accuracy: 0.001)
    }

    func testCaptureGeometryHonorsExplicitFixedZeroSourceRadius() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 300.0, y: 64.0, width: 52.0, height: 52.0))
        let menu = UIView(frame: CGRect(x: 80.0, y: 160.0, width: 260.0, height: 220.0))
        container.addSubview(source)
        container.addSubview(menu)

        let geometry = captureGooeyGeometry(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .below,
            sourceCornerRadiusPolicy: .fixed(0.0),
            menuCornerRadiusPolicy: .fixed(27.0)
        )

        XCTAssertEqual(geometry.sourceCornerRadius, 0.0, accuracy: 0.001)
    }

    func testConnectorPathForSeparatedRectsIsNonEmpty() {
        let source = CGRect(x: 160.0, y: 90.0, width: 44.0, height: 44.0)
        let menu = CGRect(x: 80.0, y: 160.0, width: 260.0, height: 220.0)

        let path = AetherGooeyConnectorView.makeConnectorPath(
            source: source,
            menu: menu,
            placement: .below,
            progress: 0.5,
            minThickness: 8.0,
            maxThickness: 28.0,
            maxConnectorLength: 96.0
        )

        XCTAssertFalse(path.boundingBoxOfPath.isNull)
        XCTAssertGreaterThan(path.boundingBoxOfPath.height, 0.0)
        XCTAssertGreaterThan(path.boundingBoxOfPath.width, 0.0)
    }

    func testConnectorPathAtZeroProgressIsEmpty() {
        let path = AetherGooeyConnectorView.makeConnectorPath(
            source: CGRect(x: 10.0, y: 10.0, width: 44.0, height: 44.0),
            menu: CGRect(x: 10.0, y: 90.0, width: 260.0, height: 220.0),
            placement: .below,
            progress: 0.0,
            minThickness: 8.0,
            maxThickness: 28.0,
            maxConnectorLength: 96.0
        )

        XCTAssertTrue(path.isEmpty)
    }

    func testMatureOpeningMaskNoLongerExtendsBackToSourceTail() throws {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 312.0, y: 72.0, width: 44.0, height: 44.0))
        let menu = UIView(frame: CGRect(x: 80.0, y: 160.0, width: 260.0, height: 220.0))
        container.addSubview(source)
        container.addSubview(menu)
        let geometry = captureGooeyGeometry(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .below,
            sourceCornerRadiusPolicy: .fixed(22.0),
            menuCornerRadiusPolicy: .fixed(27.0)
        )
        let morphView = AetherGooeyMorphSurfaceView(frame: container.bounds)
        let configuration = AetherGooeyContextMenuTransitionConfiguration.default(appearance: .iOS26)

        morphView.update(
            geometry: geometry,
            progress: 0.80,
            phase: .opening,
            configuration: configuration,
            accessibilitySettings: AetherGooeyAccessibilitySettings(
                reduceMotion: false,
                reduceTransparency: false,
                increasedContrast: false
            )
        )

        let bounds = try XCTUnwrap(morphView.currentPath?.boundingBoxOfPath)
        XCTAssertGreaterThan(bounds.minY, source.frame.maxY)
        XCTAssertLessThan(bounds.maxX, source.frame.maxX - 6.0)
    }

    @MainActor
    func testOpenFromPrestagedHiddenMenuFinishesVisibleAndInteractive() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 24.0, y: 64.0, width: 44.0, height: 44.0))
        let menu = MenuGlassSurfaceView(isDark: false, effectsEnabled: false)
        menu.frame = CGRect(x: 96.0, y: 124.0, width: 260.0, height: 176.0)
        menu.alpha = 0.0
        menu.isUserInteractionEnabled = false
        container.addSubview(source)
        container.addSubview(menu)

        let configuration = AetherGooeyContextMenuTransitionConfiguration(
            durationOpen: 0.01,
            durationClose: 0.01,
            springDamping: 1.0,
            springResponse: 0.2,
            connectorMaximumLength: 96.0,
            connectorMinimumThickness: 8.0,
            connectorMaximumThickness: 24.0,
            sourceCornerRadiusPolicy: .fixed(22.0),
            menuCornerRadiusPolicy: .fixed(27.0),
            glassStyle: .regular,
            blurIntensity: 0.0,
            tintAlpha: 0.0,
            strokeAlpha: 0.0,
            shadowAlpha: 0.0,
            highlightAlpha: 0.0,
            allowsLensingApproximation: false,
            respectsReduceMotion: false,
            respectsReduceTransparency: false,
            debugShowsControlPoints: false
        )
        let transition = AetherGooeyContextMenuTransition(configuration: configuration)
        let expectation = expectation(description: "gooey open completes")

        transition.animateOpen(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .trailing,
            completion: { finished in
                XCTAssertTrue(finished)
                expectation.fulfill()
            }
        )

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(menu.alpha, 1.0, accuracy: 0.001)
        XCTAssertTrue(menu.isUserInteractionEnabled)
        XCTAssertEqual(source.alpha, 0.0, accuracy: 0.001)
    }

    @MainActor
    func testOpenDoesNotScaleRealMenuSurface() {
        let container = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 390.0, height: 844.0))
        let source = UIView(frame: CGRect(x: 312.0, y: 72.0, width: 44.0, height: 44.0))
        let menu = MenuGlassSurfaceView(isDark: false, effectsEnabled: false)
        menu.frame = CGRect(x: 96.0, y: 124.0, width: 260.0, height: 176.0)
        menu.alpha = 0.0
        container.addSubview(source)
        container.addSubview(menu)

        let configuration = AetherGooeyContextMenuTransitionConfiguration(
            durationOpen: 1.0,
            durationClose: 0.01,
            springDamping: 1.0,
            springResponse: 0.2,
            connectorMaximumLength: 96.0,
            connectorMinimumThickness: 8.0,
            connectorMaximumThickness: 24.0,
            sourceCornerRadiusPolicy: .fixed(22.0),
            menuCornerRadiusPolicy: .fixed(27.0),
            glassStyle: .regular,
            blurIntensity: 0.0,
            tintAlpha: 0.0,
            strokeAlpha: 0.0,
            shadowAlpha: 0.0,
            highlightAlpha: 0.0,
            allowsLensingApproximation: false,
            respectsReduceMotion: false,
            respectsReduceTransparency: false,
            debugShowsControlPoints: false
        )
        let transition = AetherGooeyContextMenuTransition(configuration: configuration)

        transition.animateOpen(
            sourceView: source,
            menuView: menu,
            containerView: container,
            placement: .trailing,
            completion: { _ in }
        )

        XCTAssertEqual(menu.transform.a, 1.0, accuracy: 0.001)
        XCTAssertEqual(menu.transform.d, 1.0, accuracy: 0.001)
        XCTAssertEqual(menu.transform.tx, 0.0, accuracy: 0.001)
        XCTAssertEqual(menu.transform.ty, 0.0, accuracy: 0.001)
        XCTAssertNil(menu.layer.mask)
        transition.cancel()
    }
}
