import UIKit
import AetherUI

/// Tab 1 root — picker that pushes a demo per row.
func makeComponentsRoot() -> AetherViewController {
    return DemoListController(title: "Components", rows: [
        .init("Navigation + Window", "shared bar / modal nav / global overlay", { NavigationSurfaceDemoController() }),
        .init("Window Runtime", "overlays / keyboard / portal / child host", { AetherWindowRuntimeDemoController() }),
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
    private weak var modalSourceButton: UIButton?

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
        modalSourceButton = addButton("Present modal navigation") { [weak self] in self?.presentModalNavigation() }
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
        if let modalSourceButton {
            modal.useSourceTransition(from: modalSourceButton)
        }
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

final class AetherWindowRuntimeDemoController: DemoController {
    override var demoTitle: String { "Window Runtime" }

    private let portalSource = AetherPortalSourceView()
    private let childHost = AetherChildWindowHostView()
    private let composer = UITextField()
    private var lightStatusBar = false
    private var deferEdges = false
    private var hideHomeIndicator = false

    override var prefersHomeIndicatorAutoHidden: Bool {
        hideHomeIndicator
    }

    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        deferEdges ? [.bottom] : []
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installComposer()
    }

    override func buildDemo() {
        addLabel("AetherNativeWindow runtime: presentation levels, global overlays, system UI invalidation, keyboard-aware layout, portal fallback, and embedded child host.")
        addButton("Present level overlay") { [weak self] in self?.presentLevelOverlay() }
        addButton("Present global overlay") { [weak self] in self?.presentRuntimeGlobalOverlay() }
        addButton("Toggle status bar style") { [weak self] in self?.toggleStatusBar() }
        addButton("Toggle home indicator") { [weak self] in self?.toggleHomeIndicator() }
        addButton("Toggle bottom edge deferral") { [weak self] in self?.toggleScreenEdgeDeferral() }
        addButton("Focus keyboard composer") { [weak self] in self?.composer.becomeFirstResponder() }
        addButton("Toggle source global portal") { [weak self] in self?.togglePortal() }

        portalSource.backgroundColor = .systemTeal
        portalSource.layer.cornerRadius = 12
        portalSource.accessibilityLabel = "Portal source"
        addCenteredView(portalSource, height: 56)
        portalSource.widthAnchor.constraint(equalToConstant: 160).isActive = true

        childHost.layer.borderColor = UIColor.separator.cgColor
        childHost.layer.borderWidth = 1
        childHost.layer.cornerRadius = 12
        addCenteredView(childHost, height: 120)
        childHost.widthAnchor.constraint(equalToConstant: 260).isActive = true
        installChildHostContent()
    }

    private func installComposer() {
        composer.placeholder = "Keyboard runtime composer"
        composer.borderStyle = .roundedRect
        composer.returnKeyType = .done
        composer.delegate = self
        inputBarAccessoryView = composer
        setInputBarAccessoryReservedHeight(52)
    }

    private func installChildHostContent() {
        let label = UILabel()
        label.text = "Child host"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.frame = CGRect(x: 0, y: 16, width: 260, height: 24)
        childHost.addSubview(label)

        let button = UIButton(type: .system)
        button.setTitle("Present local", for: .normal)
        button.frame = CGRect(x: 40, y: 58, width: 180, height: 42)
        button.addAction(UIAction { [weak self] _ in
            self?.presentChildOverlay()
        }, for: .touchUpInside)
        childHost.addSubview(button)
    }

    private func presentLevelOverlay() {
        let controller = RuntimeOverlayController(title: "Level overlay", backgroundAlpha: 0.22)
        if let window = view.window as? AetherWindowHost {
            window.present(controller, on: .overlay, blockInteraction: true) {}
        } else {
            present(controller, animated: true)
        }
    }

    private func presentRuntimeGlobalOverlay() {
        let controller = RuntimeOverlayController(title: "Global overlay", backgroundAlpha: 0.18)
        if let window = view.window as? AetherWindow {
            window.presentInGlobalOverlay(controller, animated: true)
        }
    }

    private func presentChildOverlay() {
        let controller = RuntimeOverlayController(title: "Local child overlay", backgroundAlpha: 0.12)
        controller.onDismiss = { [weak childHost, weak controller] in
            guard let controller else { return }
            childHost?.presentationContext.dismiss(controller)
        }
        childHost.present(controller, on: .overlay, blockInteraction: true) {}
    }

    private func toggleStatusBar() {
        lightStatusBar.toggle()
        statusBarStyle = lightStatusBar ? .lightContent : .default
        (view.window as? AetherWindow)?.updateStatusBar(style: statusBarStyle, hidden: false, transition: .animated(duration: 0.2, curve: .easeInOut))
    }

    private func toggleHomeIndicator() {
        hideHomeIndicator.toggle()
        view.window?.setNeedsLayout()
        (view.window as? AetherWindow)?.invalidatePrefersOnScreenNavigationHidden()
    }

    private func toggleScreenEdgeDeferral() {
        deferEdges.toggle()
        (view.window as? AetherWindow)?.invalidateDeferScreenEdgeGestures()
    }

    private func togglePortal() {
        portalSource.needsGlobalPortal.toggle()
    }
}

extension AetherWindowRuntimeDemoController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

private final class RuntimeOverlayController: AetherViewController {
    private let titleText: String
    private let backgroundAlpha: CGFloat
    private let card = GlassBackgroundView(style: .regular)
    private let label = UILabel()
    private let close = UIButton(type: .system)
    var onDismiss: (() -> Void)?

    init(title: String, backgroundAlpha: CGFloat) {
        self.titleText = title
        self.backgroundAlpha = backgroundAlpha
        super.init(navigationBarPresentationData: nil)
        displayNavigationBar = false
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(backgroundAlpha)
        view.addSubview(card)
        label.text = titleText
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        card.contentView.addSubview(label)
        close.setTitle("Dismiss", for: .normal)
        close.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if let onDismiss = self.onDismiss {
                onDismiss()
                return
            }
            if let window = self.view.window as? AetherWindow {
                window.dismissGlobalOverlay(self, animated: true)
            } else {
                self.view.removeFromSuperview()
                self.removeFromParent()
            }
        }, for: .touchUpInside)
        card.contentView.addSubview(close)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = min(300, view.bounds.width - 48)
        card.frame = CGRect(x: (view.bounds.width - width) * 0.5, y: (view.bounds.height - 140) * 0.5, width: width, height: 140)
        card.update(size: card.bounds.size, cornerRadius: 24, transition: .immediate)
        label.frame = CGRect(x: 16, y: 28, width: card.bounds.width - 32, height: 28)
        close.frame = CGRect(x: 16, y: 82, width: card.bounds.width - 32, height: 42)
    }
}

// MARK: - Buttons

final class ButtonsDemoController: DemoController {
    override var demoTitle: String { "Buttons" }
    private var attachmentMenuController: AetherAttachmentMenuController?

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

        addLabel("Attachment morph:")
        let composer = AttachmentComposerDemoView()
        composer.onPlusTap = { [weak self, weak composer] button in
            guard let self else { return }
            let menu = AetherAttachmentMenuController(items: [
                .init(title: "Камера", icon: UIImage(systemName: "camera")) {
                    AetherToastController(content: .text("Camera")).present()
                },
                .init(title: "Фото", icon: UIImage(systemName: "photo")) {
                    AetherToastController(content: .text("Photo")).present()
                },
                .init(title: "Файлы", icon: UIImage(systemName: "paperclip")) {
                    AetherToastController(content: .text("Files")).present()
                },
                .init(title: "Плагины", icon: UIImage(systemName: "link.circle")) {
                    AetherToastController(content: .text("Plugins")).present()
                }
            ])
            menu.onDismiss = { [weak self, weak menu, weak composer] in
                if let menu, self?.attachmentMenuController === menu {
                    self?.attachmentMenuController = nil
                }
                composer?.setPlusSelected(false)
            }
            self.attachmentMenuController = menu
            menu.present(from: button, in: self.view)
            composer?.setPlusSelected(true)
        }
        composer.onMenuDismissRequest = { [weak self, weak composer] in
            self?.attachmentMenuController?.dismiss()
            composer?.setPlusSelected(false)
        }
        stack.addArrangedSubview(composer)
        composer.heightAnchor.constraint(equalToConstant: 118).isActive = true
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

private final class AttachmentComposerDemoView: UIView {
    var onPlusTap: ((UIView) -> Void)?
    var onMenuDismissRequest: (() -> Void)?

    private let plusButton = GlassBarButtonView(
        icon: UIImage(systemName: "plus"),
        title: nil,
        state: .glass
    )
    private let inputPill = GlassBackgroundView(style: .regular)
    private let placeholderLabel = UILabel()
    private let stopButton = UIButton(type: .custom)
    private var isPlusSelected = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .clear

        plusButton.contentTintColor = .label
        plusButton.action = { [weak self] button in
            guard let self else { return }
            if self.isPlusSelected {
                self.onMenuDismissRequest?()
            } else {
                self.onPlusTap?(button)
            }
        }
        addSubview(plusButton)

        addSubview(inputPill)

        placeholderLabel.text = "Спросить ChatGPT"
        placeholderLabel.font = .systemFont(ofSize: 22, weight: .regular)
        placeholderLabel.textColor = .tertiaryLabel
        inputPill.contentView.addSubview(placeholderLabel)

        stopButton.backgroundColor = .label
        stopButton.tintColor = .systemBackground
        stopButton.setImage(UIImage(systemName: "square.fill"), for: .normal)
        stopButton.layer.cornerRadius = 24
        stopButton.layer.cornerCurve = .continuous
        inputPill.contentView.addSubview(stopButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let safeWidth = bounds.width
        let buttonSide: CGFloat = 58
        let bottomInset: CGFloat = 16
        let y = bounds.height - bottomInset - buttonSide
        plusButton.frame = CGRect(x: 0, y: y, width: buttonSide, height: buttonSide)
        plusButton.layer.cornerRadius = buttonSide * 0.5

        inputPill.frame = CGRect(
            x: buttonSide + 12,
            y: y,
            width: max(0, safeWidth - buttonSide - 12),
            height: buttonSide
        )
        inputPill.update(size: inputPill.bounds.size, cornerRadius: buttonSide * 0.5, transition: .immediate)

        let stopSide: CGFloat = 48
        stopButton.frame = CGRect(
            x: inputPill.bounds.width - stopSide - 5,
            y: (inputPill.bounds.height - stopSide) * 0.5,
            width: stopSide,
            height: stopSide
        )
        stopButton.layer.cornerRadius = stopSide * 0.5

        placeholderLabel.frame = CGRect(
            x: 20,
            y: 0,
            width: max(0, stopButton.frame.minX - 32),
            height: inputPill.bounds.height
        )
    }

    func setPlusSelected(_ selected: Bool) {
        isPlusSelected = selected
        UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.plusButton.transform = selected ? CGAffineTransform(rotationAngle: .pi / 4) : .identity
        }
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
    private weak var gooeyAnchor: UIView?
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
        addLabel("Long-press для morph / gooey / preview, tap — открыть меню.")

        morphAnchor = addButton("Morph (long-press)") {}
        if let anchor = morphAnchor {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(morphLongPressed(_:)))
            lp.minimumPressDuration = 0.25
            anchor.addGestureRecognizer(lp)
        }

        gooeyAnchor = addButton("Gooey (long-press)") {}
        if let anchor = gooeyAnchor {
            let lp = UILongPressGestureRecognizer(target: self, action: #selector(gooeyLongPressed(_:)))
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

    @objc private func gooeyLongPressed(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began, let anchor = gooeyAnchor else { return }
        let menu = ContextMenuController(
            source: ContextMenuController.Source(view: anchor, cornerRadius: anchor.bounds.height / 2),
            items: sampleItems(),
            presentationStyle: .gooey()
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
            presentationStyle: .gooey()
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
