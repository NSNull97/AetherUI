import UIKit
import AetherUI

/// Tab 1 root — picker that pushes a demo per row.
func makeComponentsRoot() -> AetherViewController {
    return DemoListController(title: "Components", rows: [
        .init("Navigation + Window", "shared bar / modal nav / global overlay", { NavigationSurfaceDemoController() }),
        .init("Buttons", "UIKit + Glass", { ButtonsDemoController() }),
        .init("Alerts", "single / pair / stacked + поля", { AlertsDemoController() }),
        .init("ActionSheet", "buttons / checkbox / switch", { ActionSheetDemoController() }),
        .init("Floating Toolbar", "pill / standalone / search", { ToolbarDemoController() }),
        .init("Tooltip", "text / icon+text / attributed", { TooltipDemoController() }),
        .init("Context Menu", "morph / preview / submenu", { ContextMenuDemoController() }),
        .init("Slider", "native glass track / thumb", { SliderDemoController() }),
        .init("Segmented Control", "glass lens", { SegmentedDemoController() })
    ])
}

// MARK: - Navigation / Window

final class NavigationSurfaceDemoController: DemoController {
    override var demoTitle: String { "Navigation + Window" }
    private var detailCounter = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "shield"), style: .plain, target: self, action: #selector(navButtonPressed)),
            UIBarButtonItem(image: UIImage(systemName: "plus.circle"), style: .plain, target: self, action: #selector(navButtonPressed)),
            UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), style: .plain, target: self, action: #selector(navButtonPressed))
        ]

        navigationItem.rightBarButtonItems?.first?.separatesSharedBackground = true
        navigationItem.rightBarButtonItems?.last?.separatesSharedBackground = true
    }

    override func buildDemo() {
        addLabel("Shared navigation bar: push/replace/pop use one bar hosted by AetherNavigationController.")
        addButton("Push detail") { [weak self] in self?.pushDetail() }
        addButton("Replace top") { [weak self] in self?.replaceTop() }
        addButton("Present modal navigation") { [weak self] in self?.presentModalNavigation() }
        addButton("Present global overlay") { [weak self] in self?.presentGlobalOverlay() }
        addButton("Show in-call status bar") { [weak self] in self?.showInCallStatusBar() }
        addButton("Toggle proximity dim") { [weak self] in self?.flashProximityDim() }
    }

    private func pushDetail() {
        detailCounter += 1
        let detail = NavigationDetailDemoController(index: detailCounter)
        push(detail)
    }

    private func replaceTop() {
        detailCounter += 1
        let detail = NavigationDetailDemoController(index: detailCounter)
        if let nav = parent as? AetherNavigationController, nav.viewControllerStack.count > 1 {
            nav.replaceTopController(detail, animated: true)
        } else {
            push(detail)
        }
    }

    private func presentModalNavigation() {
        let root = NavigationDetailDemoController(index: 1)
        root.navigationItem.title = "Modal Root"
        let modal = AetherModalNavigationController(
            rootViewController: root,
            config: .init(detents: [.stage1, .stage2], initialDetent: .stage2)
        )
        present(modal, animated: true)
    }

    private func presentGlobalOverlay() {
        let overlay = GlobalOverlayDemoController()
        presentInGlobalOverlay(overlay, animated: true)
    }

    private func showInCallStatusBar() {
        guard let window = view.window as? AetherWindow else { return }
        window.setForceInCallStatusBar("AetherUI active call")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak window] in
            window?.setForceInCallStatusBar(nil)
        }
    }

    private func flashProximityDim() {
        guard let window = view.window as? AetherWindow else { return }
        window.setProximityDimHidden(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak window] in
            window?.setProximityDimHidden(true)
        }
    }

    @objc private func navButtonPressed() {
        AetherToastController(content: .text("Navigation bar button")).present()
    }
}

private final class NavigationDetailDemoController: DemoController {
    private let index: Int
    override var demoTitle: String { "Detail \(index)" }

    init(index: Int) {
        self.index = index
        super.init()
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(navButtonPressed)
        )
    }

    override func buildDemo() {
        topBarAccessory = DetailTopAccessoryView(text: "Shared bar accessory #\(index)")
        addLabel("This screen uses the same NavigationBarImpl instance as the previous screen.")
        addButton("Push next detail") { [weak self] in
            guard let self else { return }
            self.push(NavigationDetailDemoController(index: self.index + 1))
        }
        addButton("Pop to root") { [weak self] in
            (self?.parent as? AetherNavigationController)?.popToRoot(animated: true)
        }
        addButton("Dismiss if modal") { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    @objc private func navButtonPressed() {
        AetherToastController(content: .text("Detail nav button")).present()
    }
}

private final class DetailTopAccessoryView: NavigationBarContentView {
    private let glass = GlassBackgroundView(style: .regular)
    private let label = UILabel()

    override var nominalHeight: CGFloat { 40 }
    override var mode: NavigationBarContentMode { .expansion }

    init(text: String) {
        super.init(frame: .zero)
        addSubview(glass)
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .label
        label.textAlignment = .center
        glass.contentView.addSubview(label)
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds.insetBy(dx: 16, dy: 4)
        glass.update(size: glass.bounds.size, cornerRadius: 16, transition: .immediate)
        label.frame = glass.contentView.bounds
    }
}

private final class GlobalOverlayDemoController: AetherViewController {
    private let card = GlassBackgroundView(style: .regular)
    private let label = UILabel()
    private let close = UIButton(type: .system)

    init() {
        super.init(navigationBarPresentationData: nil)
        displayNavigationBar = false
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        view.addSubview(card)

        label.text = "Global overlay"
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textAlignment = .center
        card.contentView.addSubview(label)

        close.setTitle("Dismiss", for: .normal)
        close.addAction(UIAction { [weak self] _ in
            guard let self, let window = self.view.window as? AetherWindow else { return }
            window.dismissGlobalOverlay(self, animated: true)
        }, for: .touchUpInside)
        card.contentView.addSubview(close)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = min(320, view.bounds.width - 48)
        card.frame = CGRect(
            x: floor((view.bounds.width - width) / 2),
            y: floor((view.bounds.height - 150) / 2),
            width: width,
            height: 150
        )
        card.update(size: card.bounds.size, cornerRadius: 26, transition: .immediate)
        label.frame = CGRect(x: 16, y: 28, width: card.bounds.width - 32, height: 30)
        close.frame = CGRect(x: 16, y: 86, width: card.bounds.width - 32, height: 44)
    }
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
        glassBar.contentTintColor = .secondaryLabel
        glassBar.action = { button in
            let menu = ContextMenuController(
                source: ContextMenuController.Source(view: button, cornerRadius: button.bounds.height / 2),
                items: self.sampleItems(),
                presentationStyle: .fluidMorph
            )
            menu.present()
        }
        addCenteredView(glassBar, height: 44)

        addLabel("Tinted glass:")
        let tinted = GlassBarButtonView(
            icon: UIImage(systemName: "wand.and.stars"),
            title: "Tinted Glass",
            state: .tintedGlass
        )
        tinted.tintColor = .systemBlue
        tinted.action = { button in
            let menu = ContextMenuController(
                source: ContextMenuController.Source(view: button, cornerRadius: button.bounds.height / 2),
                items: self.sampleItems(),
                presentationStyle: .morph
            )
            menu.present()
        }
        addCenteredView(tinted, height: 44)
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

// MARK: - Alerts

final class AlertsDemoController: DemoController {
    override var demoTitle: String { "Alerts" }

    override func buildDemo() {
        addButton("Single — Primary OK") { [weak self] in self?.showSingle() }
        addButton("Pair — Secondary + Primary") { [weak self] in self?.showPair() }
        addButton("Stacked — Primary / Destructive / Secondary") { [weak self] in self?.showStacked() }
        addButton("1 поле ввода") { [weak self] in self?.showWithField() }
        addButton("2 поля (login / password)") { [weak self] in self?.showWithTwoFields() }
        addButton("Custom content + willDismiss") { [weak self] in self?.showCustomContent() }
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

    private func showCustomContent() {
        let slider = UISlider()
        slider.value = 0.65
        let alert = AetherAlertController(
            title: "Custom content",
            message: "Alert can host an arbitrary UIKit view between text and actions.",
            actions: [
                AetherAlertAction(title: "Cancel", style: .secondary),
                AetherAlertAction(title: "Apply", style: .primary)
            ],
            customContentView: slider,
            theme: .system
        )
        alert.willDismiss = { cancelled in
            AetherToastController(content: .text(cancelled ? "Will dismiss: outside/cancel" : "Will dismiss: action")).present()
        }
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
        addButton("Markdown text + overlay") { [weak self] in self?.showMarkdownOverlay() }
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
                AetherActionSheetTextItem(title: "**Удалить запись?** Это действие необратимо.", parseMarkdown: true),
                AetherActionSheetButtonItem(title: "Удалить", color: .destructive, action: { [weak sheet] in sheet?.dismissAnimated() })
            ]),
            AetherActionSheetItemGroup(items: [
                AetherActionSheetButtonItem(title: "Отмена", font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })
            ])
        ])
        present(sheet, animated: false)
    }

    private func showMarkdownOverlay() {
        let sheet = AetherActionSheetController(theme: .light)
        sheet.setItemGroups([
            AetherActionSheetItemGroup(items: [
                AetherActionSheetTextItem(title: "**Markdown** text item with an overlay badge.", font: .large, parseMarkdown: true),
                AetherActionSheetButtonItem(title: "Confirm", action: { [weak sheet] in sheet?.dismissAnimated() })
            ]),
            AetherActionSheetItemGroup(items: [
                AetherActionSheetButtonItem(title: "Cancel", font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })
            ])
        ])

        let badge = UILabel()
        badge.text = "overlay"
        badge.textAlignment = .center
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .white
        badge.backgroundColor = .systemBlue
        badge.layer.cornerRadius = 12
        badge.layer.masksToBounds = true
        let host = UIView()
        host.isUserInteractionEnabled = false
        host.addSubview(badge)
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: host.topAnchor, constant: 10),
            badge.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -10),
            badge.widthAnchor.constraint(equalToConstant: 68),
            badge.heightAnchor.constraint(equalToConstant: 24)
        ])
        sheet.setItemGroupOverlayView(groupIndex: 0, view: host)
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

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gear"),
            primaryAction: UIAction { _ in
                AetherToastController(content: .text("Navbar button")).present()
            },
            contextMenuItemsProvider: { [weak self] in
                self?.sampleItems() ?? []
            }
        )
    }

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

// MARK: - Slider

final class SliderDemoController: DemoController {
    override var demoTitle: String { "Slider" }

    private let valueLabel = UILabel()

    override func buildDemo() {
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        valueLabel.textAlignment = .center
        valueLabel.textColor = .label
        valueLabel.text = "64%"
        stack.addArrangedSubview(valueLabel)

        addGlassSlider(title: "Default", value: 0.64, tint: .systemBlue)
        addGlassSlider(title: "Warm tint", value: 0.35, tint: .systemOrange)
        addGlassSlider(title: "Compact", value: 0.82, tint: .systemGreen, trackHeight: 26, thumbSize: CGSize(width: 38, height: 32))

        addLabel("Disabled")
        let disabled = AetherSlider(value: 0.48, theme: .init(minimumTrackTintColor: .systemPurple))
        disabled.isEnabled = false
        addSliderView(disabled)
    }

    private func addGlassSlider(
        title: String,
        value: Float,
        tint: UIColor,
        trackHeight: CGFloat = 32,
        thumbSize: CGSize = CGSize(width: 44, height: 38)
    ) {
        addLabel(title)
        let slider = AetherSlider(value: value, theme: .init(minimumTrackTintColor: tint))
        slider.trackHeight = trackHeight
        slider.thumbSize = thumbSize
        slider.valueChanged = { [weak self] value in
            self?.valueLabel.text = "\(Int(round(value * 100)))%"
        }
        slider.addAction(UIAction { [weak self, weak slider] _ in
            guard let slider else { return }
            self?.valueLabel.text = "\(Int(round(slider.value * 100)))%"
        }, for: .valueChanged)
        addSliderView(slider)
    }

    private func addSliderView(_ slider: AetherSlider) {
        slider.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(slider)
        slider.heightAnchor.constraint(equalToConstant: 54).isActive = true
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
