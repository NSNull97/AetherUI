import ObjectiveC
import UIKit

private var aetherKeyboardAutomaticHandlingOptionsKey: UInt8 = 0

public extension UIView {
    /// Per-view keyboard transform policy used by Aether's legacy keyboard
    /// bridge during container transitions.
    var aetherKeyboardAutomaticHandlingOptions: AetherKeyboardAutomaticHandlingOptions {
        get {
            guard let value = objc_getAssociatedObject(self, &aetherKeyboardAutomaticHandlingOptionsKey) as? NSNumber else {
                return []
            }
            return AetherKeyboardAutomaticHandlingOptions(rawValue: value.intValue)
        }
        set {
            objc_setAssociatedObject(
                self,
                &aetherKeyboardAutomaticHandlingOptionsKey,
                NSNumber(value: newValue.rawValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

public extension UIScrollView {
    /// Cancels the current deceleration/animated content-offset change while
    /// preserving the current offset and the caller's scroll-enabled state.
    func aetherStopScrollingAnimation() {
        let offset = contentOffset
        let wasScrollEnabled = isScrollEnabled
        setContentOffset(offset, animated: false)
        isScrollEnabled = false
        isScrollEnabled = wasScrollEnabled
    }
}

public enum AetherLegacyAnimation {
    public static var animationDurationFactor: CGFloat = 1.0
    public static var secondaryAnimationDurationFactor: CGFloat = 1.0
    public static var forceSystemCurve: Bool = false

    private static var forceAnimationDepth = 0

    public static func adjustedDuration(_ duration: TimeInterval, secondary: Bool = false) -> TimeInterval {
        duration * TimeInterval(secondary ? secondaryAnimationDurationFactor : animationDurationFactor)
    }

    public static func animate(
        withDuration duration: TimeInterval,
        delay: TimeInterval = 0.0,
        options: UIView.AnimationOptions = [],
        animations: @escaping () -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        var resolvedOptions = options
        if forceSystemCurve {
            resolvedOptions = UIView.AnimationOptions(rawValue: resolvedOptions.rawValue | UInt(7 << 16))
        }
        UIView.animate(
            withDuration: adjustedDuration(duration, secondary: true),
            delay: delay,
            options: resolvedOptions,
            animations: animations,
            completion: completion
        )
    }

    public static func performWithoutAnimation(_ actions: () -> Void) {
        if forceAnimationDepth > 0 {
            actions()
            return
        }

        let previousDurationFactor = animationDurationFactor
        let previousAnimationsEnabled = UIView.areAnimationsEnabled
        animationDurationFactor = 0.0
        UIView.setAnimationsEnabled(false)
        actions()
        UIView.setAnimationsEnabled(previousAnimationsEnabled)
        animationDurationFactor = previousDurationFactor
    }

    public static func forcePerformWithAnimation(_ actions: () -> Void) {
        forceAnimationDepth += 1
        actions()
        forceAnimationDepth -= 1
    }
}
