import UIKit

/// Stacks multiple `NavigationBarContentView`s vertically inside the nav bar's
/// expansion area. Use to compose search bars, filter chips, and other content
/// into a single `.expansion` content view.
///
/// ```swift
/// let stacked = CrystalStackedBarContent(views: [searchBar, filterBar])
/// controller.navigationBarContent = stacked
/// ```
public final class CrystalStackedBarContent: NavigationBarContentView {

    private var contentViews: [NavigationBarContentView]

    public init(views: [NavigationBarContentView]) {
        self.contentViews = views
        super.init(frame: .zero)
        for v in views {
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override public var mode: NavigationBarContentMode { .expansion }

    override public var nominalHeight: CGFloat {
        contentViews.reduce(0) { $0 + $1.nominalHeight }
    }

    override public var height: CGFloat { nominalHeight }

    override public func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGSize {
        var y: CGFloat = 0
        for v in contentViews {
            let h = v.nominalHeight
            let frame = CGRect(x: 0, y: y, width: size.width, height: h)
            transition.updateFrame(view: v, frame: frame)
            let _ = v.updateLayout(size: frame.size, leftInset: leftInset, rightInset: rightInset, transition: transition)
            y += h
        }
        return CGSize(width: size.width, height: y)
    }
}
