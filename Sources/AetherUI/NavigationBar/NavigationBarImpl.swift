import UIKit

private final class NavigationSeparatedButtonGlueAnimator: NSObject {
    private weak var container: UIView?
    private let groups: [GlassControlGroup]
    private let fromContainerFrame: CGRect
    private let toContainerFrame: CGRect
    private let fromFrames: [CGRect]
    private let toFrames: [CGRect]
    private let appearing: Bool
    private let duration: CFTimeInterval
    private let updateContainerEffects: (CGSize) -> Void
    private let completion: () -> Void
    private var displayLink: CADisplayLink?
    private var startTimestamp: CFTimeInterval?
    private var didComplete = false

    init(
        container: UIView,
        groups: [GlassControlGroup],
        fromContainerFrame: CGRect,
        toContainerFrame: CGRect,
        fromFrames: [CGRect],
        toFrames: [CGRect],
        appearing: Bool,
        duration: Double,
        updateContainerEffects: @escaping (CGSize) -> Void,
        completion: @escaping () -> Void
    ) {
        self.container = container
        self.groups = groups
        self.fromContainerFrame = fromContainerFrame
        self.toContainerFrame = toContainerFrame
        self.fromFrames = fromFrames
        self.toFrames = toFrames
        self.appearing = appearing
        self.duration = max(0.001, duration)
        self.updateContainerEffects = updateContainerEffects
        self.completion = completion
        super.init()
    }

    deinit {
        invalidate()
    }

    func start() {
        apply(progress: 0.0)
        let displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        if #available(iOS 15.0, *) {
            let maximumFramesPerSecond = UIScreen.main.maximumFramesPerSecond
            let preferred = Float(min(120, max(60, maximumFramesPerSecond > 0 ? maximumFramesPerSecond : 120)))
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: 60.0,
                maximum: preferred,
                preferred: preferred
            )
        }
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        if startTimestamp == nil {
            startTimestamp = displayLink.timestamp
        }
        let elapsed = displayLink.timestamp - (startTimestamp ?? displayLink.timestamp)
        let progress = min(1.0, max(0.0, elapsed / duration))
        apply(progress: CGFloat(progress))
        if progress >= 1.0 {
            finish()
        }
    }

    private func finish() {
        guard !didComplete else {
            return
        }
        didComplete = true
        invalidate()
        apply(progress: 1.0)
        completion()
    }

    private func apply(progress: CGFloat) {
        let eased = appearing ? easeOut(progress) : easeIn(progress)
        if let container {
            let frame = interpolate(from: fromContainerFrame, to: toContainerFrame, progress: eased)
            container.frame = frame
            updateContainerEffects(frame.size)
        }
        for index in 0 ..< min(groups.count, fromFrames.count, toFrames.count) {
            groups[index].frame = interpolate(from: fromFrames[index], to: toFrames[index], progress: eased)
        }
    }

    private func interpolate(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: from.minX + (to.minX - from.minX) * progress,
            y: from.minY + (to.minY - from.minY) * progress,
            width: from.width + (to.width - from.width) * progress,
            height: from.height + (to.height - from.height) * progress
        )
    }

    private func easeOut(_ t: CGFloat) -> CGFloat {
        1.0 - pow(1.0 - t, 3.0)
    }

    private func easeIn(_ t: CGFloat) -> CGFloat {
        pow(t, 3.0)
    }
}

/// Full UIKit implementation of NavigationBarView.
/// Pure UIKit implementation.
public final class NavigationBarImpl: UIView, NavigationBarView {
    // MARK: - Subviews

    public let backgroundView: NavigationBackgroundView
    public let stripeView: UIView
    private let clippingView: SparseView
    private let buttonsContainerView: UIView
    private let buttonLayer: AetherNavigationBarButtonLayer

    private let backButtonView: NavigationBackButtonView
    private let backArrowView: UIImageView
    private let titleLabel: UILabel
    private let subtitleLabel: UILabel
    private let leftButtonContainer: UIView
    private let rightButtonContainer: UIView
    private let leftButtonGlassContainer: GlassBackgroundContainerView
    private let rightButtonGlassContainer: GlassBackgroundContainerView
    /// Persistent glass group used for the left bar button items in glass mode
    /// (direct port equivalent of `leftButtonsBackgroundView`).
    private var leftButtonsGroup: GlassControlGroup?
    private var leftAdditionalButtonsGroups: [GlassControlGroup] = []
    /// Persistent glass group used for the right bar button items in glass mode.
    private var rightButtonsGroup: GlassControlGroup?
    private var rightAdditionalButtonsGroups: [GlassControlGroup] = []
    public let badgeView: NavigationBarBadgeView
    private var titleContentView: UIView?

    private var _contentView: NavigationBarContentView?
    public var contentView: NavigationBarContentView? { _contentView }

    private var glassBackgroundView: GlassBackgroundView?
    /// Scroll-edge fade effect. Hosts can move it outside the bar so the
    /// floating controls stay above content without the frost covering it.
    private var edgeEffectView: EdgeEffectView?
    public weak var edgeEffectHostView: UIView? {
        didSet {
            guard edgeEffectHostView !== oldValue else {
                return
            }
            rehostEdgeEffectView()
            setNeedsLayout()
        }
    }

    // MARK: - State

    public private(set) var presentationData: NavigationBarPresentationData
    private var validLayout: (size: CGSize, defaultHeight: CGFloat, leftInset: CGFloat, rightInset: CGFloat)?
    private var isSearchModeActive = false
    private var contentHeightOverride: CGFloat?

    /// Natural height of `titleContentView`, measured during `updateLayout` for
    /// the available width. The title row in `contentHeight(defaultHeight:)`
    /// is grown to `max(defaultHeight, measuredTitleHeight)` so a tall custom
    /// titleView (avatar + multi-line subtitle, etc.) is never clipped to the
    /// standard ~44pt button-row height.
    ///
    /// Buttons (left/right/back) keep their original `defaultHeight` slot at
    /// `y=0` of `buttonsContainerView` and never re-center when the title
    /// grows — only the title centers within the expanded container.
    private var measuredTitleHeight: CGFloat = 0

    public var backPressed: () -> Void = {}
    public var userInfo: Any?

    public var item: NavigationBarItem? {
        didSet {
            updateItemContent()
        }
    }

    public var previousItem: NavigationPreviousAction? {
        didSet {
            updateBackButton()
        }
    }

    public var enableAutomaticBackButton: Bool = true {
        didSet { updateBackButton() }
    }

    public var secondaryContentHeight: CGFloat = 0.0

    public var isBackgroundVisible: Bool {
        return backgroundView.alpha > 0.01
    }

    public var intrinsicCanTransitionInline: Bool = true
    public var canTransitionInline: Bool {
        return intrinsicCanTransitionInline && !isHidden
    }

    public var passthroughTouches: Bool = false
    public var layoutSuspended: Bool = false
    public var requestContainerLayout: ((ContainedViewLayoutTransition) -> Void)?
    private var titleTransitionMode: Bool = false
    private var titleContentHiddenForTransition: Bool = false
    private var buttonsOnlyTransitionMode: Bool = false
    private var buttonContentHiddenForTransition: Bool = false
    private var buttonMorphTransitionOverride: ContainedViewLayoutTransition?
    private var leftSeparatedButtonGlueAnimator: NavigationSeparatedButtonGlueAnimator?
    private var rightSeparatedButtonGlueAnimator: NavigationSeparatedButtonGlueAnimator?
    private var legacyLeftButtonViewsByID: [BarButtonID: UIView] = [:]
    private var legacyRightButtonViewsByID: [BarButtonID: UIView] = [:]
    private var appearingTitleContentViewIDs = Set<ObjectIdentifier>()
    private var appearingVisualViewIDs = Set<ObjectIdentifier>()
    private var disappearingVisualViewIDs = Set<ObjectIdentifier>()
    private var disappearingVisualInteractionByID: [ObjectIdentifier: Bool] = [:]
    private var buttonsRowAlpha: CGFloat = 1.0
    private var currentButtonsRowFrame: CGRect = .zero
    internal var hostsNavigationItemTitleView: Bool = true {
        didSet {
            guard oldValue != hostsNavigationItemTitleView else {
                return
            }
            updateItemContent()
        }
    }

    internal static var defaultButtonHostingMode: AetherNavigationBarButtonHostingMode = .separatedLayer
    internal var buttonHostingMode: AetherNavigationBarButtonHostingMode {
        didSet {
            guard oldValue != buttonHostingMode else {
                return
            }
            installButtonChromeViewsForCurrentHostingMode(preservePresentationLayer: true)
            installTitleContentViewForCurrentHostingMode(preservePresentationLayer: true)
        }
    }

    internal weak var buttonLayerHostView: UIView? {
        didSet {
            guard buttonLayerHostView !== oldValue else {
                return
            }
            installButtonLayerForCurrentHost(preservePresentationLayer: true)
            updateButtonLayerFrame(currentButtonsRowFrame, transition: .immediate)
            updateButtonLayerEffectiveVisibility()
        }
    }

    internal var debugButtonLayer: AetherNavigationBarButtonLayer {
        buttonLayer
    }

    internal var debugButtonsContainerView: UIView {
        buttonsContainerView
    }

    override public var alpha: CGFloat {
        didSet {
            updateButtonLayerEffectiveVisibility()
        }
    }

    override public var isHidden: Bool {
        didSet {
            updateButtonLayerEffectiveVisibility()
        }
    }

    public struct ButtonChromeLayout {
        public var leftFrame: CGRect?
        public var rightFrame: CGRect?

        public init(leftFrame: CGRect?, rightFrame: CGRect?) {
            self.leftFrame = leftFrame
            self.rightFrame = rightFrame
        }
    }

    /// Amount (in points) by which the scroll-edge frost is extended
    /// upward past the navbar's own top. Set by hosts that sit the bar
    /// below a visual chrome element (e.g. AetherModalController's
    /// grabber) so the frost covers that chrome too.
    public var edgeEffectTopExtension: CGFloat = 0.0 {
        didSet {
            if edgeEffectTopExtension != oldValue {
                setNeedsLayout()
            }
        }
    }

    // MARK: - Init

    public init(presentationData: NavigationBarPresentationData) {
        self.presentationData = presentationData
        let theme = presentationData.theme

        self.backgroundView = NavigationBackgroundView(color: theme.backgroundColor, enableBlur: theme.enableBackgroundBlur)
        self.stripeView = UIView()
        self.clippingView = SparseView()
        self.buttonsContainerView = UIView()
        self.buttonLayer = AetherNavigationBarButtonLayer()

        self.backButtonView = NavigationBackButtonView()
        self.backArrowView = UIImageView()
        self.titleLabel = UILabel()
        self.subtitleLabel = UILabel()
        self.leftButtonContainer = UIView()
        self.rightButtonContainer = UIView()
        self.leftButtonGlassContainer = GlassBackgroundContainerView(spacing: 7.0)
        self.rightButtonGlassContainer = GlassBackgroundContainerView(spacing: 7.0)
        self.badgeView = NavigationBarBadgeView()
        self.buttonHostingMode = Self.defaultButtonHostingMode

        super.init(frame: .zero)

        backButtonView.isHidden = true
        backArrowView.isHidden = true

        // Background
        addSubview(backgroundView)

        // Stripe (separator)
        stripeView.backgroundColor = theme.separatorColor
        addSubview(stripeView)

        // Clipping
        clippingView.clipsToBounds = theme.style != .glass
        addSubview(clippingView)

        // Buttons container
        clippingView.addSubview(buttonsContainerView)

        // Back arrow
        backArrowView.image = NavigationBarTheme.generateBackArrowImage(color: theme.buttonColor)
        backArrowView.contentMode = .center

        // Back button
        backButtonView.color = theme.buttonColor
        backButtonView.contentTintColor = theme.buttonColor
        // isDark is applied effectively in updateLayout / traitCollectionDidChange
        // so the glass pill responds to the system dark-mode switch, not just
        // the static theme flag. Kept static here for the very first frame.
        backButtonView.isDark = theme.overallDarkAppearance
        backButtonView.usesGlassStyle = theme.style == .glass
        backButtonView.icon = NavigationBarTheme.generateBackArrowImage(color: theme.buttonColor)
        backButtonView.action = { [weak self] in self?.backButtonPressed() }

        // Title
        titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel.textColor = theme.primaryTextColor
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        buttonsContainerView.addSubview(titleLabel)

        subtitleLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.isHidden = true
        buttonsContainerView.addSubview(subtitleLabel)

        // Left/Right button containers
        leftButtonContainer.clipsToBounds = false
        rightButtonContainer.clipsToBounds = false
        leftButtonContainer.addSubview(leftButtonGlassContainer)
        rightButtonContainer.addSubview(rightButtonGlassContainer)

        installButtonChromeViewsForCurrentHostingMode(preservePresentationLayer: false)

        // Glass style
        if theme.style == .glass {
            setupGlassBackground(theme: theme)
        }

        updateBackButton()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Trait collection

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Interface style change (dark ↔ light) must propagate to glass
        // children that bake `isDark` as a parameter (see updateLayout). A
        // full re-layout is the cheapest way to get every glass subview to
        // re-apply its dark override.
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            // Dismiss any context menu currently anchored to a bar button
            // BEFORE we tear down + rebuild the GlassControlGroup item
            // buttons. Otherwise the menu's `source.view` weak reference
            // ends up dangling, the morph-back-to-source step on dismiss
            // sees a nil/detached source, and the navbar's own group
            // layout gets stuck mid-rebuild.
            dismissPresentedBarButtonContextMenu()
            let isEffectivelyDark = presentationData.theme.overallDarkAppearance || traitCollection.userInterfaceStyle == .dark
            backButtonView.isDark = isEffectivelyDark
            if let layout = validLayout {
                updateLayout(
                    size: layout.size,
                    defaultHeight: layout.defaultHeight,
                    additionalTopHeight: 0,
                    additionalContentHeight: 0,
                    additionalBackgroundHeight: 0,
                    leftInset: layout.leftInset,
                    rightInset: layout.rightInset,
                    appearsHidden: false,
                    isLandscape: false,
                    transition: .immediate
                )
            }
        }
    }

    // MARK: - Hit Testing

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if passthroughTouches {
            // Only respond to touches on interactive elements
            let result = super.hitTest(point, with: event)
            if result === self || result === clippingView || result === buttonsContainerView || result === buttonLayer {
                return nil
            }
            return result
        }
        return super.hitTest(point, with: event)
    }

    private var usesSeparatedButtonHosting: Bool {
        buttonHostingMode == .separatedLayer
    }

    private var isButtonLayerExternallyHosted: Bool {
        usesSeparatedButtonHosting && buttonLayerHostView != nil && buttonLayer.superview !== self
    }

    private var buttonChromeViews: [UIView] {
        [backArrowView, backButtonView, leftButtonContainer, rightButtonContainer, badgeView]
    }

    private func resolvedButtonLayerHostView() -> UIView {
        buttonLayerHostView ?? self
    }

    private func buttonLayerFrame(for rowFrame: CGRect) -> CGRect {
        guard let buttonLayerHostView else {
            return rowFrame
        }
        if superview != nil {
            return convert(rowFrame, to: buttonLayerHostView)
        }
        return CGRect(
            x: frame.minX + rowFrame.minX,
            y: frame.minY + rowFrame.minY,
            width: rowFrame.width,
            height: rowFrame.height
        )
    }

    private func installButtonLayerForCurrentHost(preservePresentationLayer: Bool) {
        guard usesSeparatedButtonHosting else {
            buttonLayer.isHidden = true
            return
        }

        let hostView = resolvedButtonLayerHostView()
        if buttonLayer.superview !== hostView {
            AetherNavigationBarButtonLayer.reparentPreservingPresentation(
                view: buttonLayer,
                from: buttonLayer.superview,
                to: hostView,
                targetFrame: buttonLayerFrame(for: currentButtonsRowFrame),
                preservePresentationLayer: preservePresentationLayer
            )
        }
        updateButtonLayerEffectiveVisibility()
    }

    private func installButtonChromeViewsForCurrentHostingMode(preservePresentationLayer: Bool) {
        installButtonLayerForCurrentHost(preservePresentationLayer: preservePresentationLayer)

        let hostView: UIView = usesSeparatedButtonHosting ? buttonLayer : buttonsContainerView

        for view in buttonChromeViews where view.superview !== hostView {
            AetherNavigationBarButtonLayer.reparentPreservingPresentation(
                view: view,
                from: view.superview,
                to: hostView,
                targetFrame: view.frame,
                preservePresentationLayer: preservePresentationLayer
            )
        }

        if !usesSeparatedButtonHosting {
            buttonLayer.removeAllButtonPlacements(detachViews: false)
        }
    }

    private func installTitleContentViewForCurrentHostingMode(preservePresentationLayer: Bool) {
        guard let titleContentView else {
            buttonLayer.removeButtonPlacement(id: ButtonChromePlacementID.titleContentView, detachView: false)
            return
        }

        installButtonLayerForCurrentHost(preservePresentationLayer: preservePresentationLayer)
        let hostView: UIView = usesSeparatedButtonHosting ? buttonLayer : buttonsContainerView
        if titleContentView.superview !== hostView {
            AetherNavigationBarButtonLayer.reparentPreservingPresentation(
                view: titleContentView,
                from: titleContentView.superview,
                to: hostView,
                targetFrame: titleContentView.frame,
                preservePresentationLayer: preservePresentationLayer
            )
        }
        if !usesSeparatedButtonHosting {
            buttonLayer.removeButtonPlacement(id: ButtonChromePlacementID.titleContentView, detachView: false)
        }
    }

    private func updateButtonsRowFrame(_ frame: CGRect, transition: ContainedViewLayoutTransition) {
        currentButtonsRowFrame = frame
        let geometryTransition: ContainedViewLayoutTransition = buttonMorphTransitionOverride == nil ? transition : .immediate
        performMorphGeometryWithoutAnimation {
            geometryTransition.updateFrame(view: buttonsContainerView, frame: frame)
            if usesSeparatedButtonHosting {
                updateButtonLayerFrame(frame, transition: geometryTransition)
            }
        }
    }

    private func updateButtonLayerFrame(_ rowFrame: CGRect, transition: ContainedViewLayoutTransition) {
        guard usesSeparatedButtonHosting else {
            return
        }
        installButtonLayerForCurrentHost(preservePresentationLayer: transition.isAnimated)
        transition.updateFrame(view: buttonLayer, frame: buttonLayerFrame(for: rowFrame))
    }

    private func setButtonsRowAlpha(_ alpha: CGFloat) {
        buttonsRowAlpha = alpha
        buttonsContainerView.alpha = alpha
        updateButtonLayerEffectiveVisibility()
    }

    private func updateButtonLayerEffectiveVisibility() {
        guard usesSeparatedButtonHosting else {
            buttonLayer.isHidden = true
            buttonLayer.alpha = 1.0
            return
        }

        buttonLayer.isHidden = isButtonLayerExternallyHosted ? isHidden : false
        buttonLayer.alpha = buttonsRowAlpha * (isButtonLayerExternallyHosted ? alpha : 1.0)
    }

    internal func bringButtonLayerToFrontIfNeeded() {
        guard usesSeparatedButtonHosting, let superview = buttonLayer.superview, superview.subviews.last !== buttonLayer else {
            return
        }
        superview.bringSubviewToFront(buttonLayer)
    }

    internal func detachButtonLayerFromHost() {
        buttonLayer.removeFromSuperview()
    }

    private enum ButtonChromePlacementID: Hashable {
        case leftContainer
        case rightContainer
        case backButton
        case backArrow
        case badge
        case titleContentView
        case outgoingTitleContentView(ObjectIdentifier)
    }

    private func buttonChromePlacementID(for view: UIView) -> ButtonChromePlacementID? {
        if let titleContentView, view === titleContentView {
            return .titleContentView
        }
        if view === leftButtonContainer {
            return .leftContainer
        }
        if view === rightButtonContainer {
            return .rightContainer
        }
        if view === backButtonView {
            return .backButton
        }
        if view === backArrowView {
            return .backArrow
        }
        if view === badgeView {
            return .badge
        }
        return nil
    }

    private func buttonChromeAccessibilityOrder(for id: ButtonChromePlacementID) -> Int {
        switch id {
        case .backArrow:
            return 0
        case .backButton:
            return 1
        case .leftContainer:
            return 2
        case .titleContentView:
            return 3
        case .outgoingTitleContentView:
            return 3
        case .rightContainer:
            return 4
        case .badge:
            return 5
        }
    }

    private func buttonChromeZIndex(for id: ButtonChromePlacementID) -> CGFloat {
        switch id {
        case .backArrow:
            return 0
        case .backButton:
            return 1
        case .leftContainer:
            return 2
        case .rightContainer:
            return 2
        case .titleContentView:
            return 2.5
        case .outgoingTitleContentView:
            return 2.5
        case .badge:
            return 3
        }
    }

    private func activeButtonMorphTransition() -> ContainedViewLayoutTransition? {
        guard let transition = buttonMorphTransitionOverride, transition.isAnimated else {
            return nil
        }
        return transition
    }

    private func performMorphGeometryWithoutAnimation(_ body: () -> Void) {
        guard buttonMorphTransitionOverride != nil else {
            body()
            return
        }
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            body()
            CATransaction.commit()
        }
    }

    private func buttonEffectTransition(appearing: Bool, from transition: ContainedViewLayoutTransition) -> ContainedViewLayoutTransition {
        guard transition.isAnimated else {
            return .immediate
        }
        let curve: ContainedViewLayoutTransitionCurve = appearing
            ? .custom(0.16, 1.0, 0.30, 1.0)
            : .custom(0.70, 0.0, 0.84, 0.0)
        return .animated(duration: transition.duration, curve: curve)
    }

    private func prepareAppearingVisualView(_ view: UIView, targetTransform: CGAffineTransform = .identity) {
        performMorphGeometryWithoutAnimation {
            view.alpha = 0.0
            view.transform = targetTransform.scaledBy(x: 0.94, y: 0.94)
            ContainedViewLayoutTransition.immediate.setBlur(layer: view.layer, radius: 10.0)
        }
    }

    private func animateAppearingVisualView(
        _ view: UIView,
        transition: ContainedViewLayoutTransition,
        targetTransform: CGAffineTransform = .identity
    ) {
        let id = ObjectIdentifier(view)
        appearingVisualViewIDs.insert(id)
        let effectTransition = buttonEffectTransition(appearing: true, from: transition)
        effectTransition.updateAlpha(view: view, alpha: 1.0) { [weak self] _ in
            self?.appearingVisualViewIDs.remove(id)
        }
        effectTransition.updateTransform(view: view, transform: targetTransform)
        effectTransition.setBlur(layer: view.layer, radius: 0.0)
        applyButtonOverspringPulseIfNeeded(to: view, amplitude: buttonPulseAmplitude(appearing: true), transition: effectTransition)
    }

    private func animateDisappearingVisualView(
        _ view: UIView,
        transition: ContainedViewLayoutTransition?,
        completion: (() -> Void)? = nil
    ) {
        let id = ObjectIdentifier(view)
        guard !disappearingVisualViewIDs.contains(id) else {
            return
        }
        let originalTransform = view.transform

        guard let transition, transition.isAnimated else {
            view.removeFromSuperview()
            view.alpha = 1.0
            view.transform = originalTransform
            ContainedViewLayoutTransition.immediate.setBlur(layer: view.layer, radius: 0.0)
            completion?()
            return
        }

        disappearingVisualViewIDs.insert(id)
        let wasUserInteractionEnabled = view.isUserInteractionEnabled
        disappearingVisualInteractionByID[id] = wasUserInteractionEnabled
        view.isUserInteractionEnabled = false
        let effectTransition = buttonEffectTransition(appearing: false, from: transition)
        effectTransition.updateAlpha(view: view, alpha: 0.0) { [weak self, weak view] _ in
            guard let self else { return }
            guard self.disappearingVisualViewIDs.remove(id) != nil else {
                return
            }
            let restoredUserInteraction = self.disappearingVisualInteractionByID.removeValue(forKey: id) ?? wasUserInteractionEnabled
            guard let view else {
                completion?()
                return
            }
            view.removeFromSuperview()
            view.alpha = 1.0
            view.transform = originalTransform
            view.isUserInteractionEnabled = restoredUserInteraction
            ContainedViewLayoutTransition.immediate.setBlur(layer: view.layer, radius: 0.0)
            completion?()
        }
        effectTransition.updateTransform(view: view, transform: originalTransform.scaledBy(x: 0.94, y: 0.94))
        effectTransition.setBlur(layer: view.layer, radius: 10.0)
        applyButtonOverspringPulseIfNeeded(to: view, amplitude: buttonPulseAmplitude(appearing: false), transition: effectTransition)
    }

    private func buttonPulseAmplitude(appearing: Bool) -> CGFloat {
        appearing ? 0.115 : -0.115
    }

    private func legacyButtonViews(for alignment: ButtonAlignment) -> [BarButtonID: UIView] {
        switch alignment {
        case .left:
            return legacyLeftButtonViewsByID
        case .right:
            return legacyRightButtonViewsByID
        }
    }

    private func legacyButtonView(for id: BarButtonID, alignment: ButtonAlignment) -> UIView? {
        switch alignment {
        case .left:
            return legacyLeftButtonViewsByID[id]
        case .right:
            return legacyRightButtonViewsByID[id]
        }
    }

    private func setLegacyButtonView(_ view: UIView?, for id: BarButtonID, alignment: ButtonAlignment) {
        switch alignment {
        case .left:
            legacyLeftButtonViewsByID[id] = view
        case .right:
            legacyRightButtonViewsByID[id] = view
        }
    }

    private func clearLegacyButtonViews(alignment: ButtonAlignment) {
        switch alignment {
        case .left:
            legacyLeftButtonViewsByID.removeAll()
        case .right:
            legacyRightButtonViewsByID.removeAll()
        }
    }

    private func applyButtonLayerPlacement(
        id: ButtonChromePlacementID,
        view: UIView,
        frame: CGRect,
        alpha: CGFloat,
        transform: CGAffineTransform,
        isHidden: Bool,
        isUserInteractionEnabled: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        let preservePresentationLayer = transition.isAnimated && buttonMorphTransitionOverride == nil
        installButtonLayerForCurrentHost(preservePresentationLayer: preservePresentationLayer)
        buttonLayer.applyButtonPlacements(
            [
                AetherNavigationBarButtonPlacement(
                    id: id,
                    view: view,
                    frame: frame,
                    alpha: alpha,
                    transform: transform,
                    isHidden: isHidden,
                    zIndex: buttonChromeZIndex(for: id),
                    accessibilityOrder: buttonChromeAccessibilityOrder(for: id),
                    isUserInteractionEnabled: isUserInteractionEnabled,
                    preservePresentationLayer: preservePresentationLayer
                )
            ],
            transition: .existing(transition),
            removesMissing: false
        )
    }

    private func updateButtonLayerHostedView(
        view: UIView,
        frame: CGRect? = nil,
        alpha: CGFloat? = nil,
        transform: CGAffineTransform? = nil,
        transition: ContainedViewLayoutTransition
    ) {
        guard usesSeparatedButtonHosting, let id = buttonChromePlacementID(for: view) else {
            if let frame {
                transition.updateFrame(view: view, frame: frame)
            }
            if let alpha {
                transition.updateAlpha(view: view, alpha: alpha)
            }
            if let transform {
                transition.updateTransform(view: view, transform: transform)
            }
            return
        }

        let preservePresentationLayer = transition.isAnimated && buttonMorphTransitionOverride == nil
        if id == .titleContentView {
            installTitleContentViewForCurrentHostingMode(preservePresentationLayer: preservePresentationLayer)
        } else {
            installButtonChromeViewsForCurrentHostingMode(preservePresentationLayer: preservePresentationLayer)
        }
        applyButtonLayerPlacement(
            id: id,
            view: view,
            frame: frame ?? view.frame,
            alpha: alpha ?? view.alpha,
            transform: transform ?? view.transform,
            isHidden: view.isHidden,
            isUserInteractionEnabled: view.isUserInteractionEnabled,
            transition: transition
        )
    }

    private func updateButtonChromeFrame(
        view: UIView,
        frame: CGRect,
        transition: ContainedViewLayoutTransition
    ) {
        updateButtonLayerHostedView(view: view, frame: frame, transition: transition)
    }

    private func animateOutgoingTitleContentView(_ view: UIView, transition: ContainedViewLayoutTransition?) {
        let id = ButtonChromePlacementID.outgoingTitleContentView(ObjectIdentifier(view))
        if usesSeparatedButtonHosting {
            applyButtonLayerPlacement(
                id: id,
                view: view,
                frame: view.frame,
                alpha: view.alpha,
                transform: view.transform,
                isHidden: view.isHidden,
                isUserInteractionEnabled: view.isUserInteractionEnabled,
                transition: .immediate
            )
        }
        animateDisappearingVisualView(view, transition: transition) { [weak self] in
            self?.buttonLayer.removeButtonPlacement(id: id, detachView: false)
        }
    }

    // MARK: - NavigationBarView Protocol

    private var ownedContentView: NavigationBarContentView? {
        guard let contentView = _contentView, contentView.superview === clippingView else {
            return nil
        }
        return contentView
    }

    public func setContentHeightOverride(_ height: CGFloat?) {
        contentHeightOverride = height
    }

    public func contentHeight(defaultHeight: CGFloat) -> CGFloat {
        if let contentHeightOverride {
            return contentHeightOverride
        }
        if isSearchModeActive, let contentView = ownedContentView {
            // Search mode: only the search pill height, no title row or filters
            if let stacked = contentView as? AetherStackedBarContent {
                // Use only the first child's height (search pill)
                return stacked.views.first?.nominalHeight ?? contentView.height
            }
            return contentView.height
        }
        let titleAreaHeight = max(defaultHeight, measuredTitleHeight)
        if let contentView = ownedContentView {
            switch contentView.mode {
            case .replacement:
                return contentView.height
            case .expansion:
                return titleAreaHeight + contentView.height
            }
        }
        return titleAreaHeight
    }

    public func setContentView(_ contentView: NavigationBarContentView?, animated: Bool) {
        // iOS 26-style "glass replacement": the outgoing content softly
        // fades with a tiny shrink, the incoming content emerges with a
        // tiny grow. Both run concurrently so the swap feels like a fluid
        // morph rather than a fade-out-then-in.
        let fadeOutScale: CGFloat = 0.94
        let fadeInScaleStart: CGFloat = 0.94

        if let old = _contentView, old !== contentView {
            let ownsOldContent = old.superview === clippingView
            if animated {
                if ownsOldContent {
                    UIView.animate(
                        withDuration: 0.28,
                        delay: 0,
                        options: [.curveEaseIn, .beginFromCurrentState],
                        animations: {
                            old.alpha = 0.0
                            old.transform = CGAffineTransform(scaleX: fadeOutScale, y: fadeOutScale)
                        },
                        completion: { [weak self, weak old] _ in
                            // Race guard: a later setContentView call may have
                            // re-attached `old` as the new _contentView. Only
                            // remove it if the bar is no longer using it —
                            // otherwise a stale completion would yank the view
                            // out from under a fresh re-add (this was causing
                            // the filter bar to disappear after tab switches
                            // that were preceded by a push/pop animation).
                            guard let old else { return }
                            if self?._contentView === old {
                                // Re-used — restore visual state so it's visible.
                                old.alpha = 1.0
                                old.transform = .identity
                            } else if old.superview === self?.clippingView {
                                old.removeFromSuperview()
                                old.alpha = 1.0
                                old.transform = .identity
                            } else {
                                old.alpha = 1.0
                                old.transform = .identity
                            }
                        }
                    )
                }
            } else {
                if ownsOldContent {
                    old.removeFromSuperview()
                    old.alpha = 1.0
                    old.transform = .identity
                }
            }
        }

        _contentView = contentView

        if let contentView = contentView {
            contentView.requestContainerLayout = { [weak self] transition in
                self?.requestContainerLayout?(transition)
            }
            if contentView.superview !== clippingView {
                clippingView.addSubview(contentView)
            }

            if animated {
                contentView.alpha = 0.0
                contentView.transform = CGAffineTransform(scaleX: fadeInScaleStart, y: fadeInScaleStart)
                UIView.animate(
                    withDuration: 0.32,
                    delay: 0,
                    options: [.curveEaseOut, .beginFromCurrentState],
                    animations: {
                        contentView.alpha = 1.0
                        contentView.transform = .identity
                    },
                    completion: nil
                )
            } else {
                // Always land at visible + identity when the swap is
                // non-animated — `contentView` may have been left at
                // alpha 0 / scaled by a prior fade-out that was
                // interrupted.
                contentView.alpha = 1.0
                contentView.transform = .identity
            }
        }

        // Honour the caller's `animated` flag for the outer layout too.
        // Previously this always fired an animated spring layout even on
        // tab switches (which pass animated: false expecting an instant
        // state swap). That made the bar re-lay-out with a 0.3s spring,
        // which the user sees as an "extra" animation.
        requestContainerLayout?(animated ? .animated(duration: 0.3, curve: .spring) : .immediate)
    }

    public func executeBack() -> Bool {
        backPressed()
        return true
    }

    public func setHidden(_ hidden: Bool, animated: Bool) {
        if animated {
            UIView.animate(withDuration: 0.3) {
                self.alpha = hidden ? 0.0 : 1.0
            }
        } else {
            self.alpha = hidden ? 0.0 : 1.0
        }
    }

    public func setTitleTransitionMode(_ enabled: Bool) {
        titleTransitionMode = enabled
        isUserInteractionEnabled = !enabled
        if enabled {
            applyTransitionVisibilityState()
        } else {
            updateBackButton()
        }
    }

    public func setTitleContentHiddenForTransition(_ hidden: Bool) {
        titleContentHiddenForTransition = hidden
        applyTransitionVisibilityState()
    }

    public func setButtonsOnlyTransitionMode(_ enabled: Bool) {
        buttonsOnlyTransitionMode = enabled
        isUserInteractionEnabled = !enabled
        applyTransitionVisibilityState()
    }

    public func setButtonContentHiddenForTransition(_ hidden: Bool) {
        buttonContentHiddenForTransition = hidden
        applyTransitionVisibilityState()
    }

    public func setButtonChromeScale(_ scale: CGFloat, transition: ContainedViewLayoutTransition) {
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        updateButtonLayerHostedView(view: leftButtonContainer, transform: transform, transition: transition)
        updateButtonLayerHostedView(view: rightButtonContainer, transform: transform, transition: transition)
        updateButtonLayerHostedView(view: backButtonView, transform: transform, transition: transition)
        updateButtonLayerHostedView(view: backArrowView, transform: transform, transition: transition)
        updateButtonLayerHostedView(view: badgeView, transform: transform, transition: transition)
    }

    public func buttonChromeLayout() -> ButtonChromeLayout {
        return ButtonChromeLayout(
            leftFrame: buttonChromeFrame(container: leftButtonContainer, groups: glassButtonGroups(for: .left)),
            rightFrame: buttonChromeFrame(container: rightButtonContainer, groups: glassButtonGroups(for: .right))
        )
    }

    var hasPureAutomaticBackButtonGroup: Bool {
        return glassButtonGroups(for: .left).contains { group in
            isPureAutomaticBackButtonGroup(group, in: leftButtonContainer)
        }
    }

    public func setButtonChromeLayout(_ layout: ButtonChromeLayout, transition: ContainedViewLayoutTransition, appearing: Bool? = nil) {
        applyButtonChromeFrame(layout.leftFrame, container: leftButtonContainer, groups: glassButtonGroups(for: .left), alignment: .leading, transition: transition, appearing: appearing)
        applyButtonChromeFrame(layout.rightFrame, container: rightButtonContainer, groups: glassButtonGroups(for: .right), alignment: .trailing, transition: transition, appearing: appearing)
    }

    public func setButtonChromeAlpha(left: CGFloat, right: CGFloat, keepsPureBackButtonStable: Bool = false, transition: ContainedViewLayoutTransition) {
        applyButtonChromeAlpha(left, container: leftButtonContainer, groups: glassButtonGroups(for: .left), keepsPureBackButtonStable: keepsPureBackButtonStable, transition: transition)
        applyButtonChromeAlpha(right, container: rightButtonContainer, groups: glassButtonGroups(for: .right), keepsPureBackButtonStable: false, transition: transition)
    }

    public func setButtonTransitionEffects(alpha: CGFloat, blurRadius: CGFloat, scale: CGFloat, horizontalScale: CGFloat = 1.0, pulseAmplitude: CGFloat = 0.0, keepsPureBackButtonStable: Bool = false, transition: ContainedViewLayoutTransition) {
        leftButtonContainer.alpha = 1.0
        rightButtonContainer.alpha = 1.0
        ContainedViewLayoutTransition.immediate.setBlur(layer: leftButtonContainer.layer, radius: 0.0)
        ContainedViewLayoutTransition.immediate.setBlur(layer: rightButtonContainer.layer, radius: 0.0)

        applyButtonContentTransitionEffects(
            container: leftButtonContainer,
            groups: glassButtonGroups(for: .left),
            alpha: alpha,
            blurRadius: blurRadius,
            scale: scale,
            horizontalScale: horizontalScale,
            pulseAmplitude: pulseAmplitude,
            keepsPureBackButtonStable: keepsPureBackButtonStable,
            transition: transition
        )
        applyButtonContentTransitionEffects(
            container: rightButtonContainer,
            groups: glassButtonGroups(for: .right),
            alpha: alpha,
            blurRadius: blurRadius,
            scale: scale,
            horizontalScale: horizontalScale,
            pulseAmplitude: pulseAmplitude,
            keepsPureBackButtonStable: false,
            transition: transition
        )
        let transform = CGAffineTransform(scaleX: scale * horizontalScale, y: scale)
        updateButtonLayerHostedView(view: backButtonView, alpha: alpha, transform: transform, transition: transition)
        updateButtonLayerHostedView(view: backArrowView, alpha: alpha, transform: transform, transition: transition)
        updateButtonLayerHostedView(view: badgeView, alpha: alpha, transform: transform, transition: transition)
        transition.setBlur(layer: backButtonView.layer, radius: blurRadius)
        transition.setBlur(layer: backArrowView.layer, radius: blurRadius)
        transition.setBlur(layer: badgeView.layer, radius: blurRadius)
        applyButtonOverspringPulseIfNeeded(to: backButtonView, amplitude: pulseAmplitude, transition: transition)
        applyButtonOverspringPulseIfNeeded(to: backArrowView, amplitude: pulseAmplitude, transition: transition)
        applyButtonOverspringPulseIfNeeded(to: badgeView, amplitude: pulseAmplitude, transition: transition)
    }

    public func setButtonContentTransform(scale: CGFloat, horizontalScale: CGFloat = 1.0, transition: ContainedViewLayoutTransition) {
        applyButtonContentTransform(container: leftButtonContainer, groups: glassButtonGroups(for: .left), scale: scale, horizontalScale: horizontalScale, transition: transition)
        applyButtonContentTransform(container: rightButtonContainer, groups: glassButtonGroups(for: .right), scale: scale, horizontalScale: horizontalScale, transition: transition)
        let transform = CGAffineTransform(scaleX: scale * horizontalScale, y: scale)
        updateButtonLayerHostedView(view: backButtonView, transform: transform, transition: transition)
        updateButtonLayerHostedView(view: backArrowView, transform: transform, transition: transition)
        updateButtonLayerHostedView(view: badgeView, transform: transform, transition: transition)
    }

    private func buttonChromeFrame(container: UIView, groups: [GlassControlGroup]) -> CGRect? {
        guard !container.isHidden, container.bounds.width > 0.0, container.bounds.height > 0.0 else {
            return nil
        }
        if groups.contains(where: { isGlassButtonGroup($0, hostedIn: container) && !$0.items.isEmpty }) {
            return container.frame
        }
        let hasVisibleSubview = container.subviews.contains { subview in
            !isButtonGlassContainer(subview, for: container) &&
            !subview.isHidden && subview.alpha > 0.01 && subview.bounds.width > 0.0 && subview.bounds.height > 0.0
        }
        return hasVisibleSubview ? container.frame : nil
    }

    private func applyButtonChromeFrame(
        _ frame: CGRect?,
        container: UIView,
        groups: [GlassControlGroup],
        alignment: GlassControlGroup.TransitionChromeContentAlignment,
        transition: ContainedViewLayoutTransition,
        appearing: Bool?
    ) {
        guard let frame else {
            return
        }
        container.clipsToBounds = false
        if groups.count > 1 {
            let visibleGroups = groups.filter { isGlassButtonGroup($0, hostedIn: container) }
            guard !visibleGroups.isEmpty else {
                updateButtonChromeFrame(view: container, frame: frame, transition: transition)
                updateButtonGlassContainer(in: container, size: frame.size, transition: transition)
                return
            }
            let spacing: CGFloat = 8.0
            let naturalTotalWidth = visibleGroups.enumerated().reduce(CGFloat(0.0)) { partial, entry in
                partial + entry.element.bounds.width + (entry.offset < visibleGroups.count - 1 ? spacing : 0.0)
            }
            let targetFrame = frame

            var finalGroupFrames: [(group: GlassControlGroup, frame: CGRect)] = []
            finalGroupFrames.reserveCapacity(visibleGroups.count)
            var finalGroupX: CGFloat = 0.0
            for group in visibleGroups {
                let size = group.bounds.size
                finalGroupFrames.append((group, CGRect(x: finalGroupX, y: 0.0, width: size.width, height: size.height)))
                finalGroupX += size.width + spacing
            }

            if transition.isAnimated, let appearing {
                animateSeparatedButtonGlue(
                    entries: finalGroupFrames,
                    naturalTotalWidth: naturalTotalWidth,
                    targetContainerFrame: targetFrame,
                    alignment: alignment,
                    appearing: appearing,
                    transition: transition,
                    container: container
                )
            } else {
                setSeparatedButtonGlueAnimator(nil, for: container)
                updateButtonChromeFrame(view: container, frame: targetFrame, transition: transition)
                updateButtonGlassContainer(in: container, size: targetFrame.size, transition: transition)
                let measuredProgress = separatedButtonLayoutProgress(
                    finalFrames: finalGroupFrames.map(\.frame),
                    naturalTotalWidth: naturalTotalWidth,
                    containerWidth: targetFrame.width,
                    alignment: alignment
                )
                let progress: CGFloat = appearing == true && targetFrame.width < naturalTotalWidth - 0.5 ? 0.0 : measuredProgress
                let frames = separatedButtonFrames(
                    finalFrames: finalGroupFrames.map(\.frame),
                    naturalTotalWidth: naturalTotalWidth,
                    containerWidth: targetFrame.width,
                    alignment: alignment,
                    progress: progress
                )
                for index in 0 ..< min(finalGroupFrames.count, frames.count) {
                    transition.updateFrame(view: finalGroupFrames[index].group, frame: frames[index])
                }
            }
        } else {
            updateButtonChromeFrame(view: container, frame: frame, transition: transition)
            updateButtonGlassContainer(in: container, size: frame.size, transition: transition)
        }

        if groups.count == 1, let group = groups.first, isGlassButtonGroup(group, hostedIn: container) {
            let finalFrame = CGRect(origin: .zero, size: frame.size)
            group.setTransitionChromeFrame(finalFrame, contentAlignment: alignment, transition: transition)
        }
    }

    private func separatedButtonFrames(
        finalFrames: [CGRect],
        naturalTotalWidth: CGFloat,
        containerWidth: CGFloat,
        alignment: GlassControlGroup.TransitionChromeContentAlignment,
        progress: CGFloat
    ) -> [CGRect] {
        guard finalFrames.count > 1 else {
            return finalFrames
        }
        let clampedProgress = max(0.0, min(1.0, progress))
        return finalFrames.map { frame in
            let collapsedX: CGFloat
            let finalX: CGFloat
            switch alignment {
            case .leading:
                collapsedX = 0.0
                finalX = frame.minX
            case .trailing:
                collapsedX = containerWidth - frame.width
                finalX = containerWidth - naturalTotalWidth + frame.minX
            }
            return CGRect(
                x: collapsedX + (finalX - collapsedX) * clampedProgress,
                y: frame.minY,
                width: frame.width,
                height: frame.height
            )
        }
    }

    private func animateSeparatedButtonGlue(
        entries: [(group: GlassControlGroup, frame: CGRect)],
        naturalTotalWidth: CGFloat,
        targetContainerFrame: CGRect,
        alignment: GlassControlGroup.TransitionChromeContentAlignment,
        appearing: Bool,
        transition: ContainedViewLayoutTransition,
        container: UIView
    ) {
        let groups = entries.map(\.group)
        let finalFrames = entries.map(\.frame)
        guard !groups.isEmpty else {
            return
        }
        guard transition.isAnimated else {
            for entry in entries {
                entry.group.frame = entry.frame
            }
            return
        }

        let currentContainerFrame = container.layer.presentation()?.frame ?? container.frame
        let targetFrame = targetContainerFrame
        let collapsedWidth = separatedButtonCollapsedWidth(
            finalFrames: finalFrames,
            fallback: min(targetFrame.width, targetFrame.height),
            alignment: alignment
        )
        let shouldUseCurrentFrame = currentContainerFrame.width > 0.0 && abs(currentContainerFrame.width - targetFrame.width) > 0.5
        let startContainerFrame: CGRect
        if appearing {
            if shouldUseCurrentFrame {
                startContainerFrame = currentContainerFrame
            } else {
                startContainerFrame = collapsedButtonContainerFrame(
                    from: targetFrame,
                    collapsedWidth: collapsedWidth,
                    alignment: alignment
                )
            }
        } else {
            startContainerFrame = shouldUseCurrentFrame ? currentContainerFrame : targetFrame
        }
        let endContainerFrame: CGRect
        if appearing {
            endContainerFrame = targetFrame
        } else {
            endContainerFrame = collapsedButtonContainerFrame(
                from: targetFrame,
                collapsedWidth: min(max(targetFrame.width, collapsedWidth), max(naturalTotalWidth, collapsedWidth)),
                alignment: alignment
            )
        }

        let collapsedStartFrames = separatedButtonFrames(
            finalFrames: finalFrames,
            naturalTotalWidth: naturalTotalWidth,
            containerWidth: startContainerFrame.width,
            alignment: alignment,
            progress: 0.0
        )
        let collapsedEndFrames = separatedButtonFrames(
            finalFrames: finalFrames,
            naturalTotalWidth: naturalTotalWidth,
            containerWidth: endContainerFrame.width,
            alignment: alignment,
            progress: 0.0
        )
        let targetFrames = separatedButtonFrames(
            finalFrames: finalFrames,
            naturalTotalWidth: naturalTotalWidth,
            containerWidth: endContainerFrame.width,
            alignment: alignment,
            progress: 1.0
        )
        let currentFrames = groups.map { group in
            group.layer.presentation()?.frame ?? group.frame
        }
        let fromFrames: [CGRect]
        let toFrames: [CGRect]
        if appearing {
            fromFrames = shouldUseCurrentFrame ? currentFrames : collapsedStartFrames
            toFrames = targetFrames
        } else {
            fromFrames = shouldUseCurrentFrame ? currentFrames : separatedButtonFrames(
                finalFrames: finalFrames,
                naturalTotalWidth: naturalTotalWidth,
                containerWidth: startContainerFrame.width,
                alignment: alignment,
                progress: 1.0
            )
            toFrames = collapsedEndFrames
        }
        let animator = NavigationSeparatedButtonGlueAnimator(
            container: container,
            groups: groups,
            fromContainerFrame: startContainerFrame,
            toContainerFrame: endContainerFrame,
            fromFrames: fromFrames,
            toFrames: toFrames,
            appearing: appearing,
            duration: max(0.28, transition.duration),
            updateContainerEffects: { [weak self, weak container] size in
                guard let self, let container else {
                    return
                }
                self.updateButtonGlassContainer(in: container, size: size, transition: .immediate)
            },
            completion: { [weak self, weak container] in
                guard let self, let container else {
                    return
                }
                self.setSeparatedButtonGlueAnimator(nil, for: container, invalidating: false)
            }
        )
        setSeparatedButtonGlueAnimator(animator, for: container)
        animator.start()
    }

    private func separatedButtonLayoutProgress(
        finalFrames: [CGRect],
        naturalTotalWidth: CGFloat,
        containerWidth: CGFloat,
        alignment: GlassControlGroup.TransitionChromeContentAlignment
    ) -> CGFloat {
        guard finalFrames.count > 1, naturalTotalWidth > 0.0 else {
            return 1.0
        }
        let collapsedWidth = separatedButtonCollapsedWidth(
            finalFrames: finalFrames,
            fallback: min(naturalTotalWidth, containerWidth),
            alignment: alignment
        )
        let denominator = max(1.0, naturalTotalWidth - collapsedWidth)
        return max(0.0, min(1.0, (containerWidth - collapsedWidth) / denominator))
    }

    private func separatedButtonCollapsedWidth(
        finalFrames: [CGRect],
        fallback: CGFloat,
        alignment: GlassControlGroup.TransitionChromeContentAlignment
    ) -> CGFloat {
        guard !finalFrames.isEmpty else {
            return max(1.0, fallback)
        }
        switch alignment {
        case .leading:
            return max(1.0, finalFrames.first?.width ?? fallback)
        case .trailing:
            return max(1.0, finalFrames.last?.width ?? fallback)
        }
    }

    private func collapsedButtonContainerFrame(
        from frame: CGRect,
        collapsedWidth: CGFloat,
        alignment: GlassControlGroup.TransitionChromeContentAlignment
    ) -> CGRect {
        let width = max(1.0, min(max(frame.width, 1.0), collapsedWidth))
        switch alignment {
        case .leading:
            return CGRect(x: frame.minX, y: frame.minY, width: width, height: frame.height)
        case .trailing:
            return CGRect(x: frame.maxX - width, y: frame.minY, width: width, height: frame.height)
        }
    }

    private func setSeparatedButtonGlueAnimator(
        _ animator: NavigationSeparatedButtonGlueAnimator?,
        for container: UIView,
        invalidating: Bool = true
    ) {
        if container === leftButtonContainer {
            if invalidating {
                leftSeparatedButtonGlueAnimator?.invalidate()
            }
            leftSeparatedButtonGlueAnimator = animator
        } else if container === rightButtonContainer {
            if invalidating {
                rightSeparatedButtonGlueAnimator?.invalidate()
            }
            rightSeparatedButtonGlueAnimator = animator
        }
    }

    private func applyButtonChromeAlpha(
        _ alpha: CGFloat,
        container: UIView,
        groups: [GlassControlGroup],
        keepsPureBackButtonStable: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        let groupSet = Set(groups.map { ObjectIdentifier($0) })
        for group in groups where isGlassButtonGroup(group, hostedIn: container) {
            let resolvedAlpha = keepsPureBackButtonStable && isPureAutomaticBackButtonGroup(group, in: container) ? 1.0 : alpha
            group.setTransitionChromeAlpha(resolvedAlpha, transition: transition)
        }
        for subview in container.subviews where !groupSet.contains(ObjectIdentifier(subview)) && !isButtonGlassContainer(subview, for: container) {
            transition.updateAlpha(view: subview, alpha: alpha)
        }
    }

    private func applyButtonContentTransitionEffects(
        container: UIView,
        groups: [GlassControlGroup],
        alpha: CGFloat,
        blurRadius: CGFloat,
        scale: CGFloat,
        horizontalScale: CGFloat,
        pulseAmplitude: CGFloat,
        keepsPureBackButtonStable: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        let groupSet = Set(groups.map { ObjectIdentifier($0) })
        for group in groups where isGlassButtonGroup(group, hostedIn: container) {
            group.alpha = 1.0
            ContainedViewLayoutTransition.immediate.setBlur(layer: group.layer, radius: 0.0)
            if keepsPureBackButtonStable && isPureAutomaticBackButtonGroup(group, in: container) {
                group.setContentTransitionEffects(alpha: 1.0, blurRadius: 0.0, scale: 1.0, horizontalScale: 1.0, pulseAmplitude: 0.0, transition: transition)
            } else {
                group.setContentTransitionEffects(alpha: alpha, blurRadius: blurRadius, scale: scale, horizontalScale: horizontalScale, pulseAmplitude: pulseAmplitude, transition: transition)
            }
        }

        let transform = CGAffineTransform(scaleX: scale * horizontalScale, y: scale)
        for subview in container.subviews where !groupSet.contains(ObjectIdentifier(subview)) && !isButtonGlassContainer(subview, for: container) {
            transition.updateAlpha(view: subview, alpha: alpha)
            transition.setBlur(layer: subview.layer, radius: blurRadius)
            transition.updateTransform(view: subview, transform: transform)
            applyButtonOverspringPulseIfNeeded(to: subview, amplitude: pulseAmplitude, transition: transition)
        }
    }

    private func applyButtonContentTransform(
        container: UIView,
        groups: [GlassControlGroup],
        scale: CGFloat,
        horizontalScale: CGFloat,
        transition: ContainedViewLayoutTransition
    ) {
        let groupSet = Set(groups.map { ObjectIdentifier($0) })
        for group in groups where isGlassButtonGroup(group, hostedIn: container) {
            group.setContentTransform(scale: scale, horizontalScale: horizontalScale, transition: transition)
        }

        let transform = CGAffineTransform(scaleX: scale * horizontalScale, y: scale)
        for subview in container.subviews where !groupSet.contains(ObjectIdentifier(subview)) && !isButtonGlassContainer(subview, for: container) {
            transition.updateTransform(view: subview, transform: transform)
        }
    }

    private func isPureAutomaticBackButtonGroup(_ group: GlassControlGroup, in container: UIView) -> Bool {
        guard container === leftButtonContainer,
              group.items.count == 1,
              let item = group.items.first else {
            return false
        }
        return item.id == AnyHashable(automaticBackButtonID(alignment: .left))
    }

    private func applyButtonOverspringPulseIfNeeded(to view: UIView, amplitude: CGFloat, transition: ContainedViewLayoutTransition) {
        let resolvedAmplitude = abs(amplitude)
        guard resolvedAmplitude > 0.0, transition.isAnimated, !UIAccessibility.isReduceMotionEnabled else {
            return
        }
        let duration = transition.duration
        guard duration > 0.0 else {
            return
        }
        view.layer.removeAnimation(forKey: "aether.navigationButtonOverspringPulse")

        let baseTransform = view.layer.transform
        let peakTransform = CATransform3DScale(baseTransform, 1.0 + resolvedAmplitude, 1.0 + resolvedAmplitude, 1.0)
        let undershootScale = max(0.968, 1.0 - resolvedAmplitude * 0.30)
        let undershootTransform = CATransform3DScale(baseTransform, undershootScale, undershootScale, 1.0)
        let animation = CAKeyframeAnimation(keyPath: "transform")
        if amplitude >= 0.0 {
            animation.values = [baseTransform, peakTransform, undershootTransform, baseTransform]
        } else {
            animation.values = [baseTransform, undershootTransform, peakTransform, baseTransform]
        }
        animation.keyTimes = [0.0, 0.36, 0.74, 1.0]
        animation.duration = duration
        let timingFunction = amplitude >= 0.0
            ? CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.30, 1.0)
            : CAMediaTimingFunction(controlPoints: 0.70, 0.0, 0.84, 0.0)
        animation.timingFunctions = [timingFunction, timingFunction, timingFunction]
        animation.isRemovedOnCompletion = true
        animation.aetherPreferHighFrameRate()
        view.layer.add(animation, forKey: "aether.navigationButtonOverspringPulse")
    }

    @discardableResult
    internal func updateMeasuredTitleHeight(
        titleView: UIView?,
        size: CGSize,
        defaultHeight: CGFloat,
        leftInset: CGFloat,
        rightInset: CGFloat,
        requestLayoutIfNeeded: Bool
    ) -> Bool {
        let newTitleHeight = Self.measureTitleNaturalHeight(titleView: titleView, for: size, leftInset: leftInset, rightInset: rightInset)
        guard abs(measuredTitleHeight - newTitleHeight) > 0.5 else {
            return false
        }

        let oldEffective = max(defaultHeight, measuredTitleHeight)
        let newEffective = max(defaultHeight, newTitleHeight)
        measuredTitleHeight = newTitleHeight
        if requestLayoutIfNeeded && abs(oldEffective - newEffective) > 0.5 {
            DispatchQueue.main.async { [weak self] in
                self?.requestContainerLayout?(.animated(duration: 0.3, curve: .spring))
            }
        }
        return true
    }

    public func withButtonMorphTransition(_ transition: ContainedViewLayoutTransition, _ body: () -> Void) {
        buttonMorphTransitionOverride = transition
        defer { buttonMorphTransitionOverride = nil }
        body()
    }

    public func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        if presentationData.theme.style == .glass {
            transition.updateAlpha(view: backgroundView, alpha: 0.0)
            if let glassBackgroundView {
                transition.updateAlpha(view: glassBackgroundView, alpha: 0.0)
            }
            transition.updateAlpha(view: stripeView, alpha: 0.0)
            return
        }
        transition.updateAlpha(view: backgroundView, alpha: glassBackgroundView == nil ? alpha : 0.0)
        if let glassBackgroundView {
            transition.updateAlpha(view: glassBackgroundView, alpha: alpha)
        }
        transition.updateAlpha(view: stripeView, alpha: alpha)
    }

    public func updatePresentationData(_ presentationData: NavigationBarPresentationData, transition: ContainedViewLayoutTransition) {
        self.presentationData = presentationData
        let theme = presentationData.theme

        backgroundView.updateColor(color: theme.backgroundColor, enableBlur: theme.enableBackgroundBlur, transition: transition)
        stripeView.backgroundColor = theme.separatorColor
        titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        subtitleLabel.font = UIFont.systemFont(ofSize: 12.0, weight: .medium)
        clippingView.clipsToBounds = theme.style != .glass
        titleLabel.textColor = theme.primaryTextColor
        subtitleLabel.textColor = .secondaryLabel
        backButtonView.color = theme.buttonColor
        backButtonView.contentTintColor = theme.buttonColor
        backButtonView.isDark = theme.overallDarkAppearance
        backButtonView.usesGlassStyle = theme.style == .glass
        backButtonView.icon = NavigationBarTheme.generateBackArrowImage(color: theme.buttonColor)
        backArrowView.image = NavigationBarTheme.generateBackArrowImage(color: theme.buttonColor)

        badgeView.badgeColor = theme.badgeBackgroundColor
        badgeView.textColor = theme.badgeTextColor
        badgeView.strokeColor = theme.badgeStrokeColor

        if theme.style == .glass && glassBackgroundView == nil {
            setupGlassBackground(theme: theme)
        } else if theme.style == .glass {
            glassBackgroundView?.alpha = 0.0
            backgroundView.alpha = 0.0
            stripeView.alpha = 0.0
        } else if theme.style == .legacy {
            glassBackgroundView?.removeFromSuperview()
            glassBackgroundView = nil
            backgroundView.alpha = 1.0
            stripeView.alpha = 1.0
        }
        applyTransitionVisibilityState()
    }

    public func updateLayout(size: CGSize, defaultHeight: CGFloat, additionalTopHeight: CGFloat, additionalContentHeight: CGFloat, additionalBackgroundHeight: CGFloat, additionalCutout: CGSize?, leftInset: CGFloat, rightInset: CGFloat, appearsHidden: Bool, isLandscape: Bool, transition: ContainedViewLayoutTransition) {
        guard !layoutSuspended else { return }

        self.validLayout = (size, defaultHeight, leftInset, rightInset)

        // Re-measure titleContentView for the current width. If the new
        // natural height changes the EFFECTIVE title-row height
        // (`max(defaultHeight, titleHeight)`) — i.e. the title is tall
        // enough to grow the nav bar — schedule a follow-up layout pass so
        // the parent container picks up the new contentHeight. Skip the
        // re-layout when the title fits within `defaultHeight`: the cached
        // value still updates, but contentHeight wouldn't change, and
        // firing `.immediate` here would interrupt any in-flight push /
        // height-change animation for nothing.
        updateMeasuredTitleHeight(
            titleView: titleContentView ?? item?.titleView,
            size: size,
            defaultHeight: defaultHeight,
            leftInset: leftInset,
            rightInset: rightInset,
            requestLayoutIfNeeded: true
        )

        let stripeHeight: CGFloat = UIScreenPixel
        let contentHeight = self.contentHeight(defaultHeight: defaultHeight)

        // Background
        let bgHeight = size.height + additionalBackgroundHeight
        transition.updateFrame(view: backgroundView, frame: CGRect(origin: .zero, size: CGSize(width: size.width, height: bgHeight)))
        backgroundView.update(size: CGSize(width: size.width, height: bgHeight), transition: transition)

        // Glass — `isDark` must follow the system interface style, not the
        // static `theme.overallDarkAppearance` (which is often false even on
        // a dark-mode device because `.liquidGlass()` doesn't know the
        // runtime style). Without this, the glass renders with a light
        // lumaMin/lumaMax on dark-mode devices and the bar flashes white
        // during push/pop transitions when the glass re-composites.
        let isEffectivelyDark = presentationData.theme.overallDarkAppearance || traitCollection.userInterfaceStyle == .dark
        if backButtonView.isDark != isEffectivelyDark {
            backButtonView.isDark = isEffectivelyDark
        }
        if let glass = glassBackgroundView {
            transition.updateFrame(view: glass, frame: CGRect(origin: .zero, size: CGSize(width: size.width, height: bgHeight)))
            glass.update(
                size: CGSize(width: size.width, height: bgHeight),
                cornerRadius: 0.0,
                isDark: isEffectivelyDark,
                tintColor: .init(kind: presentationData.theme.glassStyle == .clear ? .clear : .panel),
                isInteractive: false,
                isVisible: true,
                transition: transition
            )
            if presentationData.theme.style == .glass {
                transition.updateAlpha(view: glass, alpha: 0.0)
            }
        }

        // Stripe
        // Stripe is carved out by `additionalCutout` to leave a gap for pinned
        // content (matches Dynamic-Island-style cutout handling).
        let stripeOriginX = additionalCutout?.width ?? 0.0
        transition.updateFrame(view: stripeView, frame: CGRect(x: stripeOriginX, y: size.height - stripeHeight, width: size.width - stripeOriginX, height: stripeHeight))
        if presentationData.theme.style == .glass {
            transition.updateAlpha(view: backgroundView, alpha: 0.0)
            transition.updateAlpha(view: stripeView, alpha: 0.0)
        }

        // Scroll-edge frost anchored to the BOTTOM of the nav bar. The fade
        // zone terminates exactly at the nav bar bottom (transparent there)
        // and ramps up to full frost near the top of the screen. No bleed
        // past the nav bar — the bottom boundary is a clean transparent edge.
        if let edgeEffect = edgeEffectView {
            if presentationData.theme.style != .glass {
                edgeEffect.isHidden = true
            } else if let edgeEffectColor = presentationData.theme.edgeEffectColor, edgeEffectColor.cgColor.alpha == 0.0 {
                edgeEffect.isHidden = true
            } else {
                edgeEffect.isHidden = false
                // 8pt bleed into the safe-area region on top, plus 8pt
                // past the navbar bottom so the fade spills softly into
                // the content area (instead of ending sharply at the
                // navbar edge). When `edgeEffectTopExtension` is set the
                // frost starts even higher — used e.g. by the modal
                // controller to have the frost cover its grabber strip.
                //
                // `bandShift` raises the band's TOP edge further past the
                // status bar AND grows the band's height by the same
                // amount — bottom edge stays put, frost extends upward.
                // Mirror of the tab bar's downward bleed; covers the
                // visible "просвет" between the nav bar's frost and the
                // status bar / dynamic island area.
                let topInset: CGFloat = 8.0
                // 2pt of bleed past the navbar bottom — that's where the
                // gradient mask reaches alpha=0. With `bottomBleed=0` the
                // alpha=0 row sat exactly at navbar.bottom, and during a
                // sheet resize the unfiltered backdrop sample at that row
                // showed presenter dim through it — read as a gap. With
                // 2pt bleed the alpha=0 row is just below navbar.bottom,
                // and the row at navbar.bottom itself is already at a
                // small but non-zero alpha (gradient is cosine), so the
                // backdrop blur covers content there. 2pt is small enough
                // that the bleed doesn't read as a visible stripe — the
                // 8pt original did.
                let bottomBleed: CGFloat = 4.0
                let bandShift: CGFloat = 12.0
                let topExtension = edgeEffectTopExtension
                let localEdgeEffectFrame = CGRect(
                    x: 0.0,
                    y: -(topInset + topExtension + bandShift),
                    width: size.width,
                    height: size.height + topInset + topExtension + bottomBleed + bandShift
                )
                // Snap the edge-effect frame and force `.immediate` on the
                // internal frame setters inside `edgeEffect.update(...)`.
                // When the nav-bar resizes via an `.animated` transition
                // (search pill jumping navbar↔bottom, modal detent change),
                // the bar's own frame snaps synchronously (see
                // `ViewController.containerLayoutUpdated`) but the edge
                // effect's frame would otherwise interpolate over 0.3s —
                // its bottom edge would lag behind the bar's bottom for
                // the duration of the animation, showing as a visible
                // gap (or "hard line" along the trailing edge of the
                // ramping fade) between the navbar and the content
                // beneath it. Snapping the edge-effect geometry restores
                // lockstep. Visual-only properties of the effect (color,
                // blur radius) still animate via the caller's transition
                // because we no longer pass the heavy frame-resize work
                // through it.
                let edgeEffectFrame: CGRect
                if let hostView = edgeEffectHostView, edgeEffect.superview === hostView {
                    let convertedOrigin = convert(localEdgeEffectFrame.origin, to: hostView)
                    edgeEffectFrame = CGRect(
                        x: 0.0,
                        y: convertedOrigin.y,
                        width: hostView.bounds.width,
                        height: localEdgeEffectFrame.height
                    )
                } else {
                    edgeEffectFrame = localEdgeEffectFrame
                }
                edgeEffect.frame = edgeEffectFrame
                let fadeZone: CGFloat = min(48.0, size.height * 0.4)
                // Force uniform blur path by passing the same radius for
                // both ends. The variable-blur path (which kicks in when
                // edge != fade) uses the gradient mask as a *per-pixel
                // radius scale* — at the bottom of the fade zone, where
                // alpha drops to near zero, backdrop blur radius drops to
                // ~0 and the backdrop sample passes through unfiltered.
                // Presenter dim shows through and reads as a gap between
                // the navbar and the content. The uniform path uses the
                // gradient mask as *opacity* on top of an already-blurred
                // backdrop — at the bottom row backdrop is still blurred,
                // only attenuated, so no presenter leaks through.
                let uniformRadius = presentationData.theme.edgeEffectBlurRadiusAtEdge
                edgeEffect.update(
                    content: presentationData.theme.edgeEffectColor ?? presentationData.theme.opaqueBackgroundColor,
                    blur: true,
                    alpha: presentationData.theme.edgeEffectAlpha,
                    rect: CGRect(origin: .zero, size: edgeEffectFrame.size),
                    edge: .top,
                    edgeSize: fadeZone,
                    blurRadiusAtEdge: uniformRadius,
                    blurRadiusAtFade: uniformRadius,
                    transition: .immediate
                )
            }
        }

        // Clipping
        transition.updateFrame(view: clippingView, frame: CGRect(origin: .zero, size: size))

        // Content area
        let statusBarHeight = size.height - contentHeight
        let buttonsAreaY = statusBarHeight + additionalTopHeight

        // Content view
        if let contentView = ownedContentView {
            switch contentView.mode {
            case .replacement:
                // Buttons hidden, content replaces title row
                let buttonsHeight = contentHeight - additionalTopHeight
                updateButtonsRowFrame(CGRect(x: 0, y: buttonsAreaY, width: size.width, height: buttonsHeight), transition: transition)
                layoutButtons(width: size.width, height: buttonsHeight, leftInset: leftInset, rightInset: rightInset, defaultHeight: defaultHeight, transition: transition)

                let contentFrame = CGRect(x: 0, y: buttonsAreaY, width: size.width, height: contentView.height)
                transition.updateFrame(view: contentView, frame: contentFrame)
                let _ = contentView.updateLayout(size: contentFrame.size, leftInset: leftInset, rightInset: rightInset, transition: transition)
                setButtonsRowAlpha(0.0)
            case .expansion:
                let buttonsHeight = max(defaultHeight, measuredTitleHeight)
                updateButtonsRowFrame(CGRect(x: 0, y: buttonsAreaY, width: size.width, height: buttonsHeight), transition: transition)
                layoutButtons(width: size.width, height: buttonsHeight, leftInset: leftInset, rightInset: rightInset, defaultHeight: defaultHeight, transition: transition)

                if isSearchModeActive {
                    // Search mode: content (search pill) at title position, no offset
                    let searchPillHeight = (contentView as? AetherStackedBarContent)?.views.first?.nominalHeight ?? contentView.height
                    let contentFrame = CGRect(x: 0, y: buttonsAreaY, width: size.width, height: searchPillHeight)
                    transition.updateFrame(view: contentView, frame: contentFrame)
                    let _ = contentView.updateLayout(size: contentFrame.size, leftInset: leftInset, rightInset: rightInset, transition: transition)
                    // Hide non-search children (filters) in stacked content
                    if let stacked = contentView as? AetherStackedBarContent {
                        for (i, v) in stacked.views.enumerated() {
                            v.alpha = i == 0 ? 1.0 : 0.0
                        }
                    }
                } else {
                    // Normal: content below title row
                    let contentFrame = CGRect(x: 0, y: buttonsAreaY + buttonsHeight, width: size.width, height: contentView.height)
                    transition.updateFrame(view: contentView, frame: contentFrame)
                    let _ = contentView.updateLayout(size: contentFrame.size, leftInset: leftInset, rightInset: rightInset, transition: transition)
                    // Restore all children alpha
                    if let stacked = contentView as? AetherStackedBarContent {
                        for v in stacked.views { v.alpha = 1.0 }
                    }
                    setButtonsRowAlpha(1.0)
                }
            }
            // Buttons always above content view (glass capsules over filter bar).
            clippingView.bringSubviewToFront(buttonsContainerView)
        } else {
            // No content view — buttons fill the entire content area
            let buttonsHeight: CGFloat
            if contentHeightOverride != nil {
                buttonsHeight = min(contentHeight - additionalTopHeight, max(defaultHeight, measuredTitleHeight))
            } else {
                buttonsHeight = contentHeight - additionalTopHeight
            }
            updateButtonsRowFrame(CGRect(x: 0, y: buttonsAreaY, width: size.width, height: buttonsHeight), transition: transition)
            layoutButtons(width: size.width, height: buttonsHeight, leftInset: leftInset, rightInset: rightInset, defaultHeight: defaultHeight, transition: transition)
            if !isSearchModeActive {
                setButtonsRowAlpha(1.0)
            }
        }

        bringButtonLayerToFrontIfNeeded()
        applyTransitionVisibilityState()
    }

    // MARK: - Search Mode

    public func setSearchMode(_ active: Bool, animated: Bool) {
        guard isSearchModeActive != active else { return }
        isSearchModeActive = active

        // Trigger a full layout cycle through the VC hierarchy.
        // This recalculates contentHeight (smaller in search mode),
        // which causes the VC to recompute additionalSafeAreaInsets,
        // which animates the collection content offset.
        let transition: ContainedViewLayoutTransition = animated
            ? .animated(duration: 0.3, curve: .easeInOut)
            : .immediate

        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                self.setButtonsRowAlpha(active ? 0.0 : 1.0)
                for group in self.glassButtonGroups(for: .left) {
                    group.alpha = active ? 0.0 : 1.0
                }
                for group in self.glassButtonGroups(for: .right) {
                    group.alpha = active ? 0.0 : 1.0
                }
            }
        } else {
            setButtonsRowAlpha(active ? 0.0 : 1.0)
            for group in glassButtonGroups(for: .left) {
                group.alpha = active ? 0.0 : 1.0
            }
            for group in glassButtonGroups(for: .right) {
                group.alpha = active ? 0.0 : 1.0
            }
        }

        requestContainerLayout?(transition)
    }

    // MARK: - Private

    private func layoutButtons(width: CGFloat, height: CGFloat, leftInset: CGFloat, rightInset: CGFloat, defaultHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let buttonHeight: CGFloat = min(defaultHeight, height)
        let sideInset: CGFloat = 8.0
        let usesGlassStyle = presentationData.theme.style == .glass
        let geometryTransition: ContainedViewLayoutTransition = buttonMorphTransitionOverride == nil ? transition : .immediate
        let buttonContainerTransition = buttonMorphTransitionOverride ?? geometryTransition
        let glassTransition = buttonMorphTransitionOverride ?? transition

        let titleLeftInset: CGFloat
        let titleRightInset: CGFloat
        if titleTransitionMode && !buttonsOnlyTransitionMode {
            backArrowView.isHidden = true
            backButtonView.isHidden = true
            leftButtonContainer.isHidden = true
            rightButtonContainer.isHidden = true
            badgeView.isHidden = true
            titleLeftInset = leftInset
            titleRightInset = rightInset
        } else if usesGlassStyle {
            // In glass mode the back button lives INSIDE the left
            // GlassControlGroup — no separate capsule. The group handles
            // morphing (fade old items out, new items in) automatically.
            backArrowView.isHidden = true
            backButtonView.isHidden = true
            let glassButtonHeight: CGFloat = 44.0
            // Inset from the bar edges to the button capsule. 20pt
            // (vs the original 16pt) gives a touch more breathing room
            // on the right side without throwing off symmetry — the
            // same value is applied to both sides below so left/right
            // capsules sit at identical distances from the bar edges.
            let glassSideInset: CGFloat = 16.0
            let glassY = floor((buttonHeight - glassButtonHeight) / 2.0) + 2.0

            let leftStart = leftInset + glassSideInset
            let leftAvailableWidth = max(1.0, width * 0.5 - leftStart)
            let rightAvailableWidth = max(1.0, width * 0.5 - rightInset - glassSideInset)

            if buttonMorphTransitionOverride == nil || leftButtonContainer.bounds.height.isZero {
                updateButtonChromeFrame(view: leftButtonContainer, frame: CGRect(x: leftStart, y: glassY, width: leftAvailableWidth, height: glassButtonHeight), transition: geometryTransition)
            }
            if buttonMorphTransitionOverride == nil || rightButtonContainer.bounds.height.isZero {
                updateButtonChromeFrame(view: rightButtonContainer, frame: CGRect(x: width * 0.5, y: glassY, width: rightAvailableWidth, height: glassButtonHeight), transition: geometryTransition)
            }

            let leftButtonsWidth = layoutBarButtonItems(in: leftButtonContainer, items: item?.leftBarButtonItems, alignment: .left, height: glassButtonHeight, transition: glassTransition)
            let rightButtonsWidth = layoutBarButtonItems(in: rightButtonContainer, items: item?.rightBarButtonItems, alignment: .right, height: glassButtonHeight, transition: glassTransition)

            if leftButtonsWidth > 0.0 {
                updateButtonChromeFrame(view: leftButtonContainer, frame: CGRect(x: leftStart, y: glassY, width: leftButtonsWidth, height: glassButtonHeight), transition: buttonContainerTransition)
            }
            if rightButtonsWidth > 0.0 {
                let rightFrame = CGRect(x: width - rightInset - glassSideInset - rightButtonsWidth, y: glassY, width: rightButtonsWidth, height: glassButtonHeight)
                let rightFrameTransition: ContainedViewLayoutTransition = glassTransition.isAnimated ? .immediate : buttonContainerTransition
                updateButtonChromeFrame(view: rightButtonContainer, frame: rightFrame, transition: rightFrameTransition)
            }

            titleLeftInset = leftButtonsWidth > 0.0 ? leftInset + glassSideInset + leftButtonsWidth + 10.0 : leftInset
            titleRightInset = rightButtonsWidth > 0.0 ? rightInset + glassSideInset + rightButtonsWidth + 10.0 : rightInset
        } else {
            let chromeGeometryTransition = geometryTransition
            // Back arrow
            let arrowSize = CGSize(width: 13.0, height: 22.0)
            let arrowFrame = CGRect(x: sideInset + leftInset, y: (buttonHeight - arrowSize.height) / 2.0, width: arrowSize.width, height: arrowSize.height)
            updateButtonChromeFrame(view: backArrowView, frame: arrowFrame, transition: chromeGeometryTransition)

            // Back button
            let backTextX = arrowFrame.maxX + 6.0
            let backSize = backButtonView.sizeThatFits(CGSize(width: width / 2.0, height: buttonHeight))
            let backFrame = CGRect(x: backTextX, y: (buttonHeight - backSize.height) / 2.0, width: backSize.width, height: backSize.height)
            updateButtonChromeFrame(view: backButtonView, frame: backFrame, transition: chromeGeometryTransition)

            titleLeftInset = max(backFrame.maxX + sideInset, sideInset + leftInset + 44.0)
            titleRightInset = sideInset + rightInset + 88.0

            // Left buttons
            let leftFrame = CGRect(x: sideInset + leftInset, y: 0, width: width / 3.0, height: buttonHeight)
            updateButtonChromeFrame(view: leftButtonContainer, frame: leftFrame, transition: chromeGeometryTransition)

            // Right buttons
            let rightWidth = width / 3.0
            let rightFrame = CGRect(x: width - rightWidth - sideInset - rightInset, y: 0, width: rightWidth, height: buttonHeight)
            updateButtonChromeFrame(view: rightButtonContainer, frame: rightFrame, transition: chromeGeometryTransition)

            layoutBarButtonItems(in: rightButtonContainer, items: item?.rightBarButtonItems, alignment: .right, height: buttonHeight)
            layoutBarButtonItems(in: leftButtonContainer, items: item?.leftBarButtonItems, alignment: .left, height: buttonHeight)
        }

        let balancedTitleInset = max(titleLeftInset, titleRightInset)
        let titleMaxWidth = max(0.0, width - balancedTitleInset * 2.0)
        if let titleContentView {
            // Try, in order: systemLayoutSizeFitting (Auto Layout-aware)
            // → sizeThatFits → current bounds → intrinsicContentSize.
            //
            // Auto Layout-aware fitting is first because it's the only
            // path that correctly resolves wrapper views without their
            // own `intrinsicContentSize` (HypeUI `.padding()` returns a
            // plain UIView; `GlassBackgroundView` is a custom UIView). For
            // those, both `sizeThatFits` (returns `bounds.size` = .zero
            // before first layout) and `intrinsicContentSize` (returns
            // `noIntrinsicMetric`) collapse to 0 and the title renders
            // invisible. `systemLayoutSizeFitting` propagates constraints
            // through the whole subtree and gives the real size.
            //
            // Height budget here is the FULL container height (`height`,
            // grown to fit a tall titleView via `measuredTitleHeight`),
            // not the short `buttonHeight` — otherwise tall titles get
            // clipped to ~44pt.
            let alFitting = titleContentView.systemLayoutSizeFitting(
                CGSize(width: titleMaxWidth, height: 0),
                withHorizontalFittingPriority: .fittingSizeLevel,
                verticalFittingPriority: .fittingSizeLevel
            )
            var resolvedWidth: CGFloat = alFitting.width
            var resolvedHeight: CGFloat = alFitting.height
            if resolvedWidth <= 0.0 || resolvedHeight <= 0.0 {
                let stf = titleContentView.sizeThatFits(CGSize(width: titleMaxWidth, height: .greatestFiniteMagnitude))
                if resolvedWidth <= 0.0 { resolvedWidth = stf.width }
                if resolvedHeight <= 0.0 { resolvedHeight = stf.height }
            }
            if resolvedWidth <= 0.0 { resolvedWidth = titleContentView.bounds.width }
            if resolvedHeight <= 0.0 { resolvedHeight = titleContentView.bounds.height }
            if resolvedWidth <= 0.0 || resolvedHeight <= 0.0 {
                let intrinsic = titleContentView.intrinsicContentSize
                if resolvedWidth <= 0.0 && intrinsic.width > 0.0 { resolvedWidth = intrinsic.width }
                if resolvedHeight <= 0.0 && intrinsic.height > 0.0 { resolvedHeight = intrinsic.height }
            }
            if resolvedHeight <= 0.0 { resolvedHeight = buttonHeight }
            let titleSize = CGSize(
                width: min(titleMaxWidth, max(0.0, resolvedWidth)),
                height: min(height, max(0.0, resolvedHeight))
            )
            // Center within the full container height. For a short title
            // this matches the previous (`buttonHeight`) centering exactly
            // because the container collapses to `defaultHeight`. For a
            // tall title, the container grew to titleHeight, so the title
            // sits at y≈0 and fills it — buttons stay at y=0 with their
            // own `buttonHeight`, never re-centering with the title.
            var titleFrame = CGRect(
                x: floor((width - titleSize.width) / 2.0),
                y: floor((height - titleSize.height) / 2.0) + (usesGlassStyle ? 1.0 : 0.0),
                width: titleSize.width,
                height: titleSize.height
            )
            titleFrame.origin.x = min(max(titleFrame.origin.x, titleLeftInset), max(titleLeftInset, width - titleRightInset - titleFrame.width))
            let titleViewID = ObjectIdentifier(titleContentView)
            if appearingTitleContentViewIDs.contains(titleViewID), let morphTransition = activeButtonMorphTransition() {
                appearingTitleContentViewIDs.remove(titleViewID)
                let targetTransform = titleContentView.transform
                updateButtonLayerHostedView(
                    view: titleContentView,
                    frame: titleFrame,
                    alpha: 0.0,
                    transform: targetTransform,
                    transition: .immediate
                )
                prepareAppearingVisualView(titleContentView, targetTransform: targetTransform)
                animateAppearingVisualView(titleContentView, transition: morphTransition, targetTransform: targetTransform)
            } else {
                updateButtonLayerHostedView(view: titleContentView, frame: titleFrame, transition: geometryTransition)
            }
        } else {
            let hasSubtitle = !(item?.subtitle?.isEmpty ?? true)
            if hasSubtitle {
                let titleMeasure = titleLabel.sizeThatFits(CGSize(width: titleMaxWidth, height: buttonHeight))
                let subtitleMeasure = subtitleLabel.sizeThatFits(CGSize(width: titleMaxWidth, height: buttonHeight))
                let stackSpacing: CGFloat = 1.0
                let titleHeight = min(22.0, max(0.0, titleMeasure.height))
                let subtitleHeight = min(16.0, max(0.0, subtitleMeasure.height))
                let stackHeight = min(buttonHeight, titleHeight + stackSpacing + subtitleHeight)
                let stackWidth = min(titleMaxWidth, max(titleMeasure.width, subtitleMeasure.width))
                var stackFrame = CGRect(
                    x: floor((width - stackWidth) / 2.0),
                    y: floor((buttonHeight - stackHeight) / 2.0) + (usesGlassStyle ? 1.0 : 0.0),
                    width: stackWidth,
                    height: stackHeight
                )
                stackFrame.origin.x = min(max(stackFrame.origin.x, titleLeftInset), max(titleLeftInset, width - titleRightInset - stackFrame.width))
                geometryTransition.updateFrame(
                    view: titleLabel,
                    frame: CGRect(
                        x: stackFrame.minX,
                        y: stackFrame.minY,
                        width: stackFrame.width,
                        height: titleHeight
                    )
                )
                geometryTransition.updateFrame(
                    view: subtitleLabel,
                    frame: CGRect(
                        x: stackFrame.minX,
                        y: stackFrame.minY + titleHeight + stackSpacing,
                        width: stackFrame.width,
                        height: subtitleHeight
                    )
                )
            } else {
                let measuredTitleSize = titleLabel.sizeThatFits(CGSize(width: titleMaxWidth, height: buttonHeight))
                let titleSize = CGSize(
                    width: min(titleMaxWidth, max(0.0, measuredTitleSize.width)),
                    height: min(buttonHeight, max(0.0, measuredTitleSize.height))
                )
                var titleFrame = CGRect(x: floor((width - titleSize.width) / 2.0), y: floor((buttonHeight - titleSize.height) / 2.0) + (usesGlassStyle ? 1.0 : 0.0), width: titleSize.width, height: titleSize.height)
                titleFrame.origin.x = min(max(titleFrame.origin.x, titleLeftInset), max(titleLeftInset, width - titleRightInset - titleFrame.width))
                geometryTransition.updateFrame(view: titleLabel, frame: titleFrame)
            }
        }
    }

    private enum ButtonAlignment {
        case left, right
    }

    private struct BuiltGlassButtonGroup {
        var items: [GlassControlGroup.Item] = []
        var sourceItems: [UIBarButtonItem] = []
    }

    private func measuredBarButtonCustomViewSize(
        _ view: UIView,
        availableWidth: CGFloat,
        height: CGFloat,
        minimumWidth: CGFloat = 0.0
    ) -> CGSize {
        let bounds = view.bounds.size
        var measured = CGSize.zero

        if bounds.width > 0.0 && bounds.height > 0.0 {
            measured = bounds
        } else {
            let fitting = view.sizeThatFits(CGSize(width: availableWidth, height: height))
            if fitting.width > 0.0 { measured.width = fitting.width }
            if fitting.height > 0.0 { measured.height = fitting.height }
            if measured.width <= 0.0 && bounds.width > 0.0 { measured.width = bounds.width }
            if measured.height <= 0.0 && bounds.height > 0.0 { measured.height = bounds.height }
        }

        if measured.width <= 0.0 || measured.height <= 0.0 {
            let intrinsic = view.intrinsicContentSize
            if measured.width <= 0.0 && intrinsic.width > 0.0 { measured.width = intrinsic.width }
            if measured.height <= 0.0 && intrinsic.height > 0.0 { measured.height = intrinsic.height }
        }

        if measured.width <= 0.0 { measured.width = height }
        if measured.height <= 0.0 { measured.height = height }
        measured.width = max(minimumWidth, measured.width)
        measured.height = min(height, measured.height)
        return measured
    }

    private func glassButtonGroups(for alignment: ButtonAlignment) -> [GlassControlGroup] {
        switch alignment {
        case .left:
            return [leftButtonsGroup].compactMap { $0 } + leftAdditionalButtonsGroups
        case .right:
            return [rightButtonsGroup].compactMap { $0 } + rightAdditionalButtonsGroups
        }
    }

    private func storeGlassButtonGroups(_ groups: [GlassControlGroup], alignment: ButtonAlignment) {
        switch alignment {
        case .left:
            leftButtonsGroup = groups.first
            leftAdditionalButtonsGroups = groups.count > 1 ? Array(groups.dropFirst()) : []
        case .right:
            rightButtonsGroup = groups.first
            rightAdditionalButtonsGroups = groups.count > 1 ? Array(groups.dropFirst()) : []
        }
    }

    private func buttonGlassContainer(for container: UIView) -> GlassBackgroundContainerView? {
        if container === leftButtonContainer {
            return leftButtonGlassContainer
        }
        if container === rightButtonContainer {
            return rightButtonGlassContainer
        }
        return nil
    }

    private func buttonGroupHostView(for container: UIView) -> UIView {
        return buttonGlassContainer(for: container)?.contentView ?? container
    }

    private func isButtonGlassContainer(_ view: UIView, for container: UIView) -> Bool {
        guard let glassContainer = buttonGlassContainer(for: container) else {
            return false
        }
        return view === glassContainer
    }

    private func isGlassButtonGroup(_ group: GlassControlGroup, hostedIn container: UIView) -> Bool {
        let hostView = buttonGroupHostView(for: container)
        return group.superview === hostView || group.superview === container
    }

    private func updateButtonGlassContainer(
        in container: UIView,
        size: CGSize,
        transition: ContainedViewLayoutTransition
    ) {
        guard let glassContainer = buttonGlassContainer(for: container) else {
            return
        }
        let resolvedSize = CGSize(width: max(0.0, size.width), height: max(0.0, size.height))
        transition.updateFrame(view: glassContainer, frame: CGRect(origin: .zero, size: resolvedSize))
        glassContainer.update(
            size: resolvedSize,
            isDark: presentationData.theme.overallDarkAppearance || traitCollection.userInterfaceStyle == .dark,
            transition: transition
        )
    }

    private func removeGlassButtonGroups(alignment: ButtonAlignment) {
        for group in glassButtonGroups(for: alignment) {
            group.removeFromSuperview()
        }
        storeGlassButtonGroups([], alignment: alignment)
    }

    private func barButtonID(for item: UIBarButtonItem, alignment: ButtonAlignment) -> BarButtonID {
        let side: String
        switch alignment {
        case .left: side = "left"
        case .right: side = "right"
        }
        return BarButtonID("\(side).item.\(ObjectIdentifier(item))")
    }

    private func automaticBackButtonID(alignment: ButtonAlignment) -> BarButtonID {
        let side: String
        switch alignment {
        case .left: side = "left"
        case .right: side = "right"
        }
        return BarButtonID("\(side).nav.back")
    }

    @discardableResult
    private func layoutBarButtonItems(in container: UIView, items: [UIBarButtonItem]?, alignment: ButtonAlignment, height: CGFloat, transition glassTransition: ContainedViewLayoutTransition = .immediate) -> CGFloat {
        let theme = presentationData.theme
        let itemGeometryTransition: ContainedViewLayoutTransition = buttonMorphTransitionOverride == nil ? glassTransition : .immediate

        if theme.style == .glass {
            clearLegacyButtonViews(alignment: alignment)
            // When every bar-button item has its own customView and no
            // auto back-button is needed, skip the shared GlassControlGroup
            // capsule entirely. Reason: wrapping caller-provided views
            // (especially glass-bearing ones like GlassButton) inside the
            // group's glass capsule creates a double-glass stack — the
            // inner iconView's iOS 26 monochromatic treatment then inverts
            // against the outer capsule and renders with the wrong tint,
            // and custom layout views lose their size when the group
            // constrains them to its own flow. Laying out customViews
            // directly in the container lets them render exactly as-is.
            let rawItems = items ?? []
            let needsBackButton = alignment == .left && previousItem != nil && enableAutomaticBackButton
            let allCustomView = !rawItems.isEmpty && rawItems.allSatisfy {
                $0.customView != nil && !$0.aetherHostsCustomViewInGlassControlGroup
            }

            if allCustomView && !needsBackButton {
                removeGlassButtonGroups(alignment: alignment)

                let expected = rawItems.compactMap { $0.customView }
                for sub in container.subviews where !isButtonGlassContainer(sub, for: container) && !expected.contains(where: { $0 === sub }) {
                    if glassTransition.isAnimated {
                        glassTransition.updateAlpha(view: sub, alpha: 0.0) { [weak sub] _ in
                            sub?.removeFromSuperview()
                        }
                    } else {
                        sub.removeFromSuperview()
                    }
                }

                let spacing: CGFloat = 6.0
                var offsetX: CGFloat = 0.0
                for (idx, view) in expected.enumerated() {
                    let item = rawItems[idx]
                    let isNewView = view.superview !== container
                    if view.superview !== container {
                        if glassTransition.isAnimated {
                            view.alpha = 0.0
                        }
                        container.addSubview(view)
                    }
                    let measured = measuredBarButtonCustomViewSize(
                        view,
                        availableWidth: .greatestFiniteMagnitude,
                        height: height
                    )

                    let y = floor((height - measured.height) / 2.0)
                    let frame = CGRect(x: offsetX, y: y, width: measured.width, height: measured.height)
                    itemGeometryTransition.updateFrame(view: view, frame: frame)
                    if isNewView {
                        glassTransition.updateAlpha(view: view, alpha: 1.0)
                    } else if view.alpha < 1.0 {
                        view.alpha = 1.0
                    }
                    if #available(iOS 14.0, *),
                       item.contextMenuItemsProvider != nil,
                       let control = view as? UIControl {
                        wireBarButtonMenuTrigger(button: control, item: item, alignment: alignment)
                    }
                    offsetX += measured.width
                    if idx < expected.count - 1 { offsetX += spacing }
                }
                updateButtonGlassContainer(in: container, size: CGSize(width: offsetX, height: height), transition: itemGeometryTransition)
                return offsetX
            }

            var builtGroups: [BuiltGlassButtonGroup] = []
            var currentGroup = BuiltGlassButtonGroup()

            func flushCurrentGroup() {
                guard !currentGroup.items.isEmpty else {
                    return
                }
                builtGroups.append(currentGroup)
                currentGroup = BuiltGlassButtonGroup()
            }

            // Left group: prepend back button (icon-only circle) if applicable.
            if alignment == .left, let _ = self.previousItem, enableAutomaticBackButton {
                let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
                let backArrow = UIImage(systemName: "chevron.left", withConfiguration: config)!
                currentGroup.items.append(GlassControlGroup.Item(
                    id: automaticBackButtonID(alignment: alignment),
                    content: .icon(backArrow),
                    action: { [weak self] in self?.backPressed() }
                ))
            }

            // Regular bar button items.
            if let items, !items.isEmpty {
                for item in items {
                    let content: GlassControlGroup.Item.Content
                    let insets: UIEdgeInsets
                    if let customView = item.customView {
                        content = .customView(customView)
                        insets = .zero
                    } else if let image = item.image {
                        content = .icon(image)
                        insets = .zero
                    } else if let title = item.title {
                        content = .text(title)
                        insets = UIEdgeInsets(top: 0.0, left: 10.0, bottom: 0.0, right: 10.0)
                    } else {
                        content = .text("")
                        insets = UIEdgeInsets(top: 0.0, left: 10.0, bottom: 0.0, right: 10.0)
                    }

                    let primaryAction: (() -> Void)?
                    if let selector = item.action, let target = item.target as AnyObject? {
                        primaryAction = { [weak target] in
                            UIApplication.shared.sendAction(selector, to: target, from: item, for: nil)
                        }
                    } else if item.aetherHostsCustomViewInGlassControlGroup, item.customView?.isUserInteractionEnabled == true {
                        primaryAction = {}
                    } else {
                        primaryAction = nil
                    }

                    // If the bar item carries a AetherUI menu provider
                    // (set by `UIBarButtonItem(title:image:primaryAction:contextMenuItemsProvider:)`
                    // or directly via `contextMenuItemsProvider`),
                    // tapping pops the AetherUI context menu anchored
                    // to the capsule cell.
                    //
                    //   * iOS 14+ — pass a NO-OP action here (so the
                    //     `GlassControlGroup` keeps `isUserInteractionEnabled = true`
                    //     and the button rendered at full alpha; passing
                    //     `nil` greys the cell out and silences taps).
                    //     The real menu trigger is wired further down via
                    //     `wireBarButtonMenuTrigger` on `.touchDown`,
                    //     BEFORE the button's highlight + onTap chain.
                    //   * iOS 13 — `UIAction` is unavailable, so route
                    //     through the action callback (touchUpInside).
                    let action: (() -> Void)?
                    if let menuProvider = item.contextMenuItemsProvider {
                        if #available(iOS 14.0, *) {
                            action = { /* no-op — menu fires on .touchDown */ }
                        } else {
                            action = { [weak self, weak item] in
                                guard let self, let item else { return }
                                self.presentBarButtonContextMenu(for: item, alignment: alignment, provider: menuProvider)
                            }
                        }
                    } else {
                        action = primaryAction
                    }

                    let groupItem = GlassControlGroup.Item(id: barButtonID(for: item, alignment: alignment), content: content, contentInsets: insets, action: action)
                    if item.separatesSharedBackground {
                        flushCurrentGroup()
                        builtGroups.append(BuiltGlassButtonGroup(items: [groupItem], sourceItems: [item]))
                    } else {
                        currentGroup.items.append(groupItem)
                        currentGroup.sourceItems.append(item)
                    }
                }
            }
            flushCurrentGroup()

            guard !builtGroups.isEmpty else {
                var existingGroups = glassButtonGroups(for: alignment)
                for (index, group) in existingGroups.enumerated() {
                    group.animatesInsertedItemsAlpha = glassTransition.isAnimated
                    group.transitionContentAlignment = alignment == .right ? .trailing : .leading
                    _ = group.update(
                        items: [],
                        background: .panel,
                        preferClearGlass: theme.glassStyle == .clear,
                        foregroundColor: theme.buttonColor,
                        isDark: theme.overallDarkAppearance || traitCollection.userInterfaceStyle == .dark,
                        availableHeight: height,
                        minWidth: height,
                        transition: glassTransition
                    )
                    if index > 0 {
                        if glassTransition.isAnimated {
                            glassTransition.updateAlpha(view: group, alpha: 0.0) { [weak group] _ in
                                group?.removeFromSuperview()
                                group?.alpha = 1.0
                            }
                        } else {
                            group.removeFromSuperview()
                            group.alpha = 1.0
                        }
                    }
                }
                if existingGroups.count > 1 {
                    existingGroups = Array(existingGroups.prefix(1))
                }
                storeGlassButtonGroups(existingGroups, alignment: alignment)
                if !glassTransition.isAnimated {
                    updateButtonGlassContainer(in: container, size: CGSize(width: 0.0, height: height), transition: .immediate)
                }
                return 0.0
            }

            var groups = glassButtonGroups(for: alignment)
            while groups.count < builtGroups.count {
                groups.append(GlassControlGroup())
            }
            if groups.count > builtGroups.count {
                for staleGroup in groups.dropFirst(builtGroups.count) {
                    staleGroup.transitionContentAlignment = alignment == .right ? .trailing : .leading
                    _ = staleGroup.update(
                        items: [],
                        background: .panel,
                        preferClearGlass: theme.glassStyle == .clear,
                        foregroundColor: theme.buttonColor,
                        isDark: theme.overallDarkAppearance || traitCollection.userInterfaceStyle == .dark,
                        availableHeight: height,
                        minWidth: height,
                        transition: glassTransition
                    )
                    if glassTransition.isAnimated {
                        glassTransition.updateAlpha(view: staleGroup, alpha: 0.0) { [weak staleGroup] _ in
                            staleGroup?.removeFromSuperview()
                            staleGroup?.alpha = 1.0
                        }
                    } else {
                        staleGroup.removeFromSuperview()
                        staleGroup.alpha = 1.0
                    }
                }
                groups = Array(groups.prefix(builtGroups.count))
            }

            let groupHostView = buttonGroupHostView(for: container)
            for group in groups where group.superview !== groupHostView {
                groupHostView.addSubview(group)
            }
            storeGlassButtonGroups(groups, alignment: alignment)

            // Clean up stale non-group subviews from legacy/custom paths.
            let groupSet = Set(groups.map { ObjectIdentifier($0) })
            for sub in container.subviews where !isButtonGlassContainer(sub, for: container) {
                sub.removeFromSuperview()
            }
            for sub in groupHostView.subviews where !groupSet.contains(ObjectIdentifier(sub)) {
                sub.removeFromSuperview()
            }

            let spacing: CGFloat = 8.0
            var groupSizes: [CGSize] = []
            groupSizes.reserveCapacity(builtGroups.count)
            var totalWidth: CGFloat = 0.0
            for (index, builtGroup) in builtGroups.enumerated() {
                let group = groups[index]
                group.animatesInsertedItemsAlpha = glassTransition.isAnimated
                group.transitionContentAlignment = alignment == .right ? .trailing : .leading
                let size = group.update(
                    items: builtGroup.items,
                    background: .panel,
                    preferClearGlass: theme.glassStyle == .clear,
                    foregroundColor: theme.buttonColor,
                    isDark: theme.overallDarkAppearance || traitCollection.userInterfaceStyle == .dark,
                    availableHeight: height,
                    minWidth: height,
                    transition: glassTransition
                )
                groupSizes.append(size)
                totalWidth += size.width
                if index < builtGroups.count - 1 {
                    totalWidth += spacing
                }
            }

            var offsetX: CGFloat = 0.0
            for (index, group) in groups.enumerated() {
                let size = groupSizes[index]
                itemGeometryTransition.updateFrame(view: group, frame: CGRect(x: offsetX, y: 0.0, width: size.width, height: size.height))
                offsetX += size.width
                if index < groups.count - 1 {
                    offsetX += spacing
                }
            }
            updateButtonGlassContainer(in: container, size: CGSize(width: totalWidth, height: height), transition: itemGeometryTransition)

            // After `group.update` rebuilds the cell buttons, wire the
            // menu trigger DIRECTLY onto each button that carries a
            // provider. We use `.touchDown` on iOS 14+ so the menu fires
            // the moment the finger lands — same response curve as
            // `UIButton.menu` with `showsMenuAsPrimaryAction = true` —
            // and the menu source is still in a clean (non-press) state.
            // iOS 13 falls back to the old action-callback path
            // already wired through GlassControlGroup.
            if #available(iOS 14.0, *) {
                for (groupIndex, builtGroup) in builtGroups.enumerated() {
                    let group = groups[groupIndex]
                    for item in builtGroup.sourceItems {
                        guard item.contextMenuItemsProvider != nil,
                              let buttonView = group.itemButton(id: barButtonID(for: item, alignment: alignment)) as? UIControl
                        else { continue }
                        wireBarButtonMenuTrigger(button: buttonView, item: item, alignment: alignment)
                    }
                }
            }
            return totalWidth
        }

        // Legacy (non-glass) layout — unchanged from prior behaviour.
        if container === leftButtonContainer {
            removeGlassButtonGroups(alignment: .left)
        }
        if container === rightButtonContainer {
            removeGlassButtonGroups(alignment: .right)
        }

        let rawItems = items ?? []
        let expectedIDs = Set(rawItems.map { barButtonID(for: $0, alignment: alignment) })
        let morphTransition = activeButtonMorphTransition()
        for (id, view) in legacyButtonViews(for: alignment) where !expectedIDs.contains(id) {
            setLegacyButtonView(nil, for: id, alignment: alignment)
            animateDisappearingVisualView(view, transition: morphTransition)
        }

        guard !rawItems.isEmpty else {
            clearLegacyButtonViews(alignment: alignment)
            for subview in container.subviews where !isButtonGlassContainer(subview, for: container) {
                animateDisappearingVisualView(subview, transition: morphTransition)
            }
            return 0.0
        }

        var offsetX: CGFloat = 0
        var expectedViews: [UIView] = []

        for item in rawItems {
            let id = barButtonID(for: item, alignment: alignment)
            let view: UIView
            let size: CGSize
            let isNewView: Bool
            let targetTransform: CGAffineTransform

            if let customView = item.customView {
                if let generatedView = legacyButtonView(for: id, alignment: alignment), generatedView !== customView {
                    setLegacyButtonView(nil, for: id, alignment: alignment)
                    animateDisappearingVisualView(generatedView, transition: morphTransition)
                }
                view = customView
                isNewView = customView.superview !== container
                targetTransform = customView.transform
                size = measuredBarButtonCustomViewSize(
                    customView,
                    availableWidth: container.bounds.width,
                    height: height,
                    minimumWidth: 30.0
                )
            } else if theme.style == .glass {
                let button = GlassBarButtonView(icon: item.image, title: item.title, state: .glass)
                button.contentTintColor = theme.buttonColor
                if let action = item.action, let target = item.target {
                    button.action = { _ in
                        UIApplication.shared.sendAction(action, to: target, from: item, for: nil)
                    }
                }
                view = button
                isNewView = true
                targetTransform = .identity
                size = button.intrinsicContentSize
            } else {
                let button: UIButton
                if let existingButton = legacyButtonView(for: id, alignment: alignment) as? UIButton {
                    button = existingButton
                    isNewView = button.superview !== container
                } else {
                    button = UIButton(type: .system)
                    setLegacyButtonView(button, for: id, alignment: alignment)
                    isNewView = true
                }
                button.tintColor = theme.buttonColor

                button.setImage(item.image, for: .normal)
                button.setTitle(item.title, for: .normal)
                if item.title != nil {
                    button.titleLabel?.font = UIFont.systemFont(ofSize: 17.0)
                }

                button.removeTarget(nil, action: nil, for: .touchUpInside)
                if item.contextMenuItemsProvider == nil, let action = item.action, let target = item.target {
                    button.addTarget(target, action: action, for: .touchUpInside)
                }

                button.sizeToFit()
                view = button
                targetTransform = .identity
                size = CGSize(width: max(button.bounds.width, 30.0), height: button.bounds.height)
            }

            let x: CGFloat
            switch alignment {
            case .left:
                x = offsetX
            case .right:
                x = container.bounds.width - offsetX - size.width
            }

            let frame = CGRect(x: x, y: floor((height - size.height) / 2.0), width: size.width, height: size.height)
            performMorphGeometryWithoutAnimation {
                view.frame = frame
            }
            if view.superview !== container {
                if isNewView, morphTransition != nil {
                    prepareAppearingVisualView(view, targetTransform: targetTransform)
                }
                container.addSubview(view)
                if isNewView, let morphTransition {
                    animateAppearingVisualView(view, transition: morphTransition, targetTransform: targetTransform)
                }
            } else if disappearingVisualViewIDs.contains(ObjectIdentifier(view)) {
                let viewID = ObjectIdentifier(view)
                disappearingVisualViewIDs.remove(viewID)
                appearingVisualViewIDs.remove(viewID)
                let restoredUserInteraction = disappearingVisualInteractionByID.removeValue(forKey: viewID) ?? view.isUserInteractionEnabled
                view.layer.removeAllAnimations()
                view.alpha = 1.0
                view.transform = targetTransform
                view.isUserInteractionEnabled = restoredUserInteraction
                ContainedViewLayoutTransition.immediate.setBlur(layer: view.layer, radius: 0.0)
            } else if appearingVisualViewIDs.contains(ObjectIdentifier(view)) {
                // Keep the in-flight blur/alpha/scale animation intact.
            } else {
                view.alpha = 1.0
                view.transform = targetTransform
                ContainedViewLayoutTransition.immediate.setBlur(layer: view.layer, radius: 0.0)
            }
            expectedViews.append(view)
            if #available(iOS 14.0, *),
               item.contextMenuItemsProvider != nil,
               let control = view as? UIControl {
                wireBarButtonMenuTrigger(button: control, item: item, alignment: alignment)
            }
            offsetX += size.width + 8.0
        }
        let expectedViewIDs = Set(expectedViews.map { ObjectIdentifier($0) })
        for subview in container.subviews where !isButtonGlassContainer(subview, for: container) && !expectedViewIDs.contains(ObjectIdentifier(subview)) {
            animateDisappearingVisualView(subview, transition: morphTransition)
        }
        return max(0.0, offsetX - 8.0)
    }

    private func updateItemContent() {
        titleLabel.text = item?.title
        subtitleLabel.text = item?.subtitle
        let itemTitleView = hostsNavigationItemTitleView ? item?.titleView : nil
        if let existingTitleContentView = titleContentView, existingTitleContentView !== itemTitleView {
            let morphTransition = activeButtonMorphTransition()
            buttonLayer.removeButtonPlacement(id: ButtonChromePlacementID.titleContentView, detachView: false)
            let isHostedByThisBar = existingTitleContentView.isDescendant(of: buttonLayer)
                || existingTitleContentView.isDescendant(of: buttonsContainerView)
                || existingTitleContentView.isDescendant(of: self)
            if morphTransition?.isAnimated == true && isHostedByThisBar {
                animateOutgoingTitleContentView(existingTitleContentView, transition: morphTransition)
            } else if isHostedByThisBar {
                existingTitleContentView.removeFromSuperview()
            }
            titleContentView = nil
            // Drop any cached height from the previous titleView so the next
            // layout pass re-measures (or collapses back to defaultHeight).
            measuredTitleHeight = 0
        }
        if let titleView = itemTitleView, titleView !== titleContentView {
            buttonLayer.removeButtonPlacement(id: ButtonChromePlacementID.titleContentView, detachView: false)
            titleContentView?.removeFromSuperview()
            titleContentView = titleView
            if activeButtonMorphTransition()?.isAnimated == true {
                appearingTitleContentViewIDs.insert(ObjectIdentifier(titleView))
            }
            installTitleContentViewForCurrentHostingMode(preservePresentationLayer: false)
            measuredTitleHeight = 0
        }
        titleLabel.isHidden = titleContentView != nil
        subtitleLabel.isHidden = titleContentView != nil || (item?.subtitle?.isEmpty ?? true)
        updateBackButton()
        // Do NOT schedule any layout here. The caller — syncNavigationItem
        // in TabBarController, wireControllers in NavigationController, etc.
        // — is responsible for driving the layout pass with the correct
        // transition. Requesting an animated spring here meant every
        // `item = ...` set kicked off a 0.3s layout, which showed up as
        // an unwanted animation on tab switches (syncNavigationItem passes
        // animated: false, but this implicit request was overriding it).
    }

    /// Probe the current `titleContentView`'s natural height for the given
    /// container width. Used by `updateLayout` to decide whether the nav
    /// bar should grow to fit a tall custom titleView. Width budget mirrors
    /// the conservative side reserve used by `layoutButtons` (back/right
    /// buttons + insets) so the same height we measure here is what the
    /// title will actually render at later in the pass.
    ///
    /// Auto Layout (`systemLayoutSizeFitting`) is the primary path because
    /// it correctly resolves wrapper views (HypeUI's `.padding()`, etc.)
    /// that have no `intrinsicContentSize` of their own — `sizeThatFits`
    /// on those returns bounds.size = (0, 0) before first layout, and the
    /// intrinsic chain breaks when any child reports `noIntrinsicMetric`.
    internal static func measureTitleNaturalHeight(titleView: UIView?, for size: CGSize, leftInset: CGFloat, rightInset: CGFloat) -> CGFloat {
        guard let titleContentView = titleView else { return 0 }
        let sideButtonsBudget: CGFloat = 100
        let titleMaxWidth = max(0, size.width - leftInset - rightInset - sideButtonsBudget * 2)
        let alFitting = titleContentView.systemLayoutSizeFitting(
            CGSize(width: titleMaxWidth, height: 0),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
        if alFitting.height > 0 { return alFitting.height }
        let stf = titleContentView.sizeThatFits(CGSize(width: titleMaxWidth, height: .greatestFiniteMagnitude))
        if stf.height > 0 { return stf.height }
        return max(0, titleContentView.intrinsicContentSize.height)
    }

    /// Call after mutating the wrapped titleView in a way that changes its
    /// natural height (text replaced, child added/removed). Drops the cached
    /// measurement and asks the parent container to re-run layout — the
    /// nav bar will then re-measure and grow/shrink to fit.
    public func invalidateTitleViewLayout(transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .spring)) {
        measuredTitleHeight = 0
        requestContainerLayout?(transition)
    }

    private func updateBackButton() {
        let hasBack: Bool
        let backText: String

        if let previousItem = self.previousItem {
            switch previousItem {
            case let .item(navItem):
                hasBack = true
                backText = navItem.title ?? presentationData.strings.back
            case .close:
                hasBack = true
                backText = presentationData.strings.close
            }
        } else {
            hasBack = false
            backText = ""
        }

        backButtonView.isHidden = !hasBack || !enableAutomaticBackButton
        backArrowView.isHidden = backButtonView.isHidden || presentationData.theme.style == .glass
        backButtonView.text = backText
        applyTransitionVisibilityState()
    }

    @objc private func backButtonPressed() {
        backPressed()
    }

    private func setupGlassBackground(theme: NavigationBarTheme) {
        let glass = GlassBackgroundView(style: theme.glassStyle == .clear ? .clear : .regular)
        insertSubview(glass, aboveSubview: backgroundView)
        self.glassBackgroundView = glass
        backgroundView.alpha = 0.0
        glass.alpha = 0.0
        stripeView.alpha = 0.0

        // Scroll-edge fade (`NavigationBarImpl` creates this unconditionally
        // in glass mode — scrolling content dissolves as it meets the nav bar).
        let edgeEffect = EdgeEffectView()
        edgeEffect.isUserInteractionEnabled = false
        self.edgeEffectView = edgeEffect
        rehostEdgeEffectView()
        applyTransitionVisibilityState()
    }

    private func rehostEdgeEffectView() {
        guard let edgeEffectView else {
            return
        }
        edgeEffectView.removeFromSuperview()
        if let edgeEffectHostView {
            edgeEffectHostView.addSubview(edgeEffectView)
        } else {
            insertSubview(edgeEffectView, at: 0)
        }
    }

    deinit {
        edgeEffectView?.removeFromSuperview()
        buttonLayer.removeFromSuperview()
    }

    private func applyTransitionVisibilityState() {
        if titleTransitionMode {
            backgroundView.isHidden = true
            stripeView.isHidden = true
            glassBackgroundView?.isHidden = true
            edgeEffectView?.isHidden = presentationData.theme.style != .glass || (presentationData.theme.edgeEffectColor?.cgColor.alpha ?? 1.0).isZero
            leftButtonContainer.isHidden = true
            rightButtonContainer.isHidden = true
            badgeView.isHidden = true
        } else if buttonsOnlyTransitionMode {
            backgroundView.isHidden = true
            stripeView.isHidden = true
            glassBackgroundView?.isHidden = true
            edgeEffectView?.isHidden = true
            leftButtonContainer.isHidden = false
            rightButtonContainer.isHidden = false
            badgeView.isHidden = true
        } else {
            let chromeOnlyTransition = titleContentHiddenForTransition
            backgroundView.isHidden = chromeOnlyTransition
            stripeView.isHidden = chromeOnlyTransition
            glassBackgroundView?.isHidden = chromeOnlyTransition
            edgeEffectView?.isHidden = chromeOnlyTransition || presentationData.theme.style != .glass || (presentationData.theme.edgeEffectColor?.cgColor.alpha ?? 1.0).isZero
            leftButtonContainer.isHidden = buttonContentHiddenForTransition
            rightButtonContainer.isHidden = buttonContentHiddenForTransition
            badgeView.isHidden = buttonContentHiddenForTransition || badgeView.text.isEmpty
        }
        if titleTransitionMode || buttonContentHiddenForTransition {
            backButtonView.isHidden = true
            backArrowView.isHidden = true
        } else if !buttonsOnlyTransitionMode {
            let hasBack = previousItem != nil && enableAutomaticBackButton
            backButtonView.isHidden = !hasBack
            backArrowView.isHidden = !hasBack || presentationData.theme.style == .glass
        }

        let titleAlpha: CGFloat = titleContentHiddenForTransition || buttonsOnlyTransitionMode ? 0.0 : 1.0
        let customTitleAlpha: CGFloat = titleTransitionMode || buttonContentHiddenForTransition ? 0.0 : 1.0
        let contentAlpha: CGFloat = titleContentHiddenForTransition || buttonsOnlyTransitionMode ? 0.0 : 1.0
        titleLabel.alpha = titleAlpha
        if let titleContentView {
            updateButtonLayerHostedView(view: titleContentView, alpha: customTitleAlpha, transition: .immediate)
        }
        ownedContentView?.alpha = contentAlpha
    }

    /// Reference to the menu currently anchored to one of our bar
    /// buttons. Tracked so `traitCollectionDidChange` can dismiss it
    /// before the navbar tears down + rebuilds its `GlassControlGroup`
    /// cell buttons (which would otherwise leave the menu pointing at
    /// a detached source view and corrupt the navbar's own re-layout).
    private weak var presentedBarButtonMenu: ContextMenuController?

    private func dismissPresentedBarButtonContextMenu() {
        guard let menu = presentedBarButtonMenu else {
            return
        }
        presentedBarButtonMenu = nil
        menu.dismiss(animated: false)
    }

    /// Wires the menu trigger directly onto the `GlassControlGroup`
    /// cell button via `UIAction` on `.touchDown`. This intentionally
    /// bypasses the group's own `onTap` action — the menu fires the
    /// moment the user's finger lands instead of after touch-up,
    /// matching `UIButton.menu`-with-`showsMenuAsPrimaryAction`'s
    /// timing and avoiding the brief icon shift the action-callback path
    /// produced when the cell was already mid-press.
    @available(iOS 14.0, *)
    private func wireBarButtonMenuTrigger(
        button: UIControl,
        item: UIBarButtonItem,
        alignment: ButtonAlignment
    ) {
        let identifier = UIAction.Identifier("AetherUI.NavigationBar.BarButtonContextMenu")
        button.removeAction(identifiedBy: identifier, for: .touchDown)
        let action = UIAction(identifier: identifier) { [weak self, weak item, weak button] _ in
            guard let self,
                  let item,
                  let sourceView = button,
                  let provider = item.contextMenuItemsProvider
            else { return }
            let sourceID = self.barButtonID(for: item, alignment: alignment)
            let visualSourceView = self.glassButtonGroups(for: alignment).compactMap { group -> UIView? in
                guard group.itemButton(id: sourceID) === sourceView else {
                    return nil
                }
                return group.itemVisualSourceView(id: sourceID)
            }.first ?? sourceView
            self.presentBarButtonContextMenu(
                sourceView: sourceView,
                visualSourceView: visualSourceView,
                provider: provider
            )
        }
        button.addAction(action, for: .touchDown)
    }

    /// Show a AetherUI context menu anchored to the bar item's glass
    /// capsule cell. Routes through `GlassControlGroup.itemButton(id:)`
    /// to find the visible source view — the cell rounds with the
    /// capsule's height/2, so we mirror that for the menu's morph-out
    /// corner radius.
    private func presentBarButtonContextMenu(
        for item: UIBarButtonItem,
        alignment: ButtonAlignment,
        provider: () -> [ContextMenuItem]
    ) {
        // Don't open a duplicate menu if one is already up.
        if presentedBarButtonMenu != nil { return }

        let sourceID = barButtonID(for: item, alignment: alignment)
        let sourceViews = glassButtonGroups(for: alignment).compactMap { group -> (hit: UIView, visual: UIView)? in
            guard let hit = group.itemButton(id: sourceID) else {
                return nil
            }
            return (hit, group.itemVisualSourceView(id: sourceID) ?? hit)
        }.first
        guard let sourceViews else {
            return
        }
        presentBarButtonContextMenu(
            sourceView: sourceViews.hit,
            visualSourceView: sourceViews.visual,
            provider: provider
        )
    }

    private func presentBarButtonContextMenu(
        sourceView: UIView,
        visualSourceView: UIView,
        provider: () -> [ContextMenuItem]
    ) {
        // Don't open a duplicate menu if one is already up.
        if presentedBarButtonMenu != nil { return }

        let items = provider()
        guard !items.isEmpty else { return }
        guard sourceView.window != nil else { return }

        let menu = ContextMenuController(
            source: .init(
                view: visualSourceView,
                cornerRadius: visualSourceView.bounds.height / 2.0,
                hidesDuringPresentation: true
            ),
            items: items,
            presentationStyle: .fluidMorph,
            onDismiss: { [weak self] in
                guard let self else { return }
                self.presentedBarButtonMenu = nil
            }
        )
        presentedBarButtonMenu = menu
        menu.present()
    }

}

// MARK: - Back Button Content View (for GlassControlGroup)

/// Lightweight icon + label view used as `.customView` content inside
/// `GlassControlGroup`. The group provides the glass capsule background;
/// this view just renders the chevron and title text.
private final class BackButtonContentView: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()

    init(icon: UIImage?, text: String, tintColor: UIColor) {
        super.init(frame: .zero)

        iconView.image = icon?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = tintColor
        iconView.contentMode = .center
        addSubview(iconView)

        label.text = text
        label.font = .systemFont(ofSize: 17.0)
        label.textColor = tintColor
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let iconWidth: CGFloat = iconView.image == nil ? 0.0 : 20.0
        let spacing: CGFloat = (iconView.image == nil || label.text?.isEmpty == true) ? 0.0 : 3.0
        let labelSize = label.sizeThatFits(size)
        return CGSize(width: iconWidth + spacing + labelSize.width, height: max(labelSize.height, 20.0))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let iconWidth: CGFloat = iconView.image == nil ? 0.0 : 20.0
        let spacing: CGFloat = (iconView.image == nil || label.text?.isEmpty == true) ? 0.0 : 3.0
        iconView.frame = CGRect(x: 0.0, y: 0.0, width: iconWidth, height: bounds.height)
        label.frame = CGRect(x: iconWidth + spacing, y: 0.0, width: bounds.width - iconWidth - spacing, height: bounds.height)
    }
}

// MARK: - Back Button View

final class NavigationBackButtonView: UIView {
    private let glassBackground = GlassBackgroundView(style: .regular)
    private let iconView = UIImageView()
    private let label = UILabel()
    private var elasticRecognizer: GlassHighlightGestureRecognizer?

    var action: (() -> Void)?

    var text: String = "" {
        didSet {
            label.text = text
            invalidateIntrinsicContentSize()
        }
    }

    var color: UIColor = .systemBlue {
        didSet {
            label.textColor = color
        }
    }

    var contentTintColor: UIColor = .systemBlue {
        didSet {
            iconView.tintColor = contentTintColor
            label.textColor = contentTintColor
        }
    }

    var isDark: Bool = false {
        didSet {
            setNeedsLayout()
        }
    }

    var usesGlassStyle: Bool = false {
        didSet {
            glassBackground.isHidden = !usesGlassStyle
            iconView.isHidden = !usesGlassStyle || icon == nil
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    var icon: UIImage? {
        didSet {
            iconView.image = icon?.withRenderingMode(.alwaysTemplate)
            iconView.isHidden = !usesGlassStyle || icon == nil
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Glass must be interactive so UIGlassEffect.isInteractive (iOS
        // 26+) can observe finger position for the native warp.
        glassBackground.isUserInteractionEnabled = true
        glassBackground.isHidden = true
        addSubview(glassBackground)

        // Icon + label sit inside the glass content host so the warp
        // deforms both surface and contents together (same trick as
        // GlassButton / GlassBarButtonView).
        iconView.contentMode = .center
        iconView.tintColor = contentTintColor
        iconView.isHidden = true
        glassBackground.contentView.addSubview(iconView)

        label.font = UIFont.systemFont(ofSize: 17.0)
        label.textColor = color
        glassBackground.contentView.addSubview(label)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        if #unavailable(iOS 26.0) {
            let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
            elastic.touchEffectView = self
            elastic.highlightContainerView = glassBackground.contentView
            addGestureRecognizer(elastic)
            self.elasticRecognizer = elastic
        }
    }

    @objc private func handleTap() {
        action?()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let labelSize = label.sizeThatFits(size)
        if usesGlassStyle {
            let iconWidth: CGFloat = icon == nil ? 0.0 : 20.0
            let spacing: CGFloat = icon == nil || text.isEmpty ? 0.0 : 3.0
            return CGSize(width: max(44.0, labelSize.width + iconWidth + spacing + 20.0), height: 44.0)
        }
        return labelSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if usesGlassStyle {
            glassBackground.frame = bounds
            glassBackground.update(
                size: bounds.size,
                cornerRadius: bounds.height * 0.5,
                isDark: isDark,
                tintColor: .init(kind: .panel),
                isInteractive: true,
                isVisible: true,
                transition: .immediate
            )

            let iconWidth: CGFloat = icon == nil ? 0.0 : 20.0
            let spacing: CGFloat = icon == nil || text.isEmpty ? 0.0 : 3.0
            let labelSize = label.sizeThatFits(CGSize(width: max(0.0, bounds.width - iconWidth - spacing - 20.0), height: bounds.height))
            let contentWidth = iconWidth + spacing + labelSize.width
            var x = floor((bounds.width - contentWidth) / 2.0)
            if icon != nil {
                iconView.frame = CGRect(x: x, y: 0.0, width: iconWidth, height: bounds.height)
                x += iconWidth + spacing
            }
            label.frame = CGRect(x: x, y: 0.0, width: labelSize.width, height: bounds.height)
        } else {
            label.frame = bounds
        }
    }

}
