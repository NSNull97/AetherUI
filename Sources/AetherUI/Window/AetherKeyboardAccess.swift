import UIKit

/// Swift-only access to the native keyboard window + the in-process
/// container view that hosts the visible keyboard region.
///
/// iOS 14/15: keys render in-process inside `UIInputSetContainerView →
/// UIInputSetHostView`. Translating `UIInputSetHostView.layer.bounds`
/// moves the keys in lockstep with a finger — this is the Telegram-iOS
/// trick used for interactive keyboard dismissal.
///
/// iOS 16+: keys render in a separate process
/// (`com.apple.keyboard.KeyboardManager`), composited via
/// `_UIRemoteKeyboardPlaceholderView` inside `UIKeyboardItemContainerView`.
/// The CARemoteLayer surface is pinned to screen coordinates, so
/// translating any in-process view (window, container, placeholder)
/// does not move the visible keys. We still return the container
/// so callers can cheaply no-op on iOS 16+ without branching. Real
/// drag-tracking on modern iOS requires
/// `UIScrollView.keyboardDismissMode = .interactive`, which talks to
/// the keyboard process over XPC.
///
/// We sniff class names rather than linking private frameworks so the
/// code fails gracefully when UIKit reshuffles internals.
public enum AetherKeyboardAccess {
    public static func keyboardWindow() -> UIWindow? {
        let app = UIApplication.shared

        // 1. Private `internalGetKeyboard` selector — the path
        // Telegram-iOS uses on iOS 16+. Some build configurations
        // wire it up, others don't; cheap to try first.
        let internalSelector = NSSelectorFromString("internalGetKeyboard")
        if app.responds(to: internalSelector) {
            if let window = app.perform(internalSelector)?.takeUnretainedValue() as? UIWindow {
                return window
            }
        }

        // 2. iOS 16+: keyboard lives in its own `UIKeyboardScene`.
        // Walk every connected scene whose class name contains
        // "Keyboard", grab its windows, and prefer any
        // `UIRemoteKeyboardWindow` we find there.
        var keyboardSceneWindows: [UIWindow] = []
        for scene in app.connectedScenes {
            let sceneClass = NSStringFromClass(type(of: scene))
            guard sceneClass.contains("Keyboard") else { continue }
            if let ws = scene as? UIWindowScene {
                keyboardSceneWindows.append(contentsOf: ws.windows)
            }
        }
        for window in keyboardSceneWindows
            where NSStringFromClass(type(of: window)).hasSuffix("RemoteKeyboardWindow") {
            return window
        }
        if let firstSceneWindow = keyboardSceneWindows.first {
            return firstSceneWindow
        }

        // 3. Walk regular UI scenes for the legacy keyboard window
        // classes (iOS ≤15 fallback path).
        var seen: [UIWindow] = []
        seen.append(contentsOf: allApplicationWindows())
        for window in app.windows where !seen.contains(window) {
            seen.append(window)
        }
        for window in seen where NSStringFromClass(type(of: window)).hasSuffix("RemoteKeyboardWindow") {
            return window
        }
        for window in seen where NSStringFromClass(type(of: window)).hasSuffix("TextEffectsWindow") {
            return window
        }
        return nil
    }

    public static func keyboardView(in window: UIWindow? = nil) -> UIView? {
        let kwindow = window ?? keyboardWindow()
        guard let kwindow else { return nil }
        return findKeyboardHost(in: kwindow)
    }

    private static func findKeyboardHost(in view: UIView) -> UIView? {
        if isKeyboardHost(view) { return view }
        for subview in view.subviews {
            if let result = findKeyboardHost(in: subview) {
                return result
            }
        }
        return nil
    }

    private static func isKeyboardHost(_ view: UIView) -> Bool {
        let name = NSStringFromClass(type(of: view))
        guard name.hasPrefix("UI") || name.hasPrefix("_UI") else { return false }
        // iOS 16+: visible keyboard region.
        if name.hasSuffix("KeyboardItemContainerView") { return true }
        // iOS 14/15: the real thing.
        if name.hasSuffix("InputSetHostView") { return true }
        return false
    }

    private static func allApplicationWindows() -> [UIWindow] {
        var result: [UIWindow] = []
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            result.append(contentsOf: ws.windows)
        }
        return result
    }
}
