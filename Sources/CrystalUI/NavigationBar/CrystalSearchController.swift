import UIKit

/// Search controller that integrates with `ViewController` and `NavigationBarImpl`.
///
/// Set on `ViewController.crystalSearchController` — the framework automatically:
/// - Shows a glass search pill in the nav bar (between title and content)
/// - On activation: pill becomes an editable text field, filters hide,
///   glass close button appears, keyboard shows
/// - On deactivation: reverse animation, filters return
///
/// ```swift
/// let search = CrystalSearchController()
/// search.placeholder = "Поиск"
/// search.onTextChanged = { text in /* filter */ }
/// controller.crystalSearchController = search
/// ```
public final class CrystalSearchController {

    // MARK: - Public API

    /// Placeholder text for the search field.
    public var placeholder: String = "Search"

    /// Called when search text changes.
    public var onTextChanged: ((String) -> Void)?

    /// Called when the user taps return.
    public var onReturn: ((String) -> Void)?

    /// Whether search is currently active.
    public private(set) var isActive: Bool = false

    // MARK: - Internal State

    /// The search pill view (shown in nav bar expansion area).
    let searchBar = CrystalSearchBarContent()

    /// Text field swapped into the pill when active.
    var textField: UITextField?

    /// Glass close button shown in the right bar area when active.
    var closeButton: GlassBarButtonView?

    /// Reference to the owning view controller (set by ViewController).
    weak var viewController: ViewController?

    /// The original nav bar content (restored on deactivation).
    var savedNavigationBarContent: NavigationBarContentView?

    /// Saved horizontal inset of the search pill.
    var savedHorizontalInset: CGFloat = 16.0

    // MARK: - Init

    public init() {
        searchBar.onTap = { [weak self] in
            self?.activate()
        }
    }

    // MARK: - Activation

    private static let closeButtonSize: CGFloat = 36.0

    /// Activate search: pill becomes text field, close button appears to its right.
    public func activate() {
        guard !isActive, let vc = viewController, let navBar = vc.navigationBarView else { return }
        isActive = true

        // Transition pill to active: hide icon/label, keep glass
        searchBar.setSearchActive(true)

        // Shrink pill to make room for close button
        searchBar.rightExtraInset = Self.closeButtonSize + 8.0

        // Text field inside the pill
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.font = .systemFont(ofSize: 17)
        tf.textColor = .label
        tf.tintColor = .systemBlue
        tf.returnKeyType = .search
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.clearButtonMode = .whileEditing
        let leftIcon = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)))
        leftIcon.tintColor = .secondaryLabel
        leftIcon.frame = CGRect(x: 0, y: 0, width: 28, height: 20)
        leftIcon.contentMode = .center
        tf.leftView = leftIcon
        tf.leftViewMode = .always
        tf.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        searchBar.addSubview(tf)
        tf.frame = searchBar.bounds.insetBy(dx: 8, dy: 0)
        tf.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textField = tf

        // Glass close button as sibling of the pill (inside same parent)
        let closeIcon = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        let close = GlassBarButtonView(icon: closeIcon, state: .glass)
        close.contentTintColor = .label
        close.alpha = 0
        close.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        // Add to searchBar's parent (the stacked content view or nav bar content area)
        if let parent = searchBar.superview {
            parent.addSubview(close)
        } else {
            navBar.addSubview(close)
        }
        closeButton = close

        // Activate search mode on the nav bar
        navBar.setSearchMode(true, animated: true)

        tf.becomeFirstResponder()

        // Lay out close button position after search mode triggers layout
        DispatchQueue.main.async { [weak self] in
            self?.layoutCloseButton()
        }

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            close.alpha = 1
            close.transform = .identity
        }
    }

    /// Deactivate search: close button disappears, pill returns to normal.
    public func deactivate() {
        guard isActive, let vc = viewController else { return }
        isActive = false
        textField?.resignFirstResponder()

        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            self.closeButton?.alpha = 0
            self.closeButton?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        } completion: { _ in
            self.cleanup(vc: vc)
        }
    }

    /// Position close button to the right of the search pill.
    func layoutCloseButton() {
        guard let close = closeButton else { return }
        let s = Self.closeButtonSize
        let pillFrame = searchBar.frame
        let parentBounds = searchBar.superview?.bounds ?? .zero
        // Close button right-aligned with right inset matching pill's left inset
        let x = parentBounds.width - s - searchBar.horizontalInset
        let y = pillFrame.midY - s / 2
        close.frame = CGRect(x: x, y: y, width: s, height: s)
    }

    @objc private func closeTapped() {
        deactivate()
    }

    private func cleanup(vc: ViewController) {
        textField?.removeFromSuperview()
        textField = nil
        closeButton?.removeFromSuperview()
        closeButton = nil

        // Restore pill
        searchBar.setSearchActive(false)
        searchBar.rightExtraInset = 0

        // Deactivate search mode on nav bar
        vc.navigationBarView?.setSearchMode(false, animated: true)

        savedNavigationBarContent = nil
    }

    @objc private func textDidChange() {
        onTextChanged?(textField?.text ?? "")
    }
}
