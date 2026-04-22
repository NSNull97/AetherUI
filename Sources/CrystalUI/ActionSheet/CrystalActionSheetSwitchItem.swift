import UIKit

public final class CrystalActionSheetSwitchItem: CrystalActionSheetItem {
    public let title: String
    public let isOn: Bool
    public let action: (Bool) -> Void

    public init(title: String, isOn: Bool, action: @escaping (Bool) -> Void) {
        self.title = title
        self.isOn = isOn
        self.action = action
    }

    public func makeView(theme: CrystalActionSheetTheme) -> CrystalActionSheetItemView {
        let view = CrystalActionSheetSwitchItemView(theme: theme)
        view.setItem(self)
        return view
    }

    public func updateView(_ view: CrystalActionSheetItemView) {
        guard let view = view as? CrystalActionSheetSwitchItemView else { return }
        view.setItem(self)
    }
}

final class CrystalActionSheetSwitchItemView: CrystalActionSheetItemView {
    private let rowButton = UIButton(type: .custom)
    private let label = UILabel()
    private let switchControl = UISwitch()

    private var item: CrystalActionSheetSwitchItem?

    public override init(theme: CrystalActionSheetTheme) {
        super.init(theme: theme)

        label.isUserInteractionEnabled = false
        label.textColor = theme.primaryTextColor
        addSubview(label)

        switchControl.onTintColor = theme.controlAccentColor
        switchControl.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        addSubview(switchControl)

        rowButton.addTarget(self, action: #selector(rowTapped), for: .touchUpInside)
        addSubview(rowButton)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setItem(_ item: CrystalActionSheetSwitchItem) {
        self.item = item
        label.font = .systemFont(ofSize: floor(theme.baseFontSize * 20.0 / 17.0))
        label.text = item.title
        switchControl.setOn(item.isOn, animated: false)
        accessibilityLabel = item.title
        accessibilityTraits = item.isOn ? [.button, .selected] : .button
        isAccessibilityElement = true
        setNeedsLayout()
    }

    override func performAction() {
        let value = !switchControl.isOn
        switchControl.setOn(value, animated: true)
        item?.action(value)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        let switchSize = switchControl.bounds.size.width.isZero
            ? CGSize(width: 51.0, height: 31.0)
            : switchControl.bounds.size

        // rowButton doesn't cover the switch — it would swallow the switch's
        // own valueChanged event otherwise. Sits to the left of the switch.
        let switchFrame = CGRect(
            x: size.width - 16.0 - switchSize.width,
            y: floor((size.height - switchSize.height) / 2),
            width: switchSize.width,
            height: switchSize.height
        )
        switchControl.frame = switchFrame
        rowButton.frame = CGRect(x: 0, y: 0, width: switchFrame.minX, height: size.height)

        let labelFits = label.sizeThatFits(CGSize(width: max(1.0, size.width - 51.0 - 32.0), height: size.height))
        label.frame = CGRect(
            x: 16.0,
            y: floor((size.height - labelFits.height) / 2),
            width: labelFits.width,
            height: labelFits.height
        )
    }

    @objc private func rowTapped() {
        let value = !switchControl.isOn
        switchControl.setOn(value, animated: true)
        item?.action(value)
    }

    @objc private func switchChanged() {
        item?.action(switchControl.isOn)
    }
}
