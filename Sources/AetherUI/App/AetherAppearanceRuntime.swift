import UIKit

private enum AetherAppearanceRuntimeCurrentStorage {
    static let key = "AetherUI.AetherAppearance.runtimeCurrent"
}

// MARK: - App Appearance

public enum AetherAppearanceStyle: Equatable, Sendable {
    case iOS26
    case iOS27
}

public struct AetherAppearance {
    public var style: AetherAppearanceStyle
    public var overallDarkAppearance: Bool
    public var emptyAreaColor: UIColor
    public var edgeEffectColor: UIColor
    public var edgeEffectAlpha: CGFloat
    public var edgeEffectBlurRadiusAtEdge: CGFloat
    public var edgeEffectBlurRadiusAtFade: CGFloat
    public var edgeEffectStyle: SystemGlassEffectStyle
    public var separatorColor: UIColor

    public init(
        style: AetherAppearanceStyle,
        overallDarkAppearance: Bool,
        emptyAreaColor: UIColor,
        edgeEffectColor: UIColor,
        edgeEffectAlpha: CGFloat,
        edgeEffectBlurRadiusAtEdge: CGFloat,
        edgeEffectBlurRadiusAtFade: CGFloat,
        edgeEffectStyle: SystemGlassEffectStyle,
        separatorColor: UIColor
    ) {
        self.style = style
        self.overallDarkAppearance = overallDarkAppearance
        self.emptyAreaColor = emptyAreaColor
        self.edgeEffectColor = edgeEffectColor
        self.edgeEffectAlpha = edgeEffectAlpha
        self.edgeEffectBlurRadiusAtEdge = edgeEffectBlurRadiusAtEdge
        self.edgeEffectBlurRadiusAtFade = edgeEffectBlurRadiusAtFade
        self.edgeEffectStyle = edgeEffectStyle
        self.separatorColor = separatorColor
    }

    public init(style: AetherAppearanceStyle) {
        switch style {
        case .iOS26:
            self.init(
                style: .iOS26,
                overallDarkAppearance: false,
                emptyAreaColor: .systemBackground,
                edgeEffectColor: .systemBackground,
                edgeEffectAlpha: 0.82,
                edgeEffectBlurRadiusAtEdge: 2.0,
                edgeEffectBlurRadiusAtFade: 0.0,
                edgeEffectStyle: .regular,
                separatorColor: .separator
            )
        case .iOS27:
            self.init(
                style: .iOS27,
                overallDarkAppearance: false,
                emptyAreaColor: .systemBackground,
                edgeEffectColor: .systemBackground,
                edgeEffectAlpha: 0.82,
                edgeEffectBlurRadiusAtEdge: 5.0,
                edgeEffectBlurRadiusAtFade: 5.0,
                edgeEffectStyle: .strong,
                separatorColor: .separator
            )
        }
    }

    public static let iOS26 = AetherAppearance(style: .iOS26)
    public static let iOS27 = AetherAppearance(style: .iOS27)

    public static func preset(_ style: AetherAppearanceStyle) -> AetherAppearance {
        AetherAppearance(style: style)
    }

    public var signature: AetherAppearanceSignature {
        AetherAppearanceSignature(appearance: self)
    }
}

public struct AetherAppearanceSignature: Equatable, Sendable {
    public var style: AetherAppearanceStyle
    public var overallDarkAppearance: Bool
    public var emptyAreaColor: String
    public var edgeEffectColor: String
    public var edgeEffectAlpha: CGFloat
    public var edgeEffectBlurRadiusAtEdge: CGFloat
    public var edgeEffectBlurRadiusAtFade: CGFloat
    public var edgeEffectStyle: SystemGlassEffectStyle
    public var separatorColor: String

    public init(appearance: AetherAppearance, traitCollection: UITraitCollection = UITraitCollection(userInterfaceStyle: .unspecified)) {
        self.style = appearance.style
        self.overallDarkAppearance = appearance.overallDarkAppearance
        self.emptyAreaColor = Self.colorSignature(appearance.emptyAreaColor, traitCollection: traitCollection)
        self.edgeEffectColor = Self.colorSignature(appearance.edgeEffectColor, traitCollection: traitCollection)
        self.edgeEffectAlpha = appearance.edgeEffectAlpha
        self.edgeEffectBlurRadiusAtEdge = appearance.edgeEffectBlurRadiusAtEdge
        self.edgeEffectBlurRadiusAtFade = appearance.edgeEffectBlurRadiusAtFade
        self.edgeEffectStyle = appearance.edgeEffectStyle
        self.separatorColor = Self.colorSignature(appearance.separatorColor, traitCollection: traitCollection)
    }

    private static func colorSignature(_ color: UIColor, traitCollection: UITraitCollection) -> String {
        let resolved = color.resolvedColor(with: traitCollection)
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return "\(red):\(green):\(blue):\(alpha)"
        }
        return resolved.description
    }
}

// MARK: - Resolved Surface Primitives

public enum AetherAppearanceSurface: Equatable, Sendable {
    case navigation
    case tab
    case search
    case bottomSearch
    case inputBar
}

public enum AetherBarPlacement: Equatable, Sendable {
    case top
    case bottom
    case navigation
    case tab
    case standaloneBottom
    case inputAccessory
}

public enum AetherBarBackgroundAppearance {
    case none
    case transparent
    case glass(SystemGlassEffectStyle)
    case color(UIColor)
}

public enum AetherGlassStrokeAppearance {
    case none
    case hairline(color: UIColor?, opacity: CGFloat)
}

public enum AetherSeparatorAppearance {
    case hidden
    case visible(color: UIColor?, opacity: CGFloat)
    case scrollActivated(threshold: CGFloat, hysteresis: CGFloat, color: UIColor?)
}

public struct AetherEdgeEffectAppearance {
    public var tintColor: UIColor?
    public var alpha: CGFloat
    public var blurRadiusAtEdge: CGFloat
    public var blurRadiusAtFade: CGFloat
    public var solidBlur: Bool
    public var style: SystemGlassEffectStyle
    public var edgeSize: CGFloat

    public init(
        tintColor: UIColor?,
        alpha: CGFloat,
        blurRadiusAtEdge: CGFloat,
        blurRadiusAtFade: CGFloat,
        solidBlur: Bool = false,
        style: SystemGlassEffectStyle,
        edgeSize: CGFloat = 48.0
    ) {
        self.tintColor = tintColor
        self.alpha = alpha
        self.blurRadiusAtEdge = blurRadiusAtEdge
        self.blurRadiusAtFade = blurRadiusAtFade
        self.solidBlur = solidBlur
        self.style = style
        self.edgeSize = edgeSize
    }

    public init(appearance: AetherAppearance, edgeSize: CGFloat = 48.0) {
        self.init(
            tintColor: appearance.edgeEffectColor,
            alpha: appearance.edgeEffectAlpha,
            blurRadiusAtEdge: appearance.edgeEffectBlurRadiusAtEdge,
            blurRadiusAtFade: appearance.edgeEffectBlurRadiusAtFade,
            solidBlur: appearance.style == .iOS27,
            style: appearance.edgeEffectStyle,
            edgeSize: edgeSize
        )
    }

    public static func transparent(
        style: SystemGlassEffectStyle,
        edgeSize: CGFloat = 48.0
    ) -> AetherEdgeEffectAppearance {
        AetherEdgeEffectAppearance(
            tintColor: .clear,
            alpha: 0.0,
            blurRadiusAtEdge: 0.0,
            blurRadiusAtFade: 0.0,
            solidBlur: true,
            style: style,
            edgeSize: edgeSize
        )
    }
}

public extension AetherAppearance {
    func edgeEffectAppearance(
        for surface: AetherAppearanceSurface,
        edgeSize: CGFloat = 48.0
    ) -> AetherEdgeEffectAppearance {
        if style == .iOS27 {
            switch surface {
            case .tab, .search, .bottomSearch, .inputBar:
                return .transparent(style: edgeEffectStyle, edgeSize: edgeSize)
            case .navigation:
                break
            }
        }
        return AetherEdgeEffectAppearance(appearance: self, edgeSize: edgeSize)
    }
}

public struct AetherNavigationBarResolvedAppearance {
    public var background: AetherBarBackgroundAppearance
    public var stroke: AetherGlassStrokeAppearance
    public var separator: AetherSeparatorAppearance
    public var edgeEffect: AetherEdgeEffectAppearance
    public var overallDarkAppearance: Bool
    public var emptyAreaColor: UIColor
    public var buttonColor: UIColor
    public var primaryTextColor: UIColor

    public init(
        background: AetherBarBackgroundAppearance,
        stroke: AetherGlassStrokeAppearance,
        separator: AetherSeparatorAppearance,
        edgeEffect: AetherEdgeEffectAppearance,
        overallDarkAppearance: Bool,
        emptyAreaColor: UIColor,
        buttonColor: UIColor,
        primaryTextColor: UIColor
    ) {
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.overallDarkAppearance = overallDarkAppearance
        self.emptyAreaColor = emptyAreaColor
        self.buttonColor = buttonColor
        self.primaryTextColor = primaryTextColor
    }
}

public struct AetherTabBarResolvedAppearance {
    public var background: AetherBarBackgroundAppearance
    public var stroke: AetherGlassStrokeAppearance
    public var separator: AetherSeparatorAppearance
    public var edgeEffect: AetherEdgeEffectAppearance
    public var overallDarkAppearance: Bool
    public var iconColor: UIColor
    public var selectedIconColor: UIColor
    public var textColor: UIColor
    public var selectedTextColor: UIColor

    public init(
        background: AetherBarBackgroundAppearance,
        stroke: AetherGlassStrokeAppearance,
        separator: AetherSeparatorAppearance,
        edgeEffect: AetherEdgeEffectAppearance,
        overallDarkAppearance: Bool,
        iconColor: UIColor,
        selectedIconColor: UIColor,
        textColor: UIColor,
        selectedTextColor: UIColor
    ) {
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.overallDarkAppearance = overallDarkAppearance
        self.iconColor = iconColor
        self.selectedIconColor = selectedIconColor
        self.textColor = textColor
        self.selectedTextColor = selectedTextColor
    }
}

public struct AetherSearchResolvedAppearance {
    public var background: AetherBarBackgroundAppearance
    public var stroke: AetherGlassStrokeAppearance
    public var separator: AetherSeparatorAppearance
    public var edgeEffect: AetherEdgeEffectAppearance
    public var overallDarkAppearance: Bool
    public var textColor: UIColor
    public var placeholderColor: UIColor

    public init(
        background: AetherBarBackgroundAppearance,
        stroke: AetherGlassStrokeAppearance,
        separator: AetherSeparatorAppearance,
        edgeEffect: AetherEdgeEffectAppearance,
        overallDarkAppearance: Bool,
        textColor: UIColor,
        placeholderColor: UIColor
    ) {
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.overallDarkAppearance = overallDarkAppearance
        self.textColor = textColor
        self.placeholderColor = placeholderColor
    }
}

public struct AetherInputBarResolvedAppearance {
    public var background: AetherBarBackgroundAppearance
    public var stroke: AetherGlassStrokeAppearance
    public var separator: AetherSeparatorAppearance
    public var edgeEffect: AetherEdgeEffectAppearance
    public var overallDarkAppearance: Bool

    public init(
        background: AetherBarBackgroundAppearance,
        stroke: AetherGlassStrokeAppearance,
        separator: AetherSeparatorAppearance,
        edgeEffect: AetherEdgeEffectAppearance,
        overallDarkAppearance: Bool
    ) {
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.overallDarkAppearance = overallDarkAppearance
    }
}

// MARK: - Overrides

public struct AetherAppearanceOverrideContext {
    public var appearance: AetherAppearance
    public var surface: AetherAppearanceSurface
    public var placement: AetherBarPlacement
    public var traitCollection: UITraitCollection?
    public var viewController: UIViewController?

    public init(
        appearance: AetherAppearance,
        surface: AetherAppearanceSurface,
        placement: AetherBarPlacement,
        traitCollection: UITraitCollection? = nil,
        viewController: UIViewController? = nil
    ) {
        self.appearance = appearance
        self.surface = surface
        self.placement = placement
        self.traitCollection = traitCollection
        self.viewController = viewController
    }
}

public protocol AetherControllerAppearanceProviding: AnyObject {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride?
}

public extension AetherControllerAppearanceProviding {
    func aetherAppearanceOverride(for context: AetherAppearanceOverrideContext) -> AetherAppearanceOverride? {
        nil
    }
}

public struct AetherAppearanceOverride {
    public var navigationBar: AetherNavigationBarAppearanceOverride?
    public var tabBar: AetherTabBarAppearanceOverride?
    public var search: AetherSearchAppearanceOverride?
    public var inputBar: AetherInputBarAppearanceOverride?

    public init(
        navigationBar: AetherNavigationBarAppearanceOverride? = nil,
        tabBar: AetherTabBarAppearanceOverride? = nil,
        search: AetherSearchAppearanceOverride? = nil,
        inputBar: AetherInputBarAppearanceOverride? = nil
    ) {
        self.navigationBar = navigationBar
        self.tabBar = tabBar
        self.search = search
        self.inputBar = inputBar
    }
}

public struct AetherNavigationBarAppearanceOverride {
    public var background: AetherBarBackgroundAppearance?
    public var stroke: AetherGlassStrokeAppearance?
    public var separator: AetherSeparatorAppearance?
    public var edgeEffect: AetherEdgeEffectAppearance?
    public var emptyAreaColor: UIColor?
    public var buttonColor: UIColor?
    public var primaryTextColor: UIColor?

    public init(
        background: AetherBarBackgroundAppearance? = nil,
        stroke: AetherGlassStrokeAppearance? = nil,
        separator: AetherSeparatorAppearance? = nil,
        edgeEffect: AetherEdgeEffectAppearance? = nil,
        emptyAreaColor: UIColor? = nil,
        buttonColor: UIColor? = nil,
        primaryTextColor: UIColor? = nil
    ) {
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.emptyAreaColor = emptyAreaColor
        self.buttonColor = buttonColor
        self.primaryTextColor = primaryTextColor
    }
}

public struct AetherTabBarAppearanceOverride {
    public var background: AetherBarBackgroundAppearance?
    public var stroke: AetherGlassStrokeAppearance?
    public var separator: AetherSeparatorAppearance?
    public var edgeEffect: AetherEdgeEffectAppearance?
    public var iconColor: UIColor?
    public var selectedIconColor: UIColor?
    public var textColor: UIColor?
    public var selectedTextColor: UIColor?

    public init(
        background: AetherBarBackgroundAppearance? = nil,
        stroke: AetherGlassStrokeAppearance? = nil,
        separator: AetherSeparatorAppearance? = nil,
        edgeEffect: AetherEdgeEffectAppearance? = nil,
        iconColor: UIColor? = nil,
        selectedIconColor: UIColor? = nil,
        textColor: UIColor? = nil,
        selectedTextColor: UIColor? = nil
    ) {
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.iconColor = iconColor
        self.selectedIconColor = selectedIconColor
        self.textColor = textColor
        self.selectedTextColor = selectedTextColor
    }
}

public extension AetherTabBarAppearanceOverride {
    func merged(with override: AetherTabBarAppearanceOverride?) -> AetherTabBarAppearanceOverride {
        guard let override else {
            return self
        }
        return AetherTabBarAppearanceOverride(
            background: override.background ?? background,
            stroke: override.stroke ?? stroke,
            separator: override.separator ?? separator,
            edgeEffect: override.edgeEffect ?? edgeEffect,
            iconColor: override.iconColor ?? iconColor,
            selectedIconColor: override.selectedIconColor ?? selectedIconColor,
            textColor: override.textColor ?? textColor,
            selectedTextColor: override.selectedTextColor ?? selectedTextColor
        )
    }
}

public struct AetherSearchAppearanceOverride {
    public var background: AetherBarBackgroundAppearance?
    public var stroke: AetherGlassStrokeAppearance?
    public var separator: AetherSeparatorAppearance?
    public var edgeEffect: AetherEdgeEffectAppearance?
    public var textColor: UIColor?
    public var placeholderColor: UIColor?

    public init(
        background: AetherBarBackgroundAppearance? = nil,
        stroke: AetherGlassStrokeAppearance? = nil,
        separator: AetherSeparatorAppearance? = nil,
        edgeEffect: AetherEdgeEffectAppearance? = nil,
        textColor: UIColor? = nil,
        placeholderColor: UIColor? = nil
    ) {
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
        self.textColor = textColor
        self.placeholderColor = placeholderColor
    }
}

public struct AetherInputBarAppearanceOverride {
    public var background: AetherBarBackgroundAppearance?
    public var stroke: AetherGlassStrokeAppearance?
    public var separator: AetherSeparatorAppearance?
    public var edgeEffect: AetherEdgeEffectAppearance?

    public init(
        background: AetherBarBackgroundAppearance? = nil,
        stroke: AetherGlassStrokeAppearance? = nil,
        separator: AetherSeparatorAppearance? = nil,
        edgeEffect: AetherEdgeEffectAppearance? = nil
    ) {
        self.background = background
        self.stroke = stroke
        self.separator = separator
        self.edgeEffect = edgeEffect
    }
}

// MARK: - Resolution

public struct AetherAppearanceResolutionContext {
    public var appearance: AetherAppearance
    public var surface: AetherAppearanceSurface
    public var placement: AetherBarPlacement
    public var traitCollection: UITraitCollection?
    public var scrollProgress: CGFloat

    public init(
        appearance: AetherAppearance,
        surface: AetherAppearanceSurface,
        placement: AetherBarPlacement,
        traitCollection: UITraitCollection? = nil,
        scrollProgress: CGFloat = 0.0
    ) {
        self.appearance = appearance
        self.surface = surface
        self.placement = placement
        self.traitCollection = traitCollection
        self.scrollProgress = scrollProgress
    }
}

public enum AetherNavigationBarAppearanceResolver {
    public static func resolve(
        context: AetherAppearanceResolutionContext,
        override: AetherNavigationBarAppearanceOverride? = nil
    ) -> AetherNavigationBarResolvedAppearance {
        let appearance = context.appearance
        let showsScrollSeparator = appearance.style == .iOS27 && appearance.edgeEffectStyle != .regular
        var resolved = AetherNavigationBarResolvedAppearance(
            background: .glass(appearance.edgeEffectStyle),
            stroke: appearance.style == .iOS27 ? .hairline(color: appearance.separatorColor, opacity: 0.35) : .none,
            separator: showsScrollSeparator
                ? .scrollActivated(threshold: 8.0, hysteresis: 2.0, color: appearance.separatorColor)
                : .hidden,
            edgeEffect: appearance.edgeEffectAppearance(for: context.surface),
            overallDarkAppearance: appearance.overallDarkAppearance,
            emptyAreaColor: appearance.emptyAreaColor,
            buttonColor: appearance.overallDarkAppearance ? .white : .label,
            primaryTextColor: appearance.overallDarkAppearance ? .white : .label
        )
        resolved.apply(override)
        return resolved
    }
}

public enum AetherTabBarAppearanceResolver {
    public static func resolve(
        context: AetherAppearanceResolutionContext,
        override: AetherTabBarAppearanceOverride? = nil
    ) -> AetherTabBarResolvedAppearance {
        let appearance = context.appearance
        var resolved = AetherTabBarResolvedAppearance(
            background: .glass(appearance.edgeEffectStyle),
            stroke: appearance.style == .iOS27 ? .hairline(color: appearance.separatorColor, opacity: 0.25) : .none,
            separator: .hidden,
            edgeEffect: appearance.edgeEffectAppearance(for: context.surface),
            overallDarkAppearance: appearance.overallDarkAppearance,
            iconColor: .label,
            selectedIconColor: .systemBlue,
            textColor: .label,
            selectedTextColor: .systemBlue
        )
        resolved.apply(override)
        return resolved
    }
}

public enum AetherSearchAppearanceResolver {
    public static func resolve(
        context: AetherAppearanceResolutionContext,
        override: AetherSearchAppearanceOverride? = nil
    ) -> AetherSearchResolvedAppearance {
        let appearance = context.appearance
        var resolved = AetherSearchResolvedAppearance(
            background: .glass(appearance.edgeEffectStyle),
            stroke: appearance.style == .iOS27 ? .hairline(color: appearance.separatorColor, opacity: 0.25) : .none,
            separator: .hidden,
            edgeEffect: appearance.edgeEffectAppearance(for: context.surface),
            overallDarkAppearance: appearance.overallDarkAppearance,
            textColor: .label,
            placeholderColor: .secondaryLabel
        )
        resolved.apply(override)
        return resolved
    }
}

public enum AetherInputBarAppearanceResolver {
    public static func resolve(
        context: AetherAppearanceResolutionContext,
        override: AetherInputBarAppearanceOverride? = nil
    ) -> AetherInputBarResolvedAppearance {
        let appearance = context.appearance
        var resolved = AetherInputBarResolvedAppearance(
            background: .glass(appearance.edgeEffectStyle),
            stroke: appearance.style == .iOS27 ? .hairline(color: appearance.separatorColor, opacity: 0.25) : .none,
            separator: .visible(color: appearance.separatorColor, opacity: appearance.style == .iOS27 ? 0.35 : 0.0),
            edgeEffect: appearance.edgeEffectAppearance(for: context.surface),
            overallDarkAppearance: appearance.overallDarkAppearance
        )
        resolved.apply(override)
        return resolved
    }
}

private extension AetherNavigationBarResolvedAppearance {
    mutating func apply(_ override: AetherNavigationBarAppearanceOverride?) {
        guard let override else { return }
        if let background = override.background { self.background = background }
        if let stroke = override.stroke { self.stroke = stroke }
        if let separator = override.separator { self.separator = separator }
        if let edgeEffect = override.edgeEffect { self.edgeEffect = edgeEffect }
        if let emptyAreaColor = override.emptyAreaColor { self.emptyAreaColor = emptyAreaColor }
        if let buttonColor = override.buttonColor { self.buttonColor = buttonColor }
        if let primaryTextColor = override.primaryTextColor { self.primaryTextColor = primaryTextColor }
    }
}

private extension AetherTabBarResolvedAppearance {
    mutating func apply(_ override: AetherTabBarAppearanceOverride?) {
        guard let override else { return }
        if let background = override.background { self.background = background }
        if let stroke = override.stroke { self.stroke = stroke }
        if let separator = override.separator { self.separator = separator }
        if let edgeEffect = override.edgeEffect { self.edgeEffect = edgeEffect }
        if let iconColor = override.iconColor { self.iconColor = iconColor }
        if let selectedIconColor = override.selectedIconColor { self.selectedIconColor = selectedIconColor }
        if let textColor = override.textColor { self.textColor = textColor }
        if let selectedTextColor = override.selectedTextColor { self.selectedTextColor = selectedTextColor }
    }
}

private extension AetherSearchResolvedAppearance {
    mutating func apply(_ override: AetherSearchAppearanceOverride?) {
        guard let override else { return }
        if let background = override.background { self.background = background }
        if let stroke = override.stroke { self.stroke = stroke }
        if let separator = override.separator { self.separator = separator }
        if let edgeEffect = override.edgeEffect { self.edgeEffect = edgeEffect }
        if let textColor = override.textColor { self.textColor = textColor }
        if let placeholderColor = override.placeholderColor { self.placeholderColor = placeholderColor }
    }
}

private extension AetherInputBarResolvedAppearance {
    mutating func apply(_ override: AetherInputBarAppearanceOverride?) {
        guard let override else { return }
        if let background = override.background { self.background = background }
        if let stroke = override.stroke { self.stroke = stroke }
        if let separator = override.separator { self.separator = separator }
        if let edgeEffect = override.edgeEffect { self.edgeEffect = edgeEffect }
    }
}

// MARK: - Legacy Renderer Adapters

public extension NavigationControllerTheme {
    convenience init(aetherAppearance appearance: AetherAppearance) {
        let context = AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .navigation,
            placement: .navigation
        )
        let resolved = AetherNavigationBarAppearanceResolver.resolve(context: context)
        self.init(
            statusBar: appearance.overallDarkAppearance ? .white : .black,
            navigationBar: NavigationBarTheme(aetherResolvedAppearance: resolved),
            emptyAreaColor: resolved.emptyAreaColor
        )
    }

    static func aetherAppearance(_ appearance: AetherAppearance) -> NavigationControllerTheme {
        NavigationControllerTheme(aetherAppearance: appearance)
    }
}

public extension NavigationBarTheme {
    convenience init(
        aetherResolvedAppearance appearance: AetherNavigationBarResolvedAppearance,
        accentButtonColor: UIColor = .systemBlue,
        accentForegroundColor: UIColor = .white
    ) {
        let backgroundColor: UIColor
        let enableBlur: Bool
        let style: NavigationBarStyle
        let glassStyle: NavigationBarGlassStyle

        switch appearance.background {
        case .none, .transparent:
            backgroundColor = .clear
            enableBlur = false
            style = .glass
            glassStyle = .clear
        case let .glass(glass):
            backgroundColor = .clear
            enableBlur = true
            style = .glass
            switch glass {
            case .clear:
                glassStyle = .clear
            case .strong:
                glassStyle = .strong
            case .regular:
                glassStyle = .default
            }
        case let .color(color):
            backgroundColor = color
            enableBlur = false
            style = .legacy
            glassStyle = .default
        }

        self.init(
            overallDarkAppearance: appearance.overallDarkAppearance,
            buttonColor: appearance.buttonColor,
            disabledButtonColor: .secondaryLabel,
            primaryTextColor: appearance.primaryTextColor,
            backgroundColor: backgroundColor,
            opaqueBackgroundColor: appearance.emptyAreaColor,
            enableBackgroundBlur: enableBlur,
            separatorColor: appearance.separator.legacyColor(defaultColor: appearance.emptyAreaColor),
            badgeBackgroundColor: .systemRed,
            badgeStrokeColor: .systemBackground,
            badgeTextColor: .white,
            edgeEffectColor: appearance.edgeEffect.tintColor,
            accentButtonColor: accentButtonColor,
            accentForegroundColor: accentForegroundColor,
            style: style,
            glassStyle: glassStyle,
            edgeEffectAlpha: appearance.edgeEffect.alpha,
            edgeEffectBlurRadiusAtEdge: appearance.edgeEffect.blurRadiusAtEdge,
            edgeEffectBlurRadiusAtFade: appearance.edgeEffect.blurRadiusAtFade,
            edgeEffectSolidBlur: appearance.edgeEffect.solidBlur,
            edgeEffectStyle: appearance.edgeEffect.style
        )
    }
}

public extension NavigationBarPresentationData {
    static func aetherAppearance(
        accentButtonColor: UIColor = .systemBlue,
        accentForegroundColor: UIColor = .white,
        edgeEffectColor: UIColor = AetherAppearance.runtimeCurrent.edgeEffectColor,
        edgeEffectBlurRadiusAtEdge: CGFloat = AetherAppearance.runtimeCurrent.edgeEffectBlurRadiusAtEdge,
        edgeEffectBlurRadiusAtFade: CGFloat = AetherAppearance.runtimeCurrent.edgeEffectBlurRadiusAtFade,
        edgeEffectStyle: SystemGlassEffectStyle = AetherAppearance.runtimeCurrent.edgeEffectStyle,
        strings: NavigationBarStrings = NavigationBarStrings()
    ) -> NavigationBarPresentationData {
        var appearance = AetherAppearance.runtimeCurrent
        appearance.edgeEffectColor = edgeEffectColor
        appearance.edgeEffectStyle = edgeEffectStyle
        appearance.edgeEffectBlurRadiusAtEdge = edgeEffectBlurRadiusAtEdge
        appearance.edgeEffectBlurRadiusAtFade = edgeEffectBlurRadiusAtFade

        let context = AetherAppearanceResolutionContext(
            appearance: appearance,
            surface: .navigation,
            placement: .navigation
        )
        let resolved = AetherNavigationBarAppearanceResolver.resolve(context: context)
        return NavigationBarPresentationData(
            theme: NavigationBarTheme(
                aetherResolvedAppearance: resolved,
                accentButtonColor: accentButtonColor,
                accentForegroundColor: accentForegroundColor
            ),
            strings: strings
        )
    }
}

public extension TabBarView.Theme {
    init(aetherResolvedAppearance appearance: AetherTabBarResolvedAppearance) {
        let backgroundColor: UIColor
        let enableBlur: Bool
        let style: TabBarView.Style
        switch appearance.background {
        case .none, .transparent:
            backgroundColor = .clear
            enableBlur = false
            style = .liquidGlass
        case .glass:
            backgroundColor = .clear
            enableBlur = true
            style = .liquidGlass
        case let .color(color):
            backgroundColor = color
            enableBlur = false
            style = .legacy
        }

        self.init(
            tabBarBackgroundColor: backgroundColor,
            tabBarSeparatorColor: appearance.separator.legacyColor(defaultColor: .clear),
            tabBarIconColor: appearance.iconColor,
            tabBarSelectedIconColor: appearance.selectedIconColor,
            tabBarTextColor: appearance.textColor,
            tabBarSelectedTextColor: appearance.selectedTextColor,
            enableBlur: enableBlur,
            isDark: appearance.overallDarkAppearance,
            style: style,
            edgeEffectAlpha: appearance.edgeEffect.alpha,
            edgeEffectBlurRadiusAtEdge: appearance.edgeEffect.blurRadiusAtEdge,
            edgeEffectBlurRadiusAtFade: appearance.edgeEffect.blurRadiusAtFade,
            edgeEffectSolidBlur: appearance.edgeEffect.solidBlur,
            glassEffectStyle: appearance.edgeEffect.style,
            edgeEffectTintColor: appearance.edgeEffect.tintColor
        )
    }
}

private extension AetherSeparatorAppearance {
    func legacyColor(defaultColor: UIColor) -> UIColor {
        switch self {
        case .hidden:
            return .clear
        case let .visible(color, opacity):
            return (color ?? defaultColor).withAlphaComponent(opacity)
        case let .scrollActivated(_, _, color):
            return color ?? defaultColor
        }
    }
}

public extension AetherAppearance {
    static func withRuntimeCurrent<Result>(_ appearance: AetherAppearance, _ body: () -> Result) -> Result {
        let threadDictionary = Thread.current.threadDictionary
        let previous = threadDictionary[AetherAppearanceRuntimeCurrentStorage.key]
        threadDictionary[AetherAppearanceRuntimeCurrentStorage.key] = appearance
        defer {
            if let previous {
                threadDictionary[AetherAppearanceRuntimeCurrentStorage.key] = previous
            } else {
                threadDictionary.removeObject(forKey: AetherAppearanceRuntimeCurrentStorage.key)
            }
        }
        return body()
    }

    static var runtimeCurrent: AetherAppearance {
        if let scoped = Thread.current.threadDictionary[AetherAppearanceRuntimeCurrentStorage.key] as? AetherAppearance {
            return scoped
        }
        return AetherApplicationRuntime.shared?.currentEnvironment.appearance ?? .iOS26
    }
}
