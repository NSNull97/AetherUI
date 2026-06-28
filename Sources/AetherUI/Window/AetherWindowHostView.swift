import UIKit

public final class AetherWindowHostView: UIView {
    public enum HitTestPolicy {
        case normal
        case passThroughEmpty
    }

    public let rootContentView = UIView()
    public let presentationContainerView = UIView()
    public let globalOverlayContainerView = UIView()
    public let portalContainerView = UIView()
    public let debugOverlayContainerView = UIView()

    public var hitTestPolicy: HitTestPolicy = .normal
    public var isInteractionBlocked: Bool = false
    public var customHitTest: ((CGPoint, UIEvent?) -> UIView?)?
    public private(set) var usesStructuredContainers = false

    public override var frame: CGRect {
        get {
            super.frame
        }
        set {
            var value = newValue
            value.size.height += value.minY
            value.origin.y = 0.0
            super.frame = value
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func installStructuredContainers() {
        guard !usesStructuredContainers else { return }
        usesStructuredContainers = true

        let ordered = [
            rootContentView,
            presentationContainerView,
            globalOverlayContainerView,
            portalContainerView,
            debugOverlayContainerView
        ]
        for view in ordered {
            view.frame = bounds
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.backgroundColor = nil
            view.isOpaque = false
            addSubview(view)
        }
        portalContainerView.isUserInteractionEnabled = false
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard usesStructuredContainers else { return }
        for view in [
            rootContentView,
            presentationContainerView,
            globalOverlayContainerView,
            portalContainerView,
            debugOverlayContainerView
        ] {
            view.frame = bounds
        }
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isInteractionBlocked, !isHidden, alpha > 0.01, isUserInteractionEnabled else {
            return nil
        }

        if let result = customHitTest?(point, event) {
            return result
        }

        if usesStructuredContainers {
            let ordered = [
                debugOverlayContainerView,
                globalOverlayContainerView,
                presentationContainerView,
                rootContentView
            ]
            for view in ordered where !view.isHidden && view.alpha > 0.01 && view.isUserInteractionEnabled {
                let converted = convert(point, to: view)
                if let result = view.hitTest(converted, with: event) {
                    return result
                }
            }
            return hitTestPolicy == .passThroughEmpty ? nil : super.hitTest(point, with: event)
        }

        let result = super.hitTest(point, with: event)
        if hitTestPolicy == .passThroughEmpty, result === self {
            return nil
        }
        return result
    }

    public override var accessibilityElements: [Any]? {
        get {
            if usesStructuredContainers {
                return [
                    debugOverlayContainerView,
                    globalOverlayContainerView,
                    presentationContainerView,
                    rootContentView
                ].filter { !$0.isHidden && $0.alpha > 0.01 }
            }
            return super.accessibilityElements
        }
        set {
            super.accessibilityElements = newValue
        }
    }
}
