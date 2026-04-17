import UIKit

// MARK: - GlassButton

/// Generic glass-styled `UIControl` — a rounded-rect button with an
/// optional title, optional leading icon, a glass background, and a
/// spring press-in feedback on touch. Designed to be dropped anywhere
/// (card bottoms, toolbars, free-standing actions), not tied to nav bar
/// sizing like `GlassBarButtonView`.
///
/// Press feedback is two layers:
///   1. **Native glass warp** via `UIGlassEffect.isInteractive = true` on
///      iOS 26 hardware. For the warp to actually fire, the
///      `GlassBackgroundView` underneath has to be hit-testable — a
///      UIControl that swallows touches first (typical `isUserInteractionEnabled = false`
///      on the glass child) suppresses it. We keep glass interaction ENABLED
///      and override `hitTest` to still route action dispatch to `self`,
///      so both UIGlassEffect observer and UIControl's target-action fire.
///   2. **Manual spring** (scale 0.97 + alpha 0.92, damping 0.7) for
///      simulator / older iOS where the native warp is a no-op, and as a
///      subtle stacking effect on top of the warp on real iOS 26 hardware.
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

    // MARK: - Init

    public init(title: String? = nil, image: UIImage? = nil) {
        self.glassBackground = GlassBackgroundView(style: .regular)
        super.init(frame: .zero)

        // Interaction stays ENABLED on the glass so iOS 26's
        // `UIGlassEffect.isInteractive` window-level observer registers
        // finger position inside the glass bounds and runs the native
        // liquid warp. `hitTest` below rewrites the returned target to
        // `self` so UIControl still owns action dispatch (otherwise the
        // glass's inner `UIVisualEffectView` would claim the hit and
        // swallow the tap).
        glassBackground.isUserInteractionEnabled = true
        addSubview(glassBackground)

        contentContainer.isUserInteractionEnabled = false
        addSubview(contentContainer)

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
    // Every in-bounds touch resolves to `self` so UIControl's tracking /
    // target-action dispatch fires. The glass sibling's own subtree still
    // exists in the view hierarchy (interaction enabled), so the
    // UIGlassEffect.isInteractive observer sees the touch coordinates and
    // runs its native warp — we just don't want the UIVisualEffectView
    // returned as the delivery target.

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
        return bounds.contains(point) ? self : nil
    }

    // MARK: - Touch feedback

    public override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            let pressed = isHighlighted
            UIView.animate(
                withDuration: pressed ? 0.12 : 0.32,
                delay: 0,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: {
                    self.transform = pressed
                        ? CGAffineTransform(scaleX: 0.97, y: 0.97)
                        : .identity
                    self.alpha = pressed ? 0.92 : 1.0
                }
            )
        }
    }

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
