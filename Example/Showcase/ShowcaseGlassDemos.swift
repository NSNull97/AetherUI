import UIKit
import CrystalUI

// MARK: - GlassButton

final class GlassButtonDemoController: ShowcaseDemoController {
    override var demoTitle: String { "GlassButton" }

    override func buildDemo() {
        // Icon-only glass button.
        let iconBtn = GlassButton()
        iconBtn.image = UIImage(systemName: "heart.fill",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 20))
        iconBtn.action = { _ in
            CrystalToastController(content: .text("Icon button tapped")).present()
        }
        addPaddedView(iconBtn, height: 50)

        // Title-only pill.
        let titleBtn = GlassButton()
        titleBtn.title = "Нажми меня"
        titleBtn.action = { _ in
            CrystalToastController(content: .text("Title button tapped")).present()
        }
        addPaddedView(titleBtn, height: 50)

        // Icon + title.
        let iconTitleBtn = GlassButton()
        iconTitleBtn.image = UIImage(systemName: "square.and.arrow.up")
        iconTitleBtn.title = "Поделиться"
        iconTitleBtn.action = { _ in
            CrystalToastController(content: .text("Shared")).present()
        }
        addPaddedView(iconTitleBtn, height: 50)

        // Destructive tint.
        let destructiveBtn = GlassButton()
        destructiveBtn.image = UIImage(systemName: "trash.fill")
        destructiveBtn.title = "Удалить"
        destructiveBtn.contentColor = .systemRed
        destructiveBtn.action = { _ in
            CrystalToastController(content: .text("Deleted")).present()
        }
        addPaddedView(destructiveBtn, height: 50)

        // Small square icon button row — three in a row.
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually
        for symbol in ["bolt.fill", "star.fill", "flame.fill"] {
            let b = GlassButton()
            b.image = UIImage(systemName: symbol)
            b.action = { _ in
                CrystalToastController(content: .text(symbol)).present()
            }
            row.addArrangedSubview(b)
        }
        addPaddedView(row, height: 50)
    }
}

// MARK: - ContextMenu

final class ContextMenuDemoController: ShowcaseDemoController {
    override var demoTitle: String { "Context Menu" }

    private var morphTarget: UIView?
    private var previewTarget: UIView?

    override func buildDemo() {
        // Morph-style anchor (pill button).
        let morphBtn = GlassButton()
        morphBtn.title = "Long-press morph"
        morphBtn.action = { _ in /* long press only */ }
        let morphLong = UILongPressGestureRecognizer(target: self, action: #selector(morphLongPressed(_:)))
        morphBtn.addGestureRecognizer(morphLong)
        addPaddedView(morphBtn, height: 50)
        morphTarget = morphBtn

        // Preview-style anchor — a card that simulates content.
        let previewCard = UIView()
        previewCard.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        previewCard.layer.cornerRadius = 14
        previewCard.layer.cornerCurve = .continuous

        let label = UILabel()
        label.text = "Long-press для preview"
        label.textAlignment = .center
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        previewCard.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: previewCard.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: previewCard.centerYAnchor)
        ])

        let previewLong = UILongPressGestureRecognizer(target: self, action: #selector(previewLongPressed(_:)))
        previewCard.addGestureRecognizer(previewLong)
        previewCard.isUserInteractionEnabled = true
        addPaddedView(previewCard, height: 140)
        previewTarget = previewCard

        // Tap button — opens a regular context menu (simulating a 3-dot menu).
        addButton("Открыть меню (tap)") { [weak self] in
            self?.showSimpleMenu()
        }
    }

    @objc private func morphLongPressed(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began, let view = morphTarget else { return }
        let menu = ContextMenuController(
            source: ContextMenuController.Source(view: view, cornerRadius: view.bounds.height / 2),
            items: sampleItems(),
            presentationStyle: .morph
        )
        menu.present()
    }

    @objc private func previewLongPressed(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began, let view = previewTarget else { return }
        let menu = ContextMenuController(
            source: ContextMenuController.Source(view: view, cornerRadius: 14),
            items: sampleItems(),
            presentationStyle: .preview()
        )
        menu.present()
    }

    private func showSimpleMenu() {
        // Anchor to the third button — the "Открыть меню (tap)" button.
        guard stack.arrangedSubviews.count >= 3 else { return }
        let anchor = stack.arrangedSubviews[2]
        let menu = ContextMenuController(
            source: ContextMenuController.Source(view: anchor, cornerRadius: 14),
            items: sampleItems(),
            presentationStyle: .morph
        )
        menu.present()
    }

    private func sampleItems() -> [ContextMenuItem] {
        return [
            .action(ContextMenuActionItem(
                title: "Копировать",
                icon: UIImage(systemName: "doc.on.doc"),
                action: { _, handle in
                    CrystalToastController(content: .text("Copied")).present()
                    handle.dismiss()
                }
            )),
            .action(ContextMenuActionItem(
                title: "Поделиться",
                icon: UIImage(systemName: "square.and.arrow.up"),
                action: { _, handle in
                    CrystalToastController(content: .text("Shared")).present()
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
                    CrystalToastController(content: .text("Deleted")).present()
                    handle.dismiss()
                }
            ))
        ]
    }
}

// MARK: - NavigationBar Search

final class NavigationBarSearchDemoController: ShowcaseDemoController, CrystalSearchControllerDelegate {
    override var demoTitle: String { "NavigationBar Search" }

    private let resultsLabel = UILabel()

    override func buildDemo() {
        resultsLabel.text = "Нажми search-пилюлю в навбаре сверху, чтобы превратить её в поле ввода."
        resultsLabel.font = .systemFont(ofSize: 15)
        resultsLabel.textColor = .secondaryLabel
        resultsLabel.numberOfLines = 0
        resultsLabel.textAlignment = .center
        addPaddedView(resultsLabel, height: 80)

        addButton("Активировать search") { [weak self] in
            self?.crystalSearchController?.activate()
        }
        addButton("Деактивировать search") { [weak self] in
            self?.crystalSearchController?.deactivate()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let search = CrystalSearchController()
        search.placeholder = "Поиск..."
        search.delegate = self
        crystalSearchController = search
    }

    // MARK: CrystalSearchControllerDelegate

    func searchController(_ controller: CrystalSearchController, didUpdateSearchText searchText: String) {
        resultsLabel.text = searchText.isEmpty
            ? "Введите запрос в поле поиска"
            : "Query: \(searchText)"
    }

    func searchControllerDidDeactivate(_ controller: CrystalSearchController) {
        resultsLabel.text = "Search cancelled."
    }
}
