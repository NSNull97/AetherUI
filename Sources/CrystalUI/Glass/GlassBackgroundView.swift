import UIKit

// MARK: - Internal content container

private final class GlassContentContainer: UIView {
    private let maskContentView: UIView

    init(maskContentView: UIView) {
        self.maskContentView = maskContentView
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let result = super.hitTest(point, with: event) else {
            return nil
        }
        if result === self {
            if let recognizers = self.gestureRecognizers, !recognizers.isEmpty {
                return result
            }
            return nil
        }
        return result
    }

    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        if let subview = subview as? GlassBackgroundView.ContentView {
            maskContentView.addSubview(subview.tintMask)
        }
    }

    override func willRemoveSubview(_ subview: UIView) {
        super.willRemoveSubview(subview)
        if let subview = subview as? GlassBackgroundView.ContentView {
            subview.tintMask.removeFromSuperview()
        }
    }
}

// MARK: - GlassBackgroundView

/// Glass background effect view — the core glass morphism component.
/// Port of Display framework `GlassBackgroundComponent.GlassBackgroundView` targeting
/// the native `UIGlassEffect` pipeline on iOS 26+ with a legacy CABackdropLayer
/// fallback for earlier systems.
public class GlassBackgroundView: UIView {
    // MARK: Content view protocol

    public protocol ContentView: UIView {
        var tintMask: UIView { get }
    }

    public final class ContentColorView: UIView, ContentView {
        public let tintMask = UIView()

        public override init(frame: CGRect) {
            super.init(frame: frame)
            tintMask.backgroundColor = .black
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override var backgroundColor: UIColor? {
            didSet {
                tintMask.backgroundColor = backgroundColor?.withAlphaComponent(1.0) ?? .black
            }
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            tintMask.frame = bounds
            tintMask.layer.cornerRadius = layer.cornerRadius
        }
    }

    public final class ContentImageView: UIImageView, ContentView {
        private let tintImageView = UIImageView()

        public var tintMask: UIView {
            tintImageView
        }

        public override var image: UIImage? {
            didSet {
                tintImageView.image = image?.withRenderingMode(.alwaysTemplate)
            }
        }

        public override var tintColor: UIColor? {
            didSet {
                setMonochromaticEffect(tintColor: tintColor)
            }
        }

        public override init(frame: CGRect) {
            super.init(frame: frame)
            tintImageView.tintColor = .black
        }

        public override init(image: UIImage?) {
            super.init(image: image)
            tintImageView.image = image?.withRenderingMode(.alwaysTemplate)
            tintImageView.tintColor = .black
        }

        public override init(image: UIImage?, highlightedImage: UIImage?) {
            super.init(image: image, highlightedImage: highlightedImage)
            tintImageView.image = image?.withRenderingMode(.alwaysTemplate)
            tintImageView.tintColor = .black
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            tintImageView.frame = bounds
        }
    }

    // MARK: Public types (preserve existing API surface)

    public enum Style: Equatable {
        case regular
        case clear
        case prominent
    }

    public struct TintColor: Equatable {
        public enum CustomStyle: Equatable {
            case `default`
            case clear
        }

        public enum Kind: Equatable {
            case panel
            case clear
            case custom(style: CustomStyle, color: UIColor)
        }

        public let kind: Kind
        public let innerColor: UIColor?
        public let innerInset: CGFloat

        public init(kind: Kind, innerColor: UIColor? = nil, innerInset: CGFloat = 3.0) {
            self.kind = kind
            self.innerColor = innerColor
            self.innerInset = innerInset
        }
    }

    public enum Shape: Equatable {
        case roundedRect(cornerRadius: CGFloat)
    }

    public struct GlassParams: Equatable {
        public let cornerRadius: CGFloat
        public let keepRoundedCorners: Bool

        public init(cornerRadius: CGFloat = 10.0, keepRoundedCorners: Bool = true) {
            self.cornerRadius = cornerRadius
            self.keepRoundedCorners = keepRoundedCorners
        }
    }

    public struct Params: Equatable {
        public let shape: Shape
        public let isDark: Bool
        public let tintColor: TintColor
        public let isInteractive: Bool
        public let isVisible: Bool
    }

    /// When `true`, always use the legacy CABackdropLayer renderer even on iOS 26+.
    /// Matches `useCustomGlassImpl` debug switch.
    public static var useCustomGlassImpl: Bool = !GlassCompatibility.isLiquidDesignAvailable

    private static let legacyShadowInset: CGFloat = 32.0

    // MARK: Internal state

    private var style: Style

    // Native (iOS 26+) path.
    private let nativeView: UIVisualEffectView?
    private var nativeViewShape: Shape?
    private let nativeParamsView: EffectSettingsContainerView?

    // Legacy path.
    private let legacyView: LegacyGlassBackdropView?
    private let legacyHighlightContainerView: UIView?
    private let foregroundView: UIImageView?
    private let shadowView: UIImageView?

    // Mask for content-driven vibrancy (used by both paths).
    private let maskContainerView: UIView
    public let maskContentView: UIView
    private let contentContainer: GlassContentContainer
    private var innerBackgroundView: UIView?

    public var contentView: UIView {
        if let nativeView {
            return nativeView.contentView
        }
        return contentContainer
    }

    public private(set) var params: Params?

    // Legacy back-compat: expose GlassParams for callers that read it.
    public var glassParams: GlassParams? {
        guard let params else { return nil }
        switch params.shape {
        case let .roundedRect(cornerRadius):
            return GlassParams(cornerRadius: cornerRadius, keepRoundedCorners: true)
        }
    }

    // MARK: Init

    public init(style: Style = .regular) {
        self.style = style

        // Three-way path selection:
        //  1. `useNative` — iOS 26+ with liquid design enabled → `UIGlassEffect`
        //  2. `useSimpleBlur` — iOS 26+ in compat mode OR iOS < 26 (but >= 15)
        //     → plain `UIBlurEffect` on `UIVisualEffectView`. Fast, reliable,
        //     no private APIs. This is the "regular blur" fallback the user
        //     asked for when `UIDesignRequiresCompatibility = YES` is set.
        //  3. `legacy` — CABackdropLayer + manual foreground. Used only if
        //     `useCustomGlassImpl = true` is forced (debug/testing).
        let useNative: Bool
        let useSimpleBlur: Bool
        if GlassBackgroundView.useCustomGlassImpl {
            useNative = false
            useSimpleBlur = false
        } else if GlassCompatibility.isLiquidDesignAvailable {
            useNative = true
            useSimpleBlur = false
        } else {
            useNative = false
            useSimpleBlur = true
        }

        if useNative, #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            effect.isInteractive = false
            let nativeView = UIVisualEffectView(effect: effect)
            self.nativeView = nativeView

            let params = EffectSettingsContainerView(frame: .zero)
            self.nativeParamsView = params
            params.addSubview(nativeView)

            self.legacyView = nil
            self.legacyHighlightContainerView = nil
            self.foregroundView = nil
            self.shadowView = nil
        } else if useSimpleBlur {
            // Plain blur fallback — use a UIVisualEffectView in place of the
            // native `UIGlassEffect`. Routed through `nativeView` so the rest
            // of the layout code can stay style-agnostic.
            let effect = UIBlurEffect(style: .systemMaterial)
            let blurView = UIVisualEffectView(effect: effect)
            self.nativeView = blurView

            let params = EffectSettingsContainerView(frame: .zero)
            self.nativeParamsView = params
            params.addSubview(blurView)

            self.legacyView = nil
            self.legacyHighlightContainerView = nil
            self.foregroundView = nil
            self.shadowView = nil
        } else {
            self.nativeView = nil
            self.nativeParamsView = nil

            self.legacyView = LegacyGlassBackdropView(frame: .zero)
            let highlight = UIView()
            highlight.isUserInteractionEnabled = false
            highlight.clipsToBounds = true
            self.legacyHighlightContainerView = highlight
            self.foregroundView = UIImageView()
            self.shadowView = UIImageView()
        }

        self.maskContainerView = UIView()
        self.maskContainerView.backgroundColor = .white
        if let filter = CALayer.luminanceToAlpha() {
            self.maskContainerView.layer.filters = [filter]
        }

        self.maskContentView = UIView()
        self.maskContainerView.addSubview(self.maskContentView)

        self.contentContainer = GlassContentContainer(maskContentView: self.maskContentView)

        super.init(frame: .zero)

        clipsToBounds = false
        // NOTE: interaction MUST stay enabled so buttons / controls nested
        // inside `contentView` can receive taps. `hitTest` below explicitly
        // filters out the background itself — the glass surface only reports
        // an interactive hit when a child (a real button) claims the touch.
        isUserInteractionEnabled = true

        if let shadowView {
            addSubview(shadowView)
        }
        if let nativeParamsView {
            addSubview(nativeParamsView)
        }
        if let legacyView {
            addSubview(legacyView)
        }
        if let foregroundView {
            addSubview(foregroundView)
            foregroundView.mask = maskContainerView
        }
        addSubview(contentContainer)
        if let legacyHighlightContainerView {
            addSubview(legacyHighlightContainerView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Hit testing

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else {
            return nil
        }
        if let nativeView {
            if let result = nativeView.hitTest(self.convert(point, to: nativeView), with: event) {
                return result
            }
            return nil
        }
        return contentContainer.hitTest(self.convert(point, to: contentContainer), with: event)
    }

    // MARK: Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        if let params {
            switch params.shape {
            case let .roundedRect(cornerRadius):
                innerBackgroundView?.layer.cornerRadius = max(0.0, cornerRadius - params.tintColor.innerInset)
            }
        }
    }

    // MARK: Update

    /// Convenience wrapper. `isDark` is auto-derived from the view's current
    /// `traitCollection` so callers that share one `GlassBackgroundView(style: .regular)`
    /// configuration across multiple places get visually consistent glass —
    /// the previous `isDark: false` hard-code produced inconsistent tints
    /// when some call sites passed explicit `true` and others went through
    /// this short form.
    public func update(size: CGSize, cornerRadius: CGFloat, transition: ContainedViewLayoutTransition) {
        update(
            size: size,
            cornerRadius: cornerRadius,
            isDark: traitCollection.userInterfaceStyle == .dark,
            tintColor: .init(kind: .panel),
            isInteractive: false,
            isVisible: true,
            transition: transition
        )
    }

    public func update(
        size: CGSize,
        cornerRadius: CGFloat,
        isDark: Bool,
        tintColor: TintColor,
        isInteractive: Bool = false,
        isVisible: Bool = true,
        transition: ContainedViewLayoutTransition
    ) {
        let shape: Shape = .roundedRect(cornerRadius: cornerRadius)

        // Native UIGlassEffect pipeline
        if let nativeView, #available(iOS 26.0, *) {
            if nativeView.bounds.size != size || nativeViewShape != shape {
                nativeViewShape = shape
                transition.setCornerRadius(layer: nativeView.layer, cornerRadius: cornerRadius)
                nativeView.layer.masksToBounds = true
                if transition.isAnimated {
                    transition.animateView({ nativeView.frame = CGRect(origin: .zero, size: size) })
                } else {
                    nativeView.frame = CGRect(origin: .zero, size: size)
                }
            }
            // Apply the dark/light override only when it actually changes.
            // Setting it on every update made the glass briefly flicker
            // between styles during rapid layout passes (tab switches in
            // dark mode looked like a black\u2194white flash).
            let targetStyle: UIUserInterfaceStyle = isDark ? .dark : .light
            if nativeView.overrideUserInterfaceStyle != targetStyle {
                nativeView.overrideUserInterfaceStyle = targetStyle
            }
        }

        // Legacy backdrop-blur pipeline
        if let legacyView {
            let legacyStyle: LegacyGlassBackdropView.Style
            switch tintColor.kind {
            case .panel:
                legacyStyle = .normal
            case .clear:
                legacyStyle = .clear
            case let .custom(style, _):
                legacyStyle = style == .clear ? .clear : .normal
            }
            legacyView.update(size: size, cornerRadius: cornerRadius, style: legacyStyle, transition: transition)
            transition.setFrame(view: legacyView, frame: CGRect(origin: .zero, size: size))
            transition.setAlpha(view: legacyView, alpha: isVisible ? 1.0 : 0.0)

            transition.setPosition(view: contentView, position: CGPoint(x: size.width * 0.5, y: size.height * 0.5))
            transition.setBounds(view: contentView, bounds: CGRect(origin: .zero, size: size))
        }

        if let legacyHighlightContainerView {
            transition.setFrame(view: legacyHighlightContainerView, frame: CGRect(origin: .zero, size: size))
            transition.setCornerRadius(layer: legacyHighlightContainerView.layer, cornerRadius: cornerRadius)
        }

        let shadowInset = Self.legacyShadowInset

        // Inner fill overlay
        if let innerColor = tintColor.innerColor {
            let innerFrame = CGRect(origin: .zero, size: size).insetBy(dx: tintColor.innerInset, dy: tintColor.innerInset)
            let innerRadius = min(innerFrame.width, innerFrame.height) * 0.5

            let innerView: UIView
            var innerTransition = transition
            var animateIn = false
            if let current = innerBackgroundView {
                innerView = current
            } else {
                innerView = UIView()
                innerBackgroundView = innerView
                innerTransition = .immediate
                contentView.insertSubview(innerView, at: 0)

                innerView.frame = innerFrame
                innerView.layer.cornerRadius = innerRadius
                animateIn = true
            }

            innerView.backgroundColor = innerColor
            innerTransition.setFrame(view: innerView, frame: innerFrame)
            innerTransition.setCornerRadius(layer: innerView.layer, cornerRadius: innerRadius)

            if animateIn, transition.isAnimated {
                transition.animateAlpha(view: innerView, from: 0.0, to: 1.0)
                transition.animateScale(view: innerView, from: 0.001, to: 1.0)
            }
        } else if let innerView = innerBackgroundView {
            self.innerBackgroundView = nil
            if transition.isAnimated {
                transition.setAlpha(view: innerView, alpha: 0.0, completion: { [weak innerView] _ in
                    innerView?.removeFromSuperview()
                })
                transition.setScale(view: innerView, scale: 0.001)
            } else {
                innerView.removeFromSuperview()
            }
        }

        let params = Params(shape: shape, isDark: isDark, tintColor: tintColor, isInteractive: isInteractive, isVisible: isVisible)
        if self.params != params {
            self.params = params

            let outerCornerRadius: CGFloat
            switch shape {
            case let .roundedRect(cornerRadius):
                outerCornerRadius = cornerRadius
            }

            // Legacy foreground (shadow + border gradient).
            if let shadowView {
                let shadowInnerInset: CGFloat = 0.5
                shadowView.image = generateImage(
                    CGSize(width: shadowInset * 2.0 + outerCornerRadius * 2.0,
                           height: shadowInset * 2.0 + outerCornerRadius * 2.0),
                    rotatedContext: { size, context in
                        context.clear(CGRect(origin: .zero, size: size))

                        context.setFillColor(UIColor.black.cgColor)
                        context.setShadow(offset: CGSize(width: 0.0, height: 1.0), blur: 40.0, color: UIColor(white: 0.0, alpha: 0.04).cgColor)
                        context.fillEllipse(in: CGRect(
                            x: shadowInset + shadowInnerInset,
                            y: shadowInset + shadowInnerInset,
                            width: size.width - shadowInset * 2.0 - shadowInnerInset * 2.0,
                            height: size.height - shadowInset * 2.0 - shadowInnerInset * 2.0
                        ))

                        context.setFillColor(UIColor.clear.cgColor)
                        context.setBlendMode(.copy)
                        context.fillEllipse(in: CGRect(
                            x: shadowInset + shadowInnerInset,
                            y: shadowInset + shadowInnerInset,
                            width: size.width - shadowInset * 2.0 - shadowInnerInset * 2.0,
                            height: size.height - shadowInset * 2.0 - shadowInnerInset * 2.0
                        ))
                    }
                )?.stretchableImage(withLeftCapWidth: Int(shadowInset + outerCornerRadius), topCapHeight: Int(shadowInset + outerCornerRadius))
                transition.setAlpha(view: shadowView, alpha: isVisible ? 1.0 : 0.0)
            }

            if let foregroundView {
                let fillColor: UIColor
                let borderWidthFactor: CGFloat
                switch tintColor.kind {
                case .panel:
                    borderWidthFactor = 1.0
                    if isDark {
                        fillColor = UIColor(white: 1.0, alpha: 1.0).mixedWith(.black, alpha: 1.0 - 0.11).withAlphaComponent(0.85)
                    } else {
                        fillColor = UIColor(white: 1.0, alpha: 0.7)
                    }
                case .clear:
                    borderWidthFactor = 2.0
                    fillColor = UIColor(white: 1.0, alpha: 0.0)
                case let .custom(style, color):
                    fillColor = color
                    borderWidthFactor = style == .clear ? 2.0 : 1.0
                }
                foregroundView.image = Self.generateLegacyGlassImage(
                    size: CGSize(width: outerCornerRadius * 2.0, height: outerCornerRadius * 2.0),
                    inset: shadowInset,
                    borderWidthFactor: borderWidthFactor,
                    isDark: isDark,
                    fillColor: fillColor
                )
                transition.setAlpha(view: foregroundView, alpha: isVisible ? 1.0 : 0.0)
            } else if let nativeParamsView, let nativeView {
                // Native iOS 26 liquid-glass path: set up a proper UIGlassEffect
                // with tint / interactive flag. Skipped when the compat fallback
                // is active (then `nativeView` hosts a plain UIBlurEffect that
                // needs no per-frame updates).
                if GlassCompatibility.isLiquidDesignAvailable, #available(iOS 26.0, *) {
                    var glassEffect: UIGlassEffect?

                    if isVisible {
                        let value: UIGlassEffect
                        switch tintColor.kind {
                        case .panel:
                            value = UIGlassEffect(style: .regular)
                            // Slightly weaker tint so UIGlassEffect's own
                            // material specular stays the dominant effect
                            // and the surface doesn't look painted-on.
                            value.tintColor = isDark
                                ? UIColor(white: 1.0, alpha: 0.015)
                                : UIColor(white: 1.0, alpha: 0.06)
                        case let .custom(style, color):
                            switch style {
                            case .default:
                                value = UIGlassEffect(style: .regular)
                                value.tintColor = color
                            case .clear:
                                value = UIGlassEffect(style: .clear)
                                value.tintColor = color
                            }
                        case .clear:
                            value = UIGlassEffect(style: .clear)
                            value.tintColor = isDark ? UIColor(white: 0.0, alpha: 0.18) : nil
                        }
                        value.isInteractive = params.isInteractive
                        glassEffect = value
                    }

                    if glassEffect == nil {
                        if nativeView.effect is UIGlassEffect {
                            if #available(iOS 26.1, *) {
                                if transition.isAnimated {
                                    transition.animateView({ nativeView.effect = nil })
                                } else {
                                    nativeView.effect = nil
                                }
                            } else {
                                if transition.isAnimated {
                                    transition.animateView({ nativeView.effect = UIVisualEffect() })
                                } else {
                                    nativeView.effect = UIVisualEffect()
                                }
                            }
                        }
                    } else if let desired = glassEffect {
                        if transition.isAnimated {
                            if let current = nativeView.effect as? UIGlassEffect,
                               current.tintColor == desired.tintColor,
                               current.isInteractive == desired.isInteractive {
                                // No change to animate.
                            } else {
                                transition.animateView({ nativeView.effect = desired })
                            }
                        } else {
                            nativeView.effect = desired
                        }
                    }

                    if isDark {
                        nativeParamsView.lumaMin = 0.0
                        nativeParamsView.lumaMax = 0.15
                    } else {
                        nativeParamsView.lumaMin = 0.8
                        nativeParamsView.lumaMax = 0.801
                    }
                } else {
                    // Simple-blur compat path — the UIBlurEffect was set once
                    // in init. Just toggle visibility here.
                    nativeView.alpha = isVisible ? 1.0 : 0.0
                }
            }
        }

        if let nativeParamsView {
            transition.setFrame(view: nativeParamsView, frame: CGRect(origin: .zero, size: size))
        }
        transition.setFrame(view: maskContainerView, frame: CGRect(
            origin: .zero,
            size: CGSize(width: size.width + shadowInset * 2.0, height: size.height + shadowInset * 2.0)
        ))
        transition.setFrame(view: maskContentView, frame: CGRect(x: shadowInset, y: shadowInset, width: size.width, height: size.height))
        if let foregroundView {
            transition.setFrame(view: foregroundView, frame: CGRect(origin: .zero, size: size).insetBy(dx: -shadowInset, dy: -shadowInset))
        }
        if let shadowView {
            transition.setFrame(view: shadowView, frame: CGRect(origin: .zero, size: size).insetBy(dx: -shadowInset, dy: -shadowInset))
        }
        transition.setFrame(view: contentContainer, frame: CGRect(origin: .zero, size: size))
    }

    /// Back-compat shim for callers that used to swap between `.regular` / `.prominent` blur
    /// styles on a single view. In the new pipeline the visual "style" is derived from
    /// `tintColor` passed to `update(...)`, so this just records the preference.
    public func updateStyle(_ style: Style) {
        self.style = style
    }

    // MARK: Static image generators (port of helpers)

    public static func generateLegacyGlassImage(size: CGSize, inset: CGFloat, borderWidthFactor: CGFloat = 1.0, isDark: Bool, fillColor: UIColor) -> UIImage? {
        var size = size
        if size == .zero {
            size = CGSize(width: 2.0, height: 2.0)
        }
        let innerSize = size
        size.width += inset * 2.0
        size.height += inset * 2.0

        return UIGraphicsImageRenderer(size: size).image { ctx in
            let context = ctx.cgContext
            context.clear(CGRect(origin: .zero, size: size))

            // Outer shadow (light).
            func addOuterShadow(position: CGPoint, blur: CGFloat, spread: CGFloat, color: UIColor) {
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                context.saveGState()
                let rect = CGRect(origin: CGPoint(x: inset, y: inset), size: innerSize).insetBy(dx: 0.25, dy: 0.25)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * 0.5).cgPath

                context.setShadow(offset: CGSize(width: position.x, height: position.y), blur: blur + abs(spread), color: color.cgColor)
                context.setFillColor(UIColor.black.withAlphaComponent(1.0).cgColor)
                context.addPath(path)
                context.fillPath()

                let cleanRect = CGRect(origin: CGPoint(x: inset, y: inset), size: innerSize)
                let cleanPath = UIBezierPath(roundedRect: cleanRect, cornerRadius: min(cleanRect.width, cleanRect.height) * 0.5).cgPath
                context.setBlendMode(.copy)
                context.setFillColor(UIColor.clear.cgColor)
                context.addPath(cleanPath)
                context.fillPath()
                context.setBlendMode(.normal)
                context.restoreGState()
                context.endTransparencyLayer()
            }

            addOuterShadow(position: .zero, blur: 30.0, spread: 0.0, color: UIColor(white: 0.0, alpha: 0.045))
            addOuterShadow(position: .zero, blur: 20.0, spread: 0.0, color: UIColor(white: 0.0, alpha: 0.01))

            var hue: CGFloat = 0
            var sat: CGFloat = 0
            var bri: CGFloat = 0
            var a: CGFloat = 0
            fillColor.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &a)
            _ = hue

            let innerImage = UIGraphicsImageRenderer(size: size).image { ictx in
                let ic = ictx.cgContext
                ic.setFillColor(fillColor.cgColor)
                var ellipseRect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                ic.fillEllipse(in: ellipseRect)

                let lineWidth: CGFloat = (isDark ? 0.8 : 0.8) * borderWidthFactor
                let strokeColor: UIColor
                let blendMode: CGBlendMode
                let baseAlpha: CGFloat = isDark ? 0.3 : 0.6

                if sat == 0.0, abs(a - 0.7) < 0.1, !isDark {
                    blendMode = .normal
                    strokeColor = UIColor(white: 1.0, alpha: baseAlpha)
                } else if sat <= 0.3, !isDark {
                    blendMode = .normal
                    strokeColor = UIColor(white: 1.0, alpha: 0.7 * baseAlpha)
                } else if bri >= 0.2 {
                    let maxAlpha: CGFloat = isDark ? 0.7 : 0.8
                    blendMode = .overlay
                    strokeColor = UIColor(white: 1.0, alpha: max(0.5, min(1.0, maxAlpha * sat)) * baseAlpha)
                } else {
                    blendMode = .normal
                    strokeColor = UIColor(white: 1.0, alpha: 0.5 * baseAlpha)
                }

                ic.setStrokeColor(strokeColor.cgColor)
                ellipseRect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                ic.addEllipse(in: ellipseRect)
                ic.clip()

                ellipseRect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5)
                ic.setBlendMode(blendMode)

                let radius = ellipseRect.height * 0.5
                let smallerRadius = radius - lineWidth * 1.33
                ic.move(to: CGPoint(x: ellipseRect.minX, y: ellipseRect.minY + radius))
                ic.addArc(tangent1End: CGPoint(x: ellipseRect.minX, y: ellipseRect.minY), tangent2End: CGPoint(x: ellipseRect.minX + radius, y: ellipseRect.minY), radius: radius)
                ic.addLine(to: CGPoint(x: ellipseRect.maxX - smallerRadius, y: ellipseRect.minY))
                ic.addArc(tangent1End: CGPoint(x: ellipseRect.maxX, y: ellipseRect.minY), tangent2End: CGPoint(x: ellipseRect.maxX, y: ellipseRect.minY + smallerRadius), radius: smallerRadius)
                ic.addLine(to: CGPoint(x: ellipseRect.maxX, y: ellipseRect.maxY - radius))
                ic.addArc(tangent1End: CGPoint(x: ellipseRect.maxX, y: ellipseRect.maxY), tangent2End: CGPoint(x: ellipseRect.maxX - radius, y: ellipseRect.maxY), radius: radius)
                ic.addLine(to: CGPoint(x: ellipseRect.minX + smallerRadius, y: ellipseRect.maxY))
                ic.addArc(tangent1End: CGPoint(x: ellipseRect.minX, y: ellipseRect.maxY), tangent2End: CGPoint(x: ellipseRect.minX, y: ellipseRect.maxY - smallerRadius), radius: smallerRadius)
                ic.closePath()
                ic.strokePath()

                ic.resetClip()
                ic.setBlendMode(.normal)
            }
            innerImage.draw(in: CGRect(origin: .zero, size: size))
        }.stretchableImage(withLeftCapWidth: Int(size.width * 0.5), topCapHeight: Int(size.height * 0.5))
    }
}

// MARK: - GlassBackgroundContainerView (port of UIGlassContainerEffect host)

/// Groups multiple `GlassBackgroundView`s under a shared `UIGlassContainerEffect`
/// so that they merge visually when close together (iOS 26+). Falls back to a
/// plain container view for earlier systems.
public final class GlassBackgroundContainerView: UIView {
    private final class LegacyContentView: UIView {}

    private let legacyView: LegacyContentView?
    private let nativeView: UIVisualEffectView?
    private let nativeParamsView: EffectSettingsContainerView?

    public var contentView: UIView {
        if let nativeView {
            return nativeView.contentView
        }
        return legacyView!
    }

    public init(spacing: CGFloat = 7.0) {
        // Only instantiate `UIGlassContainerEffect` when liquid-glass design
        // is actually active. Under compat mode / legacy OS we fall back to a
        // plain content host — children glass elements provide their own
        // UIBlurEffect-based frost, there's nothing meaningful to merge.
        if GlassCompatibility.isLiquidDesignAvailable, #available(iOS 26.0, *), !GlassBackgroundView.useCustomGlassImpl {
            let effect = UIGlassContainerEffect()
            effect.spacing = spacing
            let nativeView = UIVisualEffectView(effect: effect)
            self.nativeView = nativeView

            let params = EffectSettingsContainerView(frame: .zero)
            self.nativeParamsView = params
            params.addSubview(nativeView)

            self.legacyView = nil
        } else {
            self.nativeView = nil
            self.nativeParamsView = nil
            self.legacyView = LegacyContentView()
        }

        super.init(frame: .zero)

        if let nativeParamsView {
            addSubview(nativeParamsView)
        } else if let legacyView {
            addSubview(legacyView)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else {
            return nil
        }
        for view in contentView.subviews.reversed() {
            if let result = view.hitTest(self.convert(point, to: view), with: event), result.isUserInteractionEnabled {
                return result
            }
        }
        guard let result = contentView.hitTest(point, with: event) else { return nil }
        if result === contentView { return nil }
        return result
    }

    public func update(size: CGSize, isDark: Bool, transition: ContainedViewLayoutTransition) {
        if let nativeView, let nativeParamsView, #available(iOS 26.0, *) {
            let targetStyle: UIUserInterfaceStyle = isDark ? .dark : .light
            if nativeView.overrideUserInterfaceStyle != targetStyle {
                nativeView.overrideUserInterfaceStyle = targetStyle
            }
            if isDark {
                nativeParamsView.lumaMin = 0.0
                nativeParamsView.lumaMax = 0.15
            } else {
                nativeParamsView.lumaMin = 0.8
                nativeParamsView.lumaMax = 0.801
            }
            transition.setFrame(view: nativeParamsView, frame: CGRect(origin: .zero, size: size))

            if transition.isAnimated {
                transition.animateView({ nativeView.frame = CGRect(origin: .zero, size: size) })
            } else {
                nativeView.frame = CGRect(origin: .zero, size: size)
            }
        } else if let legacyView {
            transition.setFrame(view: legacyView, frame: CGRect(origin: .zero, size: size))
        }
    }
}
