import UIKit

// MARK: - GlassButton

/// Generic glass-styled control with optional title, optional leading icon,
/// loading state and native liquid-glass interaction.
///
/// The control keeps its visible content inside `GlassBackgroundView.contentView`
/// so native `UIGlassEffect` deformation affects the surface and content as
/// one unit. Touch tracking is driven by a non-cancelling gesture recognizer:
/// this lets the inner visual-effect view keep receiving touches for native
/// glass feedback while `GlassButton` still exposes normal `UIControl` events.
public final class GlassButton: UIControl {
    private enum Constants {
        static let defaultHeight: CGFloat = 36.0
        static let iconOnlySize = CGSize(width: 36.0, height: 36.0)
        static let minIconSide: CGFloat = 20.0
        static let maxIconSide: CGFloat = 28.0
        static let fallbackIconSide: CGFloat = 22.0
        static let maxMeasuredTextWidth: CGFloat = 240.0
        static let loadingFadeDuration: TimeInterval = 0.18
    }

    // MARK: Subviews

    private let glassBackground: GlassBackgroundView
    private let contentContainer = UIView()
    private var iconView: UIImageView?
    private var titleLabel: UILabel?
    private var loadingIndicator: UIActivityIndicatorView?
    private var pressRecognizer: GlassButtonPressGestureRecognizer?
    private var elasticRecognizer: GlassHighlightGestureRecognizer?

    // MARK: Public API

    /// Back-compat closure for existing call sites. Standard `UIControl`
    /// target/action users can also subscribe to `.touchUpInside` or
    /// `.primaryActionTriggered`.
    public var action: ((GlassButton) -> Void)?

    /// Minimum content size used when the image/title do not provide one.
    public var minimumSize: CGSize = Constants.iconOnlySize {
        didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    /// Corner radius. `nil` means capsule (`bounds.height / 2`).
    public var cornerRadius: CGFloat? {
        didSet { setNeedsLayout() }
    }

    /// Horizontal padding around title/icon content.
    public var contentPadding: CGFloat = 14.0 {
        didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    public var tint: GlassBackgroundView.TintColor = .init(kind: .panel) {
        didSet { setNeedsLayout() }
    }

    public var font: UIFont? {
        get { titleLabel?.font }
        set { titleLabel?.font = newValue }
    }

    /// Spacing between icon and title when both are visible.
    public var iconTitleSpacing: CGFloat = 8.0 {
        didSet { invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    /// Tint color for icon, title and loading indicator.
    public var contentColor: UIColor = .label {
        didSet { applyContentColor() }
    }

    /// Override for the `isDark` flag passed to the glass background.
    /// `nil` follows `traitCollection.userInterfaceStyle`.
    public var isDarkAppearance: Bool? {
        didSet {
            glassBackground.isDarkOverride = isDarkAppearance
            setNeedsLayout()
        }
    }

    public var title: String? {
        didSet {
            guard title != oldValue else { return }
            updateTitleView()
        }
    }

    public var image: UIImage? {
        didSet {
            guard image !== oldValue else { return }
            updateIconView()
        }
    }

    public override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            updateInteractionState()
        }
    }

    /// Waiting/loading state. Swaps title/icon content for a centered spinner
    /// and blocks primary actions without applying the disabled alpha.
    public var isLoading: Bool = false {
        didSet {
            guard isLoading != oldValue else { return }
            updateInteractionState()
            updateLoadingState(animated: true)
        }
    }

    // MARK: Init

    public init(title: String? = nil, image: UIImage? = nil) {
        self.glassBackground = GlassBackgroundView(style: .regular)
        super.init(frame: .zero)

        updateAccessibilityState()

        glassBackground.isUserInteractionEnabled = true
        addSubview(glassBackground)

        contentContainer.isUserInteractionEnabled = false
        glassBackground.contentView.addSubview(contentContainer)

        self.title = title
        self.image = image
        updateTitleView()
        updateIconView()

        let press = GlassButtonPressGestureRecognizer(target: self, action: #selector(handlePressGesture(_:)))
        addGestureRecognizer(press)
        self.pressRecognizer = press

        if #unavailable(iOS 26.0) {
            let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
            elastic.touchEffectView = self
            elastic.highlightContainerView = glassBackground.contentView
            addGestureRecognizer(elastic)
            self.elasticRecognizer = elastic
        }

        updateInteractionState()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        let resolvedCorner = cornerRadius ?? bounds.height / 2.0
        let resolvedDark = isDarkAppearance ?? (traitCollection.userInterfaceStyle == .dark)

        glassBackground.frame = bounds
        if #available(iOS 26.0, *) {
            glassBackground.setNativeUniformCornerRadius(resolvedCorner)
        }
        glassBackground.update(
            size: bounds.size,
            cornerRadius: resolvedCorner,
            isDark: resolvedDark,
            tintColor: tint,
            isInteractive: isInteractionAvailable,
            isVisible: true,
            transition: .immediate
        )

        contentContainer.frame = bounds
        layoutContent()
        layoutLoadingIndicator()
    }

    @discardableResult
    public func update(
        cornerRadius: CGFloat,
        tintColor: GlassBackgroundView.TintColor,
        isInteractive: Bool = true,
        isVisible: Bool = true
    ) -> Self {
        self.tint = tintColor
        self.cornerRadius = cornerRadius

        let resolvedDark = isDarkAppearance ?? (traitCollection.userInterfaceStyle == .dark)
        if #available(iOS 26.0, *) {
            glassBackground.setNativeUniformCornerRadius(cornerRadius)
        }
        glassBackground.update(
            size: bounds.size,
            cornerRadius: cornerRadius,
            isDark: resolvedDark,
            tintColor: tintColor,
            isInteractive: isInteractive && isInteractionAvailable,
            isVisible: isVisible,
            transition: .immediate
        )

        return self
    }

    public override var intrinsicContentSize: CGSize {
        let hasIcon = image != nil
        let hasTitle = title?.isEmpty == false

        switch (hasIcon, hasTitle) {
        case (true, true):
            let width = Constants.fallbackIconSide + iconTitleSpacing + measuredTitleWidth + 2.0 * contentPadding
            return CGSize(width: max(minimumSize.width, ceil(width)), height: max(minimumSize.height, Constants.defaultHeight))
        case (true, false):
            return CGSize(
                width: max(minimumSize.width, Constants.iconOnlySize.width),
                height: max(minimumSize.height, Constants.iconOnlySize.height)
            )
        case (false, true):
            let width = measuredTitleWidth + 2.0 * contentPadding
            return CGSize(width: max(minimumSize.width, ceil(width)), height: max(minimumSize.height, Constants.defaultHeight))
        case (false, false):
            return minimumSize
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        applyContentColor()
        setNeedsLayout()
    }

    // MARK: Content

    private var measuredTitleWidth: CGFloat {
        titleLabel?.sizeThatFits(
            CGSize(width: Constants.maxMeasuredTextWidth, height: Constants.defaultHeight)
        ).width ?? 0.0
    }

    private var resolvedIconSide: CGFloat {
        guard let image else { return 0.0 }
        let side = max(image.size.width, image.size.height)
        guard side > 0.0 else { return Constants.fallbackIconSide }
        return max(Constants.minIconSide, min(Constants.maxIconSide, side))
    }

    private var isInteractionAvailable: Bool {
        isEnabled && !isLoading
    }

    private func updateTitleView() {
        if title?.isEmpty == false {
            let label = titleLabel ?? makeTitleLabel()
            label.text = title
            label.isHidden = false
        } else {
            titleLabel?.text = nil
            titleLabel?.isHidden = true
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func updateIconView() {
        if let image {
            let view = iconView ?? makeIconView()
            view.image = image.withRenderingMode(.alwaysTemplate)
            view.isHidden = false
        } else {
            iconView?.image = nil
            iconView?.isHidden = true
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func makeTitleLabel() -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15.0, weight: .medium)
        label.textColor = contentColor
        label.textAlignment = .center
        contentContainer.addSubview(label)
        titleLabel = label
        return label
    }

    private func makeIconView() -> UIImageView {
        let view = UIImageView()
        view.contentMode = .center
        view.tintColor = contentColor
        view.setMonochromaticEffect(tintColor: contentColor)
        contentContainer.addSubview(view)
        iconView = view
        return view
    }

    private func applyContentColor() {
        iconView?.tintColor = contentColor
        iconView?.setMonochromaticEffect(tintColor: contentColor)
        titleLabel?.textColor = contentColor
        loadingIndicator?.color = contentColor
    }

    private func layoutContent() {
        let hasIcon = image != nil
        let hasTitle = title?.isEmpty == false
        let iconSide = resolvedIconSide
        let maxTitleWidth = max(0.0, bounds.width - 2.0 * contentPadding)
        let titleSize = titleLabel?.sizeThatFits(CGSize(width: maxTitleWidth, height: bounds.height)) ?? .zero

        switch (hasIcon, hasTitle) {
        case (true, true):
            let titleWidth = min(titleSize.width, max(0.0, bounds.width - 2.0 * contentPadding - iconSide - iconTitleSpacing))
            let totalWidth = iconSide + iconTitleSpacing + titleWidth
            let startX = floor((bounds.width - totalWidth) / 2.0)
            iconView?.frame = CGRect(
                x: startX,
                y: floor((bounds.height - iconSide) / 2.0),
                width: iconSide,
                height: iconSide
            )
            titleLabel?.frame = CGRect(
                x: startX + iconSide + iconTitleSpacing,
                y: 0.0,
                width: titleWidth,
                height: bounds.height
            )

        case (true, false):
            iconView?.frame = CGRect(
                x: floor((bounds.width - iconSide) / 2.0),
                y: floor((bounds.height - iconSide) / 2.0),
                width: iconSide,
                height: iconSide
            )

        case (false, true):
            titleLabel?.frame = CGRect(
                x: contentPadding,
                y: 0.0,
                width: maxTitleWidth,
                height: bounds.height
            )

        case (false, false):
            break
        }
    }

    // MARK: Loading

    private func configureLoadingIndicatorIfNeeded() {
        guard loadingIndicator == nil else { return }
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = false
        indicator.color = contentColor
        indicator.alpha = 0.0
        glassBackground.contentView.addSubview(indicator)
        loadingIndicator = indicator
        setNeedsLayout()
    }

    private func layoutLoadingIndicator() {
        guard let indicator = loadingIndicator else { return }
        let size = indicator.intrinsicContentSize
        indicator.frame = CGRect(
            x: floor((bounds.width - size.width) / 2.0),
            y: floor((bounds.height - size.height) / 2.0),
            width: size.width,
            height: size.height
        )
    }

    private func updateLoadingState(animated: Bool) {
        if isLoading {
            configureLoadingIndicatorIfNeeded()
            loadingIndicator?.startAnimating()
        }

        let contentTargetAlpha: CGFloat = isLoading ? 0.0 : 1.0
        let indicatorTargetAlpha: CGFloat = isLoading ? 1.0 : 0.0

        let changes = {
            self.contentContainer.alpha = contentTargetAlpha
            self.loadingIndicator?.alpha = indicatorTargetAlpha
        }
        let completion = { [weak self] in
            guard let self else { return }
            if !self.isLoading {
                self.loadingIndicator?.stopAnimating()
            }
        }

        if animated {
            UIView.animate(
                withDuration: Constants.loadingFadeDuration,
                delay: 0.0,
                options: [.beginFromCurrentState, .curveEaseInOut],
                animations: changes,
                completion: { _ in completion() }
            )
        } else {
            changes()
            completion()
        }
    }

    // MARK: Interaction

    private func updateInteractionState() {
        let enabled = isInteractionAvailable
        alpha = isEnabled ? 1.0 : 0.4
        pressRecognizer?.isEnabled = enabled
        elasticRecognizer?.isEnabled = enabled
        if !enabled {
            isHighlighted = false
        }
        updateAccessibilityState()
        setNeedsLayout()
    }

    private func updateAccessibilityState() {
        var traits = accessibilityTraits
        traits.insert(.button)
        if isEnabled {
            traits.remove(.notEnabled)
        } else {
            traits.insert(.notEnabled)
        }
        accessibilityTraits = traits
    }

    @objc private func handlePressGesture(_ recognizer: GlassButtonPressGestureRecognizer) {
        guard isInteractionAvailable else { return }

        let location = recognizer.location(in: self)
        let isInside = bounds.contains(location)

        switch recognizer.state {
        case .began:
            isHighlighted = isInside
            if isInside {
                sendActions(for: .touchDown)
            }

        case .changed:
            if isInside != isHighlighted {
                sendActions(for: isInside ? .touchDragEnter : .touchDragExit)
            }
            isHighlighted = isInside
            sendActions(for: isInside ? .touchDragInside : .touchDragOutside)

        case .ended:
            isHighlighted = false
            if isInside {
                sendActions(for: .touchUpInside)
                action?(self)
                sendActions(for: .primaryActionTriggered)
            } else {
                sendActions(for: .touchUpOutside)
            }

        case .cancelled, .failed:
            isHighlighted = false
            sendActions(for: .touchCancel)

        default:
            break
        }
    }
}

private final class GlassButtonPressGestureRecognizer: UIGestureRecognizer {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        requiresExclusiveTouchType = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touches.count == 1 else {
            state = .failed
            return
        }
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .began || state == .changed else { return }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .began || state == .changed else {
            state = .failed
            return
        }
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }
}
