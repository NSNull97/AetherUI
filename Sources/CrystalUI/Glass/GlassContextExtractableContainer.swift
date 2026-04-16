import UIKit

/// State for context extraction animation.
public enum ContextExtractableContainerState {
    case normal
    case extracted(size: CGSize, cornerRadius: CGFloat, animatedIn: Bool)
}

/// Normal state snapshot.
public struct ContextExtractableContainerNormalState {
    public let size: CGSize
    public let cornerRadius: CGFloat

    public init(size: CGSize, cornerRadius: CGFloat) {
        self.size = size
        self.cornerRadius = cornerRadius
    }
}

/// Transition type for context extraction.
public enum ContextExtractableContainerTransition {
    case transition(ContainedViewLayoutTransition)
    case spring(duration: Double, damping: CGFloat)
}

/// Protocol for views that can be extracted into a context menu preview.
public protocol ContextExtractableContainer: UIView {
    var normalState: ContextExtractableContainerNormalState { get }
    var extractableContentView: UIView { get }
    func updateState(state: ContextExtractableContainerState, transition: ContextExtractableContainerTransition, completion: ((Bool) -> Void)?)
}

/// Glass container that supports extraction for context menus.
/// Pure UIKit implementation.
public final class GlassContextExtractableContainerView: UIView, ContextExtractableContainer {
    public let glassBackground: GlassBackgroundView
    private let contentContainerView: UIView
    private let extractedContentView: UIView

    private var currentSize: CGSize = .zero
    private var currentCornerRadius: CGFloat = 0

    public var normalState: ContextExtractableContainerNormalState {
        return ContextExtractableContainerNormalState(size: currentSize, cornerRadius: currentCornerRadius)
    }

    public var extractableContentView: UIView {
        return extractedContentView
    }

    public init(style: GlassBackgroundView.Style = .regular) {
        self.glassBackground = GlassBackgroundView(style: style)
        self.contentContainerView = UIView()
        self.extractedContentView = UIView()

        super.init(frame: .zero)

        addSubview(glassBackground)
        addSubview(contentContainerView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func addContentSubview(_ view: UIView) {
        contentContainerView.addSubview(view)
        extractedContentView.addSubview(view)
    }

    public func update(size: CGSize, cornerRadius: CGFloat, transition: ContainedViewLayoutTransition) {
        self.currentSize = size
        self.currentCornerRadius = cornerRadius

        let frame = CGRect(origin: .zero, size: size)
        glassBackground.update(size: size, cornerRadius: cornerRadius, transition: transition)
        transition.updateFrame(view: glassBackground, frame: frame)
        transition.updateFrame(view: contentContainerView, frame: frame)
        transition.updateFrame(view: extractedContentView, frame: frame)
    }

    public func updateState(state: ContextExtractableContainerState, transition: ContextExtractableContainerTransition, completion: ((Bool) -> Void)?) {
        switch state {
        case .normal:
            let t: ContainedViewLayoutTransition
            switch transition {
            case let .transition(layoutTransition):
                t = layoutTransition
            case let .spring(duration, damping):
                t = .animated(duration: duration, curve: .customSpring(damping: damping, initialVelocity: 0))
            }

            t.updateTransform(view: self, transform: .identity) { finished in
                completion?(finished)
            }

        case let .extracted(size, cornerRadius, _):
            let scale = size.width / max(1, currentSize.width)

            let t: ContainedViewLayoutTransition
            switch transition {
            case let .transition(layoutTransition):
                t = layoutTransition
            case let .spring(duration, damping):
                t = .animated(duration: duration, curve: .customSpring(damping: damping, initialVelocity: 0))
            }

            t.updateTransform(view: self, transform: CGAffineTransform(scaleX: scale, y: scale))
            t.updateCornerRadius(layer: layer, cornerRadius: cornerRadius) { finished in
                completion?(finished)
            }
        }
    }
}
