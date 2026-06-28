import UIKit

public final class AetherChildWindowHostView: UIView, AetherWindowHost {
    public enum SystemUIRouting {
        case localNoop
        case proxyToParent(AetherWindowHost)
    }

    public let presentationContext = AetherPresentationContext()
    public let globalOverlayManager = AetherGlobalOverlayManager()
    public let portalHost = AetherGlobalPortalHost()

    public var systemUIRouting: SystemUIRouting = .localNoop
    public var currentLayout: AetherWindowLayout?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = nil
        presentationContext.containerView = self
        globalOverlayManager.attach(parentController: nil, containerView: self)
        portalHost.frame = bounds
        portalHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(portalHost)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        portalHost.frame = bounds
        let layout = AetherWindowLayout(
            size: bounds.size,
            safeAreaInsets: safeAreaInsets,
            orientation: bounds.width > bounds.height ? .landscapeLeft : .portrait,
            horizontalSizeClass: traitCollection.horizontalSizeClass,
            verticalSizeClass: traitCollection.verticalSizeClass
        )
        updateLayout(layout, transition: .immediate)
    }

    public func updateLayout(_ layout: AetherWindowLayout, transition: ContainedViewLayoutTransition) {
        currentLayout = layout
        presentationContext.updateLayout(layout, transition: transition)
        globalOverlayManager.updateLayout(layout, transition: transition)
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let result = globalOverlayManager.hitTest(point: point, in: self, with: event) {
            return result
        }
        if let result = presentationContext.hitTest(point: point, in: self, with: event) {
            return result
        }
        return super.hitTest(point, with: event)
    }

    public func present(
        _ controller: AetherContainableController,
        on level: AetherPresentationSurfaceLevel,
        blockInteraction: Bool,
        completion: @escaping () -> Void
    ) {
        presentationContext.present(controller, on: level, blockInteraction: blockInteraction, completion: completion)
    }

    public func presentInGlobalOverlay(_ controller: AetherContainableController) {
        globalOverlayManager.present(controller, blockInteraction: false)
    }

    public func presentNative(_ controller: UIViewController) {
        nearestViewController()?.present(controller, animated: true)
    }

    public func addGlobalPortalHostView(sourceView: AetherPortalSourceView) {
        portalHost.addPortal(sourceView: sourceView)
    }

    public func invalidateDeferScreenEdgeGestures() {
        if case let .proxyToParent(parent) = systemUIRouting {
            parent.invalidateDeferScreenEdgeGestures()
        }
    }

    public func invalidatePrefersOnScreenNavigationHidden() {
        if case let .proxyToParent(parent) = systemUIRouting {
            parent.invalidatePrefersOnScreenNavigationHidden()
        }
    }

    public func invalidateSupportedOrientations() {
        if case let .proxyToParent(parent) = systemUIRouting {
            parent.invalidateSupportedOrientations()
        }
    }

    public func cancelInteractiveKeyboardGestures() {
        if case let .proxyToParent(parent) = systemUIRouting {
            parent.cancelInteractiveKeyboardGestures()
        }
    }

    public func forEachController(_ body: (AetherContainableController) -> Void) {
        presentationContext.forEachController(body)
        globalOverlayManager.presentationContext.forEachController(body)
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return nil
    }
}
