import UIKit

public struct CrystalToolbarAction: Equatable {
    public enum Color: Equatable {
        case accent
        case destructive
        case custom(UIColor)
    }

    public let title: String
    public let isEnabled: Bool
    public let color: Color

    public init(title: String, isEnabled: Bool = true, color: Color = .accent) {
        self.title = title
        self.isEnabled = isEnabled
        self.color = color
    }
}

public struct CrystalToolbar: Equatable {
    public let leftAction: CrystalToolbarAction?
    public let middleAction: CrystalToolbarAction?
    public let rightAction: CrystalToolbarAction?

    public init(
        leftAction: CrystalToolbarAction? = nil,
        middleAction: CrystalToolbarAction? = nil,
        rightAction: CrystalToolbarAction? = nil
    ) {
        self.leftAction = leftAction
        self.middleAction = middleAction
        self.rightAction = rightAction
    }
}

public struct CrystalToolbarTheme: Equatable {
    public let backgroundColor: UIColor
    public let separatorColor: UIColor
    public let textColor: UIColor
    public let accentColor: UIColor
    public let destructiveColor: UIColor
    public let disabledColor: UIColor
    public let font: UIFont

    public init(
        backgroundColor: UIColor,
        separatorColor: UIColor,
        textColor: UIColor,
        accentColor: UIColor,
        destructiveColor: UIColor,
        disabledColor: UIColor,
        font: UIFont = .systemFont(ofSize: 17.0)
    ) {
        self.backgroundColor = backgroundColor
        self.separatorColor = separatorColor
        self.textColor = textColor
        self.accentColor = accentColor
        self.destructiveColor = destructiveColor
        self.disabledColor = disabledColor
        self.font = font
    }

    public static let light = CrystalToolbarTheme(
        backgroundColor: UIColor.white.withAlphaComponent(0.86),
        separatorColor: UIColor(white: 0.0, alpha: 0.12),
        textColor: .black,
        accentColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
        destructiveColor: UIColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0),
        disabledColor: UIColor(white: 0.6, alpha: 1.0)
    )

    public static let dark = CrystalToolbarTheme(
        backgroundColor: UIColor(white: 0.1, alpha: 0.86),
        separatorColor: UIColor(white: 1.0, alpha: 0.12),
        textColor: .white,
        accentColor: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0),
        destructiveColor: UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1.0),
        disabledColor: UIColor(white: 0.5, alpha: 1.0)
    )
}

/// Bottom-anchored toolbar with up to three text buttons (left, middle,
/// right). Background uses a UIVisualEffectView for a system-material
/// blur so scrolling content shows through.
public final class CrystalToolbarView: UIView {
    public var theme: CrystalToolbarTheme {
        didSet { applyTheme() }
    }

    public var toolbar: CrystalToolbar {
        didSet {
            if toolbar != oldValue {
                updateButtons()
                setNeedsLayout()
            }
        }
    }

    /// Hairline at the top of the toolbar. Match `NavigationBar`'s default —
    /// visible on most backgrounds.
    public var displayTopSeparator: Bool = true {
        didSet { separatorView.isHidden = !displayTopSeparator }
    }

    public var leftTapped: () -> Void = {}
    public var middleTapped: () -> Void = {}
    public var rightTapped: () -> Void = {}

    private let blurView: UIVisualEffectView
    private let tintView = UIView()
    private let separatorView = UIView()
    private let leftButton = UIButton(type: .system)
    private let middleButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)

    public init(theme: CrystalToolbarTheme = .light, toolbar: CrystalToolbar = CrystalToolbar()) {
        self.theme = theme
        self.toolbar = toolbar
        self.blurView = UIVisualEffectView(
            effect: UIBlurEffect(style: theme.textColor == .white ? .systemMaterialDark : .systemMaterialLight)
        )
        super.init(frame: .zero)

        addSubview(blurView)
        addSubview(tintView)
        addSubview(separatorView)
        [leftButton, middleButton, rightButton].forEach { addSubview($0) }

        leftButton.addTarget(self, action: #selector(leftAction), for: .touchUpInside)
        middleButton.addTarget(self, action: #selector(middleAction), for: .touchUpInside)
        rightButton.addTarget(self, action: #selector(rightAction), for: .touchUpInside)

        applyTheme()
        updateButtons()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyTheme() {
        tintView.backgroundColor = theme.backgroundColor
        separatorView.backgroundColor = theme.separatorColor
        separatorView.isHidden = !displayTopSeparator
        updateButtons()
    }

    private func updateButtons() {
        configure(button: leftButton, action: toolbar.leftAction, alignment: .left)
        configure(button: middleButton, action: toolbar.middleAction, alignment: .center)
        configure(button: rightButton, action: toolbar.rightAction, alignment: .right)
    }

    private enum Alignment { case left, center, right }

    private func configure(button: UIButton, action: CrystalToolbarAction?, alignment: Alignment) {
        guard let action else {
            button.isHidden = true
            button.isEnabled = false
            button.setTitle(nil, for: .normal)
            return
        }
        button.isHidden = false
        button.isEnabled = action.isEnabled
        button.titleLabel?.font = theme.font
        button.setTitle(action.title, for: .normal)
        let color: UIColor
        if !action.isEnabled {
            color = theme.disabledColor
        } else {
            switch action.color {
            case .accent: color = theme.accentColor
            case .destructive: color = theme.destructiveColor
            case let .custom(c): color = c
            }
        }
        button.setTitleColor(color, for: .normal)
        button.setTitleColor(theme.disabledColor, for: .disabled)
        switch alignment {
        case .left: button.contentHorizontalAlignment = .left
        case .center: button.contentHorizontalAlignment = .center
        case .right: button.contentHorizontalAlignment = .right
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        blurView.frame = bounds
        tintView.frame = bounds
        separatorView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1.0 / UIScreen.main.scale)

        let sideInset: CGFloat = 16.0 + safeAreaInsets.left
        let rightInset: CGFloat = 16.0 + safeAreaInsets.right
        // Content area excludes the home indicator; the toolbar itself owns
        // the safe-area bottom, so only put button content in the top 44pt.
        let contentHeight: CGFloat = 44.0
        let thirdWidth = (bounds.width - sideInset - rightInset) / 3

        leftButton.frame = CGRect(x: sideInset, y: 0, width: thirdWidth, height: contentHeight)
        middleButton.frame = CGRect(x: sideInset + thirdWidth, y: 0, width: thirdWidth, height: contentHeight)
        rightButton.frame = CGRect(x: sideInset + thirdWidth * 2, y: 0, width: thirdWidth, height: contentHeight)
    }

    /// Standard content height: 44pt + bottom safe area. Call in parent's
    /// layout to size the toolbar correctly.
    public static func preferredHeight(bottomSafeInset: CGFloat) -> CGFloat {
        return 44.0 + bottomSafeInset
    }

    @objc private func leftAction() { leftTapped() }
    @objc private func middleAction() { middleTapped() }
    @objc private func rightAction() { rightTapped() }
}
