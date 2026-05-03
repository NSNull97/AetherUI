import UIKit

/// Configuration for a scroll-edge frost overlay attached to an arbitrary
/// container view. Mirrors the look used by the kit's nav bar / tab bar.
public struct EdgeEffectAttachment {
    public enum Edge {
        case top
        case bottom
        case left
        case right
    }

    /// Which edge of the host view the frost is anchored to. The solid side of
    /// the mask sits at this edge; the transparent end points toward the
    /// opposite side.
    public var edge: Edge
    /// Thickness of the frost overlay (measured perpendicular to `edge`).
    public var thickness: CGFloat
    /// Fade zone in points — distance from the transparent edge over which the
    /// frost ramps from 0 to full. Clamped to `thickness`.
    public var fadeHeight: CGFloat
    /// Optional tint color drawn over the blur (use `nil` or `.clear` for pure
    /// blur). Alpha = `tintAlpha` is applied on top.
    public var tintColor: UIColor?
    /// Alpha of the tint overlay. Ignored when `tintColor` is nil/clear.
    public var tintAlpha: CGFloat
    /// Blur radius (uniform). Convenience for callers that want a single value
    /// — sets both `blurRadiusAtEdge` and `blurRadiusAtFade` to this when used
    /// via the convenience initializer.
    public var blurRadius: CGFloat
    /// Blur radius at the SOLID side (closest to the screen edge). Use
    /// alongside `blurRadiusAtFade` for a true variable-radius gradient
    /// (CAFilter.variableBlur on iOS 26+).
    public var blurRadiusAtEdge: CGFloat
    /// Blur radius at the TRANSPARENT side (closest to the content area).
    public var blurRadiusAtFade: CGFloat

    public init(
        edge: Edge,
        thickness: CGFloat,
        fadeHeight: CGFloat? = nil,
        tintColor: UIColor? = UIColor.systemBackground,
        tintAlpha: CGFloat = 0.86,
        blurRadius: CGFloat = 5.0,
        blurRadiusAtEdge: CGFloat? = nil,
        blurRadiusAtFade: CGFloat? = nil
    ) {
        self.edge = edge
        self.thickness = thickness
        self.fadeHeight = fadeHeight ?? min(48.0, thickness * 0.4)
        self.tintColor = tintColor
        self.tintAlpha = tintAlpha
        self.blurRadius = blurRadius
        self.blurRadiusAtEdge = blurRadiusAtEdge ?? blurRadius
        self.blurRadiusAtFade = blurRadiusAtFade ?? blurRadius
    }
}

private var edgeEffectStoreKey: UInt8 = 0

public extension UIView {
    /// Attach a scroll-edge frost overlay anchored to one edge of the view.
    /// Internally uses the same `EdgeEffectView` as the nav/tab bar. Call
    /// again to update, or pass `nil` to remove.
    ///
    /// Horizontal edges (`.left` / `.right`) are implemented by rotating the
    /// internal `EdgeEffectView` 90°, so the same gradient-masked blur
    /// rendering applies.
    @discardableResult
    func setEdgeEffect(_ attachment: EdgeEffectAttachment?) -> EdgeEffectView? {
        if let store = objc_getAssociatedObject(self, &edgeEffectStoreKey) as? EdgeEffectAttachmentStore {
            store.effect.removeFromSuperview()
            objc_setAssociatedObject(self, &edgeEffectStoreKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        guard let attachment else { return nil }

        let effect = EdgeEffectView()
        effect.isUserInteractionEnabled = false
        addSubview(effect)

        let store = EdgeEffectAttachmentStore(effect: effect, attachment: attachment)
        objc_setAssociatedObject(self, &edgeEffectStoreKey, store, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        store.relayout(in: self)
        setNeedsLayout()
        return effect
    }

    /// Update the already-attached edge effect (no-op if none).
    func updateEdgeEffectLayout() {
        if let store = objc_getAssociatedObject(self, &edgeEffectStoreKey) as? EdgeEffectAttachmentStore {
            store.relayout(in: self)
        }
    }
}

private final class EdgeEffectAttachmentStore {
    let effect: EdgeEffectView
    var attachment: EdgeEffectAttachment

    init(effect: EdgeEffectView, attachment: EdgeEffectAttachment) {
        self.effect = effect
        self.attachment = attachment
    }

    func relayout(in host: UIView) {
        let bounds = host.bounds
        let frame: CGRect
        let internalEdge: EdgeEffectView.Edge
        let rotation: CGFloat

        switch attachment.edge {
        case .top:
            frame = CGRect(x: 0.0, y: 0.0, width: bounds.width, height: attachment.thickness)
            internalEdge = .top
            rotation = 0.0
        case .bottom:
            frame = CGRect(x: 0.0, y: bounds.height - attachment.thickness, width: bounds.width, height: attachment.thickness)
            internalEdge = .bottom
            rotation = 0.0
        case .left:
            // Rotate the underlying EdgeEffectView 90° so the gradient taper
            // runs horizontally. The underlying rendering pipeline remains
            // unchanged — all of the mask / blur code is vertical, we just
            // flip the host view's transform.
            let side = attachment.thickness
            frame = CGRect(x: 0.0, y: 0.0, width: side, height: bounds.height)
            internalEdge = .top
            rotation = -.pi / 2.0
        case .right:
            let side = attachment.thickness
            frame = CGRect(x: bounds.width - side, y: 0.0, width: side, height: bounds.height)
            internalEdge = .top
            rotation = .pi / 2.0
        }

        if rotation != 0.0 {
            let rotated = CGRect(x: frame.midX - frame.height / 2.0, y: frame.midY - frame.width / 2.0, width: frame.height, height: frame.width)
            effect.bounds = CGRect(origin: .zero, size: rotated.size)
            effect.center = CGPoint(x: frame.midX, y: frame.midY)
            effect.transform = CGAffineTransform(rotationAngle: rotation)
        } else {
            effect.transform = .identity
            effect.frame = frame
        }

        effect.update(
            content: attachment.tintColor,
            blur: true,
            alpha: attachment.tintAlpha,
            rect: CGRect(origin: .zero, size: effect.bounds.size),
            edge: internalEdge,
            edgeSize: min(attachment.fadeHeight, effect.bounds.height),
            blurRadiusAtEdge: attachment.blurRadiusAtEdge,
            blurRadiusAtFade: attachment.blurRadiusAtFade,
            transition: .immediate
        )
    }
}
