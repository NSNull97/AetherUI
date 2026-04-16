import UIKit

// MARK: - TouchEffect
// Direct port of Display framework `TouchEffect` from


final class TouchEffect {
    struct SpringParameters {
        var mass: CGFloat
        var stiffness: CGFloat
        var damping: CGFloat
        var initialVelocity: CGFloat
    }

    struct Parameters {
        var liftOn = SpringParameters(mass: 1.36, stiffness: 568.0, damping: 39.7, initialVelocity: 0.0)
        var liftOff = SpringParameters(mass: 2.0, stiffness: 460.0, damping: 21.8, initialVelocity: 0.0)
        var pressedSizeIncrease: CGFloat = 20.0
    }

    private struct State: Equatable {
        var isTracking: Bool
        var stretchVector: CGPoint
        var touchLocation: CGPoint?
    }

    private weak var view: UIView?
    private weak var highlightContainerView: UIView?

    private let radialHighlightLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.type = .radial

        let baseGradientAlpha: CGFloat = 0.5
        let numSteps = 8
        let firstStep = 1
        let firstLocation = 0.5
        let colors = (0..<numSteps).map { i -> UIColor in
            if i < firstStep {
                return UIColor(white: 1.0, alpha: 1.0)
            } else {
                let step = CGFloat(i - firstStep) / CGFloat(numSteps - firstStep - 1)
                let value = 1.0 - bezierPoint(0.42, 0.0, 0.58, 1.0, step)
                return UIColor(white: 1.0, alpha: baseGradientAlpha * value)
            }
        }
        let locations = (0..<numSteps).map { i -> CGFloat in
            if i < firstStep {
                return 0.0
            } else {
                let step = CGFloat(i - firstStep) / CGFloat(numSteps - firstStep - 1)
                return firstLocation + (1.0 - firstLocation) * step
            }
        }

        layer.colors = colors.map(\.cgColor)
        layer.locations = locations.map { $0 as NSNumber }
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1.0, y: 1.0)
        layer.opacity = 0.0
        layer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "opacity": NSNull(),
        ]
        return layer
    }()

    private var state = State(isTracking: false, stretchVector: .zero, touchLocation: nil)
    private var appliedState: State?

    var parameters = Parameters()

    init(view: UIView, highlightContainerView: UIView?) {
        self.view = view
        self.highlightContainerView = highlightContainerView

        if let highlightContainerView {
            highlightContainerView.layer.addSublayer(self.radialHighlightLayer)
        }
    }

    deinit {
        radialHighlightLayer.removeFromSuperlayer()
    }

    private func currentTransform(for state: State, view: UIView) -> CATransform3D {
        let reference = highlightContainerView ?? view
        let w = max(1.0, reference.bounds.width)
        let h = max(1.0, reference.bounds.height)
        let aspect = w / h

        let baseScaleX: CGFloat
        let baseScaleY: CGFloat
        if state.isTracking {
            if w < h {
                baseScaleY = 1.0 + parameters.pressedSizeIncrease / h
                baseScaleX = baseScaleY
            } else {
                baseScaleX = 1.0 + parameters.pressedSizeIncrease / w
                baseScaleY = baseScaleX
            }
        } else {
            baseScaleX = 1.0
            baseScaleY = 1.0
        }

        guard state.isTracking else {
            return CATransform3DScale(CATransform3DIdentity, baseScaleX, baseScaleY, 1.0)
        }

        let stretch = state.stretchVector
        let adjustedX = stretch.x / aspect
        let length = sqrt(pow(adjustedX, 2) + pow(stretch.y, 2))

        guard length != 0.0 else {
            return CATransform3DScale(CATransform3DIdentity, baseScaleX, baseScaleY, 1.0)
        }

        let normal = CGPoint(x: adjustedX / length, y: stretch.y / length)
        let k: CGFloat = -1.0 / ((length / h) / (5.0 * aspect) + 1.0) + 1.0
        let additionalMaxScale = (h + 16.0 / aspect) / h - 1.0
        let t = additionalMaxScale * k * aspect
        let maxOffset: CGFloat = 24.0

        if abs(normal.x) > abs(normal.y) {
            let diff = abs(normal.x) - abs(normal.y)
            var transform = CATransform3DIdentity
            transform.m11 = baseScaleX * (1.0 + t * diff)
            transform.m22 = baseScaleY * (1.0 / (1.0 + t * diff))
            transform.m41 = normal.x * maxOffset * k
            transform.m42 = normal.y * maxOffset * k
            return transform
        } else {
            let diff = abs(normal.y) - abs(normal.x)
            var transform = CATransform3DIdentity
            transform.m11 = baseScaleX * (1.0 / (1.0 + t * diff))
            transform.m22 = baseScaleY * (1.0 + t * diff)
            transform.m41 = normal.x * maxOffset * k
            transform.m42 = normal.y * maxOffset * k
            return transform
        }
    }

    private func currentSpringParameters(from previous: State?, to state: State) -> SpringParameters {
        guard let previous, previous != state else {
            return state.isTracking ? parameters.liftOn : parameters.liftOff
        }
        if !previous.isTracking, state.isTracking {
            return parameters.liftOn
        } else {
            return parameters.liftOff
        }
    }

    private func updateRadialHighlight(animated: Bool) {
        guard highlightContainerView != nil else { return }

        let baseAlpha: Float = 0.1
        let targetOpacity: Float = state.isTracking ? baseAlpha : 0.0
        let size = CGSize(width: 300.0, height: 300.0)

        if let touch = state.touchLocation {
            radialHighlightLayer.bounds = CGRect(origin: .zero, size: size)
            radialHighlightLayer.position = touch
        }

        if animated {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = radialHighlightLayer.presentation()?.opacity ?? radialHighlightLayer.opacity
            radialHighlightLayer.opacity = targetOpacity
            animation.toValue = targetOpacity
            animation.duration = state.isTracking ? 0.12 : 0.22
            animation.timingFunction = CAMediaTimingFunction(name: state.isTracking ? .easeOut : .easeInEaseOut)
            radialHighlightLayer.add(animation, forKey: "opacity")
        } else {
            radialHighlightLayer.opacity = targetOpacity
        }
    }

    func applyCurrentTransform(animated: Bool = true) {
        guard let view else { return }
        let targetTransform = currentTransform(for: state, view: view)

        if !animated {
            view.layer.removeAnimation(forKey: "sublayerTransform")
            view.layer.sublayerTransform = targetTransform
            updateRadialHighlight(animated: false)
            appliedState = state
            return
        }

        let spring = currentSpringParameters(from: appliedState, to: state)
        let animation = CASpringAnimation(keyPath: "sublayerTransform")
        animation.fromValue = NSValue(caTransform3D: view.layer.presentation()?.sublayerTransform ?? view.layer.sublayerTransform)
        animation.toValue = NSValue(caTransform3D: targetTransform)
        animation.mass = spring.mass
        animation.stiffness = spring.stiffness
        animation.damping = spring.damping
        animation.initialVelocity = spring.initialVelocity
        animation.duration = animation.settlingDuration
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false

        view.layer.sublayerTransform = targetTransform
        view.layer.add(animation, forKey: "sublayerTransform")
        updateRadialHighlight(animated: true)
        appliedState = state
    }

    func setParameters(_ parameters: Parameters, animated: Bool = false) {
        self.parameters = parameters
        applyCurrentTransform(animated: animated)
    }

    func setIsTracking(_ value: Bool, animated: Bool = true) {
        let next = State(
            isTracking: value,
            stretchVector: value ? state.stretchVector : .zero,
            touchLocation: state.touchLocation
        )
        guard state != next else { return }
        state = next
        applyCurrentTransform(animated: animated)
    }

    func setTouchLocation(_ location: CGPoint, animated: Bool = false) {
        let next = State(isTracking: state.isTracking, stretchVector: state.stretchVector, touchLocation: location)
        guard state != next else { return }
        state = next
        applyCurrentTransform(animated: animated)
    }

    func setStretchVector(_ vector: CGPoint, animated: Bool = false) {
        let next = State(isTracking: state.isTracking, stretchVector: vector, touchLocation: state.touchLocation)
        guard state != next else { return }
        state = next
        applyCurrentTransform(animated: animated)
    }
}

// MARK: - GlassHighlightGestureRecognizer
// Direct port of `GlassHighlightGestureRecognizer`.

public final class GlassHighlightGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var highlightContainerView: UIView?

    private var touchEffect: TouchEffect?
    private var initialTouchLocation: CGPoint?
    weak var touchEffectView: UIView?

    var parameters = TouchEffect.Parameters() {
        didSet {
            touchEffect?.setParameters(parameters, animated: false)
        }
    }

    public override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        self.delegate = self
        self.cancelsTouchesInView = false
        self.delaysTouchesBegan = false
        self.delaysTouchesEnded = false
        self.requiresExclusiveTouchType = false
    }

    public override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    public override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    public override func reset() {
        touchEffect?.setIsTracking(false)
        touchEffect = nil
        initialTouchLocation = nil
    }

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view = touchEffectView ?? self.view, let touch = touches.first else { return }
        let location = touch.location(in: view)
        let effect = TouchEffect(view: view, highlightContainerView: highlightContainerView)
        effect.setParameters(parameters, animated: false)
        if let highlightContainerView {
            effect.setTouchLocation(touch.location(in: highlightContainerView), animated: false)
        }
        effect.setStretchVector(.zero, animated: false)
        self.touchEffect = effect
        self.initialTouchLocation = location
        effect.setIsTracking(true)
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        touchEffect?.setIsTracking(false)
        touchEffect = nil
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        touchEffect?.setIsTracking(false)
        touchEffect = nil
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touchEffect,
              let view = touchEffectView ?? self.view,
              let touch = touches.first,
              let initial = initialTouchLocation
        else { return }
        let location = touch.location(in: view)
        if let highlightContainerView {
            touchEffect.setTouchLocation(touch.location(in: highlightContainerView), animated: false)
        }
        touchEffect.setStretchVector(
            CGPoint(x: location.x - initial.x, y: location.y - initial.y),
            animated: false
        )
    }
}
