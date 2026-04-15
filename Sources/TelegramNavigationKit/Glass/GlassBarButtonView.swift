import UIKit

/// Glass-styled bar button with multiple display states.
/// Replaces Telegram's GlassBarButtonComponent.
public final class GlassBarButtonView: UIControl {
    // MARK: - Types

    public enum DisplayState {
        case generic
        case glass
        case tintedGlass
    }

    // MARK: - Subviews

    private let glassBackground: GlassBackgroundView
    private let contentContainer: UIView
    private var iconView: UIImageView?
    private var titleLabel: UILabel?

    // MARK: - Properties

    private var displayState: DisplayState = .glass
    public var action: ((UIView) -> Void)?
    public var contentTintColor: UIColor = .white {
        didSet {
            iconView?.tintColor = contentTintColor
            iconView?.setMonochromaticEffect(tintColor: contentTintColor)
            titleLabel?.textColor = contentTintColor
        }
    }

    /// Matches Telegram's GlassBarButtonComponent highlight: spring-scale instead of a
    /// linear alpha fade so buttons feel like they pop off the glass surface.
    override public var isHighlighted: Bool {
        didSet {
            guard displayState != .glass, displayState != .tintedGlass else {
                // Native UIGlassEffect provides its own interactive feedback via
                // `UIGlassEffect.isInteractive`; avoid doubling up the animation.
                return
            }
            let duration = isHighlighted ? 0.1 : 0.25
            UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0.0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
                self.alpha = self.isHighlighted ? 0.7 : 1.0
            })
        }
    }

    // MARK: - Init

    public init(icon: UIImage? = nil, title: String? = nil, state: DisplayState = .glass) {
        self.displayState = state
        self.glassBackground = GlassBackgroundView(style: state == .tintedGlass ? .prominent : .regular)
        self.contentContainer = UIView()

        super.init(frame: .zero)

        glassBackground.isUserInteractionEnabled = false
        addSubview(glassBackground)

        contentContainer.isUserInteractionEnabled = false
        addSubview(contentContainer)

        if let icon = icon {
            let imageView = UIImageView(image: icon.withRenderingMode(.alwaysTemplate))
            imageView.contentMode = .center
            imageView.tintColor = contentTintColor
            imageView.setMonochromaticEffect(tintColor: contentTintColor)
            contentContainer.addSubview(imageView)
            self.iconView = imageView
        }

        if let title = title {
            let label = UILabel()
            label.text = title
            label.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            label.textColor = contentTintColor
            label.textAlignment = .center
            contentContainer.addSubview(label)
            self.titleLabel = label
        }

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override public func layoutSubviews() {
        super.layoutSubviews()

        glassBackground.frame = bounds
        glassBackground.update(size: bounds.size, cornerRadius: bounds.height / 2.0, transition: .immediate)
        contentContainer.frame = bounds

        if let iconView = iconView, titleLabel == nil {
            iconView.frame = bounds
        } else if let titleLabel = titleLabel, iconView == nil {
            titleLabel.frame = bounds
        } else if let iconView = iconView, let titleLabel = titleLabel {
            let iconSize: CGFloat = 20
            let spacing: CGFloat = 4
            let totalWidth = iconSize + spacing + titleLabel.sizeThatFits(bounds.size).width
            let startX = (bounds.width - totalWidth) / 2
            iconView.frame = CGRect(x: startX, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize)
            titleLabel.frame = CGRect(x: startX + iconSize + spacing, y: 0, width: totalWidth - iconSize - spacing, height: bounds.height)
        }
    }

    override public var intrinsicContentSize: CGSize {
        if let titleLabel = titleLabel {
            let textSize = titleLabel.sizeThatFits(CGSize(width: 200, height: 44))
            let iconWidth: CGFloat = iconView != nil ? 24 : 0
            return CGSize(width: textSize.width + iconWidth + 24, height: 36)
        }
        return CGSize(width: 36, height: 36)
    }

    // MARK: - State

    public func updateState(_ state: DisplayState) {
        self.displayState = state
        switch state {
        case .generic:
            glassBackground.alpha = 0
        case .glass:
            glassBackground.alpha = 1
            glassBackground.updateStyle(.regular)
        case .tintedGlass:
            glassBackground.alpha = 1
            glassBackground.updateStyle(.prominent)
        }
    }

    @objc private func tapped() {
        action?(self)
    }
}
