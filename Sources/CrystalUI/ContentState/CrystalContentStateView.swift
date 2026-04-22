import UIKit

public struct CrystalContentStateAction {
    public let title: String
    public let handler: () -> Void

    public init(title: String, handler: @escaping () -> Void) {
        self.title = title
        self.handler = handler
    }
}

public enum CrystalContentState {
    /// View hides itself — the underlying content is ready.
    case idle
    /// Centered spinner with optional subtitle.
    case loading(message: String? = nil)
    /// Empty-data placeholder. Icon optional; action button optional.
    case empty(icon: UIImage? = nil, title: String, message: String? = nil, action: CrystalContentStateAction? = nil)
    /// Error placeholder with retry CTA.
    case error(title: String, message: String? = nil, action: CrystalContentStateAction? = nil)
}

public struct CrystalContentStateTheme {
    public let backgroundColor: UIColor
    public let primaryTextColor: UIColor
    public let secondaryTextColor: UIColor
    public let accentColor: UIColor
    public let spinnerColor: UIColor
    public let iconTintColor: UIColor
    public let titleFont: UIFont
    public let messageFont: UIFont
    public let actionFont: UIFont

    public init(
        backgroundColor: UIColor = .clear,
        primaryTextColor: UIColor,
        secondaryTextColor: UIColor,
        accentColor: UIColor,
        spinnerColor: UIColor,
        iconTintColor: UIColor,
        titleFont: UIFont = .systemFont(ofSize: 17.0, weight: .semibold),
        messageFont: UIFont = .systemFont(ofSize: 14.0),
        actionFont: UIFont = .systemFont(ofSize: 15.0, weight: .medium)
    ) {
        self.backgroundColor = backgroundColor
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.accentColor = accentColor
        self.spinnerColor = spinnerColor
        self.iconTintColor = iconTintColor
        self.titleFont = titleFont
        self.messageFont = messageFont
        self.actionFont = actionFont
    }

    public static let light = CrystalContentStateTheme(
        primaryTextColor: UIColor(white: 0.15, alpha: 1.0),
        secondaryTextColor: UIColor(white: 0.4, alpha: 1.0),
        accentColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
        spinnerColor: UIColor(white: 0.5, alpha: 1.0),
        iconTintColor: UIColor(white: 0.5, alpha: 1.0)
    )

    public static let dark = CrystalContentStateTheme(
        primaryTextColor: .white,
        secondaryTextColor: UIColor(white: 0.7, alpha: 1.0),
        accentColor: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0),
        spinnerColor: UIColor(white: 0.7, alpha: 1.0),
        iconTintColor: UIColor(white: 0.6, alpha: 1.0)
    )
}

/// Single drop-in view for the empty / error / loading screen states.
/// Place over a content container and toggle `state = .loading(...)` etc.
/// Pass-through hit-testing when `.idle` so underlying UI stays reachable.
public final class CrystalContentStateView: UIView {
    public var theme: CrystalContentStateTheme {
        didSet { applyTheme() }
    }

    public var state: CrystalContentState = .idle {
        didSet { applyState(animated: false) }
    }

    /// Alpha-fade between states. Defaults to 0.18s.
    public var transitionDuration: TimeInterval = 0.18

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let actionButton = UIButton(type: .system)

    private static let horizontalInset: CGFloat = 32.0
    private static let iconSize: CGFloat = 56.0
    private static let iconToTitleSpacing: CGFloat = 14.0
    private static let titleToMessageSpacing: CGFloat = 6.0
    private static let messageToActionSpacing: CGFloat = 20.0
    private static let spinnerToMessageSpacing: CGFloat = 14.0

    public init(theme: CrystalContentStateTheme = .light) {
        self.theme = theme
        super.init(frame: .zero)

        backgroundColor = theme.backgroundColor

        iconView.contentMode = .scaleAspectFit
        iconView.isUserInteractionEnabled = false

        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(messageLabel)
        addSubview(activityIndicator)
        addSubview(actionButton)

        applyTheme()
        applyState(animated: false)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setState(_ state: CrystalContentState, animated: Bool) {
        self.state = state
        if animated {
            applyState(animated: true)
        }
    }

    private func applyTheme() {
        backgroundColor = theme.backgroundColor
        titleLabel.font = theme.titleFont
        titleLabel.textColor = theme.primaryTextColor
        messageLabel.font = theme.messageFont
        messageLabel.textColor = theme.secondaryTextColor
        activityIndicator.color = theme.spinnerColor
        iconView.tintColor = theme.iconTintColor
        actionButton.titleLabel?.font = theme.actionFont
        actionButton.setTitleColor(theme.accentColor, for: .normal)
    }

    private var currentAction: CrystalContentStateAction?

    private func applyState(animated: Bool) {
        let apply: () -> Void = {
            switch self.state {
            case .idle:
                self.isHidden = true
                self.activityIndicator.stopAnimating()
            case let .loading(message):
                self.isHidden = false
                self.iconView.isHidden = true
                self.iconView.image = nil
                self.titleLabel.isHidden = true
                self.activityIndicator.isHidden = false
                self.activityIndicator.startAnimating()
                self.messageLabel.isHidden = (message == nil)
                self.messageLabel.text = message
                self.actionButton.isHidden = true
                self.currentAction = nil
            case let .empty(icon, title, message, action):
                self.isHidden = false
                self.activityIndicator.stopAnimating()
                self.activityIndicator.isHidden = true
                self.iconView.image = icon?.withRenderingMode(.alwaysTemplate)
                self.iconView.isHidden = icon == nil
                self.titleLabel.isHidden = false
                self.titleLabel.text = title
                self.messageLabel.isHidden = (message == nil)
                self.messageLabel.text = message
                self.configureAction(action)
            case let .error(title, message, action):
                self.isHidden = false
                self.activityIndicator.stopAnimating()
                self.activityIndicator.isHidden = true
                self.iconView.isHidden = true
                self.iconView.image = nil
                self.titleLabel.isHidden = false
                self.titleLabel.text = title
                self.messageLabel.isHidden = (message == nil)
                self.messageLabel.text = message
                self.configureAction(action)
            }
            self.setNeedsLayout()
        }

        if animated {
            UIView.transition(with: self, duration: transitionDuration, options: [.transitionCrossDissolve, .beginFromCurrentState], animations: apply)
        } else {
            apply()
        }
    }

    private func configureAction(_ action: CrystalContentStateAction?) {
        currentAction = action
        if let action {
            actionButton.isHidden = false
            actionButton.setTitle(action.title, for: .normal)
        } else {
            actionButton.isHidden = true
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        let availableWidth = bounds.width - Self.horizontalInset * 2

        var contentHeight: CGFloat = 0
        var iconFrame = CGRect.zero
        var spinnerFrame = CGRect.zero
        var titleFrame = CGRect.zero
        var messageFrame = CGRect.zero
        var actionFrame = CGRect.zero

        if !iconView.isHidden, iconView.image != nil {
            iconFrame.size = CGSize(width: Self.iconSize, height: Self.iconSize)
            contentHeight += Self.iconSize + Self.iconToTitleSpacing
        }
        if !activityIndicator.isHidden {
            spinnerFrame.size = CGSize(width: 40, height: 40)
            contentHeight += 40 + Self.spinnerToMessageSpacing
        }
        if !titleLabel.isHidden, titleLabel.text?.isEmpty == false {
            let size = titleLabel.sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
            titleFrame.size = size
            contentHeight += size.height
        }
        if !messageLabel.isHidden, messageLabel.text?.isEmpty == false {
            let size = messageLabel.sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
            messageFrame.size = size
            contentHeight += Self.titleToMessageSpacing + size.height
        }
        if !actionButton.isHidden {
            actionButton.sizeToFit()
            actionFrame.size = actionButton.bounds.size
            actionFrame.size.width = max(actionFrame.size.width, 140)
            actionFrame.size.height = max(actionFrame.size.height, 40)
            contentHeight += Self.messageToActionSpacing + actionFrame.size.height
        }

        var y = floor((bounds.height - contentHeight) / 2)

        if iconFrame.size != .zero {
            iconFrame.origin = CGPoint(x: (bounds.width - iconFrame.width) / 2, y: y)
            y += iconFrame.height + Self.iconToTitleSpacing
        }
        if spinnerFrame.size != .zero {
            spinnerFrame.origin = CGPoint(x: (bounds.width - spinnerFrame.width) / 2, y: y)
            y += spinnerFrame.height + Self.spinnerToMessageSpacing
        }
        if titleFrame.size != .zero {
            titleFrame.origin = CGPoint(x: (bounds.width - titleFrame.width) / 2, y: y)
            y += titleFrame.height
        }
        if messageFrame.size != .zero {
            messageFrame.origin = CGPoint(x: (bounds.width - messageFrame.width) / 2, y: y + Self.titleToMessageSpacing)
            y += Self.titleToMessageSpacing + messageFrame.height
        }
        if actionFrame.size != .zero {
            actionFrame.origin = CGPoint(x: (bounds.width - actionFrame.width) / 2, y: y + Self.messageToActionSpacing)
        }

        iconView.frame = iconFrame
        activityIndicator.frame = spinnerFrame
        titleLabel.frame = titleFrame
        messageLabel.frame = messageFrame
        actionButton.frame = actionFrame
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Idle state should never eat touches — underlying content is the
        // real UI.
        if case .idle = state { return nil }
        return super.hitTest(point, with: event)
    }

    @objc private func actionTapped() {
        currentAction?.handler()
    }
}
