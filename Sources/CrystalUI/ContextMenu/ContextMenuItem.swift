import UIKit

// MARK: - ContextMenuItem

/// Items that can appear in a `ContextMenuController` list.
///
/// Port-inspired by Telegram `ContextMenuItem`, boiled down to the states
/// the Telegram client renders in its navbar menus: a header, one or more
/// action rows optionally marked with a checkmark, and thin separators
/// between groups.
public enum ContextMenuItem {
    /// Plain grey header label ("Последняя", "Settings", etc.).
    case header(title: String)
    /// A tappable row with a leading checkmark, trailing icon, and destructive styling.
    case action(ContextMenuActionItem)
    /// Thin inset hairline separator between groups.
    case separator
}

// MARK: - ContextMenuActionItem

public struct ContextMenuActionItem {
    public enum TextColor: Equatable {
        case primary
        case destructive
    }

    public enum IconSide: Equatable {
        case leading
        case trailing
    }

    public let id: AnyHashable
    public let title: String
    public let subtitle: String?
    public let icon: UIImage?
    public let iconSide: IconSide
    public let textColor: TextColor
    public let isSelected: Bool
    public let isEnabled: Bool
    public let action: ((ContextMenuActionItem, ContextMenuDismissHandle) -> Void)?

    /// If non-nil, tapping this row pushes a new menu page containing
    /// `submenu` instead of invoking `action`. The row renders with a
    /// trailing chevron (`chevron.right`) and its title is reused as the
    /// back-button label on the pushed page. `action` is ignored when a
    /// submenu is present.
    public let submenu: [ContextMenuItem]?

    public init(
        id: AnyHashable = UUID(),
        title: String,
        subtitle: String? = nil,
        icon: UIImage? = nil,
        iconSide: IconSide = .trailing,
        textColor: TextColor = .primary,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        submenu: [ContextMenuItem]? = nil,
        action: ((ContextMenuActionItem, ContextMenuDismissHandle) -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconSide = iconSide
        self.textColor = textColor
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.submenu = submenu
        self.action = action
    }
}

// MARK: - Dismiss handle

/// Handed to action callbacks so they can explicitly dismiss the menu.
public final class ContextMenuDismissHandle {
    private let dismissImpl: (Bool) -> Void

    init(dismiss: @escaping (Bool) -> Void) {
        self.dismissImpl = dismiss
    }

    public func dismiss(animated: Bool = true) {
        dismissImpl(animated)
    }
}
