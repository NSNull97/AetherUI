import UIKit

private let backdropLayerClass: NSObject? = {
    let name = ("CA" as NSString).appendingFormat("BackdropLayer")
    return NSClassFromString(name as String) as AnyObject as? NSObject
}()

private func getMethod<T>(object: NSObject, selector: String) -> T? {
    guard let method = object.method(for: NSSelectorFromString(selector)) else {
        return nil
    }
    return unsafeBitCast(method, to: T.self)
}

private var cachedBackdropLayerAllocMethod: (@convention(c) (AnyObject, Selector) -> NSObject?, Selector)?
private func createBackdropLayerObject() -> NSObject? {
    guard let backdropLayerClass else {
        return nil
    }
    if let cachedBackdropLayerAllocMethod {
        return cachedBackdropLayerAllocMethod.0(backdropLayerClass, cachedBackdropLayerAllocMethod.1)
    }
    let selector = NSSelectorFromString("alloc")
    guard let method: (@convention(c) (AnyObject, Selector) -> NSObject?) = getMethod(object: backdropLayerClass, selector: "alloc") else {
        return nil
    }
    cachedBackdropLayerAllocMethod = (method, selector)
    return method(backdropLayerClass, selector)
}

private var cachedBackdropLayerInitMethod: (@convention(c) (NSObject, Selector) -> NSObject?, Selector)?
private func initializeBackdropLayerObject(_ object: NSObject) -> NSObject? {
    if let cachedBackdropLayerInitMethod {
        return cachedBackdropLayerInitMethod.0(object, cachedBackdropLayerInitMethod.1)
    }
    let selector = NSSelectorFromString("init")
    guard let method: (@convention(c) (AnyObject, Selector) -> NSObject?) = getMethod(object: object, selector: "init") else {
        return nil
    }
    cachedBackdropLayerInitMethod = (method, selector)
    return method(object, selector)
}

private var cachedBackdropLayerSetScaleMethod: (@convention(c) (NSObject, Selector, Double) -> Void, Selector)?
private func setBackdropLayerScale(object: NSObject, scale: Double) {
    if let cachedBackdropLayerSetScaleMethod {
        cachedBackdropLayerSetScaleMethod.0(object, cachedBackdropLayerSetScaleMethod.1, scale)
        return
    }
    let selector = NSSelectorFromString("setScale:")
    guard let method: (@convention(c) (AnyObject, Selector, Double) -> Void) = getMethod(object: object, selector: "setScale:") else {
        return
    }
    cachedBackdropLayerSetScaleMethod = (method, selector)
    method(object, selector, scale)
}

private final class LegacyGlassNullAction: NSObject, CAAction {
    func run(forKey event: String, object anObject: Any, arguments dict: [AnyHashable: Any]?) {
    }
}

private final class LegacyGlassBackdropLayerDelegate: NSObject, CALayerDelegate {
    private let nullAction = LegacyGlassNullAction()

    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        return nullAction
    }
}

public final class LegacyGlassBackdropView: UIView {
    public enum Style: Equatable {
        case normal
        case clear
    }

    private struct Params: Equatable {
        let size: CGSize
        let cornerRadius: CGFloat
        let style: Style
    }

    /// Resolved backend at init time. Snapshotting the global config
    /// here means an in-flight glass surface keeps the backend it was
    /// born with even if `AetherGlassConfig.current` is mutated later.
    private let backend: LegacyBlurBackend

    /// Custom (CABackdropLayer) backend state. Non-nil iff `backend == .custom`.
    private let backdropLayer: CALayer?
    private let backdropLayerDelegate = LegacyGlassBackdropLayerDelegate()

    /// VisualEffectView backend state. Non-nil iff `backend == .visualEffectView`.
    private let visualEffectView: VisualEffectView?

    private var params: Params?

    var hasBackdropLayer: Bool {
        return backdropLayer != nil
    }

    public override init(frame: CGRect) {
        let backend = AetherGlassConfig.current.legacyBlurBackend
        self.backend = backend

        switch backend {
        case .custom:
            self.backdropLayer = createBackdropLayerObject().flatMap(initializeBackdropLayerObject) as? CALayer
            self.visualEffectView = nil
        case let .visualEffectView(blurRadius, tintColor, tintColorAlpha, saturation):
            self.backdropLayer = nil
            let v = VisualEffectView()
            v.style = .customBlur
            v.colorTint = tintColor
            v.colorTintAlpha = tintColorAlpha
            v.blurRadius = blurRadius
            v.saturation = saturation
            v.scale = 1.0
            self.visualEffectView = v
        }

        super.init(frame: frame)

        clipsToBounds = true
        layer.cornerCurve = .circular

        if let backdropLayer {
            layer.addSublayer(backdropLayer)
            backdropLayer.delegate = backdropLayerDelegate
            setBackdropLayerScale(object: backdropLayer, scale: Double(UIScreen.main.scale))
            backdropLayer.rasterizationScale = UIScreen.main.scale
        }

        if let visualEffectView {
            visualEffectView.frame = bounds
            visualEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(visualEffectView)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(size: CGSize, cornerRadius: CGFloat, style: Style, transition: ContainedViewLayoutTransition) {
        let params = Params(size: size, cornerRadius: cornerRadius, style: style)
        let previousStyle = self.params?.style
        self.params = params

        transition.updateCornerRadius(layer: layer, cornerRadius: cornerRadius)

        // VisualEffectView backend has nothing per-style to do —
        // `blurRadius`/`saturation` were set at init from the
        // AetherGlassConfig snapshot. The host view's `clipsToBounds`
        // + `layer.cornerRadius` (set above) shapes the round pill,
        // and `autoresizingMask` keeps the effect view filling the
        // bounds.
        if visualEffectView != nil {
            return
        }

        guard let backdropLayer else {
            return
        }

        if previousStyle != style {
            if let blurFilter = CALayer.blur(), let colorMatrixFilter = CALayer.colorMatrix() {
                // Bigger radius = more pixel mixing = less of any single
                // colour dominating the blur. With the previous 8pt
                // radius and a saturated backdrop (chips, photos) the
                // blur looked like "vivid colour swatches" instead of
                // softened glass. 14pt brings it closer to UIBlurEffect's
                // own kernel and reads as proper material.
                switch style {
                case .clear:
                    blurFilter.setValue(10.0 as NSNumber, forKey: "inputRadius")
                case .normal:
                    blurFilter.setValue(14.0 as NSNumber, forKey: "inputRadius")
                }

                // Original saturation+brightness boost matrix —
                // diagonal coefficients ~2.7, sum-of-row ~1.5. Approximates
                // Apple's stock material vibrancy. Bumps colour saturation
                // and brightness so the blur reads as "lit" frosted
                // material rather than a flat veil. Now that the
                // legacy-only underlay (in MenuGlassSurfaceView) and
                // tint floor (in the modal) flatten the backdrop sample
                // before it hits this filter, the boost no longer "burns"
                // saturated photos through — the underlay tames the
                // input and the matrix takes care of the look on top.
                var matrix: [Float32] = [
                    2.6705, -1.1087999, -0.1117, 0.0, 0.049999997,
                    -0.3295, 1.8914, -0.111899994, 0.0, 0.049999997,
                    -0.3297, -1.1084, 2.8881, 0.0, 0.049999997,
                    0.0, 0.0, 0.0, 1.0, 0.0
                ]
                colorMatrixFilter.setValue(NSValue(bytes: &matrix, objCType: "{CAColorMatrix=ffffffffffffffffffff}"), forKey: "inputColorMatrix")
                colorMatrixFilter.setValue(true as NSNumber, forKey: "inputBackdropAware")

                switch style {
                case .clear:
                    backdropLayer.filters = [blurFilter]
                case .normal:
                    backdropLayer.filters = [colorMatrixFilter, blurFilter]
                }
            }
        }

        transition.updateFrame(layer: backdropLayer, frame: CGRect(origin: .zero, size: size))
    }
}
