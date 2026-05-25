import UIKit
import AssociatedObject

private extension UIBarButtonItem {
    @AssociatedObject(.retain(.nonatomic))
    var aetherContextMenuProviderBox: AetherContextMenuProviderBox?

    @AssociatedObject(.retain(.nonatomic))
    var aetherSeparatesSharedBackground: Bool = false
}

// MARK: - UIBarButtonItem + ContextMenu

/// Mirrors UIKit's modern `UIBarButtonItem(title:image:primaryAction:menu:)`
/// init but takes a AetherUI-flavoured `contextMenuItemsProvider` instead
/// of `UIMenu` — so a bar item can drop a `ContextMenuController` (with
/// our custom glass surface, headers, action rows, submenus) without the
/// caller wiring up `UIBarButtonItem(customView:)` + a button + a long-
/// press recognizer by hand.
///
/// **Behaviour.** When `contextMenuItemsProvider` is non-nil, tapping the
/// bar item opens the AetherUI context menu, anchored to the bar item's
/// glass capsule. `primaryAction` is preserved on the underlying
/// `UIBarButtonItem` (so accessibility / menu builders still see it),
/// but the navbar's tap handler routes through the menu first — exactly
/// how UIKit's own `UIBarButtonItem.menu` overrides tap when set.
///
/// **How the navbar finds the provider.** Stored as an associated object
/// on the bar item. `NavigationBarImpl`'s glass-button layout reads it
/// (`item.contextMenuItemsProvider`)
/// and replaces the `GlassControlGroup` action with a "show menu" closure
/// when present.
public extension UIBarButtonItem {
    /// Convenience for "title/image bar item that opens a AetherUI
    /// context menu on tap". `primaryAction` is optional and preserved
    /// for non-tap entry points (accessibility, keyboard activation).
    convenience init(
        title: String? = nil,
        image: UIImage? = nil,
        primaryAction: UIAction? = nil,
        contextMenuItemsProvider: (() -> [ContextMenuItem])? = nil
    ) {
        if #available(iOS 14.0, *) {
            self.init(title: title, image: image, primaryAction: primaryAction, menu: nil)
        } else if let image = image {
            // iOS 13 fallback — `primaryAction` is dropped (the
            // closure-style action API is iOS 14+). Bar-button items
            // on iOS 13 dispatch via `target`/`action`; callers who
            // need a primary action there can wire it after init via
            // `target` / `action`.
            self.init(image: image, style: .plain, target: nil, action: nil)
        } else {
            self.init(title: title ?? "", style: .plain, target: nil, action: nil)
        }
        self.contextMenuItemsProvider = contextMenuItemsProvider
    }

    /// Provider closure that returns the menu items to show when the
    /// bar item is tapped. Stored as an associated object so attaching
    /// it doesn't require subclassing `UIBarButtonItem` and survives
    /// any `UINavigationItem` round-trips.
    ///
    /// Set this on a bar item created with any of UIKit's existing
    /// inits to get the same "tap → AetherUI context menu" behaviour
    /// without using the dedicated convenience init above.
    var contextMenuItemsProvider: (() -> [ContextMenuItem])? {
        get {
            aetherContextMenuProviderBox?.provider
        }
        set {
            aetherContextMenuProviderBox = newValue.map(AetherContextMenuProviderBox.init(provider:))
        }
    }

    /// AetherUI equivalent of iOS 26's `hidesSharedBackground`.
    ///
    /// When true, this bar item is rendered in its own floating glass
    /// background instead of being merged into the adjacent shared capsule.
    /// Set it on the `UIBarButtonItem` before assigning it through
    /// `navigationItem.leftBarButtonItems` / `rightBarButtonItems`.
    var separatesSharedBackground: Bool {
        get {
            aetherSeparatesSharedBackground
        }
        set {
            aetherSeparatesSharedBackground = newValue
        }
    }
}

/// Box around the `() -> [ContextMenuItem]` closure so the associated
/// object stores a stable reference-typed value.
private final class AetherContextMenuProviderBox {
    let provider: () -> [ContextMenuItem]
    init(provider: @escaping () -> [ContextMenuItem]) {
        self.provider = provider
    }
}
