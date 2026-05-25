import UIKit

/// Glass surface used by the context menu and submenu card. Wraps the
/// platform-appropriate backdrop:
///   - iOS 26+ liquid glass → `UIVisualEffectView(UIGlassEffect)`
///   - everything else → `LegacyGlassBackdropView` (CABackdropLayer +
///     colour-matrix saturation), which reads as glass against the
///     background instead of as the dense `UIBlurEffect.systemMaterial`
///     pill that the system shipped pre-26.
///
/// Exposes a `contentView` host with the same contract as
/// `UIVisualEffectView.contentView`, so callers stage their menu rows
/// the same way regardless of which backdrop is active. `layoutSubviews`
/// keeps the legacy backdrop in sync with `layer.cornerRadius` so
/// per-tick corner animations (the morph host updates `layer.cornerRadius`
/// every CADisplayLink frame) propagate to the legacy clip without
/// requiring callers to learn a new API.
public final class MenuGlassSurfaceView: UIView {
    public let contentView = UIView()

    private let nativeView: UIVisualEffectView?
    private let legacyView: LegacyGlassBackdropView?
    private let scatteringView = UIView()
    private let isDark: Bool
    private var glassInteractionTransform: CGAffineTransform = .identity
    private var fallbackInteractionRecognizer: GlassHighlightGestureRecognizer?
    private var surfaceCornerRadius: CGFloat = 0
    var routesTouchesToGlassSurface = false

    public init(isDark: Bool, effectsEnabled: Bool = true) {
        self.isDark = isDark
        if effectsEnabled, GlassCompatibility.isLiquidDesignAvailable, #available(iOS 26.0, *) {
            let v = UIVisualEffectView(effect: SystemGlassEffect.make(isDark: isDark))
            self.nativeView = v
            self.legacyView = nil
        } else if effectsEnabled {
            let v = LegacyGlassBackdropView(frame: .zero)
            self.nativeView = nil
            self.legacyView = v
        } else {
            self.nativeView = nil
            self.legacyView = nil
        }

        super.init(frame: .zero)

        if let nativeView {
            nativeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            nativeView.isUserInteractionEnabled = true
            addSubview(nativeView)
            // Native: content lives in the effect view's content host, same
            // as GlassButton. This keeps menu rows optically owned by the
            // glass surface while UIGlassEffect.isInteractive stretches it.
            scatteringView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scatteringView.isUserInteractionEnabled = false
            nativeView.contentView.addSubview(scatteringView)
            contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.backgroundColor = .clear
            nativeView.contentView.addSubview(contentView)
        } else if let legacyView {
            // Underlay first so it sits BEHIND the backdrop blur. The
            // backdrop's CABackdropLayer samples whatever is below it
            // in the window — including this underlay — so the blur
            // sees a flattened mostly-systemBackground colour instead
            // of the raw vivid pixels of the page below.
            legacyView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(legacyView)
            // Legacy: content sits above the backdrop in the same view
            // hierarchy. `clipsToBounds` on self honours the corner
            // radius callers set via `layer.cornerRadius`.
            scatteringView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scatteringView.isUserInteractionEnabled = false
            addSubview(scatteringView)
            contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.backgroundColor = .clear
            addSubview(contentView)
        } else {
            contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.backgroundColor = .clear
            addSubview(contentView)
        }
        updateMaterialThickness(0.0)
        configureGlassInteraction()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Explicit teardown for the UIGlassEffect carried by `nativeView`
    /// (iOS 26+). Setting `UIVisualEffectView.effect = nil` deregisters
    /// the glass effect from the application's shared
    /// `UIGlassContainerEffect`; without this, our short-lived menu
    /// surfaces leave dangling registrations after `removeFromSuperview`,
    /// and the global container ends up in a state where
    /// `UIGlassEffect.isInteractive` deformation no longer plays on
    /// OTHER glass views in the window. Call before removing the
    /// surface from its superview.
    public func tearDownGlassEffect() {
        if let nativeView, #available(iOS 26.0, *) {
            nativeView.effect = nil
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        nativeView?.frame = bounds
        legacyView?.frame = bounds
        scatteringView.frame = bounds
        contentView.frame = bounds
        let resolvedCornerRadius = surfaceCornerRadius > 0 ? surfaceCornerRadius : layer.cornerRadius
        // The legacy backdrop's blur/colour-matrix filters need to be
        // re-applied on every bounds change, AND its inner `layer.cornerRadius`
        // must follow ours so the rounded clip lines up with whatever
        // corner the caller has set. Use `.immediate` — callers drive
        // their own animation timing (CADisplayLink ticks in the morph
        // hosts), and a nested transition would fight the outer curve.
        if let legacyView {
            legacyView.update(
                size: bounds.size,
                cornerRadius: resolvedCornerRadius,
                style: .normal,
                transition: .immediate
            )
        }
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, self.point(inside: point, with: event) else {
            return nil
        }

        if !routesTouchesToGlassSurface {
            let contentPoint = convert(point, to: contentView)
            if let contentHit = contentView.hitTest(contentPoint, with: event),
               contentHit !== contentView {
                return contentHit
            }
        }

        if let nativeView {
            return nativeView
        }
        if let legacyView {
            return legacyView
        }
        return self
    }

    /// Applies iOS-style interactive stretch to the glass shell while
    /// counter-transforming menu content. The pressed menu should feel soft
    /// as a surface, but row labels/icons must not zoom under the finger.
    func setGlassInteractionTransform(_ transform: CGAffineTransform) {
        glassInteractionTransform = transform
        self.transform = transform

        let scaleX = max(0.001, hypot(transform.a, transform.c))
        let scaleY = max(0.001, hypot(transform.b, transform.d))
        contentView.transform = transform.isIdentity
            ? .identity
            : CGAffineTransform(scaleX: 1.0 / scaleX, y: 1.0 / scaleY)
    }

    func resetGlassInteractionTransform() {
        setGlassInteractionTransform(.identity)
    }

    func setSurfaceCornerRadius(_ radius: CGFloat) {
        let clampedRadius = max(0, radius)
        surfaceCornerRadius = clampedRadius
        if #available(iOS 26.0, *), let nativeView {
            cornerConfiguration = UICornerConfiguration.uniformCorners(radius: .fixed(clampedRadius))
            clipsToBounds = false
            layer.cornerRadius = 0
            layer.masksToBounds = false

            nativeView.cornerConfiguration = UICornerConfiguration.uniformCorners(radius: .fixed(clampedRadius))
            nativeView.clipsToBounds = false
            nativeView.layer.cornerRadius = 0
            nativeView.layer.masksToBounds = false

            scatteringView.applyCornerRadius(clampedRadius, clipsChildren: true)
            contentView.applyCornerRadius(clampedRadius, clipsChildren: true)
        } else {
            layer.cornerRadius = clampedRadius
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
            scatteringView.layer.cornerRadius = clampedRadius
            scatteringView.layer.cornerCurve = .continuous
            scatteringView.layer.masksToBounds = true
            contentView.layer.cornerRadius = clampedRadius
            contentView.layer.cornerCurve = .continuous
            contentView.layer.masksToBounds = true
        }
        legacyView?.update(
            size: bounds.size,
            cornerRadius: clampedRadius,
            style: .normal,
            transition: .immediate
        )
    }

    private func configureGlassInteraction() {
        if #available(iOS 26.0, *) {
            nativeView?.isUserInteractionEnabled = true
            if let effect = nativeView?.effect as? UIGlassEffect {
                effect.isInteractive = true
            }
            fallbackInteractionRecognizer?.isEnabled = false
            return
        }

        guard fallbackInteractionRecognizer == nil, let legacyView else { return }
        let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
        // Legacy fallback intentionally targets only the glass backdrop.
        // Rows and labels stay visually stable while the container material
        // gets the Telegram-style stretch/highlight response.
        elastic.touchEffectView = legacyView
        elastic.highlightContainerView = legacyView
        elastic.parameters.pressedSizeIncrease = 12.0
        addGestureRecognizer(elastic)
        fallbackInteractionRecognizer = elastic
    }

    func updateMaterialThickness(_ progress: CGFloat) {
        let t = max(0.0, min(1.0, progress))
        let baseAlpha: CGFloat = isDark ? 0.015 : 0.025
        let peakAlpha: CGFloat = isDark ? 0.085 : 0.115
        scatteringView.backgroundColor = UIColor.white.withAlphaComponent(baseAlpha + (peakAlpha - baseAlpha) * t)
    }
}
