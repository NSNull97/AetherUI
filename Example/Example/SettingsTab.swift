import UIKit
import AetherUI

/// Tab 4 — settings panel that drives the rest of the app's chrome:
/// toggles the navbar `topBarAccessory`, the tabbar `bottomBarAccessory`,
/// the minimize behaviour, and edge-effect blur via context menus.
final class SettingsController: AetherViewController {
    weak var hostTabBar: AetherTabBarController?

    private var tableView: UITableView!

    fileprivate var rows: [Row] = []

    fileprivate struct Row {
        let title: String
        let trailing: TrailingKind
        let onTap: () -> Void
    }

    fileprivate enum TrailingKind {
        case toggle(isOn: Bool, onChange: (Bool) -> Void)
        case value(String)
        case none
    }

    // State driving the settings.
    private var showsTopAccessory = false
    private var showsBottomAccessory = false
    private var minimizeBehavior: AetherTabBarController.TabBarMinimizeBehavior = .never
    private var edgeBlurAtEdge: CGFloat = 2.0
    private var edgeBlurAtFade: CGFloat = 0.0

    init() {
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: .systemGroupedBackground))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Settings"
        view.backgroundColor = .systemGroupedBackground
        installRandomNavbarButton(on: self)

        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SettingsCell.self, forCellReuseIdentifier: "row")
        tableView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 13.0, *) {
            tableView.automaticallyAdjustsScrollIndicatorInsets = false
        }
        view.addSubview(tableView)

        rebuildRows()

        // Sync starting minimize/edge-blur values to whatever the
        // tab bar already has — keeps the UI honest if Settings is
        // opened after some other code touched the chrome.
        if let tabs = hostTabBar {
            minimizeBehavior = tabs.tabBarMinimizeBehavior
            edgeBlurAtEdge = tabs.tabBarTheme.edgeEffectBlurRadiusAtEdge
            edgeBlurAtFade = tabs.tabBarTheme.edgeEffectBlurRadiusAtFade
            rebuildRows()
            tableView.reloadData()
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = cleanNavigationHeight
        let bottomInset = max(layout.safeInsets.bottom, layout.additionalInsets.bottom)
        let insets = UIEdgeInsets(
            top: topInset,
            left: layout.safeInsets.left,
            bottom: bottomInset,
            right: layout.safeInsets.right
        )
        transition.updateContentInset(scrollView: tableView, insets: insets)
        transition.updateScrollIndicatorInsets(scrollView: tableView, insets: insets)
    }

    private func rebuildRows() {
        rows = [
            Row(
                title: "Top bar accessory (этот экран)",
                trailing: .toggle(isOn: showsTopAccessory, onChange: { [weak self] on in
                    self?.applyTopAccessory(on)
                }),
                onTap: {}
            ),
            Row(
                title: "Bottom bar accessory (tab bar)",
                trailing: .toggle(isOn: showsBottomAccessory, onChange: { [weak self] on in
                    self?.applyBottomAccessory(on)
                }),
                onTap: {}
            ),
            Row(
                title: "Tab bar minimize",
                trailing: .value(minimizeBehavior.label),
                onTap: { [weak self] in self?.pickMinimizeBehavior() }
            ),
            Row(
                title: "Edge blur at edge",
                trailing: .value(String(format: "%.1f", edgeBlurAtEdge)),
                onTap: { [weak self] in self?.pickEdgeBlur(.atEdge) }
            ),
            Row(
                title: "Edge blur at fade",
                trailing: .value(String(format: "%.1f", edgeBlurAtFade)),
                onTap: { [weak self] in self?.pickEdgeBlur(.atFade) }
            )
        ]
    }

    // MARK: - Top accessory

    private func applyTopAccessory(_ on: Bool) {
        showsTopAccessory = on
        if on {
            setTopBarAccessory(SettingsTopAccessoryView(), animated: true)
        } else {
            setTopBarAccessory(nil, animated: true)
        }
        rebuildRows()
        tableView.reloadData()
    }

    // MARK: - Bottom accessory

    private func applyBottomAccessory(_ on: Bool) {
        showsBottomAccessory = on
        guard let tabs = hostTabBar else { return }
        if on {
            tabs.setBottomBarAccessory(SettingsBottomAccessoryView(), animated: true)
        } else {
            tabs.setBottomBarAccessory(nil, animated: true)
        }
        rebuildRows()
        tableView.reloadData()
    }

    // MARK: - Minimize behaviour

    private func pickMinimizeBehavior() {
        guard let row = visibleCell(forRowIndex: 2) else { return }
        let menu = ContextMenuController(
            source: ContextMenuController.Source(view: row, cornerRadius: 12),
            items: [
                .action(ContextMenuActionItem(
                    title: "Never",
                    icon: minimizeBehavior == .never ? UIImage(systemName: "checkmark") : nil,
                    action: { [weak self] _, handle in
                        self?.applyMinimize(.never)
                        handle.dismiss()
                    }
                )),
                .action(ContextMenuActionItem(
                    title: "On scroll down",
                    icon: minimizeBehavior == .onScrollDown ? UIImage(systemName: "checkmark") : nil,
                    action: { [weak self] _, handle in
                        self?.applyMinimize(.onScrollDown)
                        handle.dismiss()
                    }
                ))
            ],
            presentationStyle: .fluidMorph
        )
        menu.present()
    }

    private func applyMinimize(_ behavior: AetherTabBarController.TabBarMinimizeBehavior) {
        minimizeBehavior = behavior
        hostTabBar?.tabBarMinimizeBehavior = behavior
        rebuildRows()
        tableView.reloadData()
    }

    // MARK: - Edge blur

    private enum EdgeBlurField { case atEdge, atFade }

    private func pickEdgeBlur(_ field: EdgeBlurField) {
        let rowIndex = field == .atEdge ? 3 : 4
        guard let row = visibleCell(forRowIndex: rowIndex) else { return }
        let presets: [CGFloat] = [0.0, 1.0, 2.0, 4.0, 6.0, 10.0]
        let current = field == .atEdge ? edgeBlurAtEdge : edgeBlurAtFade
        let items: [ContextMenuItem] = presets.map { value in
            let isSelected = abs(current - value) < 0.05
            return .action(ContextMenuActionItem(
                title: String(format: "%.1f", value),
                icon: isSelected ? UIImage(systemName: "checkmark") : nil,
                action: { [weak self] _, handle in
                    self?.applyEdgeBlur(field, value: value)
                    handle.dismiss()
                }
            ))
        }
        let menu = ContextMenuController(
            source: ContextMenuController.Source(view: row, cornerRadius: 12),
            items: items,
            presentationStyle: .fluidMorph
        )
        menu.present()
    }

    private func applyEdgeBlur(_ field: EdgeBlurField, value: CGFloat) {
        switch field {
        case .atEdge: edgeBlurAtEdge = value
        case .atFade: edgeBlurAtFade = value
        }
        guard let tabs = hostTabBar else {
            rebuildRows()
            tableView.reloadData()
            return
        }
        let old = tabs.tabBarTheme
        tabs.tabBarTheme = TabBarView.Theme(
            tabBarBackgroundColor: old.tabBarBackgroundColor,
            tabBarSeparatorColor: old.tabBarSeparatorColor,
            tabBarIconColor: old.tabBarIconColor,
            tabBarSelectedIconColor: old.tabBarSelectedIconColor,
            tabBarTextColor: old.tabBarTextColor,
            tabBarSelectedTextColor: old.tabBarSelectedTextColor,
            tabBarBadgeBackgroundColor: old.tabBarBadgeBackgroundColor,
            tabBarBadgeStrokeColor: old.tabBarBadgeStrokeColor,
            tabBarBadgeTextColor: old.tabBarBadgeTextColor,
            enableBlur: old.enableBlur,
            isDark: old.isDark,
            style: old.style,
            outerInsets: old.outerInsets,
            pillHeight: old.pillHeight,
            totalHeight: old.totalHeight,
            bottomInset: old.bottomInset,
            sideInset: old.sideInset,
            innerPadding: old.innerPadding,
            showcaseSpacing: old.showcaseSpacing,
            edgeEffectAlpha: old.edgeEffectAlpha,
            edgeEffectBlurRadiusAtEdge: edgeBlurAtEdge,
            edgeEffectBlurRadiusAtFade: edgeBlurAtFade,
            edgeEffectTintColor: old.edgeEffectTintColor
        )
        rebuildRows()
        tableView.reloadData()
    }

    private func visibleCell(forRowIndex index: Int) -> UIView? {
        return tableView.cellForRow(at: IndexPath(row: index, section: 0))
    }
}

extension SettingsController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! SettingsCell
        cell.configure(with: rows[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        rows[indexPath.row].onTap()
    }
}

private final class SettingsCell: UITableViewCell {
    private let toggle = UISwitch()
    private var toggleHandler: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
        textLabel?.font = .systemFont(ofSize: 16)
        detailTextLabel?.font = .systemFont(ofSize: 15)
        detailTextLabel?.textColor = .secondaryLabel
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func toggleChanged() {
        toggleHandler?(toggle.isOn)
    }

    func configure(with row: SettingsController.Row) {
        textLabel?.text = row.title
        detailTextLabel?.text = nil
        accessoryView = nil
        accessoryType = .none
        toggleHandler = nil

        switch row.trailing {
        case .toggle(let isOn, let onChange):
            toggle.isOn = isOn
            toggleHandler = onChange
            accessoryView = toggle
        case .value(let text):
            detailTextLabel?.text = text
            accessoryType = .disclosureIndicator
        case .none:
            break
        }
    }
}

// MARK: - Helpers

private extension AetherTabBarController.TabBarMinimizeBehavior {
    var label: String {
        switch self {
        case .never: return "Never"
        case .onScrollDown: return "On scroll down"
        }
    }
}

// Sample top accessory — a simple labeled glass strip to make the
// extra navbar real estate visible.
private final class SettingsTopAccessoryView: NavigationBarContentView {
    private let glass = GlassBackgroundView(style: .regular)
    private let label = UILabel()

    override var nominalHeight: CGFloat { 44 }
    override var mode: NavigationBarContentMode { .expansion }

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(glass)
        glass.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            glass.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])

        label.text = "Top bar accessory"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: glass.contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: glass.contentView.centerYAnchor)
        ])
    }

    @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// Sample bottom accessory — fixed-height labeled view that sits above
// the tab bar pill.
private final class SettingsBottomAccessoryView: TabBarAccessoryView {
    private let label = UILabel()

    override var nominalHeight: CGFloat { 48 }

    override init(frame: CGRect) {
        super.init(frame: frame)

        label.text = "Bottom bar accessory"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
