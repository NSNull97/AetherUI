import UIKit

/// Visual container for a single `AetherActionSheetItemGroup`. Stacks
/// item views vertically, clips to a continuous-corner rounded rect, and
/// toggles row separators so the last row has no hairline. Card surface
/// is painted with `UIGlassEffect` on iOS 26+ (liquid glass) and falls
/// back to a tinted `UIBlurEffect` on older systems.
final class AetherActionSheetItemGroupView: UIView {
    var theme: AetherActionSheetTheme {
        didSet {
            updateTheme()
        }
    }

    private(set) var itemViews: [AetherActionSheetItemView] = []
    private var overlayView: UIView?

    private let blurView: UIVisualEffectView

    init(theme: AetherActionSheetTheme) {
        self.theme = theme
        self.blurView = UIVisualEffectView(
            effect: SystemGlassEffect.make(isDark: theme.backgroundType == .dark)
        )
        super.init(frame: .zero)

        applyCornerRadius(14.0)
        blurView.frame = bounds
        blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blurView)
        updateTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setItems(_ items: [AetherActionSheetItem]) {
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

    func updateItem(at index: Int, with item: AetherActionSheetItem) {
        guard itemViews.indices.contains(index) else { return }
        item.updateView(itemViews[index])
        setNeedsLayout()
    }

    func setOverlayView(_ view: UIView?) {
        guard overlayView !== view else { return }
        overlayView?.removeFromSuperview()
        overlayView = view
        if let view {
            addSubview(view)
        }
        setNeedsLayout()
    }

    private func updateSeparators() {
        guard let last = itemViews.last else { return }
        for view in itemViews {
            view.hasSeparator = view !== last
        }
    }

    private func updateTheme() {
        // UIGlassEffect paints the card itself — skip the solid tint so
        // refraction/specular aren't masked out. Legacy UIBlurEffect path
        // needs the tint so rows read correctly over content behind.
        if GlassCompatibility.isLiquidDesignAvailable {
            backgroundColor = .clear
        } else {
            backgroundColor = theme.itemBackgroundColor
        }
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
        overlayView?.frame = bounds
    }
}
