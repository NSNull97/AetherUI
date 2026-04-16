import UIKit

// MARK: - Delegate Protocol

/// Delegate for `CrystalSearchController` lifecycle and text events.
///
/// Implement to react to search activation, text changes, and dismissal.
/// All methods have default empty implementations.
public protocol CrystalSearchControllerDelegate: AnyObject {
    /// Called when search is about to activate (pill → text field).
    func searchControllerWillActivate(_ controller: CrystalSearchController)

    /// Called after search has activated and the text field is first responder.
    func searchControllerDidActivate(_ controller: CrystalSearchController)

    /// Called when the search text changes.
    func searchController(_ controller: CrystalSearchController, didChangeText text: String)

    /// Called when the user taps the return key.
    func searchController(_ controller: CrystalSearchController, didSubmitText text: String)

    /// Called when search is about to deactivate (text field → pill).
    func searchControllerWillDeactivate(_ controller: CrystalSearchController)

    /// Called after search has fully deactivated and the nav bar is restored.
    func searchControllerDidDeactivate(_ controller: CrystalSearchController)
}

// Default implementations (all optional)
public extension CrystalSearchControllerDelegate {
    func searchControllerWillActivate(_ controller: CrystalSearchController) {}
    func searchControllerDidActivate(_ controller: CrystalSearchController) {}
    func searchController(_ controller: CrystalSearchController, didChangeText text: String) {}
    func searchController(_ controller: CrystalSearchController, didSubmitText text: String) {}
    func searchControllerWillDeactivate(_ controller: CrystalSearchController) {}
    func searchControllerDidDeactivate(_ controller: CrystalSearchController) {}
}

// MARK: - Search Controller

/// Glass-styled search controller that integrates with `ViewController`'s navigation bar.
///
/// ## Integration
///
/// Set on `ViewController.crystalSearchController`. The framework automatically
/// shows a glass search pill in the nav bar expansion area (between title and
/// content like filter chips).
///
/// ```swift
/// let search = CrystalSearchController()
/// search.placeholder = "Search"
/// search.delegate = self
/// crystalSearchController = search
/// ```
///
/// ## Activation Flow
///
/// 1. User taps the search pill in the nav bar
/// 2. Title and buttons fade out (easeInOut 0.3s)
/// 3. Filter chips fade out, nav bar shrinks
/// 4. Search pill slides up to the title position
/// 5. Pill's icon/label hide, real `UITextField` appears inside
/// 6. Glass close button (36pt) appears to the right of the pill
/// 7. Keyboard shows, collection content animates up
///
/// ## Deactivation Flow
///
/// 1. User taps the close button (or `deactivate()` is called)
/// 2. Keyboard dismisses simultaneously with UI restoration
/// 3. Close button scales down and fades
/// 4. Text field removed, pill icon/label restored
/// 5. Nav bar expands back, title/buttons/filters fade in
/// 6. Collection content animates down
///
/// ## Tab Bar Integration
///
/// When the owning `ViewController` is inside a `CrystalTabBarController`,
/// the tab bar's search showcase button can trigger activation:
///
/// ```swift
/// override func tabBarActivateSearch() {
///     crystalSearchController?.activate()
/// }
/// ```
///
/// ## Results Controller
///
/// Optionally set `searchResultsController` to display a custom results view
/// when search is active:
///
/// ```swift
/// search.searchResultsController = MySearchResultsController()
/// ```
///
/// The results controller receives text updates via
/// `CrystalSearchContentController.searchTextUpdated(text:)`.
public final class CrystalSearchController: NSObject, UITextFieldDelegate {

    // MARK: - Public Properties

    /// Placeholder text for the search field.
    public var placeholder: String = "Search" {
        didSet { searchBar.placeholder = placeholder }
    }

    /// Delegate for search lifecycle and text events.
    public weak var delegate: CrystalSearchControllerDelegate?

    /// Whether search is currently active.
    public private(set) var isActive: Bool = false

    /// Current search text (empty when inactive).
    public var searchText: String {
        textField?.text ?? ""
    }

    /// Optional controller that displays search results.
    /// Its `searchTextUpdated(text:)` is called on every text change.
    public var searchResultsController: CrystalSearchContentController?

    /// Size of the glass close button (default 36pt).
    public var closeButtonSize: CGFloat = 36.0

    // MARK: - Internal Views

    /// The glass search pill shown in the nav bar.
    let searchBar = CrystalSearchBarContent()

    // MARK: - Private State

    private var textField: UITextField?
    private var closeButton: GlassBarButtonView?
    weak var viewController: ViewController?
    var savedNavigationBarContent: NavigationBarContentView?

    // MARK: - Init

    public override init() {
        super.init()
        searchBar.onTap = { [weak self] in
            self?.activate()
        }
    }

    // MARK: - Activation

    /// Activate search mode. Can be called programmatically or triggered by
    /// tapping the search pill.
    ///
    /// Does nothing if already active or if the view controller is not set.
    public func activate() {
        guard !isActive, let vc = viewController, let navBar = vc.navigationBarView else { return }
        isActive = true
        delegate?.searchControllerWillActivate(self)

        // Transition pill: hide icon/label, keep glass, shrink for close button
        searchBar.setSearchActive(true)
        searchBar.rightExtraInset = closeButtonSize + 8.0

        // Text field inside the glass pill
        let tf = makeTextField()
        searchBar.pillView.contentView.addSubview(tf)
        tf.frame = searchBar.pillView.bounds.insetBy(dx: 12, dy: 0)
        tf.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textField = tf

        // Glass close button next to the pill
        let close = makeCloseButton()
        if let parent = searchBar.superview {
            parent.addSubview(close)
        } else {
            navBar.addSubview(close)
        }
        closeButton = close

        // Nav bar: title/buttons fade, pill moves up, filters hide
        navBar.setSearchMode(true, animated: true)

        tf.becomeFirstResponder()

        // Position close button after layout settles
        DispatchQueue.main.async { [weak self] in
            self?.layoutCloseButton()
        }

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            close.alpha = 1
            close.transform = .identity
        } completion: { [weak self] _ in
            guard let self else { return }
            self.delegate?.searchControllerDidActivate(self)
        }
    }

    /// Deactivate search mode. Keyboard dismisses and nav bar restores
    /// simultaneously (easeInOut 0.3s).
    ///
    /// Does nothing if already inactive.
    public func deactivate() {
        guard isActive, let vc = viewController else { return }
        isActive = false
        delegate?.searchControllerWillDeactivate(self)

        // Everything fires at once: keyboard + UI restoration
        textField?.resignFirstResponder()
        textField?.removeFromSuperview()
        textField = nil

        searchBar.setSearchActive(false)
        searchBar.rightExtraInset = 0
        vc.navigationBarView?.setSearchMode(false, animated: true)

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.closeButton?.alpha = 0
            self.closeButton?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        } completion: { [weak self] _ in
            guard let self else { return }
            self.closeButton?.removeFromSuperview()
            self.closeButton = nil
            self.delegate?.searchControllerDidDeactivate(self)
        }
    }

    // MARK: - Layout

    /// Reposition the close button relative to the search pill.
    /// Called automatically after layout changes.
    func layoutCloseButton() {
        guard let close = closeButton else { return }
        let s = closeButtonSize
        let pillFrame = searchBar.frame
        let parentBounds = searchBar.superview?.bounds ?? .zero
        let x = parentBounds.width - s - searchBar.horizontalInset
        let y = pillFrame.midY - s / 2
        close.frame = CGRect(x: x, y: y, width: s, height: s)
    }

    // MARK: - UITextFieldDelegate

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        delegate?.searchController(self, didSubmitText: text)
        searchResultsController?.searchTextUpdated(text: text)
        return true
    }

    // MARK: - Private

    private func makeTextField() -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.font = .systemFont(ofSize: 17)
        tf.textColor = .label
        tf.tintColor = .systemBlue
        tf.returnKeyType = .search
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.clearButtonMode = .whileEditing
        tf.delegate = self

        let icon = UIImageView(image: UIImage(
            systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        ))
        icon.tintColor = .secondaryLabel
        icon.frame = CGRect(x: 0, y: 0, width: 28, height: 20)
        icon.contentMode = .center
        tf.leftView = icon
        tf.leftViewMode = .always

        tf.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        return tf
    }

    private func makeCloseButton() -> GlassBarButtonView {
        let icon = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        )
        let btn = GlassBarButtonView(icon: icon, state: .glass)
        btn.contentTintColor = .label
        btn.alpha = 0
        btn.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        btn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return btn
    }

    @objc private func closeTapped() {
        deactivate()
    }

    @objc private func textDidChange() {
        let text = textField?.text ?? ""
        delegate?.searchController(self, didChangeText: text)
        searchResultsController?.searchTextUpdated(text: text)
    }
}
