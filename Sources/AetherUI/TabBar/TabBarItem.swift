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

public typealias SearchTabBarItem = UITabBarItem
