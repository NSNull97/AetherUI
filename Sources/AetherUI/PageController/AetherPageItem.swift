import Foundation

public final class AetherPageItem {
    internal var contentDidChange: (() -> Void)?
    internal var selectionRequested: ((Bool) -> Void)?
    private var storedIsSelected = false

    public var title: String? {
        didSet {
            guard title != oldValue else { return }
            contentDidChange?()
        }
    }

    public var badgeValue: String? {
        didSet {
            guard badgeValue != oldValue else { return }
            contentDidChange?()
        }
    }

    public var isSelected: Bool {
        storedIsSelected
    }

    public init(title: String? = nil, badgeValue: String? = nil) {
        self.title = title
        self.badgeValue = badgeValue
    }

    public func select(animated: Bool = true) {
        selectionRequested?(animated)
    }

    internal func setIsSelected(_ isSelected: Bool) {
        storedIsSelected = isSelected
    }
}
