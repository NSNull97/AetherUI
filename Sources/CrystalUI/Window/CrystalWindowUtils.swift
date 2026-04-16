import UIKit

// MARK: - Interactive Keyboard Gesture Control

private var disablesInteractiveKeyboardGestureKey: UInt8 = 0

public extension UIView {
    /// Set to `true` on views that should prevent the interactive
    /// keyboard-dismissal pan gesture from activating when the touch
    /// starts inside them (e.g. a custom slider above the keyboard).
    var disablesInteractiveKeyboardGestureRecognizer: Bool {
        get {
            return objc_getAssociatedObject(self, &disablesInteractiveKeyboardGestureKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &disablesInteractiveKeyboardGestureKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// MARK: - Input Accessory Height

/// Implement on views that provide an input accessory area whose height
/// should be accounted for when calculating the keyboard-dismissal gesture
/// threshold (e.g. a chat compose bar sitting on top of the keyboard).
public protocol WindowInputAccessoryHeightProvider: UIView {
    func getWindowInputAccessoryHeight() -> CGFloat
}

// MARK: - First Responder + Accessory Height Discovery

/// Walks the view hierarchy starting from `view` to find the current
/// first responder and the accessory height reported by the nearest
/// `WindowInputAccessoryHeightProvider` ancestor.
public func getFirstResponderAndAccessoryHeight(_ view: UIView, _ accessoryHeight: CGFloat? = nil) -> (UIView?, CGFloat?) {
    if view.isFirstResponder {
        return (view, accessoryHeight)
    } else {
        var updatedAccessoryHeight = accessoryHeight
        if let view = view as? WindowInputAccessoryHeightProvider {
            updatedAccessoryHeight = view.getWindowInputAccessoryHeight()
        }
        for subview in view.subviews {
            let (result, resultHeight) = getFirstResponderAndAccessoryHeight(subview, updatedAccessoryHeight)
            if let result = result {
                return (result, resultHeight)
            }
        }
        return (nil, nil)
    }
}

/// Walks the superview chain from `view` upward, returning `true` if any
/// ancestor has `disablesInteractiveKeyboardGestureRecognizer` set.
public func doesViewTreeDisableInteractiveKeyboardGestureRecognizer(_ view: UIView) -> Bool {
    if view.disablesInteractiveKeyboardGestureRecognizer {
        return true
    }
    if let superview = view.superview {
        return doesViewTreeDisableInteractiveKeyboardGestureRecognizer(superview)
    }
    return false
}

// MARK: - Keyboard Gesture Recognizer Delegate

/// Gesture recognizer delegate for the keyboard-dismissal pan gesture.
/// Allows simultaneous recognition and excludes touches in the bottom
/// 44pt strip (tab bar / home indicator area).
public final class CrystalWindowKeyboardGestureRecognizerDelegate: NSObject, UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let view = gestureRecognizer.view {
            let location = touch.location(in: view)
            if location.y > view.bounds.height - 44.0 {
                return false
            }
        }
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}
