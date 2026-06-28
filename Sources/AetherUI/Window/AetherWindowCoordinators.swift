import UIKit
import os

public final class AetherStatusBarCoordinator {
    private weak var rootViewController: AetherWindowRootViewController?
    private var currentRequest = AetherStatusBarRequest()

    public init(rootViewController: AetherWindowRootViewController? = nil) {
        self.rootViewController = rootViewController
    }

    public func attach(rootViewController: AetherWindowRootViewController) {
        self.rootViewController = rootViewController
    }

    public func update(request: AetherStatusBarRequest, transition: ContainedViewLayoutTransition) {
        guard currentRequest != request else { return }
        currentRequest = request
        rootViewController?.updateStatusBar(style: request.style, hidden: request.isHidden, transition: transition)
    }
}

public final class AetherSystemGestureCoordinator {
    private weak var rootViewController: AetherWindowRootViewController?
    private var currentEdges: UIRectEdge = []
    private var currentHomeIndicatorHidden = false

    public init(rootViewController: AetherWindowRootViewController? = nil) {
        self.rootViewController = rootViewController
    }

    public func attach(rootViewController: AetherWindowRootViewController) {
        self.rootViewController = rootViewController
    }

    public func update(deferredScreenEdges: UIRectEdge, prefersHomeIndicatorAutoHidden: Bool) {
        if currentEdges != deferredScreenEdges {
            currentEdges = deferredScreenEdges
            rootViewController?.gestureEdges = deferredScreenEdges
        }
        if currentHomeIndicatorHidden != prefersHomeIndicatorAutoHidden {
            currentHomeIndicatorHidden = prefersHomeIndicatorAutoHidden
            rootViewController?.prefersOnScreenNavigationHidden = prefersHomeIndicatorAutoHidden
        }
    }
}

public final class AetherOrientationCoordinator {
    private weak var rootViewController: AetherWindowRootViewController?
    private var currentMask: UIInterfaceOrientationMask

    public init(rootViewController: AetherWindowRootViewController? = nil) {
        self.rootViewController = rootViewController
        self.currentMask = Self.defaultMask()
    }

    public static func defaultMask(userInterfaceIdiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom) -> UIInterfaceOrientationMask {
        userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    public func attach(rootViewController: AetherWindowRootViewController) {
        self.rootViewController = rootViewController
        rootViewController.orientations = currentMask
    }

    public func update(supportedMasks: [UIInterfaceOrientationMask]) {
        let defaultMask = Self.defaultMask()
        var resolved = defaultMask
        for mask in supportedMasks {
            let intersection = resolved.intersection(mask)
            if !intersection.isEmpty {
                resolved = intersection
            }
        }
        if resolved.isEmpty {
            resolved = defaultMask
        }
        guard resolved != currentMask else { return }
        currentMask = resolved
        rootViewController?.orientations = resolved
    }
}

public final class AetherWindowDebugInstrumentation {
    private let log = OSLog(subsystem: "AetherUI", category: "AetherWindow")
    private weak var overlayLabel: UILabel?

    public init() {}

    public func presentationBegin() {
        os_signpost(.begin, log: log, name: "Presentation")
    }

    public func presentationEnd() {
        os_signpost(.end, log: log, name: "Presentation")
    }

    public func layoutUpdated() {
        os_signpost(.event, log: log, name: "Layout")
    }

    public func keyboardFrameUpdated() {
        os_signpost(.event, log: log, name: "KeyboardFrame")
    }

    public func orientationUpdated() {
        os_signpost(.event, log: log, name: "Orientation")
    }

    public func statusBarUpdated() {
        os_signpost(.event, log: log, name: "StatusBar")
    }

    public func installDebugOverlay(in hostView: AetherWindowHostView) {
        hostView.installStructuredContainers()
        let label = UILabel()
        label.numberOfLines = 0
        label.font = UIFont.monospacedSystemFont(ofSize: 11.0, weight: .regular)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        label.layer.cornerRadius = 6.0
        label.layer.masksToBounds = true
        label.frame = CGRect(x: 8.0, y: 48.0, width: 260.0, height: 120.0)
        hostView.debugOverlayContainerView.addSubview(label)
        overlayLabel = label
    }

    public func updateDebugOverlay(
        layout: AetherWindowLayout,
        presentationLevels: [AetherPresentationSurfaceLevel],
        blockedInteractionTokenCount: Int,
        firstResponder: UIView?
    ) {
        overlayLabel?.text = [
            "size: \(Int(layout.size.width))x\(Int(layout.size.height))",
            "orientation: \(layout.orientation?.rawValue ?? 0)",
            "safe: \(Int(layout.safeAreaInsets.top)),\(Int(layout.safeAreaInsets.bottom))",
            "keyboard: \(Int(layout.keyboardHeight))",
            "levels: \(presentationLevels.map { String($0.rawValue) }.joined(separator: ","))",
            "blocks: \(blockedInteractionTokenCount)",
            "first: \(firstResponder.map { String(describing: type(of: $0)) } ?? "nil")"
        ].joined(separator: "\n")
    }
}
