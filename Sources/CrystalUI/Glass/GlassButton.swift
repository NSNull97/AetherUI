import UIKit

// MARK: - GlassButton

/// Generic glass-styled tap target — a rounded-rect view with an optional
/// title, optional leading icon, and a glass background. Designed to be
/// dropped anywhere (card bottoms, toolbars, free-standing actions), not
/// tied to nav bar sizing like `GlassBarButtonView`.
///
/// **Press feedback**
/// Deliberately NOT a `UIControl` and NOT animated manually. Touches flow
/// straight into the `GlassBackgroundView` subview (its
/// `isUserInteractionEnabled` stays `true`), which lets iOS 26's native
/// `UIGlassEffect.isInteractive` observer run the liquid-warp deformation
/// exactly like a standalone `GlassBackgroundView` would. A layered
/// UIControl + manual scale/alpha spring approach was tried and consistently
/// interfered with the native warp — either the UIControl swallowed the
/// touch before UIGlassEffect could observe it, or our `self.transform`
/// scale fought the warp's coordinate math. Letting the glass own the
/// touch gives the real "стеклянная" feel with zero custom code.
///
/// Tap dispatch goes through a plain `UITapGestureRecognizer` on the
/// button; `action` fires on a completed tap. No highlight state to track.
///
/// **Sizing contract**
///   - Only `image` → square-ish sized by `intrinsicContentSize` (36×36
///     default, configurable via `minimumSize` / explicit frame).
///   - Only `title` → pill-sized with horizontal padding around the label.
///   - Both → icon leading + label trailing inside the pill.
///
/// **Glass**
///   - Uses `GlassBackgroundView(style: .regular)` internally.
///   - `isDark` auto-derives from the view's trait collection (overrideable
///     via `isDarkAppearance` property if the surface sits on a custom dark
///     background while the system is in light mode).
///   - Corner radius defaults to `bounds.height / 2` (pill) — override via
///     `cornerRadius` if a specific rect shape is needed.
public final class GlassButton: UIView {
    // MARK: - Subviews

    private let glassBackground: GlassBackgroundView
    private let contentContainer = UIView()
    private var iconView: UIImageView?
    private var titleLabel: UILabel?
    private var loadingIndicator: UIActivityIndicatorView?
    private var tapRecognizer: UITapGestureRecognizer?
    private var elasticRecognizer: GlassHighlightGestureRecognizer?

    // MARK: - Properties

    /// Tap handler. Fires on a completed tap (finger down + up within the
    /// button's bounds, short duration). `sender` is the button itself.
    public var action: ((GlassButton) -> Void)?

    /// Minimum content size used when the image/title don't provide their own.
    public var minimumSize: CGSize = CGSize(width: 36, height: 36)

    /// Corner radius. `nil` (default) → pill (bounds.height / 2).
    public var cornerRadius: CGFloat? {
        didSet { setNeedsLayout() }
    }

    /// Horizontal padding around the content (icon + label).
    public var contentPadding: CGFloat = 14 {
        didSet { setNeedsLayout(); invalidateIntrinsicContentSize() }
    }
    
    public var tint: GlassBackgroundView.TintColor = .init(kind: .panel) {
        didSet { setNeedsLayout(); invalidateIntrinsicContentSize() }
    }

    /// Spacing between icon and title when both are shown.
    public var iconTitleSpacing: CGFloat = 8 {
        didSet { setNeedsLayout() }
    }

    /// Tint color for icon + title. Defaults to `.label` so it adapts to
    /// light / dark automatically.
    public var contentColor: UIColor = .label {
        didSet {
            iconView?.tintColor = contentColor
            iconView?.setMonochromaticEffect(tintColor: contentColor)
            titleLabel?.textColor = contentColor
            loadingIndicator?.color = contentColor
        }
    }

    /// Override for the `isDark` flag passed to the glass background.
    /// `nil` (default) → derived from `traitCollection.userInterfaceStyle`.
    /// Forwarded to `GlassBackgroundView.isDarkOverride` so the glass also
    /// picks up the override on its own auto-layout / trait-change paths.
    public var isDarkAppearance: Bool? {
        didSet {
            glassBackground.isDarkOverride = isDarkAppearance
            setNeedsLayout()
        }
    }

    public var title: String? {
        didSet {
            if title == oldValue { return }
            configureTitleIfNeeded()
            titleLabel?.text = title
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    public var image: UIImage? {
        didSet {
            configureIconIfNeeded()
            iconView?.image = image?.withRenderingMode(.alwaysTemplate)
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    /// Whether the button accepts taps. Disabled buttons dim to 0.4 and
    /// don't fire `action`. Mirrors the old UIControl-era property name
    /// for familiarity but is just a UIView with interaction gated.
    public var isEnabled: Bool = true {
        didSet {
            if isEnabled == oldValue { return }
            alpha = isEnabled ? 1.0 : 0.4
            tapRecognizer?.isEnabled = isEnabled && !isLoading
            elasticRecognizer?.isEnabled = isEnabled && !isLoading
        }
    }

    /// Waiting/loading state. Swaps the icon+title for a centered spinner,
    /// blocks taps, and keeps the glass pill at full opacity (this is a
    /// "working on it" affordance, not a disabled look — use `isEnabled`
    /// for that). Transition is a short crossfade.
    public var isLoading: Bool = false {
        didSet {
            if isLoading == oldValue { return }
            tapRecognizer?.isEnabled = isEnabled && !isLoading
            elasticRecognizer?.isEnabled = isEnabled && !isLoading
            updateLoadingState(animated: true)
        }
    }

    // MARK: - Init

    public init(title: String? = nil, image: UIImage? = nil) {
        self.glassBackground = GlassBackgroundView(style: .regular)
        super.init(frame: .zero)

        // Glass stays fully interactive — this is the whole point of the
        // UIView (not UIControl) design. Touches reach the
        // UIVisualEffectView under the glass, UIGlassEffect's
        // `isInteractive` observer picks up finger position, and the
        // native liquid warp runs with zero involvement from us.
        glassBackground.isUserInteractionEnabled = true
        addSubview(glassBackground)

        // Content lives INSIDE the glass's own content host (the
        // UIVisualEffectView.contentView). When UIGlassEffect warps on
        // press, the effect view's rendering chain deforms the entire
        // content layer in lockstep — so the icon/label ride the liquid
        // wave together with the glass surface instead of staying pinned
        // while only the glass moves.
        contentContainer.isUserInteractionEnabled = false
        glassBackground.contentView.addSubview(contentContainer)

        self.title = title
        self.image = image
        configureTitleIfNeeded()
        configureIconIfNeeded()
        titleLabel?.text = title
        iconView?.image = image?.withRenderingMode(.alwaysTemplate)

        // Gesture recognizers sit above UIResponder's delivery path — they
        // observe the touch stream but don't consume it during the press
        // phase, which is exactly what we need: glass gets to warp, tap
        // still fires on release. `cancelsTouchesInView` is left at its
        // default `true`; on recognition (tap-up) the remaining touch is
        // cancelled in the subview, but by then the warp has already done
        // its work and the press is over anyway.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
        self.tapRecognizer = tap

        // Press feedback is version-gated:
        //   - iOS 26+: native UIGlassEffect.isInteractive does the surface
        //     warp under the finger (handled in GlassBackgroundView.update).
        //   - iOS ≤25: no native warp available, so attach the ported
        //     Telegram TouchEffect — drag stretches the button via
        //     sublayerTransform, release springs back, radial highlight
        //     tracks the finger.
        if #available(iOS 26.0, *) {
            // native path
        } else {
            let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
            elastic.touchEffectView = self
            elastic.highlightContainerView = glassBackground.contentView
            addGestureRecognizer(elastic)
            self.elasticRecognizer = elastic
        }
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        let resolvedCorner = cornerRadius ?? (bounds.height / 2.0)
        let resolvedDark = isDarkAppearance ?? (traitCollection.userInterfaceStyle == .dark)

        glassBackground.frame = bounds
        glassBackground.update(
            size: bounds.size,
            cornerRadius: resolvedCorner,
            isDark: resolvedDark,
            tintColor: tint,
            isInteractive: true,
            isVisible: true,
            transition: .immediate
        )

        contentContainer.frame = bounds
        layoutContent()
    }
    
    @discardableResult
    public func update(
        cornerRadius: CGFloat,
        tintColor: GlassBackgroundView.TintColor,
        isInteractive: Bool = true,
        isVisible: Bool = true,
    ) -> Self {
        self.tint = tintColor
        self.cornerRadius = cornerRadius
        
        let resolvedDark = isDarkAppearance ?? (traitCollection.userInterfaceStyle == .dark)

        glassBackground.update(
            size: bounds.size,
            cornerRadius: cornerRadius,
            isDark: resolvedDark,
            tintColor: tintColor,
            isInteractive: isInteractive,
            isVisible: isVisible,
            transition: .immediate
        )
        
        return self
    }

    private func layoutContent() {
        let iconSize = iconView?.image?.size.width ?? 0
        let clampedIconSize: CGFloat = iconSize > 0 ? max(20, min(28, iconSize)) : 0
        let titleSize = titleLabel?.sizeThatFits(CGSize(width: bounds.width - 2 * contentPadding, height: bounds.height)) ?? .zero

        let hasIcon = (iconView?.image != nil)
        let hasTitle = (titleLabel?.text?.isEmpty == false)

        if let indicator = loadingIndicator {
            let size = indicator.intrinsicContentSize
            indicator.frame = CGRect(
                x: (bounds.width - size.width) / 2.0,
                y: (bounds.height - size.height) / 2.0,
                width: size.width, height: size.height
            )
        }

        if hasIcon && hasTitle {
            let spacing = iconTitleSpacing
            let totalW = clampedIconSize + spacing + titleSize.width
            let startX = (bounds.width - totalW) / 2.0
            iconView?.frame = CGRect(
                x: startX,
                y: (bounds.height - clampedIconSize) / 2.0,
                width: clampedIconSize, height: clampedIconSize
            )
            titleLabel?.frame = CGRect(
                x: startX + clampedIconSize + spacing,
                y: 0, width: titleSize.width, height: bounds.height
            )
        } else if hasIcon {
            iconView?.frame = CGRect(
                x: (bounds.width - clampedIconSize) / 2.0,
                y: (bounds.height - clampedIconSize) / 2.0,
                width: clampedIconSize, height: clampedIconSize
            )
        } else if hasTitle {
            titleLabel?.frame = CGRect(
                x: contentPadding, y: 0,
                width: bounds.width - 2 * contentPadding, height: bounds.height
            )
        }
    }

    public override var intrinsicContentSize: CGSize {
        let hasIcon = (image != nil)
        let hasTitle = !(title ?? "").isEmpty

        if hasIcon && hasTitle {
            let iconW: CGFloat = 22
            let textW = titleLabel?.sizeThatFits(CGSize(width: 240, height: 40)).width ?? 60
            return CGSize(width: iconW + iconTitleSpacing + textW + 2 * contentPadding, height: 36)
        }
        if hasIcon {
            return CGSize(width: max(minimumSize.width, 36), height: max(minimumSize.height, 36))
        }
        if hasTitle {
            let textW = titleLabel?.sizeThatFits(CGSize(width: 240, height: 40)).width ?? 60
            return CGSize(width: max(minimumSize.width, textW + 2 * contentPadding), height: 36)
        }
        return minimumSize
    }

    // MARK: - Lazy subviews

    private func configureTitleIfNeeded() {
        guard title != nil, titleLabel == nil else { return }
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = contentColor
        label.textAlignment = .center
        contentContainer.addSubview(label)
        titleLabel = label
    }

    private func configureIconIfNeeded() {
        guard image != nil, iconView == nil else { return }
        let view = UIImageView()
        view.contentMode = .center
        view.tintColor = contentColor
        view.setMonochromaticEffect(tintColor: contentColor)
        contentContainer.addSubview(view)
        iconView = view
    }

    private func configureLoadingIndicatorIfNeeded() {
        guard loadingIndicator == nil else { return }
        let style: UIActivityIndicatorView.Style = .medium
        let indicator = UIActivityIndicatorView(style: style)
        indicator.hidesWhenStopped = false
        indicator.color = contentColor
        indicator.alpha = 0
        glassBackground.contentView.addSubview(indicator)
        loadingIndicator = indicator
        setNeedsLayout()
    }

    private func updateLoadingState(animated: Bool) {
        if isLoading {
            configureLoadingIndicatorIfNeeded()
            loadingIndicator?.startAnimating()
        }

        let contentTarget: CGFloat = isLoading ? 0.0 : 1.0
        let indicatorTarget: CGFloat = isLoading ? 1.0 : 0.0

        let apply = {
            self.contentContainer.alpha = contentTarget
            self.loadingIndicator?.alpha = indicatorTarget
        }
        let finalize = { [weak self] in
            guard let self = self else { return }
            if !self.isLoading {
                self.loadingIndicator?.stopAnimating()
            }
        }

        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut], animations: apply) { _ in finalize() }
        } else {
            apply()
            finalize()
        }
    }

    // MARK: - Actions

    @objc private func handleTap() {
        guard isEnabled, !isLoading else { return }
        action?(self)
    }
}
