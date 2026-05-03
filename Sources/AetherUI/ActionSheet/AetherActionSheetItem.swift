import UIKit

public protocol AetherActionSheetItem {
    func makeView(theme: AetherActionSheetTheme) -> AetherActionSheetItemView
    func updateView(_ view: AetherActionSheetItemView)
}

public final class AetherActionSheetItemGroup {
    public let items: [AetherActionSheetItem]

    public init(items: [AetherActionSheetItem]) {
        self.items = items
    }
}

// MARK: - ItemView

open class AetherActionSheetItemView: UIView {
    public static let defaultItemHeight: CGFloat = 57.0

    public let theme: AetherActionSheetTheme

    public let backgroundView = UIView()
    /// Hairline shown below this row when it is not the last row of its
    /// group. The group container toggles `hasSeparator` on each item.
    public let separatorView = UIView()

    public var hasSeparator: Bool = true {
        didSet { separatorView.isHidden = !hasSeparator }
    }

    public init(theme: AetherActionSheetTheme) {
        self.theme = theme
        super.init(frame: .zero)

        // On iOS 26+ with liquid glass, the group's UIGlassEffect paints
        // the whole card; row backgrounds stay transparent so content
        // refraction shows through. On older iOS the row still needs its
        // own solid tint.
        if GlassCompatibility.isLiquidDesignAvailable {
            backgroundView.backgroundColor = .clear
        } else {
            backgroundView.backgroundColor = theme.itemBackgroundColor
        }
        backgroundView.isUserInteractionEnabled = false
        separatorView.backgroundColor = theme.separatorColor
        separatorView.isUserInteractionEnabled = false

        addSubview(backgroundView)
        addSubview(separatorView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Override in subclasses. Return preferred height for the given width.
    open func preferredHeight(constrainedWidth: CGFloat) -> CGFloat {
        return Self.defaultItemHeight
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
        separatorView.frame = CGRect(
            x: 0,
            y: bounds.height,
            width: bounds.width,
            height: 1.0 / UIScreen.main.scale
        )
    }

    /// Called by the controller when arrow-key/enter focus lands on the row.
    open func setHighlighted(_ highlighted: Bool, animated: Bool) {
        let idle: UIColor = GlassCompatibility.isLiquidDesignAvailable
            ? .clear
            : theme.itemBackgroundColor
        let color = highlighted ? theme.itemHighlightedBackgroundColor : idle
        if animated && !highlighted {
            UIView.animate(withDuration: 0.3) {
                self.backgroundView.backgroundColor = color
            }
        } else {
            backgroundView.backgroundColor = color
        }
    }

    /// Invoked when user activates the row via keyboard (Enter).
    open func performAction() {}
}
