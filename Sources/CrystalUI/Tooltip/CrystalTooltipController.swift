import UIKit

public struct CrystalTooltipTheme: Equatable {
    public let backgroundColor: UIColor
    public let textColor: UIColor
    public let iconTintColor: UIColor?
    public let cornerRadius: CGFloat
    public let font: UIFont
    public let shadowColor: UIColor
    public let shadowOpacity: Float

    public init(
        backgroundColor: UIColor,
        textColor: UIColor,
        iconTintColor: UIColor? = nil,
        cornerRadius: CGFloat = 12.0,
        font: UIFont = .systemFont(ofSize: 14.0, weight: .medium),
        shadowColor: UIColor = .black,
        shadowOpacity: Float = 0.22
    ) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.iconTintColor = iconTintColor
        self.cornerRadius = cornerRadius
        self.font = font
        self.shadowColor = shadowColor
        self.shadowOpacity = shadowOpacity
    }

    public static let dark = CrystalTooltipTheme(
        backgroundColor: UIColor(white: 0.1, alpha: 0.92),
        textColor: .white,
        iconTintColor: .white
    )

    public static let light = CrystalTooltipTheme(
        backgroundColor: UIColor.white.withAlphaComponent(0.95),
        textColor: .black,
        iconTintColor: .black
    )
}

public enum CrystalTooltipContent: Equatable {
    case text(String)
    case attributedText(NSAttributedString)
    case iconAndText(UIImage, String)

    var plainText: String {
        switch self {
        case let .text(text), let .iconAndText(_, text): return text
        case let .attributedText(text):                  return text.string
        }
    }

    var image: UIImage? {
        if case let .iconAndText(image, _) = self { return image }
        return nil
    }
}

public enum CrystalTooltipArrowDirection {
    /// Arrow points down — tooltip sits ABOVE the source rect.
    case down
    /// Arrow points up — tooltip sits BELOW the source rect.
    case up
}

/// Transient pill pointing at a source view. Mounts into the source view's
/// window as a top-level overlay so it floats above everything including
/// modals; auto-dismisses after `timeout` seconds.
public final class CrystalTooltipController {
    public var theme: CrystalTooltipTheme
    public let content: CrystalTooltipContent
    public var timeout: TimeInterval = 2.0
    public var dismissed: (() -> Void)?

    private weak var hostView: UIView?
    private var rootView: CrystalTooltipRootView?
    private var dismissWorkItem: DispatchWorkItem?

    public init(
        content: CrystalTooltipContent,
        theme: CrystalTooltipTheme = .dark,
        timeout: TimeInterval = 2.0
    ) {
        self.content = content
        self.theme = theme
        self.timeout = timeout
    }

    /// Show pointing at the given source view. `sourceRect` defaults to the
    /// source view's bounds. Placement: prefers ABOVE the source unless
    /// there's no room, then falls back BELOW.
    public func present(from sourceView: UIView, sourceRect: CGRect? = nil) {
        // Prefer the source view's window so the tip follows that window's
        // coordinate space. If the source isn't yet attached (rare: called
        // before viewDidAppear), fall back to the app's active window.
        let window = sourceView.window ?? CrystalToastController.findActiveWindow()
        guard let window else { return }
        dismiss(animated: false)
        hostView = window

        let rect = sourceRect ?? sourceView.bounds
        let windowRect = sourceView.convert(rect, to: window)

        let root = CrystalTooltipRootView(content: content, theme: theme)
        root.onTapOutside = { [weak self] in self?.dismiss(animated: true) }
        root.onTapInside = { [weak self] in self?.dismiss(animated: true) }
        root.frame = window.bounds
        root.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(root)
        root.setNeedsLayout()
        root.layoutIfNeeded()
        root.place(pointingTo: windowRect)
        root.animateIn()
        rootView = root

        let work = DispatchWorkItem { [weak self] in
            self?.dismiss(animated: true)
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    public func dismiss(animated: Bool) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        let root = rootView
        rootView = nil

        guard let root else { dismissed?(); return }
        if animated {
            root.animateOut { [weak self] in
                root.removeFromSuperview()
                self?.dismissed?()
            }
        } else {
            root.removeFromSuperview()
            dismissed?()
        }
    }

    deinit {
        dismissWorkItem?.cancel()
        rootView?.removeFromSuperview()
    }
}

// MARK: - Root view

final class CrystalTooltipRootView: UIView {
    var onTapOutside: () -> Void = {}
    var onTapInside: () -> Void = {}

    private let content: CrystalTooltipContent
    private let theme: CrystalTooltipTheme

    private let card = UIView()
    private let arrowLayer = CAShapeLayer()
    private let textLabel = UILabel()
    private let iconView = UIImageView()

    private static let horizontalInset: CGFloat = 12.0
    private static let verticalInset: CGFloat = 8.0
    private static let iconTextSpacing: CGFloat = 8.0
    private static let arrowHeight: CGFloat = 6.0
    private static let arrowHalfWidth: CGFloat = 8.0
    private static let screenMargin: CGFloat = 8.0
    private static let gapToSource: CGFloat = 6.0

    init(content: CrystalTooltipContent, theme: CrystalTooltipTheme) {
        self.content = content
        self.theme = theme
        super.init(frame: .zero)

        isUserInteractionEnabled = true

        textLabel.font = theme.font
        textLabel.textColor = theme.textColor
        textLabel.numberOfLines = 0
        textLabel.textAlignment = .left
        switch content {
        case let .text(text): textLabel.text = text
        case let .attributedText(attr): textLabel.attributedText = attr
        case let .iconAndText(image, text):
            textLabel.text = text
            iconView.image = theme.iconTintColor != nil ? image.withRenderingMode(.alwaysTemplate) : image
            if let tint = theme.iconTintColor {
                iconView.tintColor = tint
            }
            iconView.contentMode = .scaleAspectFit
        }

        // Card painted by UIGlassEffect on iOS 26+; falls back to the
        // theme's solid background color on older systems. Shadow lives
        // on the card itself so it extends below the blur view.
        card.layer.cornerRadius = theme.cornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = theme.shadowColor.cgColor
        card.layer.shadowOpacity = theme.shadowOpacity
        card.layer.shadowRadius = 14.0
        card.layer.shadowOffset = CGSize(width: 0, height: 4)
        addSubview(card)

        let isDark = theme.backgroundColor.isDarkApprox
        if GlassCompatibility.isLiquidDesignAvailable {
            card.backgroundColor = .clear
            let blur = UIVisualEffectView(
                effect: SystemGlassEffect.make(style: .regular, isDark: isDark)
            )
            blur.layer.cornerRadius = theme.cornerRadius
            blur.layer.cornerCurve = .continuous
            blur.layer.masksToBounds = true
            blur.frame = card.bounds
            blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            card.insertSubview(blur, at: 0)
        } else {
            card.backgroundColor = theme.backgroundColor
        }
        if iconView.image != nil {
            card.addSubview(iconView)
        }
        card.addSubview(textLabel)

        arrowLayer.fillColor = theme.backgroundColor.cgColor
        layer.addSublayer(arrowLayer)

        let inside = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        card.addGestureRecognizer(inside)

        let outside = UITapGestureRecognizer(target: self, action: #selector(outsideTapped))
        outside.cancelsTouchesInView = false
        addGestureRecognizer(outside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Lay out card + arrow to point at `sourceGlobalRect`. Prefers ABOVE;
    /// flips below when there's no room above.
    func place(pointingTo sourceGlobalRect: CGRect) {
        let maxCardWidth = min(280.0, bounds.width - Self.screenMargin * 2)
        let textBox = CGSize(width: maxCardWidth - Self.horizontalInset * 2 - (iconView.image != nil ? (22.0 + Self.iconTextSpacing) : 0), height: .greatestFiniteMagnitude)
        let textFits = textLabel.sizeThatFits(textBox)

        let contentHeight = max(textFits.height, iconView.image != nil ? 22.0 : 0)
        let cardHeight = contentHeight + Self.verticalInset * 2
        let cardWidth = min(maxCardWidth, textFits.width + Self.horizontalInset * 2 + (iconView.image != nil ? (22.0 + Self.iconTextSpacing) : 0))

        let anchorX = sourceGlobalRect.midX

        var cardX = anchorX - cardWidth / 2
        cardX = max(Self.screenMargin, min(bounds.width - cardWidth - Self.screenMargin, cardX))

        let wantsAbove = sourceGlobalRect.minY - cardHeight - Self.arrowHeight - Self.gapToSource >= safeAreaInsets.top + Self.screenMargin
        let direction: CrystalTooltipArrowDirection = wantsAbove ? .down : .up

        let cardY: CGFloat
        let arrowY: CGFloat
        switch direction {
        case .down:
            cardY = sourceGlobalRect.minY - Self.gapToSource - Self.arrowHeight - cardHeight
            arrowY = cardY + cardHeight
        case .up:
            cardY = sourceGlobalRect.maxY + Self.gapToSource + Self.arrowHeight
            arrowY = cardY - Self.arrowHeight
        }

        card.frame = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)

        if iconView.image != nil {
            iconView.frame = CGRect(x: Self.horizontalInset, y: (cardHeight - 22.0) / 2, width: 22.0, height: 22.0)
            textLabel.frame = CGRect(
                x: Self.horizontalInset + 22.0 + Self.iconTextSpacing,
                y: (cardHeight - textFits.height) / 2,
                width: cardWidth - Self.horizontalInset * 2 - 22.0 - Self.iconTextSpacing,
                height: textFits.height
            )
        } else {
            textLabel.frame = CGRect(
                x: Self.horizontalInset,
                y: (cardHeight - textFits.height) / 2,
                width: cardWidth - Self.horizontalInset * 2,
                height: textFits.height
            )
        }

        // Arrow path — small triangle whose tip lines up with anchorX.
        let path = UIBezierPath()
        let tipX = max(cardX + theme.cornerRadius + Self.arrowHalfWidth,
                       min(cardX + cardWidth - theme.cornerRadius - Self.arrowHalfWidth, anchorX))
        switch direction {
        case .down:
            path.move(to: CGPoint(x: tipX - Self.arrowHalfWidth, y: arrowY))
            path.addLine(to: CGPoint(x: tipX, y: arrowY + Self.arrowHeight))
            path.addLine(to: CGPoint(x: tipX + Self.arrowHalfWidth, y: arrowY))
        case .up:
            path.move(to: CGPoint(x: tipX - Self.arrowHalfWidth, y: arrowY + Self.arrowHeight))
            path.addLine(to: CGPoint(x: tipX, y: arrowY))
            path.addLine(to: CGPoint(x: tipX + Self.arrowHalfWidth, y: arrowY + Self.arrowHeight))
        }
        path.close()
        arrowLayer.path = path.cgPath
    }

    func animateIn() {
        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        arrowLayer.opacity = 0
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.2,
            options: .curveEaseOut
        ) {
            self.card.alpha = 1
            self.card.transform = .identity
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.22
        arrowLayer.opacity = 1
        arrowLayer.add(fade, forKey: "fadeIn")
    }

    func animateOut(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.card.alpha = 0
        } completion: { _ in
            completion()
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.18
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        arrowLayer.add(fade, forKey: "fadeOut")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Tap on the card goes to the card so its own recognizer fires;
        // tap anywhere else lands on self so outsideTap runs (and dismisses).
        // Tooltip is a modal-feeling overlay while shown — underlying UI
        // taps are swallowed for the short lifetime of the tip.
        return super.hitTest(point, with: event)
    }

    @objc private func cardTapped() {
        onTapInside()
    }

    @objc private func outsideTapped() {
        onTapOutside()
    }
}
