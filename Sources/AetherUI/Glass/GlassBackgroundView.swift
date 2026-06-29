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
    private let syntheticStrokeLayer = CAShapeLayer()

    // Legacy path.
    private let legacyView: LegacyGlassBackdropView?
    private let legacyHighlightContainerView: UIView?
    private let foregroundView: UIImageView?
    /// Top-edge specular highlight on the legacy path. Vertical white→
    /// clear gradient sitting above `foregroundView` so even when the
    /// backdrop sample is uniformly white (e.g. plain `systemBackground`
    /// behind the glass) the surface still reads as glass — the
    /// bright top kerb suggests light catching the curved edge of a
    /// material, not a flat opaque pill. Placed in `GlassBackgroundView`
    /// rather than `LegacyGlassBackdropView` because the foreground
    /// image (rendered shadow + border + fill) sits above the backdrop
    /// view; the highlight has to be above THAT to actually be visible.
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

    public func updateStyle(_ style: Style) {
        guard self.style != style else {
            return
        }
        self.style = style
        if let memo = lastUpdateMemo {
            update(
                size: memo.size,
                cornerRadius: memo.cornerRadius,
                isDark: resolvedIsDark,
                tintColor: memo.tintColor,
                isInteractive: memo.isInteractive,
                isVisible: memo.isVisible,
                transition: .immediate
            )
        } else {
            setNeedsLayout()
        }
    }

    public private(set) var params: Params?

    /// When `true` (default) the glass automatically re-applies its last
    /// `update(...)` with an `isDark` value derived from
    /// `traitCollection.userInterfaceStyle` whenever the trait collection
    /// changes. This fixes mixed-tint glass on screens where only some
    /// call sites go through the short-form `update`, and keeps all
    /// GlassBackgroundView instances visually consistent as the system
    /// toggles light/dark. Set to `false` if you want the explicit
    /// `isDark` you passed to update(...) to stay pinned regardless of
    /// trait changes (e.g. a forced-dark glass on a blue custom background).
    public var tracksTraitCollection: Bool = true

    /// Explicit override for the resolved `isDark` value. When non-`nil`
    /// it wins over the trait-collection auto-derivation on every path
    /// that computes dark/light implicitly — the short-form `update(...)`,
    /// `layoutSubviews`-driven auto-update, and `traitCollectionDidChange`.
    /// Leave at `nil` to let the glass follow the system theme.
    ///
    /// Typical use: a glass surface sitting on top of a custom dark
    /// artwork/image, where the system is in light mode but the glass
    /// still needs to render with dark-mode tinting so it reads against
    /// the background. Set once and forget — unlike the `isDark:`
    /// parameter on the full-form `update(...)`, this survives trait
    /// changes.
    public var isDarkOverride: Bool? {
        didSet {
            if isDarkOverride == oldValue { return }
            // Re-apply immediately so an explicit override takes effect
            // without waiting for the next layout pass or trait change.
            guard let memo = lastUpdateMemo else {
                setNeedsLayout()
                return
            }
            update(
                size: memo.size,
                cornerRadius: memo.cornerRadius,
                isDark: resolvedIsDark,
                tintColor: memo.tintColor,
                isInteractive: memo.isInteractive,
                isVisible: memo.isVisible,
                transition: .immediate
            )
        }
    }

    /// `isDarkOverride` if set, otherwise the trait-collection derivation.
    /// Single source of truth for every implicit dark/light computation.
    private var resolvedIsDark: Bool {
        isDarkOverride ?? (traitCollection.userInterfaceStyle == .dark)
    }

    /// Corner radius used by `layoutSubviews`-driven auto-update. `nil`
    /// means "pill" (`bounds.height / 2`). Set via property or via
    /// `update(...)`; the latter also writes this through so subsequent
    /// layout passes respect the explicit value.
    public var glassCornerRadius: CGFloat? {
        didSet { setNeedsLayout() }
    }

    /// Tint color used by `layoutSubviews`-driven auto-update.
    public var glassTintColor: TintColor = .init(kind: .panel) {
        didSet { setNeedsLayout() }
    }

    /// Interactive glass flag used by `layoutSubviews`-driven auto-update.
    /// When true, `UIGlassEffect.isInteractive` is set on iOS 26+ so the
    /// glass shows native elastic deformation on touch. Defaults to `true`
    /// — every `GlassBackgroundView` is interactive by default. Pass
    /// `glassIsInteractive = false` after init to opt a specific surface
    /// out of the deformation.
    public var glassIsInteractive: Bool = true {
        didSet { setNeedsLayout() }
    }

    /// Optional stroke override for the glass outline.
    /// `nil` keeps the automatic fallback: Aether's iOS27 appearance gets a
    /// synthetic hairline only on OS versions before iOS 27, because iOS 27+
    /// provides the native glass outline itself.
    public var strokeAppearance: AetherGlassStrokeAppearance? {
        didSet {
            setNeedsLayout()
        }
    }

    internal var isSyntheticStrokeVisible: Bool {
        !syntheticStrokeLayer.isHidden
    }

    internal var isSyntheticStrokeHostedByNativeEffectView: Bool {
        guard let nativeView else {
            return false
        }
        return syntheticStrokeLayer.superlayer === nativeView.layer
    }

    internal var syntheticStrokeAnimationKeys: [String] {
        syntheticStrokeLayer.animationKeys() ?? []
    }

    /// Install a per-corner shape on the native `UIVisualEffectView` host of
    /// `UIGlassEffect`. Use this instead of a CAShapeLayer mask when the
    /// outline needs different top/bottom radii — the layer mask clips the
    /// interactive elastic deformation so the glass feels stiff, while
    /// `cornerConfiguration` participates in the native shape pipeline and
    /// leaves the effect free to "float" inside its rounded outline.
    /// No-op on iOS < 26 (no native glass).
    /// True when a caller has installed a custom `cornerConfiguration` on
    /// the native glass view. Tracked separately from `nativeView.cornerConfiguration`
    /// because the latter is `nonnull` (always returns a default), so we
    /// can't tell "shape configured" from "default" without a flag.
    private var hasCustomNativeCornerConfiguration: Bool = false

    @available(iOS 26.0, *)
    public func setNativeCornerConfiguration(_ configuration: UICornerConfiguration) {
        guard let nativeView else { return }
        nativeView.cornerConfiguration = configuration
        hasCustomNativeCornerConfiguration = true
        // Drop any prior cornerRadius/masksToBounds — `cornerConfiguration`
        // is the source of truth from now on, and a leftover `masksToBounds`
        // would re-introduce the deformation clipping we're trying to avoid.
        nativeView.layer.masksToBounds = false
        nativeView.layer.cornerRadius = 0.0
        nativeViewShape = nil
    }

    /// Remembers the last `cornerRadius`, `tintColor`, `isInteractive`,
    /// `isVisible` the caller passed to `update(...)`. Referenced by
    /// `traitCollectionDidChange` and `layoutSubviews` to rebuild params.
    private struct UpdateMemo {
        let size: CGSize
        let cornerRadius: CGFloat
        let tintColor: TintColor
        let isInteractive: Bool
        let isVisible: Bool
    }
    private var lastUpdateMemo: UpdateMemo?

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

        // Two-way path selection:
        //  1. `useNative` — iOS 26+ with liquid design enabled → `UIGlassEffect`.
        //  2. `legacy`    — otherwise: `CABackdropLayer` + generated foreground.
        //     Used on iOS < 26 OR whenever `UIDesignRequiresCompatibility = YES`
        //     OR when `useCustomGlassImpl = true` is forced (debug).
        // A previous intermediate `UIBlurEffect` fallback was dropped — the
        // legacy backdrop renders the same shape across every non-liquid OS
        // and keeps theme/tint handling in one code path.
        let useNative: Bool
        if GlassBackgroundView.useCustomGlassImpl {
            useNative = false
        } else if GlassCompatibility.isLiquidDesignAvailable {
            useNative = true
        } else {
            useNative = false
        }

        if useNative, #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            // Match the `glassIsInteractive` default (true) — every
            // `GlassBackgroundView` is interactive at construction time.
            // The `update(...)` path below re-syncs `effect.isInteractive`
            // to the per-instance flag whenever it changes.
            effect.isInteractive = true
            let nativeView = UIVisualEffectView(effect: effect)
            self.nativeView = nativeView

            let params = EffectSettingsContainerView(frame: .zero)
            self.nativeParamsView = params
            params.addSubview(nativeView)

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
        self.maskContainerView.clipsToBounds = true
        if let filter = CALayer.aetherAlphaMaskFilter() {
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
        (nativeView?.layer ?? layer).addSublayer(syntheticStrokeLayer)
        syntheticStrokeLayer.fillColor = UIColor.clear.cgColor
        syntheticStrokeLayer.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Auto-layout
    //
    // GlassBackgroundView can be used two ways:
    //
    //   1. **Explicit** — caller drives everything via `update(...)`. The
    //      memo stored there is what `layoutSubviews` re-applies when
    //      bounds change.
    //
    //   2. **Property-based** — caller sets `glassCornerRadius` /
    //      `glassTintColor` / `glassIsInteractive` on the view (or leaves
    //      them at defaults) and lets the normal UIView layout cycle do
    //      the rest. `layoutSubviews` picks up the current bounds and
    //      re-renders. No explicit `update(...)` call required.
    //
    // Both work side-by-side; an explicit `update(...)` wins over the
    // property defaults (it writes its values into the memo which
    // `layoutSubviews` consults first).

    // MARK: Trait tracking

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard tracksTraitCollection, let memo = lastUpdateMemo else { return }
        // Skip when `isDarkOverride` is pinned — trait changes don't matter
        // then, the override is the source of truth.
        if isDarkOverride != nil { return }
        // Only re-apply if the resolved dark/light style actually changed —
        // avoids unnecessary redraws on e.g. content size category changes.
        let previousStyle = previousTraitCollection?.userInterfaceStyle
        if previousStyle == traitCollection.userInterfaceStyle { return }
        update(
            size: memo.size,
            cornerRadius: memo.cornerRadius,
            isDark: resolvedIsDark,
            tintColor: memo.tintColor,
            isInteractive: memo.isInteractive,
            isVisible: memo.isVisible,
            transition: .immediate
        )
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
            // When the surface is marked interactive, route in-bounds
            // "background" touches (i.e. touches that didn't land on a
            // `contentView` child) to the `UIVisualEffectView` itself.
            // iOS 26's `UIGlassEffect.isInteractive` deformation needs
            // the visual-effect view to receive the touch in order to
            // track finger position and play the liquid warp; the
            // default `UIVisualEffectView.hitTest` returns nil for
            // background touches, so without this the glass never sees
            // them and stays static. Parent gesture recognizers (a
            // search-bar tap, a segment-control scrub) still fire as
            // expected — recognizers walk the ancestor chain regardless
            // of which descendant the hit-test returned.
            if glassIsInteractive, self.point(inside: point, with: event) {
                return nativeView
            }
            return nil
        }
        return contentContainer.hitTest(self.convert(point, to: contentContainer), with: event)
    }

    // MARK: Layout

    public override func layoutSubviews() {
        super.layoutSubviews()

        // Auto-apply on layout if the caller hasn't driven it explicitly via
        // `update(...)` yet, OR the bounds changed since the last update.
        // Lets clients use GlassBackgroundView as a plain auto-layout view
        // without having to manually call `update(size:cornerRadius:...)`
        // on each layout pass.
        let size = bounds.size
        if size.width > 0, size.height > 0 {
            let corner = glassCornerRadius ?? lastUpdateMemo?.cornerRadius ?? (size.height / 2.0)
            let tint = lastUpdateMemo?.tintColor != glassTintColor ? glassTintColor : lastUpdateMemo?.tintColor ?? glassTintColor
            let interactive = lastUpdateMemo?.isInteractive != glassIsInteractive ? glassIsInteractive : lastUpdateMemo?.isInteractive ?? glassIsInteractive
            let visible = lastUpdateMemo?.isVisible ?? true
            update(
                size: size,
                cornerRadius: corner,
                isDark: resolvedIsDark,
                tintColor: tint,
                isInteractive: interactive,
                isVisible: visible,
                transition: .immediate
            )
        }

        if let params {
            switch params.shape {
            case let .roundedRect(cornerRadius):
                innerBackgroundView?.layer.cornerRadius = max(0.0, cornerRadius - params.tintColor.innerInset)
            }
        }
    }

    // MARK: Update

    /// Convenience wrapper. `isDark` is auto-derived — `isDarkOverride` wins
    /// when set, otherwise we fall back to `traitCollection.userInterfaceStyle`.
    /// Callers that share one `GlassBackgroundView(style: .regular)` config
    /// across multiple places get visually consistent glass this way; the
    /// previous `isDark: false` hard-code produced inconsistent tints when
    /// some call sites passed explicit `true` and others went through this
    /// short form.
    public func update(size: CGSize, cornerRadius: CGFloat, transition: ContainedViewLayoutTransition) {
        // Honour `glassIsInteractive` here — callers set the property up
        // front and then drive the size/corner via this short form, so
        // hard-coding `false` would silently override their intent on every
        // layout pass.
        update(
            size: size,
            cornerRadius: cornerRadius,
            isDark: resolvedIsDark,
            tintColor: .init(kind: .panel),
            isInteractive: glassIsInteractive,
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
        // Remember everything except `isDark` so `traitCollectionDidChange`
        // can rebuild the params with a fresh trait-derived isDark.
        self.lastUpdateMemo = UpdateMemo(
            size: size,
            cornerRadius: cornerRadius,
            tintColor: tintColor,
            isInteractive: isInteractive,
            isVisible: isVisible
        )
        let shape: Shape = .roundedRect(cornerRadius: cornerRadius)

        // Native UIGlassEffect pipeline
        if let nativeView, #available(iOS 26.0, *) {
            if nativeView.bounds.size != size || nativeViewShape != shape {
                nativeViewShape = shape
                // When the caller has installed a `cornerConfiguration` on
                // the native view (the modern way to round a glass surface),
                // we leave its shape alone — `masksToBounds=true` clips the
                // interactive elastic deformation inside a hard rounded rect
                // and visibly muffles the "floating" feel of the effect.
                if !hasCustomNativeCornerConfiguration {
                    transition.setCornerRadius(layer: nativeView.layer, cornerRadius: cornerRadius)
                    nativeView.layer.masksToBounds = true
                }
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
//            let targetStyle: UIUserInterfaceStyle = isDark ? .dark : .light
//            if nativeView.overrideUserInterfaceStyle != targetStyle {
//                nativeView.overrideUserInterfaceStyle = targetStyle
//            }
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
                    // Tightened tint alpha so the glass on iOS<26 reads
                    // as actual glass (you see backdrop blur through it),
                    // not a near-opaque white pill on top of the blur.
                    // The original 0.7/0.85 values dialed the foreground
                    // ellipse so high that nothing under the surface was
                    // visible. 0.35 / 0.55 keeps enough whiteness for
                    // contrast against backdrop content but lets the
                    // material breathe.
                    if isDark {
                        fillColor = UIColor(white: 1.0, alpha: 1.0)
                            .mixedWith(.black, alpha: 1.0 - 0.11)
                            .withAlphaComponent(style == .prominent ? 0.68 : 0.55)
                    } else {
                        fillColor = UIColor(white: 1.0, alpha: style == .prominent ? 0.48 : 0.35)
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
            } else if let nativeParamsView, let nativeView, #available(iOS 26.0, *) {
                // Native iOS 26 liquid-glass path: set up a proper UIGlassEffect
                // with tint / interactive flag. `nativeView` is only allocated
                // on this path (legacy takes over when liquid design is off),
                // so no inner OS-gate is needed below.
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
                            ? UIColor(white: 1.0, alpha: style == .prominent ? 0.04 : 0.015)
                            : UIColor(white: 1.0, alpha: style == .prominent ? 0.12 : 0.06)
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
            }
        }

        if let nativeParamsView {
            transition.setFrame(view: nativeParamsView, frame: CGRect(origin: .zero, size: size))
        }
        updateSyntheticStroke(size: size, cornerRadius: cornerRadius, isVisible: isVisible, transition: transition)
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

    private static var shouldUseSyntheticStrokeFallback: Bool {
        if #available(iOS 27.0, *) {
            return false
        }
        return true
    }

    private var resolvedStrokeAppearance: AetherGlassStrokeAppearance {
        if let strokeAppearance {
            return strokeAppearance
        }
        let appearance = AetherAppearance.runtimeCurrent
        guard appearance.style == .iOS27, Self.shouldUseSyntheticStrokeFallback else {
            return .none
        }
        return .hairline(color: appearance.separatorColor, opacity: 0.40)
    }

    private func updateSyntheticStroke(size: CGSize, cornerRadius: CGFloat, isVisible: Bool, transition: ContainedViewLayoutTransition) {
        let previousFrame = syntheticStrokeLayer.presentation()?.frame ?? syntheticStrokeLayer.frame
        let previousPath = syntheticStrokeLayer.presentation()?.path ?? syntheticStrokeLayer.path
        let wasHidden = syntheticStrokeLayer.isHidden

        func applyWithoutImplicitAnimation(_ update: () -> Void) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            update()
            CATransaction.commit()
        }

        guard isVisible, size.width > 0.0, size.height > 0.0 else {
            applyWithoutImplicitAnimation {
                syntheticStrokeLayer.isHidden = true
            }
            return
        }

        switch resolvedStrokeAppearance {
        case .none:
            applyWithoutImplicitAnimation {
                syntheticStrokeLayer.isHidden = true
            }
        case let .hairline(color, opacity):
            let strokeColor = (color ?? .separator)
                .resolvedColor(with: traitCollection)
                .withAlphaComponent(opacity)
            let lineWidth = max(UIScreenPixel, 1.0 / max(UIScreen.main.scale, 1.0))
            let bounds = CGRect(origin: .zero, size: size)
            let rect = bounds.insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5)
            let radius = max(0.0, cornerRadius - lineWidth * 0.5)
            let path = UIBezierPath(
                roundedRect: rect,
                cornerRadius: radius
            ).cgPath

            applyWithoutImplicitAnimation {
                syntheticStrokeLayer.isHidden = false
                syntheticStrokeLayer.frame = bounds
                syntheticStrokeLayer.path = path
                syntheticStrokeLayer.lineWidth = lineWidth
                syntheticStrokeLayer.strokeColor = strokeColor.cgColor
            }

            guard !wasHidden, transition.isAnimated else {
                return
            }
            if case let .animated(duration, curve) = transition {
                let timingFunction = curve.mediaTimingFunction()
                syntheticStrokeLayer.animateFrame(
                    from: previousFrame,
                    to: bounds,
                    duration: duration,
                    timingFunction: timingFunction
                )
                if let previousPath {
                    let animation = CABasicAnimation(keyPath: "path")
                    animation.fromValue = previousPath
                    animation.toValue = path
                    animation.duration = duration
                    animation.timingFunction = timingFunction
                    animation.isRemovedOnCompletion = true
                    animation.fillMode = .forwards
                    animation.aetherPreferHighFrameRate()
                    syntheticStrokeLayer.add(animation, forKey: "path")
                }
            }
        }
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

        clipsToBounds = false
        if let nativeParamsView {
            nativeParamsView.clipsToBounds = false
            nativeView?.clipsToBounds = false
            nativeView?.contentView.clipsToBounds = false
            addSubview(nativeParamsView)
        } else if let legacyView {
            legacyView.clipsToBounds = false
            addSubview(legacyView)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal var isUsingNativeContainerEffect: Bool {
        nativeView != nil
    }

    /// Explicit override for the `isDark` passed to `update(...)`. When
    /// non-`nil`, wins over the caller-supplied value so one container can
    /// be pinned to a specific theme regardless of what per-frame code
    /// threads through `update`. Default `nil` → the caller decides.
    public var isDarkOverride: Bool? {
        didSet {
            if isDarkOverride == oldValue { return }
            if let memo = lastUpdateMemo {
                update(size: memo.size, isDark: resolvedIsDark(passed: memo.isDark), transition: .immediate)
            }
        }
    }

    private struct UpdateMemo {
        let size: CGSize
        let isDark: Bool
    }
    private var lastUpdateMemo: UpdateMemo?

    private func resolvedIsDark(passed: Bool) -> Bool {
        isDarkOverride ?? passed
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
        // Remember the caller-supplied isDark so the `isDarkOverride`
        // setter can re-apply without needing a fresh update() call.
        self.lastUpdateMemo = UpdateMemo(size: size, isDark: isDark)
        let effectiveIsDark = resolvedIsDark(passed: isDark)

        if let nativeView, let nativeParamsView, #available(iOS 26.0, *) {
            let targetStyle: UIUserInterfaceStyle = effectiveIsDark ? .dark : .light
            if nativeView.overrideUserInterfaceStyle != targetStyle {
                nativeView.overrideUserInterfaceStyle = targetStyle
            }
            if effectiveIsDark {
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
