import UIKit

/// Custom tab bar view with glass-style rendering and glass support.
/// Replaces the original TabBarNode.
public final class TabBarView: UIView {
    // MARK: - Types

    public enum Style {
        case legacy
        case liquidGlass
    }

    public struct Theme {
        public let tabBarBackgroundColor: UIColor
        public let tabBarSeparatorColor: UIColor
        public let tabBarIconColor: UIColor
        public let tabBarSelectedIconColor: UIColor
        public let tabBarTextColor: UIColor
        public let tabBarSelectedTextColor: UIColor
        public let tabBarBadgeBackgroundColor: UIColor
        public let tabBarBadgeStrokeColor: UIColor
        public let tabBarBadgeTextColor: UIColor
        public let enableBlur: Bool
        public let isDark: Bool
        public let style: Style
        public let outerInsets: UIEdgeInsets

        // Liquid Glass layout
        public let pillHeight: CGFloat
        public let totalHeight: CGFloat
        public let bottomInset: CGFloat
        public let sideInset: CGFloat
        public let innerPadding: CGFloat
        public let showcaseSpacing: CGFloat

        // Edge effect (scroll-content frost). Blur is a progressive ramp
        // anchored at the solid edge (`…AtEdge`, full strength) tapering to
        // `…AtFade` at the content boundary. The TabBar's solid edge sits
        // at the bottom of the screen, so the heavy blur lives at the
        // bottom and tapers to zero where it meets the scrolling content.
        public let edgeEffectAlpha: CGFloat
        public let edgeEffectBlurRadiusAtEdge: CGFloat
        public let edgeEffectBlurRadiusAtFade: CGFloat
        public let edgeEffectTintColor: UIColor?

        public init(
            tabBarBackgroundColor: UIColor = .clear,
            tabBarSeparatorColor: UIColor = .separator,
            tabBarIconColor: UIColor = .label,
            tabBarSelectedIconColor: UIColor = .systemBlue,
            tabBarTextColor: UIColor = .label,
            tabBarSelectedTextColor: UIColor = .systemBlue,
            tabBarBadgeBackgroundColor: UIColor = .systemRed,
            tabBarBadgeStrokeColor: UIColor = .white,
            tabBarBadgeTextColor: UIColor = .white,
            enableBlur: Bool = true,
            isDark: Bool = false,
            style: Style = .liquidGlass,
            outerInsets: UIEdgeInsets = UIEdgeInsets(top: 4.0, left: 25.0, bottom: 4.0, right: 25.0),
            pillHeight: CGFloat = 62.0,
            totalHeight: CGFloat = 103.0,
            bottomInset: CGFloat = 25.0,
            sideInset: CGFloat = 16.0,
            innerPadding: CGFloat = 2.0,
            showcaseSpacing: CGFloat = 7.0,
            edgeEffectAlpha: CGFloat = 0.75,
            edgeEffectBlurRadiusAtEdge: CGFloat = 2.0,
            edgeEffectBlurRadiusAtFade: CGFloat = 0.0,
            edgeEffectTintColor: UIColor? = nil
        ) {
            self.tabBarBackgroundColor = tabBarBackgroundColor
            self.tabBarSeparatorColor = tabBarSeparatorColor
            self.tabBarIconColor = tabBarIconColor
            self.tabBarSelectedIconColor = tabBarSelectedIconColor
            self.tabBarTextColor = tabBarTextColor
            self.tabBarSelectedTextColor = tabBarSelectedTextColor
            self.tabBarBadgeBackgroundColor = tabBarBadgeBackgroundColor
            self.tabBarBadgeStrokeColor = tabBarBadgeStrokeColor
            self.tabBarBadgeTextColor = tabBarBadgeTextColor
            self.enableBlur = enableBlur
            self.isDark = isDark
            self.style = style
            self.outerInsets = outerInsets
            self.pillHeight = pillHeight
            self.totalHeight = totalHeight
            self.bottomInset = bottomInset
            self.sideInset = sideInset
            self.innerPadding = innerPadding
            self.showcaseSpacing = showcaseSpacing
            self.edgeEffectAlpha = edgeEffectAlpha
            self.edgeEffectBlurRadiusAtEdge = edgeEffectBlurRadiusAtEdge
            self.edgeEffectBlurRadiusAtFade = edgeEffectBlurRadiusAtFade
            self.edgeEffectTintColor = edgeEffectTintColor
        }
    }

    // MARK: - Properties

    // MARK: - Types

    /// Companion "search showcase" capsule shown next to the main tab pill,
    /// mirroring iOS 26's native `UISearchTab`. On iOS 26+ both capsules share
    /// a `UIGlassContainerEffect` via `GlassBackgroundContainerView` so they
    /// merge visually when close.
    public struct SearchShowcase {
        public let icon: UIImage?
        public let action: () -> Void
        public init(icon: UIImage? = UIImage(systemName: "magnifyingglass"), action: @escaping () -> Void) {
            self.icon = icon
            self.action = action
        }
    }

    private let backgroundView: NavigationBackgroundView
    private let separatorView: UIView
    /// Container that hosts the lens + optional search showcase so they merge
    /// into a single `UIGlassContainerEffect` on iOS 26+.
    private let tabBarGlassContainer: GlassBackgroundContainerView
    private let liquidLensView: LiquidLensView
    private var searchShowcaseView: GlassBarButtonView?
    private var itemViews: [TabBarItemView] = []
    private var selectedItemViews: [TabBarItemView] = []

    private var glassBackgroundView: GlassBackgroundView?
    /// Scroll-edge fade at the bottom — makes content dissolve as it approaches
    /// the floating tab bar pill (mirrors edge-effect on the TabBar).
    private let edgeEffectView = EdgeEffectView()
    private var theme: Theme

    /// Additional vertical real estate the edge-effect frost should cover
    /// ABOVE the tab bar's own top edge. Driven by `bottomBarAccessory`
    /// on the current tab's view controller — when set, the accessory's
    /// pill sits in this region, and the frost ramps through both the
    /// accessory and the tab bar area as a single visual band.
    public var bottomAccessoryReservedHeight: CGFloat = 0 {
        didSet {
            guard bottomAccessoryReservedHeight != oldValue else { return }
            setNeedsLayout()
        }
    }

    /// Effective bottom offset from the tab bar's bottom edge to the
    /// pill. Devices with a home indicator / safe area already push the
    /// floating pill up from the hardware bezel, so `theme.bottomInset`
    /// (25pt) sits nicely above the indicator. Older phones with
    /// `safeAreaInsets.bottom == 0` have no such buffer — the 25pt
    /// looks like wasted space, so we collapse it to 16pt matching
    /// stock iOS floating-tabbar spacing on non-home-indicator devices.
    private var effectiveBottomInset: CGFloat {
        let raw = window?.safeAreaInsets.bottom ?? superview?.safeAreaInsets.bottom ?? safeAreaInsets.bottom
        return raw > 0.01 ? theme.bottomInset : 16.0
    }

    public var searchShowcase: SearchShowcase? {
        didSet { rebuildSearchShowcase() }
    }

    // MARK: - Minimize Mode (iOS 26 `tabBarMinimizeBehavior`)

    /// Diameter of the collapsed pill / search circle and the height the
    /// `bottomBarAccessory` reflows into between them. Matches the native
    /// 48pt minimized chrome on iOS 26.
    public static let minimizedButtonSize: CGFloat = 48.0

    /// `true` while the tab bar is collapsed into the iOS 26 minimized
    /// state — the pill shrinks to a 48×48 circle on the leading edge
    /// (showing the active tab's icon), the search showcase becomes a
    /// matching 48×48 circle on the trailing edge, and any
    /// `bottomBarAccessory` reflows into the gap between them.
    ///
    /// External callers drive the state through
    /// `setMinimized(_:transition:)` — assignment isn't directly exposed
    /// because we need a transition value to animate the morph.
    public private(set) var isMinimized: Bool = false

    /// Tap handler for the collapsed pill — invoked when the user taps
    /// the 48×48 active-tab circle while minimized. The owning controller
    /// uses this to expand the tab bar back to its full pill form.
    public var onExpandRequested: (() -> Void)?

    /// Active-tab icon drawn inside `tabBarGlassContainer` while
    /// minimized. Lives in the container's content view so the glass
    /// effect deforms in lockstep with the icon during the morph.
    private var minimizedIconView: UIImageView?

    /// Recognizer attached to `tabBarGlassContainer` that only fires in
    /// minimized state — taps the collapsed pill to request expand.
    private var collapsedTapRecognizer: UITapGestureRecognizer?

    /// Transition the next `layoutLiquidGlassItems` pass should drive
    /// inner frames / glass corner-radius animation through. Set by
    /// `setMinimized`, consumed once by the very next layout pass, then
    /// cleared so subsequent layouts (rotation, selection change) don't
    /// re-animate stale state.
    private var pendingMinimizeTransition: ContainedViewLayoutTransition?

    /// Toggle the minimized state with an animated morph.
    ///
    /// The morph is layout-driven: pill / showcase / lens / icon all
    /// re-frame through the same `transition` so the glass surface
    /// deforms continuously (iOS 26's "liquid" feel) instead of
    /// cross-fading two distinct shapes.
    public func setMinimized(_ minimized: Bool, transition: ContainedViewLayoutTransition) {
        guard isMinimized != minimized else { return }
        // Search mode owns the entire chrome — refusing minimize while
        // search is active keeps the two morphs from racing through the
        // same views. The controller is expected to deactivate search
        // before requesting minimize (or vice versa).
        if minimized && isSearchActive {
            return
        }
        isMinimized = minimized

        if minimized {
            ensureMinimizedIconView()
        }
        refreshMinimizedIconImage()

        // Stash the transition so the next layout pass can animate
        // every inner frame + glass cornerRadius update through it.
        pendingMinimizeTransition = transition

        // Cross-fade item icons ⇄ collapsed icon. The lens itself stays
        // fully opaque — the glass surface IS the collapsed circle, so
        // hiding the lens would make the minimized button transparent.
        // Only the items (which live inside the lens) and the new icon
        // animate their alpha.
        let itemsAlpha: CGFloat = minimized ? 0.0 : 1.0
        for itemView in itemViews {
            transition.updateAlpha(view: itemView, alpha: itemsAlpha)
        }
        for selectedItemView in selectedItemViews {
            transition.updateAlpha(view: selectedItemView, alpha: itemsAlpha)
        }
        if let icon = minimizedIconView {
            transition.updateAlpha(view: icon, alpha: minimized ? 1.0 : 0.0)
        }

        // Run the layout pass synchronously so it consumes
        // `pendingMinimizeTransition` while the values are still fresh.
        // `layoutSubviews` itself isn't wrapped in `UIView.animate` —
        // each inner `transition.updateFrame` call runs its own animation
        // block, which is what makes the morph actually animate (the
        // earlier wrapping was getting overridden by subsequent
        // `.immediate` layout passes triggered by `setNeedsLayout`).
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func ensureMinimizedIconView() {
        guard minimizedIconView == nil else { return }
        let icon = UIImageView()
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        icon.alpha = 0.0
        // Sibling of the lens inside the glass container. Putting it
        // INSIDE the lens (`contentView` / `selectedContentView`) makes
        // it disappear: the lens applies a selection-shaped mask to
        // those views so anything outside the selection capsule is
        // clipped, and at the morph endpoints the geometry doesn't
        // line up. Keeping it outside the lens but inside the glass
        // container's content view means the glass surface still sits
        // behind the icon (lens stays opaque), and the icon renders
        // cleanly on top.
        tabBarGlassContainer.contentView.addSubview(icon)
        minimizedIconView = icon
    }

    /// (Re)apply the current active-tab image to the collapsed icon
    /// view, using the raw image without any symbol configuration — that
    /// keeps the glyph the same visual size as the regular tab item
    /// icons (which also render the raw image with `.center` content
    /// mode). The 48×48 glass capsule provides the surrounding chrome;
    /// the icon itself doesn't need to grow.
    private func refreshMinimizedIconImage() {
        guard let icon = minimizedIconView, let raw = activeTabIcon() else { return }
        icon.image = raw.withRenderingMode(.alwaysTemplate)
        icon.tintColor = theme.tabBarSelectedIconColor
    }

    @objc private func collapsedPillTapped(_ recognizer: UITapGestureRecognizer) {
        guard isMinimized, recognizer.state == .ended else { return }
        onExpandRequested?()
    }

    /// Pure-function pill frame for the given bounds size and minimize
    /// state. Lets the owning controller compute accessory layout
    /// without forcing a synchronous `tabBarView.layoutSubviews()` —
    /// that synchronous call was clobbering the in-flight morph
    /// animation by re-setting inner frames with `.immediate`.
    public func computePillFrame(in size: CGSize, minimized: Bool) -> CGRect {
        // `effectiveBottomInset` reads the window's safe-area bottom,
        // so this matches what `layoutLiquidGlassItems` will resolve to
        // when the actual layout pass runs.
        let bottomInset = effectiveBottomInset
        let sideInset = theme.sideInset
        if minimized {
            let pillSize = Self.minimizedButtonSize
            let pillY = size.height - bottomInset - pillSize
            return CGRect(x: sideInset, y: pillY, width: pillSize, height: pillSize)
        }
        let availableWidth = max(0.0, size.width - sideInset * 2.0)
        let showcaseFootprint: CGFloat = (searchShowcaseView != nil) ? (theme.pillHeight + theme.showcaseSpacing) : 0
        let pillWidth = max(0.0, availableWidth - showcaseFootprint)
        let pillY = size.height - bottomInset - theme.pillHeight
        return CGRect(x: sideInset, y: pillY, width: pillWidth, height: theme.pillHeight)
    }

    // MARK: - Search Mode (morph animation)

    /// When `true`, the tab bar is morphed into search mode.
    public private(set) var isSearchActive: Bool = false

    /// Mirrors the on-screen keyboard. Set by the owning controller from
    /// `containerLayoutUpdated` (driven by `AetherWindow`'s keyboard
    /// notifications). Search-mode chrome reacts to this — the active-tab
    /// circle hides while the keyboard is up and the controller hides
    /// the bottom-bar accessory in the same window.
    public private(set) var isKeyboardVisible: Bool = false

    /// Vertical distance the search row sits BELOW the tab pill's top
    /// edge while search is active. The owning controller reads this to
    /// align the bottom-bar accessory with the search row instead of
    /// the (currently invisible) tab pill — keeping the 8pt gap between
    /// accessory and the visible chrome consistent with the no-search
    /// state. Returns 0 when search is inactive.
    public var searchRowTopOffset: CGFloat {
        guard isSearchActive else { return 0 }
        return max(0, (theme.pillHeight - Self.searchModeHeight) / 2)
    }

    /// Sync the cached keyboard state and re-evaluate visibility of the
    /// pieces of the search chrome that depend on it (currently the
    /// `searchTabCircle` and the capsule's leading edge). Idempotent —
    /// called every layout pass.
    public func setKeyboardVisible(_ visible: Bool, transition: ContainedViewLayoutTransition) {
        guard isKeyboardVisible != visible else { return }
        isKeyboardVisible = visible
        updateSearchTabCircleVisibility(transition: transition)
        // Re-flow the capsule so it claims (or releases) the circle's
        // leading slot. Use `animateView` so the frame setters inside
        // `positionSearchViewsExpanded` ride the keyboard's transition
        // instead of snapping.
        if isSearchActive {
            transition.animateView { [weak self] in
                self?.positionSearchViewsExpanded()
            }
        }
    }

    private func updateSearchTabCircleVisibility(transition: ContainedViewLayoutTransition) {
        guard let circle = searchTabCircle else { return }
        let target: CGFloat = (isSearchActive && !isKeyboardVisible) ? 1.0 : 0.0
        if abs(circle.alpha - target) > 0.01 {
            transition.updateAlpha(view: circle, alpha: target)
        }
    }

    /// Text entered in the search field while search is active.
    public var searchText: String { searchTextField?.text ?? "" }

    /// Called when search text changes.
    public var onSearchTextChanged: ((String) -> Void)?

    /// Called when search is dismissed via the active-tab circle.
    public var onSearchDismissed: (() -> Void)?

    // Search mode views
    private var searchCapsule: GlassBackgroundView?       // expanded glass capsule for text field
    private var searchTextField: UITextField?               // text field inside capsule
    private var searchCloseButton: GlassBarButtonView?      // round glass X button
    private var searchTabCircle: GlassBarButtonView?        // collapsed active-tab icon (back to tabs)
    private var searchDimView: EdgeEffectView?               // edge-effect bg

    /// Morph: pill → active-tab circle, search button → capsule with text field.
    public func activateSearchMode(animated: Bool) {
        guard !isSearchActive else { return }
        isSearchActive = true
        buildSearchViews()

        if animated {
            positionSearchViewsAtOrigin()
            // Start capsule and circle small for glass-morph feel
            searchCapsule?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            searchTabCircle?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            searchCloseButton?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            // Show keyboard simultaneously with the morph animation
            searchTextField?.becomeFirstResponder()
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0.3, options: [.beginFromCurrentState]) {
                self.positionSearchViewsExpanded()
                self.searchCapsule?.transform = .identity
                self.searchTabCircle?.transform = .identity
                self.searchCloseButton?.transform = .identity
                self.tabBarGlassContainer.alpha = 0.0
                self.tabBarGlassContainer.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                // Showcase circle (the standalone "открыть поиск" button)
                // morphs into the expanded capsule, so hide the original
                // showcase while search is active — otherwise it stays
                // visible next to the expanded search field.
                self.searchShowcaseView?.alpha = 0.0
                self.searchShowcaseView?.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                self.searchDimView?.alpha = 1.0
            }
        } else {
            positionSearchViewsExpanded()
            tabBarGlassContainer.alpha = 0.0
            searchShowcaseView?.alpha = 0.0
            searchShowcaseView?.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            searchDimView?.alpha = 1.0
            searchTextField?.becomeFirstResponder()
        }
    }

    /// Reverse morph: capsule → search button, circle → pill.
    public func deactivateSearchMode(animated: Bool) {
        guard isSearchActive else { return }
        isSearchActive = false
        searchTextField?.resignFirstResponder()

        if animated {
            // Phase 1: quick fade of search elements + shrink toward origins
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
                // Fade + scale-down all search elements
                self.searchCapsule?.alpha = 0.0
                self.searchCapsule?.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
                self.searchTextField?.alpha = 0.0
                self.searchCloseButton?.alpha = 0.0
                self.searchCloseButton?.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                self.searchTabCircle?.alpha = 0.0
                self.searchTabCircle?.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                self.searchDimView?.alpha = 0.0

                // Restore tab bar + showcase circle (hidden during search).
                self.tabBarGlassContainer.alpha = 1.0
                self.tabBarGlassContainer.transform = .identity
                self.searchShowcaseView?.alpha = 1.0
                self.searchShowcaseView?.transform = .identity
            } completion: { _ in
                self.teardownSearchViews()
            }
        } else {
            tabBarGlassContainer.alpha = 1.0
            tabBarGlassContainer.transform = .identity
            searchShowcaseView?.alpha = 1.0
            searchShowcaseView?.transform = .identity
            teardownSearchViews()
        }
    }

    // -- Build / teardown

    private func buildSearchViews() {
        let dim = EdgeEffectView()
        dim.isUserInteractionEnabled = false
        dim.alpha = 0.0
        insertSubview(dim, aboveSubview: edgeEffectView)
        searchDimView = dim

        let capsule = GlassBackgroundView(style: .regular)
        addSubview(capsule)
        searchCapsule = capsule

        let tf = UITextField()
        tf.placeholder = "Search"
        tf.font = .systemFont(ofSize: 17)
        tf.textColor = .label
        tf.tintColor = .systemBlue
        tf.returnKeyType = .search
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.clearButtonMode = .whileEditing
        tf.alpha = 0.0
        tf.delegate = self
        tf.addTarget(self, action: #selector(searchTextDidChange), for: .editingChanged)
        // leftView wrapper: icon pinned near the left edge, right-side
        // padding controls the visible gap before the placeholder.
        let leftViewWrapper = UIView(frame: CGRect(x: 0, y: 0, width: 28, height: 20))
        let iconImage = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        let icon = UIImageView(image: iconImage)
        icon.tintColor = .secondaryLabel
        icon.frame = CGRect(x: 2, y: 0, width: 16, height: 20)
        icon.contentMode = .center
        leftViewWrapper.addSubview(icon)
        tf.leftView = leftViewWrapper
        tf.leftViewMode = .always
        addSubview(tf)
        searchTextField = tf

        // Round glass close button (X)
        let closeIcon = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        let close = GlassBarButtonView(icon: closeIcon, state: .glass)
        close.contentTintColor = .label
        close.alpha = 0.0
        close.action = { [weak self] _ in self?.onSearchDismissed?() }
        addSubview(close)
        searchCloseButton = close

        // Circle with active tab's icon — tap to go back to tabs.
        // Hidden while the keyboard is up: the search field already
        // reads as "we are searching", and the row sits flush with the
        // keyboard top so there's no extra real estate worth spending
        // on a tap target. The owner toggles visibility via
        // `setKeyboardVisible(_:transition:)` as the keyboard moves.
        let activeIcon = activeTabIcon()
        let circle = GlassBarButtonView(icon: activeIcon, state: .glass)
        circle.contentTintColor = theme.tabBarSelectedIconColor
        circle.action = { [weak self] _ in self?.onSearchDismissed?() }
        if isKeyboardVisible {
            circle.alpha = 0.0
        }
        addSubview(circle)
        searchTabCircle = circle
    }

    private func teardownSearchViews() {
        searchCapsule?.removeFromSuperview()
        searchTextField?.removeFromSuperview()
        searchCloseButton?.removeFromSuperview()
        searchTabCircle?.removeFromSuperview()
        searchDimView?.removeFromSuperview()
        searchCapsule = nil
        searchTextField = nil
        searchCloseButton = nil
        searchTabCircle = nil
        searchDimView = nil
    }

    private func activeTabIcon() -> UIImage? {
        guard selectedIndex < itemViews.count else { return nil }
        let item = items[selectedIndex]
        return item.selectedImage ?? item.image
    }

    // -- Positioning

    /// Reference frames in TabBarView coordinates.
    private var searchShowcaseFrame: CGRect {
        guard let showcase = searchShowcaseView else {
            return CGRect(x: bounds.width - theme.sideInset - theme.pillHeight,
                          y: bounds.height - effectiveBottomInset - theme.pillHeight,
                          width: theme.pillHeight, height: theme.pillHeight)
        }
        return tabBarGlassContainer.convert(showcase.frame, to: self)
    }

    private var activeTabFrame: CGRect {
        guard selectedIndex < itemViews.count else { return .zero }
        let itemFrame = itemViews[selectedIndex].frame
        return tabBarGlassContainer.convert(itemFrame, to: self)
    }

    private static let searchModeHeight: CGFloat = 42.0

    /// Start: capsule at showcase origin, circle at active tab origin.
    private func positionSearchViewsAtOrigin() {
        let h = Self.searchModeHeight
        let showcaseF = searchShowcaseFrame
        let tabF = activeTabFrame

        updateSearchDimFrame()

        // Capsule starts at search showcase's position (small circle)
        let capsuleFrame = CGRect(x: showcaseF.midX - h / 2, y: showcaseF.midY - h / 2, width: h, height: h)
        searchCapsule?.frame = capsuleFrame
        searchCapsule?.update(size: capsuleFrame.size, cornerRadius: h / 2, isDark: isEffectivelyDark,
                              tintColor: .init(kind: .panel), isInteractive: false, isVisible: true, transition: .immediate)

        // Text field hidden at capsule position
        searchTextField?.frame = CGRect(x: capsuleFrame.minX + 8, y: capsuleFrame.minY, width: max(0, capsuleFrame.width - 16), height: h)
        searchTextField?.alpha = 0.0

        // Close button hidden at capsule right edge
        searchCloseButton?.frame = CGRect(x: capsuleFrame.maxX - h, y: capsuleFrame.minY, width: h, height: h)
        searchCloseButton?.alpha = 0.0

        // Circle starts at active tab's position
        let circleFrame = CGRect(x: tabF.midX - h / 2, y: showcaseF.midY - h / 2, width: h, height: h)
        searchTabCircle?.frame = circleFrame
    }

    /// Vertical lift for the active-search row — sits a few points above
    /// the normal tab-bar center so the close button and field don't
    /// hug the bottom safe-area edge.
    private static let searchRowLift: CGFloat = 12.0

    /// End: capsule fills most of the width, circle at the left edge.
    /// Capsule width depends on whether the close button is visible — if
    /// it's hidden (field not editing yet) the capsule reclaims that
    /// trailing space so the placeholder isn't cramped.
    private func positionSearchViewsExpanded() {
        let h = Self.searchModeHeight
        let sideInset = theme.sideInset
        // `searchRowLift` only applies while the field is NOT editing —
        // once the keyboard is up, the field/row should sit flush with
        // the bottom insets so the keyboard itself (plus its safe-area
        // handling) determines vertical placement.
        let isEditing = searchTextField?.isFirstResponder ?? false
        let lift = isEditing ? 0 : Self.searchRowLift
        let pillY = bounds.height - effectiveBottomInset - h + (theme.pillHeight - h) / 2 - lift

        updateSearchDimFrame()

        // Circle visibility tracks the keyboard — while it's up, the
        // capsule reclaims the leading slot so the field has room to
        // breathe over a wider hit area.
        let circleHidden = isKeyboardVisible

        // Circle (active-tab icon) sits at the left. We keep its frame
        // pinned to the leading slot regardless of `circleHidden` so the
        // alpha cross-fade has a stable target — only the capsule starts
        // shifts to claim/release the slot.
        let circleFrame = CGRect(x: sideInset, y: pillY, width: h, height: h)
        searchTabCircle?.frame = circleFrame

        // Close button frame is always in its rightmost slot — only alpha
        // changes when editing begins / ends.
        let closeFrame = CGRect(x: bounds.width - sideInset - h, y: pillY, width: h, height: h)
        searchCloseButton?.frame = closeFrame

        let capsuleFrame = capsuleFrameExpanded(
            pillY: pillY,
            circleRight: circleFrame.maxX,
            closeMinX: closeFrame.minX,
            circleHidden: circleHidden
        )
        searchCapsule?.frame = capsuleFrame
        searchCapsule?.update(size: capsuleFrame.size, cornerRadius: h / 2, isDark: isEffectivelyDark,
                              tintColor: .init(kind: .panel), isInteractive: false, isVisible: true, transition: .immediate)

        // Text field inside capsule
        searchTextField?.frame = CGRect(x: capsuleFrame.minX + 8, y: pillY, width: max(0, capsuleFrame.width - 16), height: h)
        searchTextField?.alpha = 1.0
    }

    /// Capsule's target frame given the current close-button visibility.
    /// When close is hidden, the capsule stretches all the way to the
    /// sideInset; when visible, it stops 8pt before the close button.
    /// `circleHidden` controls the leading edge — when true (keyboard up,
    /// active-tab circle faded) the capsule claims the circle's slot.
    private func capsuleFrameExpanded(pillY: CGFloat, circleRight: CGFloat, closeMinX: CGFloat, circleHidden: Bool) -> CGRect {
        let h = Self.searchModeHeight
        let spacing: CGFloat = 8.0
        let capsuleX = circleHidden ? theme.sideInset : (circleRight + spacing)
        let closeHidden = (searchCloseButton?.alpha ?? 0) < 0.01
        let trailing: CGFloat = closeHidden
            ? (bounds.width - theme.sideInset)
            : closeMinX - spacing
        let capsuleWidth = max(0, trailing - capsuleX)
        return CGRect(x: capsuleX, y: pillY, width: capsuleWidth, height: h)
    }

    private func updateSearchDimFrame() {
        guard let dim = searchDimView else { return }
        // Extend 40pt below bounds to cover the gap above the keyboard corners
        let overflow: CGFloat = 40.0
        let extFrame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height + overflow)
        dim.frame = extFrame
        dim.clipsToBounds = false
        let fadeHeight: CGFloat = min(48.0, bounds.height * 0.4)
        dim.update(
            content: theme.edgeEffectTintColor ?? theme.tabBarBackgroundColor,
            blur: true,
            alpha: theme.edgeEffectAlpha,
            rect: CGRect(origin: .zero, size: extFrame.size),
            edge: .bottom,
            edgeSize: fadeHeight,
            blurRadiusAtEdge: theme.edgeEffectBlurRadiusAtEdge,
            blurRadiusAtFade: theme.edgeEffectBlurRadiusAtFade,
            transition: .immediate
        )
    }

    @objc private func searchTextDidChange() {
        onSearchTextChanged?(searchTextField?.text ?? "")
    }

    public var items: [AetherTabBarItem] = [] {
        didSet {
            rebuildItemViews()
        }
    }

    public var selectedIndex: Int = 0 {
        didSet {
            if selectedIndex != oldValue {
                updateSelection(animated: true)
            }
        }
    }

    public var tabSelected: ((Int) -> Void)?
    public var tabDoubleTapped: ((Int) -> Void)?
    public var tabLongPressed: ((Int, UIView, UIGestureRecognizer) -> Void)?
    public var tabSwipeAction: ((Int, TabBarItemSwipeDirection) -> Void)?
    public var itemHasDoubleTapAction: ((Int) -> Bool)?
    public var disabledPressed: (() -> Void)?

    private var interactionsEnabled: Bool = true
    private var lastTapIndex: Int?
    private var lastTapTimestamp: CFTimeInterval = 0.0

    /// Drag-to-select state. Mirrors `TabBarComponent.selectionGestureState`:
    /// the native iOS 26 interaction where the liquid lens follows the user's
    /// finger as they drag across tabs.
    private struct SelectionGestureState {
        var startIndex: Int
        var currentIndex: Int
        var currentX: CGFloat
        var itemWidth: CGFloat
    }
    private var selectionGestureState: SelectionGestureState?

    // MARK: - Init

    public init(theme: Theme = Theme()) {
        self.theme = theme
        self.backgroundView = NavigationBackgroundView(color: theme.tabBarBackgroundColor, enableBlur: theme.enableBlur)
        self.separatorView = UIView()
        self.tabBarGlassContainer = GlassBackgroundContainerView(spacing: 7.0)
        self.liquidLensView = LiquidLensView(kind: .externalContainer)

        super.init(frame: .zero)

        addSubview(backgroundView)
        separatorView.backgroundColor = theme.tabBarSeparatorColor
        addSubview(separatorView)

        // Bottom scroll-edge fade — placed under the floating tab pill so
        // scroll content dissolves as it approaches the pill edge (mirrors
        // EdgeEffect on TabBar).
        edgeEffectView.isUserInteractionEnabled = false
        insertSubview(edgeEffectView, aboveSubview: backgroundView)

        // Put the lens (and future search showcase) inside the shared container
        // so iOS 26's `UIGlassContainerEffect` can merge them when close.
        addSubview(tabBarGlassContainer)
        tabBarGlassContainer.contentView.addSubview(liquidLensView)

        let lensTap = UITapGestureRecognizer(target: self, action: #selector(lensTapped(_:)))
        lensTap.delegate = self
        liquidLensView.addGestureRecognizer(lensTap)

        // Drag-to-select: lens follows the finger. Matches the native iOS 26
        // TabBarController pan interaction.
        let lensPan = TabSelectionRecognizer(target: self, action: #selector(lensPanned(_:)))
        lensPan.delegate = self
        liquidLensView.addGestureRecognizer(lensPan)

        let lensLongPress = UILongPressGestureRecognizer(target: self, action: #selector(lensLongPressed(_:)))
        lensLongPress.delegate = self
        liquidLensView.addGestureRecognizer(lensLongPress)

        let lensSwipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(lensSwiped(_:)))
        lensSwipeLeft.direction = .left
        lensSwipeLeft.delegate = self
        liquidLensView.addGestureRecognizer(lensSwipeLeft)

        let lensSwipeRight = UISwipeGestureRecognizer(target: self, action: #selector(lensSwiped(_:)))
        lensSwipeRight.direction = .right
        lensSwipeRight.delegate = self
        liquidLensView.addGestureRecognizer(lensSwipeRight)

        // Tap target for the minimized state. Sits on the container itself
        // so it keeps receiving touches when the lens (which normally
        // owns tab interactions) is faded out for the collapsed circle.
        let collapsedTap = UITapGestureRecognizer(target: self, action: #selector(collapsedPillTapped(_:)))
        collapsedTap.delegate = self
        tabBarGlassContainer.addGestureRecognizer(collapsedTap)
        collapsedTapRecognizer = collapsedTap

        // Pre-iOS 26 elastic press feedback for the whole tab-bar glass
        // capsule. iOS 26+ gets the native UIGlassContainerEffect warp
        // (the container's own `isInteractive` hook).
        if #unavailable(iOS 26.0) {
            let elastic = GlassHighlightGestureRecognizer(target: nil, action: nil)
            elastic.touchEffectView = tabBarGlassContainer
            elastic.highlightContainerView = tabBarGlassContainer.contentView
            tabBarGlassContainer.addGestureRecognizer(elastic)
        }

        setGlassStyle(enabled: theme.enableBlur)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Theme

    public func updateTheme(_ theme: Theme) {
        self.theme = theme
        backgroundView.updateColor(color: theme.tabBarBackgroundColor, enableBlur: theme.enableBlur, transition: .immediate)
        separatorView.backgroundColor = theme.tabBarSeparatorColor
        setGlassStyle(enabled: theme.enableBlur)
        rebuildItemViews()
        updateSelection(animated: false)
    }

    // MARK: - Glass

    public func setGlassStyle(enabled: Bool) {
        if theme.style == .liquidGlass {
            glassBackgroundView?.removeFromSuperview()
            glassBackgroundView = nil
            backgroundView.alpha = 0.0
            separatorView.alpha = 0.0
            liquidLensView.isHidden = false
            return
        }

        liquidLensView.isHidden = true
        separatorView.alpha = 1.0
        if enabled {
            if glassBackgroundView == nil {
                let glass = GlassBackgroundView(style: .regular)
                insertSubview(glass, aboveSubview: backgroundView)
                self.glassBackgroundView = glass
                layoutGlassBackground()
            }
            backgroundView.alpha = 0.0
        } else {
            glassBackgroundView?.removeFromSuperview()
            glassBackgroundView = nil
            backgroundView.alpha = 1.0
        }
    }

    public func updateInteractionsEnabled(_ enabled: Bool, transition: ContainedViewLayoutTransition) {
        interactionsEnabled = enabled
        transition.updateAlpha(view: self, alpha: enabled ? 1.0 : 0.5)
    }

    public func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {
        backgroundView.updateBackgroundAlpha(alpha, transition: transition)
        transition.updateAlpha(view: separatorView, alpha: alpha)
        if let glassBackgroundView {
            transition.updateAlpha(view: glassBackgroundView, alpha: alpha)
        }
        transition.updateAlpha(view: liquidLensView, alpha: alpha)
    }

    // MARK: - Layout

    override public func layoutSubviews() {
        super.layoutSubviews()

        backgroundView.frame = bounds
        backgroundView.update(size: bounds.size, transition: .immediate)

        separatorView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: UIScreenPixel)

        // Scroll-edge frost: fade zone starts at the TOP of the tab bar
        // view (plus any accessory reservation) and ramps to solid below.
        // The top of the frost band is the boundary where scroll content
        // begins dissolving.
        //
        // When a screen installs a `bottomBarAccessory`, we extend the
        // frost band upward by `bottomAccessoryReservedHeight` so the
        // accessory pill (sitting just above our top edge) also rides on
        // the frost. That means the edge-effect view's frame reaches
        // beyond our own bounds — `clipsToBounds` stays false so the
        // overflow renders.
        if theme.style == .liquidGlass {
            edgeEffectView.isHidden = false
            // Edge-effect frost band:
            //   • Expanded — covers the full tab bar height plus any
            //     reserved space ABOVE our top edge for a `bottomBarAccessory`
            //     so accessory + pill + scroll fade dissolve as one band.
            //   • Minimized — collapses to a tight band starting just
            //     above the 48pt circle row. The accessory has reflowed
            //     INTO that row (between the two circles), so it doesn't
            //     need its own reservation above us anymore — the band
            //     only needs to mask scroll content as it approaches the
            //     mini chrome.
            //
            // The band is offset DOWN and grown by `bandShift` so the
            // solid edge spills past the tab bar's bottom (covering the
            // gap between bounds and home-indicator area) and the fade
            // zone starts a touch lower — kills the visible
            // "просвет" the user reported between the chrome and the
            // device bottom.
            let edgeFrame: CGRect
            let fadeHeight: CGFloat
            // Empirical bleed — top edge of band moves DOWN by `bandShift`,
            // bottom edge moves DOWN by `2 * bandShift`. Net effect: the
            // band shifts down AND grows, exactly matching the user's
            // ask of "опустить вниз + увеличить пропорционально высоту".
            let bandShift: CGFloat = 12.0
            if isMinimized {
                let pillSize = Self.minimizedButtonSize
                let pillTop = bounds.height - effectiveBottomInset - pillSize
                let extraTop: CGFloat = 12.0
                let edgeTop = max(0.0, pillTop - extraTop)
                edgeFrame = CGRect(
                    x: 0.0,
                    y: edgeTop + bandShift,
                    width: bounds.width,
                    height: bounds.height - edgeTop + bandShift
                )
                fadeHeight = min(36.0, edgeFrame.height * 0.45)
            } else {
                let reservedAbove = max(0, bottomAccessoryReservedHeight)
                edgeFrame = CGRect(
                    x: 0.0,
                    y: -reservedAbove + bandShift,
                    width: bounds.width,
                    height: bounds.height + reservedAbove + bandShift
                )
                fadeHeight = min(48.0, edgeFrame.height * 0.4)
            }
            edgeEffectView.frame = edgeFrame
            edgeEffectView.update(
                content: theme.edgeEffectTintColor ?? theme.tabBarBackgroundColor,
                blur: true,
                alpha: theme.edgeEffectAlpha,
                rect: CGRect(origin: .zero, size: edgeFrame.size),
                edge: .bottom,
                edgeSize: fadeHeight,
                blurRadiusAtEdge: theme.edgeEffectBlurRadiusAtEdge,
                blurRadiusAtFade: theme.edgeEffectBlurRadiusAtFade,
                transition: .immediate
            )
        } else {
            edgeEffectView.isHidden = true
        }

        layoutGlassBackground()
        layoutItemViews()

        if isSearchActive {
            positionSearchViewsExpanded()
        }
    }

    /// Effective dark flag — follows the system interface style in addition
    /// to the static theme flag. `theme.isDark` is often false even on a
    /// dark-mode device (the default theme doesn't carry that info), which
    /// caused the tab bar to render with a light tint on dark mode under
    /// `GlassBackgroundView.useCustomGlassImpl`.
    private var isEffectivelyDark: Bool {
        theme.isDark || traitCollection.userInterfaceStyle == .dark
    }

    private func layoutGlassBackground() {
        guard let glassBackgroundView else {
            return
        }
        glassBackgroundView.frame = bounds
        glassBackgroundView.update(
            size: bounds.size,
            cornerRadius: 0.0,
            isDark: isEffectivelyDark,
            tintColor: .init(kind: .panel),
            isInteractive: false,
            isVisible: true,
            transition: .immediate
        )
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            setNeedsLayout()
        }
    }

    private func layoutItemViews() {
        guard !itemViews.isEmpty else { return }

        let count = itemViews.count
        if theme.style == .liquidGlass {
            layoutLiquidGlassItems(count: count)
            return
        }

        liquidLensView.isHidden = true
        let itemWidth = bounds.width / CGFloat(count)
        let contentHeight: CGFloat = 49.0

        for (index, itemView) in itemViews.enumerated() {
            let x = CGFloat(index) * itemWidth
            itemView.frame = CGRect(x: x, y: 0, width: itemWidth, height: contentHeight)
        }
    }

    private func rebuildSearchShowcase() {
        searchShowcaseView?.removeFromSuperview()
        searchShowcaseView = nil

        guard let config = searchShowcase else {
            setNeedsLayout()
            return
        }

        let button = GlassBarButtonView(icon: config.icon, title: nil, state: .glass)
        button.contentTintColor = theme.tabBarIconColor
        button.action = { _ in config.action() }
        // Previously sat inside `tabBarGlassContainer.contentView` so
        // both the tab pill and the search circle could merge via the
        // shared `UIGlassContainerEffect` on iOS 26+. That merge made
        // the elastic press feedback affect both at once (sublayer
        // transform on the container ripples through everything
        // inside). Keeping the search as a direct subview of the
        // TabBarView scopes each press effect to its own element —
        // tapping the pill stretches only the pill, tapping search
        // stretches only search. Tradeoff: loses the iOS 26 glass
        // merge between pill and search circle.
        addSubview(button)
        searchShowcaseView = button
        setNeedsLayout()
    }

    private func layoutLiquidGlassItems(count: Int) {
        liquidLensView.isHidden = false

        // Single-use morph transition. When set (by `setMinimized`), every
        // inner frame and the glass cornerRadius update animate through it,
        // so the pill, lens, icon, and search circle morph together. After
        // this layout pass it's cleared, so subsequent layouts (rotation,
        // selection change) snap with `.immediate` instead of triggering a
        // stale animation.
        let activeTransition: ContainedViewLayoutTransition = pendingMinimizeTransition ?? .immediate
        pendingMinimizeTransition = nil

        let sideInset = theme.sideInset
        let innerPadding = theme.innerPadding
        let showcaseSpacing = theme.showcaseSpacing
        let bottomInset = effectiveBottomInset

        // Minimized layout: pill collapses to a 48×48 active-tab circle on
        // the leading edge, search showcase mirrors it on the trailing
        // edge, and the band between them is reserved for the
        // `bottomBarAccessory` (which the controller reflows there).
        if isMinimized {
            let pillSize = Self.minimizedButtonSize
            let pillY = bounds.height - bottomInset - pillSize
            let containerFrame = CGRect(x: sideInset, y: pillY, width: pillSize, height: pillSize)
            activeTransition.updateFrame(view: tabBarGlassContainer, frame: containerFrame)
            tabBarGlassContainer.update(size: containerFrame.size, isDark: isEffectivelyDark, transition: activeTransition)

            // Lens still fills the container so its stretchy press
            // feedback lines up with the circle. `isCollapsed: true`
            // drops the lens's resting tint layer — without this the
            // active-tab circle reads as a heavier glass than the
            // search showcase / accessory pill that sit beside it.
            activeTransition.updateFrame(view: liquidLensView, frame: CGRect(origin: .zero, size: containerFrame.size))
            liquidLensView.update(
                size: containerFrame.size,
                selectionOrigin: .zero,
                selectionSize: containerFrame.size,
                inset: 0.0,
                isDark: isEffectivelyDark,
                isLifted: false,
                isCollapsed: true,
                transition: activeTransition
            )

            // Active-tab icon centered inside the circle. 10pt inset
            // gives a 28×28 hit area for the SF symbol and visually
            // matches the expanded item icon's weight in 48pt chrome.
            if let icon = minimizedIconView {
                let iconInset: CGFloat = 10
                let iconFrame = CGRect(origin: .zero, size: containerFrame.size).insetBy(dx: iconInset, dy: iconInset)
                activeTransition.updateFrame(view: icon, frame: iconFrame)
            }

            // Tab item views ride along inside the lens; keep them at
            // their normal frames so re-expand finds them in place, but
            // they're invisible while the lens alpha is 0. No transition
            // needed — they're not visible during the morph.
            let itemHeight = theme.pillHeight
            let pillWidthForItems = max(0.0, bounds.width - sideInset * 2.0 - (searchShowcaseView != nil ? Self.minimizedButtonSize + showcaseSpacing : 0))
            let tabAreaWidth = pillWidthForItems - innerPadding * 2.0
            let itemWidth = max(1.0, tabAreaWidth / CGFloat(count))
            for (index, itemView) in itemViews.enumerated() {
                itemView.frame = CGRect(x: innerPadding + CGFloat(index) * itemWidth, y: 0.0, width: itemWidth, height: itemHeight)
                if index < selectedItemViews.count {
                    selectedItemViews[index].frame = itemView.frame
                }
            }

            // Search showcase shrunk to 48×48 on the trailing edge.
            if let showcase = searchShowcaseView {
                let showcaseFrame = CGRect(
                    x: bounds.width - sideInset - pillSize,
                    y: pillY,
                    width: pillSize,
                    height: pillSize
                )
                activeTransition.updateFrame(view: showcase, frame: showcaseFrame)
            }

            return
        }

        // Expanded layout — full pill + optional search circle next to it.
        let contentHeight = theme.pillHeight
        let availableWidth = max(0.0, bounds.width - sideInset * 2.0)

        // Search is a separate circle to the right of the pill (like Apple Music).
        // Both share the same glass container so they merge on iOS 26+.
        let showcaseSize: CGFloat = searchShowcaseView != nil ? contentHeight : 0.0
        let showcaseFootprint = showcaseSize > 0.0 ? showcaseSize + showcaseSpacing : 0.0

        // Pill fills remaining width after the search circle.
        let pillWidth = max(0.0, availableWidth - showcaseFootprint)
        let lensSize = CGSize(width: pillWidth, height: contentHeight)

        let pillX = sideInset
        let showcaseX = bounds.width - sideInset - showcaseSize
        let pillY = bounds.height - bottomInset - contentHeight

        // Glass container wraps only the pill now — the search circle
        // lives as a direct subview of the TabBarView so its elastic
        // press feedback can run independently (see `rebuildSearchShowcase`).
        let containerFrame = CGRect(x: pillX, y: pillY, width: pillWidth, height: contentHeight)
        activeTransition.updateFrame(view: tabBarGlassContainer, frame: containerFrame)
        tabBarGlassContainer.update(size: containerFrame.size, isDark: isEffectivelyDark, transition: activeTransition)

        // Reset minimized icon frame so when the bar morphs back to
        // minimized the icon doesn't briefly appear at full pill size.
        if let icon = minimizedIconView {
            let iconInset: CGFloat = 10
            let iconBox = CGRect(x: 0, y: 0, width: Self.minimizedButtonSize, height: Self.minimizedButtonSize).insetBy(dx: iconInset, dy: iconInset)
            activeTransition.updateFrame(view: icon, frame: iconBox)
        }

        // Lens covers just the pill (not the search circle).
        activeTransition.updateFrame(view: liquidLensView, frame: CGRect(origin: .zero, size: lensSize))

        // Search circle positioned in TabBarView coords (sibling of container).
        if let showcase = searchShowcaseView {
            activeTransition.updateFrame(view: showcase, frame: CGRect(x: showcaseX, y: pillY, width: showcaseSize, height: showcaseSize))
        }

        // Tab items fill the pill width with inner side padding.
        let tabAreaWidth = pillWidth - innerPadding * 2.0
        let itemWidth = max(1.0, tabAreaWidth / CGFloat(count))
        var selectionFrame = CGRect(x: 0.0, y: 0.0, width: max(56.0, itemWidth), height: lensSize.height)

        for (index, itemView) in itemViews.enumerated() {
            let itemFrame = CGRect(x: innerPadding + CGFloat(index) * itemWidth, y: 0.0, width: itemWidth, height: lensSize.height)
            itemView.frame = itemFrame
            if index < selectedItemViews.count {
                selectedItemViews[index].frame = itemFrame
            }
            if index == selectedIndex {
                selectionFrame = itemFrame.insetBy(dx: -4.0, dy: 0.0)
            }
        }

        // Drag-to-select: override the lens origin to follow the user's finger.
        // Clamped to the lens bounds so the lens can't leave the pill.
        if let drag = selectionGestureState {
            let maxOriginX = lensSize.width - selectionFrame.width
            let targetX = max(-4.0, min(maxOriginX, drag.currentX - 4.0))
            selectionFrame.origin.x = targetX
        }

        selectionFrame.origin.x = max(0.0, min(selectionFrame.origin.x, lensSize.width - selectionFrame.width))

        // iOS 26 native "liquid" lift: while the user is actively dragging
        // the lens, forward `isLifted = true` to the underlying
        // `_UILiquidLensView`. This triggers the system's liquid morph —
        // the selection capsule elevates/stretches out of the pill as the
        // finger moves, matching the Figma / iOS 26 reference.
        let isDraggingLens = selectionGestureState != nil
        let lensTransition: ContainedViewLayoutTransition
        if isDraggingLens {
            lensTransition = .animated(duration: 0.25, curve: .spring)
        } else if activeTransition.isAnimated {
            lensTransition = activeTransition
        } else {
            lensTransition = .animated(duration: 0.35, curve: .spring)
        }
        liquidLensView.update(
            size: lensSize,
            selectionOrigin: selectionFrame.origin,
            selectionSize: selectionFrame.size,
            inset: 4.0,
            isDark: isEffectivelyDark,
            isLifted: isDraggingLens,
            transition: lensTransition
        )
        // Lens already positioned at (0, 0, lensSize) inside the container.
    }

    // MARK: - Items

    private func rebuildItemViews() {
        itemViews.forEach { $0.removeFromSuperview() }
        selectedItemViews.forEach { $0.removeFromSuperview() }
        itemViews = []
        selectedItemViews = []

        for (index, item) in items.enumerated() {
            let itemView = TabBarItemView(item: item, theme: theme, selected: theme.style == .legacy && index == selectedIndex)
            itemView.tag = index

            let tap = UITapGestureRecognizer(target: self, action: #selector(itemTapped(_:)))
            tap.delegate = self
            itemView.addGestureRecognizer(tap)

            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(itemLongPressed(_:)))
            longPress.delegate = self
            itemView.addGestureRecognizer(longPress)

            let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(itemSwiped(_:)))
            swipeLeft.direction = .left
            swipeLeft.delegate = self
            itemView.addGestureRecognizer(swipeLeft)

            let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(itemSwiped(_:)))
            swipeRight.direction = .right
            swipeRight.delegate = self
            itemView.addGestureRecognizer(swipeRight)

            let selectedItemView = TabBarItemView(item: item, theme: theme, selected: true)
            selectedItemView.tag = index
            selectedItemView.isUserInteractionEnabled = false

            if theme.style == .liquidGlass {
                liquidLensView.contentView.addSubview(itemView)
                liquidLensView.selectedContentView.addSubview(selectedItemView)
            } else {
                addSubview(itemView)
            }
            itemViews.append(itemView)
            selectedItemViews.append(selectedItemView)
        }

        setNeedsLayout()
    }

    private func updateSelection(animated: Bool) {
        for (index, itemView) in itemViews.enumerated() {
            let isSelected = theme.style == .legacy && index == selectedIndex
            if animated {
                UIView.animate(withDuration: 0.2) {
                    itemView.isSelected = isSelected
                    if index < self.selectedItemViews.count {
                        self.selectedItemViews[index].isSelected = true
                    }
                }
            } else {
                itemView.isSelected = isSelected
                if index < selectedItemViews.count {
                    selectedItemViews[index].isSelected = true
                }
            }
        }
        // Refresh the collapsed-pill icon when the active tab changes —
        // the minimized circle shows whichever tab is currently selected.
        if let icon = minimizedIconView {
            let newImage = activeTabIcon()?.withRenderingMode(.alwaysTemplate)
            if animated, isMinimized {
                UIView.transition(with: icon, duration: 0.2, options: [.transitionCrossDissolve, .beginFromCurrentState]) {
                    icon.image = newImage
                    icon.tintColor = self.theme.tabBarSelectedIconColor
                }
            } else {
                icon.image = newImage
                icon.tintColor = theme.tabBarSelectedIconColor
            }
        }
        setNeedsLayout()
    }

    // MARK: - Actions

    private func activateItem(at index: Int) {
        guard index < items.count else { return }
        guard interactionsEnabled, items[index].isEnabled else {
            disabledPressed?()
            return
        }

        let timestamp = CACurrentMediaTime()
        let isDoubleTap = lastTapIndex == index && (timestamp - lastTapTimestamp) < 0.35
        lastTapIndex = index
        lastTapTimestamp = timestamp

        if isDoubleTap, itemHasDoubleTapAction?(index) == true {
            tabDoubleTapped?(index)
            return
        }

        selectedIndex = index
        tabSelected?(index)
    }

    private func index(at point: CGPoint) -> Int? {
        for (index, itemView) in itemViews.enumerated() {
            let frame = convert(itemView.bounds, from: itemView)
            if frame.contains(point) {
                return index
            }
        }
        return nil
    }

    @objc private func lensPanned(_ recognizer: TabSelectionRecognizer) {
        guard theme.style == .liquidGlass, !items.isEmpty else { return }

        switch recognizer.state {
        case .began:
            let location = recognizer.location(in: liquidLensView)
            guard let idx = indexInLens(x: location.x) else { return }
            let itemW = liquidLensView.bounds.width / CGFloat(max(1, items.count))
            selectionGestureState = SelectionGestureState(
                startIndex: idx,
                currentIndex: idx,
                currentX: CGFloat(idx) * itemW,
                itemWidth: itemW
            )
            setNeedsLayout()
            layoutIfNeeded()
        case .changed:
            guard var state = selectionGestureState else { return }
            let translation = recognizer.translation(in: liquidLensView).x
            state.currentX = CGFloat(state.startIndex) * state.itemWidth + translation
            let location = recognizer.location(in: liquidLensView)
            if let idx = indexInLens(x: location.x) {
                state.currentIndex = idx
            }
            selectionGestureState = state
            setNeedsLayout()
            layoutIfNeeded()
        case .ended:
            if let state = selectionGestureState, items.indices.contains(state.currentIndex) {
                let newIndex = state.currentIndex
                selectionGestureState = nil
                if newIndex != selectedIndex {
                    selectedIndex = newIndex
                    tabSelected?(newIndex)
                } else {
                    setNeedsLayout()
                    layoutIfNeeded()
                }
            } else {
                selectionGestureState = nil
                setNeedsLayout()
                layoutIfNeeded()
            }
        case .cancelled, .failed:
            selectionGestureState = nil
            setNeedsLayout()
            layoutIfNeeded()
        default:
            break
        }
    }

    private func indexInLens(x: CGFloat) -> Int? {
        guard !items.isEmpty else { return nil }
        let itemW = liquidLensView.bounds.width / CGFloat(items.count)
        let idx = Int((max(0.0, x) / max(1.0, itemW)).rounded(.down))
        return min(items.count - 1, max(0, idx))
    }

    @objc private func lensTapped(_ recognizer: UITapGestureRecognizer) {
        guard theme.style == .liquidGlass, recognizer.state == .ended else {
            return
        }
        // In minimized state the lens is the collapsed pill itself —
        // tapping it should expand the bar back, not try to pick a tab
        // (only one tab is visible there anyway).
        if isMinimized {
            onExpandRequested?()
            return
        }
        guard let index = index(at: recognizer.location(in: self)) else {
            return
        }
        activateItem(at: index)
    }

    @objc private func lensLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard theme.style == .liquidGlass, recognizer.state == .began else {
            return
        }
        guard let index = index(at: recognizer.location(in: self)) else {
            return
        }
        guard interactionsEnabled else {
            disabledPressed?()
            return
        }
        tabLongPressed?(index, itemViews[index], recognizer)
    }

    @objc private func lensSwiped(_ recognizer: UISwipeGestureRecognizer) {
        guard theme.style == .liquidGlass else {
            return
        }
        guard let index = index(at: recognizer.location(in: self)) else {
            return
        }
        guard interactionsEnabled else {
            disabledPressed?()
            return
        }
        let direction: TabBarItemSwipeDirection = recognizer.direction == .left ? .left : .right
        tabSwipeAction?(index, direction)
    }

    @objc private func itemTapped(_ recognizer: UITapGestureRecognizer) {
        guard let itemView = recognizer.view else { return }
        let index = itemView.tag
        activateItem(at: index)
    }

    @objc private func itemLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let itemView = recognizer.view else { return }
        guard interactionsEnabled else {
            disabledPressed?()
            return
        }
        tabLongPressed?(itemView.tag, itemView, recognizer)
    }

    @objc private func itemSwiped(_ recognizer: UISwipeGestureRecognizer) {
        guard let itemView = recognizer.view else {
            return
        }
        guard interactionsEnabled else {
            disabledPressed?()
            return
        }
        let direction: TabBarItemSwipeDirection = recognizer.direction == .left ? .left : .right
        tabSwipeAction?(itemView.tag, direction)
    }

    // MARK: - Public

    public func frameForTab(at index: Int) -> CGRect? {
        guard index < itemViews.count else { return nil }
        return convert(itemViews[index].bounds, from: itemViews[index])
    }

    /// Frame of the pill (selection capsule) in this view's coordinate
    /// space. Consumers — e.g. a floating toolbar that wants to sit just
    /// above the pill — should read this rather than hardcoding the
    /// pill's theme constants, otherwise they'll drift whenever the theme
    /// changes `pillHeight` / `bottomInset`.
    public var pillFrame: CGRect {
        if theme.style == .liquidGlass {
            return tabBarGlassContainer.frame
        }
        // Legacy style: items span the full width near the top. Use the
        // item row as the "pill" for anchoring purposes.
        if let first = itemViews.first, let last = itemViews.last {
            return first.frame.union(last.frame)
        }
        return .zero
    }

    /// Height the controller should reserve for the tab bar above the bottom
    /// safe area. Includes pill (62pt) + bottom gap + top edge-effect zone.
    public class var defaultHeight: CGFloat {
        return 103.0
    }
}

// MARK: - TabBarItemView

private final class TabBarItemView: UIView {
    private let imageView: UIImageView
    private let textLabel: UILabel
    private let badgeView: NavigationBarBadgeView
    private var item: AetherTabBarItem
    private var theme: TabBarView.Theme

    var isSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    init(item: AetherTabBarItem, theme: TabBarView.Theme, selected: Bool) {
        self.item = item
        self.theme = theme
        self.isSelected = selected
        self.imageView = UIImageView()
        self.textLabel = UILabel()
        self.badgeView = NavigationBarBadgeView()

        super.init(frame: .zero)

        imageView.contentMode = .center
        addSubview(imageView)

        textLabel.font = UIFont.systemFont(ofSize: 11.0, weight: .medium)
        textLabel.textAlignment = .center
        addSubview(textLabel)

        addSubview(badgeView)
        if let badge = item.badgeValue, !badge.isEmpty {
            badgeView.text = badge
        }

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        imageView.image = (isSelected ? item.selectedImage : item.image)?.withRenderingMode(.alwaysTemplate)
        imageView.tintColor = isSelected ? theme.tabBarSelectedIconColor : theme.tabBarIconColor

        textLabel.text = item.title
        textLabel.textColor = isSelected ? theme.tabBarSelectedTextColor : theme.tabBarTextColor
        textLabel.font = UIFont.systemFont(ofSize: 10.0, weight: isSelected ? .bold : .medium)

        badgeView.badgeColor = theme.tabBarBadgeBackgroundColor
        badgeView.textColor = theme.tabBarBadgeTextColor
        badgeView.strokeColor = theme.tabBarBadgeStrokeColor
        badgeView.isHidden = item.badgeValue?.isEmpty ?? true
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Figma spec: 8pt inset on all sides of the item's content (icon +
        // label). With a 60pt-tall pill that leaves 44pt of vertical content,
        // which fits the 30pt icon + 1pt gap + 13pt label exactly.
        let contentInset: CGFloat = 8.0
        let imageSize: CGFloat = 36.0
        let textFontSize: CGFloat = 10.0
        textLabel.font = UIFont.systemFont(ofSize: textFontSize, weight: isSelected ? .bold : .medium)
        let textHeight: CGFloat = ceil(textFontSize * 1.25)

        let totalHeight = imageSize + textHeight
        // Vertical content is pinned between the 8pt top and 8pt bottom insets.
        let availableHeight = max(totalHeight, bounds.height - contentInset * 2.0)
        let topY = contentInset + floor((availableHeight - totalHeight) / 2.0)

        imageView.frame = CGRect(
            x: (bounds.width - imageSize) / 2.0,
            y: 6,
            width: imageSize,
            height: imageSize
        )
        // Label gets 8pt horizontal inset so long titles respect the padding
        // rather than bleeding to the pill edge.
        textLabel.frame = CGRect(
            x: contentInset,
            y: 38,
            width: max(0.0, bounds.width - contentInset * 2.0),
            height: 12
        )

        let badgeSize = badgeView.sizeThatFits(CGSize(width: 40, height: 20))
        badgeView.frame = CGRect(
            x: bounds.width / 2.0 + 8.0,
            y: topY - 2.0,
            width: badgeSize.width,
            height: badgeSize.height
        )
    }
}

// MARK: - Gesture recognizer delegate

extension TabBarView: UIGestureRecognizerDelegate {
    /// Gesture arbitration policy:
    ///   - Two tab-bar recognisers (both attached to views inside this
    ///     view): **default compete**. Tap and long-press in particular
    ///     must NOT fire simultaneously — a held press that opens the
    ///     context menu must not ALSO emit a tap on finger-up, which
    ///     would round-trip through `tabSelected` and trigger
    ///     pop-to-root / scroll-to-top on the active tab.
    ///   - One of the recognisers is external (parent scroll, system
    ///     edge-swipe back, etc.): **simultaneous**. The tab bar
    ///     shouldn't steal touches from the surrounding hierarchy.
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let ourFirst = gestureRecognizer.view?.isDescendant(of: self) ?? false
        let ourSecond = otherGestureRecognizer.view?.isDescendant(of: self) ?? false
        if ourFirst && ourSecond {
            return false
        }
        return true
    }
}

// MARK: - Search text field delegate

extension TabBarView: UITextFieldDelegate {
    public func textFieldDidBeginEditing(_ textField: UITextField) {
        guard textField === searchTextField, let close = searchCloseButton else { return }
        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0.2, options: [.beginFromCurrentState]) {
            close.alpha = 1.0
            close.transform = .identity
            // Re-layout so the capsule shrinks away from the close pill.
            self.positionSearchViewsExpanded()
        }
    }

    public func textFieldDidEndEditing(_ textField: UITextField) {
        guard textField === searchTextField, let close = searchCloseButton else { return }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            close.alpha = 0.0
            // Capsule stretches back to the trailing edge.
            self.positionSearchViewsExpanded()
        }
    }
}
