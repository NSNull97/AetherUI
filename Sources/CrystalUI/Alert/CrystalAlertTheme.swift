import UIKit

public struct CrystalAlertTheme: Equatable {
    public let backgroundType: CrystalActionSheetBackgroundType
    public let backgroundColor: UIColor
    public let separatorColor: UIColor
    public let highlightedItemColor: UIColor
    public let primaryColor: UIColor
    public let secondaryColor: UIColor
    public let accentColor: UIColor
    public let destructiveColor: UIColor
    public let disabledColor: UIColor
    public let dimColor: UIColor
    /// Fill color for secondary/destructive pill buttons and text-field
    /// backgrounds — the "grey rounded pill" chrome.
    public let pillFillColor: UIColor
    /// Fill for the primary CTA pill (iOS blue by default).
    public let primaryFillColor: UIColor
    /// Text color inside the primary pill.
    public let primaryTextColor: UIColor
    public let baseFontSize: CGFloat

    public init(
        backgroundType: CrystalActionSheetBackgroundType,
        backgroundColor: UIColor,
        separatorColor: UIColor,
        highlightedItemColor: UIColor,
        primaryColor: UIColor,
        secondaryColor: UIColor,
        accentColor: UIColor,
        destructiveColor: UIColor,
        disabledColor: UIColor,
        dimColor: UIColor,
        pillFillColor: UIColor,
        primaryFillColor: UIColor,
        primaryTextColor: UIColor,
        baseFontSize: CGFloat = 17.0
    ) {
        self.backgroundType = backgroundType
        self.backgroundColor = backgroundColor
        self.separatorColor = separatorColor
        self.highlightedItemColor = highlightedItemColor
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.accentColor = accentColor
        self.destructiveColor = destructiveColor
        self.disabledColor = disabledColor
        self.dimColor = dimColor
        self.pillFillColor = pillFillColor
        self.primaryFillColor = primaryFillColor
        self.primaryTextColor = primaryTextColor
        self.baseFontSize = baseFontSize
    }

    public static let light = CrystalAlertTheme(
        backgroundType: .light,
        backgroundColor: UIColor.white.withAlphaComponent(0.92),
        separatorColor: UIColor(white: 0.0, alpha: 0.12),
        highlightedItemColor: UIColor(white: 0.8, alpha: 0.6),
        primaryColor: .black,
        secondaryColor: UIColor(white: 0.3, alpha: 1.0),
        accentColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
        destructiveColor: UIColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0),
        disabledColor: UIColor(white: 0.6, alpha: 1.0),
        dimColor: UIColor(white: 0.0, alpha: 0.4),
        pillFillColor: UIColor(white: 0.86, alpha: 1.0),
        primaryFillColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
        primaryTextColor: .white
    )

    public static let dark = CrystalAlertTheme(
        backgroundType: .dark,
        backgroundColor: UIColor(white: 0.15, alpha: 0.92),
        separatorColor: UIColor(white: 1.0, alpha: 0.15),
        highlightedItemColor: UIColor(white: 0.3, alpha: 0.6),
        primaryColor: .white,
        secondaryColor: UIColor(white: 0.75, alpha: 1.0),
        accentColor: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0),
        destructiveColor: UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1.0),
        disabledColor: UIColor(white: 0.5, alpha: 1.0),
        dimColor: UIColor(white: 0.0, alpha: 0.5),
        pillFillColor: UIColor(white: 0.28, alpha: 1.0),
        primaryFillColor: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0),
        primaryTextColor: .white
    )

    /// System-driven theme: text / pill colors track
    /// `UITraitCollection.userInterfaceStyle` so the alert flips between
    /// light and dark automatically when the system appearance changes.
    /// Colors are UIColor dynamic providers — the resolver runs every
    /// time the view resolves its trait collection.
    public static let system = CrystalAlertTheme(
        backgroundType: .light,
        backgroundColor: UIColor { tc in tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.15, alpha: 0.92)
            : UIColor.white.withAlphaComponent(0.92) },
        separatorColor: .separator,
        highlightedItemColor: UIColor { tc in tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.3, alpha: 0.6)
            : UIColor(white: 0.8, alpha: 0.6) },
        primaryColor: .label,
        secondaryColor: .secondaryLabel,
        accentColor: .systemBlue,
        destructiveColor: .systemRed,
        disabledColor: .tertiaryLabel,
        dimColor: UIColor { tc in tc.userInterfaceStyle == .dark
            ? UIColor(white: 0.0, alpha: 0.5)
            : UIColor(white: 0.0, alpha: 0.4) },
        pillFillColor: .tertiarySystemFill,
        primaryFillColor: .systemBlue,
        primaryTextColor: .white
    )
}
