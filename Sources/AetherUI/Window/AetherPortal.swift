import UIKit

public final class AetherPortalSourceView: UIView {
    private final class PortalReference {
        weak var portalView: AetherPortalView?

        init(portalView: AetherPortalView) {
            self.portalView = portalView
        }
    }

    private var portalReferences: [PortalReference] = []
    private weak var globalPortalView: AetherPortalView?

    public var needsGlobalPortal: Bool = false {
        didSet {
            guard needsGlobalPortal != oldValue else { return }
            if needsGlobalPortal {
                alpha = 0.0
                if let windowHost = window as? AetherWindowHost {
                    windowHost.addGlobalPortalHostView(sourceView: self)
                } else if let parentHost = nearestChildWindowHost() {
                    parentHost.addGlobalPortalHostView(sourceView: self)
                }
            } else {
                alpha = 1.0
                globalPortalView?.removeFromSuperview()
                globalPortalView?.disablePortal()
                globalPortalView = nil
            }
        }
    }

    deinit {
        globalPortalView?.disablePortal()
    }

    public func addPortal(_ portalView: AetherPortalView) {
        portalReferences.append(PortalReference(portalView: portalView))
        if window != nil {
            portalView.reloadPortal(sourceView: self)
        }
    }

    public func removePortal(_ portalView: AetherPortalView) {
        portalReferences.removeAll { $0.portalView === portalView }
        portalView.disablePortal()
    }

    func setGlobalPortal(_ portalView: AetherPortalView?) {
        globalPortalView?.disablePortal()
        globalPortalView?.removeFromSuperview()
        globalPortalView = portalView
        if let portalView, window != nil {
            portalView.reloadPortal(sourceView: self)
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        portalReferences.removeAll { $0.portalView == nil }
        for reference in portalReferences {
            reference.portalView?.reloadPortal(sourceView: self)
        }
        if needsGlobalPortal, globalPortalView == nil {
            if let windowHost = window as? AetherWindowHost {
                windowHost.addGlobalPortalHostView(sourceView: self)
            } else if let parentHost = nearestChildWindowHost() {
                parentHost.addGlobalPortalHostView(sourceView: self)
            }
        }
    }

    private func nearestChildWindowHost() -> AetherChildWindowHostView? {
        var current = superview
        while let view = current {
            if let host = view as? AetherChildWindowHostView {
                return host
            }
            current = view.superview
        }
        return nil
    }
}

public final class AetherPortalView: UIView {
    public enum HitTestingPolicy {
        case disabled
        case mirrorSource
        case portalView
    }

    public weak var sourceView: AetherPortalSourceView?
    public var matchesPosition: Bool
    public var matchesTransform: Bool
    public var matchesAlpha: Bool
    public var hitTestingPolicy: HitTestingPolicy

    private weak var snapshotView: UIView?
    private var displayLink: CADisplayLink?

    public init(
        sourceView: AetherPortalSourceView? = nil,
        matchesPosition: Bool = true,
        matchesTransform: Bool = true,
        matchesAlpha: Bool = false,
        hitTestingPolicy: HitTestingPolicy = .disabled
    ) {
        self.matchesPosition = matchesPosition
        self.matchesTransform = matchesTransform
        self.matchesAlpha = matchesAlpha
        self.hitTestingPolicy = hitTestingPolicy
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = nil
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        if let sourceView {
            reloadPortal(sourceView: sourceView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    public func reloadPortal(sourceView: AetherPortalSourceView) {
        self.sourceView = sourceView
        rebuildSnapshot()
        startDisplayLink()
        syncToSource()
    }

    public func disablePortal() {
        sourceView = nil
        snapshotView?.removeFromSuperview()
        snapshotView = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    public func syncToSource() {
        guard let sourceView, let sourceSuperview = sourceView.superview else {
            isHidden = true
            return
        }
        guard let host = superview else {
            return
        }

        isHidden = sourceView.window == nil || sourceView.isHidden
        let rect = sourceSuperview.convert(sourceView.frame, to: host)
        if matchesPosition {
            frame = rect
        } else if bounds.size != sourceView.bounds.size {
            bounds = CGRect(origin: .zero, size: sourceView.bounds.size)
        }
        if matchesTransform {
            transform = sourceView.transform
        }
        if matchesAlpha {
            alpha = sourceView.alpha
        }

        if snapshotView == nil || snapshotView?.bounds.size != sourceView.bounds.size {
            rebuildSnapshot()
        }
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        switch hitTestingPolicy {
        case .disabled:
            return nil
        case .portalView:
            return super.hitTest(point, with: event)
        case .mirrorSource:
            guard let sourceView else { return nil }
            let converted = convert(point, to: sourceView)
            return sourceView.hitTest(converted, with: event)
        }
    }

    private func rebuildSnapshot() {
        snapshotView?.removeFromSuperview()
        guard let sourceView else { return }
        let snapshot = sourceView.snapshotView(afterScreenUpdates: false) ?? fallbackSnapshot(for: sourceView)
        snapshot.frame = boundsForSnapshot(sourceView)
        snapshot.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(snapshot)
        snapshotView = snapshot
    }

    private func boundsForSnapshot(_ sourceView: UIView) -> CGRect {
        CGRect(origin: .zero, size: sourceView.bounds.size)
    }

    private func fallbackSnapshot(for sourceView: UIView) -> UIView {
        let renderer = UIGraphicsImageRenderer(bounds: sourceView.bounds)
        let image = renderer.image { _ in
            sourceView.drawHierarchy(in: sourceView.bounds, afterScreenUpdates: false)
        }
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleToFill
        return imageView
    }

    private func startDisplayLink() {
        displayLink?.invalidate()
        let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    @objc private func displayLinkTick() {
        syncToSource()
    }
}

public final class AetherGlobalPortalHost: UIView {
    private var portalViews: [AetherPortalView] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = nil
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func addPortal(sourceView: AetherPortalSourceView) {
        cleanup()
        guard !portalViews.contains(where: { $0.sourceView === sourceView }) else { return }
        let portal = AetherPortalView(sourceView: sourceView)
        portal.frame = bounds
        portal.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        portalViews.append(portal)
        addSubview(portal)
        sourceView.setGlobalPortal(portal)
    }

    public func removePortal(sourceView: AetherPortalSourceView) {
        if let index = portalViews.firstIndex(where: { $0.sourceView === sourceView }) {
            let portal = portalViews.remove(at: index)
            portal.disablePortal()
            portal.removeFromSuperview()
            sourceView.setGlobalPortal(nil)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        cleanup()
        for portal in portalViews {
            portal.syncToSource()
        }
    }

    private func cleanup() {
        portalViews.removeAll { portal in
            if portal.sourceView == nil {
                portal.removeFromSuperview()
                return true
            }
            return false
        }
    }
}
