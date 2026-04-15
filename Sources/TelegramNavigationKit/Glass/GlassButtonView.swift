import UIKit

/// Glass-styled circular button with blur background.
/// Pure UIKit replacement for Telegram's ASDK-based GlassButtonNode.
public final class GlassButtonView: UIControl {
    // MARK: - Subviews

    private let blurView: UIVisualEffectView
    private let iconView: UIImageView
    private let labelView: UILabel?

    private var regularImage: UIImage?
    private var highlightedImage: UIImage?
    private var filledImage: UIImage?

    // MARK: - Properties

    public var buttonSize: CGSize

    override public var isSelected: Bool {
        didSet {
            updateState()
        }
    }

    override public var isHighlighted: Bool {
        didSet {
            updateState()
        }
    }

    // MARK: - Init

    public init(icon: UIImage, label: String? = nil, size: CGSize = CGSize(width: 60, height: 60)) {
        self.buttonSize = size

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        blurView.clipsToBounds = true
        blurView.isUserInteractionEnabled = false
        self.blurView = blurView

        self.iconView = UIImageView()
        self.iconView.contentMode = .center

        if let label = label {
            let labelView = UILabel()
            labelView.font = UIFont.systemFont(ofSize: size.width < 70 ? 11.5 : 14.5)
            labelView.textColor = .white
            labelView.textAlignment = .center
            labelView.text = label
            self.labelView = labelView
        } else {
            self.labelView = nil
        }

        // Generate button images
        self.regularImage = GlassButtonView.generateButtonImage(icon: icon, fillColor: .clear, size: size)
        self.highlightedImage = GlassButtonView.generateButtonImage(icon: icon, fillColor: UIColor(white: 1.0, alpha: 0.3), size: size)
        self.filledImage = GlassButtonView.generateButtonImage(icon: icon, fillColor: UIColor(white: 1.0, alpha: 1.0), knockout: true, size: size)

        super.init(frame: CGRect(origin: .zero, size: size))

        addSubview(blurView)
        iconView.image = regularImage
        addSubview(iconView)

        if let labelView = labelView {
            addSubview(labelView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override public func layoutSubviews() {
        super.layoutSubviews()

        blurView.frame = bounds
        blurView.layer.cornerRadius = bounds.width / 2.0

        iconView.frame = bounds

        if let labelView = labelView {
            let labelSize = labelView.sizeThatFits(CGSize(width: 200, height: 100))
            let offset: CGFloat = bounds.width < 70 ? 65.0 : 81.0
            labelView.frame = CGRect(
                x: (bounds.width - labelSize.width) / 2.0,
                y: offset,
                width: labelSize.width,
                height: labelSize.height
            )
        }
    }

    override public var intrinsicContentSize: CGSize {
        return buttonSize
    }

    // MARK: - State

    private func updateState() {
        let targetImage: UIImage?
        if isSelected {
            targetImage = filledImage
        } else if isHighlighted {
            targetImage = highlightedImage
        } else {
            targetImage = regularImage
        }

        if iconView.image !== targetImage {
            let previousContents = iconView.layer.contents
            iconView.image = targetImage

            if let previousContents = previousContents, let targetImage = targetImage {
                let duration: Double = isSelected ? 0.25 : 0.15
                let animation = CABasicAnimation(keyPath: "contents")
                animation.fromValue = previousContents
                animation.toValue = targetImage.cgImage
                animation.duration = duration
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                iconView.layer.add(animation, forKey: "contents")
            }
        }
    }

    // MARK: - Image Generation

    private static func generateButtonImage(icon: UIImage, fillColor: UIColor, knockout: Bool = false, size: CGSize) -> UIImage? {
        return generateImage(size, contextGenerator: { size, context in
            context.clear(CGRect(origin: .zero, size: size))
            context.setBlendMode(.copy)
            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: CGRect(origin: .zero, size: size))

            let imageSize = icon.size
            let imageRect = CGRect(
                x: (size.width - imageSize.width) / 2.0,
                y: (size.height - imageSize.height) / 2.0,
                width: imageSize.width,
                height: imageSize.height
            )

            if knockout {
                context.setBlendMode(.copy)
                context.clip(to: imageRect, mask: icon.cgImage!)
                context.setFillColor(UIColor.clear.cgColor)
                context.fill(imageRect)
            } else {
                context.setBlendMode(.normal)
                context.draw(icon.cgImage!, in: imageRect)
            }
        })
    }
}
