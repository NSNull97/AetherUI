import UIKit
import AetherUI

/// Tab 1 root — picker that pushes a demo per row.
func makeComponentsRoot() -> AetherViewController {
    return DemoListController(title: "Components", rows: [
        .init("Buttons", "UIKit + Glass", { ButtonsDemoController() }),
        .init("Alerts", "single / pair / stacked + поля", { AlertsDemoController() }),
        .init("ActionSheet", "buttons / checkbox / switch", { ActionSheetDemoController() }),
        .init("Floating Toolbar", "pill / standalone / search", { ToolbarDemoController() }),
        .init("Tooltip", "text / icon+text / attributed", { TooltipDemoController() }),
        .init("Context Menu", "morph / preview / submenu", { ContextMenuDemoController() }),
        .init("Segmented Control", "glass lens", { SegmentedDemoController() })
    ])
}

// MARK: - Buttons

final class ButtonsDemoController: DemoController {
    override var demoTitle: String { "Buttons" }

    override func buildDemo() {
        addLabel("UIKit-конфигурации:")
        addButton("Filled — primary action") {
            AetherToastController(content: .text("Tapped filled")).present()
        }
        addButton("Disabled (без обработчика)") {}.isEnabled = false

        addLabel("Glass-кнопка с иконкой:")
        let glassBar = GlassBarButtonView(
            icon: UIImage(systemName: "sparkles"),
            title: "Glass Bar Button",
            state: .glass
        )
        glassBar.action = { _ in
            AetherToastController(content: .text("Glass tapped")).present()
        }
        addCenteredView(glassBar, height: 44)

        addLabel("Tinted glass:")
        let tinted = GlassBarButtonView(
            icon: UIImage(systemName: "wand.and.stars"),
            title: "Tinted Glass",
            state: .tintedGlass
        )
        tinted.action = { _ in
            AetherToastController(content: .text("Tinted tapped")).present()
        }
        addCenteredView(tinted, height: 44)
    }
}

// MARK: - Alerts

final class AlertsDemoController: DemoController {
    override var demoTitle: String { "Alerts" }

    override func buildDemo() {
        addButton("Single — Primary OK") { [weak self] in self?.showSingle() }
        addButton("Pair — Secondary + Primary") { [weak self] in self?.showPair() }
        addButton("Stacked — Primary / Destructive / Secondary") { [weak self] in self?.showStacked() }
        addButton("1 поле ввода") { [weak self] in self?.showWithField() }
        addButton("2 поля (login / password)") { [weak self] in self?.showWithTwoFields() }
    }

    private func showSingle() {
        let alert = AetherAlertController(
            title: "A Short Title Is Best",
            message: "A description should be a short, complete sentence.",
            actions: [AetherAlertAction(title: "OK", style: .primary)]
        )
        present(alert, animated: false)
    }

    private func showPair() {
        let alert = AetherAlertController(
            title: "Готовы?",
            message: "Действие можно будет отменить позже.",
            actions: [
                AetherAlertAction(title: "Отмена", style: .secondary),
                AetherAlertAction(title: "Продолжить", style: .primary)
            ]
        )
        present(alert, animated: false)
    }

    private func showStacked() {
        let alert = AetherAlertController(
            title: "Удалить запись?",
            message: "Это действие необратимо.",
            actions: [
                AetherAlertAction(title: "Сохранить копию", style: .primary),
                AetherAlertAction(title: "Удалить", style: .destructive),
                AetherAlertAction(title: "Отмена", style: .secondary)
            ]
        )
        present(alert, animated: false)
    }

    private func showWithField() {
        let alert = AetherAlertController(
            title: "Переименовать",
            message: "Введите новое имя файла.",
            actions: [
                AetherAlertAction(title: "Отмена", style: .secondary),
                AetherAlertAction(title: "Сохранить", style: .primary)
            ],
            textFields: [
                AetherAlertTextField(label: "Имя", placeholder: "filename.txt", onChanged: { _ in })
            ],
            theme: .system
        )
        present(alert, animated: false)
    }

    private func showWithTwoFields() {
        let alert = AetherAlertController(
            title: "Войти в аккаунт",
            message: "Введите логин и пароль.",
            actions: [
                AetherAlertAction(title: "Отмена", style: .secondary),
                AetherAlertAction(title: "Войти", style: .primary)
            ],
            textFields: [
                AetherAlertTextField(label: "Логин", placeholder: "email@example.com", keyboardType: .emailAddress),
                AetherAlertTextField(label: "Пароль", placeholder: "********", isSecureTextEntry: true)
            ],
            theme: .system
        )
        present(alert, animated: false)
    }
}

// MARK: - ActionSheet

final class ActionSheetDemoController: DemoController {
    override var demoTitle: String { "ActionSheet" }

    override func buildDemo() {
        addButton("3 кнопки") { [weak self] in self?.showButtonsOnly() }
        addButton("С заголовком + Destructive") { [weak self] in self?.showWithHeader() }
        addButton("Checkbox + Switch mix") { [weak self] in self?.showMixed() }
    }

    private func showButtonsOnly() {
        let sheet = AetherActionSheetController(theme: .light)
        sheet.setItemGroups([
            AetherActionSheetItemGroup(items: [
                AetherActionSheetButtonItem(title: "Действие 1", action: { [weak sheet] in sheet?.dismissAnimated() }),
                AetherActionSheetButtonItem(title: "Действие 2", action: { [weak sheet] in sheet?.dismissAnimated() }),
                AetherActionSheetButtonItem(title: "Действие 3", action: { [weak sheet] in sheet?.dismissAnimated() })
            ]),
            AetherActionSheetItemGroup(items: [
                AetherActionSheetButtonItem(title: "Отмена", font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })
            ])
        ])
        present(sheet, animated: false)
    }

    private func showWithHeader() {
        let sheet = AetherActionSheetController(theme: .light)
        sheet.setItemGroups([
            AetherActionSheetItemGroup(items: [
                AetherActionSheetTextItem(title: "Удалить запись? Это действие необратимо."),
                AetherActionSheetButtonItem(title: "Удалить", color: .destructive, action: { [weak sheet] in sheet?.dismissAnimated() })
            ]),
            AetherActionSheetItemGroup(items: [
                AetherActionSheetButtonItem(title: "Отмена", font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })
            ])
        ])
        present(sheet, animated: false)
    }

    private func showMixed() {
        let sheet = AetherActionSheetController(theme: .light)
        sheet.setItemGroups([
            AetherActionSheetItemGroup(items: [
                AetherActionSheetCheckboxItem(title: "Опция A", value: true, action: { _ in }),
                AetherActionSheetCheckboxItem(title: "Опция B", value: false, action: { _ in }),
                AetherActionSheetSwitchItem(title: "Уведомления", isOn: true, action: { _ in })
            ]),
            AetherActionSheetItemGroup(items: [
                AetherActionSheetButtonItem(title: "Готово", font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })
            ])
        ])
        present(sheet, animated: false)
    }
}

// MARK: - Toolbar

final class ToolbarDemoController: DemoController {
    override var demoTitle: String { "Floating Toolbar" }

    private enum Variant: Int, CaseIterable {
        case threeStandalone, searchOnly, searchWithClose, scanPlusSearch, safariNav

        var title: String {
            switch self {
            case .threeStandalone: return "3 standalone"
            case .searchOnly: return "Search"
            case .searchWithClose: return "Search + close"
            case .scanPlusSearch: return "Scan + search"
            case .safariNav: return "Safari nav pill"
            }
        }
    }

    override func buildDemo() {
        addLabel("Тулбар прикреплён к низу экрана. Переключатели ниже.")
        for variant in Variant.allCases {
            addButton(variant.title) { [weak self] in
                self?.floatingToolbar = self?.makeToolbar(for: variant)
            }
        }
        floatingToolbar = makeToolbar(for: .safariNav)
    }

    private func makeToolbar(for variant: Variant) -> AetherFloatingToolbarView {
        let scan = UIImage(systemName: "viewfinder")
        let back = UIImage(systemName: "chevron.left")
        let forward = UIImage(systemName: "chevron.right")
        let share = UIImage(systemName: "square.and.arrow.up")
        let bookmark = UIImage(systemName: "bookmark")
        let compass = UIImage(systemName: "safari")
        let toast: (String) -> Void = { AetherToastController(content: .text($0)).present() }

        switch variant {
        case .threeStandalone:
            return AetherFloatingToolbarView(segments: [
                .standalone(.init(icon: scan, action: { toast("scan 1") })),
                .standalone(.init(icon: scan, action: { toast("scan 2") })),
                .standalone(.init(icon: scan, action: { toast("scan 3") }))
            ])
        case .searchOnly:
            return AetherFloatingToolbarView(segments: [
                .search(.init(placeholder: "Search", onTextChanged: { toast("query: \($0)") }))
            ])
        case .searchWithClose:
            return AetherFloatingToolbarView(segments: [
                .search(.init(placeholder: "Search", showsCloseButton: true, onClose: { toast("closed") }))
            ])
        case .scanPlusSearch:
            return AetherFloatingToolbarView(segments: [
                .standalone(.init(icon: scan, action: { toast("scan") })),
                .search(.init(placeholder: "Search"))
            ])
        case .safariNav:
            return AetherFloatingToolbarView(segments: [
                .pill([
                    .init(icon: back, action: { toast("back") }),
                    .init(icon: forward, isEnabled: false, action: {}),
                    .init(icon: share, action: { toast("share") }),
                    .init(icon: bookmark, action: { toast("bookmark") }),
                    .init(icon: compass, action: { toast("compass") })
                ])
            ])
        }
    }
}

// MARK: - Tooltip

final class TooltipDemoController: DemoController {
    override var demoTitle: String { "Tooltip" }

    private weak var textSource: UIView?
    private weak var iconSource: UIView?
    private weak var attrSource: UIView?

    override func buildDemo() {
        textSource = addButton("Текст") { [weak self] in
            guard let self, let src = self.textSource else { return }
            self.present(from: src, content: .text("Подсказка о первой кнопке"))
        }
        iconSource = addButton("Иконка + текст") { [weak self] in
            guard let self, let src = self.iconSource else { return }
            let icon = UIImage(systemName: "lightbulb.fill") ?? UIImage()
            self.present(from: src, content: .iconAndText(icon, "С иконкой"))
        }
        attrSource = addButton("Attributed") { [weak self] in
            guard let self, let src = self.attrSource else { return }
            let attr = NSMutableAttributedString(
                string: "Нажмите ",
                attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.white]
            )
            attr.append(NSAttributedString(
                string: "кнопку",
                attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: UIColor.white]
            ))
            attr.append(NSAttributedString(
                string: ", чтобы продолжить",
                attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.white]
            ))
            self.present(from: src, content: .attributedText(attr))
        }
    }

    private func present(from view: UIView, content: AetherTooltipContent) {
        AetherTooltipController(content: content, theme: .dark, timeout: 3.0).present(from: view)
    }
}

// MARK: - Context Menu

final class ContextMenuDemoController: DemoController {
    override var demoTitle: String { "Context Menu" }

    private weak var morphAnchor: UIView?
    private weak var previewAnchor: UIView?
    private weak var tapAnchor: UIView?

    override func buildDemo() {
        addLabel("Long-press для morph / preview, tap — открыть меню.")

        morphAnchor = addButton("Morph (long-press)") {}
        if let anchor = morphAnchor {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(morphLongPressed(_:)))
            lp.minimumPressDuration = 0.25
            anchor.addGestureRecognizer(lp)
        }

        previewAnchor = addButton("Preview (long-press)") {}
        if let anchor = previewAnchor {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(previewLongPressed(_:)))
            lp.minimumPressDuration = 0.25
            anchor.addGestureRecognizer(lp)
        }

        tapAnchor = addButton("Tap → меню") { [weak self] in self?.openTapMenu() }
    }

    @objc private func morphLongPressed(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began, let anchor = morphAnchor else { return }
        let menu = ContextMenuController(
            source: ContextMenuController.Source(view: anchor, cornerRadius: anchor.bounds.height / 2),
            items: sampleItems(),
            presentationStyle: .fluidMorph
        )
        menu.present()
    }

    @objc private func previewLongPressed(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began, let anchor = previewAnchor else { return }
        let menu = ContextMenuController(
            source: ContextMenuController.Source(view: anchor, cornerRadius: 14),
            items: sampleItems(),
            presentationStyle: .preview()
        )
        menu.present()
    }

    private func openTapMenu() {
        guard let anchor = tapAnchor else { return }
        let menu = ContextMenuController(
            source: ContextMenuController.Source(view: anchor, cornerRadius: anchor.bounds.height / 2),
            items: sampleItems(),
            presentationStyle: .fluidMorph
        )
        menu.present()
    }

    private func sampleItems() -> [ContextMenuItem] {
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
}

// MARK: - Segmented Control

final class SegmentedDemoController: DemoController {
    override var demoTitle: String { "Segmented Control" }

    override func buildDemo() {
        addLabel("Glass lens-based segmented control.")

        let segments = AetherSegmentedControl(items: [
            .init(title: "First"),
            .init(title: "Second"),
            .init(title: "Third")
        ])
        segments.translatesAutoresizingMaskIntoConstraints = false
        segments.selectedIndexChanged = { index in
            AetherToastController(content: .text("Picked \(index)")).present()
        }
        addCenteredView(segments, height: 44)

        let two = AetherSegmentedControl(items: [
            .init(title: "Day"),
            .init(title: "Night")
        ])
        two.translatesAutoresizingMaskIntoConstraints = false
        addCenteredView(two, height: 44)
    }
}
