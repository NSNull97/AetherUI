import XCTest
import UIKit
@testable import AetherUI

final class TextNodeTests: XCTestCase {
    func testDetectedLinkHasRectsAndHitTesting() throws {
        let text = "Open https://example.com from here"
        let attributed = TextNode.detectLinks(in: NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16.0),
                .foregroundColor: UIColor.label
            ]
        ))

        let node = TextNode(frame: CGRect(x: 0.0, y: 0.0, width: 260.0, height: 80.0))
        node.maximumNumberOfLines = 0
        node.attributedText = attributed
        _ = node.updateLayout(node.bounds.size)

        let linkRange = (text as NSString).range(of: "https://example.com")
        let rects = try XCTUnwrap(node.attributeRects(for: .link, at: linkRange.location))
        XCTAssertFalse(rects.isEmpty)

        let hitPoint = CGPoint(x: rects[0].midX, y: rects[0].midY)
        let hit = try XCTUnwrap(node.attributesAtPoint(hitPoint))
        XCTAssertTrue(NSLocationInRange(hit.0, linkRange))
        XCTAssertNotNil(hit.1[.link])
    }

    func testTextCoverRectsExposeLinesAndWords() {
        let node = TextNode(frame: CGRect(x: 0.0, y: 0.0, width: 180.0, height: 80.0))
        node.maximumNumberOfLines = 0
        node.attributedText = NSAttributedString(
            string: "hello world",
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.0),
                .foregroundColor: UIColor.label
            ]
        )
        _ = node.updateLayout(node.bounds.size)

        let coverRects = node.textCoverRects()
        XCTAssertFalse(coverRects.lineRects.isEmpty)
        XCTAssertEqual(coverRects.wordRects.count, 2)
    }

    func testLabelTextCoverRectsExposeLinesAndWords() {
        let label = UILabel(frame: CGRect(x: 0.0, y: 0.0, width: 180.0, height: 80.0))
        label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: 15.0)
        label.textColor = .label
        label.text = "hello world"

        let coverRects = AetherTextCoverRects.make(for: label)
        XCTAssertFalse(coverRects.lineRects.isEmpty)
        XCTAssertEqual(coverRects.wordRects.count, 2)
        XCTAssertEqual(coverRects.effectiveRects.count, 2)
    }

    func testInvisibleInkOnTextNodeUsesSiblingOverlayAndRestoresAlpha() {
        let hostView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: 240.0, height: 120.0))
        let node = TextNode(frame: CGRect(x: 20.0, y: 20.0, width: 180.0, height: 80.0))
        node.maximumNumberOfLines = 0
        node.attributedText = NSAttributedString(
            string: "hidden words",
            attributes: [
                .font: UIFont.systemFont(ofSize: 15.0),
                .foregroundColor: UIColor.label
            ]
        )
        hostView.addSubview(node)
        _ = node.updateLayout(node.bounds.size)

        let inkView = node.setInvisibleInk(true, configuration: AetherInvisibleInkConfiguration(particleColor: .label), animated: false)

        XCTAssertTrue(inkView?.superview === hostView)
        XCTAssertEqual(node.alpha, 0.0)

        node.removeInk(animated: false)

        XCTAssertNil(node.aetherInvisibleInk)
        XCTAssertNil(inkView?.superview)
        XCTAssertEqual(node.alpha, 1.0)
    }
}
