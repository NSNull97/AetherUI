import UIKit
import SnapKit

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
    /// Height of an `.actionRow` strip. Delegated to the cell view's
    /// own metric so cell height and row height never drift apart.
    static let actionRowHeight: CGFloat = ContextMenuActionRowCellView.cellHeight
    /// Horizontal inset applied to the separator hairline inside its
    /// row container. Deliberately narrower than
    /// `ContextMenuActionItemView.horizontalInset` (8pt) so the divider
    /// extends a touch wider than the text column — the line sits
    /// 16 (outer) + 4 (this) = 20pt from the glass edge, whereas text
    /// sits at 24pt. Creates the classic "divider bracketing the
    /// content" look.
    static let separatorHorizontalInset: CGFloat = 4.0
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
    /// Native context menus use a quiet grey row selection here, not a
    /// second glass lens. This pill still tracks between rows with the same
    /// touch logic, but it does not refract or distort menu content.
    private let highlightView = UIView()
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
    private let reservesLeadingSlotForActionRows: Bool
    var onActionSelected: ((ContextMenuActionItem) -> Void)?
    var onSubmenuRequested: ((ContextMenuActionItem) -> Void)?
    var onHeaderTapped: (() -> Void)?

    private var trackedTouch: UITouch?
    private var highlightedIndex: Int?
    private var rowRevealProgress: CGFloat = 1.0

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
        /// Whether this entry is a cell inside a horizontal `.actionRow`
        /// strip. Affects touch-tracking (cells in the same strip share
        /// a midY so the nearest-row search has to tie-break by X) and
        /// highlight pill sizing (smaller corner radius / tighter insets
        /// than full-width rows).
        let isActionRowCell: Bool

        init(
            view: UIView,
            actionItem: ContextMenuActionItem?,
            isHeaderRow: Bool = false,
            isActionRowCell: Bool = false
        ) {
            self.view = view
            self.actionItem = actionItem
            self.isHeaderRow = isHeaderRow
            self.isActionRowCell = isActionRowCell
        }
    }

    // MARK: - Init

    init(items: [ContextMenuItem], headerStyle: HeaderStyle = .none) {
        self.items = items
        self.headerStyle = headerStyle
        self.reservesLeadingSlotForActionRows = Self.itemsNeedLeadingSlot(items)

        super.init(frame: .zero)

        backgroundColor = .clear

        contentContainer.clipsToBounds = false
        addSubview(contentContainer)

        // Highlight sits BENEATH the rows so text + icons stay readable on
        // top. Its alpha controls visibility (0 = hidden, 1 = visible at the
        // highlighted row).
        highlightView.alpha = 0
        highlightView.isUserInteractionEnabled = false
        highlightView.backgroundColor = Self.selectionHighlightColor(for: traitCollection)
        highlightView.layer.cornerCurve = .continuous
        highlightView.layer.masksToBounds = true
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
        var entryIdx = itemsStart
        for item in items {
            let h = heightForItem(item)
            switch item {
            case let .actionRow(cells) where !cells.isEmpty:
                // Horizontal strip: divide contentWidth equally across
                // all cells. Cells touch edge-to-edge; visual separation
                // comes from the rounded highlight pill when selected.
                let cellWidth = contentWidth / CGFloat(cells.count)
                var cellX: CGFloat = 0
                for _ in cells {
                    rowViews[entryIdx].view.frame = CGRect(
                        x: cellX, y: y, width: cellWidth, height: h
                    )
                    entryIdx += 1
                    cellX += cellWidth
                }
            default:
                rowViews[entryIdx].view.frame = CGRect(
                    x: 0, y: y, width: contentWidth, height: h
                )
                entryIdx += 1
            }
            y += h
        }

        if let highlightedIndex {
            let frame = highlightFrame(forRowAt: highlightedIndex)
            applyHighlightFrame(frame, animated: false)
        }
        applyRowRevealProgress()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        highlightView.backgroundColor = Self.selectionHighlightColor(for: traitCollection)
    }

    func setRevealProgress(_ progress: CGFloat) {
        let next = max(0.0, min(1.0, progress))
        guard abs(next - rowRevealProgress) > 0.001 else { return }
        rowRevealProgress = next
        applyRowRevealProgress()
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

    /// Drive row selection from an outer glass-surface gesture. This lets the
    /// menu's `UIGlassEffect.isInteractive` / fallback stretch own the actual
    /// touch stream while the rows remain a passive visual layer.
    func beginExternalInteraction(at point: CGPoint) {
        trackedTouch = nil
        moveHighlight(to: point, animated: false)
    }

    func updateExternalInteraction(at point: CGPoint) {
        moveHighlight(to: point, animated: true)
    }

    func endExternalInteraction(at point: CGPoint) {
        commitTouch(at: point)
    }

    func cancelExternalInteraction() {
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
        let isFirstShow = (highlightView.alpha < 0.01)

        highlightedIndex = index

        applyHighlightFrame(targetFrame, animated: animated && !isFirstShow)

        if isFirstShow {
            UIView.animate(
                withDuration: 0.15, delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: { self.highlightView.alpha = 1.0 },
                completion: nil
            )
        }
    }

    /// Fade the sliding highlight out, releasing any tracked touch's
    /// visual state. Exposed (non-private) because
    /// `ContextMenuController` needs to call it when an inline submenu
    /// opens — otherwise the highlight stays at its last tap-down row on the
    /// parent menu, which then becomes visible again when the parent
    /// un-dims on submenu-close.
    func clearHighlight(animated: Bool) {
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

    private func applyHighlightFrame(_ frame: CGRect, animated: Bool) {
        let cornerRadius = min(
            ContextMenuActionsView.highlightCornerRadius,
            min(frame.width, frame.height) * 0.5
        )
        let updates = {
            self.highlightView.frame = frame
            self.highlightView.layer.cornerRadius = cornerRadius
        }
        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                usingSpringWithDamping: 0.88,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                animations: updates,
                completion: nil
            )
        } else {
            updates()
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

        // Nearest tappable row — primary sort by Y distance (matches old
        // behaviour for regular vertical menus), tie-break by X distance
        // so cells in a horizontal `.actionRow` strip (which all share
        // the same midY) pick the one closest to the finger's X.
        //
        // Using strict <= on Y distance + <= on X distance as tie-
        // breaker means we never accidentally pick a full-width row
        // over a cell: cells in the same strip tie on Y with each
        // other, not with full-width rows above/below.
        var best: (index: Int, yDist: CGFloat, xDist: CGFloat)? = nil
        for (index, entry) in rowViews.enumerated() {
            let isTappable = entry.isHeaderRow || (entry.actionItem?.isEnabled == true)
            guard isTappable else { continue }
            let yDist = abs(pointInContent.y - entry.view.frame.midY)
            let xDist = abs(pointInContent.x - entry.view.frame.midX)
            if let current = best {
                if yDist < current.yDist {
                    best = (index, yDist, xDist)
                } else if yDist == current.yDist && xDist < current.xDist {
                    best = (index, yDist, xDist)
                }
            } else {
                best = (index, yDist, xDist)
            }
        }
        return best?.index
    }

    private func convertToContentContainer(_ point: CGPoint) -> CGPoint {
        return CGPoint(
            x: point.x - contentContainer.frame.minX,
            y: point.y - contentContainer.frame.minY
        )
    }

    private func highlightFrame(forRowAt index: Int) -> CGRect {
        let entry = rowViews[index]
        let rowFrame = entry.view.frame
        if entry.isActionRowCell {
            // Cells are compact and roughly square — use a tighter,
            // more balanced inset so the pill reads as a "button
            // highlight" rather than a full-width strip.
            return rowFrame.insetBy(dx: 4.0, dy: 6.0)
        }
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
        case .actionRow:
            return ContextMenuActionsView.actionRowHeight
        }
    }

    /// How many `RowEntry` slots a given `ContextMenuItem` occupies.
    /// Most items are 1:1 with an entry; `.actionRow` spans N entries
    /// (one per cell) so each cell can be independently touch-targeted
    /// and highlighted.
    private func rowEntryCount(for item: ContextMenuItem) -> Int {
        switch item {
        case let .actionRow(cells):
            return cells.count
        default:
            return 1
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
                // Native-iOS-26-style section title: mixed case (don't
                // uppercase — looks stale), regular weight (semibold
                // reads as too loud for a label that's meant to recede),
                // tertiaryLabel colour (~0.3 alpha of label) instead of
                // secondaryLabel (~0.6) so it sits behind the action
                // rows as quiet orientation text.
                let label = UILabel()
                label.text = title
                label.font = .systemFont(ofSize: 13.0, weight: .regular)
                label.textColor = .tertiaryLabel
                let container = UIView()
                container.isUserInteractionEnabled = false
                container.addSubview(label)
                label.snp.makeConstraints { make in
                    make.leading.equalToSuperview().offset(ContextMenuActionItemView.horizontalInset)
                    make.trailing.lessThanOrEqualToSuperview().offset(-ContextMenuActionItemView.horizontalInset)
                    make.bottom.equalToSuperview().offset(-6.0)
                }
                contentContainer.addSubview(container)
                rowViews.append(RowEntry(view: container, actionItem: nil))
            case let .action(action):
                let row = ContextMenuActionItemView(item: action)
                row.reservesLeadingSlot = reservesLeadingSlotForActionRows
                contentContainer.addSubview(row)
                rowViews.append(RowEntry(view: row, actionItem: action))
            case .separator:
                // Hairline: dropped from 0.6 → 0.3 alpha so it reads as
                // a barely-there divider, matching the native context
                // menu aesthetic where sections are separated by
                // presence rather than a hard line. Inset 4pt from
                // the content area (narrower than the row's 8pt text
                // inset) so the divider spans slightly wider than the
                // text column it divides.
                let container = UIView()
                container.isUserInteractionEnabled = false
                let line = UIView()
                line.backgroundColor = UIColor.separator.withAlphaComponent(0.3)
                container.addSubview(line)
                line.snp.makeConstraints { make in
                    make.leading.equalToSuperview().offset(ContextMenuActionsView.separatorHorizontalInset)
                    make.trailing.equalToSuperview().offset(-ContextMenuActionsView.separatorHorizontalInset)
                    make.centerY.equalToSuperview()
                    make.height.equalTo(1.0 / UIScreen.main.scale)
                }
                contentContainer.addSubview(container)
                rowViews.append(RowEntry(view: container, actionItem: nil))
            case let .actionRow(cells):
                // One `RowEntry` per cell — each cell is an independent
                // touch target with its own frame. layoutSubviews
                // positions them in a horizontal strip.
                for cellItem in cells {
                    let cellView = ContextMenuActionRowCellView(item: cellItem)
                    contentContainer.addSubview(cellView)
                    rowViews.append(RowEntry(
                        view: cellView,
                        actionItem: cellItem,
                        isActionRowCell: true
                    ))
                }
            }
        }
        // Keep the highlight UNDER the rows — text + icons need to read on top.
        contentContainer.sendSubviewToBack(highlightView)
        applyRowRevealProgress()
    }

    private static func itemsNeedLeadingSlot(_ items: [ContextMenuItem]) -> Bool {
        for item in items {
            switch item {
            case let .action(action):
                if action.isSelected || (action.icon != nil && action.iconSide == .leading) {
                    return true
                }
            case .actionRow, .header, .separator:
                continue
            }
        }
        return false
    }

    private static func selectionHighlightColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor.white.withAlphaComponent(0.14)
        }
        return UIColor.black.withAlphaComponent(0.12)
    }

    private func applyRowRevealProgress() {
        guard !rowViews.isEmpty else { return }
        for (index, entry) in rowViews.enumerated() {
            let rowStart = min(0.74, 0.42 + CGFloat(index) * 0.025)
            let rowT = Self.smootherstep(rowStart, rowStart + 0.20, rowRevealProgress)
            entry.view.alpha = rowT
            let scale = 0.985 + 0.015 * rowT
            entry.view.transform = CGAffineTransform(translationX: 0.0, y: (1.0 - rowT) * 5.0)
                .scaledBy(x: scale, y: scale)
        }
    }

    private static func smootherstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return x <= edge0 ? 0 : 1 }
        let t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
        return t * t * t * (t * (6.0 * t - 15.0) + 10.0)
    }

    /// Header row used at the top of pushed submenu pages (chevron.left)
    /// or inline-expand submenu cards (chevron.down). Renders the parent
    /// submenu's title in semibold so the row reads as a header.
    private func makeHeaderRow(title: String, chevronSymbol: String) -> UIView {
        let container = UIView()
        container.isUserInteractionEnabled = false

        let chevron = UIImageView()
        chevron.contentMode = .center
        chevron.tintColor = .label
        if #available(iOS 13.0, *) {
            let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            chevron.image = UIImage(systemName: chevronSymbol, withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
        }
        container.addSubview(chevron)

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 17.0, weight: .semibold)
        label.textColor = .label
        container.addSubview(label)

        chevron.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(ContextMenuActionItemView.horizontalInset)
            make.centerY.equalToSuperview()
            make.width.equalTo(14.0)
            make.height.equalTo(18.0)
        }
        label.snp.makeConstraints { make in
            make.leading.equalTo(chevron.snp.trailing).offset(10.0)
            make.trailing.lessThanOrEqualToSuperview().offset(-ContextMenuActionItemView.horizontalInset)
            make.centerY.equalToSuperview()
        }
        return container
    }
}
