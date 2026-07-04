import UIKit

/// Supplies custom UIKit animators for `AetherModalController`
/// presentation and dismissal.
///
/// Assign an implementation to `AetherModalController.transitionAnimation`.
/// Return `nil` from either factory to use the default bottom-sheet
/// animation for that edge.
public protocol AetherModalTransitionAnimation: AnyObject {
    func makePresentationAnimator(
        for modalController: AetherModalController
    ) -> UIViewControllerAnimatedTransitioning?

    func makeDismissalAnimator(
        for modalController: AetherModalController
    ) -> UIViewControllerAnimatedTransitioning?
}

public extension AetherModalTransitionAnimation {
    func makePresentationAnimator(
        for modalController: AetherModalController
    ) -> UIViewControllerAnimatedTransitioning? {
        nil
    }

    func makeDismissalAnimator(
        for modalController: AetherModalController
    ) -> UIViewControllerAnimatedTransitioning? {
        nil
    }
}

/// Built-in source-to-modal morph transition.
///
/// This is the Telegram attachment-menu style entrance: the modal starts
/// at a source button/frame and expands into its resolved detent frame,
/// then dismisses back into the same source.
public final class AetherModalSourceTransition: AetherModalTransitionAnimation {
    public struct Configuration: Equatable {
        public var presentationDuration: TimeInterval
        public var dismissalDuration: TimeInterval
        public var presentationDampingRatio: CGFloat
        public var dismissalDampingRatio: CGFloat
        public var initialSpringVelocity: CGFloat
        public var overscaleAmount: CGFloat
        public var sourceCornerRadius: CGFloat?
        public var targetCornerRadius: CGFloat?
        public var hidesSourceViewDuringTransition: Bool

        public init(
            presentationDuration: TimeInterval = 0.14,
            dismissalDuration: TimeInterval = 0.10,
            presentationDampingRatio: CGFloat = 110.0,
            dismissalDampingRatio: CGFloat = 124.0,
            initialSpringVelocity: CGFloat = 1.1,
            overscaleAmount: CGFloat = 0.028,
            sourceCornerRadius: CGFloat? = nil,
            targetCornerRadius: CGFloat? = nil,
            hidesSourceViewDuringTransition: Bool = true
        ) {
            self.presentationDuration = presentationDuration
            self.dismissalDuration = dismissalDuration
            self.presentationDampingRatio = presentationDampingRatio
            self.dismissalDampingRatio = dismissalDampingRatio
            self.initialSpringVelocity = initialSpringVelocity
            self.overscaleAmount = overscaleAmount
            self.sourceCornerRadius = sourceCornerRadius
            self.targetCornerRadius = targetCornerRadius
            self.hidesSourceViewDuringTransition = hidesSourceViewDuringTransition
        }
    }

    public var configuration: Configuration

    private weak var sourceView: UIView?
    private weak var sourcePresentation: (any AetherModalSourcePresentation)?
    private var sourceFrameInWindow: CGRect?

    public init(
        sourceView: UIView,
        configuration: Configuration = .init()
    ) {
        self.sourceView = sourceView
        self.configuration = configuration
    }

    public init(
        sourceFrameInWindow: CGRect,
        configuration: Configuration = .init()
    ) {
        self.sourceFrameInWindow = sourceFrameInWindow
        self.configuration = configuration
    }

    public init(
        sourcePresentation: any AetherModalSourcePresentation,
        configuration: Configuration = .init()
    ) {
        self.sourcePresentation = sourcePresentation
        self.configuration = configuration
    }

    public func makePresentationAnimator(
        for modalController: AetherModalController
    ) -> UIViewControllerAnimatedTransitioning? {
        AetherModalSourcePresentAnimator(
            sourceTransition: self,
            modalController: modalController
        )
    }

    public func makeDismissalAnimator(
        for modalController: AetherModalController
    ) -> UIViewControllerAnimatedTransitioning? {
        AetherModalSourceDismissAnimator(
            sourceTransition: self,
            modalController: modalController
        )
    }

    fileprivate func resolvedSourceView() -> UIView? {
        sourcePresentation?.aetherModalSourceView ?? sourceView
    }

    fileprivate func resolvedSourceFrame(in container: UIView) -> CGRect? {
        if let view = resolvedSourceView(), !view.bounds.isEmpty {
            let frameInWindow = view.convert(view.bounds, to: nil)
            return Self.validFrame(container.convert(frameInWindow, from: nil))
        }

        if let frameInWindow = sourcePresentation?.aetherModalSourceFrameInWindow
            ?? sourceFrameInWindow {
            return Self.validFrame(container.convert(frameInWindow, from: nil))
        }

        return nil
    }

    fileprivate func sourceCornerRadius(for frame: CGRect) -> CGFloat {
        if let value = configuration.sourceCornerRadius {
            return Self.clampedRadius(value, in: frame)
        }

        let sourceLayer = resolvedSourceView()?.layer
        let layerRadius = sourceLayer?.presentation()?.cornerRadius
            ?? sourceLayer?.cornerRadius
            ?? 0.0
        let value = layerRadius > 0.0
            ? layerRadius
            : min(frame.width, frame.height) / 2.0
        return Self.clampedRadius(value, in: frame)
    }

    fileprivate func targetCornerRadius(
        for frame: CGRect,
        modalController: AetherModalController?
    ) -> CGFloat {
        let value = configuration.targetCornerRadius
            ?? modalController?.config.topCornerRadius
            ?? 34.0
        return Self.clampedRadius(value, in: frame)
    }

    fileprivate func targetBottomCornerRadius(
        for frame: CGRect,
        modalController: AetherModalController?
    ) -> CGFloat {
        let topRadius = targetCornerRadius(for: frame, modalController: modalController)
        let deviceRadius = modalController?.deviceCornerRadius() ?? 0.0
        let value = deviceRadius > 0.0 ? deviceRadius : topRadius
        return Self.clampedRadius(value, in: frame)
    }

    private static func clampedRadius(_ radius: CGFloat, in frame: CGRect) -> CGFloat {
        guard radius.isFinite else { return 0 }
        return max(0.0, min(radius, min(frame.width, frame.height) / 2.0))
    }

    private static func validFrame(_ frame: CGRect) -> CGRect? {
        guard
            frame.origin.x.isFinite,
            frame.origin.y.isFinite,
            frame.size.width.isFinite,
            frame.size.height.isFinite,
            frame.width > 0.0,
            frame.height > 0.0
        else {
            return nil
        }
        return frame
    }
}

public extension AetherModalController {
    /// Use the built-in source-to-modal transition from a concrete view.
    func useSourceTransition(
        from sourceView: UIView,
        configuration: AetherModalSourceTransition.Configuration = .init()
    ) {
        transitionAnimation = AetherModalSourceTransition(
            sourceView: sourceView,
            configuration: configuration
        )
    }

    /// Use the built-in source-to-modal transition from an object that can
    /// provide either a source view or a source frame in window coordinates.
    func useSourceTransition(
        from sourcePresentation: any AetherModalSourcePresentation,
        configuration: AetherModalSourceTransition.Configuration = .init()
    ) {
        transitionAnimation = AetherModalSourceTransition(
            sourcePresentation: sourcePresentation,
            configuration: configuration
        )
    }

    /// Use the built-in source-to-modal transition from a frame already
    /// expressed in window coordinates.
    func useSourceTransition(
        sourceFrameInWindow: CGRect,
        configuration: AetherModalSourceTransition.Configuration = .init()
    ) {
        transitionAnimation = AetherModalSourceTransition(
            sourceFrameInWindow: sourceFrameInWindow,
            configuration: configuration
        )
    }
}

private final class AetherModalSourcePresentAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let sourceTransition: AetherModalSourceTransition
    private weak var modalController: AetherModalController?

    init(
        sourceTransition: AetherModalSourceTransition,
        modalController: AetherModalController
    ) {
        self.sourceTransition = sourceTransition
        self.modalController = modalController
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        sourceTransition.configuration.presentationDuration
    }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let toVC = ctx.viewController(forKey: .to),
              let toView = ctx.view(forKey: .to) else {
            ctx.completeTransition(false)
            return
        }

        let container = ctx.containerView
        guard let sourceFrame = sourceTransition.resolvedSourceFrame(in: container) else {
            AetherModalPresentAnimator().animateTransition(using: ctx)
            return
        }

        let finalFrame = ctx.finalFrame(for: toVC)
        let cfg = sourceTransition.configuration
        let sourceView = sourceTransition.resolvedSourceView()
        let sourceSnapshot = Self.makeSourceSnapshot(
            sourceView: sourceView,
            sourceFrame: sourceFrame,
            cornerRadius: sourceTransition.sourceCornerRadius(for: sourceFrame)
        )

        container.addSubview(toView)
        toView.frame = finalFrame
        toView.alpha = 1.0
        toView.setNeedsLayout()
        toView.layoutIfNeeded()

        let destinationSnapshot = Self.makeSnapshot(of: toView, afterScreenUpdates: true)
            ?? Self.placeholderSnapshot(
                size: finalFrame.size,
                color: modalController?.config.dimTintColor ?? .systemBackground
            )
        toView.alpha = 0.0

        let sourceAlpha = sourceView?.alpha

        let morphView = AetherModalSourceMorphTransitionView()
        morphView.configure(
            metrics: .init(
                sourceFrame: sourceFrame,
                sourceCornerRadius: sourceTransition.sourceCornerRadius(for: sourceFrame),
                targetFrame: finalFrame,
                targetCornerRadius: sourceTransition.targetCornerRadius(
                    for: finalFrame,
                    modalController: modalController
                ),
                targetBottomCornerRadius: sourceTransition.targetBottomCornerRadius(
                    for: finalFrame,
                    modalController: modalController
                ),
                containerBounds: container.bounds
            ),
            startsExpanded: false
        )
        morphView.installSourceSnapshot(sourceSnapshot)
        morphView.installDestinationSnapshot(destinationSnapshot)
        container.addSubview(morphView)

        if cfg.hidesSourceViewDuringTransition {
            sourceView?.alpha = 0.0
        }

        morphView.animateExpand(
            duration: transitionDuration(using: ctx),
            damping: cfg.presentationDampingRatio,
            initialVelocity: cfg.initialSpringVelocity,
            overscaleAmount: cfg.overscaleAmount,
            completion: {
                let completed = !ctx.transitionWasCancelled
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                morphView.removeFromSuperview()
                if completed {
                    toView.frame = finalFrame
                    toView.alpha = 1.0
                    toView.setNeedsLayout()
                    toView.layoutIfNeeded()
                } else {
                    toView.removeFromSuperview()
                }
                CATransaction.commit()
                if cfg.hidesSourceViewDuringTransition {
                    sourceView?.alpha = sourceAlpha ?? 1.0
                }
                ctx.completeTransition(completed)
            }
        )
    }
}

private final class AetherModalSourceDismissAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let sourceTransition: AetherModalSourceTransition
    private weak var modalController: AetherModalController?

    init(
        sourceTransition: AetherModalSourceTransition,
        modalController: AetherModalController
    ) {
        self.sourceTransition = sourceTransition
        self.modalController = modalController
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        sourceTransition.configuration.dismissalDuration
    }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let fromView = ctx.view(forKey: .from) else {
            ctx.completeTransition(false)
            return
        }

        let container = ctx.containerView
        guard let sourceFrame = sourceTransition.resolvedSourceFrame(in: container) else {
            AetherModalDismissAnimator().animateTransition(using: ctx)
            return
        }

        let startFrame = fromView.frame
        let cfg = sourceTransition.configuration
        let sourceView = sourceTransition.resolvedSourceView()
        let sourceSnapshot = Self.makeSourceSnapshot(
            sourceView: sourceView,
            sourceFrame: sourceFrame,
            cornerRadius: sourceTransition.sourceCornerRadius(for: sourceFrame)
        )
        fromView.setNeedsLayout()
        fromView.layoutIfNeeded()
        let destinationSnapshot = Self.makeSnapshot(of: fromView, afterScreenUpdates: false)
            ?? Self.placeholderSnapshot(
                size: startFrame.size,
                color: modalController?.config.dimTintColor ?? .systemBackground
            )

        let sourceAlpha = sourceView?.alpha
        if cfg.hidesSourceViewDuringTransition {
            sourceView?.alpha = sourceAlpha ?? 1.0
        }

        fromView.alpha = 0.0

        let morphView = AetherModalSourceMorphTransitionView()
        morphView.configure(
            metrics: .init(
                sourceFrame: sourceFrame,
                sourceCornerRadius: sourceTransition.sourceCornerRadius(for: sourceFrame),
                targetFrame: startFrame,
                targetCornerRadius: sourceTransition.targetCornerRadius(
                    for: startFrame,
                    modalController: modalController
                ),
                targetBottomCornerRadius: sourceTransition.targetBottomCornerRadius(
                    for: startFrame,
                    modalController: modalController
                ),
                containerBounds: container.bounds
            ),
            startsExpanded: true
        )
        morphView.installSourceSnapshot(sourceSnapshot)
        morphView.installDestinationSnapshot(destinationSnapshot)
        container.addSubview(morphView)

        morphView.animateCollapse(
            duration: transitionDuration(using: ctx),
            damping: cfg.dismissalDampingRatio,
            initialVelocity: cfg.initialSpringVelocity,
            overscaleAmount: cfg.overscaleAmount,
            completion: {
                let completed = !ctx.transitionWasCancelled
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                morphView.removeFromSuperview()
                fromView.alpha = 1.0
                if !completed {
                    fromView.frame = startFrame
                    fromView.setNeedsLayout()
                    fromView.layoutIfNeeded()
                }
                CATransaction.commit()
                if cfg.hidesSourceViewDuringTransition {
                    sourceView?.alpha = sourceAlpha ?? 1.0
                }
                ctx.completeTransition(completed)
            }
        )
    }
}

private extension NSObject {
    static func makeSourceSnapshot(
        sourceView: UIView?,
        sourceFrame: CGRect,
        cornerRadius: CGFloat
    ) -> UIView {
        if let sourceView {
            sourceView.setNeedsLayout()
            sourceView.layoutIfNeeded()
            if let snapshot = makeSnapshot(of: sourceView, afterScreenUpdates: false) {
                snapshot.frame = CGRect(origin: .zero, size: sourceFrame.size)
                return snapshot
            }
        }

        return placeholderSnapshot(
            size: sourceFrame.size,
            color: UIColor.secondarySystemBackground.withAlphaComponent(0.92),
            cornerRadius: cornerRadius
        )
    }

    static func makeSnapshot(of view: UIView, afterScreenUpdates: Bool) -> UIView? {
        guard view.bounds.width > 0.0, view.bounds.height > 0.0 else { return nil }
        if let snapshot = view.snapshotView(afterScreenUpdates: afterScreenUpdates) {
            snapshot.frame = view.bounds
            return snapshot
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = view.window?.screen.scale ?? UIScreen.main.scale
        format.opaque = false
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            let didDraw = view.drawHierarchy(
                in: view.bounds,
                afterScreenUpdates: afterScreenUpdates
            )
            if !didDraw {
                view.layer.render(in: context.cgContext)
            }
        }
        let imageView = UIImageView(image: image)
        imageView.frame = view.bounds
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        return imageView
    }

    static func placeholderSnapshot(
        size: CGSize,
        color: UIColor,
        cornerRadius: CGFloat = 0.0
    ) -> UIView {
        let view = UIView(frame: CGRect(origin: .zero, size: size))
        view.backgroundColor = color
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        return view
    }

}

private final class AetherModalSourceMorphTransitionView: UIView {
    struct Metrics {
        let sourceFrame: CGRect
        let sourceCornerRadius: CGFloat
        let targetFrame: CGRect
        let targetCornerRadius: CGFloat
        let targetBottomCornerRadius: CGFloat
        let containerBounds: CGRect
    }

    private struct CornerRadii {
        var topLeft: CGFloat
        var topRight: CGFloat
        var bottomRight: CGFloat
        var bottomLeft: CGFloat
    }

    private let shadowView = UIView()
    private let surfaceView = UIView()
    private let surfaceMaskLayer = CAShapeLayer()
    private let materialView: UIVisualEffectView
    private let tintView = UIView()
    private let highlightView = UIView()
    private let highlightLayer = CAGradientLayer()
    private let sourceContent = UIView()
    private let destinationContent = UIView()
    private let progressDriverView = UIView(frame: CGRect(x: -2.0, y: -2.0, width: 1.0, height: 1.0))
    private var metrics: Metrics?
    private var progressAnimator: UIViewPropertyAnimator?
    private var progressDisplayLink: CADisplayLink?
    private var progressOvershootLimit: CGFloat = 0.028
    private var isCollapsing = false
    private var progress: CGFloat = 0
    private var progressCompletion: (() -> Void)?

    init() {
        self.materialView = UIVisualEffectView(effect: nil)
        super.init(frame: .zero)

        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false

        progressDriverView.isUserInteractionEnabled = false
        progressDriverView.backgroundColor = .clear
        addSubview(progressDriverView)

        shadowView.backgroundColor = .clear
        shadowView.isUserInteractionEnabled = false
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = 0.0
        shadowView.layer.shadowRadius = 0.0
        shadowView.layer.shadowOffset = .zero
        addSubview(shadowView)

        surfaceView.backgroundColor = .clear
        surfaceView.clipsToBounds = true
        surfaceView.layer.masksToBounds = true
        surfaceView.layer.cornerRadius = 0.0
        surfaceView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        surfaceMaskLayer.fillColor = UIColor.black.cgColor
        surfaceView.layer.mask = surfaceMaskLayer
        addSubview(surfaceView)

        materialView.isUserInteractionEnabled = false
        materialView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        surfaceView.addSubview(materialView)

        tintView.backgroundColor = .clear
        tintView.isUserInteractionEnabled = false
        tintView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        surfaceView.addSubview(tintView)

        highlightView.backgroundColor = .clear
        highlightView.isUserInteractionEnabled = false
        highlightView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        highlightLayer.type = .radial
        highlightLayer.colors = [
            UIColor.white.withAlphaComponent(0.55).cgColor,
            UIColor.white.withAlphaComponent(0.16).cgColor,
            UIColor.white.withAlphaComponent(0.0).cgColor
        ]
        highlightLayer.locations = [0.0, 0.42, 1.0]
        highlightLayer.startPoint = CGPoint(x: 0.50, y: 0.50)
        highlightLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        highlightView.layer.addSublayer(highlightLayer)
        surfaceView.addSubview(highlightView)

        destinationContent.backgroundColor = .clear
        destinationContent.isUserInteractionEnabled = false
        surfaceView.addSubview(destinationContent)

        sourceContent.backgroundColor = .clear
        sourceContent.isUserInteractionEnabled = false
        surfaceView.addSubview(sourceContent)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        progressDisplayLink?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyProgress(progress)
    }

    func configure(metrics: Metrics, startsExpanded: Bool) {
        self.metrics = metrics
        cancelRunningAnimators()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = metrics.containerBounds
        configureContentFrames(metrics: metrics)
        configureShadow(metrics: metrics, expanded: startsExpanded)
        progress = startsExpanded ? 1.0 : 0.0
        progressDriverView.transform = CGAffineTransform(translationX: progress, y: 0.0)
        applyProgress(progress)
        CATransaction.commit()
    }

    func installSourceSnapshot(_ snapshot: UIView) {
        sourceContent.subviews.forEach { $0.removeFromSuperview() }
        snapshot.frame = sourceContent.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sourceContent.addSubview(snapshot)
    }

    func installDestinationSnapshot(_ snapshot: UIView) {
        destinationContent.subviews.forEach { $0.removeFromSuperview() }
        snapshot.frame = destinationContent.bounds
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        destinationContent.addSubview(snapshot)
    }

    func animateExpand(
        duration: TimeInterval,
        damping: CGFloat,
        initialVelocity: CGFloat,
        overscaleAmount: CGFloat,
        completion: @escaping () -> Void
    ) {
        guard metrics != nil else {
            completion()
            return
        }
        cancelRunningAnimators()
        isCollapsing = false
        progressOvershootLimit = Self.resolvedOvershootLimit(overscaleAmount)
        animateShadow(fromExpanded: false, toExpanded: true, duration: min(duration, 0.12))
        animateProgress(
            to: 1.0,
            duration: min(duration, 0.12),
            damping: damping,
            initialVelocity: initialVelocity,
            reversed: false,
            completion: completion
        )
    }

    func animateCollapse(
        duration: TimeInterval,
        damping: CGFloat,
        initialVelocity: CGFloat,
        overscaleAmount: CGFloat,
        completion: @escaping () -> Void
    ) {
        guard metrics != nil else {
            completion()
            return
        }
        cancelRunningAnimators()
        isCollapsing = true
        progressOvershootLimit = Self.resolvedOvershootLimit(overscaleAmount)
        animateShadow(fromExpanded: true, toExpanded: false, duration: min(duration, 0.09))
        animateProgress(
            to: 0.0,
            duration: min(duration, 0.09),
            damping: damping,
            initialVelocity: initialVelocity,
            reversed: true,
            completion: completion
        )
    }

    private func animateProgress(
        to target: CGFloat,
        duration: TimeInterval,
        damping _: CGFloat,
        initialVelocity _: CGFloat,
        reversed _: Bool,
        completion: @escaping () -> Void
    ) {
        progressCompletion = completion

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressDriverView.layer.removeAllAnimations()
        progressDriverView.transform = CGAffineTransform(translationX: progress, y: 0.0)
        applyProgress(progress)
        CATransaction.commit()

        let timing = UICubicTimingParameters(
            controlPoint1: CGPoint(x: 0.16, y: 0.84),
            controlPoint2: CGPoint(x: 0.22, y: 1.0)
        )
        let animator = UIViewPropertyAnimator(duration: max(0.001, duration), timingParameters: timing)
        animator.isInterruptible = true
        animator.addAnimations { [weak self] in
            self?.progressDriverView.transform = CGAffineTransform(translationX: target, y: 0.0)
        }
        animator.addCompletion { [weak self, weak animator] _ in
            guard let self, let animator, self.progressAnimator === animator else {
                return
            }

            self.stopProgressDisplayLink()
            self.progressAnimator = nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.progressDriverView.layer.removeAllAnimations()
            self.progress = max(0.0, min(1.0, target))
            self.progressDriverView.transform = CGAffineTransform(translationX: self.progress, y: 0.0)
            self.applyProgress(self.progress)
            CATransaction.commit()

            let completion = self.progressCompletion
            self.progressCompletion = nil
            completion?()
        }

        progressAnimator = animator
        startProgressDisplayLink()
        animator.startAnimation()
    }

    private func startCornerRadius(metrics: Metrics) -> CGFloat {
        max(0.0, min(metrics.sourceCornerRadius, min(metrics.sourceFrame.width, metrics.sourceFrame.height) * 0.5))
    }

    private func configureContentFrames(metrics: Metrics) {
        sourceContent.frame = CGRect(
            origin: .zero,
            size: metrics.sourceFrame.size
        )
        sourceContent.autoresizingMask = []
        sourceContent.alpha = 1.0
        sourceContent.transform = .identity

        destinationContent.frame = CGRect(
            origin: .zero,
            size: metrics.targetFrame.size
        )
        destinationContent.autoresizingMask = []
        destinationContent.alpha = 0.0
        destinationContent.transform = .identity
    }

    private func updateSurfaceShape(progress: CGFloat) {
        guard let metrics else { return }

        let t = max(0.0, min(1.0, progress))
        let radiusT = Self.smootherstep(0.0, 0.46, t)
        let startRadius = startCornerRadius(metrics: metrics)
        let topRadius = Self.lerp(startRadius, metrics.targetCornerRadius, radiusT)
        let bottomRadius = Self.lerp(startRadius, metrics.targetBottomCornerRadius, radiusT)
        let radii = CornerRadii(
            topLeft: topRadius,
            topRight: topRadius,
            bottomRight: bottomRadius,
            bottomLeft: bottomRadius
        )

        let path = Self.roundedRectPath(in: surfaceView.bounds, radii: radii)
        surfaceMaskLayer.frame = surfaceView.bounds
        surfaceMaskLayer.path = path
        shadowView.layer.shadowPath = path
    }

    private func configureShadow(metrics: Metrics, expanded: Bool) {
        shadowView.layer.shadowOpacity = expanded ? 0.12 : 0.0
        shadowView.layer.shadowRadius = expanded ? 18.0 : 0.0
        shadowView.layer.shadowOffset = CGSize(width: 0.0, height: expanded ? 6.0 : 0.0)
        updateSurfaceShape(progress: expanded ? 1.0 : 0.0)
    }

    private func animateShadow(fromExpanded: Bool, toExpanded: Bool, duration: TimeInterval) {
        let opacity = CAKeyframeAnimation(keyPath: "shadowOpacity")
        opacity.values = fromExpanded
            ? [0.12, 0.06, 0.0]
            : [0.0, 0.16, 0.12]
        opacity.keyTimes = [0.0, 0.45, 1.0]
        opacity.duration = duration
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shadowView.layer.shadowOpacity = toExpanded ? 0.12 : 0.0
        shadowView.layer.add(opacity, forKey: "modalSourceMorphShadowOpacity")

        let radius = CAKeyframeAnimation(keyPath: "shadowRadius")
        radius.values = fromExpanded
            ? [18.0, 8.0, 0.0]
            : [0.0, 22.0, 18.0]
        radius.keyTimes = [0.0, 0.45, 1.0]
        radius.duration = duration
        radius.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shadowView.layer.shadowRadius = toExpanded ? 18.0 : 0.0
        shadowView.layer.add(radius, forKey: "modalSourceMorphShadowRadius")
    }

    private func startProgressDisplayLink() {
        stopProgressDisplayLink()
        let link = CADisplayLink(target: self, selector: #selector(handleProgressDisplayLink(_:)))
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

    @objc private func handleProgressDisplayLink(_ link: CADisplayLink) {
        sampleProgress()
        applyProgress(progress)
    }

    private func stopProgressDisplayLink() {
        progressDisplayLink?.invalidate()
        progressDisplayLink = nil
    }

    private func sampleProgress() {
        let sampled = progressDriverView.layer.presentation()?.affineTransform().tx
            ?? progressDriverView.transform.tx
        progress = max(-progressOvershootLimit, min(1.0 + progressOvershootLimit, sampled))
    }

    private func applyProgress(_ value: CGFloat) {
        guard let metrics else { return }

        let geometryT = max(-progressOvershootLimit, min(1.0 + progressOvershootLimit, value))
        let t = max(0.0, min(1.0, geometryT))
        progress = geometryT
        let targetSize = metrics.targetFrame.size
        let currentFrame = currentSurfaceFrame(metrics: metrics, progress: geometryT)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowView.frame = currentFrame
        shadowView.transform = .identity
        surfaceView.frame = currentFrame
        surfaceView.transform = .identity

        materialView.frame = surfaceView.bounds
        tintView.frame = surfaceView.bounds
        highlightView.frame = surfaceView.bounds
        highlightLayer.frame = highlightView.bounds.insetBy(
            dx: -highlightView.bounds.width * 0.18,
            dy: -highlightView.bounds.height * 0.18
        )

        sourceContent.frame = CGRect(
            x: metrics.sourceFrame.minX - currentFrame.minX,
            y: metrics.sourceFrame.minY - currentFrame.minY,
            width: metrics.sourceFrame.width,
            height: metrics.sourceFrame.height
        )
        destinationContent.frame = CGRect(
            x: metrics.targetFrame.minX - currentFrame.minX,
            y: metrics.targetFrame.minY - currentFrame.minY,
            width: targetSize.width,
            height: targetSize.height
        )

        updateSurfaceShape(progress: t)
        materialView.alpha = 0.0
        tintView.backgroundColor = .clear
        highlightView.alpha = 0.0
        highlightLayer.startPoint = CGPoint(x: Self.lerp(0.24, 0.50, t), y: Self.lerp(0.26, 0.18, t))
        highlightLayer.endPoint = CGPoint(x: Self.lerp(0.92, 1.0, t), y: Self.lerp(0.92, 0.82, t))

        surfaceView.layer.borderWidth = 0.0
        surfaceView.layer.borderColor = UIColor.clear.cgColor
        let sourceAlpha = isCollapsing
            ? 1.0 - Self.smootherstep(0.10, 0.48, t)
            : 1.0 - Self.smootherstep(0.04, 0.22, t)
        let destinationAlpha = isCollapsing
            ? Self.smootherstep(0.02, 0.42, t)
            : Self.smootherstep(0.08, 0.34, t)
        sourceContent.alpha = sourceAlpha
        sourceContent.transform = CGAffineTransform(
            scaleX: Self.lerp(1.0, 0.92, Self.smootherstep(0.0, 0.30, t)),
            y: Self.lerp(1.0, 0.92, Self.smootherstep(0.0, 0.30, t))
        )
        destinationContent.alpha = destinationAlpha
        destinationContent.transform = CGAffineTransform(
            translationX: 0.0,
            y: isCollapsing ? 0.0 : Self.lerp(10.0, 0.0, Self.smootherstep(0.08, 0.42, t))
        )
        CATransaction.commit()
    }

    private func currentSurfaceFrame(metrics: Metrics, progress: CGFloat) -> CGRect {
        let t = max(0.0, min(1.0, progress))
        let centerT = isCollapsing
            ? Self.easeInPower(t, 1.55)
            : Self.easeOutPower(t, 1.75)
        let sizeT = isCollapsing
            ? Self.easeInPower(t, 1.35)
            : Self.easeOutPower(t, 1.55)
        return Self.interpolateRectByCenterAndSize(
            from: metrics.sourceFrame,
            to: metrics.targetFrame,
            centerT: centerT,
            sizeT: sizeT
        )
    }

    private static func roundedRectPath(in rect: CGRect, radii: CornerRadii) -> CGPath {
        guard rect.width > 0.0, rect.height > 0.0 else {
            return CGPath(rect: rect, transform: nil)
        }

        let maxRadius = min(rect.width, rect.height) * 0.5
        let topLeft = max(0.0, min(radii.topLeft, maxRadius))
        let topRight = max(0.0, min(radii.topRight, maxRadius))
        let bottomRight = max(0.0, min(radii.bottomRight, maxRadius))
        let bottomLeft = max(0.0, min(radii.bottomLeft, maxRadius))

        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        if topRight > 0.0 {
            path.addArc(
                withCenter: CGPoint(x: rect.maxX - topRight, y: rect.minY + topRight),
                radius: topRight,
                startAngle: -.pi / 2.0,
                endAngle: 0.0,
                clockwise: true
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        if bottomRight > 0.0 {
            path.addArc(
                withCenter: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY - bottomRight),
                radius: bottomRight,
                startAngle: 0.0,
                endAngle: .pi / 2.0,
                clockwise: true
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        if bottomLeft > 0.0 {
            path.addArc(
                withCenter: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY - bottomLeft),
                radius: bottomLeft,
                startAngle: .pi / 2.0,
                endAngle: .pi,
                clockwise: true
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        if topLeft > 0.0 {
            path.addArc(
                withCenter: CGPoint(x: rect.minX + topLeft, y: rect.minY + topLeft),
                radius: topLeft,
                startAngle: .pi,
                endAngle: -.pi / 2.0,
                clockwise: true
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        path.close()
        return path.cgPath
    }

    private static func smootherstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x <= edge0 ? 0.0 : 1.0 }
        let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * t * (t * (6.0 * t - 15.0) + 10.0)
    }

    private static func easeOutPower(_ x: CGFloat, _ power: CGFloat) -> CGFloat {
        let t = max(0.0, min(1.0, x))
        return 1.0 - pow(1.0 - t, power)
    }

    private static func easeInPower(_ x: CGFloat, _ power: CGFloat) -> CGFloat {
        let t = max(0.0, min(1.0, x))
        return pow(t, power)
    }

    private static func interpolateRectByCenterAndSize(
        from: CGRect,
        to: CGRect,
        centerT: CGFloat,
        sizeT: CGFloat
    ) -> CGRect {
        let center = CGPoint(
            x: lerpUnclamped(from.midX, to.midX, max(0.0, min(1.0, centerT))),
            y: lerpUnclamped(from.midY, to.midY, max(0.0, min(1.0, centerT)))
        )
        let size = CGSize(
            width: lerpUnclamped(from.width, to.width, max(0.0, min(1.0, sizeT))),
            height: lerpUnclamped(from.height, to.height, max(0.0, min(1.0, sizeT)))
        )
        return CGRect(
            x: center.x - size.width * 0.5,
            y: center.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * max(0.0, min(1.0, t))
    }

    private static func lerpUnclamped(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private static func resolvedOvershootLimit(_ amount: CGFloat) -> CGFloat {
        let reducedMotionScale: CGFloat = UIAccessibility.isReduceMotionEnabled ? 0.25 : 1.0
        return max(0.0, min(0.045, amount)) * reducedMotionScale
    }

    private func cancelRunningAnimators() {
        if progressAnimator != nil {
            sampleProgress()
        }
        progressAnimator?.stopAnimation(true)
        progressAnimator = nil
        progressCompletion = nil
        stopProgressDisplayLink()
        shadowView.layer.removeAnimation(forKey: "modalSourceMorphShadowOpacity")
        shadowView.layer.removeAnimation(forKey: "modalSourceMorphShadowRadius")
        surfaceView.layer.removeAnimation(forKey: "modalSourceMorphSurfaceOverscale")
    }
}
