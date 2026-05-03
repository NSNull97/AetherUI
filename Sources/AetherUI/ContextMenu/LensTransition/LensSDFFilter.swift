import UIKit

// MARK: - LensSDFFilter

/// Thin wrapper that installs Telegram's iOS-26 SDF lens displacement filter
/// chain on a target `CALayer` and exposes the two animatable knobs:
///
///   - `displacement.height` — drives `sublayers.sdfLayer.effect.height` and
///     mirrors it on `filters.displacementMap.inputAmount` (negated).
///     Larger value = stronger "bulge" distortion.
///   - `gaussianBlur.inputRadius` — soft blur applied alongside the
///     displacement so the morphing edges look glassy.
///
/// On iOS < 26 (or when the private CASDFLayer / CASDFGlassDisplacementEffect
/// classes can't be resolved at runtime), `init?` returns nil and the caller
/// degrades to a non-distorted morph.
@available(iOS 26.0, *)
final class LensSDFFilter {
    private let sdfLayer: CALayer
    private let sdfElementLayer: CALayer
    private let displacementEffect: NSObject
    private let blurFilter: NSObject
    private let displacementFilter: NSObject

    private weak var targetLayer: CALayer?
    private var previousFilters: [Any]?
    /// `true` when our own `blurFilter` is part of `target.filters`
    /// (i.e. we installed on a plain layer). When installed on a
    /// system-managed backdrop layer we append ONLY our
    /// `displacementFilter`, so `animateBlur` has no matching name to
    /// write to and becomes a no-op (we don't want to stomp the
    /// system's blur keypath).
    private var ownsBlurFilter: Bool = true
    private let emptyLayerDelegate = SDFEmptyLayerDelegate()

    // MARK: - Init

    init?() {
        guard
            let sdfElement = aether_makeSDFObject("CASDFElementLayer") as? CALayer,
            let sdf = aether_makeSDFObject("CASDFLayer") as? CALayer,
            let effect = aether_makeSDFObject("CASDFGlassDisplacementEffect"),
            let blur = aether_makeCAFilter(name: ObfuscatedSymbols.gaussianBlur),
            let displacement = aether_makeCAFilter(name: ObfuscatedSymbols.displacementMap)
        else {
            return nil
        }

        self.sdfElementLayer = sdfElement
        self.sdfLayer = sdf
        self.displacementEffect = effect
        self.blurFilter = blur
        self.displacementFilter = displacement

        configureLayers()
        configureFilters()
    }

    private func configureLayers() {
        displacementEffect.setValue(1.0, forKey: ObfuscatedSymbols.curvature)
        displacementEffect.setValue(0.0 as NSNumber, forKey: ObfuscatedSymbols.angle)

        sdfLayer.name = "sdfLayer"
        sdfLayer.setValue(3.0, forKey: ObfuscatedSymbols.scale)
        sdfLayer.setValue(displacementEffect, forKey: ObfuscatedSymbols.effect)
        sdfLayer.delegate = emptyLayerDelegate

        sdfElementLayer.setValue(0.5 as NSNumber, forKey: ObfuscatedSymbols.gradientOvalization)
        sdfElementLayer.isOpaque = true
        sdfElementLayer.allowsEdgeAntialiasing = true
        let sdfLayerDelegate = unsafeBitCast(sdfLayer, to: CALayerDelegate.self)
        sdfElementLayer.delegate = sdfLayerDelegate
        sdfElementLayer.setValue(3.0, forKey: ObfuscatedSymbols.scale)
        sdfLayer.addSublayer(sdfElementLayer)
    }

    private func configureFilters() {
        aether_setCAFilterName(blurFilter, ObfuscatedSymbols.gaussianBlur)
        aether_setCAFilterName(displacementFilter, ObfuscatedSymbols.displacementMap)
        displacementFilter.setValue("sdfLayer", forKey: ObfuscatedSymbols.inputSourceSublayerName)
    }

    // MARK: - Install / uninstall

    /// Attach the SDF + filter chain to `target`. Subsequent layout
    /// changes should be relayed via `updateLayout(size:cornerRadius:)`.
    ///
    /// When `preserveExistingFilters` is true, our displacement filter
    /// is APPENDED to whatever `target.filters` already holds — needed
    /// when the target is a `CABackdropLayer` (e.g. the one inside
    /// `_UIVisualEffectBackdropView`) that already carries a
    /// `gaussianBlur` chain for the glass blur. Overwriting would kill
    /// the glass. When false, our blur+displacement chain replaces
    /// `target.filters` entirely — appropriate for a plain-UIView layer
    /// that has no filters of its own.
    ///
    /// Critically the `displacementMap` filter entry here is what
    /// "consumes" the `sdfLayer` sublayer as its displacement source —
    /// without a live filter chain referencing it by
    /// `inputSourceSublayerName`, Core Animation renders `sdfElementLayer`
    /// as opaque content and the glass goes uniformly dark.
    func install(
        on target: CALayer,
        size: CGSize,
        cornerRadius: CGFloat,
        preserveExistingFilters: Bool = false
    ) {
        targetLayer = target
        target.insertSublayer(sdfLayer, at: 0)
        target.rasterizationScale = 3.0
        if preserveExistingFilters {
            // Remember the pre-existing filter chain (system glass blur
            // etc.) so `uninstall` can restore it exactly instead of
            // nilling out and leaving the backdrop un-blurred.
            // Intentionally do NOT add our `blurFilter` — there's
            // already a system blur in the chain and chaining ours
            // would either double-blur or make the keypath
            // `filters.gaussianBlur.inputRadius` ambiguous.
            previousFilters = target.filters
            var chain = target.filters ?? []
            chain.append(displacementFilter)
            target.filters = chain
            ownsBlurFilter = false
        } else {
            previousFilters = nil
            target.filters = [blurFilter, displacementFilter]
            ownsBlurFilter = true
        }
        updateLayout(size: size, cornerRadius: cornerRadius)
    }

    func uninstall() {
        if let previousFilters {
            targetLayer?.filters = previousFilters
        } else {
            targetLayer?.filters = nil
        }
        previousFilters = nil
        sdfLayer.removeFromSuperlayer()
        targetLayer = nil
    }

    // MARK: - Layout

    func updateLayout(size: CGSize, cornerRadius: CGFloat) {
        let bounds = CGRect(origin: .zero, size: size)
        sdfLayer.frame = bounds
        sdfElementLayer.frame = bounds
        sdfLayer.cornerRadius = cornerRadius
        sdfElementLayer.cornerRadius = cornerRadius
    }

    // MARK: - Animation knobs

    /// Animate `effect.height` (= `displacementMap.inputAmount` × -1) over
    /// `duration`. The keypath chain matches Telegram's `LensTransitionContainerImpl`
    /// so the linear `displacementFractionEase` keyframes carry over.
    func animateDisplacement(fromHeight: CGFloat, toHeight: CGFloat, duration: TimeInterval) {
        guard let targetLayer else { return }

        // 30-sample keyframes via displacementFractionEase (linear blend
        // between fromHeight and toHeight per sample).
        let sampleCount = 30
        let endIndex = CGFloat(sampleCount - 1)
        let heightKeyframes: [CGFloat] = (0 ..< sampleCount).map { i in
            let t = endIndex > 0 ? CGFloat(i) / endIndex : 1.0
            let f = max(0.0, min(1.0, displacementFractionEase(Double(t))))
            return (1.0 - f) * fromHeight + f * toHeight
        }

        // Model values set to 0 — after the keyframe animation is
        // removed on completion, the displayed value reverts to 0
        // and the lens is fully off. Used for the DISMISS path where
        // the menu is about to go away; the open path uses
        // `animateDisplacementPulse` instead, which has its own
        // model-value setup so the lens finalises to zero at rest.
        if ownsBlurFilter {
            targetLayer.setValue(0.0 as NSNumber, forKeyPath: ObfuscatedSymbols.keypath(ObfuscatedSymbols.filters, ObfuscatedSymbols.gaussianBlur, ObfuscatedSymbols.inputRadius))
        }
        targetLayer.setValue(0.0 as NSNumber, forKeyPath: ObfuscatedSymbols.keypath("sublayers", "sdfLayer", ObfuscatedSymbols.effect, ObfuscatedSymbols.height))
        targetLayer.setValue(0.0 as NSNumber, forKeyPath: ObfuscatedSymbols.keypath(ObfuscatedSymbols.filters, ObfuscatedSymbols.displacementMap, ObfuscatedSymbols.inputAmount))

        let scale = UIView.animationDurationFactor()

        let heightAnim = CAKeyframeAnimation(keyPath: ObfuscatedSymbols.keypath("sublayers", "sdfLayer", ObfuscatedSymbols.effect, ObfuscatedSymbols.height))
        heightAnim.duration = duration * scale
        heightAnim.values = heightKeyframes.map { $0 as NSNumber }
        heightAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        heightAnim.isRemovedOnCompletion = true
        heightAnim.fillMode = .both
        targetLayer.add(heightAnim, forKey: ObfuscatedSymbols.keypath("sublayers", "sdfLayer", ObfuscatedSymbols.effect, ObfuscatedSymbols.height))

        let dispAnim = CAKeyframeAnimation(keyPath: ObfuscatedSymbols.keypath(ObfuscatedSymbols.filters, ObfuscatedSymbols.displacementMap, ObfuscatedSymbols.inputAmount))
        dispAnim.duration = duration * scale
        dispAnim.values = heightKeyframes.map { -$0 as NSNumber }
        dispAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        dispAnim.isRemovedOnCompletion = true
        dispAnim.fillMode = .both
        targetLayer.add(dispAnim, forKey: ObfuscatedSymbols.keypath(ObfuscatedSymbols.filters, ObfuscatedSymbols.displacementMap, ObfuscatedSymbols.inputAmount))
    }

    /// Animate `effect.height` as a HOLD-then-DECAY (or RISE-then-HOLD
    /// when `reversed == true`) pulse. Open: stays at `peakHeight` for
    /// the first ~55 % of the duration, smoothsteps to 0 between 55 %
    /// and 88 %, holds 0 for the last 12 %. Close (`reversed: true`)
    /// is the exact time-reverse — held at 0 for the first 12 %, rises
    /// to peak between 12 % and 45 %, then holds peak to the end.
    /// Using the same shape in both directions keeps the SDF
    /// choreography symmetric to match the geometry spring.
    func animateDisplacementPulse(peakHeight: CGFloat, duration: TimeInterval, reversed: Bool = false) {
        guard let targetLayer else { return }

        let sampleCount = 30
        let endIndex = CGFloat(sampleCount - 1)
        // Open shape: hold peak through the first 55 %, decay to 0
        // between 55 % and 88 %, hold 0 for the last 12 % (visibly
        // FINISHED before the geometry spring settles). Close shape
        // is `open` played in reverse — same smoothstep, same three
        // phases, just mirrored so the lens rises from 0 to peak as
        // the menu collapses.
        let holdUntil: CGFloat = 0.55
        let decayEnd: CGFloat = 0.88
        let heightKeyframes: [CGFloat] = (0 ..< sampleCount).map { i in
            let tRaw = endIndex > 0 ? CGFloat(i) / endIndex : 1.0
            let t = reversed ? (1.0 - tRaw) : tRaw
            let decay: CGFloat
            if t <= holdUntil {
                decay = 0
            } else if t >= decayEnd {
                decay = 1
            } else {
                let localT = (t - holdUntil) / (decayEnd - holdUntil)
                decay = localT * localT * (3 - 2 * localT)
            }
            return peakHeight * (1.0 - decay)
        }

        // Model value = last keyframe. For the open pulse that's 0 —
        // lens finalises cleanly. For the reversed close pulse that's
        // peakHeight, which doesn't matter visually because the host
        // layer is torn down right after the close animation ends.
        //
        // Critically send actual 0 on the open path (no `max(0.001, _)`
        // floor) — a residual -0.001 on `inputAmount` leaves the
        // displacement filter visibly "on" at rest, which eats away at
        // the settled menu's corner rounding (the edges sample from
        // the nearly-zero SDF distance field and round-trip through a
        // tiny displacement). At actual zero, the filter is a no-op
        // and the rounded-rect shape mask shows through cleanly.
        let finalHeight = heightKeyframes.last ?? 0
        if ownsBlurFilter {
            targetLayer.setValue(0.0 as NSNumber, forKeyPath: ObfuscatedSymbols.keypath(ObfuscatedSymbols.filters, ObfuscatedSymbols.gaussianBlur, ObfuscatedSymbols.inputRadius))
        }
        targetLayer.setValue(finalHeight as NSNumber, forKeyPath: ObfuscatedSymbols.keypath("sublayers", "sdfLayer", ObfuscatedSymbols.effect, ObfuscatedSymbols.height))
        targetLayer.setValue(-finalHeight as NSNumber, forKeyPath: ObfuscatedSymbols.keypath(ObfuscatedSymbols.filters, ObfuscatedSymbols.displacementMap, ObfuscatedSymbols.inputAmount))

        let scale = UIView.animationDurationFactor()

        let heightAnim = CAKeyframeAnimation(keyPath: ObfuscatedSymbols.keypath("sublayers", "sdfLayer", ObfuscatedSymbols.effect, ObfuscatedSymbols.height))
        heightAnim.duration = duration * scale
        heightAnim.values = heightKeyframes.map { $0 as NSNumber }
        heightAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        heightAnim.isRemovedOnCompletion = true
        heightAnim.fillMode = .both
        targetLayer.add(heightAnim, forKey: ObfuscatedSymbols.keypath("sublayers", "sdfLayer", ObfuscatedSymbols.effect, ObfuscatedSymbols.height))

        let dispAnim = CAKeyframeAnimation(keyPath: ObfuscatedSymbols.keypath(ObfuscatedSymbols.filters, ObfuscatedSymbols.displacementMap, ObfuscatedSymbols.inputAmount))
        dispAnim.duration = duration * scale
        dispAnim.values = heightKeyframes.map { -$0 as NSNumber }
        dispAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        dispAnim.isRemovedOnCompletion = true
        dispAnim.fillMode = .both
        targetLayer.add(dispAnim, forKey: ObfuscatedSymbols.keypath(ObfuscatedSymbols.filters, ObfuscatedSymbols.displacementMap, ObfuscatedSymbols.inputAmount))
    }

    /// Animate `gaussianBlur.inputRadius` via the file-private `blurEase`
    /// curve (matches Telegram's lens blur ramp). No-op when the SDF
    /// was installed onto a layer that already had its own filter
    /// chain (= backdrop mode) — touching the shared keypath would
    /// either hit the wrong filter or stomp on the system's blur.
    func animateBlur(duration: TimeInterval) {
        guard ownsBlurFilter else { return }
        guard let targetLayer else { return }

        let sampleCount = 30
        let endIndex = CGFloat(sampleCount - 1)
        let blurKeyframes: [CGFloat] = (0 ..< sampleCount).map { i in
            let t = endIndex > 0 ? CGFloat(i) / endIndex : 1.0
            return CGFloat(blurEase(Double(t)))
        }

        let blurAnim = CAKeyframeAnimation(keyPath: ObfuscatedSymbols.keypath(ObfuscatedSymbols.filters, ObfuscatedSymbols.gaussianBlur, ObfuscatedSymbols.inputRadius))
        blurAnim.duration = duration * UIView.animationDurationFactor()
        blurAnim.values = blurKeyframes.map { $0 as NSNumber }
        blurAnim.timingFunction = CAMediaTimingFunction(name: .linear)
        blurAnim.isRemovedOnCompletion = true
        blurAnim.fillMode = .both
        targetLayer.add(blurAnim, forKey: ObfuscatedSymbols.keypath(ObfuscatedSymbols.filters, ObfuscatedSymbols.gaussianBlur, ObfuscatedSymbols.inputRadius))
    }
}

// MARK: - Helpers

private final class SDFEmptyLayerDelegate: NSObject, CALayerDelegate {
    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        return NSNull()
    }
}
