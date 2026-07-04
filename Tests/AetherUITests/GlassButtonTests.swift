import XCTest
import UIKit
@testable import AetherUI

final class GlassButtonTests: XCTestCase {
    func testGlassButtonIsUIControlAndDisablesGlassInteractionWhileLoading() throws {
        let button = GlassButton(title: "Done")
        button.frame = CGRect(x: 0.0, y: 0.0, width: 96.0, height: 40.0)
        button.layoutIfNeeded()

        XCTAssertTrue(button is UIControl)

        let glass = try XCTUnwrap(button.descendant(ofType: GlassBackgroundView.self))
        XCTAssertEqual(glass.params?.isInteractive, true)

        button.isLoading = true
        button.layoutIfNeeded()
        XCTAssertEqual(glass.params?.isInteractive, false)

        button.isLoading = false
        button.isEnabled = false
        button.layoutIfNeeded()
        XCTAssertEqual(glass.params?.isInteractive, false)
    }

    func testGlassBackgroundExplicitTintSurvivesLayoutPass() {
        let glass = GlassBackgroundView(style: .regular)
        let tint = GlassBackgroundView.TintColor(
            kind: .custom(style: .default, color: UIColor.systemTeal),
            innerColor: UIColor.systemBlue,
            innerInset: 2.0
        )

        glass.frame = CGRect(x: 0.0, y: 0.0, width: 120.0, height: 44.0)
        glass.update(
            size: glass.bounds.size,
            cornerRadius: 16.0,
            isDark: false,
            tintColor: tint,
            isInteractive: false,
            transition: .immediate
        )

        glass.setNeedsLayout()
        glass.layoutIfNeeded()

        XCTAssertEqual(glass.params?.tintColor, tint)
        XCTAssertEqual(glass.params?.isInteractive, false)
        XCTAssertEqual(glass.glassParams?.cornerRadius, 16.0)
    }

    func testGlassBackgroundCapsuleRadiusTracksBoundsInPropertyDrivenMode() {
        let glass = GlassBackgroundView(style: .regular)

        glass.frame = CGRect(x: 0.0, y: 0.0, width: 120.0, height: 40.0)
        glass.layoutIfNeeded()
        XCTAssertEqual(glass.glassParams?.cornerRadius, 20.0)

        glass.frame = CGRect(x: 0.0, y: 0.0, width: 120.0, height: 80.0)
        glass.layoutIfNeeded()
        XCTAssertEqual(glass.glassParams?.cornerRadius, 40.0)
    }
}

private extension UIView {
    func descendant<T: UIView>(ofType type: T.Type) -> T? {
        if let self = self as? T {
            return self
        }
        for subview in subviews {
            if let result = subview.descendant(ofType: type) {
                return result
            }
        }
        return nil
    }
}
