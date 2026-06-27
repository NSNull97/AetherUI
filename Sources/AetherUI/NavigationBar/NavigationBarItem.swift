import UIKit

public enum NavigationBarTitleViewStyle: Equatable {
    case regular
    case glass
}

/// Navigation data consumed by AetherUI's custom navigation bar.
///
/// Standard UIKit fields are mirrored through the wrapped `UINavigationItem`
/// so existing `navigationItem.title` and bar button assignments keep working.
/// Custom navigation-bar chrome lives here instead of extending `UINavigationItem`.
public final class NavigationBarItem {
    internal let backingItem: UINavigationItem

    internal static let contentDidChangeNotification = Notification.Name("NavigationBarItemContentDidChange")
    internal static let defaultTopBarAccessoryTransition: ContainedViewLayoutTransition = .immediate

    internal var searchBarControllerChanged: ((AetherSearchController?, AetherSearchController?) -> Void)?
    internal var topBarAccessoryChanged: ((NavigationBarContentView?, NavigationBarContentView?, ContainedViewLayoutTransition) -> Void)?
    internal var chromeContentDidChange: (() -> Void)?

    private var storedSubtitle: String?
    private var storedTitleViewStyle: NavigationBarTitleViewStyle = .regular
    private var storedSearchBarController: AetherSearchController?
    private var storedTopBarAccessory: NavigationBarContentView?

    public init(navigationItem: UINavigationItem = UINavigationItem()) {
        self.backingItem = navigationItem
    }

    public var title: String? {
        get { backingItem.title }
        set {
            guard backingItem.title != newValue else { return }
            backingItem.title = newValue
            notifyContentDidChange()
        }
    }

    public var titleView: UIView? {
        get { backingItem.titleView }
        set {
            guard backingItem.titleView !== newValue else { return }
            backingItem.titleView = newValue
            notifyContentDidChange()
        }
    }

    public var leftBarButtonItems: [UIBarButtonItem]? {
        get { backingItem.leftBarButtonItems }
        set {
            backingItem.leftBarButtonItems = newValue
            notifyContentDidChange()
        }
    }

    public var rightBarButtonItems: [UIBarButtonItem]? {
        get { backingItem.rightBarButtonItems }
        set {
            backingItem.rightBarButtonItems = newValue
            notifyContentDidChange()
        }
    }

    public var leftBarButtonItem: UIBarButtonItem? {
        get { backingItem.leftBarButtonItem }
        set {
            backingItem.leftBarButtonItem = newValue
            notifyContentDidChange()
        }
    }

    public var rightBarButtonItem: UIBarButtonItem? {
        get { backingItem.rightBarButtonItem }
        set {
            backingItem.rightBarButtonItem = newValue
            notifyContentDidChange()
        }
    }

    public var subtitle: String? {
        get { storedSubtitle }
        set {
            guard storedSubtitle != newValue else { return }
            storedSubtitle = newValue
            notifyContentDidChange()
        }
    }

    public var titleViewStyle: NavigationBarTitleViewStyle {
        get { storedTitleViewStyle }
        set {
            guard storedTitleViewStyle != newValue else { return }
            storedTitleViewStyle = newValue
            notifyContentDidChange()
        }
    }

    /// Search controller attached to the navigation bar.
    public var searchBarController: AetherSearchController? {
        get { storedSearchBarController }
        set {
            let oldValue = storedSearchBarController
            guard oldValue !== newValue else { return }
            storedSearchBarController = newValue
            searchBarControllerChanged?(oldValue, newValue)
        }
    }

    /// Custom content installed below the navigation title row.
    public var topBarAccessory: NavigationBarContentView? {
        get { storedTopBarAccessory }
        set {
            setTopBarAccessory(newValue, transition: Self.defaultTopBarAccessoryTransition)
        }
    }

    public func setTopBarAccessory(_ accessory: NavigationBarContentView?, animated: Bool) {
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.3, curve: .easeInOut) : .immediate
        setTopBarAccessory(accessory, transition: transition)
    }

    public func setTopBarAccessory(_ accessory: NavigationBarContentView?, transition: ContainedViewLayoutTransition) {
        let oldValue = storedTopBarAccessory
        guard oldValue !== accessory else { return }
        storedTopBarAccessory = accessory
        topBarAccessoryChanged?(oldValue, accessory, transition)
    }

    internal func notifyContentDidChange() {
        NotificationCenter.default.post(name: Self.contentDidChangeNotification, object: self)
        chromeContentDidChange?()
    }
}
