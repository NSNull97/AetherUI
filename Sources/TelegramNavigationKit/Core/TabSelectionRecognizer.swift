import UIKit

/// Custom gesture recognizer for tab selection with horizontal translation tracking.
/// Port of Telegram's TabSelectionRecognizer.
public final class TabSelectionRecognizer: UIGestureRecognizer {
    private var initialLocation: CGPoint?
    private var currentLocation: CGPoint?

    public override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override public func reset() {
        super.reset()
        initialLocation = nil
    }

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if initialLocation == nil {
            initialLocation = touches.first?.location(in: view)
        }
        currentLocation = initialLocation
        state = .began
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        state = .ended
    }

    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        currentLocation = touches.first?.location(in: view)
        state = .changed
    }

    public func translation(in view: UIView?) -> CGPoint {
        guard let initialLocation = initialLocation, let currentLocation = currentLocation else {
            return .zero
        }
        return CGPoint(x: currentLocation.x - initialLocation.x, y: currentLocation.y - initialLocation.y)
    }
}
