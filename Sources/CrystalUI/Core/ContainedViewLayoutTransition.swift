import UIKit

public enum ContainedViewLayoutTransitionCurve {
    case linear
    case easeInOut
    case spring
    case customSpring(damping: CGFloat, initialVelocity: CGFloat)
    case custom(Float, Float, Float, Float)

    public static var slide: ContainedViewLayoutTransitionCurve {
        return .custom(0.33, 0.52, 0.25, 0.99)
    }

    public var viewAnimationOptions: UIView.AnimationOptions {
        switch self {
        case .linear:
            return .curveLinear
        case .easeInOut:
            return .curveEaseInOut
        case .spring, .customSpring:
            return .curveLinear
        case .custom:
            return .curveLinear
        }
    }

    public func mediaTimingFunction() -> CAMediaTimingFunction {
        switch self {
        case .linear:
            return CAMediaTimingFunction(name: .linear)
        case .easeInOut:
            return CAMediaTimingFunction(name: .easeInEaseOut)
        case .spring, .customSpring:
            return CAMediaTimingFunction(name: .linear)
        case let .custom(p1, p2, p3, p4):
            return CAMediaTimingFunction(controlPoints: p1, p2, p3, p4)
        }
    }
}

public enum ContainedViewLayoutTransition {
    case immediate
    case animated(duration: Double, curve: ContainedViewLayoutTransitionCurve)

    public var isAnimated: Bool {
        switch self {
        case .immediate:
            return false
        case .animated:
            return true
        }
    }

    public var duration: Double {
        switch self {
        case .immediate:
            return 0.0
        case let .animated(duration, _):
            return duration
        }
    }

    public func updateFrame(view: UIView, frame: CGRect, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.frame = frame
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: {
                view.frame = frame
            }, completion: completion)
        }
    }

    public func updateFrame(layer: CALayer, frame: CGRect, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            layer.frame = frame
            completion?(true)
        case let .animated(duration, curve):
            let previousFrame = layer.frame
            layer.frame = frame
            layer.animateFrame(from: previousFrame, to: frame, duration: duration, timingFunction: curve.mediaTimingFunction(), completion: { finished in
                completion?(finished)
            })
        }
    }

    public func updateAlpha(view: UIView, alpha: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.alpha = alpha
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: {
                view.alpha = alpha
            }, completion: completion)
        }
    }

    public func updateAlpha(layer: CALayer, alpha: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            layer.opacity = Float(alpha)
            completion?(true)
        case let .animated(duration, _):
            let previousAlpha = layer.opacity
            layer.opacity = Float(alpha)
            layer.animate(from: NSNumber(value: previousAlpha), to: NSNumber(value: Float(alpha)), keyPath: "opacity", duration: duration, completion: { finished in
                completion?(finished)
            })
        }
    }

    public func updateTransform(view: UIView, transform: CGAffineTransform, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.transform = transform
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: {
                view.transform = transform
            }, completion: completion)
        }
    }

    public func updateBounds(view: UIView, bounds: CGRect, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.bounds = bounds
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: {
                view.bounds = bounds
            }, completion: completion)
        }
    }

    public func updatePosition(view: UIView, position: CGPoint, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.center = position
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: {
                view.center = position
            }, completion: completion)
        }
    }

    public func updateCornerRadius(layer: CALayer, cornerRadius: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            layer.cornerRadius = cornerRadius
            completion?(true)
        case let .animated(duration, _):
            let previousCornerRadius = layer.cornerRadius
            layer.cornerRadius = cornerRadius
            layer.animate(from: NSNumber(value: Float(previousCornerRadius)), to: NSNumber(value: Float(cornerRadius)), keyPath: "cornerRadius", duration: duration, completion: { finished in
                completion?(finished)
            })
        }
    }

    private func animate(duration: Double, curve: ContainedViewLayoutTransitionCurve, animations: @escaping () -> Void, completion: ((Bool) -> Void)?) {
        switch curve {
        case .spring:
            UIView.animate(withDuration: duration, delay: 0.0, usingSpringWithDamping: 500.0, initialSpringVelocity: 0.0, options: [.layoutSubviews], animations: animations, completion: completion)
        case let .customSpring(damping, initialVelocity):
            UIView.animate(withDuration: duration, delay: 0.0, usingSpringWithDamping: damping, initialSpringVelocity: initialVelocity, options: [.layoutSubviews], animations: animations, completion: completion)
        case .custom:
            UIView.animate(withDuration: duration, delay: 0.0, options: [curve.viewAnimationOptions, .layoutSubviews], animations: animations, completion: completion)
        default:
            UIView.animate(withDuration: duration, delay: 0.0, options: [curve.viewAnimationOptions, .layoutSubviews], animations: animations, completion: completion)
        }
    }

    // MARK: - Aliases that mirror ComponentTransition API surface.

    public func setFrame(view: UIView, frame: CGRect, completion: ((Bool) -> Void)? = nil) {
        updateFrame(view: view, frame: frame, completion: completion)
    }

    public func setFrame(layer: CALayer, frame: CGRect, completion: ((Bool) -> Void)? = nil) {
        updateFrame(layer: layer, frame: frame, completion: completion)
    }

    public func setAlpha(view: UIView, alpha: CGFloat, completion: ((Bool) -> Void)? = nil) {
        updateAlpha(view: view, alpha: alpha, completion: completion)
    }

    public func setAlpha(layer: CALayer, alpha: CGFloat, completion: ((Bool) -> Void)? = nil) {
        updateAlpha(layer: layer, alpha: alpha, completion: completion)
    }

    public func setBounds(view: UIView, bounds: CGRect, completion: ((Bool) -> Void)? = nil) {
        updateBounds(view: view, bounds: bounds, completion: completion)
    }

    public func setPosition(view: UIView, position: CGPoint, completion: ((Bool) -> Void)? = nil) {
        updatePosition(view: view, position: position, completion: completion)
    }

    public func setCornerRadius(layer: CALayer, cornerRadius: CGFloat, completion: ((Bool) -> Void)? = nil) {
        updateCornerRadius(layer: layer, cornerRadius: cornerRadius, completion: completion)
    }

    public func setScale(view: UIView, scale: CGFloat, completion: ((Bool) -> Void)? = nil) {
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        updateTransform(view: view, transform: transform, completion: completion)
    }

    public func animateView(_ animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            animations()
            completion?(true)
        case let .animated(duration, curve):
            self.animate(duration: duration, curve: curve, animations: animations, completion: completion)
        }
    }

    public func animateAlpha(view: UIView, from: CGFloat, to: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.alpha = to
            completion?(true)
        case let .animated(duration, _):
            view.alpha = from
            self.animate(duration: duration, curve: .easeInOut, animations: {
                view.alpha = to
            }, completion: completion)
        }
    }

    public func animateScale(view: UIView, from: CGFloat, to: CGFloat, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            view.transform = CGAffineTransform(scaleX: to, y: to)
            completion?(true)
        case let .animated(duration, curve):
            view.transform = CGAffineTransform(scaleX: from, y: from)
            self.animate(duration: duration, curve: curve, animations: {
                view.transform = CGAffineTransform(scaleX: to, y: to)
            }, completion: completion)
        }
    }

    public func withAnimation(_ other: ContainedViewLayoutTransition) -> ContainedViewLayoutTransition {
        return other
    }

    public static var none: ContainedViewLayoutTransition { .immediate }

    // MARK: - Additive animations (`animatePositionAdditive` /
    // `animateOffsetAdditive`). These add a CABasicAnimation with
    // `isAdditive = true` on top of the already-set model layer value, so
    // the layer animates FROM `position + offset` TO `position` without us
    // having to twiddle the model value first.

    public func animatePositionAdditive(layer: CALayer, offset: CGPoint, removeOnCompletion: Bool = true, completion: ((Bool) -> Void)? = nil) {
        switch self {
        case .immediate:
            completion?(true)
        case let .animated(duration, curve):
            let animation = CABasicAnimation(keyPath: "position")
            animation.isAdditive = true
            animation.fromValue = NSValue(cgPoint: offset)
            animation.toValue = NSValue(cgPoint: .zero)
            animation.duration = duration
            animation.timingFunction = curve.mediaTimingFunction()
            animation.fillMode = .both
            animation.isRemovedOnCompletion = removeOnCompletion
            if let completion {
                animation.delegate = NavTransitionAnimationDelegate(completion: completion)
            }
            switch curve {
            case .spring, .customSpring:
                let spring = CASpringAnimation(keyPath: "position")
                spring.isAdditive = true
                spring.fromValue = NSValue(cgPoint: offset)
                spring.toValue = NSValue(cgPoint: .zero)
                spring.mass = 1.0
                spring.stiffness = 320.0
                spring.damping = 30.0
                spring.duration = spring.settlingDuration
                spring.fillMode = .both
                spring.isRemovedOnCompletion = removeOnCompletion
                if let completion {
                    spring.delegate = NavTransitionAnimationDelegate(completion: completion)
                }
                layer.add(spring, forKey: "position-additive")
            default:
                layer.add(animation, forKey: "position-additive")
            }
        }
    }

    public func animateOffsetAdditive(layer: CALayer, offset: CGFloat, removeOnCompletion: Bool = true, completion: ((Bool) -> Void)? = nil) {
        animatePositionAdditive(layer: layer, offset: CGPoint(x: 0.0, y: offset), removeOnCompletion: removeOnCompletion, completion: completion)
    }
}

private final class NavTransitionAnimationDelegate: NSObject, CAAnimationDelegate {
    private let completion: (Bool) -> Void
    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        completion(flag)
    }
}
