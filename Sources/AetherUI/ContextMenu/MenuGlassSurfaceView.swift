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

    public init(isDark: Bool) {
        if GlassCompatibility.isLiquidDesignAvailable, #available(iOS 26.0, *) {
            let v = UIVisualEffectView(effect: SystemGlassEffect.make(isDark: isDark))
            self.nativeView = v
            self.legacyView = nil
        } else {
            let v = LegacyGlassBackdropView(frame: .zero)
            self.nativeView = nil
            self.legacyView = v
        }

        super.init(frame: .zero)

        if let nativeView {
            nativeView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(nativeView)
            // Native: content lives inside the visual effect view's own
            // contentView so the backdrop blur applies to it.
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
            contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.backgroundColor = .clear
            addSubview(contentView)
        }
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
        // The legacy backdrop's blur/colour-matrix filters need to be
        // re-applied on every bounds change, AND its inner `layer.cornerRadius`
        // must follow ours so the rounded clip lines up with whatever
        // corner the caller has set. Use `.immediate` — callers drive
        // their own animation timing (CADisplayLink ticks in the morph
        // hosts), and a nested transition would fight the outer curve.
        if let legacyView {
            legacyView.update(
                size: bounds.size,
                cornerRadius: layer.cornerRadius,
                style: .normal,
                transition: .immediate
            )
        }
    }
}
