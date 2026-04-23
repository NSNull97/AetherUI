import UIKit

/// Glass-styled bar button with multiple display states.
/// Pure UIKit implementation.
///
/// **Why UIView, not UIControl:** iOS 26+ `UIGlassEffect.isInteractive`
/// needs the underlying `UIVisualEffectView` to receive touches so it
/// can observe finger position for the native liquid-surface warp. A
/// UIControl host swallows touches into its own tracking pipeline
/// before the effect view can see them, which kills the press feedback.
/// So we use a plain UIView + `UITapGestureRecognizer` and keep
/// `glassBackground.isUserInteractionEnabled = true` — matches
/// `GlassButton`'s design.
public final class GlassBarButtonView: UIView {
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
    private var elasticRecognizer: GlassHighlightGestureRecognizer?

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

    /// Override for the `isDark` flag passed to the glass background.
    /// `nil` (default) → derived from `traitCollection.userInterfaceStyle`
    /// on every layout pass. Forwarded to `GlassBackgroundView.isDarkOverride`
    /// so the glass also picks up the override on its own auto-layout /
    /// trait-change paths. Use when the button sits on a custom dark
    /// background while the system is in light mode (or vice versa).
    public var isDarkAppearance: Bool? {
        didSet {
            glassBackground.isDarkOverride = isDarkAppearance
            setNeedsLayout()
        }
    }

    private var tapRecognizer: UITapGestureRecognizer?

    // MARK: - Init

    public init(icon: UIImage? = nil, title: String? = nil, state: DisplayState = .glass) {
        self.displayState = state
        self.glassBackground = GlassBackgroundView(style: state == .tintedGlass ? .prominent : .regular)
        self.contentContainer = UIView()

        super.init(frame: .zero)

        // Keep interaction ON on the glass so iOS 26+
        // UIGlassEffect.isInteractive can observe finger position for
        // the native surface warp. Tap dispatch goes via a
        // UITapGestureRecognizer on self (below).
        glassBackground.isUserInteractionEnabled = true
        addSubview(glassBackground)

        // Content sits inside the glass's own content host so
        // UIGlassEffect's warp deforms both surface and icon in
        // lockstep — otherwise only the glass jelly wobbles while
        // the icon stays pinned (barely visible). Same trick as
        // GlassButton.
        contentContainer.isUserInteractionEnabled = false
        glassBackground.contentView.addSubview(contentContainer)

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

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        self.tapRecognizer = tap

        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        long.minimumPressDuration = 0.35
        long.cancelsTouchesInView = false
        addGestureRecognizer(long)
        self.longPressRecognizer = long

        // Press feedback: iOS 26+ uses UIGlassEffect.isInteractive (see
        // layoutSubviews), iOS ≤25 gets the ported Telegram TouchEffect
        // — drag stretches the button, release springs back, radial
        // highlight tracks the finger.
        if #unavailable(iOS 26.0) {
            let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
            elastic.touchEffectView = self
            elastic.highlightContainerView = glassBackground.contentView
            addGestureRecognizer(elastic)
            self.elasticRecognizer = elastic
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override public func layoutSubviews() {
        super.layoutSubviews()

        let resolvedDark = isDarkAppearance ?? (traitCollection.userInterfaceStyle == .dark)
        glassBackground.frame = bounds
        glassBackground.update(size: bounds.size, cornerRadius: bounds.height / 2.0, isDark: resolvedDark, tintColor: .init(kind: .panel), isInteractive: displayState == .glass || displayState == .tintedGlass, isVisible: true, transition: .immediate)
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
        // Suppress the tap so a single long-press opens only the menu.
        tapRecognizer?.isEnabled = false
        DispatchQueue.main.async { [weak self] in self?.tapRecognizer?.isEnabled = true }
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
