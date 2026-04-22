import UIKit

/// Swift-only access to the native keyboard window + keyboard view.
///
/// Port of the probes in Telegram-iOS's AppDelegate (`isKeyboardWindow`,
/// `isKeyboardView`, `isKeyboardViewContainer`). We sniff class names
/// rather than linking against private frameworks, so the code stays
/// Swift-only and fails gracefully when UIKit shuffles internals
/// between releases.
///
/// On iOS 16+ the class is `UIRemoteKeyboardWindow`; earlier systems
/// use `UITextEffectsWindow`. Inside the window we look for
/// `UIInputSetContainerView → UIInputSetHostView` — that host view is
/// the one we translate to achieve interactive drag-to-dismiss.
public enum CrystalKeyboardAccess {
    /// Returns the window hosting the soft keyboard, or `nil` if the
    /// keyboard isn't currently shown.
    public static func keyboardWindow() -> UIWindow? {
        let windows = allApplicationWindows()
        for window in windows where isKeyboardWindow(window) {
            return window
        }
        return nil
    }

    /// Returns the `UIInputSetHostView` that renders the actual keyboard
    /// keys. Translate this view's layer to interactively move the
    /// keyboard on-screen.
    public static func keyboardView(in window: UIWindow? = nil) -> UIView? {
        let kwindow = window ?? keyboardWindow()
        guard let kwindow else { return nil }
        for view in kwindow.subviews where isKeyboardViewContainer(view) {
            for subview in view.subviews where isKeyboardView(subview) {
                return subview
            }
        }
        return nil
    }

    // MARK: - Class-name sniffing

    private static func isKeyboardWindow(_ window: UIWindow) -> Bool {
        let name = NSStringFromClass(type(of: window))
        guard name.hasPrefix("UI") else { return false }
        return name.hasSuffix("RemoteKeyboardWindow") || name.hasSuffix("TextEffectsWindow")
    }

    private static func isKeyboardViewContainer(_ view: UIView) -> Bool {
        let name = NSStringFromClass(type(of: view))
        return name.hasPrefix("UI") && name.hasSuffix("InputSetContainerView")
    }

    private static func isKeyboardView(_ view: UIView) -> Bool {
        let name = NSStringFromClass(type(of: view))
        return name.hasPrefix("UI") && name.hasSuffix("InputSetHostView")
    }

    /// Collect every UIWindow the current process knows about, across all
    /// connected scenes. Keyboard window attaches to a UIWindowScene at
    /// runtime and isn't always reachable via the app's key window —
    /// walking `connectedScenes.windows` covers the general case.
    private static func allApplicationWindows() -> [UIWindow] {
        var result: [UIWindow] = []
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            result.append(contentsOf: ws.windows)
        }
        return result
    }
}
