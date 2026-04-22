import UIKit
import CrystalUI

// MARK: - Common base

/// Base controller that wires a vertical stack of buttons + optional
/// container area above. Each button's tap invokes its handler — used
/// by every demo screen below.
class ShowcaseDemoController: ViewController {
    let stack = UIStackView()
    let scrollView = UIScrollView()

    /// Overridden by subclasses to set nav-bar title.
    var demoTitle: String { "Demo" }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = demoTitle
        view.backgroundColor = .systemBackground

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.alwaysBounceVertical = true
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
        var insets = layout.safeInsets
        insets.top = navigationBarView?.frame.maxY ?? insets.top
        scrollView.contentInset = insets
        scrollView.scrollIndicatorInsets = insets
    }

    /// Subclasses add buttons here via `addButton`.
    func buildDemo() {}

    @discardableResult
    func addButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.cornerStyle = .large
        let handler = UIAction { _ in action() }
        let button = UIButton(configuration: config, primaryAction: handler)
        stack.addArrangedSubview(button)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
    }

    func addPaddedView(_ view: UIView, height: CGFloat) {
        let container = UIView()
        container.heightAnchor.constraint(equalToConstant: height).isActive = true
        container.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        stack.addArrangedSubview(container)
    }
}

// MARK: - ActionSheet

final class ActionSheetDemoController: ShowcaseDemoController {
    override var demoTitle: String { "ActionSheet" }

    override func buildDemo() {
        addButton("3 кнопки (buttons only)") { [weak self] in
            self?.showButtonsOnly()
        }
        addButton("С заголовком + Destructive") { [weak self] in
            self?.showWithHeader()
        }
        addButton("Checkbox + Switch mix") { [weak self] in
            self?.showMixed()
        }
    }

    private func showButtonsOnly() {
        let sheet = CrystalActionSheetController(theme: .light)
        sheet.setItemGroups([
            CrystalActionSheetItemGroup(items: [
                CrystalActionSheetButtonItem(title: "Действие 1", action: { [weak sheet] in sheet?.dismissAnimated() }),
                CrystalActionSheetButtonItem(title: "Действие 2", action: { [weak sheet] in sheet?.dismissAnimated() }),
                CrystalActionSheetButtonItem(title: "Действие 3", action: { [weak sheet] in sheet?.dismissAnimated() })
            ]),
            CrystalActionSheetItemGroup(items: [
                CrystalActionSheetButtonItem(title: "Отмена", font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })
            ])
        ])
        present(sheet, animated: false)
    }

    private func showWithHeader() {
        let sheet = CrystalActionSheetController(theme: .light)
        sheet.setItemGroups([
            CrystalActionSheetItemGroup(items: [
                CrystalActionSheetTextItem(title: "Удалить запись? Это действие необратимо."),
                CrystalActionSheetButtonItem(title: "Удалить", color: .destructive, action: { [weak sheet] in sheet?.dismissAnimated() })
            ]),
            CrystalActionSheetItemGroup(items: [
                CrystalActionSheetButtonItem(title: "Отмена", font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })
            ])
        ])
        present(sheet, animated: false)
    }

    private func showMixed() {
        let sheet = CrystalActionSheetController(theme: .light)
        sheet.setItemGroups([
            CrystalActionSheetItemGroup(items: [
                CrystalActionSheetCheckboxItem(title: "Опция A", value: true, action: { _ in }),
                CrystalActionSheetCheckboxItem(title: "Опция B", value: false, action: { _ in }),
                CrystalActionSheetSwitchItem(title: "Уведомления", isOn: true, action: { _ in })
            ]),
            CrystalActionSheetItemGroup(items: [
                CrystalActionSheetButtonItem(title: "Готово", font: .bold, action: { [weak sheet] in sheet?.dismissAnimated() })
            ])
        ])
        present(sheet, animated: false)
    }
}

// MARK: - Alert

final class AlertDemoController: ShowcaseDemoController {
    override var demoTitle: String { "Alert" }

    override func buildDemo() {
        addButton("Single — Primary OK") { [weak self] in self?.showSingle() }
        addButton("Pair — Secondary + Primary") { [weak self] in self?.showPair() }
        addButton("Stacked — Primary / Destructive / Secondary") { [weak self] in self?.showStacked() }
        addButton("1 поле ввода") { [weak self] in self?.showWithField() }
        addButton("2 поля ввода (login/password)") { [weak self] in self?.showWithTwoFields() }
    }

    private func showSingle() {
        let alert = CrystalAlertController(
            title: "A Short Title Is Best",
            message: "A description should be a short, complete sentence.",
            actions: [CrystalAlertAction(title: "OK", style: .primary)]
        )
        present(alert, animated: false)
    }

    private func showPair() {
        let alert = CrystalAlertController(
            title: "A Short Title Is Best",
            message: "A description should be a short, complete sentence.",
            actions: [
                CrystalAlertAction(title: "Secondary", style: .secondary),
                CrystalAlertAction(title: "Primary", style: .primary)
            ]
        )
        present(alert, animated: false)
    }

    private func showStacked() {
        let alert = CrystalAlertController(
            title: "A Short Title Is Best",
            message: "A description should be a short, complete sentence.",
            actions: [
                CrystalAlertAction(title: "Primary", style: .primary),
                CrystalAlertAction(title: "Destructive", style: .destructive),
                CrystalAlertAction(title: "Secondary", style: .secondary)
            ]
        )
        present(alert, animated: false)
    }

    private func showWithField() {
        let alert = CrystalAlertController(
            title: "A Short Title Is Best",
            message: "A description should be a short, complete sentence.",
            actions: [
                CrystalAlertAction(title: "Primary", style: .primary),
                CrystalAlertAction(title: "Destructive", style: .destructive),
                CrystalAlertAction(title: "Secondary", style: .secondary)
            ],
            textFields: [
                CrystalAlertTextField(
                    label: "Value",
                    placeholder: "Value",
                    onChanged: { _ in }
                )
            ],
            theme: .system
        )
        present(alert, animated: false)
    }

    private func showWithTwoFields() {
        let alert = CrystalAlertController(
            title: "Войти в аккаунт",
            message: "Введите логин и пароль.",
            actions: [
                CrystalAlertAction(title: "Отмена", style: .secondary),
                CrystalAlertAction(title: "Войти", style: .primary)
            ],
            textFields: [
                CrystalAlertTextField(label: "Логин", placeholder: "email@example.com", keyboardType: .emailAddress),
                CrystalAlertTextField(label: "Пароль", placeholder: "********", isSecureTextEntry: true)
            ],
            theme: .system
        )
        present(alert, animated: false)
    }
}

// MARK: - Tooltip

final class TooltipDemoController: ShowcaseDemoController {
    override var demoTitle: String { "Tooltip" }
    private weak var lastTip: CrystalTooltipController?

    /// Weak refs to the per-row source buttons so the handler closures can
    /// pass them as the tooltip `from:` argument without walking the stack
    /// hierarchy (which would race layout on first tap).
    private weak var textSource: UIView?
    private weak var iconSource: UIView?
    private weak var attrSource: UIView?

    override func buildDemo() {
        let b1 = addButton("Текст") { [weak self] in
            guard let self, let src = self.textSource else { return }
            self.lastTip = self.presentTip(from: src, content: .text("Подсказка о первой кнопке"))
        }
        textSource = b1

        let b2 = addButton("Иконка + текст") { [weak self] in
            guard let self, let src = self.iconSource else { return }
            let icon = UIImage(systemName: "lightbulb.fill") ?? UIImage()
            self.lastTip = self.presentTip(from: src, content: .iconAndText(icon, "С иконкой"))
        }
        iconSource = b2

        let b3 = addButton("Attributed") { [weak self] in
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
            self.lastTip = self.presentTip(from: src, content: .attributedText(attr))
        }
        attrSource = b3
    }

    private func presentTip(from view: UIView, content: CrystalTooltipContent) -> CrystalTooltipController {
        let tip = CrystalTooltipController(content: content, theme: .dark, timeout: 3.0)
        tip.present(from: view)
        return tip
    }
}

// MARK: - Toast

final class ToastDemoController: ShowcaseDemoController {
    override var demoTitle: String { "Toast" }

    override func buildDemo() {
        addButton("Просто текст") {
            CrystalToastController(content: .text("Сообщение отправлено")).present()
        }
        addButton("Иконка + текст") {
            let icon = UIImage(systemName: "checkmark.circle.fill") ?? UIImage()
            CrystalToastController(content: .iconAndText(icon, "Сохранено в избранное")).present()
        }
        addButton("Текст + Undo action") { [weak self] in
            CrystalToastController(
                content: .textAndAction(
                    "Сообщение удалено",
                    CrystalToastAction(title: "Undo") {
                        let alert = CrystalAlertController(title: "Undo нажат", message: nil, actions: [CrystalAlertAction(title: "OK", style: .defaultFocused)])
                        self?.present(alert, animated: false)
                    }
                ),
                timeout: 5.0
            ).present()
        }
        addButton("Иконка + текст + action") {
            let icon = UIImage(systemName: "trash.fill") ?? UIImage()
            CrystalToastController(
                content: .iconTextAndAction(
                    icon,
                    "3 чата удалены",
                    CrystalToastAction(title: "Undo") {}
                ),
                timeout: 5.0
            ).present()
        }
    }
}

// MARK: - Content state

final class ContentStateDemoController: ShowcaseDemoController {
    override var demoTitle: String { "Content State" }
    private let stateView = CrystalContentStateView(theme: .light)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(stateView)
        stateView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stateView.topAnchor.constraint(equalTo: view.topAnchor),
            stateView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func buildDemo() {
        addButton("Loading") { [weak self] in
            self?.stateView.setState(.loading(message: "Загружаем данные..."), animated: true)
        }
        addButton("Empty") { [weak self] in
            self?.stateView.setState(.empty(
                icon: UIImage(systemName: "tray"),
                title: "Здесь пока пусто",
                message: "Добавьте первую запись, чтобы она появилась тут",
                action: CrystalContentStateAction(title: "Добавить") {}
            ), animated: true)
        }
        addButton("Error + Retry") { [weak self] in
            self?.stateView.setState(.error(
                title: "Не удалось загрузить",
                message: "Проверьте соединение и попробуйте ещё раз",
                action: CrystalContentStateAction(title: "Повторить") {}
            ), animated: true)
        }
        addButton("Скрыть (idle)") { [weak self] in
            self?.stateView.setState(.idle, animated: true)
        }
    }
}

// MARK: - Skeleton

final class SkeletonDemoController: ShowcaseDemoController {
    override var demoTitle: String { "Skeletons" }

    override func buildDemo() {
        for _ in 0..<3 {
            addSkeletonRow()
        }
        let block = CrystalSkeletonBlockView(theme: .light)
        block.cornerRadius = 14
        addPaddedView(block, height: 120)
    }

    private func addSkeletonRow() {
        let row = UIView()
        let avatar = CrystalSkeletonCircleView(theme: .light)
        let line1 = CrystalSkeletonLineView(theme: .light)
        line1.lineHeight = 12
        let line2 = CrystalSkeletonLineView(theme: .light)
        line2.lineHeight = 10

        [avatar, line1, line2].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            avatar.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 44),
            avatar.heightAnchor.constraint(equalToConstant: 44),

            line1.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            line1.topAnchor.constraint(equalTo: avatar.topAnchor, constant: 4),
            line1.heightAnchor.constraint(equalToConstant: 12),
            line1.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -60),

            line2.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            line2.topAnchor.constraint(equalTo: line1.bottomAnchor, constant: 8),
            line2.heightAnchor.constraint(equalToConstant: 10),
            line2.widthAnchor.constraint(equalToConstant: 120)
        ])
        addPaddedView(row, height: 56)
    }
}

// MARK: - Modal

final class ModalDemoController: ShowcaseDemoController {
    override var demoTitle: String { "Modal" }

    override func buildDemo() {
        addButton("Single-detent sheet") { [weak self] in self?.presentSingle() }
        addButton("Dual-detent sheet (half/full)") { [weak self] in self?.presentDual() }
        addButton("Sheet со scroll-content") { [weak self] in self?.presentScrollable() }
    }

    private func presentSingle() {
        let content = SimpleModalContent(title: "Одно положение",
                                         message: "Swipe вниз — закроется")
        let modal = CrystalModalController(content: content)
        present(modal, animated: true)
    }

    private func presentDual() {
        let content = SimpleModalContent(title: "Два detent",
                                         message: "Потяни выше — полный экран; потяни ниже — половина.")
        let modal = CrystalModalController(content: content)
        present(modal, animated: true)
    }

    private func presentScrollable() {
        let content = ScrollableModalContent()
        let modal = CrystalModalController(content: content)
        modal.primaryScrollView = content.scrollView
        present(modal, animated: true)
    }
}

private final class SimpleModalContent: UIViewController {
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()

    init(title: String, message: String) {
        super.init(nibName: nil, bundle: nil)
        titleLabel.text = title
        messageLabel.text = message
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textAlignment = .center
        messageLabel.textColor = .secondaryLabel
        messageLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
    }
}

private final class ScrollableModalContent: UIViewController {
    let scrollView = UIScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -40)
        ])

        for i in 1...30 {
            let label = UILabel()
            label.font = .systemFont(ofSize: 15)
            label.textColor = .label
            label.text = "Строка #\(i) — демонстрация scroll yielding в модалке"
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }
    }
}

// MARK: - Toolbar

final class ToolbarDemoController: ShowcaseDemoController {
    override var demoTitle: String { "Toolbar" }

    private let toolbar = CrystalToolbarView(
        theme: .light,
        toolbar: CrystalToolbar(
            leftAction: CrystalToolbarAction(title: "Отмена"),
            rightAction: CrystalToolbarAction(title: "Готово")
        )
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(toolbar)
        toolbar.leftTapped = {
            CrystalToastController(content: .text("Cancel tapped")).present()
        }
        toolbar.rightTapped = {
            CrystalToastController(content: .text("Done tapped")).present()
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let height = CrystalToolbarView.preferredHeight(bottomSafeInset: layout.safeInsets.bottom)
        toolbar.frame = CGRect(
            x: 0,
            y: view.bounds.height - height,
            width: view.bounds.width,
            height: height
        )
    }

    override func buildDemo() {
        addButton("Middle действие") { [weak self] in
            guard let self else { return }
            self.toolbar.toolbar = CrystalToolbar(
                leftAction: CrystalToolbarAction(title: "Left"),
                middleAction: CrystalToolbarAction(title: "Middle", color: .accent),
                rightAction: CrystalToolbarAction(title: "Right")
            )
            self.toolbar.middleTapped = {
                CrystalToastController(content: .text("Middle tapped")).present()
            }
        }
        addButton("Destructive right") { [weak self] in
            guard let self else { return }
            self.toolbar.toolbar = CrystalToolbar(
                leftAction: CrystalToolbarAction(title: "Отмена"),
                rightAction: CrystalToolbarAction(title: "Удалить", color: .destructive)
            )
        }
        addButton("Disabled right") { [weak self] in
            guard let self else { return }
            self.toolbar.toolbar = CrystalToolbar(
                leftAction: CrystalToolbarAction(title: "Отмена"),
                rightAction: CrystalToolbarAction(title: "Сохранить", isEnabled: false)
            )
        }
    }
}
