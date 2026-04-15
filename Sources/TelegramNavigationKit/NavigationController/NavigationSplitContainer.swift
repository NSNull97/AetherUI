import UIKit

/// Scroll-to-top target for split container.
enum NavigationSplitContainerScrollToTop {
    case master
    case detail
}

/// Split view container for iPad-style master-detail navigation.
/// Replaces Telegram's ASDK-based NavigationSplitContainer.
final class NavigationSplitContainer: UIView {
    private var theme: NavigationControllerTheme

    private let masterScrollToTopView: ScrollToTopView
    private let detailScrollToTopView: ScrollToTopView
    let masterContainer: NavigationContainer
    let detailContainer: NavigationContainer
    private let separator: UIView

    private(set) var masterControllers: [ViewController] = []
    private(set) var detailControllers: [ViewController] = []

    var isInFocus: Bool = false {
        didSet {
            if isInFocus != oldValue {
                masterContainer.topController?.isInFocus = isInFocus
                detailContainer.topController?.isInFocus = isInFocus
            }
        }
    }

    init(theme: NavigationControllerTheme, controllerRemoved: @escaping (ViewController) -> Void, scrollToTop: @escaping (NavigationSplitContainerScrollToTop) -> Void) {
        self.theme = theme

        self.masterScrollToTopView = ScrollToTopView(frame: .zero)
        self.masterScrollToTopView.action = { scrollToTop(.master) }

        self.detailScrollToTopView = ScrollToTopView(frame: .zero)
        self.detailScrollToTopView.action = { scrollToTop(.detail) }

        self.masterContainer = NavigationContainer(frame: .zero)
        self.masterContainer.clipsToBounds = true
        self.masterContainer.controllerRemoved = controllerRemoved

        self.detailContainer = NavigationContainer(frame: .zero)
        self.detailContainer.clipsToBounds = true
        self.detailContainer.controllerRemoved = controllerRemoved

        self.separator = UIView()
        self.separator.backgroundColor = theme.navigationBar.separatorColor

        super.init(frame: .zero)

        addSubview(masterContainer)
        addSubview(detailContainer)
        addSubview(separator)
        addSubview(masterScrollToTopView)
        addSubview(detailScrollToTopView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateTheme(theme: NavigationControllerTheme) {
        self.theme = theme
        separator.backgroundColor = theme.navigationBar.separatorColor
    }

    func update(layout: ContainerViewLayout, masterControllers: [ViewController], detailControllers: [ViewController], transition: ContainedViewLayoutTransition) {
        let masterWidth = min(max(320.0, floor(layout.size.width / 3.0)), floor(layout.size.width / 2.0))
        let detailWidth = layout.size.width - masterWidth

        masterScrollToTopView.frame = CGRect(x: 0, y: -1, width: masterWidth, height: 1)
        detailScrollToTopView.frame = CGRect(x: masterWidth, y: -1, width: detailWidth, height: 1)

        transition.updateFrame(view: masterContainer, frame: CGRect(x: 0, y: 0, width: masterWidth, height: layout.size.height))
        transition.updateFrame(view: detailContainer, frame: CGRect(x: masterWidth, y: 0, width: detailWidth, height: layout.size.height))
        transition.updateFrame(view: separator, frame: CGRect(x: masterWidth, y: 0, width: UIScreenPixel, height: layout.size.height))

        let masterLayout = ContainerViewLayout(
            size: CGSize(width: masterWidth, height: layout.size.height),
            metrics: layout.metrics,
            safeInsets: layout.safeInsets,
            additionalInsets: .zero,
            statusBarHeight: layout.statusBarHeight,
            inputHeight: layout.inputHeight,
            inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging,
            inVoiceOver: layout.inVoiceOver
        )
        masterContainer.setControllers(masterControllers, animated: transition.isAnimated)
        masterContainer.containerLayoutUpdated(masterLayout, transition: transition)

        let detailLayout = ContainerViewLayout(
            size: CGSize(width: detailWidth, height: layout.size.height),
            metrics: layout.metrics,
            safeInsets: layout.safeInsets,
            additionalInsets: layout.additionalInsets,
            statusBarHeight: layout.statusBarHeight,
            inputHeight: layout.inputHeight,
            inputHeightIsInteractivellyChanging: layout.inputHeightIsInteractivellyChanging,
            inVoiceOver: layout.inVoiceOver
        )
        detailContainer.setControllers(detailControllers, animated: transition.isAnimated)
        detailContainer.containerLayoutUpdated(detailLayout, transition: transition)

        self.masterControllers = masterControllers
        self.detailControllers = detailControllers
    }

    func combinedSupportedOrientations(currentOrientationToLock: UIInterfaceOrientationMask) -> ViewControllerSupportedOrientations {
        var result = ViewControllerSupportedOrientations()
        result = result.intersection(masterContainer.combinedSupportedOrientations(currentOrientationToLock: currentOrientationToLock))
        result = result.intersection(detailContainer.combinedSupportedOrientations(currentOrientationToLock: currentOrientationToLock))
        return result
    }
}
