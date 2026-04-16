import UIKit

/// Controller that manages search activation, results display, and dismissal.
///
/// Port of Telegram's `SearchDisplayController`. Provides a background overlay,
/// a search content view (results), and wires text changes from the search bar
/// to the content.
///
/// Usage:
/// ```swift
/// let searchController = CrystalSearchDisplayController(
///     contentController: MySearchResultsController(),
///     cancel: { /* dismiss search */ }
/// )
/// // Activate: add searchController.view to your hierarchy
/// // Wire text: searchController.updateSearchText("query")
/// ```
public final class CrystalSearchDisplayController {

    /// The content controller that displays search results.
    public let contentController: CrystalSearchContentController

    /// Background view (dimming overlay behind results).
    public let backgroundView: UIView

    /// Whether the controller is being deactivated (prevents re-entrant cancel).
    public var isDeactivating = false

    private let cancel: () -> Void

    public init(contentController: CrystalSearchContentController, cancel: @escaping () -> Void) {
        self.contentController = contentController
        self.cancel = cancel

        self.backgroundView = UIView()
        self.backgroundView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        self.backgroundView.alpha = 0.0

        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        self.backgroundView.addGestureRecognizer(tap)

        self.contentController.cancel = { [weak self] in
            self?.isDeactivating = true
            cancel()
        }
        self.contentController.dismissInput = { [weak self] in
            // Subclass/consumer should resign first responder on the search bar
            self?.onDismissInput?()
        }
    }

    /// Called when the content requests keyboard dismissal without cancelling search.
    public var onDismissInput: (() -> Void)?

    /// Forward search text to the content controller.
    public func updateSearchText(_ text: String) {
        contentController.searchTextUpdated(text: text)
    }

    /// Layout the background and content views within the given bounds.
    public func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let contentFrame = CGRect(
            x: 0,
            y: navigationBarHeight,
            width: layout.size.width,
            height: layout.size.height - navigationBarHeight
        )
        backgroundView.frame = CGRect(origin: .zero, size: layout.size)
        contentController.view.frame = contentFrame
        contentController.containerLayoutUpdated(layout, transition: transition)
    }

    /// Animate the search UI in.
    public func activate(insertIn container: UIView, above: UIView?) {
        if let above {
            container.insertSubview(backgroundView, aboveSubview: above)
        } else {
            container.addSubview(backgroundView)
        }
        container.addSubview(contentController.view)

        UIView.animate(withDuration: 0.25) {
            self.backgroundView.alpha = 1.0
        }
    }

    /// Animate the search UI out and remove from hierarchy.
    public func deactivate(animated: Bool) {
        isDeactivating = true
        let cleanup = {
            self.backgroundView.removeFromSuperview()
            self.contentController.view.removeFromSuperview()
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: {
                self.backgroundView.alpha = 0.0
                self.contentController.view.alpha = 0.0
            }, completion: { _ in
                cleanup()
                self.contentController.view.alpha = 1.0
            })
        } else {
            self.backgroundView.alpha = 0.0
            cleanup()
        }
    }

    @objc private func backgroundTapped() {
        cancel()
    }
}

// MARK: - Search Content Controller

/// Base class for search result controllers used with `CrystalSearchDisplayController`.
///
/// Subclass and override `searchTextUpdated(text:)` to filter/fetch results.
open class CrystalSearchContentController: UIViewController {

    /// Called when search text changes.
    open func searchTextUpdated(text: String) {
    }

    /// Layout update from the search display controller.
    open func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
    }

    /// Set by the display controller — call to dismiss the entire search.
    public var cancel: (() -> Void)?

    /// Set by the display controller — call to just dismiss keyboard.
    public var dismissInput: (() -> Void)?
}
