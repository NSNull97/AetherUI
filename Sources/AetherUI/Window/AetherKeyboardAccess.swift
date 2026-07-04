import UIKit

/// Compatibility shim retained for source compatibility with early AetherUI
/// builds. AetherUI no longer exposes UIKit keyboard internals.
///
/// Use `AetherKeyboardManager` for supported keyboard state tracking.
@available(*, deprecated, message: "Use AetherKeyboardManager. Direct keyboard internals are unavailable through AetherUI.")
public enum AetherKeyboardAccess {
    public static func keyboardWindow() -> UIWindow? {
        nil
    }

    public static func keyboardView(in window: UIWindow? = nil) -> UIView? {
        _ = window
        return nil
    }
}

internal enum AetherLegacyKeyboardRuntime {
    private static weak var lastInteractiveKeyboardView: UIView?
    private static weak var lastWindowVerticalFallback: UIWindow?

    static func updateInteractiveKeyboardOffset(
        _ offset: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: (() -> Void)? = nil
    ) {
        let keyboardWindow = keyboardWindow()
        let keyboardView = keyboardView(in: keyboardWindow)

        // Vertical strategies are alternatives. Stacking them makes the
        // keyboard outrun the interactive gesture.
        guard let keyboardView else {
            if let keyboardWindow {
                applyWindowVerticalFallback(
                    keyboardWindow,
                    offset: offset,
                    transition: transition
                ) {
                    if offset.isZero {
                        self.lastWindowVerticalFallback = nil
                    }
                    completion?()
                }
                if !offset.isZero {
                    lastWindowVerticalFallback = keyboardWindow
                }
            } else if offset.isZero, let lastWindowVerticalFallback {
                applyWindowVerticalFallback(
                    lastWindowVerticalFallback,
                    offset: 0.0,
                    transition: transition
                ) {
                    self.lastWindowVerticalFallback = nil
                    completion?()
                }
            } else {
                completion?()
            }
            if !offset.isZero {
                return
            }
            if keyboardWindow != nil || lastWindowVerticalFallback != nil {
                return
            }
            if let lastInteractiveKeyboardView {
                resetBounds(of: lastInteractiveKeyboardView)
                lastInteractiveKeyboardView.transform = .identity
                self.lastInteractiveKeyboardView = nil
            }
            return
        }

        if let lastWindowVerticalFallback {
            applyWindowVerticalFallback(
                lastWindowVerticalFallback,
                offset: 0.0,
                transition: .immediate
            )
            self.lastWindowVerticalFallback = nil
        }

        if let previousView = lastInteractiveKeyboardView, previousView !== keyboardView {
            resetBounds(of: previousView)
            previousView.transform = .identity
        }
        lastInteractiveKeyboardView = keyboardView
        keyboardView.transform = .identity

        let previousBounds = keyboardView.bounds
        let updatedBounds = CGRect(
            origin: CGPoint(x: 0.0, y: -offset),
            size: previousBounds.size
        )
        keyboardView.layer.bounds = updatedBounds

        let finish: () -> Void = {
            if offset.isZero {
                self.lastInteractiveKeyboardView = nil
            }
            keyboardView.transform = .identity
            completion?()
        }

        let surfaceTransition = keyboardSurfaceTransition(
            targetOffset: offset,
            previousBoundsMinY: previousBounds.minY,
            transition: transition
        )

        switch surfaceTransition {
        case .immediate:
            finish()
        case let .animated(duration, curve):
            keyboardView.layer.animateBounds(
                from: previousBounds,
                to: updatedBounds,
                duration: duration,
                timingFunction: curve.mediaTimingFunction(),
                completion: { _ in finish() }
            )
        }
    }

    static func keyboardSurfaceTransition(
        targetOffset: CGFloat,
        previousBoundsMinY: CGFloat,
        transition: ContainedViewLayoutTransition
    ) -> ContainedViewLayoutTransition {
        guard targetOffset.isZero, previousBoundsMinY < 0.0 else {
            return transition
        }
        guard case let .animated(duration, curve) = transition else {
            return transition
        }
        switch curve {
        case .spring, .customSpring:
            return .animated(duration: duration, curve: .easeInOut)
        default:
            return transition
        }
    }

    static func keyboardWindow() -> UIWindow? {
        if let keyboardWindow = bridgedKeyboardWindow() {
            return keyboardWindow
        }

        let sceneWindows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let legacyWindows = UIApplication.shared.windows.filter { window in
            !sceneWindows.contains { $0 === window }
        }
        let allWindows = sceneWindows + legacyWindows

        if let keyboardWindow = allWindows.first(where: isKeyboardWindow) {
            return keyboardWindow
        }

        return allWindows.first { window in
            NSStringFromClass(type(of: window)).contains("Keyboard")
        }
    }

    static func keyboardView(in window: UIWindow? = nil) -> UIView? {
        let resolvedWindow = window ?? keyboardWindow()
        guard let keyboardWindow = resolvedWindow else {
            return nil
        }

        for view in keyboardWindow.subviews where isKeyboardViewContainer(view) {
            for subview in view.subviews where isKeyboardView(subview) {
                return subview
            }
        }

        return findKeyboardView(in: keyboardWindow)
    }

    static func updateKeyboardLeftEdge(
        _ leftEdge: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let keyboardWindow = keyboardWindow() else {
            completion?(false)
            return
        }

        let currentTransform = keyboardWindow.layer.sublayerTransform
        let targetTransform = CATransform3DMakeTranslation(leftEdge, currentTransform.m42, 0.0)

        switch transition {
        case .immediate:
            keyboardWindow.layer.removeAnimation(forKey: "sublayerTransform")
            keyboardWindow.layer.sublayerTransform = targetTransform
            completion?(true)
        case let .animated(duration, curve):
            let fromTransform = keyboardWindow.layer.presentation()?.sublayerTransform ?? currentTransform
            keyboardWindow.layer.sublayerTransform = targetTransform

            let animation = CABasicAnimation(keyPath: "sublayerTransform")
            animation.fromValue = NSValue(caTransform3D: fromTransform)
            animation.toValue = NSValue(caTransform3D: targetTransform)
            animation.duration = duration
            animation.timingFunction = curve.mediaTimingFunction()
            keyboardWindow.layer.add(animation, forKey: "sublayerTransform")
            completion?(true)
        }
    }

    static func removeKeyboardAnimations() {
        guard let keyboardWindow = keyboardWindow() else {
            return
        }
        removeAnimationsRecursively(from: keyboardWindow)
    }

    static func isKeyboardVisible() -> Bool {
        guard let keyboardView = keyboardView() else {
            return false
        }
        return keyboardView.window != nil
            && !keyboardView.isHidden
            && keyboardView.alpha > 0.0
            && keyboardView.bounds.height > 0.0
    }

    private static func bridgedKeyboardWindow() -> UIWindow? {
        let selector = NSSelectorFromString("aether_internalGetKeyboardWindow")
        guard UIApplication.shared.responds(to: selector) else {
            return nil
        }
        return UIApplication.shared.perform(selector)?.takeUnretainedValue() as? UIWindow
    }

    private static func isKeyboardWindow(_ window: UIWindow) -> Bool {
        let typeName = NSStringFromClass(type(of: window))
        if #available(iOS 9.0, *) {
            return typeName.hasPrefix(ObfuscatedSymbols.uiPrefix) && typeName.hasSuffix(ObfuscatedSymbols.remoteKeyboardWindowSuffix)
        } else {
            return typeName.hasPrefix(ObfuscatedSymbols.uiPrefix) && typeName.hasSuffix(ObfuscatedSymbols.textEffectsWindowSuffix)
        }
    }

    private static func isKeyboardView(_ view: UIView) -> Bool {
        let typeName = NSStringFromClass(type(of: view))
        guard typeName.hasPrefix(ObfuscatedSymbols.uiPrefix) || typeName.hasPrefix(ObfuscatedSymbols.uiUnderscorePrefix) else {
            return false
        }
        return typeName.hasSuffix(ObfuscatedSymbols.inputSetHostViewSuffix)
            || typeName.hasSuffix(ObfuscatedSymbols.keyboardItemContainerViewSuffix)
    }

    private static func isKeyboardViewContainer(_ view: UIView) -> Bool {
        let typeName = NSStringFromClass(type(of: view))
        return typeName.hasPrefix(ObfuscatedSymbols.uiPrefix) && typeName.hasSuffix(ObfuscatedSymbols.inputSetContainerViewSuffix)
    }

    private static func findKeyboardView(in view: UIView) -> UIView? {
        if isKeyboardView(view) {
            return view
        }
        for subview in view.subviews {
            if let result = findKeyboardView(in: subview) {
                return result
            }
        }
        return nil
    }

    private static func resetBounds(of view: UIView) {
        view.layer.bounds = CGRect(origin: .zero, size: view.bounds.size)
    }

    private static func applyWindowVerticalFallback(
        _ window: UIWindow,
        offset: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: (() -> Void)? = nil
    ) {
        window.transform = .identity
        let bounds = window.bounds
        let targetFrame = CGRect(
            x: bounds.minX,
            y: bounds.minY + offset,
            width: bounds.width,
            height: bounds.height
        )
        transition.updateFrame(view: window, frame: targetFrame) { _ in
            completion?()
        }
    }

    private static func removeAnimationsRecursively(from view: UIView) {
        view.layer.removeAllAnimations()
        for subview in view.subviews {
            removeAnimationsRecursively(from: subview)
        }
    }
}
