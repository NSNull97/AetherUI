import UIKit

// MARK: - ContextMenuActionItemView

/// Single row inside a context menu actions list. Pure presentation — touch
/// handling and the moving highlight pill live on the parent
/// `ContextMenuActionsView`, mirroring iOS 26 native context menus where a
/// single rounded selection rectangle slides between rows during a drag.
final class ContextMenuActionItemView: UIView {
    // MARK: - Metrics

    static let rowHeight: CGFloat = 44.0
    static let horizontalInset: CGFloat = 16.0
    static let iconSize: CGFloat = 22.0
    static let checkSize: CGFloat = 18.0
    static let checkSpacing: CGFloat = 12.0

    // MARK: - Subviews

    private let checkmarkView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let iconView = UIImageView()
    /// Trailing `chevron.right` shown when `item.submenu != nil`. Mutually
    /// exclusive with the trailing icon — submenu chevron wins (a row with
    /// a submenu doesn't carry an extra trailing icon).
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

        checkmarkView.contentMode = .scaleAspectFit
        checkmarkView.tintColor = .label
        checkmarkView.image = ContextMenuActionItemView.checkmarkImage()
        addSubview(checkmarkView)

        titleLabel.font = .systemFont(ofSize: 17.0, weight: .regular)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 12.0, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(subtitleLabel)

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .label
        addSubview(iconView)

        submenuIndicator.contentMode = .scaleAspectFit
        submenuIndicator.tintColor = .tertiaryLabel
        submenuIndicator.image = ContextMenuActionItemView.chevronImage()
        submenuIndicator.isHidden = true
        addSubview(submenuIndicator)

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
        iconView.tintColor = tint
        checkmarkView.tintColor = tint

        checkmarkView.isHidden = !item.isSelected
        if let icon = item.icon {
            iconView.image = icon.withRenderingMode(.alwaysTemplate)
            iconView.isHidden = false
        } else {
            iconView.image = nil
            iconView.isHidden = true
        }
        // Submenu chevron supersedes the trailing icon (a submenu row's icon
        // is shown leading by convention; trailing slot is reserved for the
        // chevron).
        submenuIndicator.isHidden = (item.submenu == nil)
        if item.submenu != nil { iconView.isHidden = true }

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

        // Leading checkmark column always reserved, so text aligns whether or not
        // any row in the menu is currently selected. Keeps the menu visually calm.
        let checkW = ContextMenuActionItemView.checkSize
        let checkSpacing = ContextMenuActionItemView.checkSpacing
        let leadingContentX = layoutRect.minX + checkW + checkSpacing

        checkmarkView.frame = CGRect(
            x: layoutRect.minX,
            y: (bounds.height - checkW) / 2.0,
            width: checkW,
            height: checkW
        )

        // Trailing slot: submenu chevron > trailing icon. (Mutually exclusive
        // — apply(item:) clears `iconView.isHidden = true` when a submenu is
        // present, so only one of these renders.)
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
        } else if !iconView.isHidden {
            let iconW = ContextMenuActionItemView.iconSize
            iconView.frame = CGRect(
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
            let titleH: CGFloat = 20.0
            let subH: CGFloat = 14.0
            let total = titleH + subH
            let startY = (bounds.height - total) / 2.0
            titleLabel.frame = CGRect(x: textRect.minX, y: startY, width: textRect.width, height: titleH)
            subtitleLabel.frame = CGRect(x: textRect.minX, y: startY + titleH, width: textRect.width, height: subH)
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
            let config = UIImage.SymbolConfiguration(pointSize: 13.0, weight: .semibold)
            return UIImage(systemName: "chevron.right", withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
        }
        return nil
    }
}
