import UIKit
import CrystalUI

/// Lists every major CrystalUI component and opens a dedicated demo on tap.
final class ShowcaseHomeController: ViewController {
    private struct Section {
        let title: String
        let rows: [Row]
    }

    private struct Row {
        let title: String
        let subtitle: String
        let make: () -> UIViewController
    }

    private let sections: [Section] = [
        Section(title: "Диалоги", rows: [
            Row(title: "ActionSheet", subtitle: "кнопки/чекбоксы/свитчи/текст",
                make: { ActionSheetDemoController() }),
            Row(title: "Alert", subtitle: "title + message + buttons",
                make: { AlertDemoController() }),
            Row(title: "Tooltip", subtitle: "указывает на view",
                make: { TooltipDemoController() }),
            Row(title: "Toast / Snackbar", subtitle: "snackbar внизу",
                make: { ToastDemoController() })
        ]),
        Section(title: "Состояния экрана", rows: [
            Row(title: "Content State", subtitle: "loading / empty / error",
                make: { ContentStateDemoController() }),
            Row(title: "Skeletons", subtitle: "shimmer-плейсхолдеры",
                make: { SkeletonDemoController() })
        ]),
        Section(title: "Навигация", rows: [
            Row(title: "Toolbar", subtitle: "нижняя панель кнопок",
                make: { ToolbarDemoController() })
        ])
    ]

    private var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "CrystalUI Showcase"

        view.backgroundColor = .systemBackground

        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ShowcaseRowCell.self, forCellReuseIdentifier: "row")
        view.addSubview(tableView)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        var insets = layout.safeInsets
        // Give the table room under the custom navbar. The nav controller
        // owns the nav bar and exposes its height through its frame.
        insets.top = navigationBarView?.frame.maxY ?? insets.top
        tableView.contentInset = insets
        tableView.scrollIndicatorInsets = insets
    }
}

extension ShowcaseHomeController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! ShowcaseRowCell
        let row = sections[indexPath.section].rows[indexPath.row]
        cell.configure(title: row.title, subtitle: row.subtitle)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        let vc = row.make()
        if let nav = navigationController as? CrystalNavigationController, let vc = vc as? ViewController {
            nav.pushViewController(vc, animated: true)
        } else {
            present(vc, animated: true)
        }
    }
}

final class ShowcaseRowCell: UITableViewCell {
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        accessoryType = .disclosureIndicator
        textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        detailTextLabel?.font = .systemFont(ofSize: 13)
        detailTextLabel?.textColor = .secondaryLabel
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, subtitle: String) {
        textLabel?.text = title
        detailTextLabel?.text = subtitle
    }
}
