import UIKit

/// Side used by Telegram-style list swipe actions.
public enum AetherListSwipeActionsSide: Equatable {
    case left
    case right
}

/// A single action displayed behind a row while it is swiped horizontally.
public struct AetherListSwipeAction: Equatable {
    public enum Icon: Equatable {
        case none
        case image(UIImage)

        public static func == (lhs: Icon, rhs: Icon) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none):
                return true
            case let (.image(lhsImage), .image(rhsImage)):
                return lhsImage === rhsImage || lhsImage == rhsImage
            default:
                return false
            }
        }
    }

    public let key: AnyHashable
    public let title: String
    public let icon: Icon
    public let backgroundColor: UIColor
    public let foregroundColor: UIColor
    public let textColor: UIColor?
    public let accessibilityLabel: String?

    public init(
        key: AnyHashable,
        title: String,
        icon: Icon = .none,
        backgroundColor: UIColor,
        foregroundColor: UIColor = .white,
        textColor: UIColor? = nil,
        accessibilityLabel: String? = nil
    ) {
        self.key = key
        self.title = title
        self.icon = icon
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.textColor = textColor
        self.accessibilityLabel = accessibilityLabel
    }

    public static func == (lhs: AetherListSwipeAction, rhs: AetherListSwipeAction) -> Bool {
        lhs.key == rhs.key
            && lhs.title == rhs.title
            && lhs.icon == rhs.icon
            && lhs.backgroundColor.isEqual(rhs.backgroundColor)
            && lhs.foregroundColor.isEqual(rhs.foregroundColor)
            && optionalColorsEqual(lhs.textColor, rhs.textColor)
            && lhs.accessibilityLabel == rhs.accessibilityLabel
    }
}

private func optionalColorsEqual(_ lhs: UIColor?, _ rhs: UIColor?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
        return true
    case let (.some(lhs), .some(rhs)):
        return lhs.isEqual(rhs)
    default:
        return false
    }
}

/// Left and right swipe actions for a list item.
public struct AetherListSwipeActions: Equatable {
    public var left: [AetherListSwipeAction]
    public var right: [AetherListSwipeAction]

    public init(left: [AetherListSwipeAction] = [], right: [AetherListSwipeAction] = []) {
        self.left = left
        self.right = right
    }

    public static let none = AetherListSwipeActions()

    public var isEmpty: Bool {
        left.isEmpty && right.isEmpty
    }

    public func actions(for side: AetherListSwipeActionsSide) -> [AetherListSwipeAction] {
        switch side {
        case .left:
            return left
        case .right:
            return right
        }
    }
}

internal final class AetherListSwipeGestureRecognizer: UIPanGestureRecognizer {
    var validatedGesture = false
    var firstLocation: CGPoint = .zero
    var allowAnyDirection = false
    var lastGestureVelocity: CGPoint = .zero

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        if #available(iOS 13.4, *) {
            allowedScrollTypesMask = .continuous
        }
        maximumNumberOfTouches = 1
    }

    override func reset() {
        super.reset()
        validatedGesture = false
        lastGestureVelocity = .zero
    }

    func becomeCancelled() {
        state = .cancelled
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first {
            firstLocation = touch.location(in: view)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else {
            super.touchesMoved(touches, with: event)
            return
        }

        let location = touch.location(in: view)
        let translation = CGPoint(x: location.x - firstLocation.x, y: location.y - firstLocation.y)

        if !validatedGesture {
            if !allowAnyDirection && translation.x > 0.0 {
                state = .failed
            } else if abs(translation.y) > 4.0 && abs(translation.y) > abs(translation.x) * 2.5 {
                state = .failed
            } else if abs(translation.x) > 4.0 && abs(translation.y) * 2.5 < abs(translation.x) {
                validatedGesture = true
            }
        }

        if validatedGesture {
            lastGestureVelocity = velocity(in: view)
            super.touchesMoved(touches, with: event)
        }
    }
}

private let aetherSwipeTitleFont = UIFont.systemFont(ofSize: 11.0, weight: .regular)
private let aetherSwipeIconlessTitleFont = UIFont.systemFont(ofSize: 13.0, weight: .regular)
private let aetherSwipeSpacing: CGFloat = 10.0
private let aetherSwipeEdgeInset: CGFloat = 10.0
private let aetherSwipeTitleSpacing: CGFloat = 4.0
private let aetherSwipeRevealStartOverlap: CGFloat = 12.0
private let aetherSwipeRevealEndDistance: CGFloat = 10.0
private let aetherSwipeExpandedActivationWidthFactor: CGFloat = 3.0
private let aetherSwipeExpandedTransitionDistance: CGFloat = 16.0
private let aetherSwipeIconlessTitleExpandedHorizontalPadding: CGFloat = 8.0
private let aetherSwipeIconlessTitleHorizontalPadding: CGFloat = 8.0

private func aetherSwipeClampToUnitInterval(_ value: CGFloat) -> CGFloat {
    max(0.0, min(1.0, value))
}

private func aetherSwipeFloorToScreenPixels(_ value: CGFloat) -> CGFloat {
    let scale = UIScreen.main.scale
    return floor(value * scale) / scale
}

internal func aetherListBoundedSwipeOffset(
    _ offset: CGFloat,
    revealWidth: CGFloat,
    viewportWidth: CGFloat
) -> CGFloat {
    guard revealWidth > 0.0 else {
        return 0.0
    }

    let sign: CGFloat = offset < 0.0 ? -1.0 : 1.0
    let distance = abs(offset)
    if distance <= revealWidth {
        return offset
    }

    let overswipe = distance - revealWidth
    let maxOverswipe = min(max(108.0, revealWidth * 0.6), max(112.0, viewportWidth * 0.32))
    let boundedOverswipe = min(maxOverswipe, overswipe * 0.35)
    return sign * (revealWidth + boundedOverswipe)
}

private extension AetherListSwipeAction.Icon {
    var hasVisualIcon: Bool {
        switch self {
        case .none:
            return false
        case .image:
            return true
        }
    }
}

private struct AetherListSwipeOptionLayoutMetrics: Equatable {
    let shapeSize: CGSize
    let slotWidth: CGFloat
    let titleWidth: CGFloat
    let iconMaxSide: CGFloat
    let cornerRadius: CGFloat
    let expandedIconInset: CGFloat

    var slotShapeInset: CGFloat {
        aetherSwipeFloorToScreenPixels((slotWidth - shapeSize.width) / 2.0)
    }

    static func metrics(for height: CGFloat, hasVisualIcons: Bool) -> AetherListSwipeOptionLayoutMetrics {
        let regularShapeSize = CGSize(width: 50.0, height: 50.0)
        let compactShapeSize = CGSize(width: 60.0, height: 32.0)
        let regularContentHeight = regularShapeSize.height + aetherSwipeTitleSpacing + ceil(aetherSwipeTitleFont.lineHeight)
        if height < regularContentHeight || !hasVisualIcons {
            return AetherListSwipeOptionLayoutMetrics(
                shapeSize: compactShapeSize,
                slotWidth: 70.0,
                titleWidth: 70.0,
                iconMaxSide: 24.0,
                cornerRadius: 16.0,
                expandedIconInset: 16.0
            )
        } else {
            return AetherListSwipeOptionLayoutMetrics(
                shapeSize: regularShapeSize,
                slotWidth: 60.0,
                titleWidth: 60.0,
                iconMaxSide: 40.0,
                cornerRadius: 25.0,
                expandedIconInset: 20.0
            )
        }
    }

    func withGroupTitleWidth(_ maxTitleWidth: CGFloat) -> AetherListSwipeOptionLayoutMetrics {
        if maxTitleWidth <= shapeSize.width - aetherSwipeIconlessTitleExpandedHorizontalPadding {
            return self
        }

        let updatedShapeWidth = ceil(maxTitleWidth + aetherSwipeIconlessTitleExpandedHorizontalPadding)
        let slotWidthDelta = slotWidth - shapeSize.width
        return AetherListSwipeOptionLayoutMetrics(
            shapeSize: CGSize(width: updatedShapeWidth, height: shapeSize.height),
            slotWidth: updatedShapeWidth + slotWidthDelta,
            titleWidth: max(titleWidth, updatedShapeWidth - aetherSwipeIconlessTitleExpandedHorizontalPadding),
            iconMaxSide: iconMaxSide,
            cornerRadius: cornerRadius,
            expandedIconInset: expandedIconInset
        )
    }

    func revealWidth(count: Int) -> CGFloat {
        guard count > 0 else {
            return 0.0
        }
        return aetherSwipeEdgeInset * 2.0 + shapeSize.width * CGFloat(count) + aetherSwipeSpacing * CGFloat(count - 1)
    }
}

internal final class AetherListSwipeOptionContainer: UIView {
    private final class OptionView: UIView {
        private let contentContainerView = UIView()
        private let backgroundView = UIView()
        private let titleLabel = UILabel()
        private let iconView: UIImageView?
        private let displaysTitleInsidePill: Bool
        private var measuredTitleSize: CGSize?
        private var didApplyLayout = false

        var isExpanded = false
        var hasAppliedLayout: Bool { didApplyLayout }

        var titleWidthForGroupPillSizing: CGFloat {
            var titleWidth = titleLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width
            if displaysTitleInsidePill {
                titleWidth += aetherSwipeIconlessTitleHorizontalPadding
            }
            return titleWidth
        }

        init(action: AetherListSwipeAction) {
            switch action.icon {
            case .none:
                iconView = nil
            case let .image(image):
                let imageView = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
                imageView.tintColor = action.foregroundColor
                imageView.contentMode = .center
                iconView = imageView
            }

            displaysTitleInsidePill = !action.icon.hasVisualIcon

            super.init(frame: .zero)

            isAccessibilityElement = true
            accessibilityTraits = .button
            accessibilityLabel = action.accessibilityLabel ?? action.title

            contentContainerView.layer.allowsGroupOpacity = true
            addSubview(contentContainerView)

            backgroundView.backgroundColor = action.backgroundColor
            backgroundView.layer.masksToBounds = true
            contentContainerView.addSubview(backgroundView)

            titleLabel.text = action.title
            titleLabel.textColor = displaysTitleInsidePill ? action.foregroundColor : (action.textColor ?? .secondaryLabel)
            titleLabel.textAlignment = .center
            titleLabel.font = displaysTitleInsidePill ? aetherSwipeIconlessTitleFont : aetherSwipeTitleFont
            titleLabel.numberOfLines = 1
            titleLabel.lineBreakMode = .byTruncatingTail
            contentContainerView.addSubview(titleLabel)

            if let iconView {
                contentContainerView.addSubview(iconView)
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func updateLayout(
            isLeft: Bool,
            isPrimary: Bool,
            metrics: AetherListSwipeOptionLayoutMetrics,
            revealProgress: CGFloat,
            overswipeProgress: CGFloat,
            expandedProgress: CGFloat,
            isStretched: Bool,
            isExpanded: Bool,
            transition: ContainedViewLayoutTransition
        ) {
            let bounds = CGRect(origin: .zero, size: self.bounds.size)
            contentContainerView.bounds = bounds
            contentContainerView.center = CGPoint(x: bounds.midX, y: bounds.midY)

            let titleSize = titleLabel.sizeThatFits(CGSize(width: metrics.titleWidth, height: CGFloat.greatestFiniteMagnitude))
            measuredTitleSize = titleSize

            let shapeY: CGFloat
            if displaysTitleInsidePill {
                shapeY = aetherSwipeFloorToScreenPixels((bounds.height - metrics.shapeSize.height) / 2.0)
            } else {
                let contentHeight = metrics.shapeSize.height + aetherSwipeTitleSpacing + titleSize.height
                shapeY = aetherSwipeFloorToScreenPixels((bounds.height - contentHeight) / 2.0)
            }

            let shapeFrameX: CGFloat
            if isStretched {
                shapeFrameX = isLeft ? 0.0 : bounds.width - metrics.shapeSize.width
            } else {
                shapeFrameX = metrics.slotShapeInset
            }
            let shapeFrame = CGRect(origin: CGPoint(x: shapeFrameX, y: shapeY), size: metrics.shapeSize)
            let backgroundFrame: CGRect
            if isStretched {
                backgroundFrame = CGRect(x: 0.0, y: shapeY, width: bounds.width, height: metrics.shapeSize.height)
            } else {
                backgroundFrame = shapeFrame
            }

            transition.updateFrame(view: backgroundView, frame: backgroundFrame)
            backgroundView.layer.cornerRadius = metrics.cornerRadius

            let contentAlpha = isPrimary ? revealProgress : revealProgress * (1.0 - 0.3 * overswipeProgress)
            let contentScale = 0.3 + 0.7 * revealProgress
            transition.updateAlpha(view: contentContainerView, alpha: contentAlpha)
            transition.updateTransform(view: contentContainerView, transform: CGAffineTransform(scaleX: contentScale, y: contentScale))

            let centeredIconCenterX = isPrimary ? backgroundFrame.midX : shapeFrame.midX
            let iconCenterX: CGFloat
            if isPrimary, expandedProgress > 0.0 {
                let expandedIconCenterX = isLeft ? backgroundFrame.maxX - metrics.expandedIconInset : backgroundFrame.minX + metrics.expandedIconInset
                iconCenterX = centeredIconCenterX + (expandedIconCenterX - centeredIconCenterX) * expandedProgress
            } else {
                iconCenterX = centeredIconCenterX
            }
            let iconCenterY = backgroundFrame.midY

            if let iconView, let imageSize = iconView.image?.size {
                var fittedSize = imageSize
                let imageMaxSide = max(fittedSize.width, fittedSize.height)
                if imageMaxSide > metrics.iconMaxSide {
                    let imageScale = metrics.iconMaxSide / imageMaxSide
                    fittedSize = CGSize(
                        width: aetherSwipeFloorToScreenPixels(fittedSize.width * imageScale),
                        height: aetherSwipeFloorToScreenPixels(fittedSize.height * imageScale)
                    )
                }
                let iconFrame = CGRect(
                    x: aetherSwipeFloorToScreenPixels(iconCenterX - fittedSize.width / 2.0),
                    y: aetherSwipeFloorToScreenPixels(iconCenterY - fittedSize.height / 2.0),
                    width: fittedSize.width,
                    height: fittedSize.height
                )
                transition.updateFrame(view: iconView, frame: iconFrame)
            }

            let titleAlpha: CGFloat = isPrimary && !displaysTitleInsidePill ? (1.0 - expandedProgress) : 1.0
            transition.updateAlpha(view: titleLabel, alpha: titleAlpha)

            let titleFrame: CGRect
            if displaysTitleInsidePill {
                var titleCenterX = backgroundFrame.midX
                if isPrimary, expandedProgress > 0.0 {
                    let titleEdgeInset = max(metrics.expandedIconInset, titleSize.width / 2.0 + aetherSwipeIconlessTitleExpandedHorizontalPadding)
                    let expandedTitleCenterX = isLeft ? backgroundFrame.maxX - titleEdgeInset : backgroundFrame.minX + titleEdgeInset
                    titleCenterX += (expandedTitleCenterX - backgroundFrame.midX) * expandedProgress
                }
                titleFrame = CGRect(
                    x: aetherSwipeFloorToScreenPixels(titleCenterX - titleSize.width / 2.0),
                    y: aetherSwipeFloorToScreenPixels(backgroundFrame.midY - titleSize.height / 2.0),
                    width: titleSize.width,
                    height: titleSize.height
                )
            } else {
                let titleCenterX = isPrimary ? backgroundFrame.midX : shapeFrame.midX
                titleFrame = CGRect(
                    x: aetherSwipeFloorToScreenPixels(titleCenterX - titleSize.width / 2.0),
                    y: shapeFrame.maxY + aetherSwipeTitleSpacing,
                    width: titleSize.width,
                    height: titleSize.height
                )
            }
            transition.updateFrame(view: titleLabel, frame: titleFrame)

            self.isExpanded = isExpanded
            didApplyLayout = true
        }
    }

    internal final class OptionsView: UIView {
        private let optionSelected: (AetherListSwipeAction) -> Void
        private let expandedStateChanged: () -> Void
        private let clippingContainerView = UIView()
        private let optionsContainerView = UIView()

        private var actions: [AetherListSwipeAction] = []
        private var isLeft = false
        private var optionViews: [OptionView] = []
        private var revealOffset: CGFloat = 0.0
        private var sideInset: CGFloat = 0.0
        private var currentMetrics: (containerSize: CGSize, metrics: AetherListSwipeOptionLayoutMetrics)?

        init(
            optionSelected: @escaping (AetherListSwipeAction) -> Void,
            expandedStateChanged: @escaping () -> Void
        ) {
            self.optionSelected = optionSelected
            self.expandedStateChanged = expandedStateChanged
            super.init(frame: .zero)

            clipsToBounds = false
            clippingContainerView.clipsToBounds = true
            addSubview(clippingContainerView)
            clippingContainerView.addSubview(optionsContainerView)

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapGesture(_:)))
            addGestureRecognizer(tapGesture)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func setActions(_ actions: [AetherListSwipeAction], isLeft: Bool) {
            guard self.actions != actions || self.isLeft != isLeft else {
                return
            }

            self.actions = actions
            self.isLeft = isLeft

            for view in optionViews {
                view.removeFromSuperview()
            }
            optionViews = actions.map(OptionView.init(action:))
            currentMetrics = nil

            if isLeft {
                for view in optionViews.reversed() {
                    optionsContainerView.addSubview(view)
                }
            } else {
                for view in optionViews {
                    optionsContainerView.addSubview(view)
                }
            }
        }

        private func layoutMetrics(for containerSize: CGSize) -> AetherListSwipeOptionLayoutMetrics {
            if let currentMetrics, currentMetrics.containerSize == containerSize {
                return currentMetrics.metrics
            }

            let metrics = AetherListSwipeOptionLayoutMetrics.metrics(
                for: containerSize.height,
                hasVisualIcons: actions.contains(where: { $0.icon.hasVisualIcon })
            )
            let maxTitleWidth = optionViews.reduce(CGFloat(0.0)) { result, view in
                max(result, view.titleWidthForGroupPillSizing)
            }
            let updatedMetrics = metrics.withGroupTitleWidth(maxTitleWidth)
            currentMetrics = (containerSize, updatedMetrics)
            return updatedMetrics
        }

        func calculateSize(_ constrainedSize: CGSize) -> CGSize {
            let metrics = layoutMetrics(for: constrainedSize)
            return CGSize(width: metrics.revealWidth(count: optionViews.count), height: constrainedSize.height)
        }

        func updateRevealOffset(_ offset: CGFloat, sideInset: CGFloat, transition: ContainedViewLayoutTransition) {
            revealOffset = offset
            self.sideInset = sideInset
            updateViewsLayout(transition: transition)
        }

        func isDisplayingExtendedAction() -> Bool {
            optionViews.contains { $0.isExpanded }
        }

        func expandedAction() -> AetherListSwipeAction? {
            guard isDisplayingExtendedAction() else { return nil }
            return isLeft ? actions.first : actions.last
        }

        func containsAction(at point: CGPoint) -> Bool {
            let convertedPoint = optionsContainerView.convert(point, from: self)
            return optionViews.contains { !$0.isHidden && $0.alpha > 0.01 && $0.frame.contains(convertedPoint) }
        }

        private func updateViewsLayout(transition: ContainedViewLayoutTransition) {
            let size = bounds.size
            guard size.width > 0.0, !optionViews.isEmpty else {
                return
            }

            let metrics = layoutMetrics(for: size)
            let revealedDistance = abs(revealOffset)
            let boundedRevealedDistance = min(revealedDistance, size.width)
            let overswipeDistance = max(0.0, revealedDistance - size.width)
            let overswipeProgress = aetherSwipeClampToUnitInterval(overswipeDistance / aetherSwipeExpandedTransitionDistance)
            let expandedActivationDistance = 50.0 * (aetherSwipeExpandedActivationWidthFactor - 1.0)
            let primaryIndex = isLeft ? 0 : optionViews.count - 1
            let stride = metrics.shapeSize.width + aetherSwipeSpacing

            let clippingFrameX: CGFloat
            if isLeft {
                clippingFrameX = max(0.0, size.width - revealedDistance)
            } else {
                clippingFrameX = 0.0
            }
            let clippingFrame = CGRect(
                x: clippingFrameX,
                y: 0.0,
                width: revealedDistance,
                height: size.height
            )
            transition.updateFrame(view: clippingContainerView, frame: clippingFrame)
            transition.updateFrame(
                view: optionsContainerView,
                frame: CGRect(x: -clippingFrameX, y: 0.0, width: max(size.width, revealedDistance), height: size.height)
            )

            var index = isLeft ? optionViews.count - 1 : 0
            while index >= 0 && index < optionViews.count {
                let optionView = optionViews[index]
                let isPrimary = index == primaryIndex
                let isStretched = isPrimary && overswipeDistance > CGFloat.ulpOfOne
                let isExpanded = isPrimary && overswipeDistance > expandedActivationDistance
                let expandedProgress: CGFloat = isExpanded ? 1.0 : 0.0
                if optionView.hasAppliedLayout, optionView.isExpanded != isExpanded, !transition.isAnimated {
                    expandedStateChanged()
                }

                let baseCircleFrame: CGRect
                let optionFrame: CGRect
                let revealProgress: CGFloat
                if isLeft {
                    let baseCircleLeft = size.width - boundedRevealedDistance + sideInset + aetherSwipeEdgeInset + CGFloat(index) * stride
                    baseCircleFrame = CGRect(origin: CGPoint(x: baseCircleLeft, y: 0.0), size: metrics.shapeSize)
                    let distanceFromShutterEdge = size.width - baseCircleFrame.maxX
                    revealProgress = aetherSwipeClampToUnitInterval((distanceFromShutterEdge + aetherSwipeRevealStartOverlap) / (aetherSwipeRevealStartOverlap + aetherSwipeRevealEndDistance))

                    if isStretched {
                        let primaryLeft = size.width - boundedRevealedDistance + sideInset + aetherSwipeEdgeInset
                        let primaryRight: CGFloat
                        if optionViews.count > 1 {
                            let neighborLeft = primaryLeft + stride + overswipeDistance
                            primaryRight = max(primaryLeft + metrics.shapeSize.width, neighborLeft - aetherSwipeSpacing)
                        } else {
                            primaryRight = primaryLeft + metrics.shapeSize.width + overswipeDistance
                        }
                        optionFrame = CGRect(
                            x: aetherSwipeFloorToScreenPixels(primaryLeft),
                            y: 0.0,
                            width: max(metrics.shapeSize.width, primaryRight - primaryLeft),
                            height: size.height
                        )
                    } else {
                        let circleLeft = baseCircleLeft + (isPrimary ? 0.0 : overswipeDistance)
                        optionFrame = CGRect(
                            x: aetherSwipeFloorToScreenPixels(circleLeft - metrics.slotShapeInset),
                            y: 0.0,
                            width: metrics.slotWidth,
                            height: size.height
                        )
                    }
                } else {
                    let baseCircleRight = revealedDistance + sideInset - aetherSwipeEdgeInset - CGFloat(optionViews.count - 1 - index) * stride
                    baseCircleFrame = CGRect(origin: CGPoint(x: baseCircleRight - metrics.shapeSize.width, y: 0.0), size: metrics.shapeSize)
                    revealProgress = aetherSwipeClampToUnitInterval((baseCircleFrame.minX + aetherSwipeRevealStartOverlap) / (aetherSwipeRevealStartOverlap + aetherSwipeRevealEndDistance))

                    if isStretched {
                        let primaryRight = revealedDistance + sideInset - aetherSwipeEdgeInset
                        let primaryLeft: CGFloat
                        if optionViews.count > 1 {
                            let neighborRight = primaryRight - stride - overswipeDistance
                            primaryLeft = min(primaryRight - metrics.shapeSize.width, neighborRight + aetherSwipeSpacing)
                        } else {
                            primaryLeft = primaryRight - metrics.shapeSize.width - overswipeDistance
                        }
                        optionFrame = CGRect(
                            x: aetherSwipeFloorToScreenPixels(primaryLeft),
                            y: 0.0,
                            width: max(metrics.shapeSize.width, primaryRight - primaryLeft),
                            height: size.height
                        )
                    } else {
                        let circleLeft = baseCircleFrame.minX - (isPrimary ? 0.0 : overswipeDistance)
                        optionFrame = CGRect(
                            x: aetherSwipeFloorToScreenPixels(circleLeft - metrics.slotShapeInset),
                            y: 0.0,
                            width: metrics.slotWidth,
                            height: size.height
                        )
                    }
                }

                transition.updateFrame(view: optionView, frame: optionFrame)
                optionView.updateLayout(
                    isLeft: isLeft,
                    isPrimary: isPrimary,
                    metrics: metrics,
                    revealProgress: revealProgress,
                    overswipeProgress: overswipeProgress,
                    expandedProgress: expandedProgress,
                    isStretched: isStretched,
                    isExpanded: isExpanded,
                    transition: transition
                )

                index += isLeft ? -1 : 1
            }
        }

        @objc private func tapGesture(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else {
                return
            }

            let location = recognizer.location(in: self)
            let convertedLocation = optionsContainerView.convert(location, from: self)
            var selectedIndex: Int?
            var index = isLeft ? 0 : optionViews.count - 1
            while index >= 0 && index < optionViews.count {
                if optionViews[index].frame.contains(convertedLocation) {
                    selectedIndex = index
                    break
                }
                index += isLeft ? 1 : -1
            }

            if let selectedIndex {
                optionSelected(actions[selectedIndex])
            }
        }
    }

    private var leftOptionsView: OptionsView?
    private var rightOptionsView: OptionsView?
    private var actions: AetherListSwipeActions = .none
    private var validLayout: (size: CGSize, leftInset: CGFloat, rightInset: CGFloat)?

    private let optionSelected: (AetherListSwipeAction, Bool) -> Void
    private let expandedStateChanged: () -> Void

    private(set) var revealOffset: CGFloat = 0.0

    var isDisplayingRevealedOptions: Bool {
        !revealOffset.isZero
    }

    init(
        optionSelected: @escaping (AetherListSwipeAction, Bool) -> Void,
        expandedStateChanged: @escaping () -> Void
    ) {
        self.optionSelected = optionSelected
        self.expandedStateChanged = expandedStateChanged
        super.init(frame: .zero)
        clipsToBounds = false
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setActions(_ actions: AetherListSwipeActions) {
        self.actions = actions
        if actions.left.isEmpty, leftOptionsView != nil {
            updateRevealOffset(0.0, transition: .animated(duration: 0.3, curve: .spring))
        } else if let leftOptionsView {
            leftOptionsView.setActions(actions.left, isLeft: true)
        }

        if actions.right.isEmpty, rightOptionsView != nil {
            updateRevealOffset(0.0, transition: .animated(duration: 0.3, curve: .spring))
        } else if let rightOptionsView {
            rightOptionsView.setActions(actions.right, isLeft: false)
        }
    }

    func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat) {
        validLayout = (size, leftInset, rightInset)

        if let leftOptionsView {
            var revealSize = leftOptionsView.calculateSize(CGSize(width: CGFloat.greatestFiniteMagnitude, height: size.height))
            revealSize.width += leftInset
            leftOptionsView.frame = CGRect(x: min(revealOffset - revealSize.width, 0.0), y: 0.0, width: revealSize.width, height: revealSize.height)
            leftOptionsView.updateRevealOffset(-revealOffset, sideInset: leftInset, transition: .immediate)
        }

        if let rightOptionsView {
            var revealSize = rightOptionsView.calculateSize(CGSize(width: CGFloat.greatestFiniteMagnitude, height: size.height))
            revealSize.width += rightInset
            rightOptionsView.frame = CGRect(x: min(size.width, size.width + revealOffset), y: 0.0, width: revealSize.width, height: revealSize.height)
            rightOptionsView.updateRevealOffset(-revealOffset, sideInset: -rightInset, transition: .immediate)
        }
    }

    func ensureOptionsView(for side: AetherListSwipeActionsSide) {
        switch side {
        case .left:
            setupLeftOptionsViewIfNeeded()
        case .right:
            setupRightOptionsViewIfNeeded()
        }
    }

    func revealWidth(for side: AetherListSwipeActionsSide) -> CGFloat {
        switch side {
        case .left:
            if leftOptionsView == nil {
                setupLeftOptionsViewIfNeeded()
            }
            return leftOptionsView?.bounds.width ?? 0.0
        case .right:
            if rightOptionsView == nil {
                setupRightOptionsViewIfNeeded()
            }
            return rightOptionsView?.bounds.width ?? 0.0
        }
    }

    func expandedAction(for side: AetherListSwipeActionsSide) -> AetherListSwipeAction? {
        switch side {
        case .left:
            return leftOptionsView?.expandedAction()
        case .right:
            return rightOptionsView?.expandedAction()
        }
    }

    func containsAction(at point: CGPoint) -> Bool {
        if let leftOptionsView, leftOptionsView.frame.contains(point) {
            return leftOptionsView.containsAction(at: leftOptionsView.convert(point, from: self))
        }
        if let rightOptionsView, rightOptionsView.frame.contains(point) {
            return rightOptionsView.containsAction(at: rightOptionsView.convert(point, from: self))
        }
        return false
    }

    func updateRevealOffset(
        _ offset: CGFloat,
        transition: ContainedViewLayoutTransition,
        completion: (() -> Void)? = nil
    ) {
        revealOffset = offset
        guard let (size, leftInset, rightInset) = validLayout else {
            completion?()
            return
        }

        var pendingCompletions = 0
        var didScheduleCompletions = false
        var didRunCompletion = false
        let completeOne = {
            pendingCompletions -= 1
            if didScheduleCompletions && pendingCompletions == 0 && !didRunCompletion {
                didRunCompletion = true
                completion?()
            }
        }

        if let leftOptionsView {
            pendingCompletions += 1
            let revealSize = leftOptionsView.bounds.size
            let revealFrame = CGRect(x: min(offset - revealSize.width, 0.0), y: 0.0, width: revealSize.width, height: revealSize.height)
            leftOptionsView.updateRevealOffset(-offset, sideInset: leftInset, transition: transition)

            if offset <= 0.0 {
                self.leftOptionsView = nil
                transition.updateFrame(view: leftOptionsView, frame: revealFrame) { [weak leftOptionsView] _ in
                    leftOptionsView?.removeFromSuperview()
                    completeOne()
                }
            } else {
                transition.updateFrame(view: leftOptionsView, frame: revealFrame) { _ in
                    completeOne()
                }
            }
        }

        if let rightOptionsView {
            pendingCompletions += 1
            let revealSize = rightOptionsView.bounds.size
            let revealFrame = CGRect(
                x: min(size.width, size.width + offset),
                y: 0.0,
                width: revealSize.width,
                height: revealSize.height
            )
            rightOptionsView.updateRevealOffset(-offset, sideInset: -rightInset, transition: transition)

            if offset >= 0.0 {
                self.rightOptionsView = nil
                transition.updateFrame(view: rightOptionsView, frame: revealFrame) { [weak rightOptionsView] _ in
                    rightOptionsView?.removeFromSuperview()
                    completeOne()
                }
            } else {
                transition.updateFrame(view: rightOptionsView, frame: revealFrame) { _ in
                    completeOne()
                }
            }
        }

        didScheduleCompletions = true
        if pendingCompletions == 0 && !didRunCompletion {
            didRunCompletion = true
            completion?()
        }
    }

    private func setupLeftOptionsViewIfNeeded() {
        guard leftOptionsView == nil, !actions.left.isEmpty else {
            return
        }

        let optionsView = OptionsView(
            optionSelected: { [weak self] action in
                self?.optionSelected(action, false)
            },
            expandedStateChanged: { [weak self] in
                self?.expandedStateChanged()
            }
        )
        optionsView.setActions(actions.left, isLeft: true)
        leftOptionsView = optionsView

        if let (size, leftInset, _) = validLayout {
            var revealSize = optionsView.calculateSize(CGSize(width: CGFloat.greatestFiniteMagnitude, height: size.height))
            revealSize.width += leftInset
            optionsView.frame = CGRect(x: min(revealOffset - revealSize.width, 0.0), y: 0.0, width: revealSize.width, height: revealSize.height)
            optionsView.updateRevealOffset(0.0, sideInset: leftInset, transition: .immediate)
        }

        addSubview(optionsView)
    }

    private func setupRightOptionsViewIfNeeded() {
        guard rightOptionsView == nil, !actions.right.isEmpty else {
            return
        }

        let optionsView = OptionsView(
            optionSelected: { [weak self] action in
                self?.optionSelected(action, false)
            },
            expandedStateChanged: { [weak self] in
                self?.expandedStateChanged()
            }
        )
        optionsView.setActions(actions.right, isLeft: false)
        rightOptionsView = optionsView

        if let (size, _, rightInset) = validLayout {
            var revealSize = optionsView.calculateSize(CGSize(width: CGFloat.greatestFiniteMagnitude, height: size.height))
            revealSize.width += rightInset
            optionsView.frame = CGRect(x: min(size.width, size.width + revealOffset), y: 0.0, width: revealSize.width, height: revealSize.height)
            optionsView.updateRevealOffset(0.0, sideInset: -rightInset, transition: .immediate)
        }

        addSubview(optionsView)
    }
}
