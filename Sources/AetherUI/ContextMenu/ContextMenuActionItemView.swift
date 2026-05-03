import UIKit

// MARK: - ContextMenuActionItemView

/// Single row inside a context menu actions list. Pure presentation — touch
/// handling and the moving highlight pill live on the parent
/// `ContextMenuActionsView`.
///
/// Layout slots (left → right):
///
///   ┌───────────────────────────────────────────────────────────────┐
///   │ [LEADING]  [TITLE / TITLE+SUBTITLE]                 [TRAILING]│
///   └───────────────────────────────────────────────────────────────┘
///
///   - **Leading slot**: a single 22pt-wide column reserved when at least
///     one item in the menu would fill it (checkmark or leading icon).
///     Fills with the checkmark when `isSelected`, OR the icon when
///     `iconSide == .leading`. Mutually exclusive in render — checkmark
///     wins if both apply (selected + leading icon → checkmark shows).
///
///   - **Trailing slot**: submenu chevron > leading icon (when
///     `iconSide == .trailing`). Submenu chevron always wins (a row with
///     a submenu doesn't render a custom trailing icon).
///
///   - **Text**: title (single line) OR title + subtitle (two lines,
///     vertically centered). Row height grows automatically when subtitle
///     is non-empty (`ContextMenuActionItemView.rowHeight(for:)`).
final class ContextMenuActionItemView: UIView {
    // MARK: - Metrics

    static let rowHeight: CGFloat = 44.0
    static let rowHeightWithSubtitle: CGFloat = 56.0
    /// Internal horizontal inset of a row. The PARENT actions view applies
    /// its own 16pt `contentInset` around the row container, so the total
    /// distance from a row's icon/text to the menu's glass edge is
    /// 16 (outer content inset) + 8 (this) = 24pt. Section headers and
    /// the back row share this inset so everything text-bearing aligns
    /// on the same leading edge. Separators use a smaller inset
    /// (`ContextMenuActionsView.separatorHorizontalInset`, 4pt) so the
    /// hairline extends slightly beyond the text column — a classic
    /// "divider is wider than the content" pattern.
    static let horizontalInset: CGFloat = 8.0
    static let leadingSlotWidth: CGFloat = 18.0
    static let leadingSlotSpacing: CGFloat = 12.0
    static let trailingIconSize: CGFloat = 22.0
    static let leadingIconSize: CGFloat = 20.0

    /// Height a row of `item` should occupy. Public so the parent actions
    /// view's `heightForItem` can defer to it.
    static func rowHeight(for item: ContextMenuActionItem) -> CGFloat {
        return (item.subtitle ?? "").isEmpty ? rowHeight : rowHeightWithSubtitle
    }

    // MARK: - Subviews

    private let checkmarkView = UIImageView()
    /// Icon rendered in the LEADING slot (replaces the checkmark when item
    /// is not selected and `iconSide == .leading`).
    private let leadingIconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    /// Icon rendered in the TRAILING slot (when `iconSide == .trailing`).
    private let trailingIconView = UIImageView()
    /// Trailing `chevron.right` shown when `item.submenu != nil`. Mutually
    /// exclusive with `trailingIconView` — submenu chevron wins.
    private let submenuIndicator = UIImageView()

    // MARK: - State

    private(set) var item: ContextMenuActionItem

    // MARK: - Init

    init(item: ContextMenuActionItem) {
        self.item = item
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .button

        for view in [checkmarkView, leadingIconView, trailingIconView, submenuIndicator] {
            view.contentMode = .scaleAspectFit
            view.tintColor = .label
            addSubview(view)
        }
        checkmarkView.image = ContextMenuActionItemView.checkmarkImage()
        submenuIndicator.image = ContextMenuActionItemView.chevronImage()
        submenuIndicator.contentMode = .center
        submenuIndicator.tintColor = item.textColor == .destructive ? .systemRed : .label

        titleLabel.font = .systemFont(ofSize: 16.0, weight: .regular)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 13.0, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(subtitleLabel)

        apply(item: item)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Configuration

    func apply(item: ContextMenuActionItem) {
        self.item = item

        titleLabel.text = item.title
        subtitleLabel.text = item.subtitle
        subtitleLabel.isHidden = (item.subtitle ?? "").isEmpty

        let tint: UIColor
        switch item.textColor {
        case .primary: tint = .label
        case .destructive: tint = .systemRed
        }
        titleLabel.textColor = tint
        subtitleLabel.textColor = item.textColor == .destructive
            ? UIColor.systemRed.withAlphaComponent(0.7)
            : .secondaryLabel
        leadingIconView.tintColor = tint
        trailingIconView.tintColor = tint
        checkmarkView.tintColor = tint

        // Leading slot: checkmark > leading icon (mutually exclusive).
        let hasLeadingIcon = (item.icon != nil) && (item.iconSide == .leading)
        checkmarkView.isHidden = !item.isSelected
        leadingIconView.isHidden = !(hasLeadingIcon && !item.isSelected)
        if hasLeadingIcon, let icon = item.icon {
            leadingIconView.image = icon.withRenderingMode(.alwaysTemplate)
        } else {
            leadingIconView.image = nil
        }

        // Trailing slot: submenu chevron > trailing icon (mutually exclusive).
        let hasTrailingIcon = (item.icon != nil) && (item.iconSide == .trailing)
        submenuIndicator.isHidden = (item.submenu == nil)
        trailingIconView.isHidden = !(hasTrailingIcon && item.submenu == nil)
        if hasTrailingIcon, item.submenu == nil, let icon = item.icon {
            trailingIconView.image = icon.withRenderingMode(.alwaysTemplate)
        } else {
            trailingIconView.image = nil
        }

        alpha = item.isEnabled ? 1.0 : 0.4
        accessibilityLabel = item.title
        if item.isSelected { accessibilityTraits.insert(.selected) }

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        let insets = UIEdgeInsets(
            top: 0, left: ContextMenuActionItemView.horizontalInset,
            bottom: 0, right: ContextMenuActionItemView.horizontalInset
        )
        let layoutRect = bounds.inset(by: insets)

        let slotW = ContextMenuActionItemView.leadingSlotWidth
        let slotSpacing = ContextMenuActionItemView.leadingSlotSpacing
        let leadingContentX = layoutRect.minX + slotW + slotSpacing

        // Leading slot — checkmark and/or leading icon occupy the same rect.
        let leadingSlotRect = CGRect(
            x: layoutRect.minX,
            y: (bounds.height - slotW) / 2.0,
            width: slotW,
            height: slotW
        )
        checkmarkView.frame = leadingSlotRect
        let leadingIconW = ContextMenuActionItemView.leadingIconSize
        leadingIconView.frame = CGRect(
            x: leadingSlotRect.midX - leadingIconW / 2.0,
            y: (bounds.height - leadingIconW) / 2.0,
            width: leadingIconW,
            height: leadingIconW
        )

        // Trailing slot — submenu chevron OR trailing icon. Both occupy the
        // right edge with no overlap (apply(item:) hides one or the other).
        var trailingContentX = layoutRect.maxX
        if !submenuIndicator.isHidden {
            let chevronW: CGFloat = 12.0
            let chevronH: CGFloat = 18.0
            submenuIndicator.frame = CGRect(
                x: trailingContentX - chevronW,
                y: (bounds.height - chevronH) / 2.0,
                width: chevronW,
                height: chevronH
            )
            trailingContentX -= chevronW + 10.0
        } else if !trailingIconView.isHidden {
            let iconW = ContextMenuActionItemView.trailingIconSize
            trailingIconView.frame = CGRect(
                x: trailingContentX - iconW,
                y: (bounds.height - iconW) / 2.0,
                width: iconW,
                height: iconW
            )
            trailingContentX -= iconW + 10.0
        }

        let textRect = CGRect(
            x: leadingContentX,
            y: 0,
            width: max(0, trailingContentX - leadingContentX),
            height: bounds.height
        )

        if subtitleLabel.isHidden {
            titleLabel.frame = textRect
        } else {
            // Two-line layout: title on top, subtitle below, vertically
            // centered within the (taller) row.
            let titleH: CGFloat = 22.0
            let subH: CGFloat = 16.0
            let gap: CGFloat = 1.0
            let total = titleH + gap + subH
            let startY = (bounds.height - total) / 2.0
            titleLabel.frame = CGRect(x: textRect.minX, y: startY, width: textRect.width, height: titleH)
            subtitleLabel.frame = CGRect(x: textRect.minX, y: startY + titleH + gap, width: textRect.width, height: subH)
        }
    }

    // MARK: - Assets

    private static func checkmarkImage() -> UIImage? {
        if #available(iOS 13.0, *) {
            let config = UIImage.SymbolConfiguration(pointSize: 15.0, weight: .semibold)
            return UIImage(systemName: "checkmark", withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
        }
        return nil
    }

    private static func chevronImage() -> UIImage? {
        if #available(iOS 13.0, *) {
            let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            return UIImage(systemName: "chevron.right", withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
        }
        return nil
    }
}
