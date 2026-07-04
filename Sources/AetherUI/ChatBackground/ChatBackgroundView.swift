import UIKit

public struct ChatBackgroundContentStats: Equatable {
    public let brightness: CGFloat
    public let saturation: CGFloat

    public var isDark: Bool {
        brightness < 0.42
    }

    public var isSaturated: Bool {
        saturation > 0.32
    }

    public init(brightness: CGFloat, saturation: CGFloat) {
        self.brightness = max(0.0, min(1.0, brightness))
        self.saturation = max(0.0, min(1.0, saturation))
    }
}

public struct ChatBackgroundGradientVector: Equatable {
    public let startPoint: CGPoint
    public let endPoint: CGPoint

    public init(startPoint: CGPoint, endPoint: CGPoint) {
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
}

public struct ChatBackgroundSettings {
    public enum ImageContentMode {
        case aspectFill
        case aspectFit
        case fill
        case tile
    }

    public struct Gradient {
        public var colors: [UIColor]
        public var rotation: CGFloat
        public var locations: [NSNumber]?

        public init(colors: [UIColor], rotation: CGFloat = 0.0, locations: [NSNumber]? = nil) {
            self.colors = colors
            self.rotation = rotation
            self.locations = locations
        }
    }

    public enum Content {
        case color(UIColor)
        case gradient(Gradient)
        case image(UIImage, mode: ImageContentMode)
    }

    public struct Pattern {
        public var image: UIImage
        public var intensity: CGFloat
        public var tintColor: UIColor?
        public var scale: CGFloat
        public var rotation: CGFloat
        public var blendMode: CGBlendMode

        public init(
            image: UIImage = ChatBackgroundSettings.makeDefaultPatternImage(),
            intensity: CGFloat = 0.24,
            tintColor: UIColor? = nil,
            scale: CGFloat = 1.0,
            rotation: CGFloat = 0.0,
            blendMode: CGBlendMode = .normal
        ) {
            self.image = image
            self.intensity = intensity
            self.tintColor = tintColor
            self.scale = scale
            self.rotation = rotation
            self.blendMode = blendMode
        }

        public var clampedIntensity: CGFloat {
            max(-1.0, min(1.0, intensity))
        }

        public var clampedScale: CGFloat {
            max(0.15, min(4.0, scale))
        }
    }

    public struct ImageOverlay {
        public var image: UIImage
        public var mode: ImageContentMode
        public var alpha: CGFloat

        public init(
            image: UIImage,
            mode: ImageContentMode = .aspectFill,
            alpha: CGFloat = 1.0
        ) {
            self.image = image
            self.mode = mode
            self.alpha = max(0.0, min(1.0, alpha))
        }
    }

    public var content: Content
    public var pattern: Pattern?
    public var imageOverlay: ImageOverlay?
    public var blurRadius: CGFloat
    public var blurSaturation: CGFloat
    public var dimColor: UIColor?
    public var motionEnabled: Bool
    public var motionAmount: CGFloat

    public init(
        content: Content,
        pattern: Pattern? = nil,
        imageOverlay: ImageOverlay? = nil,
        blurRadius: CGFloat = 0.0,
        blurSaturation: CGFloat = 1.0,
        dimColor: UIColor? = nil,
        motionEnabled: Bool = false,
        motionAmount: CGFloat = 24.0
    ) {
        self.content = content
        self.pattern = pattern
        self.imageOverlay = imageOverlay
        self.blurRadius = blurRadius
        self.blurSaturation = blurSaturation
        self.dimColor = dimColor
        self.motionEnabled = motionEnabled
        self.motionAmount = motionAmount
    }

    public static var telegramClassic: ChatBackgroundSettings {
        ChatBackgroundSettings(
            content: .gradient(Gradient(colors: [
                UIColor(red: 0.84, green: 0.92, blue: 0.98, alpha: 1.0),
                UIColor(red: 0.73, green: 0.85, blue: 0.94, alpha: 1.0),
                UIColor(red: 0.88, green: 0.93, blue: 0.89, alpha: 1.0)
            ], rotation: 22.0)),
            pattern: Pattern(intensity: 0.18),
            blurRadius: 0.0,
            dimColor: UIColor.white.withAlphaComponent(0.04),
            motionEnabled: true,
            motionAmount: 18.0
        )
    }

    public static var darkTelegramClassic: ChatBackgroundSettings {
        ChatBackgroundSettings(
            content: .gradient(Gradient(colors: [
                UIColor(red: 0.10, green: 0.16, blue: 0.20, alpha: 1.0),
                UIColor(red: 0.12, green: 0.20, blue: 0.25, alpha: 1.0),
                UIColor(red: 0.08, green: 0.12, blue: 0.15, alpha: 1.0)
            ], rotation: 24.0)),
            pattern: Pattern(intensity: -0.22),
            blurRadius: 0.0,
            dimColor: UIColor.black.withAlphaComponent(0.08),
            motionEnabled: true,
            motionAmount: 18.0
        )
    }

    public static func gradientVector(rotation: CGFloat) -> ChatBackgroundGradientVector {
        let radians = rotation * .pi / 180.0
        let dx = cos(radians)
        let dy = sin(radians)
        return ChatBackgroundGradientVector(
            startPoint: CGPoint(x: 0.5 - dx * 0.5, y: 0.5 - dy * 0.5),
            endPoint: CGPoint(x: 0.5 + dx * 0.5, y: 0.5 + dy * 0.5)
        )
    }

    public static func contentStats(for colors: [UIColor], traitCollection: UITraitCollection = .current) -> ChatBackgroundContentStats {
        guard !colors.isEmpty else {
            return ChatBackgroundContentStats(brightness: 1.0, saturation: 0.0)
        }

        var totalBrightness: CGFloat = 0.0
        var maxSaturation: CGFloat = 0.0
        for color in colors {
            let resolved = color.resolvedColor(with: traitCollection)
            var hue: CGFloat = 0.0
            var saturation: CGFloat = 0.0
            var brightness: CGFloat = 0.0
            var alpha: CGFloat = 0.0
            if resolved.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) {
                totalBrightness += brightness
                maxSaturation = max(maxSaturation, saturation * min(brightness * 1.3, 1.0))
            } else {
                var red: CGFloat = 0.0
                var green: CGFloat = 0.0
                var blue: CGFloat = 0.0
                if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                    totalBrightness += 0.299 * red + 0.587 * green + 0.114 * blue
                }
            }
        }

        return ChatBackgroundContentStats(
            brightness: totalBrightness / CGFloat(colors.count),
            saturation: maxSaturation
        )
    }

    public func estimatedContentStats(traitCollection: UITraitCollection = .current) -> ChatBackgroundContentStats {
        switch content {
        case let .color(color):
            return ChatBackgroundSettings.contentStats(for: [color], traitCollection: traitCollection)
        case let .gradient(gradient):
            return ChatBackgroundSettings.contentStats(for: gradient.colors, traitCollection: traitCollection)
        case let .image(image, _):
            return ChatBackgroundSettings.contentStats(for: image)
        }
    }

    public static func contentStats(for image: UIImage) -> ChatBackgroundContentStats {
        guard let cgImage = image.cgImage else {
            return ChatBackgroundContentStats(brightness: 1.0, saturation: 0.0)
        }

        let width = 12
        let height = 12
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return ChatBackgroundContentStats(brightness: 1.0, saturation: 0.0)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var totalBrightness: CGFloat = 0.0
        var totalSaturation: CGFloat = 0.0
        for index in 0..<(width * height) {
            let offset = index * bytesPerPixel
            let red = CGFloat(pixels[offset]) / 255.0
            let green = CGFloat(pixels[offset + 1]) / 255.0
            let blue = CGFloat(pixels[offset + 2]) / 255.0
            let color = UIColor(red: red, green: green, blue: blue, alpha: 1.0)
            var hue: CGFloat = 0.0
            var saturation: CGFloat = 0.0
            var brightness: CGFloat = 0.0
            var alpha: CGFloat = 0.0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            totalBrightness += 0.299 * red + 0.587 * green + 0.114 * blue
            totalSaturation += saturation * min(brightness * 1.3, 1.0)
        }

        let count = CGFloat(width * height)
        return ChatBackgroundContentStats(brightness: totalBrightness / count, saturation: totalSaturation / count)
    }

    public static func makeDefaultPatternImage(
        size: CGSize = CGSize(width: 144.0, height: 144.0),
        strokeColor: UIColor = .black
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            cg.clear(CGRect(origin: .zero, size: size))
            cg.setStrokeColor(strokeColor.cgColor)
            cg.setFillColor(strokeColor.cgColor)
            cg.setLineWidth(1.6)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)

            func stroke(_ path: UIBezierPath) {
                path.lineWidth = 1.6
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.stroke()
            }

            let plane = UIBezierPath()
            plane.move(to: CGPoint(x: 24, y: 24))
            plane.addLine(to: CGPoint(x: 62, y: 12))
            plane.addLine(to: CGPoint(x: 48, y: 48))
            plane.addLine(to: CGPoint(x: 38, y: 34))
            plane.addLine(to: CGPoint(x: 24, y: 24))
            stroke(plane)

            let bubble = UIBezierPath(roundedRect: CGRect(x: 84, y: 24, width: 34, height: 22), cornerRadius: 8)
            stroke(bubble)
            let tail = UIBezierPath()
            tail.move(to: CGPoint(x: 98, y: 46))
            tail.addLine(to: CGPoint(x: 92, y: 56))
            tail.addLine(to: CGPoint(x: 108, y: 46))
            stroke(tail)

            let arc = UIBezierPath(arcCenter: CGPoint(x: 42, y: 104), radius: 20, startAngle: 0.15, endAngle: 2.9, clockwise: true)
            stroke(arc)
            let dotRects = [
                CGRect(x: 34, y: 98, width: 3, height: 3),
                CGRect(x: 44, y: 98, width: 3, height: 3),
                CGRect(x: 54, y: 98, width: 3, height: 3),
                CGRect(x: 100, y: 92, width: 4, height: 4),
                CGRect(x: 116, y: 112, width: 3, height: 3)
            ]
            for rect in dotRects {
                cg.fillEllipse(in: rect)
            }

            let wave = UIBezierPath()
            wave.move(to: CGPoint(x: 88, y: 116))
            wave.addCurve(to: CGPoint(x: 132, y: 116), controlPoint1: CGPoint(x: 98, y: 104), controlPoint2: CGPoint(x: 118, y: 128))
            stroke(wave)
        }.withRenderingMode(.alwaysTemplate)
    }
}

public final class ChatBackgroundView: UIView {
    public private(set) var settings: ChatBackgroundSettings
    public private(set) var contentStats: ChatBackgroundContentStats
    public var contentStatsUpdated: ((ChatBackgroundContentStats) -> Void)?

    private let visualContainer = UIView()
    private let imageView = UIImageView()
    private let tiledImageView = ChatBackgroundTiledImageView()
    private let overlayImageView = UIImageView()
    private let overlayTiledImageView = ChatBackgroundTiledImageView()
    private let blurView = VisualEffectView()
    private let patternView = ChatBackgroundPatternView()
    private let dimView = UIView()
    private let gradientLayer = CAGradientLayer()

    public init(settings: ChatBackgroundSettings = .telegramClassic) {
        self.settings = settings
        self.contentStats = settings.estimatedContentStats()
        super.init(frame: .zero)
        commonInit()
        applySettings(transition: .immediate)
    }

    public required init?(coder: NSCoder) {
        self.settings = .telegramClassic
        self.contentStats = settings.estimatedContentStats()
        super.init(coder: coder)
        commonInit()
        applySettings(transition: .immediate)
    }

    public func setSettings(_ settings: ChatBackgroundSettings, transition: ContainedViewLayoutTransition = .immediate) {
        self.settings = settings
        applySettings(transition: transition)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateFrames(transition: .immediate)
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyStats()
        patternView.setNeedsDisplay()
    }

    private func commonInit() {
        isOpaque = true
        clipsToBounds = true
        backgroundColor = .systemBackground

        visualContainer.clipsToBounds = false
        addSubview(visualContainer)

        gradientLayer.needsDisplayOnBoundsChange = true
        visualContainer.layer.addSublayer(gradientLayer)

        imageView.clipsToBounds = true
        visualContainer.addSubview(imageView)
        visualContainer.addSubview(tiledImageView)
        overlayImageView.clipsToBounds = true
        visualContainer.addSubview(overlayImageView)
        visualContainer.addSubview(overlayTiledImageView)

        blurView.style = .customBlur
        blurView.isUserInteractionEnabled = false
        visualContainer.addSubview(blurView)

        patternView.isUserInteractionEnabled = false
        patternView.backgroundColor = .clear
        visualContainer.addSubview(patternView)

        dimView.isUserInteractionEnabled = false
        visualContainer.addSubview(dimView)
    }

    private func applySettings(transition: ContainedViewLayoutTransition) {
        applyContent()
        applyImageOverlay()
        applyBlur()
        applyStats()

        patternView.pattern = settings.pattern
        patternView.contentStats = contentStats
        dimView.backgroundColor = settings.dimColor
        dimView.isHidden = settings.dimColor == nil

        updateMotionEffects()
        updateFrames(transition: transition)
    }

    private func applyContent() {
        imageView.isHidden = true
        tiledImageView.isHidden = true
        gradientLayer.isHidden = true
        visualContainer.backgroundColor = nil

        switch settings.content {
        case let .color(color):
            visualContainer.backgroundColor = color

        case let .gradient(gradient):
            gradientLayer.isHidden = false
            gradientLayer.colors = normalizedGradientColors(gradient.colors).map { $0.cgColor }
            gradientLayer.locations = gradient.locations
            let vector = ChatBackgroundSettings.gradientVector(rotation: gradient.rotation)
            gradientLayer.startPoint = vector.startPoint
            gradientLayer.endPoint = vector.endPoint

        case let .image(image, mode):
            switch mode {
            case .tile:
                tiledImageView.isHidden = false
                tiledImageView.image = image
            case .aspectFill, .aspectFit, .fill:
                imageView.isHidden = false
                imageView.image = image
                switch mode {
                case .aspectFill:
                    imageView.contentMode = .scaleAspectFill
                case .aspectFit:
                    imageView.contentMode = .scaleAspectFit
                case .fill:
                    imageView.contentMode = .scaleToFill
                case .tile:
                    break
                }
            }
        }
    }

    private func applyImageOverlay() {
        overlayImageView.isHidden = true
        overlayImageView.image = nil
        overlayImageView.alpha = 1.0
        overlayTiledImageView.isHidden = true
        overlayTiledImageView.image = nil
        overlayTiledImageView.alpha = 1.0

        guard let overlay = settings.imageOverlay, overlay.alpha > 0.0 else {
            return
        }

        switch overlay.mode {
        case .tile:
            overlayTiledImageView.isHidden = false
            overlayTiledImageView.image = overlay.image
            overlayTiledImageView.alpha = overlay.alpha
        case .aspectFill, .aspectFit, .fill:
            overlayImageView.isHidden = false
            overlayImageView.image = overlay.image
            overlayImageView.alpha = overlay.alpha
            switch overlay.mode {
            case .aspectFill:
                overlayImageView.contentMode = .scaleAspectFill
            case .aspectFit:
                overlayImageView.contentMode = .scaleAspectFit
            case .fill:
                overlayImageView.contentMode = .scaleToFill
            case .tile:
                break
            }
        }
    }

    private func normalizedGradientColors(_ colors: [UIColor]) -> [UIColor] {
        if colors.isEmpty {
            return [.systemBackground, .secondarySystemBackground]
        }
        if colors.count == 1 {
            return [colors[0], colors[0]]
        }
        return colors
    }

    private func applyBlur() {
        let blurRadius = max(0.0, settings.blurRadius)
        blurView.blurRadius = blurRadius
        blurView.saturation = max(0.0, settings.blurSaturation)
        blurView.alpha = blurRadius > 0.0 ? 1.0 : 0.0
        blurView.isHidden = blurRadius <= 0.0
    }

    private func applyStats() {
        let stats = settings.estimatedContentStats(traitCollection: traitCollection)
        guard stats != contentStats else {
            return
        }
        contentStats = stats
        contentStatsUpdated?(stats)
    }

    private func updateFrames(transition: ContainedViewLayoutTransition) {
        let amount = resolvedMotionAmount()
        let visualFrame = bounds.insetBy(dx: -amount, dy: -amount)
        transition.updateFrame(view: visualContainer, frame: visualFrame)

        let contentBounds = CGRect(origin: .zero, size: visualFrame.size)
        gradientLayer.frame = contentBounds
        transition.updateFrame(view: imageView, frame: contentBounds)
        transition.updateFrame(view: tiledImageView, frame: contentBounds)
        transition.updateFrame(view: overlayImageView, frame: contentBounds)
        transition.updateFrame(view: overlayTiledImageView, frame: contentBounds)
        transition.updateFrame(view: blurView, frame: contentBounds)
        transition.updateFrame(view: patternView, frame: contentBounds)
        transition.updateFrame(view: dimView, frame: contentBounds)
    }

    private func resolvedMotionAmount() -> CGFloat {
        guard settings.motionEnabled, !UIAccessibility.isReduceMotionEnabled else {
            return 0.0
        }
        return max(0.0, min(64.0, settings.motionAmount))
    }

    private func updateMotionEffects() {
        visualContainer.motionEffects.forEach { visualContainer.removeMotionEffect($0) }
        let amount = resolvedMotionAmount()
        guard amount > 0.0 else {
            return
        }

        let horizontal = UIInterpolatingMotionEffect(keyPath: "center.x", type: .tiltAlongHorizontalAxis)
        horizontal.minimumRelativeValue = -amount
        horizontal.maximumRelativeValue = amount

        let vertical = UIInterpolatingMotionEffect(keyPath: "center.y", type: .tiltAlongVerticalAxis)
        vertical.minimumRelativeValue = -amount
        vertical.maximumRelativeValue = amount

        let group = UIMotionEffectGroup()
        group.motionEffects = [horizontal, vertical]
        visualContainer.addMotionEffect(group)
    }
}

private final class ChatBackgroundTiledImageView: UIView {
    var image: UIImage? {
        didSet {
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
        backgroundColor = .clear
    }

    override func draw(_ rect: CGRect) {
        guard let image else {
            return
        }
        let tileSize = image.size
        guard tileSize.width > 0.0, tileSize.height > 0.0 else {
            return
        }

        var y = floor(rect.minY / tileSize.height) * tileSize.height
        while y < rect.maxY {
            var x = floor(rect.minX / tileSize.width) * tileSize.width
            while x < rect.maxX {
                image.draw(in: CGRect(x: x, y: y, width: tileSize.width, height: tileSize.height))
                x += tileSize.width
            }
            y += tileSize.height
        }
    }
}

private final class ChatBackgroundPatternView: UIView {
    var pattern: ChatBackgroundSettings.Pattern? {
        didSet {
            tintedPatternImage = nil
            setNeedsDisplay()
        }
    }

    var contentStats: ChatBackgroundContentStats = ChatBackgroundContentStats(brightness: 1.0, saturation: 0.0) {
        didSet {
            tintedPatternImage = nil
            setNeedsDisplay()
        }
    }

    private var tintedPatternImage: UIImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isOpaque = false
    }

    override func draw(_ rect: CGRect) {
        guard let pattern else {
            return
        }

        let intensity = pattern.clampedIntensity
        let alpha = abs(intensity)
        guard alpha > 0.001 else {
            return
        }

        let image = resolvedPatternImage(for: pattern, intensity: intensity)
        let scale = pattern.clampedScale
        let tileSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        guard tileSize.width > 0.0, tileSize.height > 0.0 else {
            return
        }

        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: pattern.rotation * .pi / 180.0)
        context.translateBy(x: -bounds.midX, y: -bounds.midY)

        let drawRect = bounds.insetBy(dx: -bounds.width, dy: -bounds.height)
        var y = floor(drawRect.minY / tileSize.height) * tileSize.height
        while y < drawRect.maxY {
            var x = floor(drawRect.minX / tileSize.width) * tileSize.width
            while x < drawRect.maxX {
                image.draw(in: CGRect(x: x, y: y, width: tileSize.width, height: tileSize.height), blendMode: pattern.blendMode, alpha: alpha)
                x += tileSize.width
            }
            y += tileSize.height
        }

        context.restoreGState()
    }

    private func resolvedPatternImage(for pattern: ChatBackgroundSettings.Pattern, intensity: CGFloat) -> UIImage {
        if let tintedPatternImage {
            return tintedPatternImage
        }

        let color: UIColor
        if let tintColor = pattern.tintColor {
            color = tintColor
        } else if intensity < 0.0 {
            color = .white
        } else {
            color = contentStats.isDark ? .white : .black
        }

        let image = tintedImage(pattern.image, color: color)
        tintedPatternImage = image
        return image
    }

    private func tintedImage(_ image: UIImage, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: image.size)
            color.setFill()
            context.fill(rect)
            image.draw(in: rect, blendMode: .destinationIn, alpha: 1.0)
        }
    }
}
