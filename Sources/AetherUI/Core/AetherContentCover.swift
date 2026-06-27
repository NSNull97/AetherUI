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

open class AetherParticleContentCoverView: UIView {
    public var configuration: AetherParticleContentCoverConfiguration {
        didSet {
            applyConfiguration()
        }
    }

    public var onReveal: (() -> Void)?
    public private(set) var isRevealed: Bool = false

    weak var ownerView: UIView?

    private let blurView = UIVisualEffectView(effect: nil)
    private let tintView = UIView()
    private let sparkleLayer = CAReplicatorLayer()
    private let particleLayer = CALayer()

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
        tintView.frame = bounds
        sparkleLayer.frame = bounds
        particleLayer.bounds = CGRect(origin: .zero, size: CGSize(width: 2.5, height: 2.5))
        particleLayer.position = CGPoint(x: 1.25, y: bounds.midY)
        sparkleLayer.instanceCount = max(1, Int(max(bounds.width, bounds.height) / 7.0))
        sparkleLayer.instanceTransform = CATransform3DMakeTranslation(7.0, 0.0, 0.0)
    }

    public func reveal(animated: Bool = true) {
        guard !isRevealed else { return }
        isRevealed = true
        onReveal?()

        if let ownerView {
            ownerView.removeParticleContentCover(animated: animated)
        } else {
            removeFromSuperview()
        }
    }

    private func commonInit() {
        isOpaque = false
        clipsToBounds = true
        isUserInteractionEnabled = true

        addSubview(blurView)
        addSubview(tintView)

        particleLayer.cornerRadius = 1.25
        sparkleLayer.addSublayer(particleLayer)
        layer.addSublayer(sparkleLayer)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        applyConfiguration()
    }

    private func applyConfiguration() {
        if configuration.blurRadius > 0.0 {
            blurView.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            tintView.backgroundColor = configuration.particleColor.withAlphaComponent(0.18)
        } else {
            blurView.effect = nil
            tintView.backgroundColor = configuration.particleColor.withAlphaComponent(0.28)
        }
        particleLayer.backgroundColor = configuration.particleColor.withAlphaComponent(0.42).cgColor
        sparkleLayer.instanceAlphaOffset = -0.018
    }

    @objc private func handleTap() {
        reveal(animated: true)
    }
}

open class AetherInvisibleInkView: UIView {
    public var configuration: AetherInvisibleInkConfiguration {
        didSet {
            inkColor = configuration.particleColor
            setNeedsDisplay()
        }
    }

    public var onReveal: (() -> Void)?
    public private(set) var isRevealed: Bool = false

    weak var ownerView: UIView?

    private var inkColor: UIColor
    private var textColor: UIColor
    private var lineRects: [CGRect] = []
    private var wordRects: [CGRect] = []

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

    open override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), !isRevealed else { return }

        context.saveGState()
        context.setShouldAntialias(true)

        let coverRects = wordRects.isEmpty ? (lineRects.isEmpty ? [bounds] : lineRects) : wordRects
        let resolvedColor = inkColor.resolvedColor(with: traitCollection)
        let fillColor = resolvedColor.withAlphaComponent(0.22)
        let strokeColor = textColor.resolvedColor(with: traitCollection).withAlphaComponent(0.10)

        for coverRect in coverRects where coverRect.width > 0.0 && coverRect.height > 0.0 {
            let roundedRect = coverRect.insetBy(dx: -1.0, dy: -1.0)
            let radius = min(roundedRect.height * 0.42, 7.0)
            let path = UIBezierPath(roundedRect: roundedRect, cornerRadius: radius)
            fillColor.setFill()
            path.fill()

            strokeColor.setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }

        context.restoreGState()
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
        setNeedsDisplay()
    }

    public func update(for label: UILabel) {
        let textRect = label.bounds
        update(
            size: textRect.size,
            color: configuration.particleColor,
            textColor: label.textColor,
            rects: [CGRect(origin: .zero, size: textRect.size)],
            wordRects: [CGRect(origin: .zero, size: textRect.size)]
        )
    }

    public func reveal(animated: Bool = true) {
        guard !isRevealed else { return }
        isRevealed = true
        onReveal?()

        if let ownerView {
            ownerView.removeInk(animated: animated)
        } else {
            removeFromSuperview()
        }
    }

    private func commonInit() {
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        reveal(animated: true)
    }
}

private extension UIView {
    @AssociatedObject(.retain(.nonatomic))
    var aetherStoredCoverView: AetherParticleContentCoverView?

    @AssociatedObject(.retain(.nonatomic))
    var aetherStoredInvisibleInk: AetherInvisibleInkView?
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
        aetherStoredCoverView = nil

        let remove = {
            coverView.removeFromSuperview()
        }

        guard animated else {
            remove()
            return
        }

        UIView.animate(
            withDuration: 0.18,
            animations: {
                coverView.alpha = 0.0
            },
            completion: { _ in
                remove()
            }
        )
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

        inkView.frame = bounds
        inkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        inkView.isHidden = false
        bringSubviewToFront(inkView)

        if let label = self as? UILabel {
            inkView.update(for: label)
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
        aetherStoredInvisibleInk = nil

        let remove = {
            inkView.removeFromSuperview()
        }

        guard animated else {
            remove()
            return
        }

        UIView.animate(
            withDuration: 0.18,
            animations: {
                inkView.alpha = 0.0
            },
            completion: { _ in
                remove()
            }
        )
    }
}
