import UIKit

/// Visual container for a single `CrystalActionSheetItemGroup`. Stacks
/// item views vertically, clips to a continuous-corner rounded rect, and
/// toggles row separators so the last row has no hairline.
final class CrystalActionSheetItemGroupView: UIView {
    var theme: CrystalActionSheetTheme {
        didSet {
            updateTheme()
        }
    }

    private(set) var itemViews: [CrystalActionSheetItemView] = []

    init(theme: CrystalActionSheetTheme) {
        self.theme = theme
        super.init(frame: .zero)

        layer.cornerRadius = 14.0
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        backgroundColor = theme.itemBackgroundColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setItems(_ items: [CrystalActionSheetItem]) {
        // Rebuild the subview list from scratch — the controller only calls
        // this once per group lifecycle, so reuse isn't worth the bookkeeping.
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = items.map { item in
            let view = item.makeView(theme: theme)
            addSubview(view)
            return view
        }
        updateSeparators()
        setNeedsLayout()
    }

    func updateItem(at index: Int, with item: CrystalActionSheetItem) {
        guard itemViews.indices.contains(index) else { return }
        item.updateView(itemViews[index])
        setNeedsLayout()
    }

    private func updateSeparators() {
        guard let last = itemViews.last else { return }
        for view in itemViews {
            view.hasSeparator = view !== last
        }
    }

    private func updateTheme() {
        backgroundColor = theme.itemBackgroundColor
    }

    /// Layout: stack bottom-to-top with `preferredHeight(constrainedWidth:)`
    /// per row. Called by the controller after sizing each group.
    func preferredHeight(constrainedWidth: CGFloat) -> CGFloat {
        return itemViews.reduce(0) { $0 + $1.preferredHeight(constrainedWidth: constrainedWidth) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var y: CGFloat = 0
        for view in itemViews {
            let h = view.preferredHeight(constrainedWidth: bounds.width)
            view.frame = CGRect(x: 0, y: y, width: bounds.width, height: h)
            y += h
        }
    }
}
