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

    /// The original right bar button item (restored on deactivation).
    var savedRightBarButtonItem: UIBarButtonItem?

    /// The original nav bar content (restored on deactivation).
    var savedNavigationBarContent: NavigationBarContentView?

    // MARK: - Init

    public init() {
        searchBar.onTap = { [weak self] in
            self?.activate()
        }
    }

    // MARK: - Activation

    /// Activate search: pill becomes text field, close button appears.
    public func activate() {
        guard !isActive, let vc = viewController, let navBar = vc.navigationBarView else { return }
        isActive = true

        // Save current state
        savedNavigationBarContent = vc.navigationBarContent

        // Transition pill to active: hide icon/label, keep glass
        searchBar.setSearchActive(true)

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

        // Hide filters (only search pill in nav bar)
        vc._rawNavigationBarContent = nil
        vc.rebuildNavigationBarContent()

        // Glass close button added directly to the nav bar (not via UIBarButtonItem)
        let closeIcon = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        let close = GlassBarButtonView(icon: closeIcon, state: .glass)
        close.contentTintColor = .label
        let closeSize: CGFloat = 36.0
        // Position in top-right of nav bar
        let navBarBounds = navBar.bounds
        close.frame = CGRect(
            x: navBarBounds.width - closeSize - 16,
            y: navBarBounds.height - closeSize - 10,
            width: closeSize,
            height: closeSize
        )
        close.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]
        close.alpha = 0
        close.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        navBar.addSubview(close)
        closeButton = close

        // Hide existing right button
        savedRightBarButtonItem = vc.navigationItem.rightBarButtonItem
        vc.navigationItem.rightBarButtonItems = []

        tf.becomeFirstResponder()
        vc.requestLayout(transition: .animated(duration: 0.35, curve: .spring))

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.2, options: [.beginFromCurrentState]) {
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

    @objc private func closeTapped() {
        deactivate()
    }

    private func cleanup(vc: ViewController) {
        textField?.removeFromSuperview()
        textField = nil
        closeButton?.removeFromSuperview()
        closeButton = nil

        // Restore pill to inactive
        searchBar.setSearchActive(false)

        // Restore original content and buttons
        vc.navigationItem.rightBarButtonItem = savedRightBarButtonItem
        vc._rawNavigationBarContent = savedNavigationBarContent
        vc.rebuildNavigationBarContent()
        savedRightBarButtonItem = nil
        savedNavigationBarContent = nil

        vc.requestLayout(transition: .animated(duration: 0.35, curve: .spring))
    }

    @objc private func textDidChange() {
        onTextChanged?(textField?.text ?? "")
    }
}
