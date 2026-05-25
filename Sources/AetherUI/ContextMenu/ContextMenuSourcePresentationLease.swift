import UIKit

struct ContextMenuSourceDescriptor {
    let hitView: UIView
    let visualView: UIView
    let sourceFrameInOverlay: CGRect
    let sourceCornerRadius: CGFloat
    let sourceMode: ContextMenuSourceVisualMode

    let makeProxyView: () -> UIView
    let suppressOriginal: (_ suppressed: Bool) -> Void
    let setOriginalInteractionEnabled: (_ enabled: Bool) -> Void
}

final class SourcePresentationLease {
    weak var originalView: UIView?
    weak var hitView: UIView?
    weak var overlayView: UIView?

    let sourceID: AnyHashable
    let proxyView: UIView
    let sourceFrameInOverlay: CGRect

    private let originalAlpha: CGFloat
    private let originalIsHidden: Bool
    private let originalIsUserInteractionEnabled: Bool
    private let originalTransform: CGAffineTransform
    private let hitIsUserInteractionEnabled: Bool?
    private let descriptorSuppressOriginal: (_ suppressed: Bool) -> Void
    private let descriptorSetOriginalInteractionEnabled: (_ enabled: Bool) -> Void
    private var isActive = false
    private var didRestore = false

    convenience init?(
        sourceID: AnyHashable,
        originalView: UIView,
        overlayView: UIView
    ) {
        guard let descriptor = ContextMenuSourceDescriptor(
            sourceID: sourceID,
            hitView: originalView,
            visualView: originalView,
            overlayView: overlayView,
            sourceCornerRadius: originalView.layer.cornerRadius,
            sourceMode: .leasedGlassSource
        ) else {
            return nil
        }
        self.init(sourceID: sourceID, descriptor: descriptor, overlayView: overlayView)
    }

    init?(
        sourceID: AnyHashable,
        descriptor: ContextMenuSourceDescriptor,
        overlayView: UIView
    ) {
        let originalView = descriptor.visualView
        assert(!originalView.isHidden, "Context menu source proxy must not be created from an already-hidden source.")
        let frame = descriptor.sourceFrameInOverlay
        guard SourcePresentationLease.isValidFrame(frame) else {
            assertionFailure("Context menu source frame must be finite and non-empty in overlay coordinates.")
            return nil
        }

        self.sourceID = sourceID
        self.originalView = originalView
        self.hitView = descriptor.hitView
        self.overlayView = overlayView
        self.sourceFrameInOverlay = frame
        self.originalAlpha = originalView.alpha
        self.originalIsHidden = originalView.isHidden
        self.originalIsUserInteractionEnabled = originalView.isUserInteractionEnabled
        self.originalTransform = originalView.transform
        self.hitIsUserInteractionEnabled = descriptor.hitView === originalView ? nil : descriptor.hitView.isUserInteractionEnabled
        self.descriptorSuppressOriginal = descriptor.suppressOriginal
        self.descriptorSetOriginalInteractionEnabled = descriptor.setOriginalInteractionEnabled
        self.proxyView = descriptor.makeProxyView()
        self.proxyView.isUserInteractionEnabled = false
        self.proxyView.frame = frame
        self.proxyView.alpha = 1.0
    }

    func acquire() {
        guard !isActive, let originalView, let overlayView else { return }
        isActive = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        proxyView.layer.removeAllAnimations()
        proxyView.transform = .identity
        proxyView.frame = sourceFrameInOverlay
        proxyView.alpha = 1.0
        proxyView.isUserInteractionEnabled = false
        if proxyView.superview !== overlayView {
            overlayView.addSubview(proxyView)
        }
        overlayView.bringSubviewToFront(proxyView)

        originalView.layer.removeAllAnimations()
        descriptorSuppressOriginal(true)
        descriptorSetOriginalInteractionEnabled(false)
        if let hitView, hitView !== originalView {
            hitView.isUserInteractionEnabled = false
        }
        CATransaction.commit()

        assert(proxyView.superview != nil, "Context menu source proxy must be installed before suppressing the original.")
        assert(originalView.alpha == 0.0 || originalView.isHidden, "Context menu original source must be hidden while a proxy owns it.")
        assert(originalView.isUserInteractionEnabled == false, "Context menu original source must be non-interactive while a proxy owns it.")
    }

    func attachProxy(to container: UIView) {
        guard isActive else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        proxyView.layer.removeAllAnimations()
        proxyView.transform = .identity
        proxyView.alpha = 1.0
        proxyView.frame = container.bounds
        if proxyView.superview !== container {
            container.addSubview(proxyView)
        }
        container.bringSubviewToFront(proxyView)
        CATransaction.commit()
    }

    func suppressOriginal() {
        guard let originalView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        descriptorSuppressOriginal(true)
        descriptorSetOriginalInteractionEnabled(false)
        if let hitView, hitView !== originalView {
            hitView.isUserInteractionEnabled = false
        }
        CATransaction.commit()
    }

    func restoreOriginalIfNeeded() {
        guard !didRestore else { return }
        didRestore = true
        isActive = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        proxyView.layer.removeAllAnimations()
        proxyView.removeFromSuperview()
        proxyView.transform = .identity
        if let originalView, originalView.superview != nil {
            originalView.layer.removeAllAnimations()
            originalView.transform = originalTransform
            descriptorSuppressOriginal(false)
            originalView.isHidden = originalIsHidden
            originalView.alpha = originalAlpha
            descriptorSetOriginalInteractionEnabled(originalIsUserInteractionEnabled)
        }
        if let hitView, hitView !== originalView, let hitIsUserInteractionEnabled {
            hitView.isUserInteractionEnabled = hitIsUserInteractionEnabled
        }
        CATransaction.commit()
    }

    func release() {
        restoreOriginalIfNeeded()
    }

    func cancel() {
        restoreOriginalIfNeeded()
    }

    fileprivate static func makeProxyView(from sourceView: UIView) -> UIView {
        if let snapshot = sourceView.snapshotView(afterScreenUpdates: false) {
            snapshot.frame = CGRect(origin: .zero, size: sourceView.bounds.size)
            return snapshot
        }

        let renderer = UIGraphicsImageRenderer(bounds: sourceView.bounds)
        let image = renderer.image { _ in
            sourceView.drawHierarchy(in: sourceView.bounds, afterScreenUpdates: false)
        }
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        imageView.frame = CGRect(origin: .zero, size: sourceView.bounds.size)
        return imageView
    }

    private static func isValidFrame(_ frame: CGRect) -> Bool {
        frame.width.isFinite && frame.height.isFinite
            && frame.minX.isFinite && frame.minY.isFinite
            && frame.width > 0.0 && frame.height > 0.0
    }
}

extension ContextMenuSourceDescriptor {
    init?(
        sourceID _: AnyHashable,
        hitView: UIView,
        visualView: UIView,
        overlayView: UIView,
        sourceCornerRadius: CGFloat,
        sourceMode: ContextMenuSourceVisualMode
    ) {
        let frame = visualView.convert(visualView.bounds, to: overlayView)
        guard frame.width.isFinite,
              frame.height.isFinite,
              frame.minX.isFinite,
              frame.minY.isFinite,
              frame.width > 0.0,
              frame.height > 0.0 else {
            assertionFailure("Context menu source descriptor frame must be finite and non-empty.")
            return nil
        }

        self.hitView = hitView
        self.visualView = visualView
        self.sourceFrameInOverlay = frame
        self.sourceCornerRadius = sourceCornerRadius
        self.sourceMode = sourceMode
        self.makeProxyView = { [weak visualView] in
            guard let visualView else { return UIView(frame: CGRect(origin: .zero, size: frame.size)) }
            return SourcePresentationLease.makeProxyView(from: visualView)
        }
        self.suppressOriginal = { [weak visualView] suppressed in
            guard let visualView else { return }
            visualView.alpha = suppressed ? 0.0 : 1.0
        }
        self.setOriginalInteractionEnabled = { [weak hitView, weak visualView] enabled in
            visualView?.isUserInteractionEnabled = enabled
            if let hitView, let visualView, hitView !== visualView {
                hitView.isUserInteractionEnabled = enabled
            }
        }
    }
}
