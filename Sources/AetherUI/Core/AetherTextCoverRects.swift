import UIKit

public struct AetherTextCoverRects {
    public let lineRects: [CGRect]
    public let wordRects: [CGRect]

    public init(lineRects: [CGRect], wordRects: [CGRect]) {
        self.lineRects = lineRects
        self.wordRects = wordRects
    }
}
