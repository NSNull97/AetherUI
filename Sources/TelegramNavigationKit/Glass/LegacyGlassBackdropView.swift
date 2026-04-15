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

final class LegacyGlassBackdropView: UIView {
    enum Style: Equatable {
        case normal
        case clear
    }

    private struct Params: Equatable {
        let size: CGSize
        let cornerRadius: CGFloat
        let style: Style
    }

    private let backdropLayer: CALayer?
    private let backdropLayerDelegate = LegacyGlassBackdropLayerDelegate()
    private var params: Params?

    var hasBackdropLayer: Bool {
        return backdropLayer != nil
    }

    override init(frame: CGRect) {
        self.backdropLayer = createBackdropLayerObject().flatMap(initializeBackdropLayerObject) as? CALayer
        super.init(frame: frame)

        clipsToBounds = true
        layer.cornerCurve = .circular

        if let backdropLayer {
            layer.addSublayer(backdropLayer)
            backdropLayer.delegate = backdropLayerDelegate
            setBackdropLayerScale(object: backdropLayer, scale: Double(UIScreen.main.scale))
            backdropLayer.rasterizationScale = UIScreen.main.scale
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(size: CGSize, cornerRadius: CGFloat, style: Style, transition: ContainedViewLayoutTransition) {
        let params = Params(size: size, cornerRadius: cornerRadius, style: style)
        let previousStyle = self.params?.style
        self.params = params

        transition.updateCornerRadius(layer: layer, cornerRadius: cornerRadius)

        guard let backdropLayer else {
            return
        }

        if previousStyle != style {
            if let blurFilter = CALayer.blur(), let colorMatrixFilter = CALayer.colorMatrix() {
                switch style {
                case .clear:
                    blurFilter.setValue(6.0 as NSNumber, forKey: "inputRadius")
                case .normal:
                    blurFilter.setValue(2.0 as NSNumber, forKey: "inputRadius")
                }

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
