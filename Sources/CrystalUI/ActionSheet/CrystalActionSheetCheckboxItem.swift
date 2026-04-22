import UIKit

public enum CrystalActionSheetCheckboxStyle {
    case `default`
    case alignRight
}

public final class CrystalActionSheetCheckboxItem: CrystalActionSheetItem {
    public let title: String
    public let label: String
    public let value: Bool
    public let style: CrystalActionSheetCheckboxStyle
    public let action: (Bool) -> Void

    public init(
        title: String,
        label: String = "",
        value: Bool,
        style: CrystalActionSheetCheckboxStyle = .default,
        action: @escaping (Bool) -> Void
    ) {
        self.title = title
        self.label = label
        self.value = value
        self.style = style
        self.action = action
    }

    public func makeView(theme: CrystalActionSheetTheme) -> CrystalActionSheetItemView {
        let view = CrystalActionSheetCheckboxItemView(theme: theme)
        view.setItem(self)
        return view
    }

    public func updateView(_ view: CrystalActionSheetItemView) {
        guard let view = view as? CrystalActionSheetCheckboxItemView else { return }
        view.setItem(self)
    }
}

final class CrystalActionSheetCheckboxItemView: CrystalActionSheetItemView {
    private let button = UIButton(type: .custom)
    private let titleLabel = UILabel()
    private let trailingLabel = UILabel()
    private let checkImageView = UIImageView()

    private var item: CrystalActionSheetCheckboxItem?

    public override init(theme: CrystalActionSheetTheme) {
        super.init(theme: theme)

        titleLabel.isUserInteractionEnabled = false
        titleLabel.textColor = theme.primaryTextColor
        trailingLabel.isUserInteractionEnabled = false
        trailingLabel.textColor = theme.secondaryTextColor
        trailingLabel.textAlignment = .right
        checkImageView.isUserInteractionEnabled = false
        checkImageView.image = Self.makeCheckImage(color: theme.controlAccentColor)

        addSubview(titleLabel)
        addSubview(trailingLabel)
        addSubview(checkImageView)

        button.frame = bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        button.addTarget(self, action: #selector(buttonDown), for: .touchDown)
        button.addTarget(self, action: #selector(buttonUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        addSubview(button)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setItem(_ item: CrystalActionSheetCheckboxItem) {
        self.item = item

        let font = UIFont.systemFont(ofSize: floor(theme.baseFontSize * 20.0 / 17.0))
        titleLabel.font = font
        trailingLabel.font = font
        titleLabel.text = item.title
        trailingLabel.text = item.label
        checkImageView.isHidden = !item.value

        accessibilityLabel = item.title
        accessibilityTraits = item.value ? [.button, .selected] : .button
        isAccessibilityElement = true
        setNeedsLayout()
    }

    override func performAction() {
        guard let item else { return }
        item.action(!item.value)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        let size = bounds.size
        let titleOriginX: CGFloat
        let checkOriginX: CGFloat
        if item?.style == .alignRight {
            titleOriginX = 24.0
            checkOriginX = size.width - 22.0
        } else {
            titleOriginX = 50.0
            checkOriginX = 27.0
        }

        let trailingFits = trailingLabel.sizeThatFits(CGSize(width: size.width - 44.0 - 15.0 - 8.0, height: size.height))
        let titleFits = titleLabel.sizeThatFits(CGSize(width: size.width - 44.0 - trailingFits.width - 15.0 - 8.0, height: size.height))

        titleLabel.frame = CGRect(
            x: titleOriginX,
            y: floor((size.height - titleFits.height) / 2),
            width: titleFits.width,
            height: titleFits.height
        )
        trailingLabel.frame = CGRect(
            x: size.width - 15.0 - trailingFits.width,
            y: floor((size.height - trailingFits.height) / 2),
            width: trailingFits.width,
            height: trailingFits.height
        )
        if let image = checkImageView.image {
            checkImageView.frame = CGRect(
                x: floor(checkOriginX - image.size.width / 2),
                y: floor((size.height - image.size.height) / 2),
                width: image.size.width,
                height: image.size.height
            )
        }
    }

    @objc private func buttonDown() {
        setHighlighted(true, animated: false)
    }

    @objc private func buttonUp() {
        setHighlighted(false, animated: true)
    }

    @objc private func buttonTapped() {
        guard let item else { return }
        item.action(!item.value)
    }

    /// Checkmark — same geometry as Telegram-iOS ActionSheetCheckboxItem:
    /// 14×12 pt stroke path with 2pt rounded-cap line.
    private static func makeCheckImage(color: UIColor) -> UIImage? {
        let size = CGSize(width: 14.0, height: 12.0)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(2.0 - 1.0 / UIScreen.main.scale)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            cg.move(to: CGPoint(x: 13.0, y: 1.0))
            cg.addLine(to: CGPoint(x: 5.0, y: 11.0))
            cg.addLine(to: CGPoint(x: 1.0, y: 7.0))
            cg.strokePath()
        }
    }
}
