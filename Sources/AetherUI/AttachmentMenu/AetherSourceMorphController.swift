import UIKit

public final class AetherSourceMorphController: NSObject {
    public struct Configuration {
        public var targetCornerRadius: CGFloat
        public var horizontalMargin: CGFloat
        public var verticalMargin: CGFloat
        public var sourceOverlap: CGFloat
        public var openDuration: TimeInterval
        public var closeDuration: TimeInterval

        public init(
            targetCornerRadius: CGFloat = 38.0,
            horizontalMargin: CGFloat = 24.0,
            verticalMargin: CGFloat = 18.0,
            sourceOverlap: CGFloat = 42.0,
            openDuration: TimeInterval = 0.5,
            closeDuration: TimeInterval = 0.5
        ) {
            self.targetCornerRadius = targetCornerRadius
            self.horizontalMargin = horizontalMargin
            self.verticalMargin = verticalMargin
            self.sourceOverlap = sourceOverlap
            self.openDuration = openDuration
            self.closeDuration = closeDuration
        }
    }

    public var onDismiss: (() -> Void)?

    private let contentView: UIView
    private let targetSize: CGSize
    private let configuration: Configuration

    private weak var sourceView: UIView?
    private var overlayView: SourceMorphOverlayView?
    private var surfaceView: SourceMorphSurfaceView?
    private var sourceOriginalAlpha: CGFloat = 1.0
    private var sourceOriginalIsHidden = false
    private var sourceOriginalInteractionEnabled = true
    private var isPresented = false
    private var selfRetainer: AetherSourceMorphController?

    public init(
        contentView: UIView,
        targetSize: CGSize,
        configuration: Configuration = Configuration()
    ) {
        self.contentView = contentView
        self.targetSize = targetSize
        self.configuration = configuration
        super.init()
    }

    public func present(
        from sourceView: UIView,
        in hostView: UIView? = nil,
        targetFrame explicitTargetFrame: CGRect? = nil
    ) {
        guard !isPresented else { return }
        guard let host = hostView ?? sourceView.window else { return }

        host.layoutIfNeeded()
        sourceView.layoutIfNeeded()

        let overlay = SourceMorphOverlayView(frame: host.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(overlay)

        let sourceFrame = sourceView.convert(sourceView.bounds, to: overlay)
        guard sourceFrame.width > 0, sourceFrame.height > 0 else {
            overlay.removeFromSuperview()
            return
        }

        let targetFrame = explicitTargetFrame ?? Self.defaultTargetFrame(
            for: targetSize,
            sourceFrame: sourceFrame,
            bounds: overlay.bounds,
            configuration: configuration
        )
        let sourceCornerRadius = Self.resolvedCornerRadius(for: sourceView)
        let sourceSnapshot = Self.makeProxyView(from: sourceView)

        let surface = SourceMorphSurfaceView(
            sourceFrame: sourceFrame,
            targetFrame: targetFrame,
            sourceCornerRadius: sourceCornerRadius,
            targetCornerRadius: configuration.targetCornerRadius,
            contentView: contentView,
            sourceSnapshot: sourceSnapshot
        )
        surface.frame = overlay.bounds
        surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.addSubview(surface)
        overlay.surfaceView = surface
        overlay.dismissHandler = { [weak self] in
            self?.dismiss()
        }

        self.sourceView = sourceView
        self.overlayView = overlay
        self.surfaceView = surface
        self.sourceOriginalAlpha = sourceView.alpha
        self.sourceOriginalIsHidden = sourceView.isHidden
        self.sourceOriginalInteractionEnabled = sourceView.isUserInteractionEnabled
        self.isPresented = true
        self.selfRetainer = self

        sourceView.alpha = 0.0
        sourceView.isHidden = true
        sourceView.isUserInteractionEnabled = false

        surface.open(duration: configuration.openDuration)
    }

    public func dismiss(animated: Bool = true) {
        guard isPresented else { return }
        guard let surfaceView else {
            finishDismissal()
            return
        }

        surfaceView.close(duration: animated ? configuration.closeDuration : 0.001) { [weak self] in
            self?.finishDismissal()
        }
    }

    private func finishDismissal() {
        overlayView?.removeFromSuperview()

        if let sourceView {
            sourceView.isHidden = sourceOriginalIsHidden
            sourceView.alpha = sourceOriginalAlpha
            sourceView.isUserInteractionEnabled = sourceOriginalInteractionEnabled
        }

        surfaceView = nil
        overlayView = nil
        sourceView = nil
        isPresented = false
        onDismiss?()
        selfRetainer = nil
    }

    private static func defaultTargetFrame(
        for targetSize: CGSize,
        sourceFrame: CGRect,
        bounds: CGRect,
        configuration: Configuration
    ) -> CGRect {
        let safeBounds = bounds.insetBy(
            dx: configuration.horizontalMargin,
            dy: configuration.verticalMargin
        )
        let width = min(targetSize.width, safeBounds.width)
        let height = min(targetSize.height, safeBounds.height)
        var x = sourceFrame.minX - 8.0
        var y = sourceFrame.maxY - height + configuration.sourceOverlap

        x = min(max(x, safeBounds.minX), safeBounds.maxX - width)
        y = min(max(y, safeBounds.minY), safeBounds.maxY - height)

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func resolvedCornerRadius(for view: UIView) -> CGFloat {
        let layer = view.layer.presentation() ?? view.layer
        let maxRadius = min(view.bounds.width, view.bounds.height) * 0.5
        let radius = layer.cornerRadius > 0 ? layer.cornerRadius : maxRadius
        return min(max(0, radius), maxRadius)
    }

    private static func makeProxyView(from view: UIView) -> UIView {
        if let snapshot = view.snapshotView(afterScreenUpdates: false) {
            snapshot.frame = CGRect(origin: .zero, size: view.bounds.size)
            return snapshot
        }

        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.frame = CGRect(origin: .zero, size: view.bounds.size)
        return imageView
    }
}

public final class AetherAttachmentMenuController: NSObject {
    public struct Item {
        public let title: String
        public let icon: UIImage?
        public let action: (() -> Void)?

        public init(title: String, icon: UIImage? = nil, action: (() -> Void)? = nil) {
            self.title = title
            self.icon = icon
            self.action = action
        }
    }

    public var onDismiss: (() -> Void)?

    private let items: [Item]
    private let configuration: AetherSourceMorphController.Configuration
    private var morphController: AetherSourceMorphController?
    private var selfRetainer: AetherAttachmentMenuController?

    public init(
        items: [Item],
        configuration: AetherSourceMorphController.Configuration = AetherSourceMorphController.Configuration()
    ) {
        self.items = items
        self.configuration = configuration
        super.init()
    }

    public func present(from sourceView: UIView, in hostView: UIView? = nil) {
        let contentView = AttachmentMenuContentView(items: items)
        contentView.itemSelected = { [weak self] index in
            guard let self else { return }
            self.items[index].action?()
            self.dismiss()
        }

        let controller = AetherSourceMorphController(
            contentView: contentView,
            targetSize: contentView.intrinsicMenuSize,
            configuration: configuration
        )
        controller.onDismiss = { [weak self, weak controller] in
            guard let self else { return }
            if let controller, self.morphController === controller {
                self.morphController = nil
            }
            self.onDismiss?()
            self.selfRetainer = nil
        }
        morphController = controller
        selfRetainer = self
        controller.present(from: sourceView, in: hostView)
    }

    public func dismiss() {
        morphController?.dismiss()
    }
}

private final class SourceMorphOverlayView: UIView, UIGestureRecognizerDelegate {
    weak var surfaceView: SourceMorphSurfaceView?
    var dismissHandler: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let surfaceView else { return true }
        let point = touch.location(in: self)
        return !surfaceView.hitFrame.insetBy(dx: -18, dy: -18).contains(point)
    }

    @objc
    private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        dismissHandler?()
    }
}

private final class SourceMorphSurfaceView: UIView {
    private let sourceFrame: CGRect
    private let targetFrame: CGRect
    private let sourceCornerRadius: CGFloat
    private let targetCornerRadius: CGFloat

    private let shadowView = UIView()
    private let glassView: UIVisualEffectView
    private let tintView = UIView()
    private let strokeView = UIView()
    private let sourceSnapshot: UIView
    private let contentHost = UIView()

    private var surfaceFrame: CGRect
    private var progress: CGFloat = 0.0
    private var displayLink: CADisplayLink?
    private var animationStartTime: CFTimeInterval = 0.0
    private var animationDuration: TimeInterval = 0.0
    private var animationFromProgress: CGFloat = 0.0
    private var animationToProgress: CGFloat = 1.0
    private var animationCompletion: (() -> Void)?
    var hitFrame: CGRect { surfaceFrame }

    init(
        sourceFrame: CGRect,
        targetFrame: CGRect,
        sourceCornerRadius: CGFloat,
        targetCornerRadius: CGFloat,
        contentView: UIView,
        sourceSnapshot: UIView
    ) {
        self.sourceFrame = sourceFrame
        self.targetFrame = targetFrame
        self.sourceCornerRadius = sourceCornerRadius
        self.targetCornerRadius = targetCornerRadius
        self.sourceSnapshot = sourceSnapshot
        self.surfaceFrame = sourceFrame

        if #available(iOS 13.0, *) {
            self.glassView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
        } else {
            self.glassView = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
        }

        super.init(frame: .zero)

        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false
        isUserInteractionEnabled = true

        shadowView.backgroundColor = .clear
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = 0.0
        shadowView.layer.shadowRadius = 0.0
        shadowView.layer.shadowOffset = .zero
        addSubview(shadowView)

        glassView.clipsToBounds = true
        glassView.layer.cornerCurve = .continuous
        addSubview(glassView)

        tintView.backgroundColor = UIColor.white.withAlphaComponent(0.62)
        tintView.isUserInteractionEnabled = false
        glassView.contentView.addSubview(tintView)

        strokeView.backgroundColor = .clear
        strokeView.isUserInteractionEnabled = false
        strokeView.layer.borderColor = UIColor.black.withAlphaComponent(0.12).cgColor
        strokeView.layer.borderWidth = 0.75
        strokeView.layer.cornerCurve = .continuous
        glassView.contentView.addSubview(strokeView)

        contentHost.backgroundColor = .clear
        contentHost.alpha = 0.0
        contentHost.transform = CGAffineTransform(translationX: 0, y: 10)
        glassView.contentView.addSubview(contentHost)
        contentView.frame = contentHost.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentHost.addSubview(contentView)

        sourceSnapshot.isUserInteractionEnabled = false
        glassView.contentView.addSubview(sourceSnapshot)

        apply(progress: 0.0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    func open(duration: TimeInterval) {
        startAnimation(from: 0.0, to: 1.0, duration: duration, completion: nil)
    }

    func close(duration: TimeInterval, completion: @escaping () -> Void) {
        startAnimation(from: progress, to: 0.0, duration: duration, completion: completion)
    }

    private func startAnimation(
        from fromProgress: CGFloat,
        to toProgress: CGFloat,
        duration: TimeInterval,
        completion: (() -> Void)?
    ) {
        stopAnimation()

        animationFromProgress = max(0.0, min(1.0, fromProgress))
        animationToProgress = max(0.0, min(1.0, toProgress))
        animationDuration = max(0.001, duration)
        animationStartTime = CACurrentMediaTime()
        animationCompletion = completion
        progress = animationFromProgress

        layer.removeAllAnimations()
        shadowView.layer.removeAllAnimations()
        glassView.layer.removeAllAnimations()
        tintView.layer.removeAllAnimations()
        strokeView.layer.removeAllAnimations()
        sourceSnapshot.layer.removeAllAnimations()
        contentHost.layer.removeAllAnimations()

        apply(progress: progress)
        startDisplayLink()
    }

    private func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func startDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(animationTick(_:)))
        let maximumFramesPerSecond = max(60, UIScreen.main.maximumFramesPerSecond)
        if #available(iOS 15.0, *) {
            let preferred = Float(min(120, maximumFramesPerSecond))
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: min(80, preferred),
                maximum: preferred,
                preferred: preferred
            )
        } else {
            link.preferredFramesPerSecond = maximumFramesPerSecond
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc
    private func animationTick(_ link: CADisplayLink) {
        let elapsed = max(0.0, CACurrentMediaTime() - animationStartTime)
        let linear = min(1.0, CGFloat(elapsed / animationDuration))
        let opening = animationToProgress >= animationFromProgress
        let eased = opening
            ? Self.easeOutQuad(linear)
            : Self.easeInOutCubic(linear)

        progress = Self.lerp(animationFromProgress, animationToProgress, eased)
        apply(progress: progress)

        guard linear >= 1.0 else { return }
        stopAnimation()
        progress = animationToProgress
        apply(progress: progress)

        let completion = animationCompletion
        animationCompletion = nil
        completion?()
    }

    private func apply(progress rawProgress: CGFloat) {
        let t = max(0.0, min(1.0, rawProgress))
        let baseFrame = Self.lerp(sourceFrame, targetFrame, t)
        let overscale = animationToProgress > animationFromProgress
            ? 1.0 + 0.035 * sin(.pi * Self.smootherstep(0.58, 1.0, t))
            : 1.0
        let frame = Self.scaledFrame(baseFrame, scale: overscale)
        let cornerRadius = Self.lerp(sourceCornerRadius, targetCornerRadius, Self.smootherstep(0.08, 0.78, t))
        let closing = animationToProgress < animationFromProgress
        let sourceAlpha = closing
            ? 1.0 - Self.smootherstep(0.0, 0.46, t)
            : 1.0 - Self.smootherstep(0.04, 0.24, t)
        let contentAlpha = closing
            ? Self.smootherstep(0.08, 0.72, t)
            : Self.smootherstep(0.18, 0.58, t)
        let shadowAlpha = 0.09 * Self.smootherstep(0.10, 0.54, t)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        surfaceFrame = frame
        shadowView.frame = frame
        shadowView.layer.shadowPath = UIBezierPath(
            roundedRect: shadowView.bounds,
            cornerRadius: cornerRadius
        ).cgPath
        shadowView.layer.shadowOpacity = Float(shadowAlpha)
        shadowView.layer.shadowRadius = 10.0 + 16.0 * Self.smootherstep(0.0, 0.86, t)
        shadowView.layer.shadowOffset = CGSize(width: 0, height: 4.0 + 8.0 * Self.smootherstep(0.0, 1.0, t))

        glassView.frame = frame
        glassView.layer.cornerRadius = cornerRadius

        tintView.frame = glassView.bounds
        tintView.layer.cornerRadius = cornerRadius
        tintView.layer.cornerCurve = .continuous

        strokeView.frame = glassView.bounds
        strokeView.layer.cornerRadius = cornerRadius

        contentHost.frame = CGRect(
            x: targetFrame.minX - frame.minX,
            y: targetFrame.minY - frame.minY,
            width: targetFrame.width,
            height: targetFrame.height
        )
        contentHost.alpha = contentAlpha
        contentHost.transform = CGAffineTransform(translationX: 0, y: 9.0 * (1.0 - contentAlpha))
        for subview in contentHost.subviews {
            subview.frame = contentHost.bounds
        }

        sourceSnapshot.isHidden = sourceAlpha <= 0.001
        sourceSnapshot.bounds = CGRect(origin: .zero, size: sourceFrame.size)
        sourceSnapshot.center = CGPoint(
            x: sourceFrame.midX - frame.minX,
            y: sourceFrame.midY - frame.minY
        )
        sourceSnapshot.alpha = sourceAlpha
        let sourceScale = Self.lerp(0.92, 1.0, sourceAlpha)
        sourceSnapshot.transform = CGAffineTransform(scaleX: sourceScale, y: sourceScale)

        CATransaction.commit()
    }

    private static func scaledFrame(_ frame: CGRect, scale: CGFloat) -> CGRect {
        guard scale != 1.0 else { return frame }
        let width = frame.width * scale
        let height = frame.height * scale
        return CGRect(
            x: frame.midX - width * 0.5,
            y: frame.midY - height * 0.5,
            width: width,
            height: height
        )
    }

    private static func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
        from + (to - from) * t
    }

    private static func lerp(_ from: CGRect, _ to: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(
            x: lerp(from.minX, to.minX, t),
            y: lerp(from.minY, to.minY, t),
            width: lerp(from.width, to.width, t),
            height: lerp(from.height, to.height, t)
        )
    }

    private static func smootherstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge0 != edge1 else { return x >= edge1 ? 1.0 : 0.0 }
        let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
    }

    private static func easeOutQuad(_ x: CGFloat) -> CGFloat {
        let t = max(0.0, min(1.0, x))
        return 1.0 - pow(1.0 - t, 2.0)
    }

    private static func easeInOutCubic(_ x: CGFloat) -> CGFloat {
        let t = max(0.0, min(1.0, x))
        if t < 0.5 {
            return 4.0 * t * t * t
        }
        return 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5
    }
}

private final class AttachmentMenuContentView: UIView {
    static let rowHeight: CGFloat = 72.0
    static let horizontalPadding: CGFloat = 24.0
    static let verticalPadding: CGFloat = 22.0
    static let menuWidth: CGFloat = 330.0

    var itemSelected: ((Int) -> Void)?
    let intrinsicMenuSize: CGSize

    private var rows: [AttachmentMenuRowView] = []

    init(items: [AetherAttachmentMenuController.Item]) {
        self.intrinsicMenuSize = CGSize(
            width: Self.menuWidth,
            height: Self.verticalPadding * 2.0 + CGFloat(items.count) * Self.rowHeight
        )
        super.init(frame: CGRect(origin: .zero, size: intrinsicMenuSize))

        backgroundColor = .clear
        for (index, item) in items.enumerated() {
            let row = AttachmentMenuRowView(item: item)
            row.tag = index
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
            addSubview(row)
            rows.append(row)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width - Self.horizontalPadding * 2.0
        for (index, row) in rows.enumerated() {
            row.frame = CGRect(
                x: Self.horizontalPadding,
                y: Self.verticalPadding + CGFloat(index) * Self.rowHeight,
                width: width,
                height: Self.rowHeight
            )
        }
    }

    @objc
    private func rowTapped(_ row: AttachmentMenuRowView) {
        itemSelected?(row.tag)
    }
}

private final class AttachmentMenuRowView: UIControl {
    private let iconContainer = UIView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()

    init(item: AetherAttachmentMenuController.Item) {
        super.init(frame: .zero)

        backgroundColor = .clear
        layer.cornerRadius = 18.0
        layer.cornerCurve = .continuous

        iconContainer.backgroundColor = UIColor.secondarySystemFill.withAlphaComponent(0.56)
        iconContainer.isUserInteractionEnabled = false
        iconContainer.layer.cornerRadius = 24.0
        iconContainer.layer.cornerCurve = .continuous
        addSubview(iconContainer)

        imageView.image = item.icon?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = .label
        imageView.contentMode = .scaleAspectFit
        iconContainer.addSubview(imageView)

        titleLabel.text = item.title
        titleLabel.textColor = .label
        titleLabel.font = .systemFont(ofSize: 25.0, weight: .regular)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.82
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(
                withDuration: 0.12,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.backgroundColor = self.isHighlighted
                    ? UIColor.secondarySystemFill.withAlphaComponent(0.38)
                    : .clear
                self.iconContainer.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.94, y: 0.94)
                    : .identity
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let iconSide: CGFloat = 48.0
        iconContainer.frame = CGRect(
            x: 0,
            y: (bounds.height - iconSide) * 0.5,
            width: iconSide,
            height: iconSide
        )
        imageView.frame = iconContainer.bounds.insetBy(dx: 12, dy: 12)
        titleLabel.frame = CGRect(
            x: 74,
            y: 0,
            width: bounds.width - 74,
            height: bounds.height
        )
    }
}
