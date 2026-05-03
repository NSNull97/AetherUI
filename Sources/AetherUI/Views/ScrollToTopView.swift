import UIKit

/// Invisible scroll view that intercepts status bar taps to trigger scroll-to-top.
final class ScrollToTopView: UIScrollView, UIScrollViewDelegate {
    var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentSize = CGSize(width: 1.0, height: frame.height + 1.0)
        self.contentOffset = CGPoint(x: 0.0, y: 1.0)
        self.scrollsToTop = true
        self.delegate = self
        self.isHidden = false
        self.alpha = 0.0
        self.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var frame: CGRect {
        didSet {
            if frame != oldValue && frame.height > 0 {
                self.contentSize = CGSize(width: 1.0, height: frame.height + 1.0)
                self.contentOffset = CGPoint(x: 0.0, y: 1.0)
            }
        }
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        action?()
        return false
    }
}
