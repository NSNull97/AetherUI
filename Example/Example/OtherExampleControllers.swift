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
    /// Two pills, one hugging the left edge of the section and one hugging
    /// the right edge. Used to visually verify that the morph anchor
    /// follows the source position: tapping the left button should unfold
    /// the menu rightward from the button's left edge, and tapping the
    /// right one should unfold LEFTWARD from its own right edge — not
    /// "always from the left", which was the old bug.
    private let leftAlignButton = GlassBarButtonView(title: "Left")
    private let rightAlignButton = GlassBarButtonView(title: "Right")
    /// Decorated card view for the long-press-preview demo (Phase 2). Plain
    /// UIView with rounded corners + colored background + label so the lifted
    /// snapshot is visible. Has its own long-press recognizer that calls
    /// `ContextMenuController.present(... presentationStyle: .preview)`.
    private let previewCard = UIView()
    private let subtitlePill = GlassBarButtonView(title: "Profile")

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

        // 0. Left + right anchor test.
        //
        // Two pills in the same row: one flush-left, one flush-right.
        // Tapping each should unfold the menu from the corresponding
        // edge (left button → menu grows rightward; right button →
        // menu grows leftward). If both look identical (menu appears
        // from the left regardless), the xAnchor detection in the
        // morph host has regressed.
        leftAlignButton.contentTintColor = .label
        leftAlignButton.contextMenuTrigger = .tap
        leftAlignButton.contextMenuItemsProvider = { [weak self] in self?.simpleItems() ?? [] }
        rightAlignButton.contentTintColor = .label
        rightAlignButton.contextMenuTrigger = .tap
        rightAlignButton.contextMenuItemsProvider = { [weak self] in self?.simpleItems() ?? [] }
        stack.addArrangedSubview(leftRightAnchorSection(
            title: "0. Anchor test — left vs right",
            description: "Left pill opens its menu rightward from its left edge. Right pill opens LEFTWARD from its right edge.",
            leftContent: leftAlignButton,
            rightContent: rightAlignButton,
            contentHeight: 36.0
        ))

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
            title: "6. Submenus (inline expand)",
            description: "Tap a row with a chevron to pop a submenu card OUT of that row; the parent menu dims behind it. Tap the down-chevron OR the dimmed parent area to collapse. Tap outside to dismiss the whole menu.",
            content: submenuPill,
            contentHeight: 36.0
        ))

        // 7. Long-press preview (Telegram chat-row style).
        configurePreviewCard()
        stack.addArrangedSubview(section(
            title: "7. Long-press preview",
            description: "Long-press the card below — it lifts as a snapshot (with shadow) and the menu appears beneath it instead of morphing out of it. Tap outside to release.",
            content: previewCard,
            contentHeight: 80.0
        ))

        // 8. Subtitles + leading icons (Phase 3 + 4 polish).
        subtitlePill.contentTintColor = .label
        subtitlePill.contextMenuTrigger = .tap
        subtitlePill.contextMenuItemsProvider = { [weak self] in self?.subtitleAndIconsItems() ?? [] }
        stack.addArrangedSubview(section(
            title: "8. Subtitles + leading/trailing icons",
            description: "Action rows can carry a secondary subtitle line (taller row) and an icon on either side. Icon respects `iconSide`. Leading icons replace the checkmark slot when the item isn't selected.",
            content: subtitlePill,
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

    /// Build the colored card that shows the long-press preview demo (Phase 2).
    /// Plain rounded UIView with a label inside; long-press triggers the
    /// preview-style context menu where the card lifts as a snapshot.
    private func configurePreviewCard() {
        previewCard.backgroundColor = .systemIndigo
        previewCard.layer.cornerRadius = 16.0
        if #available(iOS 13.0, *) {
            previewCard.layer.cornerCurve = .continuous
        }

        let label = UILabel()
        label.text = "Long-press me"
        label.textColor = .white
        label.font = .systemFont(ofSize: 18.0, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        previewCard.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: previewCard.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: previewCard.centerYAnchor),
        ])

        previewCard.translatesAutoresizingMaskIntoConstraints = false
        // Width is layout-constrained by the section row; height is a fixed
        // 80pt (passed via contentHeight in the section() call).
        previewCard.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true

        let long = UILongPressGestureRecognizer(target: self, action: #selector(handleCardLongPress(_:)))
        long.minimumPressDuration = 0.35
        previewCard.addGestureRecognizer(long)
        previewCard.isUserInteractionEnabled = true
    }

    @objc private func handleCardLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        ContextMenuController.present(
            source: previewCard,
            cornerRadius: previewCard.layer.cornerRadius,
            items: cardActionItems(),
            presentationStyle: .preview()
        )
    }

    private func subtitleAndIconsItems() -> [ContextMenuItem] {
        return [
            .header(title: "Account"),
            .action(ContextMenuActionItem(
                id: "name",
                title: "Edit profile",
                subtitle: "Name, photo, username",
                icon: UIImage(systemName: "person.crop.circle"),
                iconSide: .leading,
                action: { [weak self] _, h in self?.report("Edit profile"); h.dismiss() }
            )),
            .action(ContextMenuActionItem(
                id: "appearance-radio",
                title: "Appearance",
                subtitle: "Light · Auto-switch at sunset",
                icon: UIImage(systemName: "paintbrush"),
                iconSide: .leading,
                isSelected: true,  // demonstrates checkmark winning over leading icon
                action: { [weak self] _, h in self?.report("Appearance"); h.dismiss() }
            )),
            .separator,
            .action(ContextMenuActionItem(
                id: "trailing-1",
                title: "Open in Safari",
                icon: UIImage(systemName: "arrow.up.right.square"),
                iconSide: .trailing,
                action: { [weak self] _, h in self?.report("Open in Safari"); h.dismiss() }
            )),
            .action(ContextMenuActionItem(
                id: "trailing-2",
                title: "Long action title that wraps trailing icon",
                subtitle: "Subtitle with extra context",
                icon: UIImage(systemName: "square.and.arrow.up"),
                iconSide: .trailing,
                action: { [weak self] _, h in self?.report("Long trailing"); h.dismiss() }
            )),
            .separator,
            .action(ContextMenuActionItem(
                id: "destructive-sub",
                title: "Sign out",
                subtitle: "You'll need to log in again",
                icon: UIImage(systemName: "rectangle.portrait.and.arrow.right"),
                iconSide: .leading,
                textColor: .destructive,
                action: { [weak self] _, h in self?.report("Sign out"); h.dismiss() }
            ))
        ]
    }

    private func cardActionItems() -> [ContextMenuItem] {
        return [
            .action(ContextMenuActionItem(
                id: "preview-share", title: "Share",
                icon: UIImage(systemName: "square.and.arrow.up"), iconSide: .leading,
                action: { [weak self] _, h in self?.report("Card: Share"); h.dismiss() }
            )),
            .action(ContextMenuActionItem(
                id: "preview-copy", title: "Copy",
                icon: UIImage(systemName: "doc.on.doc"), iconSide: .leading,
                action: { [weak self] _, h in self?.report("Card: Copy"); h.dismiss() }
            )),
            .separator,
            .action(ContextMenuActionItem(
                id: "preview-delete", title: "Delete",
                icon: UIImage(systemName: "trash"), iconSide: .leading,
                textColor: .destructive,
                action: { [weak self] _, h in self?.report("Card: Delete"); h.dismiss() }
            ))
        ]
    }

    /// Section with two pills — one flush-left, one flush-right — for
    /// verifying that the morph animation anchors to the correct edge
    /// of each button.
    private func leftRightAnchorSection(
        title: String,
        description: String,
        leftContent: UIView,
        rightContent: UIView,
        contentHeight: CGFloat
    ) -> UIStackView {
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
        row.addArrangedSubview(leftContent)
        row.addArrangedSubview(UIView()) // flexible spacer
        row.addArrangedSubview(rightContent)
        leftContent.setContentHuggingPriority(.required, for: .horizontal)
        rightContent.setContentHuggingPriority(.required, for: .horizontal)
        leftContent.heightAnchor.constraint(equalToConstant: contentHeight).isActive = true
        rightContent.heightAnchor.constraint(equalToConstant: contentHeight).isActive = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, row])
        stack.axis = .vertical
        stack.spacing = 6.0
        return stack
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
