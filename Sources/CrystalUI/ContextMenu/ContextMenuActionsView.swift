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
    /// Glass selection lens — the same `LiquidLensView` the tab bar uses
    /// for its sliding selected indicator. `.noContainer` so only the
    /// lens "blob" itself renders (no surrounding GlassBackgroundContainer
    /// strip — the menu's outer UIVisualEffectView already provides the
    /// background). Covers the whole content area and positions its visible
    /// lens at the selected row via `update(selectionOrigin:selectionSize:...)`.
    /// Rendered BELOW the row views so text + icons stay readable on top.
    private let highlightLens = LiquidLensView(kind: .noContainer)
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

        super.init(frame: .zero)

        backgroundColor = .clear

        contentContainer.clipsToBounds = false
        addSubview(contentContainer)

        // Lens sits BENEATH the rows so text + icons stay readable on top
        // of the lens glass. Its alpha controls visibility (0 = hidden,
        // 1 = visible at the highlighted row).
        highlightLens.alpha = 0
        highlightLens.isUserInteractionEnabled = false
        contentContainer.addSubview(highlightLens)

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

        // Lens covers the whole content area so its `selectionOrigin` /
        // `selectionSize` can address any row. Update happens immediately
        // here; `moveHighlight` re-runs `update(...)` with an animated
        // transition when the user changes which row is highlighted.
        highlightLens.frame = contentContainer.bounds
        if let highlightedIndex {
            let frame = highlightFrame(forRowAt: highlightedIndex)
            highlightLens.update(
                size: contentContainer.bounds.size,
                cornerRadius: ContextMenuActionsView.highlightCornerRadius,
                selectionOrigin: frame.origin,
                selectionSize: frame.size,
                inset: 0,
                isDark: traitCollection.userInterfaceStyle == .dark,
                isLifted: true,
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
        // Pick the nearest enabled row — this is what makes the drag
        // track smoothly across separators / headers BETWEEN sections
        // instead of clearing whenever the finger crosses a non-action
        // row. If the point is far outside the menu we keep the
        // highlight pinned to the last valid row (don't clear) so
        // dragging outside doesn't jitter the highlight off; the user
        // can drag back in and land on a row cleanly.
        if let index = nearestEnabledRowIndex(at: point) {
            applyHighlight(to: index, animated: animated)
            return
        }
        // Far outside the menu — preserve whatever highlight was last
        // shown. Only cancel/touchesEnded will actually clear it.
        if highlightedIndex == nil {
            clearHighlight(animated: animated)
        }
    }

    private func applyHighlight(to index: Int, animated: Bool) {
        let targetFrame = highlightFrame(forRowAt: index)
        let isFirstShow = (highlightLens.alpha < 0.01)

        highlightedIndex = index

        let isDark = traitCollection.userInterfaceStyle == .dark
        let lensTransition: ContainedViewLayoutTransition = (animated && !isFirstShow)
            ? .animated(duration: 0.32, curve: .customSpring(damping: 0.85, initialVelocity: 0))
            : .immediate

        // Lens covers the whole content area; `selectionOrigin/Size` move
        // the visible lens to the highlighted row. The lens animates
        // internally via its own update transition (matches the tab bar's
        // lens motion).
        highlightLens.frame = contentContainer.bounds
        highlightLens.update(
            size: contentContainer.bounds.size,
            cornerRadius: ContextMenuActionsView.highlightCornerRadius,
            selectionOrigin: targetFrame.origin,
            selectionSize: targetFrame.size,
            inset: 0,
            isDark: isDark,
            isLifted: true,
            transition: lensTransition
        )

        if isFirstShow {
            UIView.animate(
                withDuration: 0.15, delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: { self.highlightLens.alpha = 1.0 },
                completion: nil
            )
        }
    }

    private func clearHighlight(animated: Bool) {
        highlightedIndex = nil
        if animated {
            UIView.animate(
                withDuration: 0.18, delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: { self.highlightLens.alpha = 0.0 },
                completion: nil
            )
        } else {
            highlightLens.alpha = 0.0
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

    /// Returns the index of the enabled tappable row (action OR header
    /// row) whose frame contains `point`. Direct hit only — used by
    /// `commitTouch` to decide whether a touch-up lands on an
    /// actionable row.
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

    /// Nearest enabled row for highlight purposes during a drag. Unlike
    /// `enabledRowIndex` this one:
    ///   - returns the closest tappable row when the finger is over a
    ///     separator / section header / disabled item (so the highlight
    ///     tracks smoothly across section boundaries instead of clearing)
    ///   - returns `nil` only when the finger is genuinely far from the
    ///     menu (beyond a generous slack band) — we use that to mean
    ///     "don't touch the highlight", and the caller preserves whatever
    ///     row was last highlighted.
    private func nearestEnabledRowIndex(at point: CGPoint) -> Int? {
        let pointInContent = convertToContentContainer(point)

        // Direct hit on a tappable row short-circuits the nearest-search.
        for (index, entry) in rowViews.enumerated() {
            guard entry.view.frame.contains(pointInContent) else { continue }
            if entry.isHeaderRow { return index }
            if let actionItem = entry.actionItem, actionItem.isEnabled {
                return index
            }
            // Direct hit on a disabled / separator / header-label row —
            // fall through to nearest-search so the highlight jumps to
            // the nearest tappable row.
            break
        }

        // Slack band: accept points up to 40pt horizontally outside the
        // content area so a lazy drag that clips the menu edge still
        // tracks. Vertically unbounded — we clamp to the row band below
        // via the nearest-search, so finger-above-menu pins to the top
        // row, finger-below pins to the bottom.
        let horizontalSlack: CGFloat = 40
        let xMin = contentContainer.bounds.minX - horizontalSlack
        let xMax = contentContainer.bounds.maxX + horizontalSlack
        guard pointInContent.x >= xMin, pointInContent.x <= xMax else {
            return nil
        }

        // Nearest tappable row by vertical distance to its midY.
        var nearestIndex: Int? = nil
        var nearestDistance: CGFloat = .infinity
        for (index, entry) in rowViews.enumerated() {
            let isTappable = entry.isHeaderRow || (entry.actionItem?.isEnabled == true)
            guard isTappable else { continue }
            let rowMidY = entry.view.frame.midY
            let distance = abs(pointInContent.y - rowMidY)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestIndex = index
            }
        }
        return nearestIndex
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
        // Keep the lens UNDER the rows — text + icons need to read on top.
        contentContainer.sendSubviewToBack(highlightLens)
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
