import UIKit

/// Protocol for a container that manages minimized (PIP) controllers.
/// Replaces the original MinimizedContainer protocol.
public protocol MinimizedContainerProtocol: UIView {
    var navigationController: AetherNavigationController? { get set }
    var minimizedControllers: [MinimizableController] { get }
    var isExpanded: Bool { get }

    var willMaximize: ((MinimizedContainerProtocol) -> Void)? { get set }
    var willDismiss: ((MinimizedContainerProtocol) -> Void)? { get set }
    var didDismiss: ((MinimizedContainerProtocol) -> Void)? { get set }
    var statusBarStyleUpdated: (() -> Void)? { get set }

    func addController(_ viewController: MinimizableController, topEdgeOffset: CGFloat?, beforeMaximize: @escaping (AetherNavigationController, @escaping () -> Void) -> Void, transition: ContainedViewLayoutTransition)
    func removeController(_ viewController: MinimizableController)
    func maximizeController(_ viewController: MinimizableController, animated: Bool, completion: @escaping (Bool) -> Void)
    func collapse()
    func dismissAll(completion: @escaping () -> Void)

    func updateLayout(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition)
    func collapsedHeight(layout: ContainerViewLayout) -> CGFloat
}

/// Protocol for view controllers that can be minimized (PIP).
public protocol MinimizableController: AetherViewController {
    var minimizedTopEdgeOffset: CGFloat? { get }
    var minimizedBounds: CGRect? { get }
    var isMinimized: Bool { get set }
    var isMinimizable: Bool { get }
    var minimizedIcon: UIImage? { get }
    var minimizedProgress: Float? { get }
    var isFullscreen: Bool { get }

    func requestMinimize(topEdgeOffset: CGFloat?, initialVelocity: CGFloat?)
    func makeContentSnapshotView() -> UIView?
    func prepareContentSnapshotView()
    func resetContentSnapshotView()
    func shouldDismissImmediately() -> Bool
}

/// Default implementations.
public extension MinimizableController {
    var isFullscreen: Bool { return false }
    var minimizedTopEdgeOffset: CGFloat? { return nil }
    var minimizedBounds: CGRect? { return nil }
    var isMinimized: Bool { return false }
    var isMinimizable: Bool { return false }
    var minimizedIcon: UIImage? { return nil }
    var minimizedProgress: Float? { return nil }

    func requestMinimize(topEdgeOffset: CGFloat?, initialVelocity: CGFloat?) {}

    func makeContentSnapshotView() -> UIView? {
        return self.view.snapshotView(afterScreenUpdates: false)
    }

    func prepareContentSnapshotView() {}
    func resetContentSnapshotView() {}
    func shouldDismissImmediately() -> Bool { return true }
}
