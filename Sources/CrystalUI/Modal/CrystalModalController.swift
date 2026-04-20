import UIKit

public protocol CrystalModalControllerDelegate: AnyObject {
    /// Fires continuously (per-frame during drag and during the settle
    /// animation) as the sheet scrolls between detents. Progress is 0 at
    /// stage1 and 1 at stage2; values are clamped to `0...1`.
    func crystalModalController(
        _ controller: CrystalModalController,
        didUpdateDetentProgress progress: CGFloat
    )
    /// Fires when the sheet commits to a detent — at the start of a settle
    /// animation, a programmatic `setDetent`, or on a live drag crossing
    /// to a different nearest detent.
    func crystalModalController(
        _ controller: CrystalModalController,
        didChangeDetent detent: CrystalModalController.Detent
    )
}

public extension CrystalModalControllerDelegate {
    func crystalModalController(
        _ controller: CrystalModalController,
        didUpdateDetentProgress progress: CGFloat
    ) {}
    func crystalModalController(
        _ controller: CrystalModalController,
        didChangeDetent detent: CrystalModalController.Detent
    ) {}
}

public final class CrystalModalController: UIViewController {
    public enum Detent: Hashable {
        case stage1
        case stage2
    }

    public struct Config: Equatable {
        public var sideInset: CGFloat
        /// Distance from the sheet's bottom edge to the screen bottom at
        /// stage1. Default 8pt — the sheet floats above the home indicator.
        public var bottomInsetStage1: CGFloat
        /// Distance from the sheet's bottom edge to the screen bottom at
        /// stage2. Default 0 — the sheet nestles into the device corners.
        public var bottomInsetStage2: CGFloat
        public var topInsetStage1: CGFloat
        public var topInsetStage2: CGFloat
        public var topCornerRadius: CGFloat
        /// Dim alpha applied over the presenting view at stage1.
        public var dimAlphaStage1: CGFloat
        /// Dim alpha applied over the presenting view at stage2.
        public var dimAlphaStage2: CGFloat
        public var dimTintColor: UIColor
        /// Detents the sheet is allowed to rest at. When a single detent
        /// is specified the sheet opens at that detent and drags toward
        /// the other detent are blocked — only a strong downward drag can
        /// dismiss the sheet. Must contain at least one detent.
        public var detents: Set<Detent>
        /// Detent the sheet opens at. Must be contained in `detents`.
        /// Nil → pick the first allowed detent (stage1 preferred).
        public var initialDetent: Detent?

        public init(
            sideInset: CGFloat = 8.0,
            bottomInsetStage1: CGFloat = 8.0,
            bottomInsetStage2: CGFloat = 0.0,
            topInsetStage1: CGFloat = UIScreenHeight / 2,
            topInsetStage2: CGFloat = 10.0,
            topCornerRadius: CGFloat = 38.0,
            dimAlphaStage1: CGFloat = 0.25,
            dimAlphaStage2: CGFloat = 0.4,
            dimTintColor: UIColor = .systemBackground,
            detents: Set<Detent> = [.stage1, .stage2],
            initialDetent: Detent? = nil
        ) {
            self.sideInset = sideInset
            self.bottomInsetStage1 = bottomInsetStage1
            self.bottomInsetStage2 = bottomInsetStage2
            self.topInsetStage1 = topInsetStage1
            self.topInsetStage2 = topInsetStage2
            self.topCornerRadius = topCornerRadius
            self.dimAlphaStage1 = dimAlphaStage1
            self.dimAlphaStage2 = dimAlphaStage2
            self.dimTintColor = dimTintColor
            self.detents = detents.isEmpty ? [.stage1, .stage2] : detents
            self.initialDetent = initialDetent
        }

        /// Resolved opening detent — `initialDetent` if allowed,
        /// otherwise stage1 (if allowed), otherwise stage2.
        public var resolvedInitialDetent: Detent {
            if let requested = initialDetent, detents.contains(requested) {
                return requested
            }
            return detents.contains(.stage1) ? .stage1 : .stage2
        }
    }

    public let content: UIViewController
    public let config: Config

    /// Scroll view inside `content` that should cooperate with sheet drag.
    /// Set this to the content's primary scroll view so the sheet can yield to it.
    public weak var primaryScrollView: UIScrollView?

    public weak var delegate: CrystalModalControllerDelegate?

    public private(set) var currentDetent: Detent = .stage1
    public var currentDetentProgress: CGFloat { detentProgress }

    private let glassBackground = GlassBackgroundView(style: .regular)
    private let contentContainer = UIView()
    private let grabberContainer = UIView()
    private let grabberView = UIView()
    private let maskLayer = CAShapeLayer()

    /// Height of the grabber container area at the top of the sheet —
    /// content is inset down by this much so its own top (e.g. a navbar
    /// inside the content VC) doesn't collide with the grabber.
    public static let grabberContainerHeight: CGFloat = 17.0
    private static let grabberSize: CGSize = CGSize(width: 36.0, height: 5.0)

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

        glassBackground.contentView.addSubview(contentContainer)
        glassBackground.contentView.addSubview(grabberContainer)
        glassBackground.glassIsInteractive = true

        grabberView.backgroundColor = UIColor.label.withAlphaComponent(0.28)
        grabberView.layer.cornerRadius = Self.grabberSize.height / 2.0
        grabberView.layer.cornerCurve = .continuous
        grabberView.isUserInteractionEnabled = false
        grabberContainer.isUserInteractionEnabled = false
        grabberContainer.addSubview(grabberView)

        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = true
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentContainer.addSubview(content.view)
        content.didMove(toParent: self)

        view = root
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        compensatePhantomSafeArea()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutGlassAndContent()
        updateMaskPath()
        applyEdgeEffectExtensionToContentNavBars()
    }

    /// Propagate the grabber strip's height into every nav bar in the
    /// content hierarchy so their scroll-edge frost extends upward past
    /// the navbar top and covers the grabber area — otherwise the frost
    /// ends at the navbar edge and leaves the grabber visually
    /// disconnected from the nav-bar chrome below it.
    private func applyEdgeEffectExtensionToContentNavBars() {
        applyEdgeEffectExtension(to: content)
    }

    private func applyEdgeEffectExtension(to vc: UIViewController) {
        if let ctrl = vc as? ViewController,
           let bar = ctrl.navigationBarView as? NavigationBarImpl
        {
            if bar.edgeEffectTopExtension != Self.grabberContainerHeight {
                bar.edgeEffectTopExtension = Self.grabberContainerHeight
            }
        }
        for child in vc.children {
            applyEdgeEffectExtension(to: child)
        }
    }

    /// UIKit propagates the window's full status-bar-sized top safe area
    /// into the presented view even when the sheet sits below the status
    /// bar, so content anchored to `view.safeAreaLayoutGuide.topAnchor`
    /// gets a phantom gap. Compensate by pushing a matching negative
    /// `additionalSafeAreaInsets.top` so the effective inset matches the
    /// actual overlap with the window safe area.
    private func compensatePhantomSafeArea() {
        guard let window = view.window else { return }
        let topInWindow = view.convert(CGPoint.zero, to: nil).y
        let windowSafeTop = window.safeAreaInsets.top
        let realOverlap = max(0.0, windowSafeTop - topInWindow)

        let inherited = view.safeAreaInsets.top - additionalSafeAreaInsets.top
        let desired = realOverlap - inherited
        if abs(additionalSafeAreaInsets.top - desired) > 0.5 {
            additionalSafeAreaInsets.top = desired
        }
    }

    public func setDetent(_ detent: Detent, animated: Bool) {
        guard let presentation = presentationController as? CrystalModalPresentationController else {
            return
        }
        presentation.setDetent(detent, animated: animated)
    }

    private var detentProgress: CGFloat = 0.0

    func applyDetentProgress(_ progress: CGFloat) {
        let clamped = max(0.0, min(1.0, progress))

        glassBackground.glassTintColor = .init(kind: .custom(style: .default, color: config.dimTintColor.withAlphaComponent(clamped)))
        glassBackground.contentView.backgroundColor = config.dimTintColor.withAlphaComponent(clamped)

        guard abs(detentProgress - clamped) > 0.0001 else { return }
        detentProgress = clamped
        updateMaskPath()
        delegate?.crystalModalController(self, didUpdateDetentProgress: clamped)
    }

    func applyCurrentDetent(_ detent: Detent) {
        guard currentDetent != detent else { return }
        currentDetent = detent
        delegate?.crystalModalController(self, didChangeDetent: detent)
    }

    func deviceCornerRadius() -> CGFloat {
        if let presentation = presentationController as? CrystalModalPresentationController {
            return presentation.deviceCornerRadius
        }
        return 39.0
    }

    private func layoutGlassAndContent() {
        // `.immediate` inside an outer UIView.animate is the right call:
        // it just sets frames/cornerRadius directly, and those direct sets
        // are captured by the enclosing CA transaction — so they inherit
        // the outer spring timing. A non-immediate transition here would
        // spawn a nested UIView.animate with its own damping (500 for
        // `.spring`), which doesn't match the caller's curve and makes
        // the glass race ahead of (or lag behind) the root frame.
        glassBackground.frame = view.bounds
        glassBackground.update(size: view.bounds.size, cornerRadius: 0.0, transition: .immediate)

        let grabberHeight = Self.grabberContainerHeight
        grabberContainer.frame = CGRect(
            x: 0.0,
            y: 0.0,
            width: view.bounds.width,
            height: grabberHeight
        )
        grabberView.frame = CGRect(
            x: (view.bounds.width - Self.grabberSize.width) / 2.0,
            y: (grabberHeight - Self.grabberSize.height) / 2.0,
            width: Self.grabberSize.width,
            height: Self.grabberSize.height
        )

        // Content sits below the grabber container — its coordinate space
        // starts at y = grabberHeight in modal space, so anything
        // positioned at y=0 inside the content (e.g. a navbar) appears
        // just under the grabber.
        contentContainer.frame = CGRect(
            x: 0.0,
            y: grabberHeight,
            width: view.bounds.width,
            height: max(0.0, view.bounds.height - grabberHeight)
        )
        content.view.frame = contentContainer.bounds
    }

    private func updateMaskPath() {
        let bounds = view.bounds
        let topRadius = config.topCornerRadius
        // Concentric bottom: subtract the sheet's distance from the screen
        // bottom from the device radius so the sheet's bottom corner nests
        // into the device chamfer. That distance interpolates between the
        // two detents' bottom insets via detentProgress.
        let deviceRadius = deviceCornerRadius()
        let stage1Radius = max(0.0, deviceRadius - config.bottomInsetStage1)
        let stage2Radius = max(0.0, deviceRadius - config.bottomInsetStage2)
        let bottomRadius = stage1Radius + (stage2Radius - stage1Radius) * detentProgress
        let newPath = Self.roundedRectPath(
            in: bounds,
            topLeftRadius: topRadius,
            topRightRadius: topRadius,
            bottomLeftRadius: bottomRadius,
            bottomRightRadius: bottomRadius
        ).cgPath

        let oldPath = maskLayer.path
        maskLayer.frame = bounds
        maskLayer.path = newPath

        if UIView.inheritedAnimationDuration <= 0, oldPath != newPath {
            maskLayer.removeAnimation(forKey: "path")
        }
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
