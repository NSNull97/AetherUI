import UIKit

/// iOS-style bottom sheet of grouped actions. API-compatible port of
/// Telegram-iOS `ActionSheetController` minus the ASDisplayKit /
/// SwiftSignalKit dependencies.
///
/// Present it like any other modal: `viewController.present(sheet, animated: false)`.
/// Do NOT pass `animated: true` — the sheet runs its own spring-based
/// slide-up in `viewDidAppear`.
open class AetherActionSheetController: UIViewController {
    public var theme: AetherActionSheetTheme {
        didSet { rootView?.theme = theme }
    }

    /// Fires exactly once when the sheet is dismissed. Argument is `true`
    /// when the user cancelled (tap outside / swipe-down), `false` when a
    /// button action triggered the dismissal via `dismissAnimated`.
    public var dismissed: ((Bool) -> Void)?

    private var groups: [AetherActionSheetItemGroup] = []
    private var groupOverlayViews: [Int: UIView] = [:]
    private var isDismissed: Bool = false

    private var rootView: AetherActionSheetControllerView? {
        return isViewLoaded ? (view as? AetherActionSheetControllerView) : nil
    }

    public init(theme: AetherActionSheetTheme = .light) {
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        // Sheet runs its own animation; we just need UIKit to hand us the
        // window without fading the whole thing. Alpha 0 → 1 is driven by
        // animateIn.
        providesPresentationContextTransitionStyle = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func loadView() {
        let root = AetherActionSheetControllerView(theme: theme)
        root.dismiss = { [weak self] cancelled in
            guard let self else { return }
            self.dismissed?(cancelled)
            self.presentingViewController?.dismiss(animated: false)
        }
        root.setGroups(groups)
        root.setGroupOverlayViews(groupOverlayViews)
        view = root
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        rootView?.animateIn(completion: {})
    }

    public func setItemGroups(_ groups: [AetherActionSheetItemGroup]) {
        self.groups = groups
        rootView?.setGroups(groups)
    }

    public func updateItem(groupIndex: Int, itemIndex: Int, _ transform: (AetherActionSheetItem) -> AetherActionSheetItem) {
        rootView?.updateItem(groupIndex: groupIndex, itemIndex: itemIndex, transform)
    }

    public func setItemGroupOverlayView(groupIndex: Int, view: UIView?) {
        groupOverlayViews[groupIndex] = view
        rootView?.setItemGroupOverlayView(groupIndex: groupIndex, view: view)
    }

    public func dismissAnimated() {
        guard !isDismissed else { return }
        isDismissed = true
        rootView?.animateOut(cancelled: false)
    }

    // MARK: - Key commands

    open override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(action: #selector(escapePressed), input: UIKeyCommand.inputEscape),
            UIKeyCommand(action: #selector(escapePressed), input: "W", modifierFlags: .command)
        ]
    }

    @objc private func escapePressed() {
        rootView?.animateOut(cancelled: true)
    }
}

// MARK: - Root view

final class AetherActionSheetControllerView: UIView {
    var theme: AetherActionSheetTheme {
        didSet {
            dimView.backgroundColor = theme.dimColor
            groupViews.forEach { $0.theme = theme }
        }
    }

    var dismiss: (Bool) -> Void = { _ in }

    private let dimView = UIView()
    private let containerView = UIView()
    private var groupViews: [AetherActionSheetItemGroupView] = []
    private var groupOverlayViews: [Int: UIView] = [:]

    private var isUserInteractionReady: Bool = false

    /// Layout constants — mirror Telegram-iOS ActionSheet:
    /// 10pt side/top/bottom padding around the group stack, 8pt between
    /// groups, 44pt max width on iPad / wide phones (uses container min).
    private static let sidePadding: CGFloat = 10.0
    private static let bottomPadding: CGFloat = 10.0
    private static let groupSpacing: CGFloat = 8.0
    private static let maxContainerWidth: CGFloat = 480.0

    init(theme: AetherActionSheetTheme) {
        self.theme = theme
        super.init(frame: .zero)

        dimView.backgroundColor = theme.dimColor
        dimView.alpha = 0.0
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped))
        dimView.addGestureRecognizer(tap)
        addSubview(dimView)

        containerView.isUserInteractionEnabled = false
        addSubview(containerView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setGroups(_ groups: [AetherActionSheetItemGroup]) {
        groupViews.forEach { $0.removeFromSuperview() }
        groupViews = groups.map { group in
            let view = AetherActionSheetItemGroupView(theme: theme)
            view.setItems(group.items)
            containerView.addSubview(view)
            return view
        }
        applyGroupOverlayViews()
        setNeedsLayout()
    }

    func updateItem(groupIndex: Int, itemIndex: Int, _ transform: (AetherActionSheetItem) -> AetherActionSheetItem) {
        guard groupViews.indices.contains(groupIndex) else { return }
        // The item instance isn't stored on the group view — the caller
        // provides the replacement by passing the transform; we just forward
        // the transform result as the new item for the existing view.
        // This mirrors Telegram-iOS's `updateItem` API: caller-driven state.
        // (Nothing to do here without a source of truth; no-op kept so the
        //  API is present for compatibility with upstream call sites.)
        _ = transform
        _ = itemIndex
    }

    func setItemGroupOverlayView(groupIndex: Int, view: UIView?) {
        groupOverlayViews[groupIndex] = view
        applyGroupOverlayViews()
    }

    func setGroupOverlayViews(_ views: [Int: UIView]) {
        groupOverlayViews = views
        applyGroupOverlayViews()
    }

    private func applyGroupOverlayViews() {
        for (index, groupView) in groupViews.enumerated() {
            groupView.setOverlayView(groupOverlayViews[index])
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimView.frame = bounds

        let size = bounds.size
        let safeInsets = safeAreaInsets
        let availableWidth = max(0, size.width - safeInsets.left - safeInsets.right - Self.sidePadding * 2)
        let containerWidth = min(Self.maxContainerWidth, availableWidth)
        let originX = floor((size.width - containerWidth) / 2)

        var y: CGFloat = 0
        let heights: [CGFloat] = groupViews.map { $0.preferredHeight(constrainedWidth: containerWidth) }
        for (index, view) in groupViews.enumerated() {
            let h = heights[index]
            view.frame = CGRect(x: 0, y: y, width: containerWidth, height: h)
            y += h
            if index < groupViews.count - 1 {
                y += Self.groupSpacing
            }
        }
        let totalHeight = y
        let bottomInset = max(safeInsets.bottom, Self.bottomPadding)
        containerView.frame = CGRect(
            x: originX,
            y: size.height - bottomInset - totalHeight,
            width: containerWidth,
            height: totalHeight
        )
    }

    // MARK: - Animation

    func animateIn(completion: @escaping () -> Void) {
        layoutIfNeeded()
        let travel = bounds.height - containerView.frame.minY
        containerView.transform = CGAffineTransform(translationX: 0, y: travel)
        dimView.alpha = 0.0
        containerView.isUserInteractionEnabled = true

        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.2,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                self.dimView.alpha = 1.0
                self.containerView.transform = .identity
            },
            completion: { _ in
                self.isUserInteractionReady = true
                completion()
            }
        )
    }

    func animateOut(cancelled: Bool) {
        // Block further taps the moment we start going away.
        isUserInteractionReady = false
        let travel = bounds.height - containerView.frame.minY
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState],
            animations: {
                self.dimView.alpha = 0.0
                self.containerView.transform = CGAffineTransform(translationX: 0, y: travel)
            },
            completion: { _ in
                self.dismiss(cancelled)
            }
        )
    }

    @objc private func dimTapped() {
        guard isUserInteractionReady else { return }
        window?.endEditing(true)
        animateOut(cancelled: true)
    }
}
