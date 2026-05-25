import UIKit
import CoreImage

let contextMenuLensBloomGeometryOnly = true
private let lensBloomDebugGeometry = contextMenuLensBloomGeometryOnly
private let lensBloomDebugShadow = false

enum ContextMenuSourceVisualMode {
    case persistentSource
    case leasedGlassSource
}

final class ContextMenuLensBloomTransitionView: UIView {
    var sourceFrameInOverlay: CGRect {
        didSet { rebuildLocalGeometry() }
    }
    var targetMenuFrameInOverlay: CGRect {
        didSet { rebuildLocalGeometry() }
    }
    var sourceMode: ContextMenuSourceVisualMode {
        didSet { updateSourceProxyVisibility(progress: progress) }
    }

    private(set) var progress: CGFloat = 0

    let transitionMaterialView = UIView()
    let menuContentTransitionView = UIView()
    let liveMenuContentView = UIView()
    let finalMenuGlassSurfaceView: MenuGlassSurfaceView
    let sourceProxyContainer = UIView()

    var contentRevealProgressChanged: ((CGFloat) -> Void)?

    static var debugGeometryOverlayEnabled = lensBloomDebugGeometry
    static var debugFrozenProgress: CGFloat?

    private let materialTintView = UIView()
    private let materialBlurView: UIVisualEffectView
    private let transitionSnapshotContainer = UIView()
    private let blurredContentSnapshotView = UIImageView()
    private let sharpContentSnapshotView = UIImageView()
    private let shadowContainerView = UIView()
    private let ambientShadowLayer = CAShapeLayer()
    private let contactShadowLayer = CAShapeLayer()
    private let debugShadowPathLayer = CAShapeLayer()
    private let lensMaskLayer = CAShapeLayer()
    private let contentMaskLayer = CAShapeLayer()
    private let debugShapeLayer = CAShapeLayer()
    private let debugSourceView = UIView()
    private let debugTargetView = UIView()
    private let debugCanvasView = UIView()
    private let debugSeedView = UIView()
    private let debugProgressLabel = UILabel()
    private let debugSourceModeLabel = UILabel()
    private let restingHitView = UIView()

    private let finalCornerRadius: CGFloat
    private let sourceCornerRadius: CGFloat
    private var canvasFrameInOverlay: CGRect = .zero
    private var sourceRectInCanvas: CGRect = .zero
    private var targetRectInCanvas: CGRect = .zero
    private var lensSeedPoint: CGPoint = .zero

    private var displayLink: CADisplayLink?
    private var animationStart: CFTimeInterval = 0
    private var animationDuration: TimeInterval = 0
    private var animationFrom: CGFloat = 0
    private var animationTo: CGFloat = 0
    private var animationDamping: CGFloat = 0.72
    private var animationCompletion: (() -> Void)?

    private static let canvasOutset: CGFloat = 64.0

    private struct ContextMenuGeometry {
        let sourceFrameInOverlay: CGRect
        let targetMenuFrameInOverlay: CGRect
        let canvasFrameInOverlay: CGRect
        let sourceRectInCanvas: CGRect
        let targetRectInCanvas: CGRect
    }

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
        self.finalMenuGlassSurfaceView = MenuGlassSurfaceView(isDark: isDark, effectsEnabled: !lensBloomDebugGeometry)
        self.materialBlurView = UIVisualEffectView(
            effect: UIBlurEffect(style: isDark ? .systemThinMaterialDark : .systemThinMaterialLight)
        )

        super.init(frame: .zero)

        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false

        configureMask(lensMaskLayer)
        configureMask(contentMaskLayer)

        shadowContainerView.backgroundColor = .clear
        shadowContainerView.isUserInteractionEnabled = false
        shadowContainerView.layer.masksToBounds = false
        addSubview(shadowContainerView)
        configureShadowLayer(ambientShadowLayer)
        configureShadowLayer(contactShadowLayer)
        shadowContainerView.layer.addSublayer(ambientShadowLayer)
        shadowContainerView.layer.addSublayer(contactShadowLayer)

        debugShadowPathLayer.contentsScale = UIScreen.main.scale
        debugShadowPathLayer.allowsEdgeAntialiasing = true
        debugShadowPathLayer.fillColor = UIColor.clear.cgColor
        debugShadowPathLayer.strokeColor = UIColor.systemRed.withAlphaComponent(0.9).cgColor
        debugShadowPathLayer.lineWidth = 1.0
        debugShadowPathLayer.isHidden = !lensBloomDebugShadow
        shadowContainerView.layer.addSublayer(debugShadowPathLayer)

        debugShapeLayer.contentsScale = UIScreen.main.scale
        debugShapeLayer.allowsEdgeAntialiasing = true
        debugShapeLayer.fillRule = .nonZero
        debugShapeLayer.fillColor = UIColor.systemGreen.withAlphaComponent(0.78).cgColor
        debugShapeLayer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.9).cgColor
        debugShapeLayer.lineWidth = 1.0
        debugShapeLayer.lineJoin = .round
        debugShapeLayer.lineCap = .round
        debugShapeLayer.isHidden = !lensBloomDebugGeometry
        layer.addSublayer(debugShapeLayer)

        transitionMaterialView.backgroundColor = .clear
        transitionMaterialView.layer.mask = lensMaskLayer
        transitionMaterialView.isHidden = lensBloomDebugGeometry
        addSubview(transitionMaterialView)

        materialBlurView.isUserInteractionEnabled = false
        transitionMaterialView.addSubview(materialBlurView)

        materialTintView.backgroundColor = isDark
            ? UIColor(white: 0.14, alpha: 0.82)
            : UIColor.white.withAlphaComponent(0.76)
        materialTintView.isUserInteractionEnabled = false
        transitionMaterialView.addSubview(materialTintView)

        menuContentTransitionView.backgroundColor = .clear
        menuContentTransitionView.layer.mask = contentMaskLayer
        menuContentTransitionView.alpha = 0.0
        menuContentTransitionView.isHidden = lensBloomDebugGeometry
        addSubview(menuContentTransitionView)

        transitionSnapshotContainer.backgroundColor = .clear
        transitionSnapshotContainer.isUserInteractionEnabled = false
        menuContentTransitionView.addSubview(transitionSnapshotContainer)

        for snapshotView in [blurredContentSnapshotView, sharpContentSnapshotView] {
            snapshotView.backgroundColor = .clear
            snapshotView.contentMode = .scaleToFill
            snapshotView.clipsToBounds = true
            snapshotView.isUserInteractionEnabled = false
            snapshotView.alpha = 0.0
            transitionSnapshotContainer.addSubview(snapshotView)
        }

        liveMenuContentView.backgroundColor = .clear
        liveMenuContentView.alpha = 0.0
        liveMenuContentView.isUserInteractionEnabled = false
        menuContentTransitionView.addSubview(liveMenuContentView)

        finalMenuGlassSurfaceView.alpha = 0.0
        finalMenuGlassSurfaceView.isHidden = lensBloomDebugGeometry
        addSubview(finalMenuGlassSurfaceView)

        sourceProxyContainer.backgroundColor = .clear
        sourceProxyContainer.clipsToBounds = true
        sourceProxyContainer.isUserInteractionEnabled = false
        addSubview(sourceProxyContainer)

        configureDebugView(debugCanvasView, color: .systemPurple)
        configureDebugView(debugSourceView, color: .systemGreen)
        configureDebugView(debugTargetView, color: .systemOrange)
        debugSeedView.isUserInteractionEnabled = false
        debugSeedView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.85)
        debugSeedView.layer.cornerRadius = 4
        debugSeedView.isHidden = !Self.debugGeometryOverlayEnabled
        configureDebugLabel(debugProgressLabel)
        configureDebugLabel(debugSourceModeLabel)
        addSubview(debugCanvasView)
        addSubview(debugSourceView)
        addSubview(debugTargetView)
        addSubview(debugSeedView)
        addSubview(debugProgressLabel)
        addSubview(debugSourceModeLabel)

        restingHitView.backgroundColor = .clear
        restingHitView.isUserInteractionEnabled = false
        addSubview(restingHitView)

        rebuildLocalGeometry()
        setProgress(0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    func prepareMenuContentSnapshots(from contentView: UIView) {
        guard !lensBloomDebugGeometry else { return }
        contentView.layoutIfNeeded()
        let bounds = contentView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        let sharpImage = Self.renderImage(of: contentView)
        sharpContentSnapshotView.image = sharpImage
        blurredContentSnapshotView.image = Self.blurredImage(from: sharpImage, radius: 18.0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        transitionMaterialView.frame = bounds
        shadowContainerView.frame = bounds
        ambientShadowLayer.frame = shadowContainerView.bounds
        contactShadowLayer.frame = shadowContainerView.bounds
        debugShadowPathLayer.frame = shadowContainerView.bounds
        materialBlurView.frame = transitionMaterialView.bounds
        materialTintView.frame = transitionMaterialView.bounds
        menuContentTransitionView.frame = targetRectInCanvas
        finalMenuGlassSurfaceView.frame = targetRectInCanvas
        sourceProxyContainer.frame = sourceRectInCanvas
        restingHitView.frame = targetRectInCanvas
        updateContentLayerFrames()
        lensMaskLayer.frame = bounds
        contentMaskLayer.frame = menuContentTransitionView.bounds
        debugShapeLayer.frame = bounds
        enforceGeometryOnlyVisibilityIfNeeded()
        updateDebugFrames()
    }

    private func updateContentLayerFrames() {
        let contentBounds = menuContentTransitionView.bounds
        transitionSnapshotContainer.frame = contentBounds
        blurredContentSnapshotView.frame = transitionSnapshotContainer.bounds
        sharpContentSnapshotView.frame = transitionSnapshotContainer.bounds
        liveMenuContentView.frame = contentBounds
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if progress >= 0.985 {
            return targetRectInCanvas.contains(point)
        }
        return bounds.contains(point)
    }

    func setProgress(_ progress: CGFloat) {
        cancelAnimation()
        self.progress = max(0, min(1, progress))
        updateLensShape(progress: self.progress, geometryProgress: self.progress)
    }

    func animateExpand(duration: TimeInterval, damping: CGFloat, completion: (() -> Void)? = nil) {
        prepareCanvasForTransition()
        if let frozenProgress = Self.debugFrozenProgress {
            setProgress(frozenProgress)
            completion?()
            return
        }
        animateProgress(to: 1, duration: duration, damping: damping) { [weak self] in
            if lensBloomDebugGeometry {
                self?.setProgress(1)
            } else {
                self?.finishToFinalMenu()
            }
            completion?()
        }
    }

    func animateCollapse(duration: TimeInterval, damping: CGFloat, completion: (() -> Void)? = nil) {
        prepareCanvasForTransition()
        animateProgress(to: 0, duration: duration, damping: damping) { [weak self] in
            self?.cancelOrDismiss()
            completion?()
        }
    }

    func updateLensShape(progress: CGFloat) {
        updateLensShape(progress: progress, geometryProgress: progress)
    }

    func updateMaterial(progress: CGFloat) {
        let t = max(0, min(1, progress))
        let path = lensPath(phaseProgress: t, geometryProgress: t)
        updateShadow(progress: t, path: path)
    }

    func updateContent(progress: CGFloat) {
        guard !lensBloomDebugGeometry else {
            menuContentTransitionView.alpha = 0.0
            menuContentTransitionView.isHidden = true
            transitionSnapshotContainer.alpha = 0.0
            blurredContentSnapshotView.alpha = 0.0
            sharpContentSnapshotView.alpha = 0.0
            liveMenuContentView.alpha = 0.0
            finalMenuGlassSurfaceView.alpha = 0.0
            finalMenuGlassSurfaceView.isHidden = true
            contentRevealProgressChanged?(0.0)
            return
        }
        let t = max(0, min(1, progress))
        let sharpT = Self.smootherstep(0.58, 0.96, t)
        let handoffT = Self.smootherstep(0.86, 0.98, t)
        let transitionAlpha = Self.smootherstep(0.34, 0.58, t)
        let liveT = Self.smootherstep(0.78, 0.98, t)

        menuContentTransitionView.alpha = lensBloomDebugGeometry ? 0.0 : max(transitionAlpha, liveT)
        menuContentTransitionView.isHidden = lensBloomDebugGeometry
        menuContentTransitionView.transform = .identity
        let snapshotScale = Self.lerp(1.18, 1.0, sharpT)
        transitionSnapshotContainer.alpha = transitionAlpha
        transitionSnapshotContainer.transform = CGAffineTransform(scaleX: snapshotScale, y: snapshotScale)
        blurredContentSnapshotView.alpha = transitionAlpha * (1.0 - sharpT)
        sharpContentSnapshotView.alpha = transitionAlpha * sharpT * (1.0 - liveT)
        liveMenuContentView.alpha = liveT
        finalMenuGlassSurfaceView.alpha = lensBloomDebugGeometry ? 0.0 : handoffT
        finalMenuGlassSurfaceView.isHidden = lensBloomDebugGeometry
        contentRevealProgressChanged?(liveT)
    }

    func finishToFinalMenu() {
        cancelAnimation()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = targetMenuFrameInOverlay
        bounds = CGRect(origin: .zero, size: targetMenuFrameInOverlay.size)
        canvasFrameInOverlay = targetMenuFrameInOverlay
        sourceRectInCanvas = CGRect(
            x: sourceFrameInOverlay.minX - targetMenuFrameInOverlay.minX,
            y: sourceFrameInOverlay.minY - targetMenuFrameInOverlay.minY,
            width: sourceFrameInOverlay.width,
            height: sourceFrameInOverlay.height
        )
        targetRectInCanvas = CGRect(origin: .zero, size: targetMenuFrameInOverlay.size)
        lensSeedPoint = resolvedLensSeedPoint()
        transitionMaterialView.alpha = 0.0
        finalMenuGlassSurfaceView.frame = bounds
        finalMenuGlassSurfaceView.alpha = lensBloomDebugGeometry ? 0.0 : 1.0
        finalMenuGlassSurfaceView.isHidden = lensBloomDebugGeometry
        finalMenuGlassSurfaceView.layer.cornerRadius = finalCornerRadius
        finalMenuGlassSurfaceView.clipsToBounds = true
        if !lensBloomDebugGeometry, menuContentTransitionView.superview !== finalMenuGlassSurfaceView.contentView {
            finalMenuGlassSurfaceView.contentView.addSubview(menuContentTransitionView)
        }
        menuContentTransitionView.frame = bounds
        menuContentTransitionView.transform = .identity
        menuContentTransitionView.alpha = lensBloomDebugGeometry ? 0.0 : 1.0
        menuContentTransitionView.layer.mask = nil
        updateContentLayerFrames()
        transitionSnapshotContainer.alpha = 0.0
        blurredContentSnapshotView.alpha = 0.0
        sharpContentSnapshotView.alpha = 0.0
        liveMenuContentView.alpha = lensBloomDebugGeometry ? 0.0 : 1.0
        liveMenuContentView.transform = .identity
        sourceProxyContainer.alpha = 0.0
        sourceProxyContainer.isHidden = true
        updateShadow(progress: 1.0, path: UIBezierPath(
            roundedRect: bounds,
            cornerRadius: finalCornerRadius
        ).cgPath)
        restingHitView.frame = bounds
        progress = 1
        contentRevealProgressChanged?(lensBloomDebugGeometry ? 0.0 : 1.0)
        CATransaction.commit()
    }

    func cancelOrDismiss() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progress = 0
        transitionMaterialView.alpha = lensBloomDebugGeometry ? 0.0 : 1.0
        menuContentTransitionView.alpha = 0.0
        transitionSnapshotContainer.alpha = 0.0
        blurredContentSnapshotView.alpha = 0.0
        sharpContentSnapshotView.alpha = 0.0
        liveMenuContentView.alpha = 0.0
        finalMenuGlassSurfaceView.alpha = 0.0
        finalMenuGlassSurfaceView.isHidden = true
        updateSourceProxyVisibility(progress: 0)
        let path = lensPath(phaseProgress: 0, geometryProgress: 0)
        lensMaskLayer.path = path
        contentMaskLayer.path = contentPath(fromCanvasPath: path)
        debugShapeLayer.path = path
        updateShadow(progress: 0, path: path)
        enforceGeometryOnlyVisibilityIfNeeded()
        CATransaction.commit()
    }

    private func updateLensShape(progress phaseProgress: CGFloat, geometryProgress: CGFloat) {
        let phaseT = max(0, min(1, phaseProgress))
        let geometryT = max(0, min(1.04, geometryProgress))
        let path = lensPath(phaseProgress: phaseT, geometryProgress: geometryT)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lensMaskLayer.path = path
        contentMaskLayer.path = contentPath(fromCanvasPath: path)
        debugShapeLayer.path = path

        let lensOpacity = Self.smootherstep(0.04, 0.20, phaseT)
        let handoffT = Self.smootherstep(0.86, 1.00, phaseT)
        debugShapeLayer.opacity = lensBloomDebugGeometry ? 1.0 : 0.0
        transitionMaterialView.alpha = lensBloomDebugGeometry ? 0.0 : lensOpacity * (1.0 - handoffT)
        transitionMaterialView.isHidden = lensBloomDebugGeometry
        materialBlurView.alpha = Self.lerp(0.96, 0.58, Self.smootherstep(0.58, 0.96, phaseT))
        materialTintView.alpha = Self.lerp(0.9, 0.64, Self.smootherstep(0.58, 0.96, phaseT))

        finalMenuGlassSurfaceView.frame = targetRectInCanvas
        finalMenuGlassSurfaceView.layer.cornerRadius = finalCornerRadius
        finalMenuGlassSurfaceView.clipsToBounds = true
        if lensBloomDebugGeometry {
            updateShadow(progress: 0, path: path)
        } else {
            updateShadow(progress: phaseT, path: path)
        }
        updateContent(progress: phaseT)
        updateSourceProxyVisibility(progress: phaseT)
        enforceGeometryOnlyVisibilityIfNeeded()
        updateDebugFrames()
        CATransaction.commit()
    }

    private func animateProgress(
        to target: CGFloat,
        duration: TimeInterval,
        damping: CGFloat,
        completion: (() -> Void)?
    ) {
        cancelAnimation()
        animationStart = CACurrentMediaTime()
        animationDuration = max(0.001, duration)
        animationFrom = progress
        animationTo = target
        animationDamping = damping
        animationCompletion = completion

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
        displayLink = link
    }

    private func cancelAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        animationCompletion = nil
    }

    @objc
    private func handleDisplayLink(_ link: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - animationStart
        let rawT = CGFloat(elapsed / animationDuration)
        let phaseRaw = max(0, min(1, rawT))
        let phaseProgress = animationFrom + (animationTo - animationFrom) * phaseRaw
        // Geometry itself is eased/sprung inside the lens path. Keeping the
        // display-link phase monotonic prevents alpha/content windows from
        // moving backwards while still avoiding raw linear geometry.
        let geometryProgress = phaseProgress
        progress = max(0, min(1, phaseProgress))
        updateLensShape(
            progress: max(0, min(1, phaseProgress)),
            geometryProgress: max(0, min(1, geometryProgress))
        )

        if rawT >= 1 {
            link.invalidate()
            displayLink = nil
            let completion = animationCompletion
            animationCompletion = nil
            progress = max(0, min(1, animationTo))
            completion?()
        }
    }

    private func prepareCanvasForTransition() {
        let desiredCanvas = sourceFrameInOverlay
            .union(targetMenuFrameInOverlay)
            .insetBy(dx: -Self.canvasOutset, dy: -Self.canvasOutset)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = desiredCanvas
        bounds = CGRect(origin: .zero, size: desiredCanvas.size)
        canvasFrameInOverlay = desiredCanvas
        rebuildLocalGeometry()
        if menuContentTransitionView.superview !== self {
            addSubview(menuContentTransitionView)
        }
        menuContentTransitionView.layer.mask = contentMaskLayer
        transitionMaterialView.frame = bounds
        shadowContainerView.frame = bounds
        ambientShadowLayer.frame = shadowContainerView.bounds
        contactShadowLayer.frame = shadowContainerView.bounds
        debugShadowPathLayer.frame = shadowContainerView.bounds
        materialBlurView.frame = transitionMaterialView.bounds
        materialTintView.frame = transitionMaterialView.bounds
        lensMaskLayer.frame = bounds
        debugShapeLayer.frame = bounds
        menuContentTransitionView.frame = targetRectInCanvas
        contentMaskLayer.frame = menuContentTransitionView.bounds
        finalMenuGlassSurfaceView.frame = targetRectInCanvas
        sourceProxyContainer.frame = sourceRectInCanvas
        restingHitView.frame = targetRectInCanvas
        updateContentLayerFrames()
        enforceGeometryOnlyVisibilityIfNeeded()
        bringSubviewToFront(sourceProxyContainer)
        bringSubviewToFront(menuContentTransitionView)
        bringDebugViewsToFrontIfNeeded()
        CATransaction.commit()
    }

    private func rebuildLocalGeometry() {
        let geometry = Self.makeGeometry(
            sourceFrameInOverlay: sourceFrameInOverlay,
            targetMenuFrameInOverlay: targetMenuFrameInOverlay,
            canvasOutset: Self.canvasOutset
        )
        canvasFrameInOverlay = geometry.canvasFrameInOverlay
        if frame == .zero || bounds.size == .zero {
            frame = geometry.canvasFrameInOverlay
            bounds = CGRect(origin: .zero, size: geometry.canvasFrameInOverlay.size)
        }

        sourceRectInCanvas = geometry.sourceRectInCanvas
        targetRectInCanvas = geometry.targetRectInCanvas
        lensSeedPoint = resolvedLensSeedPoint()

        assert(Self.isValidFrame(sourceFrameInOverlay), "LensBloom source frame must be finite and non-empty in overlay coordinates.")
        assert(Self.isValidFrame(targetMenuFrameInOverlay), "LensBloom target frame must be finite and non-empty in overlay coordinates.")
        assert(targetMenuFrameInOverlay != canvasFrameInOverlay, "LensBloom target menu frame must not be the transition canvas frame.")
        assert(bounds.contains(sourceRectInCanvas), "LensBloom sourceRectInCanvas must be inside canvas bounds.")
        assert(bounds.contains(targetRectInCanvas), "LensBloom targetRectInCanvas must be inside canvas bounds.")
        assert(backgroundColor == nil || backgroundColor == .clear, "LensBloom transition canvas must stay visually transparent.")

        transitionMaterialView.frame = bounds
        shadowContainerView.frame = bounds
        ambientShadowLayer.frame = shadowContainerView.bounds
        contactShadowLayer.frame = shadowContainerView.bounds
        debugShadowPathLayer.frame = shadowContainerView.bounds
        materialBlurView.frame = transitionMaterialView.bounds
        materialTintView.frame = transitionMaterialView.bounds
        lensMaskLayer.frame = bounds
        debugShapeLayer.frame = bounds
        menuContentTransitionView.frame = targetRectInCanvas
        contentMaskLayer.frame = menuContentTransitionView.bounds
        finalMenuGlassSurfaceView.frame = targetRectInCanvas
        sourceProxyContainer.frame = sourceRectInCanvas
        sourceProxyContainer.layer.cornerRadius = min(sourceRectInCanvas.width, sourceRectInCanvas.height) / 2
        if #available(iOS 13.0, *) {
            sourceProxyContainer.layer.cornerCurve = .continuous
        }
        restingHitView.frame = targetRectInCanvas
        updateContentLayerFrames()
        enforceGeometryOnlyVisibilityIfNeeded()
        updateSourceProxyVisibility(progress: progress)
        updateDebugFrames()
    }

    private func lensPath(phaseProgress: CGFloat, geometryProgress: CGFloat) -> CGPath {
        if lensBloomDebugGeometry {
            return geometryOnlyLensPath(phaseProgress: phaseProgress, geometryProgress: geometryProgress)
        }
        switch sourceMode {
        case .leasedGlassSource:
            return leasedGlassLensPath(phaseProgress: phaseProgress, geometryProgress: geometryProgress)
        case .persistentSource:
            return persistentLensPath(phaseProgress: phaseProgress, geometryProgress: geometryProgress)
        }
    }

    private func geometryOnlyLensPath(phaseProgress: CGFloat, geometryProgress: CGFloat) -> CGPath {
        let t = max(0, min(1, phaseProgress))
        let geometryT = max(0, min(1, geometryProgress))
        if t >= 0.999 {
            return UIBezierPath(
                roundedRect: targetRectInCanvas,
                cornerRadius: finalCornerRadius
            ).cgPath
        }

        if case .leasedGlassSource = sourceMode {
            return leasedGlassStagedLensPath(
                phaseProgress: phaseProgress,
                geometryProgress: geometryProgress
            )
        }

        let targetCenter = CGPoint(x: targetRectInCanvas.midX, y: targetRectInCanvas.midY)
        let startCenter = lensSeedPoint
        let startSize = CGSize(width: 36.0, height: 36.0)
        let startCornerRadius: CGFloat = 18.0

        if t <= 0.001 {
            let startRect = CGRect(
                x: startCenter.x - startSize.width / 2.0,
                y: startCenter.y - startSize.height / 2.0,
                width: startSize.width,
                height: startSize.height
            )
            return UIBezierPath(
                roundedRect: startRect,
                cornerRadius: startCornerRadius
            ).cgPath
        }

        let inflatePhaseT = Self.smootherstep(0.10, 0.52, geometryT)
        let inflateT = Self.dampedSpring01(
            inflatePhaseT,
            response: 0.42,
            dampingRatio: 0.72,
            overshootLimit: 1.06
        )
        let driftT = Self.smootherstep(0.18, 0.68, geometryT)
        let rectifyT = Self.smootherstep(0.68, 0.94, geometryT)
        let settleT = Self.dampedSpring01(
            Self.smootherstep(0.84, 1.00, geometryT),
            response: 0.34,
            dampingRatio: 0.80,
            overshootLimit: 1.03
        )

        let startRadius = startSize.width * 0.5
        let maxBubbleRadius = Self.maxLensBubbleRadius(
            from: startCenter,
            to: targetRectInCanvas,
            inside: bounds
        )
        let bubbleRadius = Self.lerpUnclamped(startRadius, maxBubbleRadius, inflateT)
        let bubbleCenter = CGPoint(
            x: Self.lerp(startCenter.x, targetCenter.x, driftT * 0.55),
            y: Self.lerp(startCenter.y, targetCenter.y, driftT * 0.55)
        )
        let bubbleRect = CGRect(
            x: bubbleCenter.x - bubbleRadius,
            y: bubbleCenter.y - bubbleRadius,
            width: bubbleRadius * 2.0,
            height: bubbleRadius * 2.0
        )
        let rectifyingRect = Self.interpolateRectByCenterAndSize(
            from: bubbleRect,
            to: targetRectInCanvas,
            t: rectifyT
        )
        let finalRect = Self.interpolateRectByCenterAndSizeUnclamped(
            from: rectifyingRect,
            to: targetRectInCanvas,
            t: settleT
        )
        let circleRadius = min(finalRect.width, finalRect.height) * 0.5
        let cornerT = Self.smootherstep(0.70, 0.98, t)
        let cornerRadius = min(
            Self.lerpUnclamped(circleRadius, finalCornerRadius, cornerT),
            circleRadius
        )

        #if DEBUG
        let pathTouchesCanvas = finalRect.minX <= 1.0 || finalRect.minY <= 1.0
            || finalRect.maxX >= bounds.width - 1.0 || finalRect.maxY >= bounds.height - 1.0
        let targetTouchesCanvas = targetRectInCanvas.minX <= 1.0 || targetRectInCanvas.minY <= 1.0
            || targetRectInCanvas.maxX >= bounds.width - 1.0 || targetRectInCanvas.maxY >= bounds.height - 1.0
        if t < 0.90, pathTouchesCanvas, !targetTouchesCanvas {
            print("LensBloom geometry warning: lens path touches canvas before final settle", "t:", t, "rect:", finalRect, "bounds:", bounds)
        }
        #endif

        return UIBezierPath(
            roundedRect: finalRect,
            cornerRadius: cornerRadius
        ).cgPath
    }

    private func persistentLensPath(phaseProgress: CGFloat, geometryProgress: CGFloat) -> CGPath {
        let phaseT = max(0, min(1, phaseProgress))
        let geometryT = max(0, min(1, geometryProgress))
        if phaseT >= 0.999 {
            return UIBezierPath(
                roundedRect: targetRectInCanvas,
                cornerRadius: finalCornerRadius
            ).cgPath
        }

        let seedT = Self.smootherstep(0.00, 0.14, phaseT)
        let bloomPhaseT = Self.smootherstep(0.10, 0.58, geometryT)
        let bloomT = Self.dampedSpring01(
            bloomPhaseT,
            response: 0.42,
            dampingRatio: 0.70,
            overshootLimit: 1.06
        )
        let rectifyT = Self.smootherstep(0.68, 0.94, geometryT)
        let settlePhaseT = Self.smootherstep(0.84, 1.00, geometryT)
        let settleT = Self.dampedSpring01(
            settlePhaseT,
            response: 0.34,
            dampingRatio: 0.78,
            overshootLimit: 1.04
        )

        let seedRadius = Self.lerp(6.0, 18.0, seedT)
        let maxBubbleSize = Self.maxBloomBubbleSize(for: targetRectInCanvas)
        let bubbleWidth = Self.lerpUnclamped(seedRadius * 2.0, maxBubbleSize.width, bloomT)
        let bubbleHeight = Self.lerpUnclamped(seedRadius * 2.0, maxBubbleSize.height, bloomT)
        let centerTravel = min(1.0, bloomT * 0.55)
        let bubbleCenter = CGPoint(
            x: Self.lerp(lensSeedPoint.x, targetRectInCanvas.midX, centerTravel),
            y: Self.lerp(lensSeedPoint.y, targetRectInCanvas.midY, centerTravel)
        )
        let bubbleRect = CGRect(
            x: bubbleCenter.x - bubbleWidth / 2.0,
            y: bubbleCenter.y - bubbleHeight / 2.0,
            width: bubbleWidth,
            height: bubbleHeight
        )

        let targetGrowRect = Self.rectGrowingFromPoint(
            finalRect: targetRectInCanvas,
            seedPoint: lensSeedPoint,
            progress: Self.smootherstep(0.24, 0.82, geometryT)
        )
        let currentRect = Self.interpolateRectByCenterAndSize(from: bubbleRect, to: targetGrowRect, t: rectifyT)
        let overshoot = 1.0 + 0.018 * sin(.pi * settlePhaseT)
        let overshotRect = Self.scale(rect: currentRect, sx: overshoot, sy: overshoot, around: CGPoint(x: currentRect.midX, y: currentRect.midY))
        let finalRectMix = Self.interpolateRectByCenterAndSizeUnclamped(from: overshotRect, to: targetRectInCanvas, t: settleT)
        let circleRadiusLike = min(finalRectMix.width, finalRectMix.height) * 0.5
        let cornerRadius = Self.lerp(circleRadiusLike, finalCornerRadius, Self.smootherstep(0.70, 0.98, geometryT))

        return UIBezierPath(
            roundedRect: finalRectMix,
            cornerRadius: min(cornerRadius, circleRadiusLike)
        ).cgPath
    }

    private func leasedGlassLensPath(phaseProgress: CGFloat, geometryProgress: CGFloat) -> CGPath {
        leasedGlassStagedLensPath(
            phaseProgress: phaseProgress,
            geometryProgress: geometryProgress
        )
    }

    private func leasedGlassStagedLensPath(phaseProgress: CGFloat, geometryProgress: CGFloat) -> CGPath {
        let t = max(0, min(1, phaseProgress))
        let geometryT = max(0, min(1, geometryProgress))
        let sourceRadius = normalizedSourceCornerRadius()
        if t >= 0.999 {
            return UIBezierPath(
                roundedRect: targetRectInCanvas,
                cornerRadius: finalCornerRadius
            ).cgPath
        }

        let sourceCenter = CGPoint(x: sourceRectInCanvas.midX, y: sourceRectInCanvas.midY)
        let targetCenter = CGPoint(x: targetRectInCanvas.midX, y: targetRectInCanvas.midY)
        let growsMostlyVertical = abs(targetCenter.y - sourceCenter.y) >= abs(targetCenter.x - sourceCenter.x)

        if t < 0.06 {
            let press = Self.smootherstep(0.00, 0.06, t)
            let compressed = Self.compressedSourceRect(
                sourceRectInCanvas,
                press: press,
                growsMostlyVertical: growsMostlyVertical
            )
            let radius = min(
                Self.lerpUnclamped(sourceRadius, sourceRadius * 1.04, press),
                min(compressed.width, compressed.height) * 0.5
            )
            return UIBezierPath(
                roundedRect: compressed,
                cornerRadius: radius
            ).cgPath
        }

        let swellT = Self.smootherstep(0.06, 0.24, geometryT)
        let ovalT = Self.smootherstep(0.18, 0.44, geometryT)
        let bubbleT = Self.dampedSpring01(
            Self.smootherstep(0.30, 0.62, geometryT),
            response: 0.42,
            dampingRatio: 0.72,
            overshootLimit: 1.05
        )
        let driftT = Self.smootherstep(0.28, 0.68, geometryT)
        let rectifyT = Self.smootherstep(0.70, 0.94, geometryT)
        let settlePhaseT = Self.smootherstep(0.86, 1.00, geometryT)
        let settleT = Self.dampedSpring01(
            settlePhaseT,
            response: 0.34,
            dampingRatio: 0.82,
            overshootLimit: 1.03
        )

        let swollenRect = Self.scale(
            rect: sourceRectInCanvas,
            sx: Self.lerp(1.0, growsMostlyVertical ? 1.08 : 1.28, swellT),
            sy: Self.lerp(1.0, growsMostlyVertical ? 1.28 : 1.08, swellT),
            around: sourceCenter
        )
        let ovalCenter = Self.lerpPoint(sourceCenter, targetCenter, driftT * 0.25)
        let ovalSize = CGSize(
            width: Self.lerp(
                swollenRect.width,
                max(sourceRectInCanvas.width * 1.18, targetRectInCanvas.width * 0.70),
                ovalT
            ),
            height: Self.lerp(
                swollenRect.height,
                max(sourceRectInCanvas.height * 2.40, targetRectInCanvas.height * 0.45),
                ovalT
            )
        )
        let ovalRect = Self.rect(center: ovalCenter, size: ovalSize)

        let bubbleProbe = Self.lerpPoint(sourceCenter, targetCenter, 0.35)
        let maxBubbleRadius = Self.maxDistance(from: bubbleProbe, toCornersOf: targetRectInCanvas) * 1.02
        let bubbleCenter = Self.lerpPoint(sourceCenter, targetCenter, driftT * 0.55)
        let bubbleDiameter = maxBubbleRadius * 2.0
        let bubbleRect = Self.rect(
            center: bubbleCenter,
            size: CGSize(width: bubbleDiameter, height: bubbleDiameter)
        )

        let lensRect = Self.interpolateRectByCenterAndSize(
            from: ovalRect,
            to: bubbleRect,
            t: bubbleT
        )
        let rectifyingRect = Self.interpolateRectByCenterAndSize(
            from: lensRect,
            to: targetRectInCanvas,
            t: rectifyT
        )
        let widthPulse = 1.0 + 0.018 * sin(.pi * settlePhaseT)
        let heightPulse = 1.0 - 0.010 * sin(.pi * settlePhaseT)
        let elasticRect: CGRect
        if t > 0.72, t < 0.98 {
            elasticRect = Self.scale(
                rect: rectifyingRect,
                sx: widthPulse,
                sy: heightPulse,
                around: CGPoint(x: rectifyingRect.midX, y: rectifyingRect.midY)
            )
        } else {
            elasticRect = rectifyingRect
        }
        let finalRect = Self.interpolateRectByCenterAndSizeUnclamped(
            from: elasticRect,
            to: targetRectInCanvas,
            t: settleT
        )

        let sourceRadiusT = Self.smootherstep(0.06, 0.24, geometryT)
        let ovalRadiusT = Self.smootherstep(0.22, 0.48, geometryT)
        let finalRadiusT = Self.smootherstep(0.72, 0.98, geometryT)
        let capsuleRadius = min(swollenRect.width, swollenRect.height) * 0.5
        let bubbleRadiusLike = min(lensRect.width, lensRect.height) * 0.5
        let earlyRadius = Self.lerpUnclamped(sourceRadius, capsuleRadius, sourceRadiusT)
        let lensRadius = Self.lerpUnclamped(earlyRadius, bubbleRadiusLike, ovalRadiusT)
        let maxCurrentRadius = min(finalRect.width, finalRect.height) * 0.5
        let cornerRadius = min(
            Self.lerpUnclamped(lensRadius, finalCornerRadius, finalRadiusT),
            maxCurrentRadius
        )

        #if DEBUG
        if t < 0.12 {
            let sourceCenterDistance = hypot(finalRect.midX - sourceCenter.x, finalRect.midY - sourceCenter.y)
            assert(sourceCenterDistance <= 12.0 || t > 0.10, "Leased glass LensBloom must start at the source, not at the target.")
        }
        if t < 0.68 {
            assert(abs(finalRect.minY - targetRectInCanvas.minY) > 0.5 || finalRect.size != targetRectInCanvas.size, "Leased glass LensBloom must not become target rect before rectification.")
        }
        if t < 0.06 {
            assert(finalRect.width <= sourceRectInCanvas.width * 1.05 && finalRect.height <= sourceRectInCanvas.height * 1.05, "Leased glass LensBloom must not become a bubble during the source hold phase.")
        }
        #endif

        return UIBezierPath(
            roundedRect: finalRect,
            cornerRadius: cornerRadius
        ).cgPath
    }

    private func updateSourceProxyVisibility(progress: CGFloat) {
        guard !lensBloomDebugGeometry else {
            sourceProxyContainer.alpha = 0.0
            sourceProxyContainer.isHidden = true
            sourceProxyContainer.transform = .identity
            return
        }
        let t = max(0, min(1, progress))
        switch sourceMode {
        case .persistentSource:
            sourceProxyContainer.alpha = 0.0
            sourceProxyContainer.isHidden = true
            sourceProxyContainer.transform = .identity
        case .leasedGlassSource:
            sourceProxyContainer.isHidden = false
            sourceProxyContainer.alpha = 1.0 - Self.smootherstep(0.16, 0.42, t)
            let pressureScale = Self.lerp(1.0, 0.96, Self.smootherstep(0.10, 0.32, t))
            sourceProxyContainer.transform = CGAffineTransform(scaleX: pressureScale, y: pressureScale)
        }
    }

    private func updateShadow(progress: CGFloat, path: CGPath) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        shadowContainerView.frame = bounds
        ambientShadowLayer.frame = shadowContainerView.bounds
        contactShadowLayer.frame = shadowContainerView.bounds
        debugShadowPathLayer.frame = shadowContainerView.bounds
        ambientShadowLayer.shadowPath = path
        contactShadowLayer.shadowPath = path
        debugShadowPathLayer.path = path
        debugShadowPathLayer.isHidden = !lensBloomDebugShadow

        let box = path.boundingBoxOfPath
//        assert(box.minX >= -2.0 && box.minY >= -2.0, "LensBloom shadow path must be in transition local coordinates.")
//        assert(box.maxX <= bounds.maxX + 2.0 && box.maxY <= bounds.maxY + 2.0, "LensBloom shadow path must stay inside transition bounds.")

        guard !lensBloomDebugGeometry else {
            ambientShadowLayer.shadowOpacity = 0.0
            contactShadowLayer.shadowOpacity = 0.0
            return
        }

        let phaseT = max(0, min(1, progress))
        let visibleT = Self.smootherstep(0.04, 0.20, phaseT)
        let energy = sin(.pi * Self.smootherstep(0.10, 0.82, phaseT))
        let settleT = Self.smootherstep(0.74, 1.0, phaseT)
        let handoffT = Self.smootherstep(0.86, 1.0, phaseT)

        let transitionAmbientOpacity = Self.lerp(
            Self.lerp(0.04, 0.11, energy),
            0.10,
            settleT
        )
        let transitionContactOpacity = Self.lerp(
            Self.lerp(0.02, 0.065, energy),
            0.045,
            settleT
        )
        let ambientOpacity = visibleT * (
            transitionAmbientOpacity * (1.0 - handoffT) + 0.10 * handoffT
        )
        let contactOpacity = visibleT * (
            transitionContactOpacity * (1.0 - handoffT) + 0.045 * handoffT
        )

        let ambientRadius = Self.lerp(
            Self.lerp(10.0, 32.0, energy),
            22.0,
            settleT
        )
        let contactRadius = Self.lerp(
            Self.lerp(6.0, 16.0, energy),
            12.0,
            settleT
        )
        let contactOffsetY = Self.lerp(
            Self.lerp(1.0, 6.0, energy),
            4.0,
            settleT
        )

        ambientShadowLayer.shadowOpacity = Float(ambientOpacity)
        ambientShadowLayer.shadowRadius = ambientRadius
        ambientShadowLayer.shadowOffset = .zero
        contactShadowLayer.shadowOpacity = Float(contactOpacity)
        contactShadowLayer.shadowRadius = contactRadius
        contactShadowLayer.shadowOffset = CGSize(width: 0, height: contactOffsetY)

        if lensBloomDebugShadow {
            print(
                "LensBloom shadow",
                "frame:", frame,
                "path:", box,
                "layer:", shadowContainerView.bounds,
                "offset:", contactShadowLayer.shadowOffset,
                "radius:", contactRadius
            )
        }
    }

    private func configureMask(_ layer: CAShapeLayer) {
        layer.contentsScale = UIScreen.main.scale
        layer.allowsEdgeAntialiasing = true
        layer.fillRule = .nonZero
    }

    private func configureShadowLayer(_ layer: CALayer) {
        layer.contentsScale = UIScreen.main.scale
        layer.backgroundColor = UIColor.clear.cgColor
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.0
        layer.shadowRadius = 10.0
        layer.shadowOffset = .zero
    }

    private func configureDebugView(_ view: UIView, color: UIColor) {
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.layer.borderColor = color.cgColor
        view.layer.borderWidth = 1.25
        view.isHidden = !Self.debugGeometryOverlayEnabled
    }

    private func configureDebugLabel(_ label: UILabel) {
        label.isUserInteractionEnabled = false
        label.font = .monospacedSystemFont(ofSize: 11.0, weight: .semibold)
        label.textColor = .systemBlue
        label.backgroundColor = UIColor.white.withAlphaComponent(0.82)
        label.layer.cornerRadius = 5.0
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.isHidden = !Self.debugGeometryOverlayEnabled
    }

    private func enforceGeometryOnlyVisibilityIfNeeded() {
        guard lensBloomDebugGeometry else { return }
        backgroundColor = .clear
        transitionMaterialView.alpha = 0.0
        transitionMaterialView.isHidden = true
        materialBlurView.alpha = 0.0
        materialTintView.alpha = 0.0
        menuContentTransitionView.alpha = 0.0
        menuContentTransitionView.isHidden = true
        transitionSnapshotContainer.alpha = 0.0
        blurredContentSnapshotView.alpha = 0.0
        sharpContentSnapshotView.alpha = 0.0
        liveMenuContentView.alpha = 0.0
        finalMenuGlassSurfaceView.alpha = 0.0
        finalMenuGlassSurfaceView.isHidden = true
        sourceProxyContainer.alpha = 0.0
        sourceProxyContainer.isHidden = true
        ambientShadowLayer.shadowOpacity = 0.0
        contactShadowLayer.shadowOpacity = 0.0
        shadowContainerView.isHidden = true
        debugShapeLayer.isHidden = false
        debugShapeLayer.opacity = 1.0
        debugCanvasView.isHidden = !Self.debugGeometryOverlayEnabled
        debugSourceView.isHidden = !Self.debugGeometryOverlayEnabled
        debugTargetView.isHidden = !Self.debugGeometryOverlayEnabled
        debugSeedView.isHidden = !Self.debugGeometryOverlayEnabled
        debugProgressLabel.isHidden = !Self.debugGeometryOverlayEnabled
        debugSourceModeLabel.isHidden = !Self.debugGeometryOverlayEnabled
    }

    private func updateDebugFrames() {
        debugCanvasView.isHidden = !Self.debugGeometryOverlayEnabled
        debugSourceView.isHidden = !Self.debugGeometryOverlayEnabled
        debugTargetView.isHidden = !Self.debugGeometryOverlayEnabled
        debugSeedView.isHidden = !Self.debugGeometryOverlayEnabled
        debugProgressLabel.isHidden = !Self.debugGeometryOverlayEnabled
        debugSourceModeLabel.isHidden = !Self.debugGeometryOverlayEnabled
        guard Self.debugGeometryOverlayEnabled else { return }
        debugCanvasView.frame = bounds
        debugSourceView.frame = sourceRectInCanvas
        debugTargetView.frame = targetRectInCanvas
        debugSeedView.frame = CGRect(
            x: lensSeedPoint.x - 4.0,
            y: lensSeedPoint.y - 4.0,
            width: 8.0,
            height: 8.0
        )
        debugProgressLabel.text = String(format: "t %.2f", Double(progress))
        debugProgressLabel.frame = CGRect(
            x: min(max(targetRectInCanvas.minX, 0), max(0, bounds.width - 70)),
            y: max(0, targetRectInCanvas.minY - 24.0),
            width: 70,
            height: 18
        )
        switch sourceMode {
        case .leasedGlassSource:
            debugSourceModeLabel.text = "leasedGlassSource"
        case .persistentSource:
            debugSourceModeLabel.text = "persistentSource"
        }
        debugSourceModeLabel.frame = CGRect(
            x: min(max(sourceRectInCanvas.minX, 0), max(0, bounds.width - 150)),
            y: min(bounds.height - 18, sourceRectInCanvas.maxY + 4.0),
            width: 150,
            height: 18
        )
    }

    private func bringDebugViewsToFrontIfNeeded() {
        guard Self.debugGeometryOverlayEnabled else { return }
        bringSubviewToFront(debugCanvasView)
        bringSubviewToFront(debugSourceView)
        bringSubviewToFront(debugTargetView)
        bringSubviewToFront(debugSeedView)
        bringSubviewToFront(debugProgressLabel)
        bringSubviewToFront(debugSourceModeLabel)
    }

    private func contentPath(fromCanvasPath path: CGPath) -> CGPath {
        var transform = CGAffineTransform(
            translationX: -targetRectInCanvas.minX,
            y: -targetRectInCanvas.minY
        )
        return path.copy(using: &transform) ?? path
    }

    private static func seedRect(for targetRect: CGRect) -> CGRect {
        guard targetRect.width > 24.0, targetRect.height > 24.0 else { return targetRect }
        return targetRect.insetBy(dx: 12.0, dy: 12.0)
    }

    private static func nearestPoint(on rect: CGRect, to point: CGPoint) -> CGPoint {
        if rect.contains(point) {
            let distances: [(CGFloat, CGPoint)] = [
                (abs(point.x - rect.minX), CGPoint(x: rect.minX, y: point.y)),
                (abs(point.x - rect.maxX), CGPoint(x: rect.maxX, y: point.y)),
                (abs(point.y - rect.minY), CGPoint(x: point.x, y: rect.minY)),
                (abs(point.y - rect.maxY), CGPoint(x: point.x, y: rect.maxY))
            ]
            return distances.min(by: { $0.0 < $1.0 })?.1 ?? point
        }
        return CGPoint(
            x: max(rect.minX, min(rect.maxX, point.x)),
            y: max(rect.minY, min(rect.maxY, point.y))
        )
    }

    private static func rectGrowingFromPoint(
        finalRect: CGRect,
        seedPoint: CGPoint,
        progress: CGFloat
    ) -> CGRect {
        let p = max(0.0, min(1.0, progress))
        if p >= 0.999 { return finalRect }

        let width = lerp(36.0, finalRect.width, p)
        let height = lerp(36.0, finalRect.height, p)

        let leftDistance = abs(seedPoint.x - finalRect.minX)
        let rightDistance = abs(seedPoint.x - finalRect.maxX)
        let topDistance = abs(seedPoint.y - finalRect.minY)
        let bottomDistance = abs(seedPoint.y - finalRect.maxY)

        let x: CGFloat
        if min(leftDistance, rightDistance) <= 18.0 {
            x = leftDistance <= rightDistance ? finalRect.minX : finalRect.maxX - width
        } else {
            x = max(finalRect.minX, min(finalRect.maxX - width, seedPoint.x - width / 2.0))
        }

        let y: CGFloat
        if min(topDistance, bottomDistance) <= 18.0 {
            y = topDistance <= bottomDistance ? finalRect.minY : finalRect.maxY - height
        } else {
            y = max(finalRect.minY, min(finalRect.maxY - height, seedPoint.y - height / 2.0))
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func maxBloomBubbleSize(for targetRect: CGRect) -> CGSize {
        // The bloom should feel like an optical lens swelling over the future
        // platter, not a full-screen circle. Keep the middle phase slightly
        // wider than the target and notably softer/shorter vertically; the
        // late rectification step grows it into the exact menu rect.
        let width = max(44.0, targetRect.width * 1.04)
        let height = max(
            44.0,
            min(targetRect.height * 0.86, targetRect.width * 0.78)
        )
        return CGSize(width: width, height: height)
    }

    private static func maxLensBubbleRadius(from startPoint: CGPoint, to targetRect: CGRect, inside bounds: CGRect) -> CGFloat {
        let targetMaxDimension = max(targetRect.width, targetRect.height)
        let targetDiagonalRadius = hypot(targetRect.width, targetRect.height) * 0.5
        let sourceDistance = hypot(targetRect.midX - startPoint.x, targetRect.midY - startPoint.y)
        let desired = max(
            targetMaxDimension * 0.58,
            min(targetDiagonalRadius * 0.92, targetMaxDimension * 0.68 + sourceDistance * 0.10)
        )
        let edgeDistances = [
            startPoint.x,
            startPoint.y,
            bounds.width - startPoint.x,
            bounds.height - startPoint.y
        ].filter { $0.isFinite && $0 > 0.0 }
        let edgeCap = max(24.0, (edgeDistances.min() ?? desired) - 2.0)
        let generousCap = max(targetMaxDimension * 0.42, edgeCap)
        return max(18.0, min(desired, generousCap))
    }

    private func resolvedLensSeedPoint() -> CGPoint {
        switch sourceMode {
        case .leasedGlassSource:
            return CGPoint(x: sourceRectInCanvas.midX, y: sourceRectInCanvas.midY)
        case .persistentSource:
            return Self.nearestPoint(
                on: Self.seedRect(for: targetRectInCanvas),
                to: CGPoint(x: sourceRectInCanvas.midX, y: sourceRectInCanvas.midY)
            )
        }
    }

    private func normalizedSourceCornerRadius() -> CGFloat {
        let maxRadius = min(sourceRectInCanvas.width, sourceRectInCanvas.height) * 0.5
        let radius = sourceCornerRadius > 0.0 ? sourceCornerRadius : maxRadius
        return min(max(0.0, radius), maxRadius)
    }

    private static func interpolateRect(from: CGRect, to: CGRect, t: CGFloat) -> CGRect {
        CGRect(
            x: lerp(from.minX, to.minX, t),
            y: lerp(from.minY, to.minY, t),
            width: lerp(from.width, to.width, t),
            height: lerp(from.height, to.height, t)
        )
    }

    private static func interpolateRectByCenterAndSize(from: CGRect, to: CGRect, t: CGFloat) -> CGRect {
        let clamped = max(0, min(1, t))
        let center = CGPoint(
            x: lerp(from.midX, to.midX, clamped),
            y: lerp(from.midY, to.midY, clamped)
        )
        let size = CGSize(
            width: lerp(from.width, to.width, clamped),
            height: lerp(from.height, to.height, clamped)
        )
        return CGRect(
            x: center.x - size.width / 2.0,
            y: center.y - size.height / 2.0,
            width: size.width,
            height: size.height
        )
    }

    private static func interpolateRectByCenterAndSizeUnclamped(from: CGRect, to: CGRect, t: CGFloat) -> CGRect {
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

    private static func maxDistance(from point: CGPoint, toCornersOf rect: CGRect) -> CGFloat {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        .map { hypot($0.x - point.x, $0.y - point.y) }
        .max() ?? max(rect.width, rect.height)
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

    private static func compressedSourceRect(
        _ sourceRect: CGRect,
        press: CGFloat,
        growsMostlyVertical: Bool
    ) -> CGRect {
        let compression = 1.0 - 0.025 * press
        let stretch = 1.0 + 0.018 * press
        return scale(
            rect: sourceRect,
            sx: growsMostlyVertical ? compression : stretch,
            sy: growsMostlyVertical ? stretch : compression,
            around: CGPoint(x: sourceRect.midX, y: sourceRect.midY)
        )
    }

    private static func rect(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: center.x - size.width / 2.0,
            y: center.y - size.height / 2.0,
            width: size.width,
            height: size.height
        )
    }

    private static func lerpPoint(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(
            x: lerp(a.x, b.x, t),
            y: lerp(a.y, b.y, t)
        )
    }

    private static func makeGeometry(
        sourceFrameInOverlay: CGRect,
        targetMenuFrameInOverlay: CGRect,
        canvasOutset: CGFloat
    ) -> ContextMenuGeometry {
        let canvasFrame = sourceFrameInOverlay
            .union(targetMenuFrameInOverlay)
            .insetBy(dx: -canvasOutset, dy: -canvasOutset)
        let sourceRect = sourceFrameInOverlay.offsetBy(
            dx: -canvasFrame.minX,
            dy: -canvasFrame.minY
        )
        let targetRect = targetMenuFrameInOverlay.offsetBy(
            dx: -canvasFrame.minX,
            dy: -canvasFrame.minY
        )
        return ContextMenuGeometry(
            sourceFrameInOverlay: sourceFrameInOverlay,
            targetMenuFrameInOverlay: targetMenuFrameInOverlay,
            canvasFrameInOverlay: canvasFrame,
            sourceRectInCanvas: sourceRect,
            targetRectInCanvas: targetRect
        )
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * max(0, min(1, t))
    }

    private static func lerpUnclamped(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private static func smootherstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x <= edge0 ? 0 : 1 }
        let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * t * (t * (6.0 * t - 15.0) + 10.0)
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
            return min(max(value, 0.0), overshootLimit)
        } else {
            let value = 1.0 - exp(-omega0 * x) * (1.0 + omega0 * x)
            return min(max(value, 0.0), 1.0)
        }
    }

    private static func renderImage(of view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    private static func blurredImage(from image: UIImage, radius: CGFloat) -> UIImage {
        guard radius > 0.0, let cgImage = image.cgImage else { return image }
        let input = CIImage(cgImage: cgImage)
        let clamp = input.clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(clamp, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return image }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let result = context.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: result, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func isValidFrame(_ frame: CGRect) -> Bool {
        frame.width.isFinite && frame.height.isFinite
            && frame.minX.isFinite && frame.minY.isFinite
            && frame.width > 0.0 && frame.height > 0.0
    }
}
