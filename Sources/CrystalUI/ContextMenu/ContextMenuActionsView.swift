import UIKit

// MARK: - ContextMenuActionsView

/// Glass-backed list container for `ContextMenuItem`s. Owns a single
/// "highlight pill" that slides between rows as the user drags their finger
/// across the menu — matching the iOS 26 native behaviour where the selection
/// rectangle smoothly tracks the touch instead of snapping per-row.
///
/// Touch handling:
///   - Touch-down on a row → highlight appears at that row (spring fade-in).
///   - Touch-move to another row → highlight slides to its new position.
///   - Touch-up on an enabled action row → that row's action is invoked,
///     then the menu auto-dismisses via the action callback.
///   - Touch-up outside any row OR over a header / separator → highlight
///     fades out, no action fires, no dismissal.
final class ContextMenuActionsView: UIView {
    // MARK: - Metrics

    static let cornerRadius: CGFloat = 27.0
    static let preferredWidth: CGFloat = 260.0
    static let headerHeight: CGFloat = 32.0
    static let separatorHeight: CGFloat = 8.0
    static let highlightHorizontalInset: CGFloat = 0.0
    static let highlightCornerRadius: CGFloat = 20.0
    static let backRowHeight: CGFloat = 44.0
    /// Inset applied to the content area inside the menu's glass surface.
    /// Rows + headers + separators all live inside `bounds.inset(by:)` of
    /// this. Each row's own `horizontalInset` is then set to 0 so the
    /// 16pt outer padding isn't doubled.
    static let contentInset: UIEdgeInsets = .init(top: 16, left: 16, bottom: 16, right: 16)

    // MARK: - Subviews

    /// `contentContainer` clips rows + highlight to a rounded shape that
    /// matches the menu's outer cornerRadius. The glass surface is owned by
    /// the outer `ContextMenuController.menuContainer` (UIVisualEffectView
    /// with UIGlassEffect / UIBlurEffect) — this view is just rows on
    /// transparent background.
    private let contentContainer = UIView()
    /// Glass selection pill (like the tab bar's `LiquidLensView`). Sits
    /// on top of the rows and slides between them via spring animation.
    /// On iOS 26+ uses native UIGlassEffect (so it visibly refracts the
    /// content underneath); falls back to a tinted backdrop blur otherwise.
    private let highlightView: GlassBackgroundView
    private var rowViews: [RowEntry] = []

    // MARK: - State

    /// How the optional header-row at the top of the page renders.
    ///   - `.none`: no header row (root menu).
    ///   - `.back(title)`: leading `chevron.left` + title — used by push/pop
    ///     submenu pages, fires `onHeaderTapped` to pop.
    ///   - `.disclosure(title)`: leading `chevron.down` + title — used by
    ///     inline-expand submenu cards (Yandex Music style), fires
    ///     `onHeaderTapped` to collapse the card.
    enum HeaderStyle {
        case none
        case back(title: String)
        case disclosure(title: String)
    }

    private let items: [ContextMenuItem]
    private let headerStyle: HeaderStyle
    var onActionSelected: ((ContextMenuActionItem) -> Void)?
    var onSubmenuRequested: ((ContextMenuActionItem) -> Void)?
    var onHeaderTapped: (() -> Void)?

    private var trackedTouch: UITouch?
    private var highlightedIndex: Int?

    /// Hooks the controller can use to apply the rubber-band stretch on the
    /// outer container (the whole menu chrome, not just the rows). Reporting
    /// the touch in the actionsView's own coords; the controller is
    /// responsible for converting / applying the transform on its own host.
    var onStretchUpdate: ((CGPoint) -> Void)?
    var onStretchRelease: (() -> Void)?

    // MARK: - Row taxonomy

    private struct RowEntry {
        let view: UIView
        /// Concrete action item if this row is tappable. Headers / separators
        /// have nil; the header row has nil too (special-cased via `isHeaderRow`).
        let actionItem: ContextMenuActionItem?
        let isHeaderRow: Bool

        init(view: UIView, actionItem: ContextMenuActionItem?, isHeaderRow: Bool = false) {
            self.view = view
            self.actionItem = actionItem
            self.isHeaderRow = isHeaderRow
        }
    }

    // MARK: - Init

    init(items: [ContextMenuItem], headerStyle: HeaderStyle = .none) {
        self.items = items
        self.headerStyle = headerStyle
        self.highlightView = GlassBackgroundView(style: .regular)

        super.init(frame: .zero)

        backgroundColor = .clear

        contentContainer.clipsToBounds = false
        addSubview(contentContainer)

        highlightView.layer.cornerRadius = ContextMenuActionsView.highlightCornerRadius
        if #available(iOS 13.0, *) {
            highlightView.layer.cornerCurve = .continuous
        }
        highlightView.alpha = 0
        highlightView.isUserInteractionEnabled = false
        contentContainer.addSubview(highlightView)

        buildRowViews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Public

    /// Intrinsic size for a given width — sums the heights of the items
    /// (plus the header row when one is configured) and adds the
    /// `contentInset` top + bottom.
    func preferredSize(maxWidth: CGFloat) -> CGSize {
        let width = min(maxWidth, ContextMenuActionsView.preferredWidth)
        let inset = ContextMenuActionsView.contentInset
        var height: CGFloat = inset.top + inset.bottom
        if hasHeader { height += ContextMenuActionsView.backRowHeight }
        for item in items {
            height += heightForItem(item)
        }
        return CGSize(width: width, height: height)
    }

    private var hasHeader: Bool {
        if case .none = headerStyle { return false }
        return true
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        // contentContainer is inset by 16pt on all sides. Rows live inside
        // and are positioned in contentContainer-local coords starting at
        // (0, 0). Each row's internal slots already use 0 horizontal inset
        // (the outer 16pt is enough), so text/icons sit visually 16pt
        // from the menu's glass edge.
        contentContainer.frame = bounds.inset(by: ContextMenuActionsView.contentInset)

        let contentWidth = contentContainer.bounds.width
        var y: CGFloat = 0.0
        let itemsStart = hasHeader ? 1 : 0
        if itemsStart > 0 {
            rowViews[0].view.frame = CGRect(
                x: 0, y: y, width: contentWidth,
                height: ContextMenuActionsView.backRowHeight
            )
            y += ContextMenuActionsView.backRowHeight
        }
        for (index, item) in items.enumerated() {
            let h = heightForItem(item)
            rowViews[itemsStart + index].view.frame = CGRect(x: 0, y: y, width: contentWidth, height: h)
            y += h
        }

        // Reposition the highlight if it's currently anchored on a row.
        if let highlightedIndex {
            let frame = highlightFrame(forRowAt: highlightedIndex)
            highlightView.frame = frame
            highlightView.update(
                size: frame.size,
                cornerRadius: ContextMenuActionsView.highlightCornerRadius,
                isDark: traitCollection.userInterfaceStyle == .dark,
                tintColor: .init(kind: .panel),
                isInteractive: false,
                isVisible: true,
                transition: .immediate
            )
        }
    }

    // MARK: - Touch tracking

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackedTouch == nil, let touch = touches.first else { return }
        trackedTouch = touch
        let point = touch.location(in: self)
        onStretchUpdate?(point)
        moveHighlight(to: point, animated: false)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracked = trackedTouch, touches.contains(tracked) else { return }
        let point = tracked.location(in: self)
        onStretchUpdate?(point)
        moveHighlight(to: point, animated: true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tracked = trackedTouch, touches.contains(tracked) else { return }
        trackedTouch = nil
        onStretchRelease?()
        commitTouch(at: tracked.location(in: self))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let tracked = trackedTouch, touches.contains(tracked) {
            trackedTouch = nil
        }
        onStretchRelease?()
        clearHighlight(animated: true)
    }

    // MARK: - Highlight tracking

    private func moveHighlight(to point: CGPoint, animated: Bool) {
        guard let index = enabledRowIndex(at: point) else {
            clearHighlight(animated: animated)
            return
        }

        let targetFrame = highlightFrame(forRowAt: index)
        let isFirstShow = (highlightView.alpha < 0.01)

        highlightedIndex = index

        let isDark = traitCollection.userInterfaceStyle == .dark

        if isFirstShow {
            // First show: jump to position with no slide, only fade in.
            highlightView.frame = targetFrame
            highlightView.update(
                size: targetFrame.size,
                cornerRadius: ContextMenuActionsView.highlightCornerRadius,
                isDark: isDark,
                tintColor: .init(kind: .panel),
                isInteractive: false,
                isVisible: true,
                transition: .immediate
            )
            UIView.animate(
                withDuration: 0.15, delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: { self.highlightView.alpha = 1.0 },
                completion: nil
            )
            return
        }

        // Subsequent moves: slide via spring (matches the tab bar's lens
        // motion). `glassBackground.update(...)` is also given the same
        // animated transition so its internal sizing tracks the spring.
        if animated {
            let glassTransition: ContainedViewLayoutTransition = .animated(
                duration: 0.32,
                curve: .customSpring(damping: 0.85, initialVelocity: 0)
            )
            UIView.animate(
                withDuration: 0.32, delay: 0,
                usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: { self.highlightView.frame = targetFrame },
                completion: nil
            )
            highlightView.update(
                size: targetFrame.size,
                cornerRadius: ContextMenuActionsView.highlightCornerRadius,
                isDark: isDark,
                tintColor: .init(kind: .panel),
                isInteractive: false,
                isVisible: true,
                transition: glassTransition
            )
        } else {
            highlightView.frame = targetFrame
            highlightView.update(
                size: targetFrame.size,
                cornerRadius: ContextMenuActionsView.highlightCornerRadius,
                isDark: isDark,
                tintColor: .init(kind: .panel),
                isInteractive: false,
                isVisible: true,
                transition: .immediate
            )
        }
    }

    private func clearHighlight(animated: Bool) {
        highlightedIndex = nil
        if animated {
            UIView.animate(
                withDuration: 0.18, delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: { self.highlightView.alpha = 0.0 },
                completion: nil
            )
        } else {
            highlightView.alpha = 0.0
        }
    }

    private func commitTouch(at point: CGPoint) {
        guard let index = enabledRowIndex(at: point) else {
            clearHighlight(animated: true)
            return
        }
        let entry = rowViews[index]
        if entry.isHeaderRow {
            onHeaderTapped?()
            return
        }
        guard let actionItem = entry.actionItem else {
            clearHighlight(animated: true)
            return
        }
        if actionItem.submenu != nil {
            onSubmenuRequested?(actionItem)
        } else {
            // Action invoked synchronously; the highlight stays visible until
            // the menu dismiss animation removes the view.
            onActionSelected?(actionItem)
        }
    }

    /// Returns the index of the enabled tappable row (action OR header row)
    /// whose frame contains `point`. `point` is in actions-view bounds; rows
    /// live inside the inset contentContainer so we offset by its origin
    /// before hit-testing. Headers / separators / disabled rows return nil.
    private func enabledRowIndex(at point: CGPoint) -> Int? {
        let pointInContent = convertToContentContainer(point)
        for (index, entry) in rowViews.enumerated() {
            guard entry.view.frame.contains(pointInContent) else { continue }
            if entry.isHeaderRow { return index }
            guard let actionItem = entry.actionItem, actionItem.isEnabled else { return nil }
            return index
        }
        return nil
    }

    private func convertToContentContainer(_ point: CGPoint) -> CGPoint {
        return CGPoint(
            x: point.x - contentContainer.frame.minX,
            y: point.y - contentContainer.frame.minY
        )
    }

    private func highlightFrame(forRowAt index: Int) -> CGRect {
        let rowFrame = rowViews[index].view.frame
        return rowFrame.insetBy(
            dx: ContextMenuActionsView.highlightHorizontalInset,
            dy: 2.0
        )
    }

    // MARK: - Internals

    private func heightForItem(_ item: ContextMenuItem) -> CGFloat {
        switch item {
        case .header:
            return ContextMenuActionsView.headerHeight
        case let .action(action):
            return ContextMenuActionItemView.rowHeight(for: action)
        case .separator:
            return ContextMenuActionsView.separatorHeight
        }
    }

    private func buildRowViews() {
        switch headerStyle {
        case .none:
            break
        case let .back(title):
            let row = makeHeaderRow(title: title, chevronSymbol: "chevron.left")
            contentContainer.addSubview(row)
            rowViews.append(RowEntry(view: row, actionItem: nil, isHeaderRow: true))
        case let .disclosure(title):
            let row = makeHeaderRow(title: title, chevronSymbol: "chevron.down")
            contentContainer.addSubview(row)
            rowViews.append(RowEntry(view: row, actionItem: nil, isHeaderRow: true))
        }
        for item in items {
            switch item {
            case let .header(title):
                let label = UILabel()
                label.text = title.uppercased()
                label.font = .systemFont(ofSize: 12.0, weight: .semibold)
                label.textColor = .secondaryLabel
                let container = UIView()
                container.isUserInteractionEnabled = false
                container.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: ContextMenuActionItemView.horizontalInset),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -ContextMenuActionItemView.horizontalInset),
                    label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6.0)
                ])
                contentContainer.addSubview(container)
                rowViews.append(RowEntry(view: container, actionItem: nil))
            case let .action(action):
                let row = ContextMenuActionItemView(item: action)
                contentContainer.addSubview(row)
                rowViews.append(RowEntry(view: row, actionItem: action))
            case .separator:
                let container = UIView()
                container.isUserInteractionEnabled = false
                let line = UIView()
                line.backgroundColor = UIColor.separator.withAlphaComponent(0.6)
                container.addSubview(line)
                line.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: ContextMenuActionItemView.horizontalInset),
                    line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -ContextMenuActionItemView.horizontalInset),
                    line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                    line.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
                ])
                contentContainer.addSubview(container)
                rowViews.append(RowEntry(view: container, actionItem: nil))
            }
        }
        // Keep the highlight on top of rows so it visually sits above content.
        contentContainer.bringSubviewToFront(highlightView)
    }

    /// Header row used at the top of pushed submenu pages (chevron.left)
    /// or inline-expand submenu cards (chevron.down). Renders the parent
    /// submenu's title in semibold so the row reads as a header.
    private func makeHeaderRow(title: String, chevronSymbol: String) -> UIView {
        let container = UIView()
        container.isUserInteractionEnabled = false

        let chevron = UIImageView()
        chevron.contentMode = .scaleAspectFit
        chevron.tintColor = .label
        if #available(iOS 13.0, *) {
            let config = UIImage.SymbolConfiguration(pointSize: 14.0, weight: .semibold)
            chevron.image = UIImage(systemName: chevronSymbol, withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
        }
        container.addSubview(chevron)

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 17.0, weight: .semibold)
        label.textColor = .label
        container.addSubview(label)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            chevron.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: ContextMenuActionItemView.horizontalInset),
            chevron.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 14.0),
            chevron.heightAnchor.constraint(equalToConstant: 18.0),
            label.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 10.0),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -ContextMenuActionItemView.horizontalInset),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }
}
