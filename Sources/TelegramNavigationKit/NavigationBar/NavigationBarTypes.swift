import UIKit

// MARK: - NavigationBar Style

public enum NavigationBarStyle {
    case legacy
    case glass
}

public enum NavigationBarGlassStyle {
    case `default`
    case clear
}

// MARK: - Navigation Bar Theme

public final class NavigationBarTheme {
    public let overallDarkAppearance: Bool
    public let buttonColor: UIColor
    public let disabledButtonColor: UIColor
    public let primaryTextColor: UIColor
    public let backgroundColor: UIColor
    public let opaqueBackgroundColor: UIColor
    public let enableBackgroundBlur: Bool
    public let separatorColor: UIColor
    public let badgeBackgroundColor: UIColor
    public let badgeStrokeColor: UIColor
    public let badgeTextColor: UIColor
    public let edgeEffectColor: UIColor?
    public let accentButtonColor: UIColor
    public let accentForegroundColor: UIColor
    public let style: NavigationBarStyle
    public let glassStyle: NavigationBarGlassStyle

    // Edge effect (scroll-content frost at nav bar boundary)
    public let edgeEffectAlpha: CGFloat
    public let edgeEffectBlurRadius: CGFloat

    // Layout
    public let defaultContentHeight: CGFloat

    public init(
        overallDarkAppearance: Bool = false,
        buttonColor: UIColor = .systemBlue,
        disabledButtonColor: UIColor = .gray,
        primaryTextColor: UIColor = .black,
        backgroundColor: UIColor = .white,
        opaqueBackgroundColor: UIColor? = nil,
        enableBackgroundBlur: Bool = true,
        separatorColor: UIColor = UIColor(white: 0.0, alpha: 0.3),
        badgeBackgroundColor: UIColor = .systemRed,
        badgeStrokeColor: UIColor = .white,
        badgeTextColor: UIColor = .white,
        edgeEffectColor: UIColor? = nil,
        accentButtonColor: UIColor = .systemBlue,
        accentForegroundColor: UIColor = .white,
        style: NavigationBarStyle = .legacy,
        glassStyle: NavigationBarGlassStyle = .default,
        edgeEffectAlpha: CGFloat = 0.65,
        edgeEffectBlurRadius: CGFloat = 3.0,
        defaultContentHeight: CGFloat = 60.0
    ) {
        self.overallDarkAppearance = overallDarkAppearance
        self.buttonColor = buttonColor
        self.disabledButtonColor = disabledButtonColor
        self.primaryTextColor = primaryTextColor
        self.backgroundColor = backgroundColor
        self.opaqueBackgroundColor = opaqueBackgroundColor ?? backgroundColor
        self.enableBackgroundBlur = enableBackgroundBlur
        self.separatorColor = separatorColor
        self.badgeBackgroundColor = badgeBackgroundColor
        self.badgeStrokeColor = badgeStrokeColor
        self.badgeTextColor = badgeTextColor
        self.edgeEffectColor = edgeEffectColor
        self.accentButtonColor = accentButtonColor
        self.accentForegroundColor = accentForegroundColor
        self.style = style
        self.glassStyle = glassStyle
        self.edgeEffectAlpha = edgeEffectAlpha
        self.edgeEffectBlurRadius = edgeEffectBlurRadius
        self.defaultContentHeight = defaultContentHeight
    }

    public func withUpdatedBackgroundColor(_ color: UIColor) -> NavigationBarTheme {
        return NavigationBarTheme(overallDarkAppearance: overallDarkAppearance, buttonColor: buttonColor, disabledButtonColor: disabledButtonColor, primaryTextColor: primaryTextColor, backgroundColor: color, opaqueBackgroundColor: opaqueBackgroundColor, enableBackgroundBlur: false, separatorColor: separatorColor, badgeBackgroundColor: badgeBackgroundColor, badgeStrokeColor: badgeStrokeColor, badgeTextColor: badgeTextColor, edgeEffectColor: edgeEffectColor, accentButtonColor: accentButtonColor, accentForegroundColor: accentForegroundColor, style: style, glassStyle: glassStyle)
    }

    public func withUpdatedSeparatorColor(_ color: UIColor) -> NavigationBarTheme {
        return NavigationBarTheme(overallDarkAppearance: overallDarkAppearance, buttonColor: buttonColor, disabledButtonColor: disabledButtonColor, primaryTextColor: primaryTextColor, backgroundColor: backgroundColor, opaqueBackgroundColor: opaqueBackgroundColor, enableBackgroundBlur: enableBackgroundBlur, separatorColor: color, badgeBackgroundColor: badgeBackgroundColor, badgeStrokeColor: badgeStrokeColor, badgeTextColor: badgeTextColor, edgeEffectColor: edgeEffectColor, accentButtonColor: accentButtonColor, accentForegroundColor: accentForegroundColor, style: style, glassStyle: glassStyle)
    }

    public static func liquidGlass(
        overallDarkAppearance: Bool = false,
        buttonColor: UIColor = .label,
        primaryTextColor: UIColor = .label,
        accentButtonColor: UIColor = .systemBlue,
        accentForegroundColor: UIColor = .white,
        glassStyle: NavigationBarGlassStyle = .default
    ) -> NavigationBarTheme {
        return NavigationBarTheme(
            overallDarkAppearance: overallDarkAppearance,
            buttonColor: buttonColor,
            disabledButtonColor: UIColor.secondaryLabel,
            primaryTextColor: primaryTextColor,
            backgroundColor: .clear,
            opaqueBackgroundColor: UIColor.systemBackground,
            enableBackgroundBlur: true,
            separatorColor: .clear,
            badgeBackgroundColor: .systemRed,
            badgeStrokeColor: UIColor.systemBackground,
            badgeTextColor: .white,
            edgeEffectColor: nil,
            accentButtonColor: accentButtonColor,
            accentForegroundColor: accentForegroundColor,
            style: .glass,
            glassStyle: glassStyle
        )
    }

    public static func generateBackArrowImage(color: UIColor) -> UIImage? {
        return generateImage(CGSize(width: 13.0, height: 22.0), rotatedContext: { size, context in
            context.clear(CGRect(origin: .zero, size: size))
            context.setFillColor(color.cgColor)
            context.translateBy(x: 0.0, y: -UIScreenPixel)
            let _ = try? drawSvgPath(context, path: "M3.60751322,11.5 L11.5468531,3.56066017 C12.1326395,2.97487373 12.1326395,2.02512627 11.5468531,1.43933983 C10.9610666,0.853553391 10.0113191,0.853553391 9.42553271,1.43933983 L0.449102936,10.4157696 C-0.149700979,11.0145735 -0.149700979,11.9854265 0.449102936,12.5842304 L9.42553271,21.5606602 C10.0113191,22.1464466 10.9610666,22.1464466 11.5468531,21.5606602 C12.1326395,20.9748737 12.1326395,20.0251263 11.5468531,19.4393398 L3.60751322,11.5 Z ")
        })
    }
}

// MARK: - Strings

public final class NavigationBarStrings {
    public let back: String
    public let close: String

    public init(back: String = "Back", close: String = "Close") {
        self.back = back
        self.close = close
    }
}

// MARK: - Presentation Data

public final class NavigationBarPresentationData {
    public let theme: NavigationBarTheme
    public let strings: NavigationBarStrings

    public init(theme: NavigationBarTheme, strings: NavigationBarStrings = NavigationBarStrings()) {
        self.theme = theme
        self.strings = strings
    }
}

// MARK: - Previous Action

public enum NavigationPreviousAction: Equatable {
    case item(UINavigationItem)
    case close

    public static func ==(lhs: NavigationPreviousAction, rhs: NavigationPreviousAction) -> Bool {
        switch lhs {
        case let .item(lhsItem):
            if case let .item(rhsItem) = rhs, lhsItem === rhsItem {
                return true
            }
            return false
        case .close:
            if case .close = rhs { return true }
            return false
        }
    }
}

// MARK: - Content Mode

public enum NavigationBarContentMode {
    case replacement
    case expansion
}

// MARK: - Back Arrow Cache

private var backArrowImageCache: [Int32: UIImage] = [:]

public func navigationBarBackArrowImage(color: UIColor) -> UIImage? {
    var red: CGFloat = 0.0
    var green: CGFloat = 0.0
    var blue: CGFloat = 0.0
    var alpha: CGFloat = 0.0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

    let key = (Int32(alpha * 255.0) << 24) | (Int32(red * 255.0) << 16) | (Int32(green * 255.0) << 8) | Int32(blue * 255.0)
    if let image = backArrowImageCache[key] {
        return image
    } else if let image = NavigationBarTheme.generateBackArrowImage(color: color) {
        backArrowImageCache[key] = image
        return image
    }
    return nil
}
