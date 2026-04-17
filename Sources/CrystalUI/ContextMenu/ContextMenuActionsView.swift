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
    static let highlightHorizontalInset: CGFloat = 6.0
    static let highlightCornerRadius: CGFloat = 14.0

    // MARK: - Subviews

    /// Direct `UIVisualEffectView` (UIGlassEffect on iOS 26+, UIBlurEffect
    /// fallback) instead of `GlassBackgroundView` — the latter is correct in
    /// isolation but disappears once placed inside `LensTransitionContainer`'s
    /// keyframe-driven contentsView (the lens sublayerTransform / clipping
    /// interactions hide its native pipeline). A plain `UIVisualEffectView`
    /// renders reliably regardless of where it's placed.
    private let glassView: UIVisualEffectView
    private let contentContainer = UIView()
    private let highlightView = UIView()
    private var rowViews: [RowEntry] = []

    private struct RowEntry {
        let view: UIView
        let actionItem: ContextMenuActionItem?
    }

    // MARK: - State

    private let items: [ContextMenuItem]
    var onActionSelected: ((ContextMenuActionItem) -> Void)?

    private var trackedTouch: UITouch?
    private var highlightedIndex: Int?

    /// Hooks the controller can use to apply the rubber-band stretch on the
    /// outer container (the whole menu chrome, not just the rows). Reporting
    /// the touch in the actionsView's own coords; the controller is
    /// responsible for converting / applying the transform on its own host.
    var onStretchUpdate: ((CGPoint) -> Void)?
    var onStretchRelease: (() -> Void)?

    // MARK: - Init

    init(items: [ContextMenuItem]) {
        self.items = items
        let blur = UIVisualEffectView()
        if #available(iOS 26.0, *) {
            blur.effect = UIGlassEffect(style: .regular)
        } else {
            blur.effect = UIBlurEffect(style: .systemMaterial)
        }
        blur.layer.cornerRadius = ContextMenuActionsView.cornerRadius
        blur.layer.masksToBounds = true
        if #available(iOS 13.0, *) {
            blur.layer.cornerCurve = .continuous
        }
        blur.isUserInteractionEnabled = false
        self.glassView = blur

        super.init(frame: .zero)

        addSubview(glassView)

        contentContainer.clipsToBounds = true
        contentContainer.layer.cornerRadius = ContextMenuActionsView.cornerRadius
        if #available(iOS 13.0, *) {
            contentContainer.layer.cornerCurve = .continuous
        }
        addSubview(contentContainer)

        highlightView.backgroundColor = UIColor.label.withAlphaComponent(0.08)
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

    /// Intrinsic size for a given width — sums the heights of the items.
    func preferredSize(maxWidth: CGFloat) -> CGSize {
        let width = min(maxWidth, ContextMenuActionsView.preferredWidth)
        var height: CGFloat = 0.0
        for item in items {
            height += heightForItem(item)
        }
        return CGSize(width: width, height: height)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        let frame = CGRect(origin: .zero, size: bounds.size)
        glassView.frame = frame
        contentContainer.frame = frame

        var y: CGFloat = 0.0
        for (index, item) in items.enumerated() {
            let h = heightForItem(item)
            rowViews[index].view.frame = CGRect(x: 0, y: y, width: bounds.width, height: h)
            y += h
        }

        // Reposition the highlight if it's currently anchored on a row.
        if let highlightedIndex {
            highlightView.frame = highlightFrame(forRowAt: highlightedIndex)
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

        if isFirstShow {
            // First show: jump to position with no slide, only fade in.
            highlightView.frame = targetFrame
            UIView.animate(
                withDuration: 0.15, delay: 0,
                options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
                animations: { self.highlightView.alpha = 1.0 },
                completion: nil
            )
            return
        }

        // Subsequent moves: slide via spring.
        if animated {
            UIView.animate(
                withDuration: 0.32, delay: 0,
                usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: { self.highlightView.frame = targetFrame },
                completion: nil
            )
        } else {
            highlightView.frame = targetFrame
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
        guard let index = enabledRowIndex(at: point), let actionItem = rowViews[index].actionItem else {
            clearHighlight(animated: true)
            return
        }
        // Action is invoked synchronously; the highlight stays visible until
        // the menu dismiss animation removes the view, giving the user a
        // moment of feedback that their tap registered.
        onActionSelected?(actionItem)
    }

    /// Returns the index of the enabled action row whose frame contains
    /// `point`. Headers / separators / disabled rows return nil.
    private func enabledRowIndex(at point: CGPoint) -> Int? {
        for (index, entry) in rowViews.enumerated() {
            guard entry.view.frame.contains(point) else { continue }
            guard let actionItem = entry.actionItem, actionItem.isEnabled else { return nil }
            return index
        }
        return nil
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
        case .action:
            return ContextMenuActionItemView.rowHeight
        case .separator:
            return ContextMenuActionsView.separatorHeight
        }
    }

    private func buildRowViews() {
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
}
