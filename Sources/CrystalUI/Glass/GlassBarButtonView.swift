import UIKit

/// Glass-styled bar button with multiple display states.
/// Pure UIKit implementation.
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

    /// Provider for a long-press context menu. When this returns a non-empty
    /// list, the button attaches a long-press gesture that presents a
    /// `ContextMenuController` anchored at the button.
    public var contextMenuItemsProvider: (() -> [ContextMenuItem])?
    /// Haptic + presentation flavour: `.longPress` uses UILongPressGestureRecognizer,
    /// `.tap` overrides `action` and presents on tap-up.
    public enum ContextMenuTrigger { case longPress, tap }
    public var contextMenuTrigger: ContextMenuTrigger = .longPress
    /// Layout flavour passed to the underlying `ContextMenuController`.
    /// Defaults to `.morph` (button glass expands into menu). Set to
    /// `.preview(...)` to use the long-press card style (button lifts as a
    /// preview snapshot, menu appears below).
    public var contextMenuPresentationStyle: ContextMenuController.PresentationStyle = .morph
    private weak var currentContextController: ContextMenuController?
    private var longPressRecognizer: UILongPressGestureRecognizer?

    public var contentTintColor: UIColor = .white {
        didSet {
            iconView?.tintColor = contentTintColor
            iconView?.setMonochromaticEffect(tintColor: contentTintColor)
            titleLabel?.textColor = contentTintColor
        }
    }

    /// Touch feedback. Two flavours:
    ///   - `.glass` / `.tintedGlass`: subtle elastic press — scale 0.97 + a
    ///     small alpha dip 1.0→0.92, sprung. The native UIGlassEffect's
    ///     `.isInteractive` is also enabled (when iOS 26+ is available),
    ///     so on real glass surfaces the lens deformation kicks in on top.
    ///   - `.generic`: stronger pop — scale 0.92, alpha 0.7. Same as before.
    override public var isHighlighted: Bool {
        didSet {
            let isGlass = (displayState == .glass || displayState == .tintedGlass)
            let pressedScale: CGFloat = isGlass ? 0.97 : 0.92
            let pressedAlpha: CGFloat = isGlass ? 0.92 : 0.7
            let duration: TimeInterval = isHighlighted ? 0.12 : 0.32
            let damping: CGFloat = isGlass ? 0.7 : 0.9
            UIView.animate(
                withDuration: duration, delay: 0,
                usingSpringWithDamping: damping, initialSpringVelocity: 0.0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: {
                    self.transform = self.isHighlighted ? CGAffineTransform(scaleX: pressedScale, y: pressedScale) : .identity
                    self.alpha = self.isHighlighted ? pressedAlpha : 1.0
                }
            )
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

        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        long.minimumPressDuration = 0.35
        long.cancelsTouchesInView = false
        addGestureRecognizer(long)
        self.longPressRecognizer = long
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override public func layoutSubviews() {
        super.layoutSubviews()

        glassBackground.frame = bounds
        glassBackground.update(size: bounds.size, cornerRadius: bounds.height / 2.0, isDark: traitCollection.userInterfaceStyle == .dark, tintColor: .init(kind: .panel), isInteractive: displayState == .glass || displayState == .tintedGlass, isVisible: true, transition: .immediate)
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
        // `tap` trigger takes precedence over `action` so callers can easily turn
        // a button into a menu host without replumbing their action pipelines.
        if contextMenuTrigger == .tap, let items = contextMenuItemsProvider?(), !items.isEmpty {
            presentContextMenu(items: items)
            return
        }
        action?(self)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard contextMenuTrigger == .longPress, recognizer.state == .began else { return }
        guard let items = contextMenuItemsProvider?(), !items.isEmpty else { return }
        // Suppress the accompanying touch-up action so a single long-press only
        // opens the menu instead of firing the regular tap handler afterwards.
        isHighlighted = false
        cancelTracking(with: nil)
        presentContextMenu(items: items)
    }

    private func presentContextMenu(items: [ContextMenuItem]) {
        let controller = ContextMenuController.present(
            source: self,
            cornerRadius: bounds.height / 2.0,
            items: items,
            presentationStyle: contextMenuPresentationStyle,
            onDismiss: { [weak self] in
                self?.currentContextController = nil
            }
        )
        currentContextController = controller
    }
}
