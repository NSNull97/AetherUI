import UIKit

/// Active search bar with a real text field, used as a `NavigationBarContentView`
/// in `.replacement` mode — replaces the title row when search is activated.
///
/// Features:
/// - Glass-styled text field matching the iOS 26 aesthetic
/// - Cancel button with configurable title
/// - Delegate callbacks for text changes, activation, and cancellation
/// - Automatic first-responder management
///
/// ```swift
/// let searchBar = CrystalActiveSearchBar()
/// searchBar.placeholder = "Search"
/// searchBar.onTextChanged = { text in print(text) }
/// searchBar.onCancel = { print("cancelled") }
/// controller.navigationBarContent = searchBar
/// ```
public final class CrystalActiveSearchBar: NavigationBarContentView, UITextFieldDelegate {

    // MARK: - Public API

    /// Placeholder text displayed in the text field.
    public var placeholder: String = "Search" {
        didSet { textField.placeholder = placeholder }
    }

    /// Current search text.
    public var text: String {
        get { textField.text ?? "" }
        set { textField.text = newValue }
    }

    /// Cancel button title.
    public var cancelTitle: String = "Cancel" {
        didSet { cancelButton.setTitle(cancelTitle, for: .normal) }
    }

    /// Called when the search text changes.
    public var onTextChanged: ((String) -> Void)?

    /// Called when the cancel button is tapped.
    public var onCancel: (() -> Void)?

    /// Called when the user taps return on the keyboard.
    public var onReturn: ((String) -> Void)?

    /// Pill height.
    public var pillHeight: CGFloat = 36.0

    /// Horizontal inset from content edges to pill.
    public var horizontalInset: CGFloat = 16.0

    /// Whether to become first responder automatically when added to the bar.
    public var activatesOnAppear: Bool = true

    // MARK: - Subviews

    private let pillView = GlassBackgroundView(style: .regular)
    private let iconView = UIImageView()
    private let textField = UITextField()
    private let clearButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    // MARK: - Init

    public init() {
        super.init(frame: .zero)

        pillView.isUserInteractionEnabled = false
        addSubview(pillView)

        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        iconView.image = UIImage(systemName: "magnifyingglass", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .center
        addSubview(iconView)

        textField.placeholder = placeholder
        textField.font = .systemFont(ofSize: 17)
        textField.textColor = .label
        textField.tintColor = .systemBlue
        textField.returnKeyType = .search
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.clearButtonMode = .whileEditing
        textField.delegate = self
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        addSubview(textField)

        cancelButton.setTitle(cancelTitle, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        addSubview(cancelButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - NavigationBarContentView

    override public var nominalHeight: CGFloat { pillHeight + 12.0 }

    override public var mode: NavigationBarContentMode { .replacement }

    override public func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGSize {
        let cancelSize = cancelButton.sizeThatFits(CGSize(width: 200, height: pillHeight))
        let cancelWidth = cancelSize.width + 8.0

        let insetL = horizontalInset + leftInset
        let insetR = 8.0 + rightInset
        let pillWidth = max(0, size.width - insetL - insetR - cancelWidth)
        let pillY = floor((size.height - pillHeight) / 2.0)

        let pillFrame = CGRect(x: insetL, y: pillY, width: pillWidth, height: pillHeight)
        transition.updateFrame(view: pillView, frame: pillFrame)
        pillView.update(
            size: pillFrame.size,
            cornerRadius: pillHeight / 2.0,
            isDark: traitCollection.userInterfaceStyle == .dark,
            tintColor: .init(kind: .panel),
            isInteractive: false,
            isVisible: true,
            transition: transition
        )

        let iconSize: CGFloat = 18.0
        let iconX = insetL + 10.0
        let iconY = pillY + floor((pillHeight - iconSize) / 2.0)
        transition.updateFrame(view: iconView, frame: CGRect(x: iconX, y: iconY, width: iconSize, height: iconSize))

        let textX = iconX + iconSize + 6.0
        let textWidth = max(0, pillFrame.maxX - textX - 8.0)
        let textY = pillY + floor((pillHeight - 22.0) / 2.0)
        transition.updateFrame(view: textField, frame: CGRect(x: textX, y: textY, width: textWidth, height: 22.0))

        let cancelX = pillFrame.maxX + 8.0
        let cancelY = pillY + floor((pillHeight - cancelSize.height) / 2.0)
        transition.updateFrame(view: cancelButton, frame: CGRect(x: cancelX, y: cancelY, width: cancelSize.width, height: cancelSize.height))

        return size
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && activatesOnAppear {
            DispatchQueue.main.async { [weak self] in
                self?.textField.becomeFirstResponder()
            }
        }
    }

    // MARK: - UITextFieldDelegate

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onReturn?(textField.text ?? "")
        return true
    }

    // MARK: - Actions

    @objc private func textDidChange() {
        onTextChanged?(textField.text ?? "")
    }

    @objc private func cancelTapped() {
        textField.resignFirstResponder()
        onCancel?()
    }

    // MARK: - Public Methods

    /// Make the text field the first responder.
    @discardableResult
    public func activate() -> Bool {
        return textField.becomeFirstResponder()
    }

    /// Resign first responder from the text field.
    public func deactivate() {
        textField.resignFirstResponder()
    }
}
