import UIKit
import AetherUI

/// Tab 3 — chat-list demo for `AetherListView`. Mixes sticky date
/// headers, the four delete animations (incl. Telegram-style particle
/// dissolve) and a push to a chat detail screen that hides the tab
/// bar — exactly the surface a real messaging app needs.
final class ListDemoController: AetherViewController {
    private var listView: AetherListView!
    private var controls: ListDemoTopAccessoryView!

    private var nextChatId: Int = 0
    private var debugOverlayEnabled = false

    private let deleteAnimations: [AetherListItemDeleteAnimation] = [
        .fade,
        .slide(.up),
        .scale,
        .particles
    ]

    init() {
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: .systemBackground))
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Chats"
        view.backgroundColor = .systemBackground
        installRandomNavbarButton(on: self)

        listView = AetherListView()
        listView.translatesAutoresizingMaskIntoConstraints = false
        // Long-press on a chat row picks it up for reordering. Date
        // headers refuse to move (`canReorder = false`), so they
        // stay anchored to their sections.
        listView.allowsReorder = true
        listView.didMoveItem = { from, to in
            AetherToastController(content: .text("Перемещено: \(from) → \(to)")).present()
        }
        // Pull-to-refresh: simulate fetching three new chats. The
        // closure receives a `done` callback so the spinner stays up
        // until the work is committed.
        listView.refreshHandler = { [weak self] done in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self?.injectFreshChats(count: 3)
                done()
            }
        }
        view.addSubview(listView)
        NSLayoutConstraint.activate([
            listView.topAnchor.constraint(equalTo: view.topAnchor),
            listView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            listView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        controls = ListDemoTopAccessoryView()
        controls.onInsert = { [weak self] in self?.addRandom() }
        controls.onUpdate = { [weak self] in self?.updateRandom() }
        controls.onMove = { [weak self] in self?.moveRandom() }
        controls.onDelete = { [weak self] in self?.deleteRandom() }
        controls.onDebug = { [weak self] in self?.toggleDebugOverlay() }
        topBarAccessory = controls

        seedInitialItems()
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let topInset = cleanNavigationHeight
        let bottomInset = max(layout.safeInsets.bottom, layout.additionalInsets.bottom)
        // Drive through transition so the scroll view animates the
        // inset change AND compensates `contentOffset` by the delta —
        // first-show chrome appears with content already pinned
        // beneath it, no jump-from-behind-navbar.
        listView.updateInsets(
            UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0),
            transition: transition
        )
    }

    // MARK: - Seed

    private func seedInitialItems() {
        // Stress dataset: 10k mixed-height rows with sticky date
        // headers. AetherListView should keep only visible + preload
        // views alive, not 10k UIViews.
        var items: [AetherListItem] = []
        for index in 0..<10_000 {
            if index % 500 == 0 {
                items.append(DateSectionHeaderItem(title: "Section \(index / 500 + 1)"))
            }
            items.append(makeRandomChat(today: index < 200))
        }

        let inserts = items.enumerated().map { i, item in
            AetherListInsertItem(index: i, item: item)
        }
        listView.transaction(insertIndicesAndItems: inserts, options: [])
    }

    private static let names: [String] = [
        "Антон Чехов", "Мария Кюри", "Лев Толстой", "Александр Пушкин",
        "Анна Ахматова", "Сергей Есенин", "Иван Бунин", "Михаил Булгаков",
        "Борис Пастернак", "Марина Цветаева", "Николай Гоголь", "Фёдор Достоевский",
        "Татьяна Толстая", "Виктор Пелевин", "Дмитрий Лихачёв"
    ]

    private static let previews: [String] = [
        "Можно завтра встретиться?",
        "Спасибо!",
        "Видел документ?",
        "Уже в пути 🚗",
        "Перезвоню через 10 минут",
        "Отправил по почте",
        "Окей, договорились",
        "Что думаешь?",
        "👍",
        "Файл во вложении",
        "Не получается, увы",
        "Звонила тебе"
    ]

    private static let avatarColors: [UIColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemTeal, .systemBlue, .systemIndigo, .systemPurple, .systemPink, .systemBrown
    ]

    private func makeRandomChat(today: Bool) -> ChatRowItem {
        let id = nextChatId
        nextChatId += 1
        let name = Self.names.randomElement() ?? "Без имени"
        let preview = Self.previews.randomElement() ?? ""
        let color = Self.avatarColors[id % Self.avatarColors.count]
        let time: String = today
            ? String(format: "%02d:%02d", Int.random(in: 8...23), Int.random(in: 0...59))
            : ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"].randomElement() ?? ""
        let unread = Int.random(in: 0...50) < 12 ? Int.random(in: 1...9) : 0
        let height: CGFloat = [64, 72, 88, 104][id % 4]
        let amplifiedPreview: String
        if height > 80 {
            amplifiedPreview = preview + " · " + (Self.previews.randomElement() ?? preview)
        } else {
            amplifiedPreview = preview
        }
        return ChatRowItem(id: id, name: name, preview: amplifiedPreview, time: time, unread: unread, color: color, height: height)
    }

    private var loadedCount: Int { listView.itemCount }

    // MARK: - Actions

    private func addRandom() {
        let position = Int.random(in: 0...loadedCount)
        let item = makeRandomChat(today: true)
        listView.transaction(
            insertIndicesAndItems: [AetherListInsertItem(index: position, item: item)],
            options: [.animateInsertions]
        )
    }

    private func updateRandom() {
        guard loadedCount > 0 else { return }
        let index = Int.random(in: 0..<loadedCount)
        let updated = makeRandomChat(today: false)
        listView.transaction(
            updateIndicesAndItems: [AetherListUpdateItem(index: index, previousIndex: index, item: updated)],
            options: [.crossfade]
        )
    }

    private func moveRandom() {
        guard loadedCount >= 2 else { return }
        let from = Int.random(in: 0..<loadedCount)
        var to = Int.random(in: 0..<loadedCount)
        while to == from { to = Int.random(in: 0..<loadedCount) }
        listView.transaction(
            moveIndices: [AetherListMoveItem(fromIndex: from, toIndex: to)],
            options: [.animateInsertions]
        )
    }

    private func deleteRandom() {
        guard loadedCount > 0 else { return }
        let index = Int.random(in: 0..<loadedCount)
        let animation = deleteAnimations[controls.deleteAnimationIndex]
        listView.transaction(
            deleteIndices: [AetherListDeleteItem(index: index, animation: animation)],
            options: [.animateInsertions]
        )
    }

    private func toggleDebugOverlay() {
        debugOverlayEnabled.toggle()
        listView.debugInfo = debugOverlayEnabled
        listView.showsDebugOverlay = debugOverlayEnabled
        listView.usesCustomScrollIndicator = debugOverlayEnabled
    }

    /// Inject fresh chats below the "Сегодня" header — fired by the
    /// pull-to-refresh handler. Falls back to inserting at the top
    /// if no header is found (shouldn't happen with the seed).
    fileprivate func injectFreshChats(count: Int) {
        // Find first row immediately after the "Сегодня" header.
        // The seed places sticky DateSectionHeaderItem at index 0,
        // so rows go in at index 1.
        let insertionIndex = 1
        var inserts: [AetherListInsertItem] = []
        for i in 0..<count {
            inserts.append(AetherListInsertItem(
                index: insertionIndex + i,
                item: makeRandomChat(today: true)
            ))
        }
        listView.transaction(
            insertIndicesAndItems: inserts,
            options: [.animateInsertions]
        )
    }

    // MARK: - Push detail

    fileprivate func openChat(_ chat: ChatRowItem) {
        let detail = ChatDetailController(chat: chat)
        push(detail)
    }
}

// MARK: - Top accessory

private final class ListDemoTopAccessoryView: NavigationBarContentView {
    var onInsert: (() -> Void)?
    var onUpdate: (() -> Void)?
    var onMove: (() -> Void)?
    var onDelete: (() -> Void)?
    var onDebug: (() -> Void)?

    private(set) var deleteAnimationIndex: Int = 0

    private let actionsStack = UIStackView()
    private let pickerLabel = UILabel()
    private let picker = AetherSegmentedControl(items: [
        .init(title: "Fade"),
        .init(title: "Slide"),
        .init(title: "Scale"),
        .init(title: "Particles")
    ])

    override var nominalHeight: CGFloat { 80 }
    override var mode: NavigationBarContentMode { .expansion }

    override init(frame: CGRect) {
        super.init(frame: frame)

        actionsStack.axis = .horizontal
        actionsStack.spacing = 6
        actionsStack.distribution = .fillEqually
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionsStack)

        actionsStack.addArrangedSubview(makeButton("Insert") { [weak self] in self?.onInsert?() })
        actionsStack.addArrangedSubview(makeButton("Update") { [weak self] in self?.onUpdate?() })
        actionsStack.addArrangedSubview(makeButton("Move") { [weak self] in self?.onMove?() })
        actionsStack.addArrangedSubview(makeButton("Delete") { [weak self] in self?.onDelete?() })
        actionsStack.addArrangedSubview(makeButton("Debug") { [weak self] in self?.onDebug?() })

        pickerLabel.text = "Delete:"
        pickerLabel.font = .systemFont(ofSize: 13, weight: .medium)
        pickerLabel.textColor = .secondaryLabel
        pickerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pickerLabel)

        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.selectedIndexChanged = { [weak self] index in
            self?.deleteAnimationIndex = index
        }
        addSubview(picker)

        NSLayoutConstraint.activate([
            actionsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            actionsStack.topAnchor.constraint(equalTo: topAnchor),
            actionsStack.heightAnchor.constraint(equalToConstant: 36),

            pickerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            pickerLabel.centerYAnchor.constraint(equalTo: picker.centerYAnchor),

            picker.leadingAnchor.constraint(equalTo: pickerLabel.trailingAnchor, constant: 8),
            picker.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            picker.topAnchor.constraint(equalTo: actionsStack.bottomAnchor, constant: 8),
            picker.heightAnchor.constraint(equalToConstant: 36),
            picker.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    @MainActor required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func makeButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.title = title
        config.cornerStyle = .medium
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        return button
    }
}

// MARK: - Date section header (sticky)

private final class DateSectionHeaderItem: AetherListItem {
    let title: String

    init(title: String) { self.title = title }

    var approximateHeight: CGFloat { 36 }
    var selectable: Bool { false }
    var isFloatingHeader: Bool { true }
    // Headers stay put while their chat rows shuffle around.
    var canReorder: Bool { false }

    func createNode(
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?
    ) -> (AetherListItemNode, AetherListItemNodeLayout) {
        let node = DateSectionHeaderNode()
        node.configure(title: title)
        return (node, AetherListItemNodeLayout(
            contentSize: CGSize(width: params.width, height: 36),
            insets: .zero
        ))
    }

    func updateNode(
        _ node: AetherListItemNode,
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?,
        animation: AetherListItemUpdateAnimation
    ) -> AetherListItemNodeLayout {
        if let header = node as? DateSectionHeaderNode {
            header.configure(title: title)
        }
        return AetherListItemNodeLayout(
            contentSize: CGSize(width: params.width, height: 36),
            insets: .zero
        )
    }
}

private final class DateSectionHeaderNode: AetherListItemNode {
    private let label = UILabel()
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground

        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        addSubview(label)

        separator.backgroundColor = .separator
        addSubview(separator)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String) {
        label.text = title
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = CGRect(x: 16, y: 0, width: bounds.width - 32, height: bounds.height - 1)
        let pixel: CGFloat = 1.0 / UIScreen.main.scale
        separator.frame = CGRect(x: 16, y: bounds.height - pixel, width: bounds.width - 16, height: pixel)
    }
}

// MARK: - Chat row

private final class ChatRowItem: AetherListItem {
    let id: Int
    let name: String
    let preview: String
    let time: String
    let unread: Int
    let color: UIColor
    let height: CGFloat

    init(id: Int, name: String, preview: String, time: String, unread: Int, color: UIColor, height: CGFloat = 72) {
        self.id = id
        self.name = name
        self.preview = preview
        self.time = time
        self.unread = unread
        self.color = color
        self.height = height
    }

    var stableId: AnyHashable { id }
    var approximateHeight: CGFloat { height }
    var estimatedHeight: CGFloat { height }
    var selectable: Bool { true }

    func createNode(
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?
    ) -> (AetherListItemNode, AetherListItemNodeLayout) {
        let node = ChatRowNode()
        node.configure(item: self)
        return (node, AetherListItemNodeLayout(
            contentSize: CGSize(width: params.width, height: height),
            insets: .zero
        ))
    }

    func updateNode(
        _ node: AetherListItemNode,
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?,
        animation: AetherListItemUpdateAnimation
    ) -> AetherListItemNodeLayout {
        if let row = node as? ChatRowNode {
            row.configure(item: self, animation: animation)
        }
        return AetherListItemNodeLayout(
            contentSize: CGSize(width: params.width, height: height),
            insets: .zero
        )
    }

    func selected(listView: AetherListView) {
        // Walk the responder chain from the list view up to its host
        // controller — same shape as `UIView.firstResponder(of:)`
        // used in many UIKit codebases.
        var responder: UIResponder? = listView
        while let current = responder {
            if let host = current as? ListDemoController {
                host.openChat(self)
                return
            }
            responder = current.next
        }
    }
}

private final class ChatRowNode: AetherListItemNode {
    private let avatar = UIView()
    private let avatarLabel = UILabel()
    private let nameLabel = UILabel()
    private let previewLabel = UILabel()
    private let timeLabel = UILabel()
    private let badge = UIView()
    private let badgeLabel = UILabel()
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground

        avatar.layer.cornerRadius = 24
        avatar.layer.cornerCurve = .continuous
        addSubview(avatar)

        avatarLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        avatarLabel.textColor = .white
        avatarLabel.textAlignment = .center
        avatar.addSubview(avatarLabel)

        nameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        nameLabel.textColor = .label
        addSubview(nameLabel)

        previewLabel.font = .systemFont(ofSize: 14)
        previewLabel.textColor = .secondaryLabel
        previewLabel.numberOfLines = 2
        addSubview(previewLabel)

        timeLabel.font = .systemFont(ofSize: 13)
        timeLabel.textColor = .secondaryLabel
        addSubview(timeLabel)

        badge.backgroundColor = .systemBlue
        badge.layer.cornerRadius = 10
        addSubview(badge)

        badgeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badge.addSubview(badgeLabel)

        separator.backgroundColor = .separator
        addSubview(separator)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(item: ChatRowItem, animation: AetherListItemUpdateAnimation = .none) {
        let apply = {
            self.avatar.backgroundColor = item.color
            self.avatarLabel.text = String(item.name.prefix(1))
            self.nameLabel.text = item.name
            self.previewLabel.text = item.preview
            self.timeLabel.text = item.time
            if item.unread > 0 {
                self.badge.isHidden = false
                self.badgeLabel.text = "\(item.unread)"
            } else {
                self.badge.isHidden = true
            }
            self.setNeedsLayout()
        }
        switch animation {
        case .crossfade:
            UIView.transition(with: self, duration: 0.25, options: [.transitionCrossDissolve], animations: apply)
        default:
            apply()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let avatarSize: CGFloat = 48
        avatar.frame = CGRect(x: 16, y: (bounds.height - avatarSize) / 2, width: avatarSize, height: avatarSize)
        avatarLabel.frame = avatar.bounds

        let timeWidth: CGFloat = 60
        let badgeSize: CGFloat = 20
        let textX = avatar.frame.maxX + 12
        let textRight = bounds.width - 16

        timeLabel.frame = CGRect(x: textRight - timeWidth, y: 12, width: timeWidth, height: 18)
        timeLabel.textAlignment = .right
        nameLabel.frame = CGRect(x: textX, y: 12, width: timeLabel.frame.minX - textX - 8, height: 22)

        if !badge.isHidden {
            let badgeWidth = max(badgeSize, (badgeLabel.text?.size(withAttributes: [.font: badgeLabel.font!]).width ?? 0) + 12)
            badge.frame = CGRect(x: textRight - badgeWidth, y: bounds.height - 36, width: badgeWidth, height: badgeSize)
            badgeLabel.frame = badge.bounds
            previewLabel.frame = CGRect(x: textX, y: nameLabel.frame.maxY + 4, width: badge.frame.minX - textX - 8, height: max(20, bounds.height - nameLabel.frame.maxY - 16))
        } else {
            previewLabel.frame = CGRect(x: textX, y: nameLabel.frame.maxY + 4, width: textRight - textX, height: max(20, bounds.height - nameLabel.frame.maxY - 16))
        }

        let pixel: CGFloat = 1.0 / UIScreen.main.scale
        separator.frame = CGRect(x: textX, y: bounds.height - pixel, width: bounds.width - textX, height: pixel)
    }

    override func tapped() {
        UIView.animate(withDuration: 0.08, animations: {
            self.backgroundColor = UIColor.systemFill
        }, completion: { _ in
            UIView.animate(withDuration: 0.18) {
                self.backgroundColor = .systemBackground
            }
        })
    }
}

// MARK: - Chat detail

private final class ChatDetailController: AetherViewController {
    private let chat: ChatRowItem
    /// AetherListView replaces the old UITableView — every message
    /// is now a `MessageItem` / `MessageNode` pair, so deletion can
    /// pipe through the regular transaction API and inherit the
    /// Telegram-style particle dissolve.
    private var listView: AetherListView!
    /// Plain subview — NOT `inputAccessoryView`. The latter relies
    /// on UIKit's window-level keyboard tracking surface, which
    /// leaves the bar visible during back-swipe pop. Keeping it
    /// as a regular view we drive from `containerLayoutUpdated`
    /// matches Telegram-iOS.
    private var inputBar: UIView!
    private static let inputBarHeight: CGFloat = 56
    /// Active message items in display order. Used as the data
    /// source for transactions; identity-based lookups handle
    /// deletes/inserts after Long-press menu actions.
    private var messageItems: [MessageItem] = []

    private static let messageBank: [String] = [
        "Привет!", "Как дела?", "Всё ок, ты как?",
        "Слушай, видел новый билд?", "Запустил только что — огонь",
        "Особенно эффект удаления 🔥", "Прям как в Telegram",
//        "А скрытие таббара работает?", "Да, тут видишь",
//        "Окей, тестим дальше", "Пора обедать", "Согласен 😋",
//        "Что там по проекту?", "Завтра релиз", "Понял, готовлюсь",
//        "Кинь ссылку, плиз", "Сейчас", "Пасибо",
//        "На созвоне сегодня?", "Да, в 18:00", "Ок, буду",
//        "Дождь идёт", "У нас солнце 🌞", "Завидую",
//        "Кофе?", "Двойной эспрессо", "Аналогично",
//        "Закрыли тикет?", "Закрыли, ушёл в QA", "Огонь",
//        "Слышал про новый Swift?", "Async вкуснее стал",
//        "Macros тоже глянь", "Да, видел доклад",
//        "Что почитать порекомендуешь?", "Hacking with Swift",
//        "Тесты гоняешь?", "Да, snapshot пишу",
//        "Удачи!", "Спасибо 🙌", "До завтра", "Доброй ночи 🌙",
//        "Поднял билд", "👍", "Звонила тебе", "Перезвоню",
//        "Кстати, видел вакансию?", "Скинь почитать",
//        "Окей, отправил", "Спасибо, изучу",
//        "На море едем?", "В августе", "Запиши меня",
//        "Документ на ревью", "Гляну вечером",
//        "Готово, можно вычитывать", "Принял в работу",
//        "Сейчас в дороге", "Будь аккуратнее на дороге",
//        "Конечно", "До связи!"
    ]

    /// Mock chat — long enough that the keyboard reveal is actually
    /// felt. Roles alternate so bubbles split left/right.
    private var messages: [String] = ChatDetailController.messageBank

    init(chat: ChatRowItem) {
        self.chat = chat
        super.init(navigationBarPresentationData: .defaultTheme(edgeColor: .systemBackground))
        hidesBottomBarWhenPushed = true
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = chat.name
        view.backgroundColor = .systemBackground

        listView = AetherListView()
        listView.frame = view.bounds
        listView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        listView.stackFromBottom = true
        // iOS 26 keyboard is out-of-process — only UIKit's
        // `.interactive` dismiss can physically drag it. The window
        // pan is disabled in viewDidAppear so the two systems don't
        // fight.
        listView.keyboardDismissMode = .interactive
        view.addSubview(listView)

        inputBar = makeInputBar()
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBar)
        // Pin the bar's bottom edge to the keyboard layout guide.
        // That guide is the only handle UIKit gives us that follows
        // an interactive keyboard drag in real time — `keyboardWillChangeFrame`
        // notifications only fire at the start/end of a drag, not
        // on every frame, so any layout we did from notifications
        // alone would lag the finger.
        NSLayoutConstraint.activate([
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.heightAnchor.constraint(equalToConstant: Self.inputBarHeight),
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])

        seedMessages()
    }

    private func seedMessages() {
        for raw in messages {
            let isIncoming = messageItems.count % 2 == 0
            messageItems.append(MessageItem(text: raw, isIncoming: isIncoming, accent: chat.color))
        }
        let inserts = messageItems.enumerated().map { i, item in
            AetherListInsertItem(index: i, item: item)
        }
        listView.transaction(insertIndicesAndItems: inserts)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore the window's keyboard pan recognizer for whoever
        // we're popping back to.
        if let cw = view.window as? AetherWindow {
            cw.setInteractiveKeyboardPanEnabled(true)
        }
        // Drop the window-level overlay binding — the list view
        // owns its dust overlay's lifetime, but if we leave the
        // window pointer set the overlay will outlast the chat
        // (AetherListView keeps its dust overlay around until
        // `becameEmpty` fires).
        listView.particleDissolveOverlayHost = nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // `view.window` only resolves once we're in the hierarchy,
        // which is `viewDidAppear` (not `viewWillAppear`). Yield
        // the keyboard-tracking gesture to UIKit's `.interactive`
        // dismiss on the list view here.
        (view.window as? AetherWindow)?.setInteractiveKeyboardPanEnabled(false)
        // Render the particle dissolve overlay at the window level
        // so it lands above the ContextMenu's preview snapshot.
        listView.particleDissolveOverlayHost = view.window
        // Chat-style: start parked at the latest message.
        listView.scrollToBottom(animated: false)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        // Top inset sits under the floating navbar; bottom is owned
        // by `viewDidLayoutSubviews`, which reads the input bar's
        // post-autolayout frame (auto-layout settles after this
        // method returns and is driven by the system keyboard guide).
        let topInset = cleanNavigationHeight
        listView.updateInsets(
            UIEdgeInsets(top: topInset, left: 0, bottom: listView.insets.bottom, right: 0),
            transition: transition
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Sync list-bottom inset to the input bar's actual frame —
        // when the keyboard is dragged interactively the keyboard
        // layout guide pushes auto-layout, which fires this method
        // every frame.
        let bottomInset = max(0, view.bounds.height - inputBar.frame.minY + 8)
        if abs(listView.insets.bottom - bottomInset) > 0.5 {
            var insets = listView.insets
            insets.bottom = bottomInset
            listView.insets = insets
        }
    }

    private func makeInputBar() -> UIView {
        let bar = UIView()
        bar.backgroundColor = .secondarySystemBackground

        let separator = UIView()
        separator.backgroundColor = .separator
        bar.addSubview(separator)

        let field = UITextField()
        field.borderStyle = .roundedRect
        field.placeholder = "Сообщение"
        field.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(field)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            field.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10)
        ])
        let pixel: CGFloat = 1.0 / UIScreen.main.scale
        separator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: bar.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: pixel)
        ])
        return bar
    }
}

private final class PendingMenuAction {
    var run: (() -> Void)?
}

private final class MessageReactionAccessoryView: UIVisualEffectView {
    var onSelect: ((String) -> Void)?

    private let stack = UIStackView()

    override var intrinsicContentSize: CGSize {
        CGSize(width: 252, height: 48)
    }

    init() {
        super.init(effect: UIBlurEffect(style: .systemThinMaterial))
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        clipsToBounds = true

        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4)
        ])

        ["👍", "❤️", "😂", "🔥", "👏"].forEach { reaction in
            let button = ReactionButton(reaction: reaction)
            button.titleLabel?.font = .systemFont(ofSize: 24)
            button.addTarget(self, action: #selector(handleReaction(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleReaction(_ sender: ReactionButton) {
        onSelect?(sender.reaction)
    }
}

private final class ReactionButton: UIButton {
    let reaction: String

    init(reaction: String) {
        self.reaction = reaction
        super.init(frame: .zero)
        setTitle(reaction, for: .normal)
        adjustsImageWhenHighlighted = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private extension ChatDetailController {
    /// Long-press on a bubble fires through the responder chain
    /// from `MessageNode` up to here. We open a `.preview()` menu
    /// pinned to the bubble; the action's real work runs in
    /// `onDismiss` so the preview has already settled back into
    /// the bubble before the dust burst starts.
    func presentMessageMenu(for item: MessageItem, anchor: UIView) {
        let pending = PendingMenuAction()
        let reactionAccessory = MessageReactionAccessoryView()

        let copyItem = ContextMenuActionItem(
            title: "Копировать",
            icon: UIImage(systemName: "doc.on.doc"),
            action: { _, handle in
                let text = item.text
                pending.run = {
                    UIPasteboard.general.string = text
                    AetherToastController(content: .text("Скопировано")).present()
                }
                handle.dismiss()
            }
        )
        let deleteItem = ContextMenuActionItem(
            title: "Удалить",
            icon: UIImage(systemName: "trash"),
            textColor: .destructive,
            action: { [weak self] _, handle in
                // Kick the particle dissolve immediately so it
                // overlaps the menu's close animation — waiting for
                // `onDismiss` adds the full close duration (~475ms)
                // of dead air before any visual change.
                self?.dissolveAndDeleteMessage(item)
                handle.dismiss()
            }
        )
        let menu = ContextMenuController(
            source: ContextMenuController.Source(view: anchor, cornerRadius: 16),
            items: [.action(copyItem), .action(deleteItem)],
            presentationStyle: .preview(
                accessory: ContextMenuController.PreviewAccessory(
                    view: reactionAccessory,
                    preferredSize: CGSize(width: 252, height: 48),
                    spacing: 8
                )
            ),
            onDismiss: {
                pending.run?()
            }
        )
        reactionAccessory.onSelect = { [weak menu] reaction in
            pending.run = {
                AetherToastController(content: .text("Реакция \(reaction)")).present()
            }
            menu?.dismiss()
        }
        menu.present()
    }

    /// Run the native particle-dissolve delete. `AetherListView`
    /// snapshots the node's `particleDissolveTargetView` (overridden
    /// to `bubble` in `MessageNode`), runs the burst on the dust
    /// overlay (hosted at `view.window`, set in `viewDidAppear`),
    /// and animates the row out — all in one transaction.
    func dissolveAndDeleteMessage(_ item: MessageItem) {
        guard let index = messageItems.firstIndex(where: { $0 === item }) else { return }
        messageItems.remove(at: index)
        listView.transaction(
            deleteIndices: [AetherListDeleteItem(index: index, animation: .particles)],
            options: [.animateInsertions]
        )
    }
}

// MARK: - MessageItem / MessageNode

private final class MessageItem: AetherListItem {
    let text: String
    let isIncoming: Bool
    let accent: UIColor

    init(text: String, isIncoming: Bool, accent: UIColor) {
        self.text = text
        self.isIncoming = isIncoming
        self.accent = accent
    }

    var selectable: Bool { false }

    var approximateHeight: CGFloat { 56 }

    private static let labelFont = UIFont.systemFont(ofSize: 15)
    private static let bubbleHorizontalInset: CGFloat = 12
    private static let bubbleVerticalInset: CGFloat = 8
    private static let cellVerticalPad: CGFloat = 4
    private static let labelHorizontalInset: CGFloat = 12
    private static let labelVerticalInset: CGFloat = 8

    fileprivate func computeLayout(width: CGFloat) -> AetherListItemNodeLayout {
        // Bubble caps at 75% of the screen — same proportion the
        // old UITableView cell used.
        let availableLabelWidth = max(0, width * 0.75 - Self.labelHorizontalInset * 2)
        let labelHeight = ceil((text as NSString).boundingRect(
            with: CGSize(width: availableLabelWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: Self.labelFont],
            context: nil
        ).height)
        let bubbleHeight = labelHeight + Self.labelVerticalInset * 2
        return AetherListItemNodeLayout(
            contentSize: CGSize(width: width, height: bubbleHeight),
            insets: UIEdgeInsets(top: Self.cellVerticalPad, left: 0, bottom: Self.cellVerticalPad, right: 0)
        )
    }

    func createNode(
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?
    ) -> (AetherListItemNode, AetherListItemNodeLayout) {
        let node = MessageNode()
        node.configure(item: self)
        return (node, computeLayout(width: params.width))
    }

    func updateNode(
        _ node: AetherListItemNode,
        params: AetherListItemLayoutParams,
        previousItem: AetherListItem?,
        nextItem: AetherListItem?,
        animation: AetherListItemUpdateAnimation
    ) -> AetherListItemNodeLayout {
        if let m = node as? MessageNode {
            m.configure(item: self)
        }
        return computeLayout(width: params.width)
    }
}

private final class MessageNode: AetherListItemNode {
    private let bubble = UIView()
    private let label = UILabel()
    private weak var currentItem: MessageItem?

    /// Anchor for the context menu's preview — exposed publicly
    /// so the host controller can pin its menu to the bubble.
    var bubbleView: UIView { bubble }

    /// Restrict the particle-dissolve burst to the bubble. The
    /// row itself is full-width with empty side padding; without
    /// this override the burst would also fire over those empty
    /// regions and look fake.
    override var particleDissolveTargetView: UIView { bubble }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false

        bubble.layer.cornerRadius = 16
        bubble.layer.cornerCurve = .continuous
        bubble.isUserInteractionEnabled = true
        addSubview(bubble)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.3
        bubble.addGestureRecognizer(longPress)

        label.font = .systemFont(ofSize: 15)
        label.numberOfLines = 0
        bubble.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(item: MessageItem) {
        currentItem = item
        label.text = item.text
        if item.isIncoming {
            bubble.backgroundColor = .secondarySystemBackground
            label.textColor = .label
        } else {
            bubble.backgroundColor = item.accent
            label.textColor = .white
        }
        bubble.alpha = 1
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let item = currentItem else { return }
        let cellPad: CGFloat = 4
        let bubblePadH: CGFloat = 12
        let labelPadH: CGFloat = 12
        let labelPadV: CGFloat = 8
        let maxBubbleWidth = bounds.width * 0.75
        let labelMaxWidth = max(0, maxBubbleWidth - labelPadH * 2)
        let labelSize = label.sizeThatFits(CGSize(width: labelMaxWidth, height: .greatestFiniteMagnitude))
        let bubbleWidth = labelSize.width + labelPadH * 2
        let bubbleHeight = ceil(labelSize.height) + labelPadV * 2
        let bubbleX: CGFloat = item.isIncoming ? bubblePadH : bounds.width - bubblePadH - bubbleWidth
        let bubbleY = cellPad
        bubble.frame = CGRect(x: bubbleX, y: bubbleY, width: bubbleWidth, height: bubbleHeight)
        label.frame = CGRect(x: labelPadH, y: labelPadV, width: bubbleWidth - labelPadH * 2, height: bubbleHeight - labelPadV * 2)
    }

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        guard gr.state == .began, let item = currentItem else { return }
        // Walk up the responder chain to the host controller.
        var responder: UIResponder? = self
        while let current = responder {
            if let host = current as? ChatDetailController {
                host.presentMessageMenu(for: item, anchor: bubble)
                return
            }
            responder = current.next
        }
    }
}
