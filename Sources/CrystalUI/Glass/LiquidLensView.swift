import UIKit

private final class LiquidLensRestingBackgroundView: UIVisualEffectView {
    private var isDarkValue: Bool?

    private static func colorMatrix(isDark: Bool) -> [Float32] {
        if isDark {
            return [
                1.082, -0.113, -0.011, 0.0, 0.135,
                -0.034, 1.003, -0.011, 0.0, 0.135,
                -0.034, -0.113, 1.105, 0.0, 0.135,
                0.0, 0.0, 0.0, 1.0, 0.0
            ]
        } else {
            return [
                1.185, -0.05, -0.005, 0.0, -0.2,
                -0.015, 1.15, -0.005, 0.0, -0.2,
                -0.015, -0.05, 1.195, 0.0, -0.2,
                0.0, 0.0, 0.0, 1.0, 0.0
            ]
        }
    }

    init() {
        super.init(effect: UIBlurEffect(style: .light))

        clipsToBounds = true
        for subview in subviews where String(describing: type(of: subview)).contains("VisualEffectSubview") {
            subview.isHidden = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        update(isDark: traitCollection.userInterfaceStyle == .dark)
    }

    func update(isDark: Bool) {
        guard isDarkValue != isDark else {
            return
        }
        isDarkValue = isDark

        guard let filter = CALayer.colorMatrix() else {
            return
        }

        var matrix = Self.colorMatrix(isDark: isDark)
        filter.setValue(NSValue(bytes: &matrix, objCType: "{CAColorMatrix=ffffffffffffffffffff}"), forKey: "inputColorMatrix")

        if let sublayer = layer.sublayers?.first {
            sublayer.filters = [filter]
            sublayer.isOpaque = false
            sublayer.backgroundColor = nil
            sublayer.setValue(1.0, forKey: "scale")
        }
    }
}

private final class LiquidLensDisplayLinkTarget: NSObject {
    var action: (() -> Void)?

    @objc func step() {
        action?()
    }
}

private final class LiquidLensDisplayLink {
    private let target: LiquidLensDisplayLinkTarget
    private let displayLink: CADisplayLink

    init(action: @escaping () -> Void) {
        let target = LiquidLensDisplayLinkTarget()
        target.action = action
        self.target = target
        self.displayLink = CADisplayLink(target: target, selector: #selector(LiquidLensDisplayLinkTarget.step))
        if #available(iOS 15.0, *) {
            self.displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30.0, maximum: 120.0, preferred: 120.0)
        }
        self.displayLink.add(to: .main, forMode: .common)
    }

    func invalidate() {
        displayLink.invalidate()
    }
}

public final class LiquidLensView: UIView {
    public final class TransitionInfo {
        public let disableAnimationWorkarounds: Bool

        public init(disableAnimationWorkarounds: Bool) {
            self.disableAnimationWorkarounds = disableAnimationWorkarounds
        }
    }

    public enum Kind {
        case externalContainer
        case builtinContainer
        case noContainer
    }

    private struct Params: Equatable {
        let size: CGSize
        let cornerRadius: CGFloat?
        let selectionOrigin: CGPoint
        let selectionSize: CGSize
        let inset: CGFloat
        let liftedInset: CGFloat
        let isDark: Bool
        let isLifted: Bool
        let isCollapsed: Bool
    }

    private struct LensParams: Equatable {
        let baseFrame: CGRect
        let inset: CGFloat
        let liftedInset: CGFloat
        let isLifted: Bool
    }

    private let containerView = UIView()
    private let backgroundContainer: GlassBackgroundContainerView?
    private let genericBackgroundContainer: UIView?
    private let backgroundView: GlassBackgroundView?
    private var lensView: UIView?
    private let liftedContainerView = UIView()
    public let contentView = UIView()
    private let restingBackgroundView = LiquidLensRestingBackgroundView()

    private var legacySelectionView: GlassBackgroundView.ContentImageView?
    private var legacyContentMaskView: UIView?
    private var legacyContentMaskBlobView: UIImageView?
    private var legacyLiftedContentBlobMaskView: UIImageView?

    public var selectedContentView: UIView {
        liftedContainerView
    }

    /// Explicit override for the `isDark` flag. When non-`nil`, wins over
    /// the `isDark:` parameter passed to `update(...)` and pins the lens
    /// tint/tone regardless of caller or system theme. Set once on the
    /// outer component and the lens stays consistent across layout passes
    /// — avoids the subtle-mismatch issue where the lens reads one theme
    /// while its parent glass reads another.
    public var isDarkAppearance: Bool? {
        didSet {
            guard isDarkAppearance != oldValue else { return }
            // Re-apply the last params with the override resolved in.
            if let last = self.params {
                update(params: last, transition: .immediate)
            }
        }
    }

    public var selectionOrigin: CGPoint? {
        params?.selectionOrigin
    }

    public var selectionSize: CGSize? {
        params?.selectionSize
    }

    public private(set) var isAnimating: Bool = false {
        didSet {
            if isAnimating != oldValue {
                onUpdatedIsAnimating?(isAnimating)
            }
        }
    }

    public var onUpdatedIsAnimating: ((Bool) -> Void)?
    public var isLiftedAnimationCompleted: (() -> Void)?

    private var params: Params?
    private var appliedLensParams: LensParams?
    /// Reentrancy guard + queued update. While a lifted-state native
    /// animation is in flight further `updateLens` calls stash their params
    /// here and the alongside-closure re-applies once the animation lands.
    /// Port of `isApplyingLensParams` / `pendingLensParams` from upstream.
    private var isApplyingLensParams: Bool = false
    private var pendingLensParams: LensParams?
    private var nativeLensLiftedState: Bool?
    private var liftedDisplayLink: LiquidLensDisplayLink?

    public init(kind: Kind) {
        switch kind {
        case .builtinContainer:
            self.backgroundContainer = GlassBackgroundContainerView()
            self.genericBackgroundContainer = nil
        case .externalContainer, .noContainer:
            self.backgroundContainer = nil
            self.genericBackgroundContainer = UIView()
        }

        if case .noContainer = kind {
            self.backgroundView = nil
        } else {
            self.backgroundView = GlassBackgroundView()
        }

        super.init(frame: .zero)

        switch kind {
        case .builtinContainer:
            if let backgroundContainer {
                addSubview(backgroundContainer)
                if let backgroundView {
                    backgroundContainer.contentView.addSubview(backgroundView)
                    backgroundView.contentView.addSubview(containerView)
                }
            }
        case .externalContainer, .noContainer:
            if let genericBackgroundContainer {
                addSubview(genericBackgroundContainer)
                if let backgroundView {
                    genericBackgroundContainer.addSubview(backgroundView)
                    backgroundView.contentView.addSubview(containerView)
                } else {
                    genericBackgroundContainer.addSubview(containerView)
                }
            }
        }

        containerView.isUserInteractionEnabled = false

        if #available(iOS 26.0, *), let viewClass = NSClassFromString("_UILiquidLensView") as AnyObject? {
            let allocSelector = NSSelectorFromString("alloc")
            let initSelector = NSSelectorFromString("initWithRestingBackground:")
            if let allocated = viewClass.perform(allocSelector)?.takeUnretainedValue() as AnyObject?,
               let instance = allocated.perform(initSelector, with: UIView())?.takeUnretainedValue() as? UIView {
                lensView = instance
            }
        }

        if let lensView {
            if let backgroundContainer {
                backgroundContainer.layer.zPosition = 1.0
            } else if let genericBackgroundContainer {
                genericBackgroundContainer.layer.zPosition = 1.0
            }
            lensView.layer.zPosition = 10.0

            liftedContainerView.addSubview(restingBackgroundView)
            containerView.addSubview(liftedContainerView)
            containerView.addSubview(lensView)
            containerView.addSubview(contentView)

            if let backgroundContainer {
                setNativeContainer(on: lensView, selectorName: "setLiftedContainerView:", view: backgroundContainer.contentView)
            } else if let genericBackgroundContainer {
                setNativeContainer(on: lensView, selectorName: "setLiftedContainerView:", view: genericBackgroundContainer)
            }
            setNativeContainer(on: lensView, selectorName: "setLiftedContentView:", view: liftedContainerView)
            setNativeContainer(on: lensView, selectorName: "setOverridePunchoutView:", view: contentView)
            setNativeInt(on: lensView, selectorName: "setLiftedContentMode:", value: 1)
            setNativeInt(on: lensView, selectorName: "setStyle:", value: 1)
            setNativeBool(on: lensView, selectorName: "setWarpsContentBelow:", value: true)
            // Match Telegram-iOS LiquidLensView: a soft resting tint (alpha 0.1)
            // so the capsule has a faint visible body even in the non-lifted
            // state. Full transparency made the selection dissolve entirely
            // when the underlying content was low-contrast.
            lensView.setValue(UIColor(white: 0.0, alpha: 0.1), forKey: "restingBackgroundColor")
        } else {
            let legacySelectionView = GlassBackgroundView.ContentImageView()
            self.legacySelectionView = legacySelectionView
            if let backgroundView {
                backgroundView.contentView.insertSubview(legacySelectionView, at: 0)
            } else {
                containerView.insertSubview(legacySelectionView, at: 0)
            }

            let legacyContentMaskView = UIView()
            legacyContentMaskView.backgroundColor = .white
            self.legacyContentMaskView = legacyContentMaskView
            if let filter = CALayer.luminanceToAlpha() {
                legacyContentMaskView.layer.filters = [filter]
            }
            contentView.mask = legacyContentMaskView

            let legacyContentMaskBlobView = UIImageView()
            self.legacyContentMaskBlobView = legacyContentMaskBlobView
            legacyContentMaskView.addSubview(legacyContentMaskBlobView)

            containerView.addSubview(contentView)

            let legacyLiftedContentBlobMaskView = UIImageView()
            self.legacyLiftedContentBlobMaskView = legacyLiftedContentBlobMaskView
            liftedContainerView.mask = legacyLiftedContentBlobMaskView
            containerView.addSubview(liftedContainerView)
        }
    }

    deinit {
        liftedDisplayLink?.invalidate()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func setLiftedContainer(view: UIView) {
        guard let lensView else {
            return
        }
        setNativeContainer(on: lensView, selectorName: "setLiftedContainerView:", view: view)
    }

    public func update(
        size: CGSize,
        cornerRadius: CGFloat? = nil,
        selectionOrigin: CGPoint,
        selectionSize: CGSize,
        inset: CGFloat,
        liftedInset: CGFloat = 4.0,
        isDark: Bool,
        isLifted: Bool,
        isCollapsed: Bool = false,
        transition: ContainedViewLayoutTransition
    ) {
        // `isDarkAppearance` wins over the caller-supplied `isDark` so a
        // consumer can pin the lens theme once and not worry about every
        // call site threading the same value through.
        let resolvedIsDark = isDarkAppearance ?? isDark
        let params = Params(
            size: size,
            cornerRadius: cornerRadius,
            selectionOrigin: selectionOrigin,
            selectionSize: selectionSize,
            inset: inset,
            liftedInset: liftedInset,
            isDark: resolvedIsDark,
            isLifted: isLifted,
            isCollapsed: isCollapsed
        )
        if self.params == params {
            return
        }
        update(params: params, transition: transition)
    }

    private func update(params: Params, transition: ContainedViewLayoutTransition) {
        self.params = params

        let frame = CGRect(origin: .zero, size: params.size)
        transition.updateFrame(view: self, frame: frame)
        transition.updateFrame(view: containerView, frame: frame)

        if let backgroundContainer {
            transition.updateFrame(view: backgroundContainer, frame: frame)
            backgroundContainer.update(size: params.size, isDark: params.isDark, transition: transition)
        } else if let genericBackgroundContainer {
            transition.updateFrame(view: genericBackgroundContainer, frame: frame)
        }

        if let backgroundView {
            transition.updateFrame(view: backgroundView, frame: frame)
            backgroundView.update(
                size: params.size,
                cornerRadius: params.cornerRadius ?? (params.size.height * 0.5),
                isDark: params.isDark,
                tintColor: GlassBackgroundView.TintColor(kind: .panel),
                isInteractive: true,
                isVisible: true,
                transition: transition
            )
        }

        let contentCornerRadius = params.cornerRadius ?? (params.size.height * 0.5)
        transition.updateFrame(view: contentView, frame: frame)
        transition.updateCornerRadius(layer: contentView.layer, cornerRadius: contentCornerRadius)
        transition.updateFrame(view: liftedContainerView, frame: frame)
        transition.updateCornerRadius(layer: liftedContainerView.layer, cornerRadius: contentCornerRadius)

        let lensParams = LensParams(
            baseFrame: CGRect(origin: params.selectionOrigin, size: params.selectionSize),
            inset: params.inset,
            liftedInset: params.liftedInset,
            isLifted: params.isLifted
        )
        updateLens(params: lensParams, transition: transition)
        updateLegacyMasks(params: params, lensParams: lensParams, transition: transition)

        transition.updateFrame(view: restingBackgroundView, frame: frame)
        restingBackgroundView.update(isDark: params.isDark)
        transition.updateAlpha(view: restingBackgroundView, alpha: (params.isLifted || params.isCollapsed) ? 0.0 : 1.0)

        if params.isLifted {
            if liftedDisplayLink == nil {
                liftedDisplayLink = LiquidLensDisplayLink { [weak self] in
                    self?.updateLiftedLensPosition()
                }
            }
        } else {
            liftedDisplayLink?.invalidate()
            liftedDisplayLink = nil
        }
    }

    private func updateLens(params: LensParams, transition: ContainedViewLayoutTransition) {
        guard let lensView else {
            return
        }

        // Queue updates that arrive while a previous lifted-state animation
        // is still in flight — otherwise a fast tap-retap would trample the
        // first animation's callback and leave isApplyingLensParams stuck
        // true. Port of Telegram-iOS LiquidLensView.updateLens (§316-406).
        if isApplyingLensParams {
            pendingLensParams = params
            return
        }
        isApplyingLensParams = true
        let previousParams = appliedLensParams
        appliedLensParams = params

        let liftedInset = params.isLifted ? params.liftedInset : (-params.inset)
        let lensBounds = CGRect(
            origin: .zero,
            size: CGSize(
                width: params.baseFrame.width + liftedInset * 2.0,
                height: params.baseFrame.height + liftedInset * 2.0
            )
        )
        let lensCenter = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)

        if previousParams?.isLifted != params.isLifted {
            isAnimating = transition.isAnimated

            // Go through the private `setLifted:animated:alongsideAnimations:completion:`
            // selector ourselves rather than through the simple wrapper, so
            // the bounds update runs INSIDE the same native animation block
            // as the lift — no desync.
            let selector = NSSelectorFromString("setLifted:animated:alongsideAnimations:completion:")
            var didProcessUpdate = false
            var shouldScheduleUpdate = false
            pendingLensParams = params

            if let method = lensView.method(for: selector) {
                typealias Function = @convention(c) (AnyObject, Selector, Bool, Bool, @escaping () -> Void, (() -> Void)?) -> Void
                let function = unsafeBitCast(method, to: Function.self)
                function(lensView, selector, params.isLifted, transition.isAnimated, { [weak self] in
                    // Alongside closure: resize bounds in lockstep with the
                    // native lift animation. No additive position fix here —
                    // setLifted path lands the center where the native
                    // animation ends anyway.
                    guard let self else { return }
                    lensView.bounds = lensBounds
                    didProcessUpdate = true
                    if shouldScheduleUpdate {
                        DispatchQueue.main.async { [weak self] in
                            guard let self, let pending = self.pendingLensParams else { return }
                            self.isApplyingLensParams = false
                            self.pendingLensParams = nil
                            self.updateLens(params: pending, transition: transition)
                        }
                    }
                }, { [weak self] in
                    guard let self else { return }
                    if !self.isApplyingLensParams {
                        self.isAnimating = false
                    }
                    self.isLiftedAnimationCompleted?()
                })
            } else {
                // Fallback for older iOS / when setLifted isn't available —
                // just set the bounds directly. Matches setNativeLifted's
                // simple-selector path.
                lensView.bounds = lensBounds
                setNativeLifted(on: lensView, value: params.isLifted, animated: transition.isAnimated)
                didProcessUpdate = true
            }

            if didProcessUpdate {
                transition.updatePosition(view: lensView, position: lensCenter)
                pendingLensParams = nil
                isApplyingLensParams = false
            } else {
                // Native method invoked the alongside closure asynchronously —
                // the closure will clear these when it runs.
                shouldScheduleUpdate = true
            }
        } else {
            // Lifted-state unchanged — no native lift animation, just resize
            // + reposition. Needs two workarounds from upstream:
            //   1. removeAllAnimations + direct bounds set: prevents bounds
            //      animations from stacking when the user flicks quickly.
            //   2. additive position animation: CoreAnimation shifts the
            //      layer's render center when bounds width changes, so we
            //      inject a compensating position delta to keep the lens
            //      visually anchored.
            let previousBounds = lensView.bounds
            transition.updateBounds(view: lensView, bounds: lensBounds)
            lensView.layer.removeAllAnimations()
            lensView.bounds = lensBounds

            if transition.isAnimated {
                isAnimating = true
            }
            transition.updatePosition(view: lensView, position: lensCenter)

            if previousBounds.width != lensBounds.width {
                let deltaX = (lensBounds.width - previousBounds.width) * 0.5
                let animation = CABasicAnimation(keyPath: "position")
                animation.fromValue = NSValue(cgPoint: CGPoint(x: deltaX, y: 0.0))
                animation.toValue = NSValue(cgPoint: .zero)
                animation.duration = transition.isAnimated ? transition.duration : 0.2
                animation.isAdditive = true
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                lensView.layer.add(animation, forKey: "additivePositionFix")
            }

            if !transition.isAnimated {
                isAnimating = false
            }
            isApplyingLensParams = false
        }
    }

    private func updateLiftedLensPosition() {
        // Skip while a native-lift animation is mid-flight; the alongside
        // closure owns the lens transform for the duration and our per-frame
        // center write would fight it.
        if isApplyingLensParams { return }
        guard let lensView, let params = appliedLensParams else {
            return
        }
        lensView.center = CGPoint(x: params.baseFrame.midX, y: params.baseFrame.midY)
    }

    private func updateLegacyMasks(params: Params, lensParams: LensParams, transition: ContainedViewLayoutTransition) {
        if let legacyContentMaskView {
            transition.updateFrame(view: legacyContentMaskView, frame: CGRect(origin: .zero, size: params.size))
        }

        guard let legacyContentMaskBlobView,
              let legacyLiftedContentBlobMaskView,
              let legacySelectionView else {
            return
        }

        let lensFrame = lensParams.baseFrame.insetBy(dx: lensParams.inset, dy: lensParams.inset)
        let effectiveLensFrame = lensFrame.insetBy(dx: lensParams.isLifted ? -2.0 : 0.0, dy: lensParams.isLifted ? -2.0 : 0.0)

        if legacyContentMaskBlobView.image?.size.height != lensFrame.height {
            let blobImage = generateStretchableFilledCircleImage(diameter: lensFrame.height, color: .black)
            legacyContentMaskBlobView.image = blobImage
            legacyLiftedContentBlobMaskView.image = blobImage
            legacySelectionView.image = generateStretchableFilledCircleImage(diameter: lensFrame.height, color: .white)?.withRenderingMode(.alwaysTemplate)
        }

        transition.updateFrame(view: legacyContentMaskBlobView, frame: effectiveLensFrame)
        transition.updateFrame(view: legacyLiftedContentBlobMaskView, frame: effectiveLensFrame)
        legacySelectionView.tintColor = UIColor(white: params.isDark ? 1.0 : 0.0, alpha: params.isDark ? 0.1 : 0.075)
        transition.updateFrame(view: legacySelectionView, frame: effectiveLensFrame)
    }

    private func setNativeLifted(on view: UIView, value: Bool, animated: Bool) {
        let complexSelector = NSSelectorFromString("setLifted:animated:alongsideAnimations:completion:")
        if let method = view.method(for: complexSelector) {
            typealias Function = @convention(c) (AnyObject, Selector, Bool, Bool, @escaping () -> Void, (() -> Void)?) -> Void
            let function = unsafeBitCast(method, to: Function.self)
            function(view, complexSelector, value, animated, {}, nil)
            return
        }

        let simpleSelector = NSSelectorFromString("setLifted:")
        if let method = view.method(for: simpleSelector) {
            typealias Function = @convention(c) (AnyObject, Selector, Bool) -> Void
            let function = unsafeBitCast(method, to: Function.self)
            function(view, simpleSelector, value)
        }
    }

    private func setNativeContainer(on view: UIView, selectorName: String, view targetView: UIView) {
        let selector = NSSelectorFromString(selectorName)
        guard view.responds(to: selector) else {
            return
        }
        _ = view.perform(selector, with: targetView)
    }

    private func setNativeBool(on view: UIView, selectorName: String, value: Bool) {
        let selector = NSSelectorFromString(selectorName)
        guard let method = view.method(for: selector) else {
            return
        }
        typealias Function = @convention(c) (AnyObject, Selector, Bool) -> Void
        let function = unsafeBitCast(method, to: Function.self)
        function(view, selector, value)
    }

    private func setNativeInt(on view: UIView, selectorName: String, value: Int32) {
        let selector = NSSelectorFromString(selectorName)
        guard let method = view.method(for: selector) else {
            return
        }
        typealias Function = @convention(c) (AnyObject, Selector, Int32) -> Void
        let function = unsafeBitCast(method, to: Function.self)
        function(view, selector, value)
    }
}

public typealias LiquidGlassView = LiquidLensView
