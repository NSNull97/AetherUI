import UIKit

public struct LayoutMetrics: Equatable {
    public enum WidthClass {
        case compact
        case regular
    }

    public let widthClass: WidthClass
    public let isTablet: Bool

    public init(widthClass: WidthClass = .compact, isTablet: Bool = false) {
        self.widthClass = widthClass
        self.isTablet = isTablet
    }

    public static var `default`: LayoutMetrics {
        return LayoutMetrics()
    }
}

public struct ContainerViewLayout: Equatable {
    public let size: CGSize
    public let metrics: LayoutMetrics
    public let safeInsets: UIEdgeInsets
    public let additionalInsets: UIEdgeInsets
    public let statusBarHeight: CGFloat?
    public let inputHeight: CGFloat?
    public let inputHeightIsInteractivellyChanging: Bool
    public let inVoiceOver: Bool

    public init(
        size: CGSize,
        metrics: LayoutMetrics = .default,
        safeInsets: UIEdgeInsets = .zero,
        additionalInsets: UIEdgeInsets = .zero,
        statusBarHeight: CGFloat? = nil,
        inputHeight: CGFloat? = nil,
        inputHeightIsInteractivellyChanging: Bool = false,
        inVoiceOver: Bool = false
    ) {
        self.size = size
        self.metrics = metrics
        self.safeInsets = safeInsets
        self.additionalInsets = additionalInsets
        self.statusBarHeight = statusBarHeight
        self.inputHeight = inputHeight
        self.inputHeightIsInteractivellyChanging = inputHeightIsInteractivellyChanging
        self.inVoiceOver = inVoiceOver
    }

    public var isNonExclusive: Bool {
        return self.metrics.widthClass == .regular
    }

    public var isModalOverlay: Bool {
        return self.metrics.widthClass == .regular
    }

    public func insets(options: ContainerViewLayoutInsetOptions) -> UIEdgeInsets {
        var insets = UIEdgeInsets()
        if options.contains(.statusBar) {
            insets.top += self.statusBarHeight ?? 0.0
        }
        if options.contains(.input) {
            insets.bottom = max(insets.bottom, self.inputHeight ?? 0.0)
        }
        return insets
    }

    public func withUpdatedSize(_ size: CGSize) -> ContainerViewLayout {
        return ContainerViewLayout(size: size, metrics: self.metrics, safeInsets: self.safeInsets, additionalInsets: self.additionalInsets, statusBarHeight: self.statusBarHeight, inputHeight: self.inputHeight, inputHeightIsInteractivellyChanging: self.inputHeightIsInteractivellyChanging, inVoiceOver: self.inVoiceOver)
    }

    public func withUpdatedSafeInsets(_ safeInsets: UIEdgeInsets) -> ContainerViewLayout {
        return ContainerViewLayout(size: self.size, metrics: self.metrics, safeInsets: safeInsets, additionalInsets: self.additionalInsets, statusBarHeight: self.statusBarHeight, inputHeight: self.inputHeight, inputHeightIsInteractivellyChanging: self.inputHeightIsInteractivellyChanging, inVoiceOver: self.inVoiceOver)
    }

    public func withUpdatedAdditionalInsets(_ additionalInsets: UIEdgeInsets) -> ContainerViewLayout {
        return ContainerViewLayout(size: self.size, metrics: self.metrics, safeInsets: self.safeInsets, additionalInsets: additionalInsets, statusBarHeight: self.statusBarHeight, inputHeight: self.inputHeight, inputHeightIsInteractivellyChanging: self.inputHeightIsInteractivellyChanging, inVoiceOver: self.inVoiceOver)
    }

    public func withUpdatedInputHeight(_ inputHeight: CGFloat?) -> ContainerViewLayout {
        return ContainerViewLayout(size: self.size, metrics: self.metrics, safeInsets: self.safeInsets, additionalInsets: self.additionalInsets, statusBarHeight: self.statusBarHeight, inputHeight: inputHeight, inputHeightIsInteractivellyChanging: self.inputHeightIsInteractivellyChanging, inVoiceOver: self.inVoiceOver)
    }
}

public struct ContainerViewLayoutInsetOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let statusBar = ContainerViewLayoutInsetOptions(rawValue: 1 << 0)
    public static let input = ContainerViewLayoutInsetOptions(rawValue: 1 << 1)
}
