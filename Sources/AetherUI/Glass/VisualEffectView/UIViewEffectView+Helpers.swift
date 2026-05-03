//
//  UIVisualEffectView+Helpers.swift
//  VisualEffectView
//
//  Created by Lasha Efremidze on 9/14/20.
//

import UIKit

extension UIVisualEffectView {
    var backdropView: UIView? {
        return subview(of: NSClassFromString(ObfuscatedSymbols.uiVisualEffectBackdropView))
    }
    var overlayView: UIView? {
        return subview(of: NSClassFromString(ObfuscatedSymbols.uiVisualEffectSubview))
    }
    var gaussianBlur: NSObject? {
        return backdropView?.value(forKey: ObfuscatedSymbols.filters, withFilterType: ObfuscatedSymbols.gaussianBlur)
    }
    var sourceOver: NSObject? {
        return overlayView?.value(forKey: ObfuscatedSymbols.viewEffects, withFilterType: ObfuscatedSymbols.sourceOver)
    }
    func prepareForChanges() {
        self.effect = UIBlurEffect(style: .light)
        gaussianBlur?.setValue(1.0, forKeyPath: ObfuscatedSymbols.requestedScaleHint)
    }
    func applyChanges() {
        backdropView?.perform(NSSelectorFromString(ObfuscatedSymbols.applyRequestedFilterEffects))
    }
}

extension NSObject {
    var requestedValues: [String: Any]? {
        get { return value(forKeyPath: ObfuscatedSymbols.requestedValues) as? [String: Any] }
        set { setValue(newValue, forKeyPath: ObfuscatedSymbols.requestedValues) }
    }
    func value(forKey key: String, withFilterType filterType: String) -> NSObject? {
        return (value(forKeyPath: key) as? [NSObject])?.first { $0.value(forKeyPath: ObfuscatedSymbols.filterType) as? String == filterType }
    }
}

private extension UIView {
    func subview(of classType: AnyClass?) -> UIView? {
        return subviews.first { type(of: $0) == classType }
    }
}
