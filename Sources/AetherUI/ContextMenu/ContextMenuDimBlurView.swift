import UIKit

// MARK: - CABackdropLayer runtime helpers
//
// Same pattern as `LegacyGlassBackdropView` — we can't refer to
// `CABackdropLayer` by name because it's private, so instantiate it
// via the Obj-C runtime. Once we have the layer object, we can use
// it like any other `CALayer` and attach a `gaussianBlur` `CAFilter`
// to its `filters` property.

private let backdropLayerClass: NSObject? = {
    return NSClassFromString(ObfuscatedSymbols.caBackdropClass) as AnyObject as? NSObject
}()

private func makeBackdropLayer() -> CALayer? {
    guard let cls = backdropLayerClass else { return nil }
    let allocSel = NSSelectorFromString("alloc")
    let initSel = NSSelectorFromString("init")
    guard cls.responds(to: allocSel) else { return nil }
    guard let alloc = cls.perform(allocSel)?.takeUnretainedValue() as? NSObject else {
        return nil
    }
    return alloc.perform(initSel)?.takeUnretainedValue() as? CALayer
}

// MARK: - ContextMenuDimBlurView

/// Dim layer for the context menu background. Uses a raw
/// `CABackdropLayer` + `CAFilter("gaussianBlur")` instead of a
/// `UIVisualEffectView` so the blur radius is continuously tunable —
/// `UIBlurEffect` has only a few coarse fixed styles, none of which
/// produce the very-light "just-barely-blurred" look we want for the
/// context menu background (radius ~2pt). Falls back to a plain tint
/// view on platforms where the private `CABackdropLayer` isn't
/// available.
final class ContextMenuDimBlurView: UIView {
    private let backdropLayer: CALayer?
    private let tint = UIView()

    var blurRadius: CGFloat {
        didSet {
            guard oldValue != blurRadius else { return }
            applyBlur()
        }
    }

    var tintAlpha: CGFloat {
        didSet {
            guard oldValue != tintAlpha else { return }
            tint.backgroundColor = UIColor.black.withAlphaComponent(tintAlpha)
        }
    }

    init(blurRadius: CGFloat, tintAlpha: CGFloat) {
        self.blurRadius = blurRadius
        self.tintAlpha = tintAlpha
        self.backdropLayer = makeBackdropLayer()

        super.init(frame: .zero)

        if let backdropLayer {
            // Backdrop layers sample at 1× by default; lifting to the
            // screen scale avoids pixel-stepping on the blurred
            // result.
            backdropLayer.setValue(Double(UIScreen.main.scale), forKey: ObfuscatedSymbols.scale)
            backdropLayer.rasterizationScale = UIScreen.main.scale
            layer.addSublayer(backdropLayer)
        }

        tint.isUserInteractionEnabled = false
        tint.backgroundColor = UIColor.black.withAlphaComponent(tintAlpha)
        addSubview(tint)

        applyBlur()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropLayer?.frame = bounds
        tint.frame = bounds
        CATransaction.commit()
    }

    private func applyBlur() {
        guard let backdropLayer else { return }
        guard let filter = CALayer.blur() else {
            backdropLayer.filters = nil
            return
        }
        filter.setValue(blurRadius as NSNumber, forKey: ObfuscatedSymbols.inputRadius)
        backdropLayer.filters = [filter]
    }
}
