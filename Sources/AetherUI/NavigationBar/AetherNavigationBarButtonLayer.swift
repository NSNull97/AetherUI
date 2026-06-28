import UIKit

internal enum AetherNavigationBarButtonHostingMode {
    case legacyInline
    case separatedLayer
}

internal struct AetherNavigationBarButtonPlacement {
    var id: AnyHashable
    var view: UIView
    var frame: CGRect
    var alpha: CGFloat
    var transform: CGAffineTransform
    var isHidden: Bool
    var zIndex: CGFloat
    var hitTestInsets: UIEdgeInsets
    var accessibilityOrder: Int
    var isUserInteractionEnabled: Bool
    var preservePresentationLayer: Bool

    init(
        id: AnyHashable,
        view: UIView,
        frame: CGRect,
        alpha: CGFloat = 1.0,
        transform: CGAffineTransform = .identity,
        isHidden: Bool = false,
        zIndex: CGFloat = 0.0,
        hitTestInsets: UIEdgeInsets = .zero,
        accessibilityOrder: Int = 0,
        isUserInteractionEnabled: Bool = true,
        preservePresentationLayer: Bool = false
    ) {
        self.id = id
        self.view = view
        self.frame = frame
        self.alpha = alpha
        self.transform = transform
        self.isHidden = isHidden
        self.zIndex = zIndex
        self.hitTestInsets = hitTestInsets
        self.accessibilityOrder = accessibilityOrder
        self.isUserInteractionEnabled = isUserInteractionEnabled
        self.preservePresentationLayer = preservePresentationLayer
    }
}

internal struct AetherNavigationBarButtonTransition {
    enum Mode {
        case immediate
        case existing(ContainedViewLayoutTransition)
    }

    var mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    static func existing(_ transition: ContainedViewLayoutTransition) -> AetherNavigationBarButtonTransition {
        AetherNavigationBarButtonTransition(
            mode: transition.isAnimated ? .existing(transition) : .immediate
        )
    }

    var containedTransition: ContainedViewLayoutTransition {
        switch mode {
        case .immediate:
            return .immediate
        case let .existing(transition):
            return transition
        }
    }
}

internal final class AetherNavigationBarButtonLayer: UIView {
    private var placementsByID: [AnyHashable: AetherNavigationBarButtonPlacement] = [:]
    private var placementOrder: [AnyHashable] = []
    private var explicitAccessibilityElements: [Any]?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        isUserInteractionEnabled = true
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyButtonPlacements(
        _ placements: [AetherNavigationBarButtonPlacement],
        transition: AetherNavigationBarButtonTransition,
        removesMissing: Bool = true
    ) {
        let transition = transition.containedTransition
        let incomingIDs = Set(placements.map(\.id))

        if removesMissing {
            for id in placementOrder where !incomingIDs.contains(id) {
                placementsByID[id]?.view.removeFromSuperview()
                placementsByID[id] = nil
            }
            placementOrder.removeAll { !incomingIDs.contains($0) }
        }

        for placement in placements {
            let applyPlacement = {
                if !self.placementOrder.contains(placement.id) {
                    self.placementOrder.append(placement.id)
                }
                self.placementsByID[placement.id] = placement

                let shouldPreservePresentation = placement.preservePresentationLayer
                Self.reparentPreservingPresentation(
                    view: placement.view,
                    from: placement.view.superview,
                    to: self,
                    targetFrame: placement.frame,
                    preservePresentationLayer: shouldPreservePresentation
                )

                placement.view.layer.zPosition = placement.zIndex
                placement.view.isUserInteractionEnabled = placement.isUserInteractionEnabled
                placement.view.isHidden = placement.isHidden

                transition.updateFrame(view: placement.view, frame: placement.frame)
                transition.updateAlpha(view: placement.view, alpha: placement.alpha)
                transition.updateTransform(view: placement.view, transform: placement.transform)
            }

            if transition.isAnimated {
                applyPlacement()
            } else {
                UIView.performWithoutAnimation {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    applyPlacement()
                    CATransaction.commit()
                }
            }
        }

        setNeedsLayout()
    }

    func removeAllButtonPlacements(detachViews: Bool) {
        if detachViews {
            for id in placementOrder {
                placementsByID[id]?.view.removeFromSuperview()
            }
        }
        placementsByID.removeAll()
        placementOrder.removeAll()
    }

    func removeButtonPlacement(id: AnyHashable, detachView: Bool) {
        if detachView {
            placementsByID[id]?.view.removeFromSuperview()
        }
        placementsByID[id] = nil
        placementOrder.removeAll { $0 == id }
    }

    func morphSourceView(for id: AnyHashable) -> UIView? {
        placementsByID[id]?.view
    }

    func morphTargetView(for id: AnyHashable) -> UIView? {
        placementsByID[id]?.view
    }

    func convertMorphFrame(_ frame: CGRect, from sourceSpace: UIView?, to targetSpace: UIView?) -> CGRect {
        switch (sourceSpace, targetSpace) {
        case let (source?, target?):
            return source.convert(frame, to: target)
        case let (source?, nil):
            return source.convert(frame, to: nil)
        case let (nil, target?):
            return target.convert(frame, from: nil)
        case (nil, nil):
            return frame
        }
    }

    func reparentPreservingPresentation(
        view: UIView,
        from oldParent: UIView?,
        to newParent: UIView,
        targetFrame: CGRect,
        preservePresentationLayer: Bool
    ) {
        Self.reparentPreservingPresentation(
            view: view,
            from: oldParent,
            to: newParent,
            targetFrame: targetFrame,
            preservePresentationLayer: preservePresentationLayer
        )
    }

    static func reparentPreservingPresentation(
        view: UIView,
        from oldParent: UIView?,
        to newParent: UIView,
        targetFrame: CGRect,
        preservePresentationLayer: Bool
    ) {
        guard view.superview !== newParent else {
            return
        }

        let visualFrame: CGRect
        if preservePresentationLayer,
           let oldParent,
           let presentationLayer = view.layer.presentation() {
            visualFrame = oldParent.convert(presentationLayer.frame, to: newParent)
        } else if let oldParent {
            visualFrame = oldParent.convert(view.frame, to: newParent)
        } else {
            visualFrame = targetFrame
        }

        let alpha = view.alpha
        let transform = view.transform
        let isHidden = view.isHidden
        let isUserInteractionEnabled = view.isUserInteractionEnabled

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        newParent.addSubview(view)
        view.frame = visualFrame
        view.alpha = alpha
        view.transform = transform
        view.isHidden = isHidden
        view.isUserInteractionEnabled = isUserInteractionEnabled
        CATransaction.commit()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else {
            return false
        }
        return hitTestCandidatePlacements().contains { placement in
            placementContains(point, placement: placement)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else {
            return nil
        }

        for placement in hitTestCandidatePlacements().reversed() {
            guard placementContains(point, placement: placement) else {
                continue
            }
            let viewPoint = convert(point, to: placement.view)
            if let hitView = placement.view.hitTest(viewPoint, with: event) {
                return hitView
            }
            if placement.view is UIControl || !(placement.view.gestureRecognizers?.isEmpty ?? true) {
                return placement.view
            }
        }
        return nil
    }

    override var accessibilityElements: [Any]? {
        get {
            if let explicitAccessibilityElements {
                return explicitAccessibilityElements
            }
            let elements = accessibilityOrderedPlacements()
                .flatMap { accessibilityElements(in: $0.view) }
            return elements.isEmpty ? nil : elements
        }
        set {
            explicitAccessibilityElements = newValue
        }
    }

    private func hitTestCandidatePlacements() -> [AetherNavigationBarButtonPlacement] {
        placementOrder
            .compactMap { placementsByID[$0] }
            .filter { placement in
                let view = placement.view
                return view.superview === self
                    && !view.isHidden
                    && view.alpha > 0.01
                    && placement.isUserInteractionEnabled
                    && view.isUserInteractionEnabled
            }
            .sorted {
                if $0.zIndex == $1.zIndex {
                    return $0.accessibilityOrder < $1.accessibilityOrder
                }
                return $0.zIndex < $1.zIndex
            }
    }

    private func accessibilityOrderedPlacements() -> [AetherNavigationBarButtonPlacement] {
        placementOrder
            .compactMap { placementsByID[$0] }
            .filter { placement in
                let view = placement.view
                return view.superview === self
                    && !view.isHidden
                    && view.alpha > 0.01
            }
            .sorted { $0.accessibilityOrder < $1.accessibilityOrder }
    }

    private func placementContains(_ point: CGPoint, placement: AetherNavigationBarButtonPlacement) -> Bool {
        let viewPoint = convert(point, to: placement.view)
        let bounds = placement.view.bounds
        let hitBounds = CGRect(
            x: bounds.minX - placement.hitTestInsets.left,
            y: bounds.minY - placement.hitTestInsets.top,
            width: bounds.width + placement.hitTestInsets.left + placement.hitTestInsets.right,
            height: bounds.height + placement.hitTestInsets.top + placement.hitTestInsets.bottom
        )
        return hitBounds.contains(viewPoint)
    }

    private func accessibilityElements(in view: UIView) -> [Any] {
        guard !view.isHidden, view.alpha > 0.01 else {
            return []
        }
        if view.isAccessibilityElement {
            return [view]
        }
        if let elements = view.accessibilityElements, !elements.isEmpty {
            return elements
        }
        return view.subviews.flatMap { accessibilityElements(in: $0) }
    }
}
