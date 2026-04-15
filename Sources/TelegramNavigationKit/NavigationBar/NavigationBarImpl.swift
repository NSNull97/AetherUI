import UIKit

/// Full UIKit implementation of NavigationBarView.
/// Replaces the ASDK-based NavigationBarImpl from Telegram.
public final class NavigationBarImpl: UIView, NavigationBarView {
    // MARK: - Subviews

    public let backgroundView: NavigationBackgroundView
    public let stripeView: UIView
    private let clippingView: SparseView
    private let buttonsContainerView: UIView

    private let backButtonView: NavigationBackButtonView
    private let backArrowView: UIImageView
    private let titleLabel: UILabel
    private let leftButtonContainer: UIView
    private let rightButtonContainer: UIView
    /// Persistent glass group used for the left bar button items in glass mode
    /// (direct port equivalent of Telegram's `leftButtonsBackgroundView`).
    private var leftButtonsGroup: GlassControlGroup?
    /// Persistent glass group used for the right bar button items in glass mode.
    private var rightButtonsGroup: GlassControlGroup?
    public let badgeView: NavigationBarBadgeView
    private var titleContentView: UIView?

    private var _contentView: NavigationBarContentView?
    public var contentView: NavigationBarContentView? { _contentView }

    private var glassBackgroundView: GlassBackgroundView?
    /// Scroll-edge fade effect rendered ABOVE the nav bar. Mirrors Telegram's
    /// `NavigationBarImpl.edgeEffectView` — makes scroll content "dissolve" as
    /// it approaches the top of the screen.
    private var edgeEffectView: EdgeEffectView?

    // MARK: - State

    private var presentationData: NavigationBarPresentationData
    private var validLayout: (size: CGSize, defaultHeight: CGFloat, leftInset: CGFloat, rightInset: CGFloat)?

    public var backPressed: () -> Void = {}
    public var userInfo: Any?

    public var item: UINavigationItem? {
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

    // MARK: - Init

    public init(presentationData: NavigationBarPresentationData) {
        self.presentationData = presentationData
        let theme = presentationData.theme

        self.backgroundView = NavigationBackgroundView(color: theme.backgroundColor, enableBlur: theme.enableBackgroundBlur)
        self.stripeView = UIView()
        self.clippingView = SparseView()
        self.buttonsContainerView = UIView()

        self.backButtonView = NavigationBackButtonView()
        self.backArrowView = UIImageView()
        self.titleLabel = UILabel()
        self.leftButtonContainer = UIView()
        self.rightButtonContainer = UIView()
        self.badgeView = NavigationBarBadgeView()

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
        buttonsContainerView.addSubview(backArrowView)

        // Back button
        backButtonView.color = theme.buttonColor
        backButtonView.contentTintColor = theme.buttonColor
        // isDark is applied effectively in updateLayout / traitCollectionDidChange
        // so the glass pill responds to the system dark-mode switch, not just
        // the static theme flag. Kept static here for the very first frame.
        backButtonView.isDark = theme.overallDarkAppearance
        backButtonView.usesGlassStyle = theme.style == .glass
        backButtonView.icon = NavigationBarTheme.generateBackArrowImage(color: theme.buttonColor)
        backButtonView.addTarget(self, action: #selector(backButtonPressed), for: .touchUpInside)
        buttonsContainerView.addSubview(backButtonView)

        // Title
        titleLabel.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel.textColor = theme.primaryTextColor
        titleLabel.textAlignment = .center
        buttonsContainerView.addSubview(titleLabel)

        // Left/Right button containers
        buttonsContainerView.addSubview(leftButtonContainer)
        buttonsContainerView.addSubview(rightButtonContainer)

        // Badge
        buttonsContainerView.addSubview(badgeView)

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
            if result === self || result === clippingView || result === buttonsContainerView {
                return nil
            }
            return result
        }
        return super.hitTest(point, with: event)
    }

    // MARK: - NavigationBarView Protocol

    public func contentHeight(defaultHeight: CGFloat) -> CGFloat {
        if let contentView = _contentView {
            switch contentView.mode {
            case .replacement:
                return contentView.height
            case .expansion:
                return defaultHeight + contentView.height
            }
        }
        return defaultHeight
    }

    public func setContentView(_ contentView: NavigationBarContentView?, animated: Bool) {
        // iOS 26-style "glass replacement": the outgoing content softly
        // fades with a tiny shrink, the incoming content emerges with a
        // tiny grow. Both run concurrently so the swap feels like a fluid
        // morph rather than a fade-out-then-in.
        let fadeOutScale: CGFloat = 0.94
        let fadeInScaleStart: CGFloat = 0.94

        if let old = _contentView, old !== contentView {
            if animated {
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
                        } else {
                            old.removeFromSuperview()
                            old.alpha = 1.0
                            old.transform = .identity
                        }
                    }
                )
            } else {
                old.removeFromSuperview()
                old.alpha = 1.0
                old.transform = .identity
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

    // MARK: - Programmatic glass item transition
    //
    // `performGlassItemChange(changes:)` wraps an `item` / `previousItem`
    // swap in an iOS 26-style soft glass replacement: the outgoing state
    // fades + shrinks slightly, the incoming state emerges with a
    // mirror scale. It uses a snapshot overlay of the OLD buttons
    // container so that title text / back-pill visibility / button
    // additions and removals all crossfade together as a single unit
    // (the raw property changes are not individually animatable).
    //
    // Caller puts ALL the state mutations (self.item = ..., previousItem
    // = ...) inside the `changes` closure. The method snapshots the
    // current container, runs the closure, forces a layout so the new
    // buttons are at their target positions, installs the snapshot as
    // an overlay, and animates the crossfade.

    private var isPerformingGlassItemChange: Bool = false

    /// True while a programmatic glass item change animation is running.
    /// `updateLayout` uses this to avoid snapping `buttonsContainerView`
    /// alpha/transform back to 1.0/identity mid-animation (which would
    /// interrupt the fade-in).
    public var hasGlassItemChangeInFlight: Bool {
        isPerformingGlassItemChange
    }

    public func performGlassItemChange(
        duration: TimeInterval = 0.32,
        changes: () -> Void
    ) {
        // Snapshot the CURRENT buttons/title before mutating state.
        let oldSnap = buttonsContainerView.snapshotView(afterScreenUpdates: false)

        // Apply new state. `item.didSet` / `previousItem.didSet` update
        // titles and visibility synchronously but DON'T trigger a layout
        // (per the contract in updateItemContent). We explicitly lay out
        // below so the new buttons render at their target positions for
        // the animation's "to" frame.
        changes()

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

        // Install the old snapshot above the now-up-to-date buttons
        // container. The new state is visible underneath at alpha=1 by
        // default; we'll animate it IN from a tiny scale + 0 alpha so
        // the two states crossfade into each other.
        guard let oldSnap else { return }
        oldSnap.frame = buttonsContainerView.frame
        oldSnap.alpha = 1.0
        clippingView.insertSubview(oldSnap, aboveSubview: buttonsContainerView)

        buttonsContainerView.alpha = 0.0
        buttonsContainerView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        isPerformingGlassItemChange = true

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
            animations: {
                oldSnap.alpha = 0.0
                oldSnap.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
                self.buttonsContainerView.alpha = 1.0
                self.buttonsContainerView.transform = .identity
            },
            completion: { [weak self] _ in
                oldSnap.removeFromSuperview()
                self?.isPerformingGlassItemChange = false
            }
        )
    }

    // MARK: - Interactive item transition
    //
    // When the container hosting this bar is driving an *interactive*
    // pop (user is dragging-to-go-back), the shared bar needs to show
    // both the "from" and "to" states simultaneously and crossfade
    // between them based on gesture progress. We implement that by
    // capturing two snapshots of `buttonsContainerView` — one for each
    // state — and blending their alphas in sync with the drag.
    //
    // API contract:
    //  1. `beginInteractiveItemTransition(targetItem:targetPreviousItem:)`
    //     snapshots the current state, applies the target state long
    //     enough to snapshot that too, then reverts. Both snapshots are
    //     installed above `buttonsContainerView`.
    //  2. `updateInteractiveItemTransition(progress:)` — called from the
    //     pan `.changed` handler. 0 → show only OLD, 1 → show only NEW.
    //  3. `finishInteractiveItemTransition(cancelled:)` — fades the
    //     leftover snapshots out. When `cancelled == false` the caller
    //     is expected to have already re-applied the target state
    //     permanently via a regular item/previousItem assignment.

    private var interactiveOldSnapshot: UIView?
    private var interactiveNewSnapshot: UIView?

    public var hasInteractiveItemTransitionInFlight: Bool {
        interactiveOldSnapshot != nil || interactiveNewSnapshot != nil
    }

    public func beginInteractiveItemTransition(
        targetItem: UINavigationItem?,
        targetPreviousItem: NavigationPreviousAction?
    ) {
        // Clean up any leftover snapshots from a prior aborted transition.
        interactiveOldSnapshot?.removeFromSuperview()
        interactiveNewSnapshot?.removeFromSuperview()

        // Snapshot the CURRENT (old) state.
        let oldSnap = buttonsContainerView.snapshotView(afterScreenUpdates: false)

        // Swap to target state, force layout, snapshot, revert.
        let savedItem = self.item
        let savedPrevious = self.previousItem
        // Direct ivar-style assignment via the public setters triggers
        // didSet paths (updateItemContent / updateBackButton); that's what
        // we want so the layout reflects the target state.
        self.item = targetItem
        self.previousItem = targetPreviousItem
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
        let newSnap = buttonsContainerView.snapshotView(afterScreenUpdates: true)

        // Revert to old state — caller will apply new state permanently
        // only at commit time. (In cancel, we stay in old state.)
        self.item = savedItem
        self.previousItem = savedPrevious
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

        if let oldSnap {
            oldSnap.frame = buttonsContainerView.frame
            oldSnap.alpha = 1.0
            clippingView.insertSubview(oldSnap, aboveSubview: buttonsContainerView)
            interactiveOldSnapshot = oldSnap
        }
        if let newSnap {
            newSnap.frame = buttonsContainerView.frame
            newSnap.alpha = 0.0
            clippingView.insertSubview(newSnap, aboveSubview: oldSnap ?? buttonsContainerView)
            interactiveNewSnapshot = newSnap
        }
        // Hide the live container while snapshots are on top so the
        // two layers don't stack-render at intermediate alphas (would
        // look doubly-faded at 50%).
        buttonsContainerView.alpha = 0.0
    }

    public func updateInteractiveItemTransition(progress: CGFloat) {
        let clamped = max(0.0, min(1.0, progress))
        interactiveOldSnapshot?.alpha = 1.0 - clamped
        interactiveNewSnapshot?.alpha = clamped
    }

    public func finishInteractiveItemTransition(cancelled: Bool, duration: TimeInterval = 0.2) {
        let oldSnap = interactiveOldSnapshot
        let newSnap = interactiveNewSnapshot
        interactiveOldSnapshot = nil
        interactiveNewSnapshot = nil

        // Restore live container visibility; the final item/previousItem
        // is in whatever state the caller has set (cancel: still OLD;
        // commit: already NEW via syncNavigationItem).
        buttonsContainerView.alpha = 1.0

        let oldTarget: CGFloat = cancelled ? 1.0 : 0.0
        let newTarget: CGFloat = cancelled ? 0.0 : 1.0
        UIView.animate(withDuration: duration, animations: {
            oldSnap?.alpha = oldTarget
            newSnap?.alpha = newTarget
        }, completion: { _ in
            oldSnap?.removeFromSuperview()
            newSnap?.removeFromSuperview()
        })
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
        clippingView.clipsToBounds = theme.style != .glass
        titleLabel.textColor = theme.primaryTextColor
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
    }

    public func updateLayout(size: CGSize, defaultHeight: CGFloat, additionalTopHeight: CGFloat, additionalContentHeight: CGFloat, additionalBackgroundHeight: CGFloat, additionalCutout: CGSize?, leftInset: CGFloat, rightInset: CGFloat, appearsHidden: Bool, isLandscape: Bool, transition: ContainedViewLayoutTransition) {
        guard !layoutSuspended else { return }

        self.validLayout = (size, defaultHeight, leftInset, rightInset)

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
        // content (matches Telegram's Dynamic-Island-style cutout handling).
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
                let edgeEffectFrame = CGRect(x: 0.0, y: -8.0, width: size.width, height: size.height)
                transition.updateFrame(view: edgeEffect, frame: edgeEffectFrame)
                // Fade zone = roughly the bottom third so the transparency at
                // the nav-bar boundary is a soft ramp rather than a hard edge.
                let fadeZone: CGFloat = min(48.0, size.height * 0.4)
                edgeEffect.update(
                    content: presentationData.theme.edgeEffectColor ?? presentationData.theme.opaqueBackgroundColor,
                    blur: true,
                    alpha: 0.65,
                    rect: CGRect(origin: .zero, size: edgeEffectFrame.size),
                    edge: .top, // solid at TOP (status bar), fade at BOTTOM (content boundary)
                    edgeSize: fadeZone,
                    blurRadiusAtEdge: 3.0, // strong blur at the screen top
                    blurRadiusAtFade: 3.0, // ramps down to almost nothing at the content boundary
                    transition: transition
                )
            }
        }

        // Clipping
        transition.updateFrame(view: clippingView, frame: CGRect(origin: .zero, size: size))

        // Content area
        let statusBarHeight = size.height - contentHeight
        let buttonsAreaY = statusBarHeight + additionalTopHeight
        let buttonsAreaHeight = contentHeight - additionalTopHeight
        let buttonsFrame = CGRect(x: 0, y: buttonsAreaY, width: size.width, height: buttonsAreaHeight)
        transition.updateFrame(view: buttonsContainerView, frame: buttonsFrame)

        // Layout buttons
        layoutButtons(width: size.width, height: buttonsAreaHeight, leftInset: leftInset, rightInset: rightInset, defaultHeight: defaultHeight, transition: transition)

        // Content view
        if let contentView = _contentView {
            switch contentView.mode {
            case .replacement:
                let contentFrame = CGRect(x: 0, y: buttonsAreaY, width: size.width, height: contentView.height)
                transition.updateFrame(view: contentView, frame: contentFrame)
                let _ = contentView.updateLayout(size: contentFrame.size, leftInset: leftInset, rightInset: rightInset, transition: transition)

                // Skip alpha reassignment while a glass item change is
                // crossfading — it owns buttonsContainerView.alpha for
                // the duration of the animation.
                if !isPerformingGlassItemChange {
                    buttonsContainerView.alpha = 0.0
                }
            case .expansion:
                let contentFrame = CGRect(x: 0, y: buttonsAreaY + defaultHeight, width: size.width, height: contentView.height)
                transition.updateFrame(view: contentView, frame: contentFrame)
                let _ = contentView.updateLayout(size: contentFrame.size, leftInset: leftInset, rightInset: rightInset, transition: transition)

                if !isPerformingGlassItemChange {
                    buttonsContainerView.alpha = 1.0
                }
            }
        } else if !isPerformingGlassItemChange {
            buttonsContainerView.alpha = 1.0
        }
    }

    // MARK: - Private

    private func layoutButtons(width: CGFloat, height: CGFloat, leftInset: CGFloat, rightInset: CGFloat, defaultHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let buttonHeight: CGFloat = min(defaultHeight, height)
        let sideInset: CGFloat = 8.0
        let usesGlassStyle = presentationData.theme.style == .glass

        let backFrame: CGRect
        let titleLeftInset: CGFloat
        let titleRightInset: CGFloat
        if usesGlassStyle {
            backArrowView.isHidden = true
            let glassButtonHeight: CGFloat = 44.0
            let glassSideInset: CGFloat = 16.0
            let glassInterGroupSpacing: CGFloat = 8.0
            let glassY = floor((buttonHeight - glassButtonHeight) / 2.0) + 2.0

            // Back button first — in glass mode it is its own capsule and, when
            // present, pushes subsequent left-side content (leftButtonContainer)
            // further right so the two do not overlap.
            let backIsVisible = !backButtonView.isHidden
            let backSize = backButtonView.sizeThatFits(CGSize(width: width / 2.0, height: glassButtonHeight))
            backFrame = CGRect(
                x: leftInset + glassSideInset,
                y: glassY,
                width: backSize.width,
                height: glassButtonHeight
            )
            transition.updateFrame(view: backButtonView, frame: backFrame)

            let leftStart = leftInset + glassSideInset + (backIsVisible ? backSize.width + glassInterGroupSpacing : 0.0)
            let leftAvailableWidth = max(1.0, width * 0.5 - leftStart)
            let rightAvailableWidth = max(1.0, width * 0.5 - rightInset - glassSideInset)

            transition.updateFrame(view: leftButtonContainer, frame: CGRect(x: leftStart, y: glassY, width: leftAvailableWidth, height: glassButtonHeight))
            transition.updateFrame(view: rightButtonContainer, frame: CGRect(x: width * 0.5, y: glassY, width: rightAvailableWidth, height: glassButtonHeight))

            let leftButtonsWidth = layoutBarButtonItems(in: leftButtonContainer, items: item?.leftBarButtonItems, alignment: .left, height: glassButtonHeight)
            let rightButtonsWidth = layoutBarButtonItems(in: rightButtonContainer, items: item?.rightBarButtonItems, alignment: .right, height: glassButtonHeight)

            if leftButtonsWidth > 0.0 {
                transition.updateFrame(view: leftButtonContainer, frame: CGRect(x: leftStart, y: glassY, width: leftButtonsWidth, height: glassButtonHeight))
            }
            if rightButtonsWidth > 0.0 {
                transition.updateFrame(view: rightButtonContainer, frame: CGRect(x: width - rightInset - glassSideInset - rightButtonsWidth, y: glassY, width: rightButtonsWidth, height: glassButtonHeight))
            }

            let effectiveLeftWidth = (backIsVisible ? backSize.width + (leftButtonsWidth > 0.0 ? glassInterGroupSpacing + leftButtonsWidth : 0.0) : leftButtonsWidth)
            titleLeftInset = effectiveLeftWidth > 0.0 ? leftInset + glassSideInset + effectiveLeftWidth + 10.0 : leftInset
            titleRightInset = rightButtonsWidth > 0.0 ? rightInset + glassSideInset + rightButtonsWidth + 10.0 : rightInset
        } else {
            // Back arrow
            let arrowSize = CGSize(width: 13.0, height: 22.0)
            let arrowFrame = CGRect(x: sideInset + leftInset, y: (buttonHeight - arrowSize.height) / 2.0, width: arrowSize.width, height: arrowSize.height)
            transition.updateFrame(view: backArrowView, frame: arrowFrame)

            // Back button
            let backTextX = arrowFrame.maxX + 6.0
            let backSize = backButtonView.sizeThatFits(CGSize(width: width / 2.0, height: buttonHeight))
            backFrame = CGRect(x: backTextX, y: (buttonHeight - backSize.height) / 2.0, width: backSize.width, height: backSize.height)
            transition.updateFrame(view: backButtonView, frame: backFrame)

            titleLeftInset = max(backFrame.maxX + sideInset, sideInset + leftInset + 44.0)
            titleRightInset = sideInset + rightInset + 88.0

            // Left buttons
            let leftFrame = CGRect(x: sideInset + leftInset, y: 0, width: width / 3.0, height: buttonHeight)
            transition.updateFrame(view: leftButtonContainer, frame: leftFrame)

            // Right buttons
            let rightWidth = width / 3.0
            let rightFrame = CGRect(x: width - rightWidth - sideInset - rightInset, y: 0, width: rightWidth, height: buttonHeight)
            transition.updateFrame(view: rightButtonContainer, frame: rightFrame)

            layoutBarButtonItems(in: rightButtonContainer, items: item?.rightBarButtonItems, alignment: .right, height: buttonHeight)
            layoutBarButtonItems(in: leftButtonContainer, items: item?.leftBarButtonItems, alignment: .left, height: buttonHeight)
        }

        let balancedTitleInset = max(titleLeftInset, titleRightInset)
        let titleMaxWidth = max(0.0, width - balancedTitleInset * 2.0)
        if let titleContentView {
            let fittingSize = titleContentView.sizeThatFits(CGSize(width: titleMaxWidth, height: buttonHeight))
            let titleSize = CGSize(
                width: min(titleMaxWidth, max(0.0, fittingSize.width > 0.0 ? fittingSize.width : titleContentView.bounds.width)),
                height: min(buttonHeight, max(0.0, fittingSize.height > 0.0 ? fittingSize.height : titleContentView.bounds.height))
            )
            var titleFrame = CGRect(
                x: floor((width - titleSize.width) / 2.0),
                y: floor((buttonHeight - titleSize.height) / 2.0) + (usesGlassStyle ? 1.0 : 0.0),
                width: titleSize.width,
                height: titleSize.height
            )
            titleFrame.origin.x = min(max(titleFrame.origin.x, titleLeftInset), max(titleLeftInset, width - titleRightInset - titleFrame.width))
            transition.updateFrame(view: titleContentView, frame: titleFrame)
        } else {
            let titleSize = titleLabel.sizeThatFits(CGSize(width: titleMaxWidth, height: buttonHeight))
            var titleFrame = CGRect(x: floor((width - titleSize.width) / 2.0), y: floor((buttonHeight - titleSize.height) / 2.0) + (usesGlassStyle ? 1.0 : 0.0), width: titleSize.width, height: titleSize.height)
            titleFrame.origin.x = min(max(titleFrame.origin.x, titleLeftInset), max(titleLeftInset, width - titleRightInset - titleFrame.width))
            transition.updateFrame(view: titleLabel, frame: titleFrame)
        }
    }

    private enum ButtonAlignment {
        case left, right
    }

    @discardableResult
    private func layoutBarButtonItems(in container: UIView, items: [UIBarButtonItem]?, alignment: ButtonAlignment, height: CGFloat) -> CGFloat {
        let theme = presentationData.theme

        if theme.style == .glass {
            // Reuse persistent GlassControlGroup across updates so the native
            // UIGlassEffect capsule can animate/morph instead of being rebuilt.
            let group: GlassControlGroup
            switch alignment {
            case .left:
                if let existing = leftButtonsGroup {
                    group = existing
                } else {
                    let new = GlassControlGroup()
                    leftButtonsGroup = new
                    container.addSubview(new)
                    group = new
                }
            case .right:
                if let existing = rightButtonsGroup {
                    group = existing
                } else {
                    let new = GlassControlGroup()
                    rightButtonsGroup = new
                    container.addSubview(new)
                    group = new
                }
            }

            // Clean up stale non-group subviews from legacy path.
            for sub in container.subviews where sub !== group {
                sub.removeFromSuperview()
            }

            guard let items, !items.isEmpty else {
                group.update(
                    items: [],
                    background: .panel,
                    preferClearGlass: theme.glassStyle == .clear,
                    foregroundColor: theme.buttonColor,
                    isDark: theme.overallDarkAppearance,
                    availableHeight: height,
                    minWidth: height,
                    transition: .immediate
                )
                return 0.0
            }

            let groupItems: [GlassControlGroup.Item] = items.map { item in
                let content: GlassControlGroup.Item.Content
                // Text buttons get 8pt horizontal inset (Figma spec). Icon and
                // custom-view buttons use zero inset — their natural size +
                // `GlassControlGroup`'s per-item min width handles the padding.
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

                let action: (() -> Void)?
                if let selector = item.action, let target = item.target as AnyObject? {
                    action = { [weak target] in
                        UIApplication.shared.sendAction(selector, to: target, from: item, for: nil)
                    }
                } else {
                    action = nil
                }

                return GlassControlGroup.Item(id: ObjectIdentifier(item), content: content, contentInsets: insets, action: action)
            }

            let size = group.update(
                items: groupItems,
                background: .panel,
                preferClearGlass: theme.glassStyle == .clear,
                foregroundColor: theme.buttonColor,
                isDark: theme.overallDarkAppearance || traitCollection.userInterfaceStyle == .dark,
                availableHeight: height,
                minWidth: height,
                transition: .immediate
            )
            return size.width
        }

        // Legacy (non-glass) layout — unchanged from prior behaviour.
        if let group = leftButtonsGroup, container === leftButtonContainer {
            group.removeFromSuperview()
            leftButtonsGroup = nil
        }
        if let group = rightButtonsGroup, container === rightButtonContainer {
            group.removeFromSuperview()
            rightButtonsGroup = nil
        }

        container.subviews.forEach { $0.removeFromSuperview() }
        guard let items, !items.isEmpty else { return 0.0 }

        var offsetX: CGFloat = 0

        for item in items {
            let view: UIView
            let size: CGSize

            if let customView = item.customView {
                view = customView
                let fittingSize = customView.sizeThatFits(CGSize(width: container.bounds.width, height: height))
                size = CGSize(
                    width: max(30.0, fittingSize.width > 0.0 ? fittingSize.width : customView.bounds.width),
                    height: min(height, max(0.0, fittingSize.height > 0.0 ? fittingSize.height : customView.bounds.height))
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
                size = button.intrinsicContentSize
            } else {
                let button = UIButton(type: .system)
                button.tintColor = theme.buttonColor

                if let image = item.image {
                    button.setImage(image, for: .normal)
                } else if let title = item.title {
                    button.setTitle(title, for: .normal)
                    button.titleLabel?.font = UIFont.systemFont(ofSize: 17.0)
                }

                if let action = item.action, let target = item.target {
                    button.addTarget(target, action: action, for: .touchUpInside)
                }

                button.sizeToFit()
                view = button
                size = CGSize(width: max(button.bounds.width, 30.0), height: button.bounds.height)
            }

            let x: CGFloat
            switch alignment {
            case .left:
                x = offsetX
            case .right:
                x = container.bounds.width - offsetX - size.width
            }

            view.frame = CGRect(x: x, y: floor((height - size.height) / 2.0), width: size.width, height: size.height)
            container.addSubview(view)
            offsetX += size.width + 8.0
        }
        return max(0.0, offsetX - 8.0)
    }

    private func updateItemContent() {
        titleLabel.text = item?.title
        if let existingTitleContentView = titleContentView, existingTitleContentView !== item?.titleView {
            existingTitleContentView.removeFromSuperview()
            titleContentView = nil
        }
        if let titleView = item?.titleView, titleView !== titleContentView {
            titleContentView?.removeFromSuperview()
            titleContentView = titleView
            buttonsContainerView.addSubview(titleView)
        }
        titleLabel.isHidden = titleContentView != nil
        updateBackButton()
        // Do NOT schedule any layout here. The caller — syncNavigationItem
        // in TabBarController, wireControllers in NavigationController, etc.
        // — is responsible for driving the layout pass with the correct
        // transition. Requesting an animated spring here meant every
        // `item = ...` set kicked off a 0.3s layout, which showed up as
        // an unwanted animation on tab switches (syncNavigationItem passes
        // animated: false, but this implicit request was overriding it).
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

        // Scroll-edge fade (Telegram's `NavigationBarImpl` creates this unconditionally
        // in glass mode — scrolling content dissolves as it meets the nav bar).
        let edgeEffect = EdgeEffectView()
        edgeEffect.isUserInteractionEnabled = false
        insertSubview(edgeEffect, at: 0)
        self.edgeEffectView = edgeEffect
    }
}

// MARK: - Back Button View

final class NavigationBackButtonView: UIControl {
    private let glassBackground = GlassBackgroundView(style: .regular)
    private let iconView = UIImageView()
    private let label = UILabel()

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

        glassBackground.isUserInteractionEnabled = false
        glassBackground.isHidden = true
        addSubview(glassBackground)

        iconView.contentMode = .center
        iconView.tintColor = contentTintColor
        iconView.isHidden = true
        addSubview(iconView)

        label.font = UIFont.systemFont(ofSize: 17.0)
        label.textColor = color
        addSubview(label)

        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let labelSize = label.sizeThatFits(size)
        if usesGlassStyle {
            let iconWidth: CGFloat = icon == nil ? 0.0 : 20.0
            let spacing: CGFloat = icon == nil || text.isEmpty ? 0.0 : 3.0
            return CGSize(width: max(36.0, labelSize.width + iconWidth + spacing + 20.0), height: 36.0)
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
                isInteractive: false,
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

    @objc private func touchDown() {
        applyPressAnimation(pressed: true)
    }

    @objc private func touchUp() {
        applyPressAnimation(pressed: false)
    }

    /// Glass-style press animation matching `HighlightTrackingButton` in
    /// `GlassControlGroup`: spring-scale up to 1.15 on press, relax to 1.0 on
    /// release. Subtle alpha dip preserves the previous "press feedback".
    private func applyPressAnimation(pressed: Bool) {
        let scaleKey = "transform.scale"
        layer.removeAnimation(forKey: scaleKey)

        let fromValue = (layer.presentation()?.value(forKeyPath: "transform.scale.x") as? NSNumber)?.floatValue
            ?? Float(pressed ? 1.0 : 1.0)
        let toValue: Float = pressed ? 1.0 : 1.0

        let spring = CASpringAnimation(keyPath: scaleKey)
        spring.fromValue = fromValue
        spring.toValue = toValue
        spring.mass = 1.0
        spring.stiffness = pressed ? 520.0 : 480.0
        spring.damping = pressed ? 34.0 : 22.0
        spring.duration = spring.settlingDuration
        spring.fillMode = .forwards
        spring.isRemovedOnCompletion = false
        layer.add(spring, forKey: scaleKey)
        layer.setValue(toValue, forKeyPath: scaleKey)

        UIView.animate(withDuration: pressed ? 0.1 : 0.25, animations: {
            self.alpha = pressed ? 0.7 : 1.0
        })
    }
}
