import UIKit

/// iOS 26-style alert dialog: title + message + optional text field + one
/// or more pill-shaped action buttons (primary blue CTA, grey secondary,
/// grey/red destructive). Two-button pairs lay out side-by-side; 3+
/// actions stack vertically.
open class AetherAlertController: UIViewController {
    public var theme: AetherAlertTheme {
        didSet { rootView?.applyTheme(theme) }
    }

    public let alertTitle: String?
    public let alertMessage: String?
    public let actions: [AetherAlertAction]
    public let textFieldConfigs: [AetherAlertTextField]

    /// Tap outside the card dismisses. Default `true` — matches the
    /// AetherUI interactive-dim expectation (UIKit's UIAlertController
    /// is `false`, but that's because UIKit forces the user to answer
    /// the alert; our alerts are more toast-like).
    public var dismissOnOutsideTap: Bool = true

    public var dismissed: ((Bool) -> Void)?

    /// Current text of the Nth text field, or nil if index out of range.
    /// Useful for reading input from action handlers.
    public func textFieldValue(at index: Int) -> String? {
        return rootView?.textFieldValue(at: index)
    }

    private var isDismissed: Bool = false
    private var rootView: AetherAlertRootView? {
        return isViewLoaded ? (view as? AetherAlertRootView) : nil
    }

    public init(
        title: String?,
        message: String?,
        actions: [AetherAlertAction],
        textFields: [AetherAlertTextField] = [],
        theme: AetherAlertTheme = .system
    ) {
        self.alertTitle = title
        self.alertMessage = message
        self.actions = actions
        self.textFieldConfigs = textFields
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        // No crossDissolve — the root view runs its own fade + spring in
        // animateIn(). A UIKit transition on top would render the alert
        // once (via system dissolve) and then again via our animation,
        // producing the "double appearance" flicker.
        modalTransitionStyle = .coverVertical
    }

    /// Back-compat single-text-field overload.
    public convenience init(
        title: String?,
        message: String?,
        actions: [AetherAlertAction],
        textField: AetherAlertTextField?,
        theme: AetherAlertTheme = .system
    ) {
        self.init(
            title: title,
            message: message,
            actions: actions,
            textFields: textField.map { [$0] } ?? [],
            theme: theme
        )
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        let root = AetherAlertRootView(
            theme: theme,
            title: alertTitle,
            message: alertMessage,
            actions: actions,
            textFields: textFieldConfigs
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
        if actions.contains(where: { $0.style == .primary }) {
            commands.append(UIKeyCommand(action: #selector(enterPressed), input: "\r"))
        }
        return commands
    }

    @objc private func escapePressed() {
        dismissAnimated()
    }

    @objc private func enterPressed() {
        guard let focused = actions.first(where: { $0.style == .primary && $0.enabled }) else { return }
        rootView?.triggerAction(focused)
    }
}

// MARK: - Root view

final class AetherAlertRootView: UIView {
    var actionTriggered: (AetherAlertAction) -> Void = { _ in }
    var outsideTap: () -> Void = {}

    private var theme: AetherAlertTheme
    private let title: String?
    private let message: String?
    private let actions: [AetherAlertAction]
    private let textFieldConfigs: [AetherAlertTextField]

    private let dimView = UIView()
    /// Interactive liquid-glass card on iOS 26+. `glassIsInteractive = true`
    /// opts into the native elastic deform / specular shimmer under touch.
    /// All content is hosted inside `card.contentView`.
    private let card: GlassBackgroundView
    private let tintOverlay = UIView()

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    /// One `FieldRow` per configured text field — a 52pt pill-shaped input.
    /// Optional caption label renders *above* the pill, not inside it, so
    /// the pill itself is exactly the requested 52pt.
    private struct FieldRow {
        let captionLabel: UILabel?
        let container: UIView
        let input: UITextField
    }
    private var fieldRows: [FieldRow] = []
    private var buttonViews: [AetherAlertPillButton] = []

    /// Tuning constants — match the iOS 26 system alert proportions from
    /// the design reference the caller provided.
    private static let cardWidth: CGFloat = 300.0
    private static let cardCornerRadius: CGFloat = 28.0
    private static let horizontalPadding: CGFloat = 16.0
    private static let topPadding: CGFloat = 18.0
    private static let titleToMessageSpacing: CGFloat = 4.0
    private static let messageToFieldSpacing: CGFloat = 16.0
    private static let fieldToButtonsSpacing: CGFloat = 16.0
    private static let messageToButtonsSpacing: CGFloat = 18.0
    private static let bottomPadding: CGFloat = 12.0
    private static let buttonHeight: CGFloat = 50.0
    private static let buttonSpacing: CGFloat = 8.0
    /// Per-field pill height. User-requested 52pt (was 62pt).
    private static let fieldHeight: CGFloat = 52.0
    private static let fieldSpacing: CGFloat = 8.0

    init(
        theme: AetherAlertTheme,
        title: String?,
        message: String?,
        actions: [AetherAlertAction],
        textFields: [AetherAlertTextField]
    ) {
        self.theme = theme
        self.title = title
        self.message = message
        self.actions = actions
        self.textFieldConfigs = textFields

        self.card = GlassBackgroundView(style: .regular)
        self.card.glassIsInteractive = true
        self.card.glassCornerRadius = Self.cardCornerRadius

        super.init(frame: .zero)

        // Start everything hidden so the first frame after present is
        // already invisible — animateIn() then animates into view. This
        // fixes the "double-appearance" flicker that a UIKit crossDissolve
        // + our own fade were causing together.
        dimView.alpha = 0.0
        card.alpha = 0.0
        card.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)

        dimView.backgroundColor = theme.dimColor
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimView.addGestureRecognizer(tap)
        addSubview(dimView)

        // GlassBackgroundView clips content to its rounded shape via the
        // native UIGlassEffect pipeline (iOS 26) / legacy layer mask
        // fallback — we don't need to set masksToBounds manually.
        addSubview(card)

        if GlassCompatibility.isLiquidDesignAvailable {
            // UIGlassEffect paints the card — skip solid tint so the
            // refraction / specular show through.
            tintOverlay.backgroundColor = .clear
        } else {
            tintOverlay.backgroundColor = theme.backgroundColor
        }
        card.contentView.addSubview(tintOverlay)

        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 0
        titleLabel.textColor = theme.primaryColor
        titleLabel.font = .systemFont(ofSize: floor(theme.baseFontSize), weight: .semibold)
        titleLabel.text = title
        card.contentView.addSubview(titleLabel)

        messageLabel.textAlignment = .left
        messageLabel.numberOfLines = 0
        messageLabel.textColor = theme.primaryColor
        messageLabel.font = .systemFont(ofSize: floor(theme.baseFontSize * 15.0 / 17.0))
        messageLabel.text = message
        card.contentView.addSubview(messageLabel)

        for config in textFields {
            fieldRows.append(installFieldRow(config: config))
        }

        for action in actions {
            let button = AetherAlertPillButton(action: action, theme: theme)
            button.tapped = { [weak self] a in self?.actionTriggered(a) }
            buttonViews.append(button)
            card.contentView.addSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func installFieldRow(config: AetherAlertTextField) -> FieldRow {
        var captionView: UILabel?
        if let labelText = config.label, !labelText.isEmpty {
            let label = UILabel()
            label.text = labelText
            label.font = .systemFont(ofSize: 13.0, weight: .semibold)
            label.textColor = theme.primaryColor
            card.contentView.addSubview(label)
            captionView = label
        }

        let container = UIView()
        container.backgroundColor = theme.pillFillColor
        container.applyCornerRadius(12.0)
        card.contentView.addSubview(container)

        let field = UITextField()
        field.placeholder = config.placeholder
        field.text = config.initialText
        field.isSecureTextEntry = config.isSecureTextEntry
        field.keyboardType = config.keyboardType
        field.textColor = theme.primaryColor
        field.font = .systemFont(ofSize: 17.0)
        field.borderStyle = .none
        field.addTarget(self, action: #selector(fieldEditingChanged(_:)), for: .editingChanged)
        container.addSubview(field)

        return FieldRow(captionLabel: captionView, container: container, input: field)
    }

    func textFieldValue(at index: Int) -> String? {
        guard fieldRows.indices.contains(index) else { return nil }
        return fieldRows[index].input.text
    }

    func applyTheme(_ theme: AetherAlertTheme) {
        self.theme = theme
        dimView.backgroundColor = theme.dimColor
        if GlassCompatibility.isLiquidDesignAvailable {
            tintOverlay.backgroundColor = .clear
        } else {
            tintOverlay.backgroundColor = theme.backgroundColor
        }
        titleLabel.textColor = theme.primaryColor
        messageLabel.textColor = theme.primaryColor
        for row in fieldRows {
            row.container.backgroundColor = theme.pillFillColor
            row.captionLabel?.textColor = theme.primaryColor
            row.input.textColor = theme.primaryColor
        }
        buttonViews.forEach { $0.applyTheme(theme) }
    }

    func triggerAction(_ action: AetherAlertAction) {
        actionTriggered(action)
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        dimView.frame = bounds
        let size = bounds.size

        let cardWidth = Self.cardWidth
        let innerWidth = cardWidth - Self.horizontalPadding * 2

        var y: CGFloat = Self.topPadding

        if let title, !title.isEmpty {
            let fit = titleLabel.sizeThatFits(CGSize(width: innerWidth, height: .greatestFiniteMagnitude))
            titleLabel.frame = CGRect(x: Self.horizontalPadding, y: y, width: innerWidth, height: fit.height)
            y += fit.height
        }

        if let message, !message.isEmpty {
            if title?.isEmpty == false { y += Self.titleToMessageSpacing }
            let fit = messageLabel.sizeThatFits(CGSize(width: innerWidth, height: .greatestFiniteMagnitude))
            messageLabel.frame = CGRect(x: Self.horizontalPadding, y: y + 4, width: innerWidth, height: fit.height)
            y += fit.height
        }

        if !fieldRows.isEmpty {
            y += Self.messageToFieldSpacing
            let hInset: CGFloat = 14.0
            let captionHeight: CGFloat = 18.0
            let captionGap: CGFloat = 4.0

            for (index, row) in fieldRows.enumerated() {
                // Optional caption label above the pill. Rendered at card
                // content level (not inside the pill) so the pill stays
                // exactly 52pt tall.
                if let caption = row.captionLabel {
                    caption.frame = CGRect(
                        x: Self.horizontalPadding,
                        y: y,
                        width: innerWidth,
                        height: captionHeight
                    )
                    y += captionHeight + captionGap
                }

                row.container.frame = CGRect(
                    x: Self.horizontalPadding,
                    y: y,
                    width: innerWidth,
                    height: Self.fieldHeight
                )
                row.input.frame = CGRect(
                    x: hInset,
                    y: 0,
                    width: innerWidth - hInset * 2,
                    height: Self.fieldHeight
                )

                y += Self.fieldHeight
                if index < fieldRows.count - 1 {
                    y += Self.fieldSpacing
                }
            }
            y += Self.fieldToButtonsSpacing
        } else {
            y += Self.messageToButtonsSpacing
        }

        // Buttons: 2 actions lay out side-by-side; 3+ stack vertically. Each
        // button is its own pill with an 8pt gap.
        let buttonCount = buttonViews.count
        if buttonCount == 2 {
            let halfWidth = floor((innerWidth - Self.buttonSpacing) / 2)
            buttonViews[0].frame = CGRect(x: Self.horizontalPadding, y: y, width: halfWidth, height: Self.buttonHeight)
            buttonViews[1].frame = CGRect(
                x: Self.horizontalPadding + halfWidth + Self.buttonSpacing,
                y: y,
                width: innerWidth - halfWidth - Self.buttonSpacing,
                height: Self.buttonHeight
            )
            y += Self.buttonHeight
        } else {
            for (index, button) in buttonViews.enumerated() {
                button.frame = CGRect(x: Self.horizontalPadding, y: y, width: innerWidth, height: Self.buttonHeight)
                y += Self.buttonHeight
                if index < buttonViews.count - 1 {
                    y += Self.buttonSpacing
                }
            }
        }
        y += Self.bottomPadding
        let cardHeight = y

        card.frame = CGRect(
            x: floor((size.width - cardWidth) / 2),
            y: floor((size.height - cardHeight) / 2),
            width: cardWidth,
            height: cardHeight
        )
        card.update(size: card.bounds.size, cornerRadius: Self.cardCornerRadius, transition: .immediate)
        tintOverlay.frame = card.bounds
    }

    // MARK: Animation

    func animateIn() {
        // Initial hidden state was set in init() so the very first frame
        // after attach is invisible — no flicker. Here we only play forward.
        layoutIfNeeded()
        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.dimView.alpha = 1.0
            self.card.alpha = 1.0
            self.card.transform = .identity
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.dimView.alpha = 0.0
            self.card.alpha = 0.0
        } completion: { _ in completion() }
    }

    @objc private func dimTapped() {
        outsideTap()
    }

    @objc private func fieldEditingChanged(_ sender: UITextField) {
        guard let index = fieldRows.firstIndex(where: { $0.input === sender }) else { return }
        textFieldConfigs[index].onChanged(sender.text ?? "")
    }
}

// MARK: - Pill button

final class AetherAlertPillButton: UIControl {
    var tapped: (AetherAlertAction) -> Void = { _ in }

    private let action: AetherAlertAction
    private var theme: AetherAlertTheme
    private let label = UILabel()

    init(action: AetherAlertAction, theme: AetherAlertTheme) {
        self.action = action
        self.theme = theme
        super.init(frame: .zero)

        layer.cornerCurve = .continuous
        layer.masksToBounds = true

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

    func applyTheme(_ theme: AetherAlertTheme) {
        self.theme = theme
        let size: CGFloat = floor(theme.baseFontSize)
        label.font = .systemFont(ofSize: size, weight: .semibold)

        let textColor: UIColor
        if !action.enabled {
            textColor = theme.disabledColor
        } else {
            switch action.style {
            case .primary:     textColor = theme.primaryTextColor
            case .secondary:   textColor = theme.primaryColor
            case .destructive: textColor = theme.destructiveColor
            }
        }
        label.textColor = textColor
        label.text = action.title

        backgroundColor = idleBackgroundColor()
    }

    private func idleBackgroundColor() -> UIColor {
        switch action.style {
        case .primary:      return theme.primaryFillColor
        case .secondary:    return theme.pillFillColor
        case .destructive:  return theme.pillFillColor
        }
    }

    override var isHighlighted: Bool {
        didSet {
            guard action.enabled else { return }
            if isHighlighted {
                let base = idleBackgroundColor()
                // Slight darken for primary, slight lighten for grey.
                backgroundColor = action.style == .primary
                    ? base.withAlphaComponent(0.8)
                    : theme.highlightedItemColor
            } else {
                backgroundColor = idleBackgroundColor()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Capsule — radius = half height.
        applyCornerRadius(bounds.height / 2)
        label.frame = bounds.insetBy(dx: 8, dy: 0)
    }

    @objc private func tapAction() {
        tapped(action)
    }
}
