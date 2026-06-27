import UIKit
@_exported import AetherUIBridging

// MARK: - Input Accessory Height

/// Implement on views that provide an input accessory area whose height
/// should be accounted for when calculating the keyboard-dismissal gesture
/// threshold (e.g. a chat compose bar sitting on top of the keyboard).
///
/// This is the protocol-based path; for view hierarchies you can't conform
/// (e.g. a plain `UIView` provided by the host), use
/// `view.input_setInputAccessoryHeightProvider(_:)` from
/// `AetherUIBridging` to register a block-based provider.
public protocol WindowInputAccessoryHeightProvider: UIView {
    func getWindowInputAccessoryHeight() -> CGFloat
}

// MARK: - First Responder + Accessory Height Discovery

/// Walks the view hierarchy starting from `view` to find the current
/// first responder and the accessory height reported by the nearest
/// `WindowInputAccessoryHeightProvider` ancestor or any view registered via
/// `input_setInputAccessoryHeightProvider(_:)`.
public func getFirstResponderAndAccessoryHeight(_ view: UIView, _ accessoryHeight: CGFloat? = nil) -> (UIView?, CGFloat?) {
    if view.isFirstResponder {
        return (view, accessoryHeight)
    } else {
        var updatedAccessoryHeight = accessoryHeight
        if let provider = view as? WindowInputAccessoryHeightProvider {
            updatedAccessoryHeight = provider.getWindowInputAccessoryHeight()
        } else {
            let blockHeight = view.input_getInputAccessoryHeight()
            if blockHeight > 0.0 {
                updatedAccessoryHeight = blockHeight
            }
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
///
/// Thin wrapper over the Obj-C impl in `AetherUIBridging` so call sites
/// can keep the pre-bridging import-free Swift signature.
public func doesViewTreeDisableInteractiveKeyboardGestureRecognizer(_ view: UIView) -> Bool {
    var current: UIView? = view
    while let view = current {
        if view.disablesInteractiveKeyboardGestureRecognizer {
            return true
        }
        if let shouldDisable = view.disablesInteractiveTransitionGestureRecognizerNow, shouldDisable() {
            return true
        }
        current = view.superview
    }
    return false
}

/// Walks the superview chain from `view` upward, returning `true` if any
/// ancestor opts out of the interactive transition (swipe-back) gesture
/// via any of `disablesInteractiveTransitionGestureRecognizer`,
/// `disablesInteractiveTransitionGestureRecognizerNow`, or
/// `interactiveTransitionGestureRecognizerTest` (when `point` is provided).
public func doesViewTreeDisableInteractiveTransitionGestureRecognizer(_ view: UIView, point: CGPoint? = nil) -> Bool {
    if let point {
        return AetherViewTreeDisablesInteractiveTransitionGesture(view, point, true)
    } else {
        return AetherViewTreeDisablesInteractiveTransitionGesture(view, .zero, false)
    }
}

// MARK: - Keyboard Gesture Recognizer Delegate

/// Gesture recognizer delegate for the keyboard-dismissal pan gesture.
/// Allows simultaneous recognition and excludes touches in the bottom
/// 44pt strip (tab bar / home indicator area).
public final class AetherWindowKeyboardGestureRecognizerDelegate: NSObject, UIGestureRecognizerDelegate {
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
