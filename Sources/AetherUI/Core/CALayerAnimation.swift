import UIKit

extension CAAnimation {
    func aetherPreferHighFrameRate(maximumFramesPerSecond: Int = UIScreen.main.maximumFramesPerSecond) {
        if #available(iOS 15.0, *) {
            let screenMaximum = maximumFramesPerSecond > 0 ? maximumFramesPerSecond : 120
            let preferred = Float(min(120, max(60, screenMaximum)))
            self.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60.0,
                maximum: preferred,
                preferred: preferred
            )
        }
    }
}

extension CALayer {
    static func luminanceToAlpha() -> NSObject? {
        guard let filterClass = NSClassFromString(ObfuscatedSymbols.caFilter) as AnyObject? else {
            return nil
        }
        let selector = NSSelectorFromString(ObfuscatedSymbols.filterWithName)
        guard filterClass.responds(to: selector) else {
            return nil
        }
        return filterClass.perform(selector, with: "luminanceToAlpha")?.takeUnretainedValue() as? NSObject
    }

    static func colorInvert() -> NSObject? {
        guard let filterClass = NSClassFromString(ObfuscatedSymbols.caFilter) as AnyObject? else {
            return nil
        }
        let selector = NSSelectorFromString(ObfuscatedSymbols.filterWithName)
        guard filterClass.responds(to: selector) else {
            return nil
        }
        return filterClass.perform(selector, with: "colorInvert")?.takeUnretainedValue() as? NSObject
    }

    static func colorMatrix() -> NSObject? {
        guard let filterClass = NSClassFromString(ObfuscatedSymbols.caFilter) as AnyObject? else {
            return nil
        }
        let selector = NSSelectorFromString(ObfuscatedSymbols.filterWithName)
        guard filterClass.responds(to: selector) else {
            return nil
        }
        return filterClass.perform(selector, with: "colorMatrix")?.takeUnretainedValue() as? NSObject
    }

    static func blur() -> NSObject? {
        guard let filterClass = NSClassFromString(ObfuscatedSymbols.caFilter) as AnyObject? else {
            return nil
        }
        let selector = NSSelectorFromString(ObfuscatedSymbols.filterWithName)
        guard filterClass.responds(to: selector) else {
            return nil
        }
        return filterClass.perform(selector, with: ObfuscatedSymbols.gaussianBlur)?.takeUnretainedValue() as? NSObject
    }

    /// Private `variableBlur` filter exposed on iOS 26+. Used by `VariableBlurView`
    /// to render progressive edge fades on nav / tab bars.
    static func variableBlur() -> NSObject? {
        guard let filterClass = NSClassFromString(ObfuscatedSymbols.caFilter) as AnyObject? else {
            return nil
        }
        let selector = NSSelectorFromString(ObfuscatedSymbols.filterWithName)
        guard filterClass.responds(to: selector) else {
            return nil
        }
        return filterClass.perform(selector, with: "variableBlur")?.takeUnretainedValue() as? NSObject
    }

    func animate(from: NSValue, to: NSValue, keyPath: String, duration: Double, timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut), completion: ((Bool) -> Void)? = nil) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = timingFunction
        animation.isRemovedOnCompletion = true
        animation.fillMode = .forwards

        if let completion = completion {
            animation.delegate = CALayerAnimationDelegate(completion: completion)
        }

        animation.aetherPreferHighFrameRate()
        self.add(animation, forKey: keyPath)
    }

    func animateFrame(from: CGRect, to: CGRect, duration: Double, timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut), completion: ((Bool) -> Void)? = nil) {
        self.animatePosition(from: CGPoint(x: from.midX, y: from.midY), to: CGPoint(x: to.midX, y: to.midY), duration: duration, timingFunction: timingFunction)
        self.animateBounds(from: CGRect(origin: .zero, size: from.size), to: CGRect(origin: .zero, size: to.size), duration: duration, timingFunction: timingFunction, completion: completion)
    }

    func animatePosition(from: CGPoint, to: CGPoint, duration: Double, timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut), completion: ((Bool) -> Void)? = nil) {
        self.animate(from: NSValue(cgPoint: from), to: NSValue(cgPoint: to), keyPath: "position", duration: duration, timingFunction: timingFunction, completion: completion)
    }

    func animateBounds(from: CGRect, to: CGRect, duration: Double, timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut), completion: ((Bool) -> Void)? = nil) {
        self.animate(from: NSValue(cgRect: from), to: NSValue(cgRect: to), keyPath: "bounds", duration: duration, timingFunction: timingFunction, completion: completion)
    }

    func animateAlpha(from: CGFloat, to: CGFloat, duration: Double, completion: ((Bool) -> Void)? = nil) {
        self.animate(from: NSNumber(value: Float(from)), to: NSNumber(value: Float(to)), keyPath: "opacity", duration: duration, completion: completion)
    }

    func animateScale(from: CGFloat, to: CGFloat, duration: Double, completion: ((Bool) -> Void)? = nil) {
        self.animate(from: NSNumber(value: Float(from)), to: NSNumber(value: Float(to)), keyPath: "transform.scale", duration: duration, completion: completion)
    }
}

private final class CALayerAnimationDelegate: NSObject, CAAnimationDelegate {
    private let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        super.init()
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        self.completion(flag)
    }
}
