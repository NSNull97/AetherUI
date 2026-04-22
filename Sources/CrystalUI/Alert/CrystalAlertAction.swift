import UIKit

public struct CrystalAlertAction {
    public enum Style {
        /// Secondary/neutral action — grey pill, primary text color.
        case secondary
        /// Primary CTA — blue filled capsule, white text. Use this for the
        /// button that triggers on Enter.
        case primary
        /// Red destructive — grey pill, red text.
        case destructive

        /// Back-compat aliases for the previous API.
        public static let `default` = Style.secondary
        public static let defaultFocused = Style.primary
    }

    public let title: String
    public let style: Style
    public let enabled: Bool
    public let handler: () -> Void

    public init(
        title: String,
        style: Style = .secondary,
        enabled: Bool = true,
        handler: @escaping () -> Void = {}
    ) {
        self.title = title
        self.style = style
        self.enabled = enabled
        self.handler = handler
    }
}

public struct CrystalAlertTextField {
    /// Optional label rendered above the text field input row.
    public let label: String?
    /// Placeholder shown when the field is empty.
    public let placeholder: String
    public let initialText: String
    public let isSecureTextEntry: Bool
    public let keyboardType: UIKeyboardType
    /// Fires as the user types.
    public let onChanged: (String) -> Void

    public init(
        label: String? = nil,
        placeholder: String = "",
        initialText: String = "",
        isSecureTextEntry: Bool = false,
        keyboardType: UIKeyboardType = .default,
        onChanged: @escaping (String) -> Void = { _ in }
    ) {
        self.label = label
        self.placeholder = placeholder
        self.initialText = initialText
        self.isSecureTextEntry = isSecureTextEntry
        self.keyboardType = keyboardType
        self.onChanged = onChanged
    }
}
