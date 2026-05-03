import UIKit

// MARK: - Configuration

/// Drop-in analogue of `UIContentUnavailableConfiguration`.
///
/// Build a configuration via `.empty()`, `.loading()`, or `.error()` and
/// override individual fields:
///
///     var config = AetherContentUnavailableConfiguration.empty()
///     config.image = UIImage(systemName: "tray")
///     config.text = "Здесь пока пусто"
///     config.secondaryText = "Добавьте первую запись"
///     config.button.title = "Добавить"
///     config.button.primaryAction = { [weak self] in self?.add() }
///     stateView.configuration = config
///
/// Setting `configuration` to `nil` hides the view and lets touches pass
/// through to underlying content.
public struct AetherContentUnavailableConfiguration {
    public var image: UIImage?
    public var imageProperties: ImageProperties
    public var text: String?
    public var textProperties: TextProperties
    public var secondaryText: String?
    public var secondaryTextProperties: TextProperties
    public var button: ButtonProperties
    public var loadingIndicator: LoadingIndicatorProperties?
    public var background: BackgroundProperties
    public var directionalLayoutMargins: NSDirectionalEdgeInsets
    public var imageToTextPadding: CGFloat
    public var textToSecondaryTextPadding: CGFloat
    public var textToButtonPadding: CGFloat

    public init(
        image: UIImage? = nil,
        imageProperties: ImageProperties = .init(),
        text: String? = nil,
        textProperties: TextProperties = .title,
        secondaryText: String? = nil,
        secondaryTextProperties: TextProperties = .secondary,
        button: ButtonProperties = .init(),
        loadingIndicator: LoadingIndicatorProperties? = nil,
        background: BackgroundProperties = .init(),
        directionalLayoutMargins: NSDirectionalEdgeInsets = .init(top: 24, leading: 32, bottom: 24, trailing: 32),
        imageToTextPadding: CGFloat = 14,
        textToSecondaryTextPadding: CGFloat = 6,
        textToButtonPadding: CGFloat = 20
    ) {
        self.image = image
        self.imageProperties = imageProperties
        self.text = text
        self.textProperties = textProperties
        self.secondaryText = secondaryText
        self.secondaryTextProperties = secondaryTextProperties
        self.button = button
        self.loadingIndicator = loadingIndicator
        self.background = background
        self.directionalLayoutMargins = directionalLayoutMargins
        self.imageToTextPadding = imageToTextPadding
        self.textToSecondaryTextPadding = textToSecondaryTextPadding
        self.textToButtonPadding = textToButtonPadding
    }

    // MARK: Factories

    /// Blank empty-state preset. Caller fills in image/text/button.
    public static func empty() -> Self {
        Self()
    }

    /// Loading-state preset with a centered activity indicator.
    /// Set `secondaryText` to add a caption beneath the spinner.
    public static func loading() -> Self {
        var config = Self()
        config.loadingIndicator = LoadingIndicatorProperties()
        return config
    }

    /// Error-state preset. Caller fills in text/secondaryText/button.
    public static func error() -> Self {
        Self()
    }

    // MARK: Image

    public struct ImageProperties {
        public var tintColor: UIColor?
        public var preferredSymbolConfiguration: UIImage.SymbolConfiguration?
        /// Maximum rendered size. Use `.zero` for unbounded (intrinsic) size.
        public var maximumSize: CGSize

        public init(
            tintColor: UIColor? = UIColor(white: 0.5, alpha: 1.0),
            preferredSymbolConfiguration: UIImage.SymbolConfiguration? = nil,
            maximumSize: CGSize = CGSize(width: 56, height: 56)
        ) {
            self.tintColor = tintColor
            self.preferredSymbolConfiguration = preferredSymbolConfiguration
            self.maximumSize = maximumSize
        }
    }

    // MARK: Text

    public struct TextProperties {
        public var font: UIFont
        public var color: UIColor
        public var alignment: NSTextAlignment
        public var numberOfLines: Int

        public init(
            font: UIFont = .systemFont(ofSize: 17, weight: .semibold),
            color: UIColor = UIColor(white: 0.15, alpha: 1.0),
            alignment: NSTextAlignment = .center,
            numberOfLines: Int = 0
        ) {
            self.font = font
            self.color = color
            self.alignment = alignment
            self.numberOfLines = numberOfLines
        }

        public static let title = TextProperties()

        public static let secondary = TextProperties(
            font: .systemFont(ofSize: 14),
            color: UIColor(white: 0.4, alpha: 1.0)
        )
    }

    // MARK: Button

    public struct ButtonProperties {
        public var title: String?
        public var image: UIImage?
        public var titleFont: UIFont
        public var tintColor: UIColor
        public var contentInsets: NSDirectionalEdgeInsets
        public var primaryAction: (() -> Void)?

        public init(
            title: String? = nil,
            image: UIImage? = nil,
            titleFont: UIFont = .systemFont(ofSize: 15, weight: .medium),
            tintColor: UIColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
            contentInsets: NSDirectionalEdgeInsets = .init(top: 8, leading: 16, bottom: 8, trailing: 16),
            primaryAction: (() -> Void)? = nil
        ) {
            self.title = title
            self.image = image
            self.titleFont = titleFont
            self.tintColor = tintColor
            self.contentInsets = contentInsets
            self.primaryAction = primaryAction
        }
    }

    // MARK: Loading indicator

    public struct LoadingIndicatorProperties {
        public var color: UIColor?
        public var style: UIActivityIndicatorView.Style

        public init(
            color: UIColor? = UIColor(white: 0.5, alpha: 1.0),
            style: UIActivityIndicatorView.Style = .large
        ) {
            self.color = color
            self.style = style
        }
    }

    // MARK: Background

    public struct BackgroundProperties {
        public var backgroundColor: UIColor?

        public init(backgroundColor: UIColor? = .clear) {
            self.backgroundColor = backgroundColor
        }
    }
}

// MARK: - View

/// View that renders a `AetherContentUnavailableConfiguration`.
/// Set `configuration = nil` to hide and let touches pass through.
public final class AetherContentUnavailableView: UIView {
    public var configuration: AetherContentUnavailableConfiguration? {
        didSet { applyConfiguration(animated: false) }
    }

    /// Cross-fade duration for `setConfiguration(_:animated:)`. Defaults to 0.18s.
    public var transitionDuration: TimeInterval = 0.18

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let secondaryLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let actionButton = UIButton(type: .system)

    public init(configuration: AetherContentUnavailableConfiguration? = nil) {
        self.configuration = configuration
        super.init(frame: .zero)

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false

        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        secondaryLabel.numberOfLines = 0
        secondaryLabel.textAlignment = .center

        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        addSubview(imageView)
        addSubview(activityIndicator)
        addSubview(titleLabel)
        addSubview(secondaryLabel)
        addSubview(actionButton)

        applyConfiguration(animated: false)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setConfiguration(_ configuration: AetherContentUnavailableConfiguration?, animated: Bool) {
        if animated {
            UIView.transition(with: self, duration: transitionDuration, options: [.transitionCrossDissolve, .beginFromCurrentState], animations: {
                self.configuration = configuration
            })
        } else {
            self.configuration = configuration
        }
    }

    private func applyConfiguration(animated: Bool) {
        guard let config = configuration else {
            isHidden = true
            activityIndicator.stopAnimating()
            return
        }

        isHidden = false
        backgroundColor = config.background.backgroundColor

        if let image = config.image {
            imageView.isHidden = false
            imageView.image = image.withRenderingMode(.alwaysTemplate)
            imageView.tintColor = config.imageProperties.tintColor
            imageView.preferredSymbolConfiguration = config.imageProperties.preferredSymbolConfiguration
        } else {
            imageView.isHidden = true
            imageView.image = nil
        }

        if let text = config.text, !text.isEmpty {
            titleLabel.isHidden = false
            titleLabel.text = text
            titleLabel.font = config.textProperties.font
            titleLabel.textColor = config.textProperties.color
            titleLabel.textAlignment = config.textProperties.alignment
            titleLabel.numberOfLines = config.textProperties.numberOfLines
        } else {
            titleLabel.isHidden = true
            titleLabel.text = nil
        }

        if let secondary = config.secondaryText, !secondary.isEmpty {
            secondaryLabel.isHidden = false
            secondaryLabel.text = secondary
            secondaryLabel.font = config.secondaryTextProperties.font
            secondaryLabel.textColor = config.secondaryTextProperties.color
            secondaryLabel.textAlignment = config.secondaryTextProperties.alignment
            secondaryLabel.numberOfLines = config.secondaryTextProperties.numberOfLines
        } else {
            secondaryLabel.isHidden = true
            secondaryLabel.text = nil
        }

        if let loading = config.loadingIndicator {
            activityIndicator.isHidden = false
            activityIndicator.style = loading.style
            activityIndicator.color = loading.color
            activityIndicator.startAnimating()
        } else {
            activityIndicator.isHidden = true
            activityIndicator.stopAnimating()
        }

        let buttonTitle = config.button.title ?? ""
        let buttonImage = config.button.image
        if !buttonTitle.isEmpty || buttonImage != nil {
            actionButton.isHidden = false
            actionButton.setTitle(config.button.title, for: .normal)
            actionButton.setTitleColor(config.button.tintColor, for: .normal)
            actionButton.titleLabel?.font = config.button.titleFont
            actionButton.setImage(buttonImage, for: .normal)
            actionButton.tintColor = config.button.tintColor
            actionButton.contentEdgeInsets = UIEdgeInsets(
                top: config.button.contentInsets.top,
                left: config.button.contentInsets.leading,
                bottom: config.button.contentInsets.bottom,
                right: config.button.contentInsets.trailing
            )
        } else {
            actionButton.isHidden = true
            actionButton.setTitle(nil, for: .normal)
            actionButton.setImage(nil, for: .normal)
        }

        setNeedsLayout()
        _ = animated // animation is owned by setConfiguration(_:animated:)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        guard let config = configuration else { return }

        let margins = config.directionalLayoutMargins
        let safeBounds = bounds.inset(by: safeAreaInsets)
        let availableWidth = max(0, safeBounds.width - margins.leading - margins.trailing)

        var imageFrame = CGRect.zero
        var spinnerFrame = CGRect.zero
        var titleFrame = CGRect.zero
        var secondaryFrame = CGRect.zero
        var actionFrame = CGRect.zero

        var contentHeight: CGFloat = 0

        if !imageView.isHidden, let image = imageView.image {
            imageFrame.size = sizeForImage(image, max: config.imageProperties.maximumSize)
            contentHeight += imageFrame.height
        }
        if !activityIndicator.isHidden {
            let s = activityIndicator.intrinsicContentSize
            spinnerFrame.size = s
            if imageFrame.size != .zero { contentHeight += config.imageToTextPadding }
            contentHeight += s.height
        }
        if !titleLabel.isHidden, titleLabel.text?.isEmpty == false {
            let size = titleLabel.sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
            titleFrame.size = size
            if imageFrame.size != .zero || spinnerFrame.size != .zero { contentHeight += config.imageToTextPadding }
            contentHeight += size.height
        }
        if !secondaryLabel.isHidden, secondaryLabel.text?.isEmpty == false {
            let size = secondaryLabel.sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
            secondaryFrame.size = size
            if titleFrame.size != .zero {
                contentHeight += config.textToSecondaryTextPadding
            } else if imageFrame.size != .zero || spinnerFrame.size != .zero {
                contentHeight += config.imageToTextPadding
            }
            contentHeight += size.height
        }
        if !actionButton.isHidden {
            actionButton.sizeToFit()
            var sz = actionButton.bounds.size
            sz.width = max(sz.width, 140)
            sz.height = max(sz.height, 40)
            actionFrame.size = sz
            if titleFrame.size != .zero || secondaryFrame.size != .zero {
                contentHeight += config.textToButtonPadding
            }
            contentHeight += sz.height
        }

        let availableHeight = max(0, safeBounds.height - margins.top - margins.bottom)
        let centerX = safeBounds.midX
        var y = safeBounds.minY + margins.top + max(0, floor((availableHeight - contentHeight) / 2))

        if imageFrame.size != .zero {
            imageFrame.origin = CGPoint(x: centerX - imageFrame.width / 2, y: y)
            y += imageFrame.height
        }
        if spinnerFrame.size != .zero {
            if imageFrame.size != .zero { y += config.imageToTextPadding }
            spinnerFrame.origin = CGPoint(x: centerX - spinnerFrame.width / 2, y: y)
            y += spinnerFrame.height
        }
        if titleFrame.size != .zero {
            if imageFrame.size != .zero || spinnerFrame.size != .zero { y += config.imageToTextPadding }
            titleFrame.origin = CGPoint(x: centerX - titleFrame.width / 2, y: y)
            y += titleFrame.height
        }
        if secondaryFrame.size != .zero {
            if titleFrame.size != .zero {
                y += config.textToSecondaryTextPadding
            } else if imageFrame.size != .zero || spinnerFrame.size != .zero {
                y += config.imageToTextPadding
            }
            secondaryFrame.origin = CGPoint(x: centerX - secondaryFrame.width / 2, y: y)
            y += secondaryFrame.height
        }
        if actionFrame.size != .zero {
            if titleFrame.size != .zero || secondaryFrame.size != .zero { y += config.textToButtonPadding }
            actionFrame.origin = CGPoint(x: centerX - actionFrame.width / 2, y: y)
        }

        imageView.frame = imageFrame
        activityIndicator.frame = spinnerFrame
        titleLabel.frame = titleFrame
        secondaryLabel.frame = secondaryFrame
        actionButton.frame = actionFrame
    }

    private func sizeForImage(_ image: UIImage, max: CGSize) -> CGSize {
        var w = image.size.width
        var h = image.size.height
        if w <= 0 || h <= 0 { return max == .zero ? CGSize(width: 56, height: 56) : max }
        if max.width > 0, w > max.width {
            let s = max.width / w
            w *= s; h *= s
        }
        if max.height > 0, h > max.height {
            let s = max.height / h
            w *= s; h *= s
        }
        return CGSize(width: w, height: h)
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if configuration == nil { return nil }
        return super.hitTest(point, with: event)
    }

    @objc private func actionTapped() {
        configuration?.button.primaryAction?()
    }
}
