import UIKit

/// Badge view displayed on navigation bar items.
public final class NavigationBarBadgeView: UIView {
    private let backgroundView: UIView
    private let textLabel: UILabel

    public var text: String = "" {
        didSet {
            textLabel.text = text
            isHidden = text.isEmpty
            setNeedsLayout()
        }
    }

    public var badgeColor: UIColor = .systemRed {
        didSet {
            backgroundView.backgroundColor = badgeColor
        }
    }

    public var textColor: UIColor = .white {
        didSet {
            textLabel.textColor = textColor
        }
    }

    public var strokeColor: UIColor = .white {
        didSet {
            backgroundView.layer.borderColor = strokeColor.cgColor
        }
    }

    override init(frame: CGRect) {
        self.backgroundView = UIView()
        self.textLabel = UILabel()

        super.init(frame: frame)

        backgroundView.backgroundColor = badgeColor
        backgroundView.layer.borderWidth = 1.0
        backgroundView.layer.borderColor = strokeColor.cgColor
        addSubview(backgroundView)

        textLabel.font = UIFont.systemFont(ofSize: 13.0, weight: .medium)
        textLabel.textColor = textColor
        textLabel.textAlignment = .center
        addSubview(textLabel)

        isHidden = true
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        let textSize = textLabel.sizeThatFits(CGSize(width: 100, height: 20))
        let badgeWidth = max(18.0, textSize.width + 10.0)
        let badgeHeight: CGFloat = 18.0

        let badgeFrame = CGRect(x: 0, y: 0, width: badgeWidth, height: badgeHeight)
        backgroundView.frame = badgeFrame
        backgroundView.layer.cornerRadius = badgeHeight / 2.0
        textLabel.frame = badgeFrame
    }

    override public func sizeThatFits(_ size: CGSize) -> CGSize {
        let textSize = textLabel.sizeThatFits(CGSize(width: 100, height: 20))
        let badgeWidth = max(18.0, textSize.width + 10.0)
        return CGSize(width: badgeWidth, height: 18.0)
    }
}
