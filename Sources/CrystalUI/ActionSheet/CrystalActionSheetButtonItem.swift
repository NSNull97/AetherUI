import UIKit

public enum CrystalActionSheetButtonColor {
    case accent
    case destructive
    case disabled
}

public enum CrystalActionSheetButtonFont {
    case `default`
    case bold
}

public final class CrystalActionSheetButtonItem: CrystalActionSheetItem {
    public let title: String
    public let color: CrystalActionSheetButtonColor
    public let font: CrystalActionSheetButtonFont
    public let enabled: Bool
    public let action: () -> Void

    public init(
        title: String,
        color: CrystalActionSheetButtonColor = .accent,
        font: CrystalActionSheetButtonFont = .default,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.color = color
        self.font = font
        self.enabled = enabled
        self.action = action
    }

    public func makeView(theme: CrystalActionSheetTheme) -> CrystalActionSheetItemView {
        let view = CrystalActionSheetButtonItemView(theme: theme)
        view.setItem(self)
        return view
    }

    public func updateView(_ view: CrystalActionSheetItemView) {
        guard let view = view as? CrystalActionSheetButtonItemView else { return }
        view.setItem(self)
    }
}

final class CrystalActionSheetButtonItemView: CrystalActionSheetItemView {
    private let button = UIButton(type: .custom)
    private let label = UILabel()

    private var item: CrystalActionSheetButtonItem?

    public override init(theme: CrystalActionSheetTheme) {
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

    func setItem(_ item: CrystalActionSheetButtonItem) {
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
