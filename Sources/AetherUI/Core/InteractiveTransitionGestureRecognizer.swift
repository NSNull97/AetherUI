import UIKit

public struct InteractiveTransitionGestureRecognizerDirections: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let leftEdge = InteractiveTransitionGestureRecognizerDirections(rawValue: 1 << 0)
    public static let rightEdge = InteractiveTransitionGestureRecognizerDirections(rawValue: 1 << 1)
    public static let leftCenter = InteractiveTransitionGestureRecognizerDirections(rawValue: 1 << 2)
    public static let rightCenter = InteractiveTransitionGestureRecognizerDirections(rawValue: 1 << 3)
    public static let down = InteractiveTransitionGestureRecognizerDirections(rawValue: 1 << 4)
    public static let left = InteractiveTransitionGestureRecognizerDirections(rawValue: 1 << 5)
    public static let right = InteractiveTransitionGestureRecognizerDirections(rawValue: 1 << 6)
}

public enum InteractiveTransitionGestureRecognizerEdgeWidth {
    case constant(CGFloat)
    case widthMultiplier(factor: CGFloat, min: CGFloat, max: CGFloat)

    func effectiveWidth(for width: CGFloat) -> CGFloat {
        switch self {
        case let .constant(value):
            return value
        case let .widthMultiplier(factor, min, max):
            return Swift.min(max, Swift.max(min, width * factor))
        }
    }
}

public class InteractiveTransitionGestureRecognizer: UIPanGestureRecognizer {
    private let edgeWidth: InteractiveTransitionGestureRecognizerEdgeWidth
    private let allowedDirections: (CGPoint) -> InteractiveTransitionGestureRecognizerDirections
    var edgeWidthOverride: (() -> InteractiveTransitionGestureRecognizerEdgeWidth?)?
    private var validatedGesture = false
    private var firstLocation = CGPoint()
    private var currentAllowedDirections: InteractiveTransitionGestureRecognizerDirections = []

    public init(target: Any?, action: Selector?, allowedDirections: @escaping (CGPoint) -> InteractiveTransitionGestureRecognizerDirections, edgeWidth: InteractiveTransitionGestureRecognizerEdgeWidth = .constant(16.0)) {
        self.allowedDirections = allowedDirections
        self.edgeWidth = edgeWidth

        super.init(target: target, action: action)

        self.maximumNumberOfTouches = 1
    }

    public func cancel() {
        self.state = .cancelled
    }

    override public func reset() {
        super.reset()
        self.validatedGesture = false
    }

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)

        guard let touch = touches.first else { return }
        let location = touch.location(in: self.view)
        self.firstLocation = location
        self.currentAllowedDirections = self.allowedDirections(location)

        if self.currentAllowedDirections.isEmpty {
            self.state = .failed
            return
        }

        guard let view = self.view else { return }

        // Honour opt-outs set by descendant views (horizontal pagers,
        // sliders, carousels, etc.) via `disablesInteractiveTransitionGestureRecognizer`
        // and friends from AetherUIBridging. If the touched subtree opts
        // out, edge-only gestures survive (so the system edge-swipe back
        // still works) but center swipes fail — matches Telegram's
        // WindowContent behaviour.
        if let hit = view.hitTest(location, with: event) {
            let point = view.convert(location, to: hit)
            if doesViewTreeDisableInteractiveTransitionGestureRecognizer(hit, point: point) {
                if self.currentAllowedDirections.contains(.down) {
                    // Down-drag routes are explicitly not edge-related;
                    // a descendant's opt-out must not block them.
                } else if self.currentAllowedDirections.contains(.leftEdge) || self.currentAllowedDirections.contains(.rightEdge) {
                    self.currentAllowedDirections.remove(.leftCenter)
                    self.currentAllowedDirections.remove(.rightCenter)
                    self.currentAllowedDirections.remove(.left)
                    self.currentAllowedDirections.remove(.right)
                    if self.currentAllowedDirections.isEmpty {
                        self.state = .failed
                        return
                    }
                } else {
                    self.state = .failed
                    return
                }
            }
        }

        let effectiveEdgeWidth = (self.edgeWidthOverride?() ?? self.edgeWidth).effectiveWidth(for: view.bounds.width)

        if self.currentAllowedDirections.contains(.leftEdge) && location.x >= effectiveEdgeWidth {
            self.currentAllowedDirections.remove(.leftEdge)
        }
        if self.currentAllowedDirections.contains(.rightEdge) && location.x <= view.bounds.width - effectiveEdgeWidth {
            self.currentAllowedDirections.remove(.rightEdge)
        }
        if self.currentAllowedDirections.isEmpty {
            self.state = .failed
            return
        }
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else {
            super.touchesMoved(touches, with: event)
            return
        }

        let location = touch.location(in: self.view)
        let translation = CGPoint(x: location.x - self.firstLocation.x, y: location.y - self.firstLocation.y)

        let absX = abs(translation.x)
        let absY = abs(translation.y)

        if !self.validatedGesture {
            if absX + absY > 4.0 {
                if self.currentAllowedDirections.contains(.leftEdge) || self.currentAllowedDirections.contains(.rightEdge) {
                    let allowsRightwardEdgePan = self.currentAllowedDirections.contains(.leftEdge) && translation.x > 0.0
                    let allowsLeftwardEdgePan = self.currentAllowedDirections.contains(.rightEdge) && translation.x < 0.0
                    if absX > absY && (allowsRightwardEdgePan || allowsLeftwardEdgePan) {
                        self.validatedGesture = true
                    } else {
                        self.state = .failed
                        return
                    }
                } else if self.currentAllowedDirections.contains(.down) {
                    if absY > absX && translation.y > 0.0 {
                        self.validatedGesture = true
                    } else {
                        self.state = .failed
                        return
                    }
                } else if self.currentAllowedDirections.contains(.right) || self.currentAllowedDirections.contains(.left) {
                    let allowsRightwardPan = self.currentAllowedDirections.contains(.right) && translation.x > 0.0
                    let allowsLeftwardPan = self.currentAllowedDirections.contains(.left) && translation.x < 0.0
                    if absX > absY && (allowsRightwardPan || allowsLeftwardPan) {
                        self.validatedGesture = true
                    } else {
                        self.state = .failed
                        return
                    }
                } else {
                    self.state = .failed
                    return
                }
            }
        }

        super.touchesMoved(touches, with: event)
    }
}
