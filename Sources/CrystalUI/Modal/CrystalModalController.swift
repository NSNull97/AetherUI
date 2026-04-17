import UIKit

public final class CrystalModalController: UIViewController {
    public enum Detent: Hashable {
        case stage1
        case stage2
    }

    public struct Config: Equatable {
        public var sideInset: CGFloat
        public var bottomInsetStage1: CGFloat
        public var topInsetStage1: CGFloat
        public var topInsetStage2: CGFloat
        public var topCornerRadius: CGFloat
        public var dimAlphaStage2: CGFloat

        public init(
            sideInset: CGFloat = 8.0,
            bottomInsetStage1: CGFloat = 16.0,
            topInsetStage1: CGFloat = UIScreenHeight / 2,
            topInsetStage2: CGFloat = 10.0,
            topCornerRadius: CGFloat = 38.0,
            dimAlphaStage2: CGFloat = 0.25
        ) {
            self.sideInset = sideInset
            self.bottomInsetStage1 = bottomInsetStage1
            self.topInsetStage1 = topInsetStage1
            self.topInsetStage2 = topInsetStage2
            self.topCornerRadius = topCornerRadius
            self.dimAlphaStage2 = dimAlphaStage2
        }
    }

    public let content: UIViewController
    public let config: Config

    /// Scroll view inside `content` that should cooperate with sheet drag.
    /// Set this to the content's primary scroll view so the sheet can yield to it.
    public weak var primaryScrollView: UIScrollView?

    public private(set) var currentDetent: Detent = .stage1

    private let glassBackground = GlassBackgroundView(style: .regular)
    private let tintOverlay = UIView()
    private let contentContainer = UIView()
    private let maskLayer = CAShapeLayer()

    private let modalTransitioningDelegate: CrystalModalTransitioningDelegate

    public init(content: UIViewController, config: Config = Config()) {
        self.content = content
        self.config = config
        self.modalTransitioningDelegate = CrystalModalTransitioningDelegate()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = modalTransitioningDelegate
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        let root = RootView()
        root.backgroundColor = .clear
        root.layer.mask = maskLayer

        root.addSubview(glassBackground)

        tintOverlay.backgroundColor = .systemBackground
        tintOverlay.alpha = 0.0
        tintOverlay.isUserInteractionEnabled = false
        glassBackground.contentView.addSubview(tintOverlay)

        glassBackground.contentView.addSubview(contentContainer)

        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = true
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentContainer.addSubview(content.view)
        content.didMove(toParent: self)

        view = root
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutGlassAndContent()
        updateMaskPath()
    }

    public func setDetent(_ detent: Detent, animated: Bool) {
        guard let presentation = presentationController as? CrystalModalPresentationController else {
            return
        }
        presentation.setDetent(detent, animated: animated)
    }

    func applyDetentProgress(_ progress: CGFloat) {
        tintOverlay.alpha = max(0.0, min(1.0, progress))
    }

    func applyCurrentDetent(_ detent: Detent) {
        currentDetent = detent
    }

    func deviceCornerRadius() -> CGFloat {
        if let presentation = presentationController as? CrystalModalPresentationController {
            return presentation.deviceCornerRadius
        }
        return 39.0
    }

    private func layoutGlassAndContent() {
        glassBackground.frame = view.bounds
        glassBackground.update(size: view.bounds.size, cornerRadius: 0.0, transition: .immediate)
        tintOverlay.frame = view.bounds
        contentContainer.frame = view.bounds
        content.view.frame = contentContainer.bounds
    }

    private func updateMaskPath() {
        let bounds = view.bounds
        let topRadius = config.topCornerRadius
        let bottomRadius = deviceCornerRadius()
        maskLayer.frame = bounds
        maskLayer.path = Self.roundedRectPath(
            in: bounds,
            topLeftRadius: topRadius,
            topRightRadius: topRadius,
            bottomLeftRadius: bottomRadius,
            bottomRightRadius: bottomRadius
        ).cgPath
    }

    /// Root view for the presented modal. UIKit propagates the window's
    /// full safe area (including the status bar) to the presented view even
    /// when the sheet frame doesn't overlap the status bar — this override
    /// computes the top inset from the sheet's actual position in the
    /// window so content anchored to `view.safeAreaLayoutGuide.topAnchor`
    /// doesn't get a phantom status-bar-sized gap at the top.
    private final class RootView: UIView {
        override var safeAreaInsets: UIEdgeInsets {
            let inherited = super.safeAreaInsets
            let topInWindow = convert(CGPoint.zero, to: nil).y
            let windowSafeTop = window?.safeAreaInsets.top ?? 0.0
            let overlap = max(0.0, windowSafeTop - topInWindow)
            return UIEdgeInsets(
                top: overlap,
                left: inherited.left,
                bottom: inherited.bottom,
                right: inherited.right
            )
        }
    }

    private static func roundedRectPath(
        in rect: CGRect,
        topLeftRadius tl: CGFloat,
        topRightRadius tr: CGFloat,
        bottomLeftRadius bl: CGFloat,
        bottomRightRadius br: CGFloat
    ) -> UIBezierPath {
        let path = UIBezierPath()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: tl, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(
            withCenter: CGPoint(x: w - tr, y: tr),
            radius: tr,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(
            withCenter: CGPoint(x: w - br, y: h - br),
            radius: br,
            startAngle: 0,
            endAngle: .pi / 2,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(
            withCenter: CGPoint(x: bl, y: h - bl),
            radius: bl,
            startAngle: .pi / 2,
            endAngle: .pi,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(
            withCenter: CGPoint(x: tl, y: tl),
            radius: tl,
            startAngle: .pi,
            endAngle: 3 * .pi / 2,
            clockwise: true
        )
        path.close()
        return path
    }
}
