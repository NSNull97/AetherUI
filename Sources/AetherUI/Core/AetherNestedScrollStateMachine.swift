import UIKit

public final class AetherNestedScrollStateMachine {
    public struct Input {
        public let visibleOffset: CGFloat
        public let lockOffset: CGFloat
        public let isDecelerating: Bool
        public let isTrackingOrDragging: Bool
        public let verticalVelocityY: CGFloat

        public init(
            visibleOffset: CGFloat,
            lockOffset: CGFloat,
            isDecelerating: Bool,
            isTrackingOrDragging: Bool,
            verticalVelocityY: CGFloat
        ) {
            self.visibleOffset = visibleOffset
            self.lockOffset = lockOffset
            self.isDecelerating = isDecelerating
            self.isTrackingOrDragging = isTrackingOrDragging
            self.verticalVelocityY = verticalVelocityY
        }
    }

    public struct Output {
        public let outerOffset: CGFloat
        public let innerOffset: CGFloat

        public init(outerOffset: CGFloat, innerOffset: CGFloat) {
            self.outerOffset = outerOffset
            self.innerOffset = innerOffset
        }
    }

    private var lastOutput: Output?

    public init() {
    }

    public func reset() {
        lastOutput = nil
    }

    public func update(_ input: Input) -> Output {
        let lockOffset = max(0.0, input.lockOffset)
        let outerOffset: CGFloat
        if input.visibleOffset < 0.0 {
            outerOffset = input.visibleOffset
        } else if lockOffset <= 0.0 {
            outerOffset = 0.0
        } else {
            outerOffset = min(input.visibleOffset, lockOffset)
        }

        let innerOffset = max(0.0, input.visibleOffset - max(0.0, outerOffset))
        let output = Output(outerOffset: outerOffset, innerOffset: innerOffset)
        lastOutput = output
        return output
    }

    public func settle(_ input: Input) -> Output? {
        return nil
    }
}
