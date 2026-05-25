import UIKit
import CoreImage

final class ContextMenuSourcePlatterBloomTransitionView: UIView {
    static var debugFrozenProgress: CGFloat?

    let finalMenuGlassSurfaceView: MenuGlassSurfaceView
    let sourceProxyContainer = UIView()
    let liveMenuContentView = UIView()

    var contentRevealProgressChanged: ((CGFloat) -> Void)?

    private let sourceFrameInOverlay: CGRect
    private let targetMenuFrameInOverlay: CGRect
    private let finalCornerRadius: CGFloat
    private let sourceCornerRadius: CGFloat
    private let sourceMode: ContextMenuSourceVisualMode

    private let shadowView = UIView()
    private let ambientShadowLayer = CAShapeLayer()
    private let contactShadowLayer = CAShapeLayer()
    private let snapshotContainer = UIView()
    private let blurredMenuSnapshotView = UIImageView()
    private let sharpMenuSnapshotView = UIImageView()
    private let highlightView = UIView()
    private let highlightLayer = CAGradientLayer()
    private let progressDriverView = UIView(frame: .zero)
    private var surfaceSDFFilter: AnyObject?
    private var contentSDFFilter: AnyObject?

    private var progress: CGFloat = 0
    private var progressAnimator: UIViewPropertyAnimator?
    private var progressDisplayLink: CADisplayLink?
    private var animationFrom: CGFloat = 0
    private var animationTo: CGFloat = 0
    private var animationDirection: CGFloat = 1
    private var animationCompletion: (() -> Void)?

    init(
        sourceFrameInOverlay: CGRect,
        targetMenuFrameInOverlay: CGRect,
        finalCornerRadius: CGFloat,
        sourceCornerRadius: CGFloat,
        sourceMode: ContextMenuSourceVisualMode,
        isDark: Bool
    ) {
        self.sourceFrameInOverlay = sourceFrameInOverlay
        self.targetMenuFrameInOverlay = targetMenuFrameInOverlay
        self.finalCornerRadius = finalCornerRadius
        self.sourceCornerRadius = sourceCornerRadius
        self.sourceMode = sourceMode
        self.finalMenuGlassSurfaceView = MenuGlassSurfaceView(isDark: isDark)

        super.init(frame: .zero)

        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false
        progressDriverView.frame = CGRect(x: -4, y: -4, width: 1, height: 1)
        progressDriverView.backgroundColor = .clear
        progressDriverView.isUserInteractionEnabled = false
        addSubview(progressDriverView)

        shadowView.backgroundColor = .clear
        shadowView.isUserInteractionEnabled = false
        shadowView.layer.masksToBounds = false
        addSubview(shadowView)
        configureShadowLayer(ambientShadowLayer)
        configureShadowLayer(contactShadowLayer)
        shadowView.layer.addSublayer(ambientShadowLayer)
        shadowView.layer.addSublayer(contactShadowLayer)

        finalMenuGlassSurfaceView.clipsToBounds = false
        finalMenuGlassSurfaceView.layer.masksToBounds = false
        addSubview(finalMenuGlassSurfaceView)

        highlightView.isUserInteractionEnabled = false
        highlightView.backgroundColor = .clear
        highlightLayer.type = .radial
        highlightLayer.colors = [
            UIColor.white.withAlphaComponent(isDark ? 0.24 : 0.34).cgColor,
            UIColor.white.withAlphaComponent(isDark ? 0.08 : 0.14).cgColor,
            UIColor.white.withAlphaComponent(0.0).cgColor
        ]
        highlightLayer.locations = [0.0, 0.38, 1.0]
        highlightLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        highlightLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        highlightView.layer.addSublayer(highlightLayer)
        finalMenuGlassSurfaceView.contentView.addSubview(highlightView)

        snapshotContainer.isUserInteractionEnabled = false
        snapshotContainer.clipsToBounds = false
        finalMenuGlassSurfaceView.contentView.addSubview(snapshotContainer)

        blurredMenuSnapshotView.contentMode = .scaleAspectFit
        blurredMenuSnapshotView.clipsToBounds = false
        blurredMenuSnapshotView.isUserInteractionEnabled = false
        snapshotContainer.addSubview(blurredMenuSnapshotView)

        sharpMenuSnapshotView.contentMode = .scaleAspectFit
        sharpMenuSnapshotView.clipsToBounds = false
        sharpMenuSnapshotView.isUserInteractionEnabled = false
        snapshotContainer.addSubview(sharpMenuSnapshotView)

        installContentDistortionFilterIfAvailable()

        // Selection is driven by the recognizer on MenuGlassSurfaceView.
        // Keep this wrapper passive so touches reach the glass material and
        // native UIGlassEffect.isInteractive can stretch the menu container.
        liveMenuContentView.isUserInteractionEnabled = false
        finalMenuGlassSurfaceView.contentView.addSubview(liveMenuContentView)

        sourceProxyContainer.isUserInteractionEnabled = false
        sourceProxyContainer.clipsToBounds = true
        finalMenuGlassSurfaceView.contentView.addSubview(sourceProxyContainer)

        setProgress(0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if #available(iOS 26.0, *), let filter = surfaceSDFFilter as? LensSDFFilter {
            filter.uninstall()
        }
        if #available(iOS 26.0, *), let filter = contentSDFFilter as? LensSDFFilter {
            filter.uninstall()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateGeometry(progress: progress)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        finalMenuGlassSurfaceView.frame.contains(point)
    }

    func setProgress(_ progress: CGFloat) {
        cancelAnimation()
        self.progress = max(0, min(1, progress))
        updateGeometry(progress: self.progress)
    }

    func animateExpand(duration: TimeInterval, damping _: CGFloat, completion: (() -> Void)? = nil) {
        if let frozenProgress = Self.debugFrozenProgress {
            setProgress(frozenProgress)
            completion?()
            return
        }
        animateProgress(to: 1, duration: duration) { [weak self] in
            self?.finishToFinalMenu()
            completion?()
        }
    }

    func animateCollapse(duration: TimeInterval, damping _: CGFloat, completion: (() -> Void)? = nil) {
        animateProgress(to: 0, duration: duration) { [weak self] in
            self?.cancelOrDismiss()
            completion?()
        }
    }

    func prepareMenuContentSnapshots(from view: UIView) {
        view.layoutIfNeeded()
        let image = Self.renderImage(from: view)
        sharpMenuSnapshotView.image = image
        blurredMenuSnapshotView.image = Self.blurredImage(from: image, radius: 14.0) ?? image
        updateContentFrames(for: finalMenuGlassSurfaceView.bounds)
    }

    func finishToFinalMenu() {
        cancelAnimation()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progress = 1
        let metrics = currentMetrics(rawT: 1)
        apply(metrics: metrics, rawT: 1)
        sourceProxyContainer.alpha = 0
        sourceProxyContainer.isHidden = true
        snapshotContainer.alpha = 0
        blurredMenuSnapshotView.alpha = 0
        sharpMenuSnapshotView.alpha = 0
        liveMenuContentView.alpha = 1
        updateSurfaceSDFDistortion(rawT: 1)
        updateContentSDFDistortion(rawT: 1, liveT: 1)
        contentRevealProgressChanged?(1)
        CATransaction.commit()
    }

    func cancelOrDismiss() {
        cancelAnimation()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progress = 0
        let metrics = currentMetrics(rawT: 0)
        apply(metrics: metrics, rawT: 0)
        updateSurfaceSDFDistortion(rawT: 0)
        updateContentSDFDistortion(rawT: 0, liveT: 0)
        contentRevealProgressChanged?(0)
        CATransaction.commit()
    }

    private func updateGeometry(progress rawT: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(metrics: currentMetrics(rawT: rawT), rawT: rawT)
        CATransaction.commit()
    }

    private func apply(metrics: Metrics, rawT: CGFloat) {
        finalMenuGlassSurfaceView.frame = metrics.frame
        finalMenuGlassSurfaceView.setSurfaceCornerRadius(metrics.cornerRadius)
        finalMenuGlassSurfaceView.updateMaterialThickness(materialProgress(rawT))

        shadowView.frame = metrics.frame
        ambientShadowLayer.frame = shadowView.bounds
        contactShadowLayer.frame = shadowView.bounds
        let shadowPath = UIBezierPath(
            roundedRect: shadowView.bounds,
            cornerRadius: metrics.cornerRadius
        ).cgPath
        ambientShadowLayer.shadowPath = shadowPath
        contactShadowLayer.shadowPath = shadowPath
        updateShadow(rawT: rawT)

        let surfaceBounds = finalMenuGlassSurfaceView.bounds
        sourceProxyContainer.frame = surfaceBounds
        sourceProxyContainer.layer.cornerRadius = metrics.cornerRadius
        for proxySubview in sourceProxyContainer.subviews {
            proxySubview.frame = sourceProxyContainer.bounds
            proxySubview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        updateSourceProxy(rawT: rawT)
        updateHighlight(rawT: rawT, surfaceFrame: metrics.frame)
        updateContentFrames(for: surfaceBounds)
        updateContentVisibility(rawT: rawT)
    }

    private func updateSourceProxy(rawT: CGFloat) {
        switch sourceMode {
        case .persistentSource:
            sourceProxyContainer.alpha = 0
            sourceProxyContainer.isHidden = true
            sourceProxyContainer.transform = .identity
        case .leasedGlassSource:
            let alpha = 1.0 - Self.smootherstep(0.04, 0.24, rawT)
            sourceProxyContainer.alpha = alpha
            sourceProxyContainer.isHidden = alpha <= 0.001
            sourceProxyContainer.transform = .identity
        }
    }

    private func updateContentFrames(for surfaceBounds: CGRect) {
        let targetBounds = CGRect(origin: .zero, size: targetMenuFrameInOverlay.size)
        snapshotContainer.bounds = targetBounds
        snapshotContainer.center = CGPoint(x: surfaceBounds.midX, y: surfaceBounds.midY)
        blurredMenuSnapshotView.frame = snapshotContainer.bounds
        sharpMenuSnapshotView.frame = snapshotContainer.bounds
        updateContentSDFLayout()

        liveMenuContentView.bounds = targetBounds
        liveMenuContentView.center = CGPoint(x: surfaceBounds.midX, y: surfaceBounds.midY)
    }

    private func updateContentVisibility(rawT: CGFloat) {
        let blurredInT = Self.smootherstep(0.015, 0.18, rawT)
        let sharpInT = Self.smootherstep(0.08, 0.42, rawT)
        let liveT = Self.smootherstep(0.30, 0.70, rawT)
        let contentLag = 1.0 - Self.smootherstep(0.06, 0.48, rawT)
        let reducedMotionFactor: CGFloat = UIAccessibility.isReduceMotionEnabled ? 0.25 : 1.0
        let contentOffset = Self.multiply(flowVector, by: -7.0 * contentLag * reducedMotionFactor)
        let blurredScale = Self.lerp(1.08, 1.0, Self.smootherstep(0.16, 0.58, rawT))
        let sharpScale = Self.lerp(1.035, 1.0, Self.smootherstep(0.18, 0.62, rawT))

        snapshotContainer.alpha = max(blurredInT, sharpInT)
        blurredMenuSnapshotView.alpha = blurredInT * (1.0 - sharpInT)
        sharpMenuSnapshotView.alpha = sharpInT * (1.0 - liveT * 0.35)
        blurredMenuSnapshotView.transform = CGAffineTransform(translationX: contentOffset.x, y: contentOffset.y)
            .scaledBy(x: blurredScale, y: blurredScale)
        sharpMenuSnapshotView.transform = CGAffineTransform(translationX: contentOffset.x * 0.5, y: contentOffset.y * 0.5)
            .scaledBy(x: sharpScale, y: sharpScale)
        liveMenuContentView.alpha = liveT
        liveMenuContentView.transform = CGAffineTransform(translationX: contentOffset.x * 0.2 * (1.0 - liveT), y: contentOffset.y * 0.2 * (1.0 - liveT))
        updateContentSDFDistortion(rawT: rawT, liveT: liveT)
        contentRevealProgressChanged?(max(blurredInT * 0.70, max(sharpInT, liveT)))
    }

    private func installContentDistortionFilterIfAvailable() {
        guard contentSDFFilter == nil else { return }
        if #available(iOS 26.0, *), let filter = LensSDFFilter() {
            let size = targetMenuFrameInOverlay.size
            filter.install(
                on: snapshotContainer.layer,
                size: size,
                cornerRadius: min(finalCornerRadius, min(size.width, size.height) * 0.5),
                preserveExistingFilters: false
            )
            filter.setDisplacementHeight(0)
            filter.setBlurRadius(0)
            contentSDFFilter = filter
        }
    }

    private func installSurfaceDistortionFilterIfAvailable() {
        guard surfaceSDFFilter == nil else { return }
        if #available(iOS 26.0, *), let filter = LensSDFFilter() {
            filter.install(
                on: finalMenuGlassSurfaceView.layer,
                size: sourceFrameInOverlay.size,
                cornerRadius: startCornerRadius,
                preserveExistingFilters: false
            )
            filter.setDisplacementHeight(0)
            filter.setBlurRadius(0)
            surfaceSDFFilter = filter
        }
    }

    private func updateSurfaceSDFLayout(size: CGSize, cornerRadius: CGFloat) {
        if #available(iOS 26.0, *), let filter = surfaceSDFFilter as? LensSDFFilter {
            filter.updateLayout(
                size: size,
                cornerRadius: min(cornerRadius, min(size.width, size.height) * 0.5)
            )
        }
    }

    private func updateSurfaceSDFDistortion(rawT: CGFloat) {
        if #available(iOS 26.0, *), let filter = surfaceSDFFilter as? LensSDFFilter {
            guard !UIAccessibility.isReduceMotionEnabled else {
                filter.setDisplacementHeight(0)
                filter.setBlurRadius(0)
                return
            }

            let t = max(0, min(1, rawT))
            let phase = Self.smootherstep(0.02, 0.82, t)
            let lensBell = sin(.pi * phase)
            let visibleIn = Self.smootherstep(0.015, 0.12, t)
            let finalDecay = 1.0 - Self.smootherstep(0.58, 0.96, t)
            let sourceFade = Self.smootherstep(0.04, 0.20, t)
            let intensity = max(0, lensBell * visibleIn * max(finalDecay, 0.0) * sourceFade)

            filter.setDisplacementHeight(42.0 * intensity)
            filter.setBlurRadius(2.6 * intensity)
        }
    }

    private func updateContentSDFLayout() {
        if #available(iOS 26.0, *), let filter = contentSDFFilter as? LensSDFFilter {
            let size = snapshotContainer.bounds.size
            filter.updateLayout(
                size: size,
                cornerRadius: min(finalCornerRadius, min(size.width, size.height) * 0.5)
            )
        }
    }

    private func updateContentSDFDistortion(rawT: CGFloat, liveT: CGFloat) {
        if #available(iOS 26.0, *), let filter = contentSDFFilter as? LensSDFFilter {
            guard !UIAccessibility.isReduceMotionEnabled else {
                filter.setDisplacementHeight(0)
                filter.setBlurRadius(0)
                return
            }

            let t = max(0, min(1, rawT))
            let phase = Self.smootherstep(0.02, 0.82, t)
            let lensBell = sin(.pi * phase)
            let liveDecay = 1.0 - Self.smootherstep(0.24, 0.90, liveT)
            let contentIn = Self.smootherstep(0.015, 0.16, t)
            let intensity = max(0, lensBell * liveDecay * contentIn)

            filter.setDisplacementHeight(50.0 * intensity)
            filter.setBlurRadius(3.2 * intensity)
        }
    }

    private func updateHighlight(rawT: CGFloat, surfaceFrame: CGRect) {
        let highlightT = Self.smootherstep(0.05, 0.78, rawT)
        let motionFactor: CGFloat = UIAccessibility.isReduceMotionEnabled ? 0.35 : 1.0
        let start = CGPoint(x: sourceFrameInOverlay.midX, y: sourceFrameInOverlay.midY)
        let target = CGPoint(
            x: targetMenuFrameInOverlay.midX + flowVector.x * targetMenuFrameInOverlay.width * 0.18 * motionFactor,
            y: targetMenuFrameInOverlay.midY + flowVector.y * targetMenuFrameInOverlay.height * 0.18 * motionFactor
        )
        let overlayCenter = Self.lerpPoint(start, target, highlightT)
        let localCenter = CGPoint(
            x: overlayCenter.x - surfaceFrame.minX,
            y: overlayCenter.y - surfaceFrame.minY
        )
        let radius = Self.lerp(22.0, max(targetMenuFrameInOverlay.width, targetMenuFrameInOverlay.height) * 0.70, highlightT)
        let alphaPeak = UIAccessibility.isReduceMotionEnabled ? 0.08 : 0.18
        let alpha = alphaPeak * sin(.pi * Self.smootherstep(0.05, 0.88, rawT))
        highlightView.alpha = alpha
        highlightView.bounds = CGRect(x: 0, y: 0, width: radius * 2.0, height: radius * 2.0)
        highlightView.center = localCenter
        highlightLayer.frame = highlightView.bounds
    }

    private func updateShadow(rawT: CGFloat) {
        let energy = sin(.pi * Self.smootherstep(0.08, 0.86, rawT))
        let finalT = Self.smootherstep(0.78, 1.0, rawT)
        let visibleT = Self.smootherstep(0.02, 0.18, rawT)

        let ambientOpacity = Self.lerp(Self.lerp(0.035, 0.09, energy), 0.08, finalT) * visibleT
        let contactOpacity = Self.lerp(Self.lerp(0.02, 0.055, energy), 0.045, finalT) * visibleT
        ambientShadowLayer.shadowOpacity = Float(ambientOpacity)
        ambientShadowLayer.shadowRadius = Self.lerp(Self.lerp(10.0, 26.0, energy), 22.0, finalT)
        ambientShadowLayer.shadowOffset = .zero
        contactShadowLayer.shadowOpacity = Float(contactOpacity)
        contactShadowLayer.shadowRadius = Self.lerp(Self.lerp(6.0, 14.0, energy), 12.0, finalT)
        contactShadowLayer.shadowOffset = CGSize(width: 0, height: Self.lerp(Self.lerp(2.0, 5.0, energy), 4.0, finalT))
    }

    private func currentMetrics(rawT: CGFloat) -> Metrics {
        let raw = max(-0.12, min(1.14, rawT))
        let t = max(0, min(1, raw))
        let isProgressOvershooting = raw < 0 || raw > 1
        if t <= 0, !isProgressOvershooting {
            return Metrics(
                frame: startFrame,
                cornerRadius: startCornerRadius
            )
        }
        if t >= 1, !isProgressOvershooting {
            return Metrics(
                frame: targetMenuFrameInOverlay,
                cornerRadius: finalCornerRadius
            )
        }

        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let motionT = reduceMotion
            ? Self.smootherstep(0.0, 1.0, t)
            : (
                animationDirection < 0
                    // Closing is evaluated with t moving 1 -> 0. An
                    // opening-style ease-out would therefore crawl at the
                    // beginning and collapse in the last frames. Ease-in in
                    // value-space gives the inverse feel: leave the platter
                    // decisively, then settle softly into the source.
                    ? Self.easeInPower(t, 2.12)
                    : Self.dampedSpring01(
                        t,
                        response: 0.96,
                        dampingRatio: 0.70,
                        overshootLimit: 1.046
                    )
            )
        let sourceSize = startFrame.size
        let targetSize = targetMenuFrameInOverlay.size
        let sourceRoundness = min(sourceSize.width, sourceSize.height) / max(sourceSize.width, sourceSize.height)
        let shouldNormalizeSourceToCircle = sourceMode == .leasedGlassSource && sourceRoundness < 0.92
        let sourceMinSide = min(sourceSize.width, sourceSize.height)
        let sourceMaxSide = max(sourceSize.width, sourceSize.height)
        let circleSide = shouldNormalizeSourceToCircle ? sourceMinSide : sourceMaxSide
        let circleEnd: CGFloat = animationDirection < 0 ? 0.22 : 0.075
        let circleT = shouldNormalizeSourceToCircle ? Self.smootherstep(0.0, circleEnd, t) : 0.0
        let growT = motionT
        let travelT = animationDirection < 0
            ? Self.lerpUnclamped(motionT, Self.easeInPower(t, 1.68), 0.22)
            : Self.lerpUnclamped(motionT, Self.easeOutPower(t, 2.02), 0.18)
        // Blend the spring/oval envelope back into the exact target over the
        // main motion, not only in the last frames. A late lock reads as a
        // separate "unfold" after the menu has visually arrived.
        let finalLockT = isProgressOvershooting ? 0.0 : Self.smootherstep(0.68, 0.98, t)
        let sourceCenter = CGPoint(x: startFrame.midX, y: startFrame.midY)
        let targetCenter = CGPoint(x: targetMenuFrameInOverlay.midX, y: targetMenuFrameInOverlay.midY)
        let distance = hypot(targetCenter.x - sourceCenter.x, targetCenter.y - sourceCenter.y)

        let normalizedSourceSize = CGSize(
            width: Self.lerpUnclamped(sourceSize.width, circleSide, circleT),
            height: Self.lerpUnclamped(sourceSize.height, circleSide, circleT)
        )
        let baseSize = CGSize(
            width: Self.lerpUnclamped(normalizedSourceSize.width, targetSize.width, growT),
            height: Self.lerpUnclamped(normalizedSourceSize.height, targetSize.height, growT)
        )
        let bloomPulse = reduceMotion ? 0 : sin(.pi * Self.smootherstep(0.04, 0.78, t))
        let ovalPulse = bloomPulse * (1.0 - Self.smootherstep(0.22, 0.78, t))
        let pulsedSize = CGSize(
            width: baseSize.width * (1.0 + 0.018 * ovalPulse),
            height: baseSize.height * (1.0 + 0.205 * ovalPulse)
        )
        let currentSize = CGSize(
            width: Self.lerpUnclamped(pulsedSize.width, targetSize.width, finalLockT),
            height: Self.lerpUnclamped(pulsedSize.height, targetSize.height, finalLockT)
        )
        let fluidCenter = Self.fluidCurvePoint(
            from: sourceCenter,
            to: targetCenter,
            flow: flowVector,
            travelT: travelT,
            distance: distance,
            lowerBias: targetCenter.y >= sourceCenter.y ? 1.0 : -1.0,
            reduceMotion: reduceMotion
        )
        var currentFrame = CGRect(
            x: fluidCenter.x - currentSize.width / 2.0,
            y: fluidCenter.y - currentSize.height / 2.0,
            width: currentSize.width,
            height: currentSize.height
        )
        if targetCenter.y >= sourceCenter.y, currentFrame.minY < startFrame.minY {
            currentFrame.origin.y += startFrame.minY - currentFrame.minY
        } else if targetCenter.y < sourceCenter.y, currentFrame.maxY > startFrame.maxY {
            currentFrame.origin.y -= currentFrame.maxY - startFrame.maxY
        }
        let circleLikeRadius = min(currentFrame.width, currentFrame.height) * 0.5
        let cornerToCircleEnd: CGFloat = shouldNormalizeSourceToCircle ? (animationDirection < 0 ? 0.24 : 0.085) : 0.20
        let cornerToCircleT = Self.smootherstep(0.0, cornerToCircleEnd, t)
        let cornerToMenuT = Self.smootherstep(0.36, 0.90, t)
        let earlyRadius = Self.lerpUnclamped(startCornerRadius, circleLikeRadius, cornerToCircleT)
        let cornerRadius = min(
            max(0.0, Self.lerpUnclamped(earlyRadius, finalCornerRadius, cornerToMenuT)),
            circleLikeRadius
        )

        return Metrics(frame: currentFrame, cornerRadius: cornerRadius)
    }

    private var flowVector: CGPoint {
        let sourceCenter = CGPoint(x: sourceFrameInOverlay.midX, y: sourceFrameInOverlay.midY)
        let targetCenter = CGPoint(x: targetMenuFrameInOverlay.midX, y: targetMenuFrameInOverlay.midY)
        let vector = CGPoint(x: targetCenter.x - sourceCenter.x, y: targetCenter.y - sourceCenter.y)
        let length = hypot(vector.x, vector.y)
        if length > 0.001 {
            return CGPoint(x: vector.x / length, y: vector.y / length)
        }
        return Self.normalize(CGPoint(x: -0.6, y: 0.8))
    }

    private var startFrame: CGRect {
        switch sourceMode {
        case .leasedGlassSource:
            return sourceFrameInOverlay
        case .persistentSource:
            let seed = persistentSeedPoint
            return CGRect(x: seed.x - 18.0, y: seed.y - 18.0, width: 36.0, height: 36.0)
        }
    }

    private var startCornerRadius: CGFloat {
        switch sourceMode {
        case .leasedGlassSource:
            let maxRadius = min(sourceFrameInOverlay.width, sourceFrameInOverlay.height) * 0.5
            let radius = sourceCornerRadius > 0 ? sourceCornerRadius : maxRadius
            return min(max(0, radius), maxRadius)
        case .persistentSource:
            return 18.0
        }
    }

    private var persistentSeedPoint: CGPoint {
        let sourceCenter = CGPoint(x: sourceFrameInOverlay.midX, y: sourceFrameInOverlay.midY)
        let insetTarget = targetMenuFrameInOverlay.insetBy(dx: 12.0, dy: 12.0)
        return Self.nearestPoint(on: insetTarget, to: sourceCenter)
    }

    private func materialProgress(_ rawT: CGFloat) -> CGFloat {
        let t = max(0, min(1, rawT))
        return Self.smootherstep(0.08, 0.70, t)
    }

    private func animateProgress(
        to target: CGFloat,
        duration: TimeInterval,
        completion: (() -> Void)?
    ) {
        cancelAnimation()
        animationFrom = progress
        animationTo = target
        animationDirection = target >= animationFrom ? 1 : -1
        animationCompletion = completion

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressDriverView.layer.removeAllAnimations()
        progressDriverView.transform = CGAffineTransform(translationX: progress, y: 0)
        CATransaction.commit()

        let timing = UICubicTimingParameters(
            controlPoint1: CGPoint(x: 0.0, y: 0.0),
            controlPoint2: CGPoint(x: 1.0, y: 1.0)
        )
        let animator = UIViewPropertyAnimator(duration: max(0.001, duration), timingParameters: timing)
        animator.addAnimations { [weak self] in
            self?.progressDriverView.transform = CGAffineTransform(translationX: target, y: 0)
        }
        animator.addCompletion { [weak self, weak animator] _ in
            guard let self,
                  let animator,
                  self.progressAnimator === animator else {
                return
            }

            self.stopProgressDisplayLink()
            self.progressAnimator = nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.progressDriverView.layer.removeAllAnimations()
            self.progressDriverView.transform = CGAffineTransform(translationX: target, y: 0)
            self.progress = max(0, min(1, target))
            self.updateGeometry(progress: self.progress)
            CATransaction.commit()

            let completion = self.animationCompletion
            self.animationCompletion = nil
            completion?()
        }
        progressAnimator = animator
        startProgressDisplayLink()
        animator.startAnimation()
    }

    private func startProgressDisplayLink() {
        stopProgressDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        let maximumFramesPerSecond = max(60, UIScreen.main.maximumFramesPerSecond)
        if #available(iOS 15.0, *) {
            let preferredFrameRate = Float(min(120, maximumFramesPerSecond))
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: min(80, preferredFrameRate),
                maximum: preferredFrameRate,
                preferred: preferredFrameRate
            )
        } else {
            link.preferredFramesPerSecond = maximumFramesPerSecond
        }
        link.add(to: .main, forMode: .common)
        progressDisplayLink = link
    }

    private func stopProgressDisplayLink() {
        progressDisplayLink?.invalidate()
        progressDisplayLink = nil
    }

    private func cancelAnimation() {
        sampleProgressDriver()
        progressAnimator?.stopAnimation(true)
        progressAnimator = nil
        progressDriverView.layer.removeAllAnimations()
        stopProgressDisplayLink()
        animationCompletion = nil
    }

    @objc
    private func handleDisplayLink(_ link: CADisplayLink) {
        sampleProgressDriver()
        updateGeometry(progress: progress)
    }

    private func sampleProgressDriver() {
        let sampled = progressDriverView.layer.presentation()?.affineTransform().tx
            ?? progressDriverView.transform.tx
        let lowerBound = min(animationFrom, animationTo) - 0.12
        let upperBound = max(animationFrom, animationTo) + 0.14
        progress = max(lowerBound, min(upperBound, sampled))
    }

    private func configureShadowLayer(_ layer: CALayer) {
        layer.contentsScale = UIScreen.main.scale
        layer.backgroundColor = UIColor.clear.cgColor
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0
        layer.shadowRadius = 10
        layer.shadowOffset = .zero
    }

    private struct Metrics {
        let frame: CGRect
        let cornerRadius: CGFloat
    }

    private static func renderImage(from view: UIView) -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    private static func blurredImage(from image: UIImage, radius: CGFloat) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let clamped = input.clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(clamped, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func smootherstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge0 != edge1 else { return x >= edge1 ? 1 : 0 }
        let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    private static func easeOutCubic(_ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, x))
        let inverse = 1.0 - t
        return 1.0 - inverse * inverse * inverse
    }

    private static func easeOutQuart(_ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, x))
        let inverse = 1.0 - t
        return 1.0 - inverse * inverse * inverse * inverse
    }

    private static func easeOutPower(_ x: CGFloat, _ power: CGFloat) -> CGFloat {
        let t = max(0, min(1, x))
        return 1.0 - pow(1.0 - t, power)
    }

    private static func easeInPower(_ x: CGFloat, _ power: CGFloat) -> CGFloat {
        let t = max(0, min(1, x))
        return pow(t, power)
    }

    private static func fluidMotionProgress(_ t: CGFloat, closing: Bool) -> CGFloat {
        let x = max(0, min(1, t))
        if x == 0 || x == 1 {
            return x
        }
        if closing {
            return pow(x, 2.55)
        }
        return 1.0 - pow(1.0 - x, 2.55)
    }

    private static func dampedSpring01(
        _ t: CGFloat,
        response: CGFloat,
        dampingRatio: CGFloat,
        overshootLimit: CGFloat = 1.08
    ) -> CGFloat {
        let x = max(0, min(1, t))
        if x == 0 { return 0 }
        if x == 1 { return 1 }

        let response = max(0.001, response)
        let zeta = max(0.05, min(1.2, dampingRatio))
        let omega0 = 2.0 * CGFloat.pi / response

        if zeta < 1.0 {
            let omegaD = omega0 * sqrt(1.0 - zeta * zeta)
            let envelope = exp(-zeta * omega0 * x)
            let value = 1.0 - envelope * (
                cos(omegaD * x) +
                (zeta * omega0 / omegaD) * sin(omegaD * x)
            )
            return min(max(value, 0), overshootLimit)
        } else {
            let value = 1.0 - exp(-omega0 * x) * (1.0 + omega0 * x)
            return min(max(value, 0), 1.0)
        }
    }

    private static func interpolateRectByCenterAndSize(
        from: CGRect,
        to: CGRect,
        t: CGFloat
    ) -> CGRect {
        interpolateRectByCenterAndSizeUnclamped(from: from, to: to, t: max(0, min(1, t)))
    }

    private static func interpolateRectByCenterAndSize(
        from: CGRect,
        to: CGRect,
        centerT: CGFloat,
        sizeT: CGFloat
    ) -> CGRect {
        let clampedCenterT = max(0, min(1, centerT))
        let clampedSizeT = max(0, min(1, sizeT))
        let center = CGPoint(
            x: lerpUnclamped(from.midX, to.midX, clampedCenterT),
            y: lerpUnclamped(from.midY, to.midY, clampedCenterT)
        )
        let size = CGSize(
            width: lerpUnclamped(from.width, to.width, clampedSizeT),
            height: lerpUnclamped(from.height, to.height, clampedSizeT)
        )
        return CGRect(
            x: center.x - size.width / 2.0,
            y: center.y - size.height / 2.0,
            width: size.width,
            height: size.height
        )
    }

    private static func interpolateRectByCenterAndSizeUnclamped(
        from: CGRect,
        to: CGRect,
        t: CGFloat
    ) -> CGRect {
        let center = CGPoint(
            x: lerpUnclamped(from.midX, to.midX, t),
            y: lerpUnclamped(from.midY, to.midY, t)
        )
        let size = CGSize(
            width: lerpUnclamped(from.width, to.width, t),
            height: lerpUnclamped(from.height, to.height, t)
        )
        return CGRect(
            x: center.x - size.width / 2.0,
            y: center.y - size.height / 2.0,
            width: size.width,
            height: size.height
        )
    }

    private static func scale(rect: CGRect, sx: CGFloat, sy: CGFloat, around anchor: CGPoint) -> CGRect {
        let minX = anchor.x + (rect.minX - anchor.x) * sx
        let maxX = anchor.x + (rect.maxX - anchor.x) * sx
        let minY = anchor.y + (rect.minY - anchor.y) * sy
        let maxY = anchor.y + (rect.maxY - anchor.y) * sy
        return CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
    }

    private static func stretch(rect: CGRect, along flow: CGPoint, bell: CGFloat) -> CGRect {
        guard bell > 0.001 else { return rect }
        let alongStretch = 1.0 + 0.035 * bell
        let crossStretch = 1.0 - 0.012 * bell
        let sx: CGFloat
        let sy: CGFloat
        if abs(flow.x) > abs(flow.y) {
            sx = alongStretch
            sy = crossStretch
        } else {
            sx = crossStretch
            sy = alongStretch
        }
        return scale(
            rect: rect,
            sx: sx,
            sy: sy,
            around: CGPoint(x: rect.midX, y: rect.midY)
        )
    }

    private static func nearestPoint(on rect: CGRect, to point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(rect.minX, min(rect.maxX, point.x)),
            y: max(rect.minY, min(rect.maxY, point.y))
        )
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        lerpUnclamped(a, b, max(0, min(1, t)))
    }

    private static func lerpUnclamped(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private static func lerpPoint(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(
            x: lerp(a.x, b.x, t),
            y: lerp(a.y, b.y, t)
        )
    }

    private static func fluidCurvePoint(
        from source: CGPoint,
        to target: CGPoint,
        flow: CGPoint,
        travelT: CGFloat,
        distance: CGFloat,
        lowerBias: CGFloat,
        reduceMotion: Bool
    ) -> CGPoint {
        let t = max(0, min(1, travelT))
        guard !reduceMotion, distance > 1.0 else {
            return lerpPoint(source, target, t)
        }

        let perpendicular = CGPoint(x: -flow.y, y: flow.x)
        let curveAmount = min(distance * 0.24, 58.0)
        let lowerPull = min(distance * 0.12, 32.0)
        let sideSign: CGFloat = flow.x >= 0 ? 1.0 : -1.0

        let control1 = add(
            add(source, multiply(flow, by: distance * 0.23)),
            add(
                multiply(perpendicular, by: curveAmount * sideSign),
                CGPoint(x: 0, y: lowerPull * lowerBias)
            )
        )
        let control2 = add(
            add(target, multiply(flow, by: -distance * 0.36)),
            add(
                multiply(perpendicular, by: curveAmount * 0.46 * sideSign),
                CGPoint(x: 0, y: lowerPull * 0.68 * lowerBias)
            )
        )

        return cubicBezierPoint(source, control1, control2, target, t)
    }

    private static func cubicBezierPoint(
        _ p0: CGPoint,
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ p3: CGPoint,
        _ t: CGFloat
    ) -> CGPoint {
        let u = 1.0 - t
        let tt = t * t
        let uu = u * u
        let uuu = uu * u
        let ttt = tt * t
        return CGPoint(
            x: uuu * p0.x + 3.0 * uu * t * p1.x + 3.0 * u * tt * p2.x + ttt * p3.x,
            y: uuu * p0.y + 3.0 * uu * t * p1.y + 3.0 * u * tt * p2.y + ttt * p3.y
        )
    }

    private static func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: a.x + b.x, y: a.y + b.y)
    }

    private static func multiply(_ point: CGPoint, by value: CGFloat) -> CGPoint {
        CGPoint(x: point.x * value, y: point.y * value)
    }

    private static func normalize(_ point: CGPoint) -> CGPoint {
        let length = hypot(point.x, point.y)
        guard length > 0.001 else { return CGPoint(x: 0, y: 1) }
        return CGPoint(x: point.x / length, y: point.y / length)
    }
}
