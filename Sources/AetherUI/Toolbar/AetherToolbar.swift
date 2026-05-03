import UIKit
import SnapKit

public struct AetherToolbarAction: Equatable {
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

public struct AetherToolbar: Equatable {
    public let leftAction: AetherToolbarAction?
    public let middleAction: AetherToolbarAction?
    public let rightAction: AetherToolbarAction?

    public init(
        leftAction: AetherToolbarAction? = nil,
        middleAction: AetherToolbarAction? = nil,
        rightAction: AetherToolbarAction? = nil
    ) {
        self.leftAction = leftAction
        self.middleAction = middleAction
        self.rightAction = rightAction
    }
}

public struct AetherToolbarTheme: Equatable {
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

    public static let light = AetherToolbarTheme(
        backgroundColor: UIColor.white.withAlphaComponent(0.86),
        separatorColor: UIColor(white: 0.0, alpha: 0.12),
        textColor: .black,
        accentColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
        destructiveColor: UIColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0),
        disabledColor: UIColor(white: 0.6, alpha: 1.0)
    )

    public static let dark = AetherToolbarTheme(
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
public final class AetherToolbarView: UIView {
    private static let contentHeight: CGFloat = 44.0
    private static let horizontalInset: CGFloat = 16.0

    public var theme: AetherToolbarTheme {
        didSet { applyTheme() }
    }

    public var toolbar: AetherToolbar {
        didSet {
            if toolbar != oldValue {
                updateButtons()
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

    public init(theme: AetherToolbarTheme = .light, toolbar: AetherToolbar = AetherToolbar()) {
        self.theme = theme
        self.toolbar = toolbar
        self.blurView = UIVisualEffectView(
            effect: SystemGlassEffect.make(isDark: theme.textColor == .white)
        )
        super.init(frame: .zero)

        addSubview(blurView)
        addSubview(tintView)
        addSubview(separatorView)
        [leftButton, middleButton, rightButton].forEach { addSubview($0) }

        leftButton.addTarget(self, action: #selector(leftAction), for: .touchUpInside)
        middleButton.addTarget(self, action: #selector(middleAction), for: .touchUpInside)
        rightButton.addTarget(self, action: #selector(rightAction), for: .touchUpInside)

        setupConstraints()

        applyTheme()
        updateButtons()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupConstraints() {
        blurView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        tintView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        separatorView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(1.0 / UIScreen.main.scale)
        }

        // Three equal-width columns across the horizontal safe-area guide.
        // Height pinned to the 44pt content band; the remaining space below
        // (home indicator, extra bottom inset) is owned by the toolbar view
        // itself and left empty on purpose.
        leftButton.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.equalTo(safeAreaLayoutGuide).offset(Self.horizontalInset)
            make.height.equalTo(Self.contentHeight)
        }
        middleButton.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.equalTo(leftButton.snp.trailing)
            make.width.equalTo(leftButton)
            make.height.equalTo(Self.contentHeight)
        }
        rightButton.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.equalTo(middleButton.snp.trailing)
            make.trailing.equalTo(safeAreaLayoutGuide).offset(-Self.horizontalInset)
            make.width.equalTo(leftButton)
            make.height.equalTo(Self.contentHeight)
        }
    }

    private func applyTheme() {
        // On iOS 26+ UIGlassEffect paints the toolbar surface. Skip the
        // solid tint so the glass refraction shows through.
        if GlassCompatibility.isLiquidDesignAvailable {
            tintView.backgroundColor = .clear
        } else {
            tintView.backgroundColor = theme.backgroundColor
        }
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

    private func configure(button: UIButton, action: AetherToolbarAction?, alignment: Alignment) {
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

    /// Standard content height: 44pt + bottom safe area. Call in parent's
    /// layout to size the toolbar correctly.
    public static func preferredHeight(bottomSafeInset: CGFloat) -> CGFloat {
        return contentHeight + bottomSafeInset
    }

    @objc private func leftAction() { leftTapped() }
    @objc private func middleAction() { middleTapped() }
    @objc private func rightAction() { rightTapped() }
}
