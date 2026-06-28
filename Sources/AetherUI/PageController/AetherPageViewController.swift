import UIKit

private final class PageScrollView: UIScrollView {
    var shouldBeginPagePan: ((UIPanGestureRecognizer) -> Bool)?

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer,
           let panGestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer,
           let shouldBeginPagePan {
            return shouldBeginPagePan(panGestureRecognizer)
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

/// A Telegram-style horizontal page controller with a glass segmented pager.
///
/// The controller owns a paging `UIScrollView` for page content and exposes
/// `viewPager` as a reusable `NavigationBarContentView`. By default the pager
/// is installed as `topBarAccessory`, but callers can opt out and place it
/// manually.
open class AetherPageViewController: AetherViewController, UIScrollViewDelegate {
    public struct Page {
        public let title: String
        public let viewController: UIViewController

        public init(title: String, viewController: UIViewController) {
            self.title = title
            self.viewController = viewController
        }

        public init(viewController: UIViewController, title: String? = nil) {
            self.viewController = viewController
            self.title = title
                ?? (viewController as? AetherViewController)?.pageItem.title
                ?? viewController.title
                ?? ""
        }
    }

    public final class PagerView: NavigationBarContentView {
        public typealias Theme = AetherSegmentedControl.Theme

        public let segmentedControl: AetherSegmentedControl

        public var contentInsets: UIEdgeInsets {
            didSet {
                invalidateIntrinsicContentSize()
                invalidateLayout(transition: .immediate)
            }
        }

        public var maximumContentWidth: CGFloat? {
            didSet {
                setNeedsLayout()
                invalidateLayout(transition: .immediate)
            }
        }

        public var selectedIndexChanged: (Int) -> Void {
            get { segmentedControl.selectedIndexChanged }
            set { segmentedControl.selectedIndexChanged = newValue }
        }

        public var selectedIndexShouldChange: (Int, @escaping (Bool) -> Void) -> Void {
            get { segmentedControl.selectedIndexShouldChange }
            set { segmentedControl.selectedIndexShouldChange = newValue }
        }

        public var selectedIndex: Int {
            return segmentedControl.selectedIndex
        }

        public var preferredHeight: CGFloat {
            get { segmentedControl.preferredHeight }
            set {
                guard segmentedControl.preferredHeight != newValue else {
                    return
                }
                segmentedControl.preferredHeight = newValue
                invalidateIntrinsicContentSize()
                invalidateLayout(transition: .immediate)
            }
        }

        public override var mode: NavigationBarContentMode {
            return .expansion
        }

        public override var nominalHeight: CGFloat {
            return contentInsets.top + segmentedControl.preferredHeight + contentInsets.bottom
        }

        public override var height: CGFloat {
            return nominalHeight
        }

        public override var intrinsicContentSize: CGSize {
            let controlSize = segmentedControl.intrinsicContentSize
            return CGSize(
                width: controlSize.width + contentInsets.left + contentInsets.right,
                height: nominalHeight
            )
        }

        public init(
            items: [AetherSegmentedControl.Item],
            selectedIndex: Int,
            theme: AetherSegmentedControl.Theme = .system,
            contentInsets: UIEdgeInsets = .zero,
            maximumContentWidth: CGFloat? = nil
        ) {
            self.segmentedControl = AetherSegmentedControl(
                theme: theme,
                items: items,
                selectedIndex: selectedIndex,
                cornerRadius: nil
            )
            self.contentInsets = contentInsets
            self.maximumContentWidth = maximumContentWidth

            super.init(frame: .zero)

            clipsToBounds = false
            segmentedControl.preferredHeight = 36.0
            addSubview(segmentedControl)
        }

        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public func setItems(_ items: [AetherSegmentedControl.Item], selectedIndex: Int, animated: Bool) {
            segmentedControl.items = items
            setSelectedIndex(selectedIndex, animated: animated)
            invalidateIntrinsicContentSize()
            invalidateLayout(transition: animated ? .animated(duration: 0.3, curve: .spring) : .immediate)
        }

        public func setSelectedIndex(_ index: Int, animated: Bool) {
            segmentedControl.setSelectedIndex(index, animated: animated)
        }

        internal func setSelectedIndex(_ index: Int, animated: Bool, updatesSelectionProgress: Bool) {
            segmentedControl.setSelectedIndex(index, animated: animated, updatesSelectionProgress: updatesSelectionProgress)
        }

        internal func setSelectionProgress(_ progress: CGFloat, animated: Bool) {
            segmentedControl.setSelectionProgress(progress, animated: animated)
        }

        public func updateTheme(_ theme: Theme) {
            segmentedControl.updateTheme(theme)
        }

        public override func updateLayout(
            size: CGSize,
            leftInset: CGFloat,
            rightInset: CGFloat,
            transition: ContainedViewLayoutTransition
        ) -> CGSize {
            let horizontalInset = contentInsets.left + contentInsets.right
            let sideInset = max(leftInset, rightInset)
            let availableWidth = max(0.0, size.width - sideInset * 2.0 - horizontalInset)
            let controlWidth: CGFloat
            if let maximumContentWidth {
                controlWidth = min(availableWidth, max(0.0, maximumContentWidth))
            } else {
                controlWidth = availableWidth
            }
            let verticalInset = contentInsets.top + contentInsets.bottom
            let controlHeight = max(0.0, size.height - verticalInset)
            let controlX = sideInset + contentInsets.left + floor((availableWidth - controlWidth) / 2.0)
            let controlFrame = CGRect(
                x: controlX,
                y: contentInsets.top,
                width: controlWidth,
                height: controlHeight
            )
            transition.updateFrame(view: segmentedControl, frame: controlFrame)
            return CGSize(width: size.width, height: nominalHeight)
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            let _ = updateLayout(
                size: bounds.size,
                leftInset: 0.0,
                rightInset: 0.0,
                transition: .immediate
            )
        }
    }

    public let pages: [Page]
    public let viewPager: PagerView
    public var viewPagerAccessory: PagerView { viewPager }
    public let scrollView: UIScrollView

    public private(set) var selectedIndex: Int

    public var selectedIndexChanged: (Int) -> Void = { _ in }
    public var selectedIndexShouldChange: (Int, @escaping (Bool) -> Void) -> Void = { _, commit in
        commit(true)
    }
    public var scrollingProgressChanged: (CGFloat) -> Void = { _ in }

    private var isApplyingProgrammaticScroll = false
    private var pendingValidatedScrollIndex: Int?

    private static let topBarAccessoryPagerContentInsets = UIEdgeInsets(
        top: 0.0,
        left: 16.0,
        bottom: 0.0,
        right: 16.0
    )

    public init(
        pages: [Page],
        selectedIndex: Int = 0,
        installViewPagerAsTopBarAccessory: Bool = true,
        navigationBarPresentationData: NavigationBarPresentationData? = nil
    ) {
        self.pages = pages
        let clampedSelectedIndex = Self.clampedIndex(selectedIndex, pageCount: pages.count)
        self.selectedIndex = clampedSelectedIndex
        self.scrollView = PageScrollView(frame: .zero)
        self.viewPager = PagerView(
            items: Self.segmentedItems(for: pages),
            selectedIndex: clampedSelectedIndex,
            contentInsets: installViewPagerAsTopBarAccessory ? Self.topBarAccessoryPagerContentInsets : .zero
        )

        super.init(navigationBarPresentationData: navigationBarPresentationData)

        configureEmbeddedPageControllers()

        if installViewPagerAsTopBarAccessory {
            topBarAccessory = viewPager
        }

        configurePagerSelectionHandling()
        configurePageScrollGestureHandling()
        configurePageItems()
    }

    public init<Index: RawRepresentable>(
        pages: [Page],
        selectedIndex: Index,
        installViewPagerAsTopBarAccessory: Bool = true,
        navigationBarPresentationData: NavigationBarPresentationData? = nil
    ) where Index.RawValue == Int {
        self.pages = pages
        let clampedSelectedIndex = Self.clampedIndex(selectedIndex.rawValue, pageCount: pages.count)
        self.selectedIndex = clampedSelectedIndex
        self.scrollView = PageScrollView(frame: .zero)
        self.viewPager = PagerView(
            items: Self.segmentedItems(for: pages),
            selectedIndex: clampedSelectedIndex,
            contentInsets: installViewPagerAsTopBarAccessory ? Self.topBarAccessoryPagerContentInsets : .zero
        )

        super.init(navigationBarPresentationData: navigationBarPresentationData)

        configureEmbeddedPageControllers()

        if installViewPagerAsTopBarAccessory {
            topBarAccessory = viewPager
        }

        configurePagerSelectionHandling()
        configurePageScrollGestureHandling()
        configurePageItems()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func segmentedItems(for pages: [Page]) -> [AetherSegmentedControl.Item] {
        pages.map { page in
            let pageItem = (page.viewController as? AetherViewController)?.pageItem
            return AetherSegmentedControl.Item(
                title: pageItem?.title ?? page.title,
                badgeValue: pageItem?.badgeValue
            )
        }
    }

    open override var interactiveNavivationGestureEdgeWidth: InteractiveTransitionGestureRecognizerEdgeWidth? {
        isAtFirstPageForInteractivePop ? .widthMultiplier(factor: 1.0, min: 0.0, max: .greatestFiniteMagnitude) : .constant(0.0)
    }

    private func configurePagerSelectionHandling() {
        viewPager.selectedIndexShouldChange = { [weak self] index, commit in
            guard let self else {
                commit(false)
                return
            }
            guard index != self.selectedIndex else {
                commit(false)
                return
            }
            self.selectedIndexShouldChange(index, commit)
        }
        viewPager.selectedIndexChanged = { [weak self] index in
            self?.setSelectedIndex(index, animated: true)
        }
        scrollToTop = { [weak self] in
            self?.scrollToTopSelectedPage()
        }
    }

    private func configurePageScrollGestureHandling() {
        guard let pageScrollView = scrollView as? PageScrollView else {
            return
        }
        pageScrollView.shouldBeginPagePan = { [weak self] panGestureRecognizer in
            self?.shouldBeginPagePan(panGestureRecognizer) ?? true
        }
    }

    private func configurePageItems() {
        for (index, page) in pages.enumerated() {
            guard let controller = page.viewController as? AetherViewController else {
                continue
            }
            let pageItem = controller.pageItem
            pageItem.contentDidChange = { [weak self] in
                self?.updatePagerItems(animated: false)
            }
            pageItem.selectionRequested = { [weak self] animated in
                self?.setSelectedIndex(index, animated: animated)
            }
        }
        updatePageItemSelectionState()
    }

    private func configureEmbeddedPageControllers() {
        for page in pages {
            configureEmbeddedPageController(page.viewController)
        }
    }

    private func configureEmbeddedPageController(_ controller: UIViewController) {
        guard let controller = controller as? AetherViewController else {
            return
        }

        controller.navigationBarIsExternallyHosted = true
        controller.externalNavigationBarHeight = 0.0

        if controller.isViewLoaded,
           let bar = controller.navigationBarView,
           bar.superview === controller.view {
            bar.removeFromSuperview()
        }
    }

    private func updatePagerItems(animated: Bool) {
        viewPager.setItems(Self.segmentedItems(for: pages), selectedIndex: selectedIndex, animated: animated)
    }

    private func updatePageItemSelectionState() {
        for (index, page) in pages.enumerated() {
            (page.viewController as? AetherViewController)?.pageItem.setIsSelected(index == selectedIndex)
        }
    }

    private var isAtFirstPageForInteractivePop: Bool {
        guard selectedIndex == 0 else {
            return false
        }
        guard isViewLoaded, scrollView.bounds.width > 0.0 else {
            return true
        }
        return scrollView.contentOffset.x <= 0.5
    }

    private func shouldBeginPagePan(_ panGestureRecognizer: UIPanGestureRecognizer) -> Bool {
        shouldBeginPagePan(for: panGestureRecognizer.velocity(in: scrollView))
    }

    internal func shouldBeginPagePan(for velocity: CGPoint) -> Bool {
        guard abs(velocity.x) > abs(velocity.y), velocity.x > 0.0 else {
            return true
        }
        return !isAtFirstPageForInteractivePop
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = pages.count > 1
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = pages.count > 1
        scrollView.isDirectionalLockEnabled = true
        scrollView.delegate = self
        scrollView.scrollsToTop = false
        scrollView.backgroundColor = .clear
        if #available(iOS 11.0, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        }

        view.insertSubview(scrollView, at: 0)

        for page in pages {
            let controller = page.viewController
            configureEmbeddedPageController(controller)
            addChild(controller)
            scrollView.addSubview(controller.view)
            controller.didMove(toParent: self)
        }
    }

    open override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        guard isViewLoaded else {
            return
        }

        updatePageLayout(layout: layout, transition: transition)
    }

    open func setSelectedIndex(_ index: Int, animated: Bool) {
        let clampedIndex = Self.clampedIndex(index, pageCount: pages.count)
        guard pages.indices.contains(clampedIndex) else {
            return
        }
        guard clampedIndex != selectedIndex else {
            return
        }

        selectedIndex = clampedIndex
        let drivesPagerFromScroll = animated && isViewLoaded && scrollView.bounds.width > 0.0
        viewPager.setSelectedIndex(
            clampedIndex,
            animated: animated && !drivesPagerFromScroll,
            updatesSelectionProgress: !drivesPagerFromScroll
        )
        scrollToPage(at: clampedIndex, animated: animated)
        updatePageItemSelectionState()
        selectedIndexChanged(clampedIndex)
        pageIndexDidChange(clampedIndex)
    }

    open func setSelectedIndex<Index: RawRepresentable>(_ index: Index, animated: Bool) where Index.RawValue == Int {
        setSelectedIndex(index.rawValue, animated: animated)
    }

    open func pageIndexDidChange(_ index: Int) {
    }

    public func page(at index: Int) -> Page? {
        guard pages.indices.contains(index) else {
            return nil
        }
        return pages[index]
    }

    public var selectedPage: Page? {
        return page(at: selectedIndex)
    }

    public func viewController(at index: Int) -> UIViewController? {
        return page(at: index)?.viewController
    }

    // MARK: - UIScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let width = scrollView.bounds.width
        guard width > 0.0, !pages.isEmpty else {
            return
        }
        let rawProgress = scrollView.contentOffset.x / width
        let maxProgress = CGFloat(max(0, pages.count - 1))
        let progress = max(0.0, min(maxProgress, rawProgress))
        viewPager.setSelectionProgress(progress, animated: false)
        scrollingProgressChanged(progress)
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isApplyingProgrammaticScroll = false
        pendingValidatedScrollIndex = nil
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            commitSelectionFromCurrentScrollPosition()
        }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        commitSelectionFromCurrentScrollPosition()
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isApplyingProgrammaticScroll = false
        alignScrollOffsetToSelectedPageIfNeeded()
        viewPager.setSelectionProgress(CGFloat(selectedIndex), animated: false)
    }

    // MARK: - Private

    private static func clampedIndex(_ index: Int, pageCount: Int) -> Int {
        guard pageCount > 0 else {
            return 0
        }
        return max(0, min(pageCount - 1, index))
    }

    private func updatePageLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let size = layout.size
        transition.updateFrame(view: scrollView, frame: CGRect(origin: .zero, size: size))

        let pageCount = pages.count
        let contentWidth = size.width * CGFloat(max(1, pageCount))
        scrollView.contentSize = CGSize(width: contentWidth, height: size.height)
        scrollView.alwaysBounceHorizontal = pageCount > 1
        scrollView.bounces = pageCount > 1

        for (index, page) in pages.enumerated() {
            let pageFrame = CGRect(
                x: size.width * CGFloat(index),
                y: 0.0,
                width: size.width,
                height: size.height
            )
            transition.updateFrame(view: page.viewController.view, frame: pageFrame)

            if let controller = page.viewController as? AetherViewController {
                configureEmbeddedPageController(controller)
                controller.containerLayoutUpdated(layout.withUpdatedSize(pageFrame.size), transition: transition)
            }
        }

        alignScrollOffsetToSelectedPageIfNeeded()
    }

    private func scrollToPage(at index: Int, animated: Bool) {
        guard isViewLoaded, scrollView.bounds.width > 0.0 else {
            return
        }
        let offset = CGPoint(x: scrollView.bounds.width * CGFloat(index), y: 0.0)
        if scrollView.contentOffset == offset {
            if !animated {
                isApplyingProgrammaticScroll = false
            }
            return
        }

        isApplyingProgrammaticScroll = animated
        scrollView.setContentOffset(offset, animated: animated)
        if !animated {
            isApplyingProgrammaticScroll = false
        }
    }

    private func alignScrollOffsetToSelectedPageIfNeeded() {
        guard isViewLoaded, !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating, scrollView.bounds.width > 0.0 else {
            return
        }
        let offset = CGPoint(x: scrollView.bounds.width * CGFloat(selectedIndex), y: 0.0)
        if scrollView.contentOffset != offset {
            scrollView.setContentOffset(offset, animated: false)
        }
    }

    private func commitSelectionFromCurrentScrollPosition() {
        guard !isApplyingProgrammaticScroll, scrollView.bounds.width > 0.0 else {
            return
        }

        let targetIndex = Self.clampedIndex(
            Int(round(scrollView.contentOffset.x / scrollView.bounds.width)),
            pageCount: pages.count
        )
        guard targetIndex != selectedIndex else {
            return
        }

        pendingValidatedScrollIndex = targetIndex
        selectedIndexShouldChange(targetIndex) { [weak self] commit in
            guard let self else {
                return
            }
            guard self.pendingValidatedScrollIndex == targetIndex else {
                return
            }
            self.pendingValidatedScrollIndex = nil

            if commit {
                self.selectedIndex = targetIndex
                self.viewPager.setSelectionProgress(CGFloat(targetIndex), animated: false)
                self.viewPager.setSelectedIndex(targetIndex, animated: false, updatesSelectionProgress: false)
                self.updatePageItemSelectionState()
                self.selectedIndexChanged(targetIndex)
                self.pageIndexDidChange(targetIndex)
            } else {
                self.viewPager.setSelectedIndex(self.selectedIndex, animated: false)
                self.scrollToPage(at: self.selectedIndex, animated: false)
            }
        }
    }

    private func scrollToTopSelectedPage() {
        guard let selectedController = viewController(at: selectedIndex) else {
            return
        }

        if let aetherController = selectedController as? AetherViewController, let scrollToTop = aetherController.scrollToTop {
            scrollToTop()
            return
        }

        if let scrollView = findPrimaryScrollView(in: selectedController.view) {
            let topOffset = CGPoint(
                x: scrollView.contentOffset.x,
                y: -scrollView.adjustedContentInset.top
            )
            scrollView.setContentOffset(topOffset, animated: true)
        }
    }

    private func findPrimaryScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = findPrimaryScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }
}

public typealias AetherViewPager = AetherPageViewController.PagerView
