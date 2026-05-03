import UIKit
import AetherUI

/// Tab 2 root — picker that pushes a state demo per row.
func makeStatesRoot() -> AetherViewController {
    return DemoListController(title: "States", rows: [
        .init("Skeleton", "shimmer placeholders", { SkeletonDemoController() }),
        .init("Modal", "single / dual / scrollable sheets", { ModalDemoController() }),
        .init("Content State", "loading / empty / error", { ContentStateDemoController() }),
        .init("Toast", "text / icon / undo", { ToastDemoController() })
    ])
}

// MARK: - Skeleton

final class SkeletonDemoController: DemoController {
    override var demoTitle: String { "Skeleton" }

    override func buildDemo() {
        addLabel("Shimmer-плейсхолдеры списка:")
        for _ in 0..<3 {
            addSkeletonRow()
        }

        addLabel("Block:")
        let block = AetherSkeletonBlockView(theme: .system)
        block.cornerRadius = 14
        addCenteredView(block, height: 120)
    }

    private func addSkeletonRow() {
        let row = UIView()
        let avatar = AetherSkeletonCircleView(theme: .system)
        let line1 = AetherSkeletonLineView(theme: .system)
        line1.lineHeight = 12
        let line2 = AetherSkeletonLineView(theme: .system)
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
        row.heightAnchor.constraint(equalToConstant: 56).isActive = true
        stack.addArrangedSubview(row)
    }
}

// MARK: - Modal

final class ModalDemoController: DemoController {
    override var demoTitle: String { "Modal" }

    override func buildDemo() {
        addButton("Single-detent sheet") { [weak self] in self?.presentSingle() }
        addButton("Dual-detent (half/full)") { [weak self] in self?.presentDual() }
        addButton("Scrollable content") { [weak self] in self?.presentScrollable() }
    }

    private func presentSingle() {
        let content = SimpleModalContent(
            title: "Одно положение",
            message: "Swipe вниз — закроется"
        )
        let modal = AetherModalController(config: .init(detents: [.stage1], initialDetent: .stage1))
        modal.embedContent(content)
        present(modal, animated: true)
    }

    private func presentDual() {
        let content = SimpleModalContent(
            title: "Два detent",
            message: "Потяни выше — полный экран; потяни ниже — половина."
        )
        let modal = AetherModalController(config: .init(detents: [.stage1, .stage2], initialDetent: .stage1))
        modal.embedContent(content)
        present(modal, animated: true)
    }

    private func presentScrollable() {
        let content = ScrollableModalContent()
        let modal = AetherModalController()
        modal.embedContent(content)
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
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
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
        view.addSubview(scrollView)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24)
        ])

        for i in 1...30 {
            let label = UILabel()
            label.font = .systemFont(ofSize: 16)
            label.textColor = .label
            label.text = "Строка #\(i) — таскай sheet, скроллируй контент"
            stack.addArrangedSubview(label)
        }
    }
}

// MARK: - Content state

final class ContentStateDemoController: DemoController {
    override var demoTitle: String { "Content State" }

    override func buildDemo() {
        addButton("Loading") { [weak self] in
            var config = AetherContentUnavailableConfiguration.loading()
            config.secondaryText = "Загружаем данные..."
            self?.setAetherContentUnavailableConfiguration(config, animated: true)
        }
        addButton("Empty") { [weak self] in
            var config = AetherContentUnavailableConfiguration.empty()
            config.image = UIImage(systemName: "tray")
            config.text = "Здесь пока пусто"
            config.secondaryText = "Добавьте первую запись, чтобы она появилась тут"
            config.button.title = "Добавить"
            config.button.primaryAction = {}
            self?.setAetherContentUnavailableConfiguration(config, animated: true)
        }
        addButton("Error + Retry") { [weak self] in
            var config = AetherContentUnavailableConfiguration.error()
            config.text = "Не удалось загрузить"
            config.secondaryText = "Проверьте соединение и попробуйте ещё раз"
            config.button.title = "Повторить"
            config.button.primaryAction = {}
            self?.setAetherContentUnavailableConfiguration(config, animated: true)
        }
        addButton("Скрыть") { [weak self] in
            self?.setAetherContentUnavailableConfiguration(nil, animated: true)
        }
    }
}

// MARK: - Toast

final class ToastDemoController: DemoController {
    override var demoTitle: String { "Toast" }

    override func buildDemo() {
        addButton("Просто текст") {
            AetherToastController(content: .text("Сообщение отправлено")).present()
        }
        addButton("Иконка + текст") {
            let icon = UIImage(systemName: "checkmark.circle.fill") ?? UIImage()
            AetherToastController(content: .iconAndText(icon, "Сохранено в избранное")).present()
        }
        addButton("Текст + Undo") { [weak self] in
            AetherToastController(
                content: .textAndAction(
                    "Сообщение удалено",
                    AetherToastAction(title: "Undo") {
                        let alert = AetherAlertController(
                            title: "Undo нажат",
                            message: nil,
                            actions: [AetherAlertAction(title: "OK", style: .primary)]
                        )
                        self?.present(alert, animated: false)
                    }
                ),
                timeout: 5.0
            ).present()
        }
        addButton("Иконка + текст + action") {
            let icon = UIImage(systemName: "trash.fill") ?? UIImage()
            AetherToastController(
                content: .iconTextAndAction(
                    icon,
                    "3 чата удалены",
                    AetherToastAction(title: "Undo") {}
                ),
                timeout: 5.0
            ).present()
        }
    }
}
