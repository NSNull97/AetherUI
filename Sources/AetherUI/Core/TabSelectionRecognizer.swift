import UIKit

/// Custom gesture recognizer for tab selection with horizontal translation
/// tracking. Behaves like a standard `UIPanGestureRecognizer` in terms of
/// state transitions: stays `.possible` until horizontal movement exceeds
/// `horizontalActivationDistance`, only then transitions to `.began`.
///
/// The earlier revision entered `.began` immediately on `touchesBegan`,
/// which won the gesture-arbitration auction against every other
/// recognizer on the same view (tap, long-press, swipes). That starved the
/// `lensTap` / `lensLongPress` recognizers: a quick tap on the already-
/// selected tab had no observable effect because `lensPanned.ended` only
/// dispatches `tabSelected` when the index changed, and tap never won the
/// chance to fire. A long-press produced the "System gesture gate timed
/// out" diagnostic for the same reason — the pan held the gate open
/// without ever actually recognising a drag.
public final class TabSelectionRecognizer: UIGestureRecognizer {
    /// Minimum horizontal finger travel (points) required before the
    /// recognizer transitions to `.began`. Matches the default UIKit
    /// slop used for UIPanGestureRecognizer-style interactions.
    private static let horizontalActivationDistance: CGFloat = 10.0

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
        currentLocation = nil
    }

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if initialLocation == nil {
            initialLocation = touches.first?.location(in: view)
        }
        currentLocation = initialLocation
        // Stay in `.possible`. We need to observe movement first so the
        // competing tap / long-press recognisers get a fair chance at
        // arbitration.
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        currentLocation = touches.first?.location(in: view)

        if state == .possible {
            // Only "wake up" the pan once the finger has travelled far
            // enough — and predominantly horizontally, since tab
            // selection is strictly an x-axis drag. Vertical-biased
            // drags leave us as `.possible` so the touch is free to
            // cancel into some outer vertical recogniser.
            guard let initial = initialLocation, let current = currentLocation else { return }
            let dx = abs(current.x - initial.x)
            let dy = abs(current.y - initial.y)
            if dx > Self.horizontalActivationDistance, dx > dy {
                state = .began
            }
        } else if state == .began || state == .changed {
            state = .changed
        }
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        // Never recognised a drag: fail the pan so the simultaneously-
        // tracked tap recogniser can resolve its own hit. Without this,
        // UIKit would leave the pan in `.possible` indefinitely and the
        // arbitration gate might time out on the next interaction.
        if state == .possible {
            state = .failed
        } else {
            state = .ended
        }
    }

    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        state = .cancelled
    }

    public func translation(in view: UIView?) -> CGPoint {
        guard let initialLocation = initialLocation, let currentLocation = currentLocation else {
            return .zero
        }
        return CGPoint(x: currentLocation.x - initialLocation.x, y: currentLocation.y - initialLocation.y)
    }
}
