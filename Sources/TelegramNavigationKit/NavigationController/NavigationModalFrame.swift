import UIKit

/// Renders the visual frame (shades + corner masks) for modal presentations.
/// Replaces Telegram's ASDK-based NavigationModalFrame.
public final class NavigationModalFrame: UIView {
    private let topShade = UIView()
    private let leftShade = UIView()
    private let rightShade = UIView()
    private let bottomShade = UIView()

    private let topLeftCorner = UIImageView()
    private let topRightCorner = UIImageView()
    private let bottomLeftCorner = UIImageView()
    private let bottomRightCorner = UIImageView()

    private var currentMaxCornerRadius: CGFloat?
    private var progress: CGFloat = 1.0
    private var additionalProgress: CGFloat = 0.0
    private var validLayout: ContainerViewLayout?

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false

        for shade in [topShade, leftShade, rightShade, bottomShade] {
            shade.backgroundColor = .black
            addSubview(shade)
        }
        for corner in [topLeftCorner, topRightCorner, bottomLeftCorner, bottomRightCorner] {
            addSubview(corner)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.validLayout = layout
        updateShades(layout: layout, progress: 1.0 - self.progress, additionalProgress: self.additionalProgress, transition: transition)
    }

    public func updateDismissal(transition: ContainedViewLayoutTransition, progress: CGFloat, additionalProgress: CGFloat, completion: @escaping () -> Void) {
        self.progress = progress
        self.additionalProgress = additionalProgress

        if let layout = validLayout {
            updateShades(layout: layout, progress: 1.0 - progress, additionalProgress: additionalProgress, transition: transition)
        }
        completion()
    }

    private func updateShades(layout: ContainerViewLayout, progress: CGFloat, additionalProgress: CGFloat, transition: ContainedViewLayoutTransition) {
        let sideInset: CGFloat = 16.0
        var topInset: CGFloat = 0.0
        if let statusBarHeight = layout.statusBarHeight {
            topInset += statusBarHeight
        }
        let additionalTopInset: CGFloat = 10.0

        let contentScale = (layout.size.width - sideInset * 2.0) / layout.size.width
        let bottomInset = layout.size.height - contentScale * layout.size.height - topInset

        let cornerRadius: CGFloat = 38.0
        let initialCornerRadius: CGFloat = layout.safeInsets.top > 0 ? 38.0 : 0.0

        if currentMaxCornerRadius != cornerRadius {
            currentMaxCornerRadius = cornerRadius
            let maxRadius = max(initialCornerRadius, cornerRadius)
            topLeftCorner.image = NavigationModalFrame.generateCornerImage(radius: maxRadius, type: .topLeft)
            topRightCorner.image = NavigationModalFrame.generateCornerImage(radius: maxRadius, type: .topRight)
            bottomLeftCorner.image = NavigationModalFrame.generateCornerImage(radius: maxRadius, type: .bottomLeft)
            bottomRightCorner.image = NavigationModalFrame.generateCornerImage(radius: maxRadius, type: .bottomRight)
        }

        let cornerSize = progress * cornerRadius + (1.0 - progress) * initialCornerRadius
        let cornerSideOffset = progress * sideInset + additionalProgress * sideInset
        let cornerTopOffset = progress * topInset + additionalProgress * additionalTopInset
        let cornerBottomOffset = progress * bottomInset

        transition.updateFrame(view: topLeftCorner, frame: CGRect(x: cornerSideOffset, y: cornerTopOffset, width: cornerSize, height: cornerSize))
        transition.updateFrame(view: topRightCorner, frame: CGRect(x: layout.size.width - cornerSideOffset - cornerSize, y: cornerTopOffset, width: cornerSize, height: cornerSize))
        transition.updateFrame(view: bottomLeftCorner, frame: CGRect(x: cornerSideOffset, y: layout.size.height - cornerBottomOffset - cornerSize, width: cornerSize, height: cornerSize))
        transition.updateFrame(view: bottomRightCorner, frame: CGRect(x: layout.size.width - cornerSideOffset - cornerSize, y: layout.size.height - cornerBottomOffset - cornerSize, width: cornerSize, height: cornerSize))

        let topShadeOffset = progress * topInset + additionalProgress * additionalTopInset
        let bottomShadeOffset = progress * bottomInset
        let leftShadeOffset = progress * sideInset + additionalProgress * sideInset
        let rightShadeWidth = progress * sideInset + additionalProgress * sideInset

        transition.updateFrame(view: topShade, frame: CGRect(x: 0, y: 0, width: layout.size.width, height: topShadeOffset))
        transition.updateFrame(view: bottomShade, frame: CGRect(x: 0, y: layout.size.height - bottomShadeOffset, width: layout.size.width, height: bottomShadeOffset))
        transition.updateFrame(view: leftShade, frame: CGRect(x: 0, y: 0, width: leftShadeOffset, height: layout.size.height))
        transition.updateFrame(view: rightShade, frame: CGRect(x: layout.size.width - rightShadeWidth, y: 0, width: rightShadeWidth, height: layout.size.height))
    }

    // MARK: - Corner Image Generation

    private enum CornerType {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private static func generateCornerImage(radius: CGFloat, type: CornerType) -> UIImage? {
        return generateImage(CGSize(width: radius, height: radius), rotatedContext: { size, context in
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.setBlendMode(.copy)
            context.setFillColor(UIColor.clear.cgColor)

            UIGraphicsPushContext(context)
            let origin: CGPoint
            switch type {
            case .topLeft: origin = .zero
            case .topRight: origin = CGPoint(x: -radius, y: 0)
            case .bottomLeft: origin = CGPoint(x: 0, y: -radius)
            case .bottomRight: origin = CGPoint(x: -radius, y: -radius)
            }
            UIBezierPath(roundedRect: CGRect(origin: origin, size: CGSize(width: radius * 2, height: radius * 2)), cornerRadius: radius).fill()
            UIGraphicsPopContext()
        })
    }
}
