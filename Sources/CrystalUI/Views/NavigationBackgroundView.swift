import UIKit

/// A view that provides a background with optional blur effect, matching NavigationBackgroundNode.
public final class NavigationBackgroundView: UIView {
    private var effectView: UIVisualEffectView?
    private let backgroundColorView: UIView

    public var enableBlur: Bool = true {
        didSet {
            if enableBlur != oldValue {
                updateBackgroundBlur()
            }
        }
    }

    private var _color: UIColor = .white

    public init(color: UIColor, enableBlur: Bool = true) {
        self._color = color
        self.enableBlur = enableBlur
        self.backgroundColorView = UIView()

        super.init(frame: .zero)

        self.backgroundColorView.backgroundColor = color
        addSubview(self.backgroundColorView)

        updateBackgroundBlur()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateColor(color: UIColor, enableBlur: Bool, transition: ContainedViewLayoutTransition) {
        self._color = color
        self.enableBlur = enableBlur
        self.backgroundColorView.backgroundColor = color

        if !enableBlur {
            self.backgroundColorView.alpha = 1.0
        } else {
            self.backgroundColorView.alpha = 0.8
        }
    }

    public func update(size: CGSize, cornerRadius: CGFloat = 0.0, transition: ContainedViewLayoutTransition) {
        let frame = CGRect(origin: .zero, size: size)
        transition.updateFrame(view: self.backgroundColorView, frame: frame)
        self.effectView?.frame = frame

        if cornerRadius > 0 {
            self.layer.cornerRadius = cornerRadius
            self.clipsToBounds = true
        } else {
            self.layer.cornerRadius = 0
            self.clipsToBounds = false
        }
    }

    public func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        transition.updateAlpha(view: self, alpha: alpha)
    }

    private func updateBackgroundBlur() {
        if UIAccessibility.isReduceTransparencyEnabled {
            self.effectView?.removeFromSuperview()
            self.effectView = nil
            self.backgroundColorView.alpha = 1.0
            return
        }

        if enableBlur {
            if self.effectView == nil {
                let effect = UIBlurEffect(style: .systemMaterial)
                let effectView = UIVisualEffectView(effect: effect)
                effectView.frame = bounds
                effectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                insertSubview(effectView, at: 0)
                self.effectView = effectView
            }
            self.backgroundColorView.alpha = 0.8
        } else {
            self.effectView?.removeFromSuperview()
            self.effectView = nil
            self.backgroundColorView.alpha = 1.0
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        self.backgroundColorView.frame = bounds
        self.effectView?.frame = bounds
    }
}
