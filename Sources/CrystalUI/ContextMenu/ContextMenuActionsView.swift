import UIKit

// MARK: - ContextMenuActionsView

/// The actual menu body — rounded glass panel with vertically stacked rows,
/// optional header labels, and inset hairline separators.
///
/// Corresponds to Telegram's `ContextActionsContainerNode` but intentionally
/// thin: no stack of pages, no tips, no reactions.
final class ContextMenuActionsView: UIView {
    // MARK: - Metrics

    static let cornerRadius: CGFloat = 16.0
    static let preferredWidth: CGFloat = 260.0
    static let headerHeight: CGFloat = 34.0
    static let separatorHeight: CGFloat = 8.0

    // MARK: - Subviews

    private let glassBackground: GlassBackgroundView
    private let contentContainer = UIView()
    private var rowViews: [UIView] = []

    // MARK: - State

    private let items: [ContextMenuItem]
    var onActionSelected: ((ContextMenuActionItem) -> Void)?

    // MARK: - Init

    init(items: [ContextMenuItem]) {
        self.items = items
        self.glassBackground = GlassBackgroundView(style: .regular)

        super.init(frame: .zero)

        glassBackground.isUserInteractionEnabled = false
        addSubview(glassBackground)

        contentContainer.clipsToBounds = true
        contentContainer.layer.cornerRadius = ContextMenuActionsView.cornerRadius
        if #available(iOS 13.0, *) {
            contentContainer.layer.cornerCurve = .continuous
        }
        addSubview(contentContainer)

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

    func dimRowHighlight() {
        for view in rowViews {
            (view as? ContextMenuActionItemView)?.alpha = (view as? ContextMenuActionItemView)?.item.isEnabled == false ? 0.4 : 1.0
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()

        let frame = CGRect(origin: .zero, size: bounds.size)
        glassBackground.frame = frame
        glassBackground.update(
            size: bounds.size,
            cornerRadius: ContextMenuActionsView.cornerRadius,
            isDark: traitCollection.userInterfaceStyle == .dark,
            tintColor: .init(kind: .panel),
            isInteractive: false,
            isVisible: true,
            transition: .immediate
        )
        contentContainer.frame = frame

        var y: CGFloat = 0.0
        for (index, item) in items.enumerated() {
            let h = heightForItem(item)
            rowViews[index].frame = CGRect(x: 0, y: y, width: bounds.width, height: h)
            y += h
        }
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
                container.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: ContextMenuActionItemView.horizontalInset),
                    label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -ContextMenuActionItemView.horizontalInset),
                    label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6.0)
                ])
                contentContainer.addSubview(container)
                rowViews.append(container)
            case let .action(action):
                let row = ContextMenuActionItemView(item: action)
                row.onTap = { [weak self] tapped in
                    self?.onActionSelected?(tapped)
                }
                contentContainer.addSubview(row)
                rowViews.append(row)
            case .separator:
                let container = UIView()
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
                rowViews.append(container)
            }
        }
    }
}
