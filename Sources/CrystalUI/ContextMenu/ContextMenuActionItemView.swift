import UIKit

// MARK: - ContextMenuActionItemView

/// Single tappable row inside a context menu actions list.
///
/// Mirrors the rows Telegram draws in its `ContextActionNode` — a leading
/// checkmark slot, a title (+ optional subtitle), and a trailing icon. The
/// highlight state uses a translucent black fill that appears on touch-down.
final class ContextMenuActionItemView: UIControl {
    // MARK: - Metrics

    static let rowHeight: CGFloat = 48.0
    static let horizontalInset: CGFloat = 16.0
    static let iconSize: CGFloat = 22.0
    static let checkSize: CGFloat = 18.0
    static let checkSpacing: CGFloat = 12.0

    // MARK: - Subviews

    private let highlightView = UIView()
    private let checkmarkView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let iconView = UIImageView()

    // MARK: - State

    private(set) var item: ContextMenuActionItem
    var onTap: ((ContextMenuActionItem) -> Void)?

    // MARK: - Init

    init(item: ContextMenuActionItem) {
        self.item = item
        super.init(frame: .zero)

        isAccessibilityElement = true
        accessibilityTraits = .button

        highlightView.isUserInteractionEnabled = false
        highlightView.backgroundColor = UIColor.black.withAlphaComponent(0.08)
        highlightView.alpha = 0
        addSubview(highlightView)

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

        addTarget(self, action: #selector(handleTouchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(handleTouchUp), for: [.touchDragExit, .touchCancel, .touchUpOutside])
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)

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

        isEnabled = item.isEnabled
        alpha = item.isEnabled ? 1.0 : 0.4
        accessibilityLabel = item.title
        if item.isSelected { accessibilityTraits.insert(.selected) }

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        highlightView.frame = bounds

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

        // Trailing icon (if any) sits on the right edge.
        var trailingContentX = layoutRect.maxX
        if !iconView.isHidden {
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

    // MARK: - Touch handling

    @objc private func handleTouchDown() {
        UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.highlightView.alpha = 1.0
        }
    }

    @objc private func handleTouchUp() {
        UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.highlightView.alpha = 0.0
        }
    }

    @objc private func handleTap() {
        UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.highlightView.alpha = 0.0
        }
        onTap?(item)
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
}
