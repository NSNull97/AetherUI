import UIKit
import CrystalUI

/// Generic grouped-table list used as each tab's root. Pushes a demo
/// controller per row via the current nav controller.
final class ShowcaseListController: ViewController {
    typealias RowFactory = () -> UIViewController

    private struct Row {
        let title: String
        let subtitle: String
        let make: RowFactory
    }

    private let titleText: String
    private let rows: [Row]
    private var tableView: UITableView!

    init(title: String, rows: [(String, String, RowFactory)]) {
        self.titleText = title
        self.rows = rows.map { Row(title: $0.0, subtitle: $0.1, make: $0.2) }
        // Nav controller fabricates and attaches a nav bar via wireControllers —
        // we don't need to pass presentation data explicitly.
        super.init()
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
        tableView.register(ShowcaseRowCell.self, forCellReuseIdentifier: "row")
        view.addSubview(tableView)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        var insets = layout.safeInsets
        insets.top = navigationBarView?.frame.maxY ?? insets.top
        insets.bottom = max(insets.bottom, layout.additionalInsets.bottom)
        tableView.contentInset = insets
        tableView.scrollIndicatorInsets = insets
    }
}

extension ShowcaseListController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath) as! ShowcaseRowCell
        let row = rows[indexPath.row]
        cell.configure(title: row.title, subtitle: row.subtitle)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let vc = rows[indexPath.row].make()
        if let nav = navigationController as? CrystalNavigationController,
           let view = vc as? ViewController {
            nav.pushViewController(view, animated: true)
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
