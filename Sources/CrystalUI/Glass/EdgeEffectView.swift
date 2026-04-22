import UIKit

// MARK: - EdgeEffectView
// Direct port of Display framework `EdgeEffectView` from

// Applies a gradient-masked color fill along an edge (top/bottom) of a container
// plus an optional variable-radius blur on iOS 26+.

public final class EdgeEffectView: UIView {
    public enum Edge {
        case top
        case bottom
    }

    private let contentView: UIView
    private let contentMaskView: UIImageView
    /// Variable-blur layer (`CAFilter.variableBlur` on iOS 26+, mask-gradient
    /// fallback elsewhere). True *progressive* blur — strong at the edge,
    /// tapering to zero near the content.
    private var variableBlurView: VariableBlurView?
    /// Fallback UIVisualEffectView path used when variable blur isn't needed
    /// / available (e.g. legacy theme).
    private var blurView: UIVisualEffectView?
    /// Main blur host — CABackdropLayer + `CAFilter.blur` at a custom radius
    /// for fine-grained control (lighter than any system material).
    private var backdropBlurView: BackdropBlurHostView?
    private var blurMaskView: UIImageView?

    private struct UpdateSignature: Equatable {
        let contentRGBA: UInt64
        let blur: Bool
        let alpha: CGFloat
        let size: CGSize
        let edge: Edge
        let edgeSize: CGFloat
        let blurRadiusAtEdge: CGFloat
        let blurRadiusAtFade: CGFloat
    }
    private var lastUpdateSignature: UpdateSignature?

    public override init(frame: CGRect) {
        self.contentView = UIView()
        self.contentMaskView = UIImageView()
        self.contentView.mask = self.contentMaskView

        super.init(frame: frame)

        addSubview(contentView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateColor(color: UIColor, transition: ContainedViewLayoutTransition) {
        if transition.isAnimated {
            transition.animateView({ self.contentView.backgroundColor = color })
        } else {
            contentView.backgroundColor = color
        }
    }

    /// Render a scroll-edge frost. Pass `content = nil` (or `.clear`) to get
    /// a pure blur fade (the Figma look — heavy frost that softly fades
    /// toward the content area, with NO solid color fill bleeding through).
    ///
    /// `blurRadiusAtEdge` is the radius at the solid (screen-facing) side;
    /// `blurRadiusAtFade` is the radius at the transparent (content-facing)
    /// side. When the two differ, the view uses `CAFilter.variableBlur` to
    /// ramp the radius spatially.
    public func update(
        content: UIColor?,
        blur: Bool = false,
        alpha: CGFloat = 0.5,
        rect: CGRect,
        edge: Edge,
        edgeSize: CGFloat,
        blurRadiusAtEdge: CGFloat = 3.0,
        blurRadiusAtFade: CGFloat = 3.0,
        transition: ContainedViewLayoutTransition
    ) {
        // Fast-path early return when layout is driven by a non-animated
        // layoutSubviews pass and nothing about the inputs actually changed.
        // Measured ~30-40% of layout passes on a scroll in practice.
        if !transition.isAnimated {
            let signature = UpdateSignature(
                contentRGBA: Self.packRGBA(content),
                blur: blur,
                alpha: alpha,
                size: rect.size,
                edge: edge,
                edgeSize: edgeSize,
                blurRadiusAtEdge: blurRadiusAtEdge,
                blurRadiusAtFade: blurRadiusAtFade
            )
            if signature == lastUpdateSignature {
                return
            }
            lastUpdateSignature = signature
        } else {
            // Animated transitions always run the full pipeline; invalidate
            // the signature so the next immediate pass can't short-circuit
            // past an intermediate state.
            lastUpdateSignature = nil
        }

        // Fill layer (only used when caller actually wants a solid color band,
        // e.g. the nav bar background stripe in legacy mode).
        let useFill: Bool
        if let content, content.cgColor.alpha > 0.001 {
            if transition.isAnimated {
                transition.animateView({ self.contentView.backgroundColor = content })
            } else {
                contentView.backgroundColor = content
            }
            useFill = true
        } else {
            contentView.backgroundColor = .clear
            useFill = false
        }
        transition.setAlpha(view: contentView, alpha: useFill ? alpha : 0.0)

        let bounds = CGRect(origin: .zero, size: rect.size)
        transition.setFrame(view: contentView, frame: bounds)
        transition.setFrame(view: contentMaskView, frame: bounds)

        // Use the SAME tapered-gradient helper as the blur path so the tint
        // layer and the blur layer fade to zero at the exact same spot —
        // otherwise the terminus shows a visible band where the tint persists
        // past where the blur stops.
        if edgeSize > 0.0, useFill {
            contentMaskView.image = EdgeEffectView.generateTaperedGradient(
                totalHeight: bounds.height,
                fadeHeight: min(edgeSize, bounds.height),
                edge: edge
            )
        } else {
            contentMaskView.image = nil
        }

        if blur {
            let blurFrame = CGRect(origin: .zero, size: bounds.size)
            let fadeHeight = min(edgeSize, blurFrame.size.height)
            let useVariable = abs(blurRadiusAtEdge - blurRadiusAtFade) > 0.01

            if useVariable {
                // Variable radius: use the private `CAFilter.variableBlur`
                // via `VariableBlurView`. The mask's alpha directly controls
                // per-pixel radius — white = max, black = 0. To realise
                // `blurRadiusAtEdge` → `blurRadiusAtFade`, we build a mask
                // whose alpha goes from 1.0 at the solid side down to
                // `blurRadiusAtFade / blurRadiusAtEdge` at the transparent
                // side, then scale `maxBlurRadius = blurRadiusAtEdge`.
                let vBlur: VariableBlurView
                if let current = variableBlurView, current.maxBlurRadius == blurRadiusAtEdge {
                    vBlur = current
                } else {
                    variableBlurView?.removeFromSuperview()
                    let newView = VariableBlurView(maxBlurRadius: blurRadiusAtEdge)
                    insertSubview(newView, at: 0)
                    variableBlurView = newView
                    vBlur = newView
                }
                let minFraction = max(0.0, min(1.0, blurRadiusAtFade / max(0.001, blurRadiusAtEdge)))
                let gradient = VariableBlurEffect.Gradient(
                    height: fadeHeight,
                    alpha: [minFraction, 1.0],
                    positions: [0.0, 1.0]
                )
                vBlur.update(
                    size: blurFrame.size,
                    constantHeight: max(0.0, blurFrame.size.height - fadeHeight),
                    isInverted: edge == .bottom,
                    gradient: gradient,
                    transition: transition
                )
                transition.setFrame(view: vBlur, frame: blurFrame)

                // Tear down uniform-blur fallback paths.
                if let host = backdropBlurView {
                    backdropBlurView = nil
                    host.removeFromSuperview()
                }
                if let view = blurView {
                    blurView = nil
                    view.removeFromSuperview()
                }
            } else {
                // Uniform radius — use CABackdropLayer + CAFilter.blur at a
                // constant input radius. Gradient-masked so the blur tapers
                // toward the content area.
                let blurHost: BackdropBlurHostView
                if let current = backdropBlurView {
                    blurHost = current
                } else {
                    blurHost = BackdropBlurHostView()
                    insertSubview(blurHost, at: 0)
                    backdropBlurView = blurHost
                }
                blurHost.inputRadius = blurRadiusAtEdge
                blurHost.frame = blurFrame

                let mask: UIImageView
                if let current = blurMaskView {
                    mask = current
                } else {
                    mask = UIImageView()
                    blurMaskView = mask
                    blurHost.mask = mask
                }
                mask.frame = CGRect(origin: .zero, size: blurFrame.size)
                mask.image = EdgeEffectView.generateTaperedGradient(
                    totalHeight: blurFrame.size.height,
                    fadeHeight: fadeHeight,
                    edge: edge
                )

                transition.setFrame(view: blurHost, frame: blurFrame)

                // Tear down variable-blur fallback paths.
                if let view = blurView {
                    blurView = nil
                    view.removeFromSuperview()
                }
                if let vBlur = variableBlurView {
                    variableBlurView = nil
                    vBlur.removeFromSuperview()
                }
            }
        } else {
            if let view = blurView {
                blurView = nil
                view.removeFromSuperview()
            }
            if let host = backdropBlurView {
                backdropBlurView = nil
                host.removeFromSuperview()
            }
            blurMaskView = nil
            if let vBlur = variableBlurView {
                variableBlurView = nil
                vBlur.removeFromSuperview()
            }
        }
    }

    /// Generate a mask image for a blur view that is fully opaque at `edge`
    /// and fades to transparent over `fadeHeight` pixels toward the opposite
    /// side. Sized exactly to the blur frame so no stretching is required.
    ///
    /// The fade uses a cosine profile so the derivative of alpha is zero on
    /// both ends of the fade — the transition from the solid portion into
    /// the fade is C1-continuous, and the visible "band" that a linear
    /// gradient produces at the solid↔fade boundary disappears. Sampled at
    /// enough stops (32) that CGGradient's linear interpolation between
    /// adjacent stops is indistinguishable from the true cosine curve.
    // Per-process LRU cache. Keyed on the rounded pixel dimensions + edge so
    // repeated layout passes for the same edge size reuse the same UIImage
    // instead of re-running a 32-stop cosine gradient through CGContext each
    // time. Measured ~8–12ms per build on iPhone 12 — this is the hot path
    // for EdgeEffectView.update during scroll.
    private static let taperedGradientCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        return cache
    }()

    /// Pack a UIColor's RGBA components into a single UInt64 so the update
    /// signature can compare colors as value types. Quantizes to 1/255 per
    /// channel — sub-step color drift wouldn't be visually meaningful anyway.
    static func packRGBA(_ color: UIColor?) -> UInt64 {
        guard let color else { return 0 }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = UInt64(max(0.0, min(1.0, r)) * 255.0 + 0.5)
        let gi = UInt64(max(0.0, min(1.0, g)) * 255.0 + 0.5)
        let bi = UInt64(max(0.0, min(1.0, b)) * 255.0 + 0.5)
        let ai = UInt64(max(0.0, min(1.0, a)) * 255.0 + 0.5)
        return (ri << 24) | (gi << 16) | (bi << 8) | ai
    }

    static func generateTaperedGradient(totalHeight: CGFloat, fadeHeight: CGFloat, edge: Edge) -> UIImage? {
        let height = max(1.0, totalHeight)
        let size = CGSize(width: 1.0, height: height)
        let clampedFade = min(max(0.0, fadeHeight), height)
        let solidHeight = max(0.0, height - clampedFade)

        // Quantize to tenths of a point — sub-pixel changes on float h
        // would otherwise miss the cache on every layoutSubviews.
        let keyHeight = Int((height * 10.0).rounded())
        let keyFade = Int((clampedFade * 10.0).rounded())
        let key = "\(edge == .top ? "t" : "b")-\(keyHeight)-\(keyFade)" as NSString
        if let cached = taperedGradientCache.object(forKey: key) {
            return cached
        }

        let image = generateImage(size, rotatedContext: { size, context in
            context.clear(CGRect(origin: .zero, size: size))
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            // Cosine-sampled fade: N+1 stops from alpha 1 → 0.
            let steps = 32
            var fadeColors: [CGColor] = []
            var fadeLocations: [CGFloat] = []
            fadeColors.reserveCapacity(steps + 1)
            fadeLocations.reserveCapacity(steps + 1)
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let alpha = 0.5 * (1.0 + cos(.pi * t))
                fadeColors.append(UIColor.white.withAlphaComponent(alpha).cgColor)
                fadeLocations.append(t)
            }

            switch edge {
            case .top:
                // Opaque at TOP of image, fade toward BOTTOM.
                if solidHeight > 0.0 {
                    context.setFillColor(UIColor.white.cgColor)
                    context.fill(CGRect(x: 0.0, y: 0.0, width: size.width, height: solidHeight))
                }
                if clampedFade > 0.0,
                   let gradient = CGGradient(colorsSpace: colorSpace, colors: fadeColors as CFArray, locations: fadeLocations)
                {
                    context.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: 0.0, y: solidHeight),
                        end: CGPoint(x: 0.0, y: height),
                        options: []
                    )
                }
            case .bottom:
                // Opaque at BOTTOM of image, fade toward TOP. Reverse the
                // cosine stop order (alpha goes 0 → 1 across the fade zone).
                if solidHeight > 0.0 {
                    context.setFillColor(UIColor.white.cgColor)
                    context.fill(CGRect(x: 0.0, y: clampedFade, width: size.width, height: solidHeight))
                }
                let reversedColors = Array(fadeColors.reversed())
                let reversedLocations = fadeLocations.map { 1.0 - $0 }.reversed()
                if clampedFade > 0.0,
                   let gradient = CGGradient(colorsSpace: colorSpace, colors: reversedColors as CFArray, locations: Array(reversedLocations))
                {
                    context.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: 0.0, y: 0.0),
                        end: CGPoint(x: 0.0, y: clampedFade),
                        options: []
                    )
                }
            }
        })
        if let image {
            taperedGradientCache.setObject(image, forKey: key)
        }
        return image
    }

    // MARK: - Gradient generation

    public static func generateEdgeGradient(baseHeight: CGFloat, isInverted: Bool, extendsInwards: Bool = false) -> UIImage? {
        let height = max(1.0, baseHeight)
        let size = CGSize(width: 1.0, height: height)
        return generateImage(size, rotatedContext: { size, context in
            context.clear(CGRect(origin: .zero, size: size))

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            // For `isInverted = false` (top-edge fade) the image is transparent
            // at its top row and opaque at its bottom row. For `isInverted = true`
            // (bottom-edge fade) the orientation is flipped.
            let colors: [CGColor] = isInverted
                ? [UIColor.white.withAlphaComponent(1.0).cgColor, UIColor.white.withAlphaComponent(0.0).cgColor]
                : [UIColor.white.withAlphaComponent(0.0).cgColor, UIColor.white.withAlphaComponent(1.0).cgColor]
            var locations: [CGFloat] = [0.0, 1.0]
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations) else {
                return
            }
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0.0, y: 0.0),
                end: CGPoint(x: 0.0, y: size.height),
                options: []
            )
        })?.resizableImage(
            // Protect the gradient side so only the solid side stretches as the
            // mask grows. For a top fade (`isInverted = false`) the gradient is
            // at the top, so top-cap = full image height. For a bottom fade the
            // gradient is at the bottom — we protect that side instead.
            withCapInsets: UIEdgeInsets(
                top: isInverted ? 0.0 : height,
                left: 0.0,
                bottom: isInverted ? height : 0.0,
                right: 0.0
            ),
            resizingMode: .stretch
        )
    }

    public static func generateEdgeGradientData(baseHeight: CGFloat) -> VariableBlurEffect.Gradient {
        let height = max(1.0, baseHeight)
        return VariableBlurEffect.Gradient(
            height: height,
            alpha: [0.0, 1.0],
            positions: [0.0, 1.0]
        )
    }
}

// MARK: - BackdropBlurHostView
// Thin wrapper around a `CABackdropLayer` (private) with a custom `CAFilter.blur`
// at a configurable `inputRadius`. Used by `EdgeEffectView` for fine-grained
// blur strength control (lighter than any `UIBlurEffect` system material).

final class BackdropBlurHostView: UIView {
    private let backdropLayer: CALayer?
    private var filter: NSObject?
    private var appliedRadius: CGFloat = -1.0

    var inputRadius: CGFloat = 5.0 {
        didSet {
            if inputRadius != oldValue {
                applyRadius()
            }
        }
    }

    override init(frame: CGRect) {
        // Instantiate the private CABackdropLayer via runtime calls (same path
        // as `LegacyGlassBackdropView`).
        self.backdropLayer = BackdropBlurHostView.createBackdropLayer()

        super.init(frame: frame)

        if let layer = backdropLayer {
            self.layer.addSublayer(layer)
            layer.frame = bounds
        }

        applyRadius()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdropLayer?.frame = bounds
    }

    private func applyRadius() {
        guard let backdropLayer else { return }
        if appliedRadius == inputRadius, filter != nil { return }

        if filter == nil, let blur = CALayer.blur() {
            filter = blur
        }
        if let filter {
            filter.setValue(inputRadius as NSNumber, forKey: "inputRadius")
            backdropLayer.filters = [filter]
        }
        appliedRadius = inputRadius
    }

    private static func createBackdropLayer() -> CALayer? {
        let name = ("CA" as NSString).appendingFormat("BackdropLayer")
        guard let cls = NSClassFromString(name as String) as AnyObject? else { return nil }
        let allocSel = NSSelectorFromString("alloc")
        let initSel = NSSelectorFromString("init")
        guard let alloc = cls.perform(allocSel)?.takeUnretainedValue() as AnyObject?,
              let layer = alloc.perform(initSel)?.takeUnretainedValue() as? CALayer
        else { return nil }
        return layer
    }
}

// MARK: - VariableBlurEffect
// Direct port of `VariableBlurEffect` — applies a variable-radius blur
// to a host layer using the private `CAFilter` `variableBlur` on iOS 26+, or a
// `CABackdropLayer` fallback on earlier systems.

public final class VariableBlurEffect {
    public final class Gradient: Equatable {
        public let height: CGFloat
        public let alpha: [CGFloat]
        public let positions: [CGFloat]

        public init(height: CGFloat, alpha: [CGFloat], positions: [CGFloat]) {
            self.height = height
            self.alpha = alpha
            self.positions = positions
        }

        public static func == (lhs: Gradient, rhs: Gradient) -> Bool {
            if lhs === rhs { return true }
            return lhs.height == rhs.height && lhs.alpha == rhs.alpha && lhs.positions == rhs.positions
        }
    }

    public struct Placement: Equatable {
        public enum Position { case top, bottom }
        public let position: Position
        public let inwardsExtension: CGFloat?

        public init(position: Position, inwardsExtension: CGFloat?) {
            self.position = position
            self.inwardsExtension = inwardsExtension
        }
    }

    private struct Params: Equatable {
        let size: CGSize
        let constantHeight: CGFloat
        let placement: Placement
        let gradient: Gradient
    }

    private let layer: CALayer
    private let isTransparent: Bool
    private let maxBlurRadius: CGFloat

    private var params: Params?
    private var gradientImage: UIImage?
    private let imageSubview: UIImageView?

    public init(layer: CALayer, isTransparent: Bool = false, maxBlurRadius: CGFloat = 20.0) {
        self.layer = layer
        self.isTransparent = isTransparent
        self.maxBlurRadius = maxBlurRadius

        if #available(iOS 26.0, *) {
            let imageSubview = UIImageView()
            self.imageSubview = imageSubview
            imageSubview.layer.name = "mask_source"

            if let variableBlur = CALayer.variableBlur() {
                variableBlur.setValue(self.maxBlurRadius, forKey: "inputRadius")
                variableBlur.setValue("mask_source", forKey: "inputSourceSublayerName")
                if isTransparent {
                    variableBlur.setValue(true, forKey: "inputNormalizeEdgesTransparent")
                } else {
                    variableBlur.setValue(true, forKey: "inputNormalizeEdges")
                }
                self.layer.filters = [variableBlur]
            }
            self.layer.addSublayer(imageSubview.layer)
        } else {
            self.imageSubview = nil
        }
    }

    public func update(
        size: CGSize,
        constantHeight: CGFloat,
        placement: Placement,
        gradient: Gradient,
        transition: ContainedViewLayoutTransition
    ) {
        let params = Params(size: size, constantHeight: constantHeight, placement: placement, gradient: gradient)
        if params == self.params {
            return
        }

        let isGradientUpdated = gradient != self.params?.gradient

        if isGradientUpdated {
            if let inwardsExtension = params.placement.inwardsExtension {
                let baseHeight = max(1.0, params.gradient.height + inwardsExtension)
                let resizingInverted = params.placement.position != .bottom
                self.gradientImage = generateImage(CGSize(width: 1.0, height: baseHeight), rotatedContext: { size, context in
                    let bounds = CGRect(origin: .zero, size: size)
                    context.clear(bounds)
                    let colors = [UIColor.white.withAlphaComponent(1.0).cgColor, UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
                    var locations: [CGFloat] = [0.0, 1.0]
                    let colorSpace = CGColorSpaceCreateDeviceRGB()
                    guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: &locations) else {
                        return
                    }
                    if params.placement.position == .bottom {
                        context.drawLinearGradient(
                            gradient,
                            start: CGPoint(x: 0.0, y: max(0.0, size.height - inwardsExtension)),
                            end: CGPoint(x: 0.0, y: 0.0),
                            options: []
                        )
                        if inwardsExtension > 0.0 {
                            context.setFillColor(UIColor.white.cgColor)
                            context.fill(CGRect(x: 0.0, y: size.height - inwardsExtension, width: size.width, height: inwardsExtension))
                        }
                    } else {
                        context.drawLinearGradient(
                            gradient,
                            start: CGPoint(x: 0.0, y: 0.0),
                            end: CGPoint(x: 0.0, y: size.height),
                            options: []
                        )
                    }
                })?.resizableImage(
                    withCapInsets: UIEdgeInsets(
                        top: resizingInverted ? baseHeight : 0.0,
                        left: 0.0,
                        bottom: resizingInverted ? 0.0 : baseHeight,
                        right: 0.0
                    ),
                    resizingMode: .stretch
                )
            } else {
                // Use the explicit `gradient.alpha` / `gradient.positions`
                // arrays — these directly control per-pixel blur radius (white
                // = max, black = none). This is what makes "8pt at edge → 1pt
                // at fade" work; the previous helper hardcoded white→clear.
                let baseHeight = max(1.0, params.gradient.height)
                let alphas = params.gradient.alpha
                let positions = params.gradient.positions
                let isBottom = params.placement.position == .bottom
                let orderedAlphas: [CGFloat] = isBottom ? Array(alphas.reversed()) : alphas
                let orderedLocations: [CGFloat] = isBottom ? Array(positions.map { 1.0 - $0 }.reversed()) : positions
                self.gradientImage = generateImage(CGSize(width: 1.0, height: baseHeight), rotatedContext: { size, context in
                    context.clear(CGRect(origin: .zero, size: size))
                    let colorSpace = CGColorSpaceCreateDeviceRGB()
                    let colors = orderedAlphas.map { UIColor(white: 1.0, alpha: $0).cgColor }
                    var locs = orderedLocations
                    guard let g = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locs) else {
                        return
                    }
                    context.drawLinearGradient(
                        g,
                        start: CGPoint(x: 0.0, y: 0.0),
                        end: CGPoint(x: 0.0, y: size.height),
                        options: []
                    )
                })?.resizableImage(
                    withCapInsets: UIEdgeInsets(
                        top: isBottom ? 0.0 : baseHeight,
                        left: 0.0,
                        bottom: isBottom ? baseHeight : 0.0,
                        right: 0.0
                    ),
                    resizingMode: .stretch
                )
            }
        }

        self.params = params

        if let imageSubview {
            if isGradientUpdated {
                imageSubview.image = self.gradientImage
            }
            transition.setFrame(layer: self.layer, frame: CGRect(origin: .zero, size: size))
            transition.setFrame(view: imageSubview, frame: CGRect(origin: .zero, size: size))
        } else {
            updateLegacyEffect()
            transition.setFrame(layer: self.layer, frame: CGRect(origin: .zero, size: size))
        }
    }

    private func updateLegacyEffect() {
        guard let params else { return }
        guard let variableBlur = CALayer.variableBlur() else { return }
        guard let gradientImage else { return }

        variableBlur.setValue(self.maxBlurRadius, forKey: "inputRadius")
        if self.isTransparent {
            variableBlur.setValue(true, forKey: "inputNormalizeEdgesTransparent")
        } else {
            variableBlur.setValue(true, forKey: "inputNormalizeEdges")
        }

        let image = generateImage(CGSize(width: 1.0, height: min(800.0, params.size.height)), rotatedContext: { size, context in
            UIGraphicsPushContext(context)
            defer { UIGraphicsPopContext() }

            context.clear(CGRect(origin: .zero, size: size))

            let mainEffectFrame: CGRect
            let additionalEffectFrame: CGRect
            if params.placement.inwardsExtension != nil {
                mainEffectFrame = CGRect(origin: .zero, size: size)
                additionalEffectFrame = .zero
            } else if params.placement.position == .bottom {
                mainEffectFrame = CGRect(x: 0.0, y: 0.0, width: size.width, height: params.constantHeight)
                additionalEffectFrame = CGRect(x: 0.0, y: params.constantHeight, width: size.width, height: max(0.0, size.height - params.constantHeight))
            } else {
                mainEffectFrame = CGRect(x: 0.0, y: size.height - params.constantHeight, width: size.width, height: params.constantHeight)
                additionalEffectFrame = CGRect(x: 0.0, y: 0.0, width: size.width, height: max(0.0, size.height - params.constantHeight))
            }

            context.setFillColor(UIColor.black.cgColor)
            context.fill(additionalEffectFrame)

            gradientImage.draw(in: mainEffectFrame, blendMode: .normal, alpha: 1.0)
        })

        if let cgImage = image?.cgImage {
            variableBlur.setValue(cgImage, forKey: "inputMaskImage")
        }

        self.layer.filters = [variableBlur]
    }
}

// MARK: - VariableBlurView
// Port of `VariableBlurView`. Uses `CABackdropLayer` as host so the blur
// samples real backdrop content (critical for iOS 26+ `variableBlur` filter).

public final class VariableBlurView: UIView {
    public let maxBlurRadius: CGFloat

    private var effect: VariableBlurEffect?
    private var mainEffectLayer: CALayer?

    public init(maxBlurRadius: CGFloat = 20.0) {
        self.maxBlurRadius = maxBlurRadius

        // Try to create a CABackdropLayer (private) for a real-backdrop blur.
        if let backdrop = VariableBlurView.createBackdropLayer() {
            self.mainEffectLayer = backdrop
        } else {
            self.mainEffectLayer = nil
        }

        super.init(frame: .zero)

        if let layer = mainEffectLayer {
            self.layer.addSublayer(layer)
            self.effect = VariableBlurEffect(layer: layer, isTransparent: false, maxBlurRadius: maxBlurRadius)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        mainEffectLayer?.frame = bounds
    }

    /// Convenience overload that matches call sites on `EdgeEffectView`.
    public func update(
        size: CGSize,
        constantHeight: CGFloat,
        isInverted: Bool,
        gradient: VariableBlurEffect.Gradient,
        transition: ContainedViewLayoutTransition
    ) {
        effect?.update(
            size: size,
            constantHeight: constantHeight,
            placement: VariableBlurEffect.Placement(
                position: isInverted ? .bottom : .top,
                inwardsExtension: nil
            ),
            gradient: gradient,
            transition: transition
        )
        mainEffectLayer?.frame = CGRect(origin: .zero, size: size)
    }

    private static func createBackdropLayer() -> CALayer? {
        let name = ("CA" as NSString).appendingFormat("BackdropLayer")
        guard let cls = NSClassFromString(name as String) as AnyObject? else { return nil }
        let allocSel = NSSelectorFromString("alloc")
        let initSel = NSSelectorFromString("init")
        guard let alloc = cls.perform(allocSel)?.takeUnretainedValue() as AnyObject?,
              let layer = alloc.perform(initSel)?.takeUnretainedValue() as? CALayer
        else { return nil }
        return layer
    }
}
