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
        let effectiveEdgeWidth = self.edgeWidth.effectiveWidth(for: view.bounds.width)

        if self.currentAllowedDirections.contains(.leftEdge) && location.x < effectiveEdgeWidth {
            self.validatedGesture = true
        }
        if self.currentAllowedDirections.contains(.rightEdge) && location.x > view.bounds.width - effectiveEdgeWidth {
            self.validatedGesture = true
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
                    if absX > absY {
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
                    if absX > absY {
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
