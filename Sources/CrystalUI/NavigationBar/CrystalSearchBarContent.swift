import UIKit

/// Glass-styled search bar matching the iOS 26 aesthetic.
/// Renders a translucent pill with a magnifying glass icon and placeholder text.
///
/// Can be used standalone or as a `NavigationBarContentView` (`.expansion` mode)
/// to sit below the nav bar title row.
///
/// ```swift
/// let searchBar = CrystalSearchBarContent()
/// searchBar.placeholder = "Search"
/// searchBar.onTap = { print("Search activated") }
/// controller.navigationBarContent = searchBar
/// ```
public final class CrystalSearchBarContent: NavigationBarContentView {

    // MARK: - Public API

    /// Placeholder text displayed in the search pill.
    public var placeholder: String = "Search" {
        didSet { placeholderLabel.text = placeholder }
    }

    /// Called when the user taps the search bar.
    public var onTap: (() -> Void)?

    /// Glass appearance: dark mode flag.
    public var isDark: Bool = false

    /// Pill height.
    public var pillHeight: CGFloat = 36.0

    /// Horizontal inset from content edges to pill.
    public var horizontalInset: CGFloat = 16.0

    // MARK: - Subviews

    private let pillView = GlassBackgroundView(style: .regular)
    private let iconView = UIImageView()
    private let placeholderLabel = UILabel()

    // MARK: - Init

    public init() {
        super.init(frame: .zero)

        pillView.isUserInteractionEnabled = false
        addSubview(pillView)

        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        iconView.image = UIImage(systemName: "magnifyingglass", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .center
        addSubview(iconView)

        placeholderLabel.text = placeholder
        placeholderLabel.font = .systemFont(ofSize: 17)
        placeholderLabel.textColor = .secondaryLabel
        addSubview(placeholderLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - NavigationBarContentView

    override public var nominalHeight: CGFloat { pillHeight + 12.0 }

    override public var mode: NavigationBarContentMode { .expansion }

    override public func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGSize {
        let insetL = horizontalInset + leftInset
        let insetR = horizontalInset + rightInset
        let pillWidth = max(0, size.width - insetL - insetR)
        let pillY = floor((size.height - pillHeight) / 2.0)

        let pillFrame = CGRect(x: insetL, y: pillY, width: pillWidth, height: pillHeight)
        transition.updateFrame(view: pillView, frame: pillFrame)
        pillView.update(
            size: pillFrame.size,
            cornerRadius: pillHeight / 2.0,
            isDark: isDark || traitCollection.userInterfaceStyle == .dark,
            tintColor: .init(kind: .panel),
            isInteractive: false,
            isVisible: true,
            transition: transition
        )

        let iconSize: CGFloat = 20.0
        let iconX = insetL + 10.0
        let iconY = pillY + floor((pillHeight - iconSize) / 2.0)
        transition.updateFrame(view: iconView, frame: CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize))

        let labelX = iconX + iconSize + 6.0
        let labelWidth = max(0, pillFrame.maxX - labelX - 10.0)
        let labelY = pillY + floor((pillHeight - 22.0) / 2.0)
        transition.updateFrame(view: placeholderLabel, frame: CGRect(x: labelX, y: labelY, width: labelWidth, height: 22.0))

        return size
    }

    // MARK: - Active/Inactive State

    /// Hides icon and label (keeps glass background) when search is active.
    /// Called by `CrystalSearchController` — not for direct use.
    public func setSearchActive(_ active: Bool) {
        iconView.alpha = active ? 0 : 1
        placeholderLabel.alpha = active ? 0 : 1
        // Disable tap gesture when text field is active inside
        gestureRecognizers?.forEach { $0.isEnabled = !active }
    }

    // MARK: - Private

    @objc private func tapped() {
        onTap?()
    }
}
