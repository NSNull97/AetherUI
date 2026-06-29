import UIKit
import ObjectiveC.runtime
import Darwin

// MARK: - Runtime trampolines (port of UIKitRuntimeUtils setBoolField/setLongLongField)

@inline(__always)
private func glass_method<T>(object: NSObject, selector: String) -> T? {
    guard let method = object.method(for: NSSelectorFromString(selector)) else {
        return nil
    }
    return unsafeBitCast(method, to: T.self)
}

@inline(__always)
private func glass_setBoolField(_ object: NSObject, _ name: String, _ value: Bool) {
    let sel = NSSelectorFromString(name)
    guard object.responds(to: sel) else { return }
    typealias Imp = @convention(c) (NSObject, Selector, Bool) -> Void
    if let impl: Imp = glass_method(object: object, selector: name) {
        impl(object, sel, value)
    }
}

@inline(__always)
private func glass_setLongLongField(_ object: NSObject, _ name: String, _ value: Int64) {
    let sel = NSSelectorFromString(name)
    guard object.responds(to: sel) else { return }
    typealias Imp = @convention(c) (NSObject, Selector, Int64) -> Void
    if let impl: Imp = glass_method(object: object, selector: name) {
        impl(object, sel, value)
    }
}

/// Port of UIKitRuntimeUtils.setMonochromaticEffectImpl.
/// Enables the runtime-only monochrome hooks on iOS 26+ to make image
/// content on glass surfaces render monochromatic.
@inline(__always)
func glassSetMonochromaticEffectImpl(_ view: UIView, isEnabled: Bool) {
    guard #available(iOS 26.0, *) else { return }
    let key1 = ObfuscatedSymbols.setAllowsMonochromaticTreatment
    let key2 = ObfuscatedSymbols.setEnableMonochromaticTreatment
    let key3 = ObfuscatedSymbols.setMonochromaticTreatment

    if isEnabled {
        glass_setBoolField(view, key1, true)
        glass_setBoolField(view, key2, true)
        glass_setLongLongField(view, key3, 2)
    } else {
        glass_setBoolField(view, key1, false)
        glass_setBoolField(view, key2, false)
        glass_setLongLongField(view, key3, 0)
    }
}

// MARK: - Design-compatibility detection

/// `true` when the process is running with the new iOS 26+ "liquid glass"
/// design language. Returns `false` on iOS < 26 *or* when the app opts into
/// legacy look via `Info.plist` key `UIDesignRequiresCompatibility = YES`.
/// Glass components check this to decide between `UIGlassEffect` and a
/// `UIBlurEffect`-based fallback.
public enum GlassCompatibility {
    /// Cached because reading Info.plist on every layout pass is wasteful.
    private static let compatFlag: Bool = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? Bool {
            return value
        }
        // Older ObjC-style boolean entries in the plist can read back as NSNumber.
        if let number = Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? NSNumber {
            return number.boolValue
        }
        return false
    }()

    public static var isLiquidDesignAvailable: Bool {
        if compatFlag { return false }
        if #available(iOS 26.0, *) { return true }
        return false
    }
}

// MARK: - UIView setMonochromaticEffect (port of Display/UIKitUtils.swift)

public extension UIView {
    func setMonochromaticEffect(tintColor: UIColor?) {
        var overrideStyle: UIUserInterfaceStyle = .unspecified
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 1.0
        if let tintColor {
            if tintColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                if red == 0.0, green == 0.0, blue == 0.0, alpha == 1.0 {
                    overrideStyle = .light
                }
            } else {
                if red == 1.0, green == 1.0, blue == 1.0, alpha == 1.0 {
                    overrideStyle = .dark
                }
            }
        }

        if self.overrideUserInterfaceStyle != overrideStyle {
            self.overrideUserInterfaceStyle = overrideStyle
            glassSetMonochromaticEffectImpl(self, isEnabled: overrideStyle != .unspecified)
        }
    }

    func setMonochromaticEffectAndAlpha(tintColor: UIColor?, transition: ContainedViewLayoutTransition) {
        var overrideStyle: UIUserInterfaceStyle = .unspecified
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 1.0
        if let tintColor {
            if tintColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                if red == 0.0, green == 0.0, blue == 0.0 {
                    overrideStyle = .light
                }
            } else {
                if red == 1.0, green == 1.0, blue == 1.0 {
                    overrideStyle = .dark
                }
            }
        }
        if self.overrideUserInterfaceStyle != overrideStyle {
            self.overrideUserInterfaceStyle = overrideStyle
            glassSetMonochromaticEffectImpl(self, isEnabled: overrideStyle != .unspecified)
        }
        transition.updateAlpha(layer: self.layer, alpha: alpha)
    }
}

// MARK: - UIView.animationDurationFactor (port of UIKitUtils.m)

#if targetEnvironment(simulator)
// UIKit has a simulator-only multiplier for the slow-mo overlay. Production
// builds always return 1.0.
private typealias AetherAnimationDurationFactorFunction = @convention(c) () -> Float
private let aetherAnimationDurationFactorFunction: AetherAnimationDurationFactorFunction? = {
    let symbol = ObfuscatedSymbols.uiAnimationDragCoefficient.withCString { name in
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }
    guard let symbol else {
        return nil
    }
    return unsafeBitCast(symbol, to: AetherAnimationDurationFactorFunction.self)
}()
#endif

public extension UIView {
    /// Multiplier callers should apply to animation durations so the simulator
    /// slow-motion debug toggle (`Debug ▸ Slow Animations`) still affects them.
    /// Required for parity with Telegram's `LensTransitionContainer` keyframe
    /// timings; on device this always returns `1.0`.
    static func animationDurationFactor() -> Double {
        #if targetEnvironment(simulator)
        return Double(aetherAnimationDurationFactorFunction?() ?? 1.0)
        #else
        return 1.0
        #endif
    }
}

// MARK: - EffectSettingsContainerView (port of UIViewController+Navigation.m)

/// Host container that carries `lumaMin` / `lumaMax` knobs for nested glass effects.
/// Mirrors the ObjC class that references from `UIGlassEffect` pipelines.
public final class EffectSettingsContainerView: UIView {
    public var lumaMin: Double = 0.0
    public var lumaMax: Double = 0.0

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - UIColor helper (port of `mixedWith` used by glass fill color)

public extension UIColor {
    func mixedWith(_ other: UIColor, alpha: CGFloat) -> UIColor {
        let clampedAlpha = max(0.0, min(1.0, alpha))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

        if !self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1) {
            var white: CGFloat = 0
            self.getWhite(&white, alpha: &a1)
            r1 = white; g1 = white; b1 = white
        }
        if !other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) {
            var white: CGFloat = 0
            other.getWhite(&white, alpha: &a2)
            r2 = white; g2 = white; b2 = white
        }
        return UIColor(
            red: r1 * (1.0 - clampedAlpha) + r2 * clampedAlpha,
            green: g1 * (1.0 - clampedAlpha) + g2 * clampedAlpha,
            blue: b1 * (1.0 - clampedAlpha) + b2 * clampedAlpha,
            alpha: a1 * (1.0 - clampedAlpha) + a2 * clampedAlpha
        )
    }
}

// MARK: - Cubic bezier interpolation (port of Display/Spring.swift bezierPoint)

@inline(__always)
private func glass_bezierA(_ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    return 1.0 - 3.0 * a2 + 3.0 * a1
}

@inline(__always)
private func glass_bezierB(_ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    return 3.0 * a2 - 6.0 * a1
}

@inline(__always)
private func glass_bezierC(_ a1: CGFloat) -> CGFloat {
    return 3.0 * a1
}

@inline(__always)
private func glass_calcBezier(_ t: CGFloat, _ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    return ((glass_bezierA(a1, a2) * t + glass_bezierB(a1, a2)) * t + glass_bezierC(a1)) * t
}

@inline(__always)
private func glass_calcSlope(_ t: CGFloat, _ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
    return 3.0 * glass_bezierA(a1, a2) * t * t + 2.0 * glass_bezierB(a1, a2) * t + glass_bezierC(a1)
}

private func glass_getTForX(_ x: CGFloat, _ x1: CGFloat, _ x2: CGFloat) -> CGFloat {
    var t = x
    for _ in 0..<4 {
        let slope = glass_calcSlope(t, x1, x2)
        if slope == 0.0 {
            return t
        }
        let currentX = glass_calcBezier(t, x1, x2) - x
        t -= currentX / slope
    }
    return t
}

public func bezierPoint(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat) -> CGFloat {
    var value = glass_calcBezier(glass_getTForX(x, x1, x2), y1, y2)
    if value >= 0.997 {
        value = 1.0
    }
    return value
}

// MARK: - CGContext helper (port of addBadgePath)

extension CGContext {
    /// Rounded-cap path used by `generateLegacyGlassImage` for glass edge generation.
    func addBadgePath(in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.minY)
        scaleBy(x: rect.width / 78.0, y: rect.height / 78.0)

        move(to: CGPoint(x: 0, y: 39))
        addCurve(to: CGPoint(x: 39, y: 0),
                 control1: CGPoint(x: 0, y: 17.4609),
                 control2: CGPoint(x: 17.4609, y: 0))
        addLine(to: CGPoint(x: 42, y: 0))
        addCurve(to: CGPoint(x: 78, y: 36),
                 control1: CGPoint(x: 61.8823, y: 0),
                 control2: CGPoint(x: 78, y: 16.1177))
        addLine(to: CGPoint(x: 78, y: 39))
        addCurve(to: CGPoint(x: 39, y: 78),
                 control1: CGPoint(x: 78, y: 60.5391),
                 control2: CGPoint(x: 60.5391, y: 78))
        addLine(to: CGPoint(x: 36, y: 78))
        addCurve(to: CGPoint(x: 0, y: 42),
                 control1: CGPoint(x: 16.1177, y: 78),
                 control2: CGPoint(x: 0, y: 61.8823))
        addLine(to: CGPoint(x: 0, y: 39))
        closePath()

        restoreGState()
    }
}
