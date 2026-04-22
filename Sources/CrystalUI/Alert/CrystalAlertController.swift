import UIKit

/// UIAlertController-style modal with title, message, and up to N buttons.
/// API-compatible port of Telegram-iOS TextAlertController minus the
/// ASDisplayKit / Signal deps. Buttons stack vertically when there are 3+;
/// two buttons lay out side-by-side horizontally like UIAlertController.
open class CrystalAlertController: UIViewController {
    public var theme: CrystalAlertTheme {
        didSet { rootView?.applyTheme(theme) }
    }

    public let alertTitle: String?
    public let alertMessage: String?
    public let actions: [CrystalAlertAction]
    /// Tap outside the alert card dismisses. Matches Telegram-iOS
    /// `contentNode.dismissOnOutsideTap`. Default `false`.
    public var dismissOnOutsideTap: Bool = false

    /// Fires once when the alert goes away. `true` if the user dismissed via
    /// outside-tap, `false` if via an action button.
    public var dismissed: ((Bool) -> Void)?

    private var isDismissed: Bool = false
    private var rootView: CrystalAlertRootView? {
        return isViewLoaded ? (view as? CrystalAlertRootView) : nil
    }

    public init(
        title: String?,
        message: String?,
        actions: [CrystalAlertAction],
        theme: CrystalAlertTheme = .light
    ) {
        self.alertTitle = title
        self.alertMessage = message
        self.actions = actions
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        let root = CrystalAlertRootView(
            theme: theme,
            title: alertTitle,
            message: alertMessage,
            actions: actions
        )
        root.actionTriggered = { [weak self] action in
            guard let self, !self.isDismissed else { return }
            self.isDismissed = true
            self.dismissed?(false)
            action.handler()
            self.dismissAnimated(fromOutside: false)
        }
        root.outsideTap = { [weak self] in
            guard let self, self.dismissOnOutsideTap, !self.isDismissed else { return }
            self.isDismissed = true
            self.dismissed?(true)
            self.dismissAnimated(fromOutside: true)
        }
        view = root
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        rootView?.animateIn()
    }

    public func dismissAnimated() {
        guard !isDismissed else { return }
        isDismissed = true
        dismissed?(false)
        dismissAnimated(fromOutside: false)
    }

    private func dismissAnimated(fromOutside: Bool) {
        rootView?.animateOut { [weak self] in
            self?.presentingViewController?.dismiss(animated: false)
        }
    }

    open override var keyCommands: [UIKeyCommand]? {
        var commands = [
            UIKeyCommand(action: #selector(escapePressed), input: UIKeyCommand.inputEscape),
            UIKeyCommand(action: #selector(escapePressed), input: "W", modifierFlags: .command)
        ]
        if actions.contains(where: { $0.style == .defaultFocused }) {
            commands.append(UIKeyCommand(action: #selector(enterPressed), input: "\r"))
        }
        return commands
    }

    @objc private func escapePressed() {
        dismissAnimated()
    }

    @objc private func enterPressed() {
        guard let focused = actions.first(where: { $0.style == .defaultFocused && $0.enabled }) else { return }
        rootView?.triggerAction(focused)
    }
}

// MARK: - Root view

final class CrystalAlertRootView: UIView {
    var actionTriggered: (CrystalAlertAction) -> Void = { _ in }
    var outsideTap: () -> Void = {}

    private var theme: CrystalAlertTheme
    private let title: String?
    private let message: String?
    private let actions: [CrystalAlertAction]

    private let dimView = UIView()
    private let card: UIView
    private let blurView: UIVisualEffectView
    private let tintOverlay = UIView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    /// Horizontal separator above the button row / first button.
    private let topSeparator = UIView()
    /// Dividers between buttons (horizontal for 2-button row, vertical for stacked).
    private var buttonSeparators: [UIView] = []
    private var buttonViews: [CrystalAlertButtonView] = []

    private static let cardWidth: CGFloat = 270.0
    private static let cardCornerRadius: CGFloat = 14.0
    private static let horizontalPadding: CGFloat = 16.0
    private static let topPadding: CGFloat = 19.0
    private static let bottomPaddingBeforeButtons: CGFloat = 16.0
    private static let buttonHeight: CGFloat = 44.0

    init(theme: CrystalAlertTheme, title: String?, message: String?, actions: [CrystalAlertAction]) {
        self.theme = theme
        self.title = title
        self.message = message
        self.actions = actions

        let effect = UIBlurEffect(style: theme.backgroundType == .light ? .systemMaterialLight : .systemMaterialDark)
        self.blurView = UIVisualEffectView(effect: effect)

        self.card = UIView()
        super.init(frame: .zero)

        dimView.backgroundColor = theme.dimColor
        dimView.alpha = 0.0
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimView.addGestureRecognizer(tap)
        addSubview(dimView)

        card.layer.cornerRadius = Self.cardCornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.masksToBounds = true
        addSubview(card)

        card.addSubview(blurView)
        tintOverlay.backgroundColor = theme.backgroundColor
        card.addSubview(tintOverlay)

        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.textColor = theme.primaryColor
        titleLabel.font = .systemFont(ofSize: floor(theme.baseFontSize * 17.0 / 17.0), weight: .semibold)
        titleLabel.text = title
        card.addSubview(titleLabel)

        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.textColor = theme.primaryColor
        messageLabel.font = .systemFont(ofSize: floor(theme.baseFontSize * 13.0 / 17.0))
        messageLabel.text = message
        card.addSubview(messageLabel)

        topSeparator.backgroundColor = theme.separatorColor
        card.addSubview(topSeparator)

        for action in actions {
            let button = CrystalAlertButtonView(action: action, theme: theme)
            button.tapped = { [weak self] a in self?.actionTriggered(a) }
            buttonViews.append(button)
            card.addSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme(_ theme: CrystalAlertTheme) {
        self.theme = theme
        dimView.backgroundColor = theme.dimColor
        tintOverlay.backgroundColor = theme.backgroundColor
        titleLabel.textColor = theme.primaryColor
        messageLabel.textColor = theme.primaryColor
        topSeparator.backgroundColor = theme.separatorColor
        buttonSeparators.forEach { $0.backgroundColor = theme.separatorColor }
        buttonViews.forEach { $0.applyTheme(theme) }
    }

    func triggerAction(_ action: CrystalAlertAction) {
        actionTriggered(action)
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        dimView.frame = bounds
        let size = bounds.size

        let cardWidth = Self.cardWidth
        let innerWidth = cardWidth - Self.horizontalPadding * 2

        var contentHeight: CGFloat = 0

        if title != nil {
            let fit = titleLabel.sizeThatFits(CGSize(width: innerWidth, height: .greatestFiniteMagnitude))
            contentHeight += Self.topPadding
            titleLabel.frame = CGRect(x: Self.horizontalPadding, y: contentHeight, width: innerWidth, height: fit.height)
            contentHeight += fit.height
        } else {
            contentHeight += Self.topPadding
        }

        if let message, !message.isEmpty {
            let fit = messageLabel.sizeThatFits(CGSize(width: innerWidth, height: .greatestFiniteMagnitude))
            let topGap: CGFloat = title == nil ? 0 : 4.0
            contentHeight += topGap
            messageLabel.frame = CGRect(x: Self.horizontalPadding, y: contentHeight, width: innerWidth, height: fit.height)
            contentHeight += fit.height
        }
        contentHeight += Self.bottomPaddingBeforeButtons

        // Buttons: side-by-side when exactly 2 short actions, otherwise stacked.
        // Remove any previously-added separators so we can rebuild cleanly.
        buttonSeparators.forEach { $0.removeFromSuperview() }
        buttonSeparators.removeAll()

        let buttonAreaY = contentHeight
        topSeparator.frame = CGRect(x: 0, y: buttonAreaY, width: cardWidth, height: 1.0 / UIScreen.main.scale)

        let buttonCount = buttonViews.count
        let cardHeight: CGFloat
        if buttonCount == 2 {
            let halfWidth = cardWidth / 2
            buttonViews[0].frame = CGRect(x: 0, y: buttonAreaY, width: halfWidth, height: Self.buttonHeight)
            buttonViews[1].frame = CGRect(x: halfWidth, y: buttonAreaY, width: cardWidth - halfWidth, height: Self.buttonHeight)
            let vSep = addFreshSeparator()
            vSep.frame = CGRect(x: halfWidth, y: buttonAreaY, width: 1.0 / UIScreen.main.scale, height: Self.buttonHeight)
            cardHeight = buttonAreaY + Self.buttonHeight
        } else {
            var y = buttonAreaY
            for (index, button) in buttonViews.enumerated() {
                button.frame = CGRect(x: 0, y: y, width: cardWidth, height: Self.buttonHeight)
                y += Self.buttonHeight
                if index < buttonViews.count - 1 {
                    let sep = addFreshSeparator()
                    sep.frame = CGRect(x: 0, y: y - 1.0 / UIScreen.main.scale, width: cardWidth, height: 1.0 / UIScreen.main.scale)
                }
            }
            cardHeight = y
        }

        card.frame = CGRect(
            x: floor((size.width - cardWidth) / 2),
            y: floor((size.height - cardHeight) / 2),
            width: cardWidth,
            height: cardHeight
        )
        blurView.frame = card.bounds
        tintOverlay.frame = card.bounds
    }

    private func addFreshSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = theme.separatorColor
        card.addSubview(view)
        buttonSeparators.append(view)
        return view
    }

    // MARK: Animation

    func animateIn() {
        layoutIfNeeded()
        card.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        card.alpha = 0.0
        dimView.alpha = 0.0
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.dimView.alpha = 1.0
                self.card.alpha = 1.0
                self.card.transform = .identity
            }
        )
    }

    func animateOut(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState],
            animations: {
                self.dimView.alpha = 0.0
                self.card.alpha = 0.0
            },
            completion: { _ in completion() }
        )
    }

    @objc private func dimTapped() {
        outsideTap()
    }
}

// MARK: - Button

final class CrystalAlertButtonView: UIControl {
    var tapped: (CrystalAlertAction) -> Void = { _ in }

    private let action: CrystalAlertAction
    private var theme: CrystalAlertTheme
    private let label = UILabel()

    init(action: CrystalAlertAction, theme: CrystalAlertTheme) {
        self.action = action
        self.theme = theme
        super.init(frame: .zero)

        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        addSubview(label)

        applyTheme(theme)
        isEnabled = action.enabled
        addTarget(self, action: #selector(tapAction), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme(_ theme: CrystalAlertTheme) {
        self.theme = theme
        let size = floor(theme.baseFontSize * 17.0 / 17.0)
        let font: UIFont
        switch action.style {
        case .default:        font = .systemFont(ofSize: size)
        case .defaultFocused: font = .systemFont(ofSize: size, weight: .semibold)
        case .destructive:    font = .systemFont(ofSize: size)
        }
        let color: UIColor
        if !action.enabled {
            color = theme.disabledColor
        } else {
            switch action.style {
            case .default, .defaultFocused: color = theme.accentColor
            case .destructive:              color = theme.destructiveColor
            }
        }
        label.font = font
        label.textColor = color
        label.text = action.title
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? theme.highlightedItemColor : .clear
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }

    @objc private func tapAction() {
        tapped(action)
    }
}
