import UIKit

// MARK: - ContextMenuActionRowCellView

/// A single cell inside a `.actionRow` — icon centred on top, single-line
/// title centred below. Pure presentation; touch tracking + the moving
/// highlight lens live on the parent `ContextMenuActionsView`, same as
/// regular action rows.
///
/// Sizing: fixed height (`cellHeight`), flexible width (cells share the
/// row's content width equally, so each cell's actual frame width
/// depends on cell count). Long titles truncate with `…` when they
/// don't fit — this is why the screenshot's "Destru..." cell shows
/// truncation instead of wrapping.
final class ContextMenuActionRowCellView: UIView {
    // MARK: - Metrics

    /// Total row height for `.actionRow`. Tuned to match the spacing
    /// iOS uses for its native inline UIMenu action bars — roomy
    /// enough that icon + label read as a unified "chip", not a
    /// cramped toolbar.
    static let cellHeight: CGFloat = 72.0
    static let iconSize: CGFloat = 24.0
    static let iconTopPadding: CGFloat = 12.0
    static let iconLabelGap: CGFloat = 4.0
    static let labelBottomPadding: CGFloat = 10.0
    static let labelFontSize: CGFloat = 13.0
    static let labelHorizontalInset: CGFloat = 4.0

    // MARK: - Subviews

    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    // MARK: - State

    let item: ContextMenuActionItem

    // MARK: - Init

    init(item: ContextMenuActionItem) {
        self.item = item
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = item.title
        if item.isSelected { accessibilityTraits.insert(.selected) }

        let tint: UIColor = item.textColor == .destructive ? .systemRed : .label

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = tint
        if let icon = item.icon {
            iconView.image = icon.withRenderingMode(.alwaysTemplate)
        }
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: Self.labelFontSize, weight: .regular)
        titleLabel.textColor = tint
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.85
        titleLabel.text = item.title
        addSubview(titleLabel)

        alpha = item.isEnabled ? 1.0 : 0.4
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        iconView.frame = CGRect(
            x: (bounds.width - Self.iconSize) / 2.0,
            y: Self.iconTopPadding,
            width: Self.iconSize,
            height: Self.iconSize
        )

        let labelY = Self.iconTopPadding + Self.iconSize + Self.iconLabelGap
        let labelHeight = max(0, bounds.height - labelY - Self.labelBottomPadding)
        titleLabel.frame = CGRect(
            x: Self.labelHorizontalInset,
            y: labelY,
            width: max(0, bounds.width - Self.labelHorizontalInset * 2),
            height: labelHeight
        )
    }
}
