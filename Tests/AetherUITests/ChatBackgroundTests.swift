import XCTest
import UIKit
@testable import AetherUI

final class ChatBackgroundTests: XCTestCase {
    func testGradientVectorForCardinalAngles() {
        let horizontal = ChatBackgroundSettings.gradientVector(rotation: 0.0)
        XCTAssertEqual(horizontal.startPoint.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(horizontal.startPoint.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(horizontal.endPoint.x, 1.0, accuracy: 0.001)
        XCTAssertEqual(horizontal.endPoint.y, 0.5, accuracy: 0.001)

        let vertical = ChatBackgroundSettings.gradientVector(rotation: 90.0)
        XCTAssertEqual(vertical.startPoint.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(vertical.startPoint.y, 0.0, accuracy: 0.001)
        XCTAssertEqual(vertical.endPoint.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(vertical.endPoint.y, 1.0, accuracy: 0.001)
    }

    func testContentStatsClassifyDarkAndSaturatedColors() {
        let black = ChatBackgroundSettings.contentStats(for: [UIColor.black])
        XCTAssertTrue(black.isDark)
        XCTAssertFalse(black.isSaturated)

        let red = ChatBackgroundSettings.contentStats(for: [UIColor.red])
        XCTAssertFalse(red.isDark)
        XCTAssertTrue(red.isSaturated)
    }

    func testPatternClampsIntensityAndScale() {
        let pattern = ChatBackgroundSettings.Pattern(intensity: 3.0, scale: 0.01)
        XCTAssertEqual(pattern.clampedIntensity, 1.0)
        XCTAssertEqual(pattern.clampedScale, 0.15)
    }

    func testDefaultPatternImageHasRequestedSize() {
        let image = ChatBackgroundSettings.makeDefaultPatternImage(size: CGSize(width: 80.0, height: 60.0))
        XCTAssertEqual(image.size.width, 80.0, accuracy: 0.001)
        XCTAssertEqual(image.size.height, 60.0, accuracy: 0.001)
    }
}
