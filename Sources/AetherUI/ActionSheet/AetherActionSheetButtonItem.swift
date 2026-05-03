import UIKit

public enum AetherActionSheetButtonColor {
    case accent
    case destructive
    case disabled
}

public enum AetherActionSheetButtonFont {
    case `default`
    case bold
}

public final class AetherActionSheetButtonItem: AetherActionSheetItem {
    public let title: String
    public let color: AetherActionSheetButtonColor
    public let font: AetherActionSheetButtonFont
    public let enabled: Bool
    public let action: () -> Void

    public init(
        title: String,
        color: AetherActionSheetButtonColor = .accent,
        font: AetherActionSheetButtonFont = .default,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.color = color
        self.font = font
        self.enabled = enabled
        self.action = action
    }

    public func makeView(theme: AetherActionSheetTheme) -> AetherActionSheetItemView {
        let view = AetherActionSheetButtonItemView(theme: theme)
        view.setItem(self)
        return view
    }

    public func updateView(_ view: AetherActionSheetItemView) {
        guard let view = view as? AetherActionSheetButtonItemView else { return }
        view.setItem(self)
    }
}

final class AetherActionSheetButtonItemView: AetherActionSheetItemView {
    private let button = UIButton(type: .custom)
    private let label = UILabel()

    private var item: AetherActionSheetButtonItem?

    public override init(theme: AetherActionSheetTheme) {
        super.init(theme: theme)

        label.isUserInteractionEnabled = false
        label.textAlignment = .center
        label.numberOfLines = 1
        addSubview(label)

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

    func setItem(_ item: AetherActionSheetButtonItem) {
        self.item = item

        let fontSize = floor(theme.baseFontSize * 20.0 / 17.0)
        let font: UIFont
        switch item.font {
        case .default: font = .systemFont(ofSize: fontSize)
        case .bold:    font = .systemFont(ofSize: fontSize, weight: .medium)
        }

        let color: UIColor
        switch item.color {
        case .accent:      color = theme.standardActionTextColor
        case .destructive: color = theme.destructiveActionTextColor
        case .disabled:    color = theme.disabledActionTextColor
        }

        label.font = font
        label.textColor = color
        label.text = item.title

        button.isEnabled = item.enabled
        accessibilityLabel = item.title
        accessibilityTraits = item.enabled ? .button : [.button, .notEnabled]
        isAccessibilityElement = true
    }

    override func performAction() {
        item?.action()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 8, dy: 0)
    }

    @objc private func buttonDown() {
        setHighlighted(true, animated: false)
    }

    @objc private func buttonUp() {
        setHighlighted(false, animated: true)
    }

    @objc private func buttonTapped() {
        item?.action()
    }
}
