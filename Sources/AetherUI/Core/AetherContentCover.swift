import UIKit
import AssociatedObject

public struct AetherParticleContentCoverConfiguration {
    public var blurRadius: CGFloat
    public var particleColor: UIColor

    public init(
        blurRadius: CGFloat = 0.0,
        particleColor: UIColor = .white
    ) {
        self.blurRadius = blurRadius
        self.particleColor = particleColor
    }
}

public struct AetherInvisibleInkConfiguration {
    public var particleColor: UIColor

    public init(particleColor: UIColor = .label) {
        self.particleColor = particleColor
    }
}

private enum AetherParticleCoverDefaults {
    static let contentDensity: Float = 0.115
    static let textDensity: Float = 0.32
    static let contentParticleScale: CGFloat = 0.22
    static let textParticleScale: CGFloat = 0.34
    static let contentParticleAlpha: CGFloat = 0.58
    static let textParticleAlpha: CGFloat = 0.92
}

private func createAetherEmitterBehavior(type: String) -> NSObject? {
    let selector = NSSelectorFromString(["behaviorWith", "Type:"].joined(separator: ""))
    guard let behaviorClass = NSClassFromString(["CA", "Emitter", "Behavior"].joined()) as? NSObject.Type,
          let behaviorWithType = behaviorClass.method(for: selector) else {
        return nil
    }

    let castedBehaviorWithType = unsafeBitCast(
        behaviorWithType,
        to: (@convention(c) (Any?, Selector, Any?) -> NSObject).self
    )
    return castedBehaviorWithType(behaviorClass, selector, type)
}

private final class AetherEmitterView: UIView {
    var particleColor: UIColor = .label {
        didSet {
            updateEmitterCell()
        }
    }

    var particleDensity: Float = AetherParticleCoverDefaults.textDensity {
        didSet {
            updateBirthRate()
        }
    }

    var maximumBirthRate: Float = 100000.0 {
        didSet {
            updateBirthRate()
        }
    }

    var particleLifetime: Float = 1.0 {
        didSet {
            updateEmitterCell()
        }
    }

    var particleScale: CGFloat = 0.5 {
        didSet {
            updateEmitterCell()
        }
    }

    var particleAlpha: CGFloat = 1.0 {
        didSet {
            updateEmitterCell()
        }
    }

    var particleVelocityRange: CGFloat = 20.0 {
        didSet {
            updateEmitterCell()
        }
    }

    var coverRects: [CGRect] = [] {
        didSet {
            updateEmitterRects()
            updateBirthRate()
        }
    }

    private(set) var isEmitting: Bool = true

    var emitterLayer: CAEmitterLayer {
        layer as! CAEmitterLayer
    }

    override class var layerClass: AnyClass {
        CAEmitterLayer.self
    }

    private let emitterCell = CAEmitterCell()
    private var isRevealing = false
    private var hasFingerAttractor = false
    private var revealCleanupWorkItem: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitterLayer.emitterPosition = .zero
        emitterLayer.emitterSize = CGSize(width: 1.0, height: 1.0)
        updateEmitterRects()
        updateFingerAttractorGeometry()
        updateBirthRate()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateEmitterCell()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        emitterLayer.birthRate = window == nil || !isEmitting ? 0.0 : 1.0
    }

    func setEmitting(_ emitting: Bool) {
        if emitting, isRevealing {
            isRevealing = false
            setFingerAttractorEnabled(false)
            emitterCell.velocityRange = particleVelocityRange
            updateBirthRate()
        }
        isEmitting = emitting
        emitterLayer.birthRate = emitting && window != nil ? 1.0 : 0.0
    }

    func beginReveal(at point: CGPoint, duration: TimeInterval) {
        guard !isRevealing else { return }
        isRevealing = true
        enableFingerAttractor(at: point)

        let birthRate = emitterCell.birthRate
        let velocityRange = emitterCell.velocityRange
        emitterCell.birthRate = 0.0
        emitterCell.velocityRange = max(velocityRange, 64.0)

        let birthAnimation = CABasicAnimation(keyPath: "emitterCells.dustCell.birthRate")
        birthAnimation.fromValue = birthRate
        birthAnimation.toValue = 0.0
        birthAnimation.duration = max(0.1, duration * 0.65)
        birthAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        birthAnimation.isRemovedOnCompletion = true
        birthAnimation.aetherPreferHighFrameRate()
        emitterLayer.add(birthAnimation, forKey: "aether.birthRate")

        let velocityAnimation = CABasicAnimation(keyPath: "emitterCells.dustCell.velocityRange")
        velocityAnimation.fromValue = velocityRange
        velocityAnimation.toValue = emitterCell.velocityRange
        velocityAnimation.duration = max(0.1, duration * 0.4)
        velocityAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        velocityAnimation.isRemovedOnCompletion = true
        velocityAnimation.aetherPreferHighFrameRate()
        emitterLayer.add(velocityAnimation, forKey: "aether.velocityRange")

        revealCleanupWorkItem?.cancel()
        let cleanupWorkItem = DispatchWorkItem { [weak self] in
            self?.setFingerAttractorEnabled(false)
        }
        revealCleanupWorkItem = cleanupWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.0, 0.8 * UIView.animationDurationFactor()), execute: cleanupWorkItem)
    }

    private func commonInit() {
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false

        emitterLayer.masksToBounds = true
        emitterLayer.allowsGroupOpacity = true
        emitterLayer.lifetime = 1.0
        emitterLayer.emitterPosition = .zero
        emitterLayer.emitterSize = CGSize(width: 1.0, height: 1.0)
        emitterLayer.emitterShape = CAEmitterLayerEmitterShape(rawValue: "rectangles")
        emitterLayer.seed = arc4random()
        emitterLayer.emitterCells = [emitterCell]

        installEmitterBehaviors()
        updateEmitterCell()
    }

    private func updateEmitterCell() {
        emitterCell.name = "dustCell"
        emitterCell.contents = AetherParticleCoverImages.speckle?.cgImage
        emitterCell.contentsScale = UIScreen.main.scale
        emitterCell.color = particleColor.resolvedColor(with: traitCollection).withAlphaComponent(particleAlpha).cgColor
        emitterCell.emissionRange = .pi * 2.0
        emitterCell.lifetime = particleLifetime
        emitterCell.scale = particleScale
        emitterCell.velocityRange = particleVelocityRange
        emitterCell.alphaRange = 1.0
        emitterCell.setValue("point", forKey: "particleType")
        emitterCell.setValue(3.0, forKey: "mass")
        emitterCell.setValue(2.0, forKey: "massRange")
        updateBirthRate()
    }

    private func updateBirthRate() {
        guard !isRevealing else { return }
        let area = coverRects.isEmpty ? bounds.width * bounds.height : coverRects.reduce(CGFloat(0.0)) { result, rect in
            result + max(0.0, rect.width) * max(0.0, rect.height)
        }
        emitterCell.birthRate = min(maximumBirthRate, max(0.0, Float(area) * particleDensity))
    }

    private func updateEmitterRects() {
        let rects = coverRects.isEmpty ? [bounds] : coverRects
        emitterLayer.setValue(rects, forKey: "emitterRects")
    }

    private func installEmitterBehaviors() {
        guard let fingerAttractor = createAetherEmitterBehavior(type: "simpleAttractor"),
              let alphaBehavior = createAetherEmitterBehavior(type: "valueOverLife") else {
            return
        }

        fingerAttractor.setValue("fingerAttractor", forKey: "name")

        alphaBehavior.setValue("color.alpha", forKey: "keyPath")
        alphaBehavior.setValue([0.0, 0.0, 1.0, 0.0, -1.0], forKey: "values")
        alphaBehavior.setValue(true, forKey: "additive")

        emitterLayer.setValue([fingerAttractor, alphaBehavior], forKey: "emitterBehaviors")
        emitterLayer.setValue(4.0, forKeyPath: "emitterBehaviors.fingerAttractor.stiffness")
        emitterLayer.setValue(false, forKeyPath: "emitterBehaviors.fingerAttractor.enabled")
        hasFingerAttractor = true
    }

    private func enableFingerAttractor(at point: CGPoint) {
        guard hasFingerAttractor else { return }
        updateFingerAttractorGeometry()
        emitterLayer.setValue(point, forKeyPath: "emitterBehaviors.fingerAttractor.position")
        setFingerAttractorEnabled(true)
    }

    private func setFingerAttractorEnabled(_ enabled: Bool) {
        guard hasFingerAttractor else { return }
        emitterLayer.setValue(enabled, forKeyPath: "emitterBehaviors.fingerAttractor.enabled")
    }

    private func updateFingerAttractorGeometry() {
        guard hasFingerAttractor else { return }
        let radius = max(bounds.width, bounds.height)
        emitterLayer.setValue(radius, forKeyPath: "emitterBehaviors.fingerAttractor.radius")
        emitterLayer.setValue(radius * -0.5, forKeyPath: "emitterBehaviors.fingerAttractor.falloff")
    }
}

open class AetherParticleContentCoverView: UIView {
    public var configuration: AetherParticleContentCoverConfiguration {
        didSet {
            applyConfiguration()
        }
    }

    public var onReveal: (() -> Void)?
    public private(set) var isRevealed: Bool = false

    weak var ownerView: UIView?

    private let blurView = VisualEffectView()
    private let dimView = UIView()
    private let emitterView = AetherEmitterView()
    private var revealMaskController: AetherRevealMaskController?

    public init(configuration: AetherParticleContentCoverConfiguration = AetherParticleContentCoverConfiguration()) {
        self.configuration = configuration
        super.init(frame: .zero)
        commonInit()
    }

    public override init(frame: CGRect) {
        self.configuration = AetherParticleContentCoverConfiguration()
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        self.configuration = AetherParticleContentCoverConfiguration()
        super.init(coder: coder)
        commonInit()
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        dimView.frame = bounds
        emitterView.frame = bounds
    }

    public func reveal(animated: Bool = true) {
        reveal(at: CGPoint(x: bounds.midX, y: bounds.midY), animated: animated)
    }

    public func reveal(at point: CGPoint, animated: Bool = true) {
        guard !isRevealed else { return }
        isRevealed = true
        onReveal?()

        guard animated else {
            if let ownerView {
                ownerView.aetherStoredCoverView = nil
            }
            removeFromSuperview()
            return
        }

        let factor = UIView.animationDurationFactor()
        let duration = 0.55 * factor
        emitterView.beginReveal(at: point, duration: duration)

        let controller = AetherRevealMaskController()
        revealMaskController = controller
        controller.animateEmitterMask(on: self, at: point, duration: duration) { [weak self] in
            guard let self else { return }
            if let ownerView = self.ownerView {
                ownerView.aetherStoredCoverView = nil
            }
            self.removeFromSuperview()
            self.revealMaskController = nil
        }
    }

    private func commonInit() {
        isOpaque = false
        clipsToBounds = true
        isUserInteractionEnabled = true

        blurView.isUserInteractionEnabled = false
        dimView.isUserInteractionEnabled = false
        addSubview(blurView)
        addSubview(dimView)
        addSubview(emitterView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)

        applyConfiguration()
    }

    private func applyConfiguration() {
        let blurRadius = max(0.0, configuration.blurRadius)
        blurView.style = .customBlur
        blurView.blurRadius = blurRadius
        blurView.colorTint = nil
        blurView.colorTintAlpha = 0.0
        blurView.saturation = 1.0
        blurView.alpha = blurRadius > 0.0 ? 1.0 : 0.0
        blurView.isHidden = blurRadius <= 0.0
        dimView.backgroundColor = UIColor.black.withAlphaComponent(blurRadius > 0.0 ? 0.08 : 0.0)
        emitterView.particleColor = configuration.particleColor
        emitterView.particleDensity = AetherParticleCoverDefaults.contentDensity
        emitterView.particleScale = AetherParticleCoverDefaults.contentParticleScale
        emitterView.particleAlpha = AetherParticleCoverDefaults.contentParticleAlpha
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        reveal(at: recognizer.location(in: self), animated: true)
    }
}

open class AetherInvisibleInkView: UIView {
    public var configuration: AetherInvisibleInkConfiguration {
        didSet {
            inkColor = configuration.particleColor
            emitterView.particleColor = inkColor
            emitterView.particleDensity = AetherParticleCoverDefaults.textDensity
            emitterView.particleScale = AetherParticleCoverDefaults.textParticleScale
            emitterView.particleAlpha = AetherParticleCoverDefaults.textParticleAlpha
        }
    }

    public var onReveal: (() -> Void)?
    public private(set) var isRevealed: Bool = false

    weak var ownerView: UIView?

    private var inkColor: UIColor
    private var textColor: UIColor
    private var lineRects: [CGRect] = []
    private var wordRects: [CGRect] = []
    private let emitterView = AetherEmitterView()
    private var textRevealMaskController: AetherRevealMaskController?
    private var emitterRevealMaskController: AetherRevealMaskController?

    public init(configuration: AetherInvisibleInkConfiguration = AetherInvisibleInkConfiguration()) {
        self.configuration = configuration
        self.inkColor = configuration.particleColor
        self.textColor = configuration.particleColor
        super.init(frame: .zero)
        commonInit()
    }

    public override init(frame: CGRect) {
        self.configuration = AetherInvisibleInkConfiguration()
        self.inkColor = configuration.particleColor
        self.textColor = configuration.particleColor
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        self.configuration = AetherInvisibleInkConfiguration()
        self.inkColor = configuration.particleColor
        self.textColor = configuration.particleColor
        super.init(coder: coder)
        commonInit()
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        emitterView.frame = bounds
    }

    open override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isRevealed else {
            return false
        }

        let hitRects = lineRects.isEmpty ? [bounds] : lineRects
        for rect in hitRects where rect.insetBy(dx: -4.0, dy: -6.0).contains(point) {
            return true
        }
        return false
    }

    public func update(
        size: CGSize,
        color: UIColor,
        textColor: UIColor,
        rects: [CGRect],
        wordRects: [CGRect]
    ) {
        bounds = CGRect(origin: .zero, size: size)
        self.inkColor = color
        self.textColor = textColor
        self.lineRects = rects
        self.wordRects = wordRects

        let coverRects = wordRects.isEmpty ? (rects.isEmpty ? [CGRect(origin: .zero, size: size)] : rects) : wordRects
        emitterView.coverRects = coverRects
        emitterView.particleColor = color
        emitterView.particleDensity = AetherParticleCoverDefaults.textDensity
        emitterView.particleScale = AetherParticleCoverDefaults.textParticleScale
        emitterView.particleAlpha = AetherParticleCoverDefaults.textParticleAlpha
    }

    public func update(for label: UILabel) {
        let coverRects = AetherTextCoverRects.make(for: label)
        update(
            size: label.bounds.size,
            color: configuration.particleColor,
            textColor: label.textColor,
            rects: coverRects.lineRects,
            wordRects: coverRects.wordRects
        )
    }

    public func reveal(animated: Bool = true) {
        reveal(at: CGPoint(x: bounds.midX, y: bounds.midY), animated: animated)
    }

    public func reveal(at point: CGPoint, animated: Bool = true) {
        guard !isRevealed else { return }
        isRevealed = true
        onReveal?()

        guard animated else {
            ownerView?.aetherRestoreInvisibleInkOwnerAlpha()
            if let ownerView {
                ownerView.aetherStoredInvisibleInk = nil
            }
            removeFromSuperview()
            return
        }

        let factor = UIView.animationDurationFactor()
        let duration = 0.55 * factor
        emitterView.beginReveal(at: point, duration: duration)

        let revealText = { [weak self] in
            guard let self else { return }
            if let ownerView = self.ownerView, ownerView.aetherStoredInvisibleInkOwnerAlpha != nil {
                ownerView.aetherRestoreInvisibleInkOwnerAlpha()
                let textController = AetherRevealMaskController()
                self.textRevealMaskController = textController
                textController.animateTextMask(on: ownerView, at: point, duration: duration) { [weak self] in
                    self?.textRevealMaskController = nil
                }
            }

            let emitterController = AetherRevealMaskController()
            self.emitterRevealMaskController = emitterController
            emitterController.animateEmitterMask(on: self.emitterView, at: point, duration: duration) { [weak self] in
                guard let self else { return }
                if let ownerView = self.ownerView {
                    ownerView.aetherStoredInvisibleInk = nil
                }
                self.removeFromSuperview()
                self.emitterRevealMaskController = nil
            }
        }

        let revealDelay = max(0.0, 0.1 * factor)
        if revealDelay > 0.0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay, execute: revealText)
        } else {
            revealText()
        }
    }

    private func commonInit() {
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = true
        clipsToBounds = false

        emitterView.isUserInteractionEnabled = false
        addSubview(emitterView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        reveal(at: recognizer.location(in: self), animated: true)
    }
}

private extension UIView {
    @AssociatedObject(.retain(.nonatomic))
    var aetherStoredCoverView: AetherParticleContentCoverView?

    @AssociatedObject(.retain(.nonatomic))
    var aetherStoredInvisibleInk: AetherInvisibleInkView?

    @AssociatedObject(.retain(.nonatomic))
    var aetherStoredInvisibleInkOwnerAlpha: NSNumber?

    func aetherStoreInvisibleInkOwnerAlphaIfNeeded() {
        if aetherStoredInvisibleInkOwnerAlpha == nil {
            aetherStoredInvisibleInkOwnerAlpha = NSNumber(value: Double(alpha))
        }
        alpha = 0.0
    }

    func aetherRestoreInvisibleInkOwnerAlpha() {
        guard let storedAlpha = aetherStoredInvisibleInkOwnerAlpha else {
            return
        }
        aetherStoredInvisibleInkOwnerAlpha = nil
        alpha = CGFloat(storedAlpha.doubleValue)
    }
}

public extension UIView {
    var aetherCoverView: AetherParticleContentCoverView? {
        aetherStoredCoverView
    }

    var aetherInvisibleInk: AetherInvisibleInkView? {
        aetherStoredInvisibleInk
    }

    @discardableResult
    func setParticleContentCovered(
        _ covered: Bool,
        configuration: AetherParticleContentCoverConfiguration = AetherParticleContentCoverConfiguration(),
        animated: Bool = false
    ) -> AetherParticleContentCoverView? {
        guard covered else {
            removeParticleContentCover(animated: animated)
            return nil
        }

        let coverView: AetherParticleContentCoverView
        if let currentCoverView = aetherStoredCoverView {
            coverView = currentCoverView
            coverView.configuration = configuration
        } else {
            coverView = AetherParticleContentCoverView(configuration: configuration)
            coverView.ownerView = self
            aetherStoredCoverView = coverView
            addSubview(coverView)
        }

        coverView.frame = bounds
        coverView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coverView.isHidden = false
        bringSubviewToFront(coverView)

        if animated {
            coverView.alpha = 0.0
            UIView.animate(withDuration: 0.18) {
                coverView.alpha = 1.0
            }
        } else {
            coverView.alpha = 1.0
        }

        return coverView
    }

    func removeParticleContentCover(animated: Bool = false) {
        guard let coverView = aetherStoredCoverView else { return }
        guard !animated else {
            coverView.reveal(animated: true)
            return
        }

        aetherStoredCoverView = nil
        coverView.removeFromSuperview()
    }

    @discardableResult
    func setInvisibleInk(
        _ covered: Bool,
        configuration: AetherInvisibleInkConfiguration = AetherInvisibleInkConfiguration(),
        animated: Bool = false
    ) -> AetherInvisibleInkView? {
        guard covered else {
            removeInk(animated: animated)
            return nil
        }

        let inkView: AetherInvisibleInkView
        if let currentInkView = aetherStoredInvisibleInk {
            inkView = currentInkView
            inkView.configuration = configuration
        } else {
            inkView = AetherInvisibleInkView(configuration: configuration)
            inkView.ownerView = self
            aetherStoredInvisibleInk = inkView
            addSubview(inkView)
        }

        inkView.isHidden = false

        if let label = self as? UILabel {
            inkView.update(for: label)
        } else if let textNode = self as? TextNode {
            let coverRects = textNode.textCoverRects()
            let color = configuration.particleColor
            let textColor: UIColor
            if let attributedText = textNode.attributedText, attributedText.length > 0 {
                textColor = attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor ?? tintColor
            } else {
                textColor = tintColor
            }
            inkView.update(
                size: bounds.size,
                color: color,
                textColor: textColor,
                rects: coverRects.lineRects,
                wordRects: coverRects.wordRects
            )
        } else {
            let coverBounds = CGRect(origin: .zero, size: bounds.size)
            inkView.update(
                size: bounds.size,
                color: configuration.particleColor,
                textColor: tintColor,
                rects: [coverBounds],
                wordRects: [coverBounds]
            )
        }

        if self is UILabel || self is TextNode, let hostView = superview {
            if inkView.superview !== hostView {
                inkView.removeFromSuperview()
                hostView.addSubview(inkView)
            }
            inkView.frame = convert(bounds, to: hostView)
            inkView.autoresizingMask = []
            hostView.bringSubviewToFront(inkView)
            aetherStoreInvisibleInkOwnerAlphaIfNeeded()
        } else {
            if inkView.superview !== self {
                inkView.removeFromSuperview()
                addSubview(inkView)
            }
            inkView.frame = bounds
            inkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            bringSubviewToFront(inkView)
        }

        if animated {
            inkView.alpha = 0.0
            UIView.animate(withDuration: 0.18) {
                inkView.alpha = 1.0
            }
        } else {
            inkView.alpha = 1.0
        }

        return inkView
    }

    func removeInk(animated: Bool = false) {
        guard let inkView = aetherStoredInvisibleInk else { return }
        guard !animated else {
            inkView.reveal(animated: true)
            return
        }

        aetherStoredInvisibleInk = nil
        aetherRestoreInvisibleInkOwnerAlpha()
        inkView.removeFromSuperview()
    }
}

private enum AetherParticleCoverImages {
    static let speckle: UIImage? = {
        generateImage(CGSize(width: 4.0, height: 4.0), contextGenerator: { size, context in
            let bounds = CGRect(origin: .zero, size: size)
            context.clear(bounds)

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors: [CGColor] = [
                UIColor.white.withAlphaComponent(1.0).cgColor,
                UIColor.white.withAlphaComponent(0.65).cgColor,
                UIColor.white.withAlphaComponent(0.0).cgColor
            ]
            var locations: [CGFloat] = [0.0, 0.55, 1.0]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations) {
                context.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: bounds.midX, y: bounds.midY),
                    startRadius: 0.0,
                    endCenter: CGPoint(x: bounds.midX, y: bounds.midY),
                    endRadius: 2.0,
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
        }, scale: 2.0)
    }()
}

private final class AetherRevealMaskController {
    private let maskView = UIView()
    private let spotView = UIImageView()
    private let fillView = UIView()

    func animateTextMask(
        on targetView: UIView,
        at point: CGPoint,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        animate(
            on: targetView,
            at: point,
            duration: duration,
            inverse: false,
            includesFillFade: false,
            fadesSpotIn: true,
            completion: completion
        )
    }

    func animateEmitterMask(
        on targetView: UIView,
        at point: CGPoint,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        animate(
            on: targetView,
            at: point,
            duration: duration,
            inverse: true,
            includesFillFade: true,
            fadesSpotIn: false,
            completion: completion
        )
    }

    private func animate(
        on targetView: UIView,
        at point: CGPoint,
        duration: TimeInterval,
        inverse: Bool,
        includesFillFade: Bool,
        fadesSpotIn: Bool,
        completion: @escaping () -> Void
    ) {
        let size = targetView.bounds.size
        guard size.width > 0.0, size.height > 0.0 else {
            completion()
            return
        }

        let clippedPoint = CGPoint(
            x: min(max(0.0, point.x), size.width),
            y: min(max(0.0, point.y), size.height)
        )
        let maskImage = generateAetherRevealMaskImage(size: size, position: clippedPoint, inverse: inverse)

        maskView.frame = CGRect(origin: .zero, size: size)
        maskView.backgroundColor = .clear
        maskView.clipsToBounds = false

        spotView.image = maskImage
        spotView.contentMode = .scaleToFill
        spotView.alpha = fadesSpotIn ? 0.0 : 1.0
        spotView.bounds = CGRect(origin: .zero, size: CGSize(width: size.width * 3.0, height: size.height * 3.0))
        spotView.layer.anchorPoint = CGPoint(
            x: size.width > 0.0 ? clippedPoint.x / size.width : 0.5,
            y: size.height > 0.0 ? clippedPoint.y / size.height : 0.5
        )
        spotView.layer.position = clippedPoint
        spotView.transform = CGAffineTransform(scaleX: 0.3333, y: 0.3333)

        fillView.backgroundColor = .white
        fillView.frame = maskView.bounds
        fillView.alpha = 1.0

        maskView.subviews.forEach { $0.removeFromSuperview() }
        maskView.addSubview(spotView)
        if includesFillFade {
            maskView.addSubview(fillView)
        }

        targetView.mask = maskView

        let xFactor = (clippedPoint.x / size.width - 0.5) * 2.0
        let yFactor = (clippedPoint.y / size.height - 0.5) * 2.0
        let maxFactor = max(abs(xFactor), abs(yFactor))
        var scaleAddition = maxFactor * 4.0
        var durationAddition = -Double(maxFactor) * 0.2
        if size.height > 0.0, size.width / size.height < 0.7 {
            scaleAddition *= 5.0
            durationAddition *= 2.0
        }

        if includesFillFade {
            UIView.animate(
                withDuration: min(0.15, duration * 0.35),
                delay: 0.0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveLinear],
                animations: {
                    self.fillView.alpha = 0.0
                }
            )
        }

        if fadesSpotIn {
            UIView.animate(
                withDuration: min(0.15, duration * 0.35),
                delay: 0.0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveLinear],
                animations: {
                    self.spotView.alpha = 1.0
                }
            )
        }

        UIView.animate(
            withDuration: max(0.1, duration + durationAddition),
            delay: 0.0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
            animations: {
                self.spotView.transform = CGAffineTransform(scaleX: 10.5 + scaleAddition, y: 10.5 + scaleAddition)
            },
            completion: { _ in
                targetView.mask = nil
                completion()
            }
        )
    }
}

private func generateAetherRevealMaskImage(size originalSize: CGSize, position originalPosition: CGPoint, inverse: Bool) -> UIImage? {
    var size = originalSize
    var position = originalPosition
    var scale: CGFloat = 1.0
    let maxSide = max(size.width, size.height)
    if maxSide > 640.0 {
        scale = 640.0 / maxSide
        size = CGSize(width: size.width * scale, height: size.height * scale)
        position = CGPoint(x: position.x * scale, y: position.y * scale)
    }

    return generateImage(size, contextGenerator: { size, context in
        let bounds = CGRect(origin: .zero, size: size)
        context.clear(bounds)

        let startAlpha: CGFloat = inverse ? 0.0 : 1.0
        let endAlpha: CGFloat = inverse ? 1.0 : 0.0
        var locations: [CGFloat] = [0.0, 0.7, 0.95, 1.0]
        let colors: [CGColor] = [
            UIColor.white.withAlphaComponent(startAlpha).cgColor,
            UIColor.white.withAlphaComponent(startAlpha).cgColor,
            UIColor.white.withAlphaComponent(endAlpha).cgColor,
            UIColor.white.withAlphaComponent(endAlpha).cgColor
        ]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations) else {
            return
        }

        context.drawRadialGradient(
            gradient,
            startCenter: position,
            startRadius: 0.0,
            endCenter: position,
            endRadius: min(10.0, min(size.width, size.height) * 0.4) * scale,
            options: .drawsAfterEndLocation
        )
    })
}
