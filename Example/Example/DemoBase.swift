import UIKit
import AetherUI
import AssociatedObject

/// Vertical stack of buttons inside a scroll view — used as the body
/// of every leaf demo screen below. Subclasses populate via `addButton`
/// inside `buildDemo()`.
class DemoController: AetherViewController {
    let stack = UIStackView()
    let scrollView = UIScrollView()

    /// Subclasses set the navbar title.
    var demoTitle: String { "Demo" }

    init() {
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: .systemBackground))
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = demoTitle
        view.backgroundColor = .systemBackground
        installRandomNavbarButton(on: self)

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 13.0, *) {
            scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        }
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.bottomAnchor, constant: -32)
        ])

        buildDemo()
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
        transition.updateContentInset(scrollView: scrollView, insets: insets)
        transition.updateScrollIndicatorInsets(scrollView: scrollView, insets: insets)
    }

    /// Override to add buttons / inline demo views.
    func buildDemo() {}

    @discardableResult
    func addButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.cornerStyle = .large
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        stack.addArrangedSubview(button)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
    }

    @discardableResult
    func addLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
        return label
    }

    func addCenteredView(_ view: UIView, height: CGFloat) {
        let container = UIView()
        container.heightAnchor.constraint(equalToConstant: height).isActive = true
        container.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        stack.addArrangedSubview(container)
    }
}

/// Generic grouped-table list — used by every tab's root and any demo
/// that needs a "pick one" picker. Pushes a controller per row through
/// the current navigation stack.
final class DemoListController: AetherViewController {
    typealias RowFactory = () -> UIViewController

    struct Row {
        let title: String
        let subtitle: String?
        let make: RowFactory
        init(_ title: String, _ subtitle: String? = nil, _ make: @escaping RowFactory) {
            self.title = title
            self.subtitle = subtitle
            self.make = make
        }
    }

    private let titleText: String
    private let rows: [Row]
    private var tableView: UITableView!

    init(title: String, rows: [Row]) {
        self.titleText = title
        self.rows = rows
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: .systemGroupedBackground))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = titleText
        view.backgroundColor = .systemGroupedBackground 

        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(DemoRowCell.self, forCellReuseIdentifier: "row")
        tableView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 13.0, *) {
            tableView.automaticallyAdjustsScrollIndicatorInsets = false
        }
        view.addSubview(tableView)
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
}

extension DemoListController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! DemoRowCell
        let row = rows[indexPath.row]
        cell.configure(title: row.title, subtitle: row.subtitle)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let vc = rows[indexPath.row].make()
        push(vc as! AetherViewController)
    }
}

final class DemoRowCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        detailTextLabel?.font = .systemFont(ofSize: 13)
        detailTextLabel?.textColor = .secondaryLabel
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, subtitle: String?) {
        textLabel?.text = title
        detailTextLabel?.text = subtitle
    }
}

// MARK: - Random navbar button

/// Fills `navigationItem.rightBarButtonItem` with a random SF Symbol —
/// each demo screen gets a different glyph as a tiny visual signature.
/// Tapping just shows a toast so the button is alive.
private let randomNavbarSymbols: [String] = [
    "bell", "gear", "ellipsis.circle", "square.and.pencil", "paperplane",
    "heart", "star", "bookmark", "bolt", "wand.and.stars",
    "person.crop.circle", "magnifyingglass", "tray", "tag", "info.circle"
]

func installRandomNavbarButton(on viewController: UIViewController) {
    let symbol = randomNavbarSymbols.randomElement() ?? "ellipsis"
    let target = NavbarButtonActionTarget {
        AetherToastController(content: .text("Tapped \(symbol)")).present()
    }

    let item = UIBarButtonItem(image: UIImage(systemName: symbol)) {
        sampleItems()
    }

    viewController.navbarButtonActionTarget = target
    viewController.navigationItem.rightBarButtonItem = item
}

func sampleItems() -> [ContextMenuItem] {
    return [
        .action(ContextMenuActionItem(
            title: "Копировать",
            icon: UIImage(systemName: "doc.on.doc"),
            action: { _, handle in
                AetherToastController(content: .text("Copied")).present()
                handle.dismiss()
            }
        )),
        .action(ContextMenuActionItem(
            title: "Поделиться",
            icon: UIImage(systemName: "square.and.arrow.up"),
            action: { _, handle in
                AetherToastController(content: .text("Shared")).present()
                handle.dismiss()
            }
        )),
        .action(ContextMenuActionItem(
            title: "Ещё",
            icon: UIImage(systemName: "chevron.right"),
            submenu: [
                .action(ContextMenuActionItem(
                    title: "Пункт 1",
                    icon: UIImage(systemName: "1.circle"),
                    action: { _, handle in handle.dismiss() }
                )),
                .action(ContextMenuActionItem(
                    title: "Пункт 2",
                    icon: UIImage(systemName: "2.circle"),
                    action: { _, handle in handle.dismiss() }
                ))
            ]
        )),
        .separator,
        .action(ContextMenuActionItem(
            title: "Удалить",
            icon: UIImage(systemName: "trash"),
            textColor: .destructive,
            action: { _, handle in
                AetherToastController(content: .text("Deleted")).present()
                handle.dismiss()
            }
        ))
    ]
}

private extension UIViewController {
    @AssociatedObject(.retain(.nonatomic))
    var navbarButtonActionTarget: NavbarButtonActionTarget?
}

private final class NavbarButtonActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func invoke() {
        action()
    }
}
