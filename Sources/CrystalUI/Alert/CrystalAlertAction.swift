import UIKit

public struct CrystalAlertAction {
    public enum Style {
        /// Standard accent-colored button.
        case `default`
        /// Bolded "OK"-equivalent — use for the button that triggers on Enter.
        case defaultFocused
        /// Red destructive button.
        case destructive
    }

    public let title: String
    public let style: Style
    public let enabled: Bool
    public let handler: () -> Void

    public init(
        title: String,
        style: Style = .default,
        enabled: Bool = true,
        handler: @escaping () -> Void = {}
    ) {
        self.title = title
        self.style = style
        self.enabled = enabled
        self.handler = handler
    }
}
