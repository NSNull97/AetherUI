import UIKit

// MARK: - GlassButton

/// Generic glass-styled `UIControl` — a rounded-rect button with an
/// optional title, optional leading icon, and a glass background. Designed
/// to be dropped anywhere (card bottoms, toolbars, free-standing actions),
/// not tied to nav bar sizing like `GlassBarButtonView`.
///
/// Press feedback is delegated entirely to the native
/// `UIGlassEffect.isInteractive` deformation: the content (icon / label) is
/// parented into the effect view's own `contentView`, so when iOS warps the
/// glass toward the finger the content warps with it as a single liquid
/// surface. No manual scale / alpha animation is layered on top.
///
/// Sizing contract:
///   - If only `image` is set, renders square-ish sized to `intrinsicContentSize`
///     (36×36 default, configurable via `minimumSize` / explicit frame).
///   - If only `title` is set, renders pill-sized with horizontal padding
///     around the label.
///   - If both are set, icon sits leading + label trailing inside the pill.
///
/// Glass:
///   - Uses `GlassBackgroundView(style: .regular)` internally.
///   - `isDark` auto-derives from the view's trait collection (overrideable
///     via `isDarkAppearance` property if the surface sits on a custom dark
///     background while the system is in light mode).
///   - Corner radius defaults to `bounds.height / 2` (pill) — override via
///     `cornerRadius` if a specific rect shape is needed.
public final class GlassButton: UIControl {
    // MARK: - Subviews

    private let glassBackground: GlassBackgroundView
    private let contentContainer = UIView()
    private var iconView: UIImageView?
    private var titleLabel: UILabel?

    // MARK: - Properties

    /// Tap handler. Fires on `touchUpInside` after the press animation
    /// starts to settle. `sender` is the button itself.
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
        }
    }

    /// Override for the `isDark` flag passed to the glass background.
    /// `nil` (default) → derived from `traitCollection.userInterfaceStyle`.
    public var isDarkAppearance: Bool? {
        didSet { setNeedsLayout() }
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

    // MARK: - Init

    public init(title: String? = nil, image: UIImage? = nil) {
        self.glassBackground = GlassBackgroundView(style: .regular)
        super.init(frame: .zero)

        // Keep glass interaction ENABLED so iOS 26's `UIGlassEffect.isInteractive`
        // can register finger position and drive the elastic stretch
        // deformation. Touches still reach this button for action handling
        // because `hitTest` below always claims points inside `bounds` for
        // `self` (UIControl receiver) — the glass only influences rendering.
        glassBackground.isUserInteractionEnabled = true
        addSubview(glassBackground)

        // Content sits INSIDE the glass's own content view so it's hosted by
        // the UIVisualEffectView that runs the interactive deformation. When
        // the user presses, `UIGlassEffect.isInteractive` warps the whole
        // visual-effect stack — glass surface AND content (icon/label) move
        // as one, which is what real iOS 26 liquid-glass buttons do. Nothing
        // we have to animate manually.
        contentContainer.isUserInteractionEnabled = false
        glassBackground.contentView.addSubview(contentContainer)

        self.title = title
        self.image = image
        configureTitleIfNeeded()
        configureIconIfNeeded()
        titleLabel?.text = title
        iconView?.image = image?.withRenderingMode(.alwaysTemplate)

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Hit testing
    //
    // Every touch inside `bounds` is claimed by `self` so UIControl's
    // target-action fires. The nested glass view has `userInteractionEnabled = true`
    // (needed for `UIGlassEffect.isInteractive` to register touches at the
    // window-level observer level), but its own hitTest would otherwise try
    // to return its `UIVisualEffectView` as the target — which has no
    // actions and would swallow taps. Bypassing here keeps glass rendering
    // interactive while routing action dispatch to the control.

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        return bounds.contains(point) ? self : nil
    }

    // MARK: - Touch feedback
    //
    // No manual press animation. Content lives inside
    // `glassBackground.contentView` (the UIVisualEffectView's own content
    // host), and the glass effect is configured with
    // `UIGlassEffect.isInteractive = true` during layout. iOS 26's runtime
    // warps the visual-effect stack toward the finger on touch, deforming
    // glass + content in lockstep. On non-iOS 26 targets there's no
    // deformation — that's the explicit trade-off of this design: a
    // physically accurate liquid-glass press on capable hardware, plain
    // hit-testing everywhere else.

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
            tintColor: .init(kind: .panel),
            isInteractive: true,
            isVisible: true,
            transition: .immediate
        )

        contentContainer.frame = bounds
        layoutContent()
    }

    private func layoutContent() {
        let iconSize = iconView?.image?.size.width ?? 0
        let clampedIconSize: CGFloat = iconSize > 0 ? max(20, min(28, iconSize)) : 0
        let titleSize = titleLabel?.sizeThatFits(CGSize(width: bounds.width - 2 * contentPadding, height: bounds.height)) ?? .zero

        let hasIcon = (iconView?.image != nil)
        let hasTitle = (titleLabel?.text?.isEmpty == false)

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

    // MARK: - Actions

    @objc private func tapped() {
        action?(self)
    }
}
