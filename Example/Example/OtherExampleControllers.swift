import UIKit
import CrystalUI

final class ContactsExampleController: ViewController {
    init() {
        super.init(navigationBarPresentationData: nil)
        navigationItem.title = "Контакты"
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "Контакты"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

final class CallsExampleController: ViewController {
    init() {
        super.init(navigationBarPresentationData: nil)
        navigationItem.title = "Звонки"
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "Звонки"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

// MARK: - Context menu playground

/// Demo/test screen exercising every variant of the ported `ContextMenuController`:
///   1. Tap-triggered title pill that re-renders its selection mark on each open
///      (mirrors the ChatGPT-style mode picker from the storyboard screenshots).
///   2. Long-press icon button showing a menu with leading icons.
///   3. Long-press pill with destructive actions and two separated groups.
///   4. Top-anchored source — menu must flip and appear below the button.
///   5. Bottom-anchored source — menu must flip and appear above the button.
///
/// A status label at the bottom records the last selected action so the
/// dismiss/completion plumbing can be eye-verified.
final class SettingsExampleController: ViewController {
    // MARK: - Subviews

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    private let titlePill = GlassBarButtonView(title: "ChatGPT")
    private let iconButton = GlassBarButtonView(
        icon: UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
    )
    private let destructivePill = GlassBarButtonView(title: "Group actions")
    private let topAnchoredButton = GlassBarButtonView(title: "Top anchored")
    private let bottomAnchoredButton = GlassBarButtonView(title: "Bottom anchored")
    private let submenuPill = GlassBarButtonView(title: "Settings ›")

    private let statusLabel = UILabel()

    // MARK: - State

    private enum Mode: String { case instant = "Instant", thinking = "Thinking" }
    private var currentMode: Mode = .instant
    private var notificationsEnabled: Bool = true
    private var soundEnabled: Bool = false
    private var theme: String = "System"
    private var fontSize: String = "Default"

    // MARK: - Init

    init() {
        super.init(navigationBarPresentationData: nil)
        navigationItem.title = "Context menu"
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        configureScrollView()
        configureTestCases()
    }

    // MARK: - Layout

    private func configureScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
        ])
    }

    private func configureTestCases() {
        // Layout is a vertical stack of labelled sections.
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 28.0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])

        // 1. Tap-triggered ChatGPT-style mode picker.
        titlePill.contentTintColor = .label
        titlePill.contextMenuTrigger = .tap
        titlePill.contextMenuItemsProvider = { [weak self] in self?.modePickerItems() ?? [] }
        stack.addArrangedSubview(section(
            title: "1. Tap — mode picker",
            description: "Current mode: \(currentMode.rawValue). Each open re-renders the checkmark on the active row.",
            content: titlePill,
            contentHeight: 36.0
        ))

        // 2. Long-press on an icon button.
        iconButton.contentTintColor = .label
        iconButton.contextMenuTrigger = .longPress
        iconButton.contextMenuItemsProvider = { [weak self] in self?.actionSheetItems() ?? [] }
        stack.addArrangedSubview(section(
            title: "2. Long-press — action sheet",
            description: "Hold the “⋯” button for ~0.35s. Items carry leading icons.",
            content: iconButton,
            contentHeight: 36.0
        ))

        // 3. Destructive / multi-group.
        destructivePill.contentTintColor = .label
        destructivePill.contextMenuTrigger = .tap
        destructivePill.contextMenuItemsProvider = { [weak self] in self?.groupedDestructiveItems() ?? [] }
        stack.addArrangedSubview(section(
            title: "3. Grouped + destructive",
            description: "Two action groups split by a separator, with one destructive row.",
            content: destructivePill,
            contentHeight: 36.0
        ))

        // 6. Submenus.
        submenuPill.contentTintColor = .label
        submenuPill.contextMenuTrigger = .tap
        submenuPill.contextMenuItemsProvider = { [weak self] in self?.submenuRootItems() ?? [] }
        stack.addArrangedSubview(section(
            title: "6. Submenus (push / pop)",
            description: "Tap a row with a chevron to push a submenu page; the back-row at the top pops back. Container resizes to fit each page.",
            content: submenuPill,
            contentHeight: 36.0
        ))

        // 4. Top-anchored source — menu should open below.
        topAnchoredButton.contentTintColor = .label
        topAnchoredButton.contextMenuTrigger = .tap
        topAnchoredButton.contextMenuItemsProvider = { [weak self] in self?.simpleItems() ?? [] }
        stack.addArrangedSubview(section(
            title: "4. Menu opens below (default)",
            description: "When there is enough room under the source, the menu appears beneath it.",
            content: topAnchoredButton,
            contentHeight: 36.0
        ))

        // 5. Bottom-anchored source — menu should open above.
        bottomAnchoredButton.contentTintColor = .label
        bottomAnchoredButton.contextMenuTrigger = .tap
        bottomAnchoredButton.contextMenuItemsProvider = { [weak self] in self?.simpleItems() ?? [] }
        // A spacer pushes this one toward the screen bottom to force the flip.
        let spacer = UIView()
        spacer.heightAnchor.constraint(greaterThanOrEqualToConstant: 240.0).isActive = true
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(section(
            title: "5. Menu opens above (flipped)",
            description: "Close to the screen bottom the menu flips to stay on-screen.",
            content: bottomAnchoredButton,
            contentHeight: 36.0
        ))

        // Status readout.
        statusLabel.text = "No selection yet."
        statusLabel.numberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 13.0, weight: .regular)
        statusLabel.textColor = .tertiaryLabel
        statusLabel.textAlignment = .center
        stack.addArrangedSubview(statusLabel)
    }

    private func section(title: String, description: String, content: UIView, contentHeight: CGFloat) -> UIStackView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15.0, weight: .semibold)

        let descriptionLabel = UILabel()
        descriptionLabel.text = description
        descriptionLabel.font = .systemFont(ofSize: 13.0, weight: .regular)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.addArrangedSubview(content)
        row.addArrangedSubview(UIView()) // flexible spacer so the button hugs leading
        content.setContentHuggingPriority(.required, for: .horizontal)
        content.heightAnchor.constraint(equalToConstant: contentHeight).isActive = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, row])
        stack.axis = .vertical
        stack.spacing = 6.0
        return stack
    }

    // MARK: - Menu item builders

    private func modePickerItems() -> [ContextMenuItem] {
        let instant = ContextMenuActionItem(
            id: "instant",
            title: "Instant",
            isSelected: currentMode == .instant,
            action: { [weak self] _, handle in
                self?.currentMode = .instant
                self?.report("Selected mode: Instant")
                handle.dismiss()
            }
        )
        let thinking = ContextMenuActionItem(
            id: "thinking",
            title: "Thinking",
            isSelected: currentMode == .thinking,
            action: { [weak self] _, handle in
                self?.currentMode = .thinking
                self?.report("Selected mode: Thinking")
                handle.dismiss()
            }
        )
        let configure = ContextMenuActionItem(
            id: "configure",
            title: "Конфигурировать",
            icon: UIImage(systemName: "slider.horizontal.3"),
            iconSide: .leading,
            action: { [weak self] _, handle in
                self?.report("Tapped Конфигурировать")
                handle.dismiss()
            }
        )
        return [
            .header(title: "Последняя"),
            .action(instant),
            .action(thinking),
            .separator,
            .action(configure)
        ]
    }

    private func actionSheetItems() -> [ContextMenuItem] {
        return [
            .action(ContextMenuActionItem(
                id: "share",
                title: "Share",
                icon: UIImage(systemName: "square.and.arrow.up"),
                iconSide: .leading,
                action: { [weak self] _, handle in self?.report("Shared"); handle.dismiss() }
            )),
            .action(ContextMenuActionItem(
                id: "copy",
                title: "Copy link",
                icon: UIImage(systemName: "link"),
                iconSide: .leading,
                action: { [weak self] _, handle in self?.report("Link copied"); handle.dismiss() }
            )),
            .action(ContextMenuActionItem(
                id: "pin",
                title: "Pin",
                icon: UIImage(systemName: "pin"),
                iconSide: .leading,
                action: { [weak self] _, handle in self?.report("Pinned"); handle.dismiss() }
            ))
        ]
    }

    private func groupedDestructiveItems() -> [ContextMenuItem] {
        let notifications = ContextMenuActionItem(
            id: "notifications",
            title: "Notifications",
            isSelected: notificationsEnabled,
            action: { [weak self] _, handle in
                self?.notificationsEnabled.toggle()
                self?.report("Notifications: \(self?.notificationsEnabled == true ? "on" : "off")")
                handle.dismiss()
            }
        )
        let sound = ContextMenuActionItem(
            id: "sound",
            title: "Sound",
            isSelected: soundEnabled,
            action: { [weak self] _, handle in
                self?.soundEnabled.toggle()
                self?.report("Sound: \(self?.soundEnabled == true ? "on" : "off")")
                handle.dismiss()
            }
        )
        let archive = ContextMenuActionItem(
            id: "archive",
            title: "Archive",
            icon: UIImage(systemName: "archivebox"),
            iconSide: .trailing,
            action: { [weak self] _, handle in self?.report("Archived"); handle.dismiss() }
        )
        let delete = ContextMenuActionItem(
            id: "delete",
            title: "Delete",
            icon: UIImage(systemName: "trash"),
            iconSide: .trailing,
            textColor: .destructive,
            action: { [weak self] _, handle in self?.report("Deleted"); handle.dismiss() }
        )
        return [
            .header(title: "Notifications"),
            .action(notifications),
            .action(sound),
            .separator,
            .action(archive),
            .action(delete)
        ]
    }

    private func simpleItems() -> [ContextMenuItem] {
        return [
            .action(ContextMenuActionItem(
                id: "one",
                title: "Option one",
                action: { [weak self] _, handle in self?.report("Option one"); handle.dismiss() }
            )),
            .action(ContextMenuActionItem(
                id: "two",
                title: "Option two",
                action: { [weak self] _, handle in self?.report("Option two"); handle.dismiss() }
            )),
            .action(ContextMenuActionItem(
                id: "three",
                title: "Option three",
                action: { [weak self] _, handle in self?.report("Option three"); handle.dismiss() }
            ))
        ]
    }

    // MARK: - Submenu items

    private func submenuRootItems() -> [ContextMenuItem] {
        return [
            .action(ContextMenuActionItem(
                id: "appearance",
                title: "Appearance",
                submenu: appearanceSubmenuItems()
            )),
            .action(ContextMenuActionItem(
                id: "notifications",
                title: "Notifications",
                submenu: notificationsSubmenuItems()
            )),
            .separator,
            .action(ContextMenuActionItem(
                id: "about",
                title: "About",
                action: { [weak self] _, handle in self?.report("About"); handle.dismiss() }
            ))
        ]
    }

    private func appearanceSubmenuItems() -> [ContextMenuItem] {
        let themes = ["System", "Light", "Dark"]
        let themeItems: [ContextMenuItem] = themes.map { name in
            .action(ContextMenuActionItem(
                id: "theme-\(name)",
                title: name,
                isSelected: self.theme == name,
                action: { [weak self] _, handle in
                    self?.theme = name
                    self?.report("Theme: \(name)")
                    handle.dismiss()
                }
            ))
        }
        return [
            .header(title: "Theme"),
        ] + themeItems + [
            .separator,
            .action(ContextMenuActionItem(
                id: "font",
                title: "Font size: \(fontSize)",
                submenu: fontSizeSubmenuItems()
            ))
        ]
    }

    private func fontSizeSubmenuItems() -> [ContextMenuItem] {
        let sizes = ["Small", "Default", "Large", "Extra Large"]
        return sizes.map { size in
            .action(ContextMenuActionItem(
                id: "font-\(size)",
                title: size,
                isSelected: self.fontSize == size,
                action: { [weak self] _, handle in
                    self?.fontSize = size
                    self?.report("Font: \(size)")
                    handle.dismiss()
                }
            ))
        }
    }

    private func notificationsSubmenuItems() -> [ContextMenuItem] {
        return [
            .action(ContextMenuActionItem(
                id: "notif-on",
                title: "Enabled",
                isSelected: notificationsEnabled,
                action: { [weak self] _, handle in
                    self?.notificationsEnabled.toggle()
                    self?.report("Notifications: \(self?.notificationsEnabled == true ? "on" : "off")")
                    handle.dismiss()
                }
            )),
            .action(ContextMenuActionItem(
                id: "notif-sound",
                title: "Sound",
                isSelected: soundEnabled,
                action: { [weak self] _, handle in
                    self?.soundEnabled.toggle()
                    self?.report("Sound: \(self?.soundEnabled == true ? "on" : "off")")
                    handle.dismiss()
                }
            ))
        ]
    }

    // MARK: - Reporting

    private func report(_ message: String) {
        statusLabel.text = "Last action: \(message)"
    }
}
