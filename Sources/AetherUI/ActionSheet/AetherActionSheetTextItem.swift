import UIKit

public final class AetherActionSheetTextItem: AetherActionSheetItem {
    public enum Font {
        case `default`
        case large
    }

    public let title: String
    public let font: Font

    public init(title: String, font: Font = .default) {
        self.title = title
        self.font = font
    }

    public func makeView(theme: AetherActionSheetTheme) -> AetherActionSheetItemView {
        let view = AetherActionSheetTextItemView(theme: theme)
        view.setItem(self)
        return view
    }

    public func updateView(_ view: AetherActionSheetItemView) {
        guard let view = view as? AetherActionSheetTextItemView else { return }
        view.setItem(self)
    }
}

final class AetherActionSheetTextItemView: AetherActionSheetItemView {
    private let label = UILabel()

    public override init(theme: AetherActionSheetTheme) {
        super.init(theme: theme)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.textColor = theme.secondaryTextColor
        addSubview(label)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setItem(_ item: AetherActionSheetTextItem) {
        let fontSize: CGFloat
        switch item.font {
        case .default: fontSize = 13.0
        case .large:   fontSize = 15.0
        }
        label.font = .systemFont(ofSize: floor(theme.baseFontSize * fontSize / 17.0))
        label.text = item.title
        setNeedsLayout()
    }

    override func preferredHeight(constrainedWidth: CGFloat) -> CGFloat {
        let labelBox = CGSize(width: max(1.0, constrainedWidth - 20.0), height: .greatestFiniteMagnitude)
        let height = label.sizeThatFits(labelBox).height
        return max(Self.defaultItemHeight, height + 32.0)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 10.0
        label.frame = CGRect(x: inset, y: 0, width: bounds.width - inset * 2, height: bounds.height)
    }

    // Text items don't highlight.
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {}
}
