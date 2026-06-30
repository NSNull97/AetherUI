import UIKit

/// Tab bar item configuration.
public final class AetherTabBarItem {
    public let title: String
    public let image: UIImage?
    public let selectedImage: UIImage?
    public var badgeValue: String?
    public var isEnabled: Bool

    public init(title: String, image: UIImage?, selectedImage: UIImage? = nil, badgeValue: String? = nil, isEnabled: Bool = true) {
        self.title = title
        self.image = image
        self.selectedImage = selectedImage ?? image
        self.badgeValue = badgeValue
        self.isEnabled = isEnabled
    }
}

/// Configuration for the standalone search control shown next to the tab bar pill.
public final class SearchTabItem: UITabBarItem {
    public var action: (() -> Void)?

    public init(
        image: UIImage? = UIImage(systemName: "magnifyingglass"),
        selectedImage: UIImage? = nil,
        action: (() -> Void)? = nil
    ) {
        self.action = action
        super.init()
        self.image = image
        self.selectedImage = selectedImage ?? image
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
