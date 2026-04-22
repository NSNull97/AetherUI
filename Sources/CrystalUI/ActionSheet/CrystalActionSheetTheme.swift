import UIKit

public enum CrystalActionSheetBackgroundType: Equatable {
    case light
    case dark
}

public struct CrystalActionSheetTheme: Equatable {
    public let dimColor: UIColor
    public let backgroundType: CrystalActionSheetBackgroundType
    public let itemBackgroundColor: UIColor
    public let itemHighlightedBackgroundColor: UIColor
    public let standardActionTextColor: UIColor
    public let destructiveActionTextColor: UIColor
    public let disabledActionTextColor: UIColor
    public let primaryTextColor: UIColor
    public let secondaryTextColor: UIColor
    public let controlAccentColor: UIColor
    public let controlColor: UIColor
    public let separatorColor: UIColor
    public let baseFontSize: CGFloat

    public init(
        dimColor: UIColor,
        backgroundType: CrystalActionSheetBackgroundType,
        itemBackgroundColor: UIColor,
        itemHighlightedBackgroundColor: UIColor,
        standardActionTextColor: UIColor,
        destructiveActionTextColor: UIColor,
        disabledActionTextColor: UIColor,
        primaryTextColor: UIColor,
        secondaryTextColor: UIColor,
        controlAccentColor: UIColor,
        controlColor: UIColor,
        separatorColor: UIColor,
        baseFontSize: CGFloat = 17.0
    ) {
        self.dimColor = dimColor
        self.backgroundType = backgroundType
        self.itemBackgroundColor = itemBackgroundColor
        self.itemHighlightedBackgroundColor = itemHighlightedBackgroundColor
        self.standardActionTextColor = standardActionTextColor
        self.destructiveActionTextColor = destructiveActionTextColor
        self.disabledActionTextColor = disabledActionTextColor
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.controlAccentColor = controlAccentColor
        self.controlColor = controlColor
        self.separatorColor = separatorColor
        self.baseFontSize = min(26.0, baseFontSize)
    }

    public static let light = CrystalActionSheetTheme(
        dimColor: UIColor(white: 0.0, alpha: 0.4),
        backgroundType: .light,
        itemBackgroundColor: UIColor.white.withAlphaComponent(0.8),
        itemHighlightedBackgroundColor: UIColor(white: 0.9, alpha: 0.8),
        standardActionTextColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
        destructiveActionTextColor: UIColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0),
        disabledActionTextColor: UIColor(white: 0.6, alpha: 1.0),
        primaryTextColor: .black,
        secondaryTextColor: UIColor(white: 0.4, alpha: 1.0),
        controlAccentColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
        controlColor: UIColor(white: 0.7, alpha: 1.0),
        separatorColor: UIColor(white: 0.0, alpha: 0.1)
    )

    public static let dark = CrystalActionSheetTheme(
        dimColor: UIColor(white: 0.0, alpha: 0.5),
        backgroundType: .dark,
        itemBackgroundColor: UIColor(white: 0.13, alpha: 0.85),
        itemHighlightedBackgroundColor: UIColor(white: 0.22, alpha: 0.85),
        standardActionTextColor: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0),
        destructiveActionTextColor: UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1.0),
        disabledActionTextColor: UIColor(white: 0.5, alpha: 1.0),
        primaryTextColor: .white,
        secondaryTextColor: UIColor(white: 0.7, alpha: 1.0),
        controlAccentColor: UIColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 1.0),
        controlColor: UIColor(white: 0.3, alpha: 1.0),
        separatorColor: UIColor(white: 1.0, alpha: 0.1)
    )
}
