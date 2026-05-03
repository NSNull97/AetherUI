import UIKit

// MARK: - LensEffectView

/// AetherUI port of Telegram's `LensTransitionContainerEffectViewImpl`
/// (`ContextControllerActionsStackNode.swift`, lines 1448–1631). Provides the
/// `UIVisualEffectView` whose `UIGlassEffect` corner radius / size is animated
/// along the keyframe arrays produced by `LensTransitionContainer`'s SDF
/// keyframe baker.
///
/// On iOS 26+ the effect uses native `UIGlassEffect` and `cornerConfiguration`
/// (also driving the `UICornerRadius` morph during `animateIn`). On older
/// systems the view degrades silently — the lens transition is a no-op.
public final class LensEffectView: UIView, LensTransitionContainerEffectView {
    public let glassView: UIVisualEffectView
    public let contentView: UIView?

    private var isDarkAppearance: Bool = false

    // MARK: - Init

    public init(contentView: UIView?) {
        self.glassView = UIVisualEffectView()
        self.contentView = contentView

        super.init(frame: CGRect())

        addSubview(self.glassView)
        if let contentView {
            self.glassView.contentView.addSubview(contentView)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Theme

    /// Equivalent of Telegram's `update(theme:)` — flips the `UIGlassEffect`
    /// style between regular/dark to match the surface beneath.
    public func updateAppearance(isDark: Bool) {
        self.isDarkAppearance = isDark
        // Routes through `SystemGlassEffect.make` so the lens picks
        // up `AetherGlassConfig.current.style` like every other
        // glass surface in AetherUI. dark/light differentiation
        // for this surface is driven by `lumaMin/lumaMax` inside
        // `EffectSettingsContainerView`, not by the glass effect.
        self.glassView.effect = SystemGlassEffect.make(isDark: isDark)
    }

    // MARK: - Sized updates (transition-driven)

    public func updateSize(size: CGSize, cornerRadius: CGFloat, transition: ContainedViewLayoutTransition) {
        transition.animateView {
            self.glassView.bounds.size = size
            self.glassView.center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            if #available(iOS 26.0, *) {
                self.glassView.cornerConfiguration = .corners(radius: UICornerRadius(floatLiteral: cornerRadius))
            }
        }
    }

    public func updateSize(size: CGSize, transition: ContainedViewLayoutTransition) {
        transition.setBounds(view: self, bounds: CGRect(origin: .zero, size: size))
        transition.setBounds(view: self.glassView, bounds: CGRect(origin: .zero, size: size))
        transition.setPosition(view: self.glassView, position: CGPoint(x: size.width * 0.5, y: size.height * 0.5))
    }

    public func updatePosition(position: CGPoint, transition: ContainedViewLayoutTransition) {
        transition.setPosition(view: self, position: position)
    }

    // MARK: - Keyframed updates (drive the lens morph)

    public func updateSize(duration: Double, keyframes: [CGSize]) {
        guard keyframes.count >= 2 else {
            if let last = keyframes.last {
                self.bounds.size = last
                self.glassView.bounds.size = last
                self.glassView.center = CGPoint(x: last.width * 0.5, y: last.height * 0.5)
            }
            return
        }
        // Start value
        self.bounds.size = keyframes[0]
        self.glassView.bounds.size = keyframes[0]
        self.glassView.center = CGPoint(x: keyframes[0].width * 0.5, y: keyframes[0].height * 0.5)

        let segmentCount = keyframes.count - 1
        let relativeStep = 1.0 / Double(segmentCount)

        var options: UIView.KeyframeAnimationOptions = [.calculationModeLinear]
        options.insert(UIView.KeyframeAnimationOptions(rawValue: UIView.AnimationOptions.curveLinear.rawValue))
        UIView.animateKeyframes(
            withDuration: duration,
            delay: 0.0,
            options: options,
            animations: {
                for i in 0 ..< segmentCount {
                    let nextSize = keyframes[i + 1]
                    let relativeStartTime = Double(i) * relativeStep
                    let relativeDuration = (i == segmentCount - 1) ? (1.0 - relativeStartTime) : relativeStep
                    UIView.addKeyframe(withRelativeStartTime: relativeStartTime, relativeDuration: relativeDuration) {
                        self.bounds.size = nextSize
                        self.glassView.bounds.size = nextSize
                        self.glassView.center = CGPoint(x: nextSize.width * 0.5, y: nextSize.height * 0.5)
                    }
                }
            },
            completion: nil
        )
    }

    public func updatePosition(duration: Double, keyframes: [CGPoint]) {
        guard keyframes.count >= 2 else {
            if let last = keyframes.last {
                self.center = last
            }
            return
        }
        self.center = keyframes[0]

        let segmentCount = keyframes.count - 1
        let relativeStep = 1.0 / Double(segmentCount)

        var options: UIView.KeyframeAnimationOptions = [.calculationModeLinear]
        options.insert(UIView.KeyframeAnimationOptions(rawValue: UIView.AnimationOptions.curveLinear.rawValue))
        UIView.animateKeyframes(
            withDuration: duration,
            delay: 0.0,
            options: options,
            animations: {
                for i in 0 ..< segmentCount {
                    let nextPosition = keyframes[i + 1]
                    let relativeStartTime = Double(i) * relativeStep
                    let relativeDuration = (i == segmentCount - 1) ? (1.0 - relativeStartTime) : relativeStep
                    UIView.addKeyframe(withRelativeStartTime: relativeStartTime, relativeDuration: relativeDuration) {
                        self.center = nextPosition
                    }
                }
            },
            completion: nil
        )
    }

    public func updateCornerRadius(duration: Double, keyframes: [CGFloat]) {
        guard #available(iOS 26.0, *) else { return }

        guard keyframes.count >= 2 else {
            if let last = keyframes.last {
                self.glassView.cornerConfiguration = .corners(radius: UICornerRadius(floatLiteral: last))
            }
            return
        }
        // Start value
        self.glassView.cornerConfiguration = .corners(radius: UICornerRadius(floatLiteral: keyframes[0]))

        let segmentCount = keyframes.count - 1
        let relativeStep = 1.0 / Double(segmentCount)

        var options: UIView.KeyframeAnimationOptions = [.calculationModeLinear]
        options.insert(UIView.KeyframeAnimationOptions(rawValue: UIView.AnimationOptions.curveLinear.rawValue))
        UIView.animateKeyframes(
            withDuration: duration,
            delay: 0.0,
            options: options,
            animations: {
                for i in 0 ..< segmentCount {
                    let nextValue = keyframes[i + 1]
                    let relativeStartTime = Double(i) * relativeStep
                    let relativeDuration = (i == segmentCount - 1) ? (1.0 - relativeStartTime) : relativeStep
                    UIView.addKeyframe(withRelativeStartTime: relativeStartTime, relativeDuration: relativeDuration) {
                        self.glassView.cornerConfiguration = .corners(radius: UICornerRadius(floatLiteral: nextValue))
                    }
                }
            },
            completion: nil
        )
    }

    public func setTransitionFraction(value: CGFloat, duration: Double) {
        let fraction = max(0.0, min(1.0, value))
        let transition: ContainedViewLayoutTransition =
            duration == 0.0 ? .immediate : .animated(duration: duration, curve: .easeInOut)
        transition.setBlur(layer: self.glassView.contentView.layer, radius: (1.0 - fraction) * 4.0)
        transition.updateAlpha(view: self.glassView.contentView, alpha: fraction)
    }
}
