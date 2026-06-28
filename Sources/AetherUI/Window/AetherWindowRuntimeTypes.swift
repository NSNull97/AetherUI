import UIKit

public struct AetherPresentationSurfaceLevel: RawRepresentable, Comparable, Hashable {
    public var rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static func < (lhs: AetherPresentationSurfaceLevel, rhs: AetherPresentationSurfaceLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static let root = AetherPresentationSurfaceLevel(rawValue: 0)
    public static let modal = AetherPresentationSurfaceLevel(rawValue: 100)
    public static let overlay = AetherPresentationSurfaceLevel(rawValue: 200)
    public static let globalOverlay = AetherPresentationSurfaceLevel(rawValue: 300)
    public static let debug = AetherPresentationSurfaceLevel(rawValue: 1000)
}

public struct AetherStatusBarRequest: Equatable {
    public var style: UIStatusBarStyle
    public var isHidden: Bool

    public init(style: UIStatusBarStyle = .default, isHidden: Bool = false) {
        self.style = style
        self.isHidden = isHidden
    }
}

public struct AetherWindowLayout: Equatable {
    public struct Transition: Equatable {
        public enum Reason: Equatable {
            case initial
            case boundsChanged
            case sceneSizeChanged
            case rotation
            case safeAreaChanged
            case keyboardFrameChanged
            case statusBarChanged
            case overlayOpacityChanged
            case homeIndicatorChanged
            case systemGestureChanged
            case manual
        }

        public var reason: Reason
        public var duration: TimeInterval
        public var curve: UIView.AnimationCurve
        public var isInteractive: Bool

        public init(
            reason: Reason = .manual,
            duration: TimeInterval = 0.0,
            curve: UIView.AnimationCurve = .easeInOut,
            isInteractive: Bool = false
        ) {
            self.reason = reason
            self.duration = duration
            self.curve = curve
            self.isInteractive = isInteractive
        }
    }

    public var size: CGSize
    public var intrinsicInsets: UIEdgeInsets
    public var safeAreaInsets: UIEdgeInsets
    public var additionalInsets: UIEdgeInsets
    public var statusBarHeight: CGFloat?
    public var keyboardFrameInWindow: CGRect
    public var keyboardHeight: CGFloat
    public var orientation: UIInterfaceOrientation?
    public var layoutDirection: UIUserInterfaceLayoutDirection
    public var horizontalSizeClass: UIUserInterfaceSizeClass
    public var verticalSizeClass: UIUserInterfaceSizeClass
    public var prefersHomeIndicatorAutoHidden: Bool
    public var deferredScreenEdges: UIRectEdge
    public var isVoiceOverRunning: Bool
    public var transition: Transition

    public init(
        size: CGSize,
        intrinsicInsets: UIEdgeInsets = .zero,
        safeAreaInsets: UIEdgeInsets = .zero,
        additionalInsets: UIEdgeInsets = .zero,
        statusBarHeight: CGFloat? = nil,
        keyboardFrameInWindow: CGRect = .zero,
        keyboardHeight: CGFloat = 0.0,
        orientation: UIInterfaceOrientation? = nil,
        layoutDirection: UIUserInterfaceLayoutDirection = UIView.userInterfaceLayoutDirection(for: .unspecified),
        horizontalSizeClass: UIUserInterfaceSizeClass = .unspecified,
        verticalSizeClass: UIUserInterfaceSizeClass = .unspecified,
        prefersHomeIndicatorAutoHidden: Bool = false,
        deferredScreenEdges: UIRectEdge = [],
        isVoiceOverRunning: Bool = UIAccessibility.isVoiceOverRunning,
        transition: Transition = Transition(reason: .initial)
    ) {
        self.size = size
        self.intrinsicInsets = intrinsicInsets
        self.safeAreaInsets = safeAreaInsets
        self.additionalInsets = additionalInsets
        self.statusBarHeight = statusBarHeight
        self.keyboardFrameInWindow = keyboardFrameInWindow
        self.keyboardHeight = keyboardHeight
        self.orientation = orientation
        self.layoutDirection = layoutDirection
        self.horizontalSizeClass = horizontalSizeClass
        self.verticalSizeClass = verticalSizeClass
        self.prefersHomeIndicatorAutoHidden = prefersHomeIndicatorAutoHidden
        self.deferredScreenEdges = deferredScreenEdges
        self.isVoiceOverRunning = isVoiceOverRunning
        self.transition = transition
    }

    public var containerViewLayout: ContainerViewLayout {
        ContainerViewLayout(
            size: size,
            metrics: LayoutMetrics(
                widthClass: horizontalSizeClass == .regular ? .regular : .compact,
                isTablet: UIDevice.current.userInterfaceIdiom == .pad
            ),
            safeInsets: safeAreaInsets,
            additionalInsets: additionalInsets,
            statusBarHeight: statusBarHeight,
            inputHeight: keyboardHeight > 0.0 ? keyboardHeight : nil,
            inputHeightIsInteractivellyChanging: transition.isInteractive,
            inVoiceOver: isVoiceOverRunning
        )
    }
}

public struct AetherKeyboardState: Equatable {
    public enum Source: Equatable {
        case notification
        case layoutGuide
        case inputAccessoryTracker
        case privateCompatibility
        case manual
    }

    public var isVisible: Bool
    public var frameInWindow: CGRect
    public var height: CGFloat
    public var animationDuration: TimeInterval
    public var animationCurve: UIView.AnimationCurve
    public var isInteractive: Bool
    public var source: Source

    public init(
        isVisible: Bool = false,
        frameInWindow: CGRect = .zero,
        height: CGFloat = 0.0,
        animationDuration: TimeInterval = 0.0,
        animationCurve: UIView.AnimationCurve = .easeInOut,
        isInteractive: Bool = false,
        source: Source = .manual
    ) {
        self.isVisible = isVisible
        self.frameInWindow = frameInWindow
        self.height = height
        self.animationDuration = animationDuration
        self.animationCurve = animationCurve
        self.isInteractive = isInteractive
        self.source = source
    }
}

public struct AetherKeyboardAutomaticHandlingOptions: OptionSet, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let disableForward = AetherKeyboardAutomaticHandlingOptions(rawValue: 1 << 0)
    public static let disableBackward = AetherKeyboardAutomaticHandlingOptions(rawValue: 1 << 1)
}

public struct AetherKeyboardSurface {
    public weak var hostView: UIView?
    public var automaticHandlingOptions: AetherKeyboardAutomaticHandlingOptions

    public init(
        hostView: UIView?,
        automaticHandlingOptions: AetherKeyboardAutomaticHandlingOptions = []
    ) {
        self.hostView = hostView
        self.automaticHandlingOptions = automaticHandlingOptions
    }
}

public protocol AetherContainableController: AnyObject {
    var aetherViewController: UIViewController { get }
    var aetherIsReady: Bool { get }
    var aetherIsOpaqueWhenInOverlay: Bool { get }
    var aetherBlocksBackgroundWhenInOverlay: Bool { get }
    var aetherSupportedOrientations: UIInterfaceOrientationMask { get }
    var aetherDeferredScreenEdges: UIRectEdge { get }
    var aetherPrefersHomeIndicatorAutoHidden: Bool { get }
    var aetherStatusBarRequest: AetherStatusBarRequest? { get }

    func aetherSetReadyHandler(_ handler: ((Bool) -> Void)?)
    func aetherContainerLayoutUpdated(_ layout: AetherWindowLayout, transition: ContainedViewLayoutTransition)
    func aetherContainerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition)
}

extension UIViewController: AetherContainableController {
    public var aetherViewController: UIViewController {
        self
    }

    public var aetherIsReady: Bool {
        (self as? AetherViewController)?.isReady ?? true
    }

    public var aetherIsOpaqueWhenInOverlay: Bool {
        if let controller = self as? AetherViewController {
            return controller.overlayWantsToBeBelowKeyboard == false && (controller.view.backgroundColor?.cgColor.alpha ?? 0.0) >= 1.0
        }
        return (view.backgroundColor?.cgColor.alpha ?? 0.0) >= 1.0
    }

    public var aetherBlocksBackgroundWhenInOverlay: Bool {
        false
    }

    public var aetherSupportedOrientations: UIInterfaceOrientationMask {
        supportedInterfaceOrientations
    }

    public var aetherDeferredScreenEdges: UIRectEdge {
        preferredScreenEdgesDeferringSystemGestures
    }

    public var aetherPrefersHomeIndicatorAutoHidden: Bool {
        prefersHomeIndicatorAutoHidden
    }

    public var aetherStatusBarRequest: AetherStatusBarRequest? {
        AetherStatusBarRequest(style: preferredStatusBarStyle, isHidden: prefersStatusBarHidden)
    }

    public func aetherSetReadyHandler(_ handler: ((Bool) -> Void)?) {
        (self as? AetherViewController)?.readyChanged = handler
    }

    public func aetherContainerLayoutUpdated(_ layout: AetherWindowLayout, transition: ContainedViewLayoutTransition) {
        aetherContainerLayoutUpdated(layout.containerViewLayout, transition: transition)
    }

    public func aetherContainerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        if let tabBarController = self as? AetherTabBarController {
            tabBarController.containerLayoutUpdated(layout, transition: transition)
        } else if let navigationController = self as? AetherNavigationController {
            navigationController.containerLayoutUpdated(layout, transition: transition)
        } else if let viewController = self as? AetherViewController {
            viewController.containerLayoutUpdated(layout, transition: transition)
        } else {
            transition.updateFrame(view: view, frame: CGRect(origin: .zero, size: layout.size))
        }
    }
}

public protocol AetherWindowHost: AnyObject {
    func present(
        _ controller: AetherContainableController,
        on level: AetherPresentationSurfaceLevel,
        blockInteraction: Bool,
        completion: @escaping () -> Void
    )

    func presentInGlobalOverlay(_ controller: AetherContainableController)
    func presentNative(_ controller: UIViewController)
    func addGlobalPortalHostView(sourceView: AetherPortalSourceView)
    func invalidateDeferScreenEdgeGestures()
    func invalidatePrefersOnScreenNavigationHidden()
    func invalidateSupportedOrientations()
    func cancelInteractiveKeyboardGestures()
    func forEachController(_ body: (AetherContainableController) -> Void)
}

internal func aetherAssertMainThread(_ message: StaticString = "Aether window runtime mutation must run on the main thread") {
    assert(Thread.isMainThread, "\(message)")
}
