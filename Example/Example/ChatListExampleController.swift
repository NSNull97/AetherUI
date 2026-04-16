import UIKit
import CrystalUI

// MARK: - Chat List Item (CrystalListItem)

/// Model for a single chat row. Implements `CrystalListItem` for use with `CrystalListView`.
final class ChatListItem: CrystalListItem {
    let title: String
    let subtitle: String
    let emoji: String
    let color: UIColor
    let badge: Int?

    var approximateHeight: CGFloat { 72.0 }
    var selectable: Bool { true }

    init(title: String, subtitle: String, emoji: String, color: UIColor, badge: Int? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.emoji = emoji
        self.color = color
        self.badge = badge
    }

    func createNode(params: CrystalListItemLayoutParams, previousItem: CrystalListItem?, nextItem: CrystalListItem?) -> (CrystalListItemNode, CrystalListItemNodeLayout) {
        let node = ChatListItemNode()
        node.configure(with: self)
        let layout = CrystalListItemNodeLayout(contentSize: CGSize(width: params.width, height: 72))
        return (node, layout)
    }

    func updateNode(_ node: CrystalListItemNode, params: CrystalListItemLayoutParams, previousItem: CrystalListItem?, nextItem: CrystalListItem?, animation: CrystalListItemUpdateAnimation) -> CrystalListItemNodeLayout {
        (node as? ChatListItemNode)?.configure(with: self)
        return CrystalListItemNodeLayout(contentSize: CGSize(width: params.width, height: 72))
    }

    func selected(listView: CrystalListView) {}
}

// MARK: - Chat List Item Node (CrystalListItemNode)

/// Visual cell for a chat row. Manual frame layout (no Auto Layout) for performance.
final class ChatListItemNode: CrystalListItemNode {
    private let avatarView = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let separatorView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        avatarView.textAlignment = .center
        avatarView.layer.cornerRadius = 24
        avatarView.clipsToBounds = true
        avatarView.font = .systemFont(ofSize: 22)
        addSubview(avatarView)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 14)
        addSubview(subtitleLabel)

        separatorView.backgroundColor = .separator
        addSubview(separatorView)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with item: ChatListItem) {
        avatarView.backgroundColor = item.color.withAlphaComponent(0.85)
        avatarView.text = item.emoji
        titleLabel.text = item.title
        subtitleLabel.text = item.subtitle
        subtitleLabel.textColor = item.subtitle.hasPrefix("online") ? .systemBlue : .secondaryLabel
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        let w = bounds.width
        avatarView.frame = CGRect(x: 12, y: (h - 48) / 2, width: 48, height: 48)
        titleLabel.frame = CGRect(x: 72, y: 14, width: w - 84, height: 22)
        subtitleLabel.frame = CGRect(x: 72, y: 38, width: w - 84, height: 18)
        separatorView.frame = CGRect(x: 72, y: h - 1.0 / UIScreen.main.scale, width: w - 72, height: 1.0 / UIScreen.main.scale)
    }

    override func setHighlighted(_ highlighted: Bool, at point: CGPoint, animated: Bool) {
        let color: UIColor = highlighted ? .systemGray5 : .clear
        if animated {
            UIView.animate(withDuration: 0.2) { self.backgroundColor = color }
        } else {
            backgroundColor = color
        }
    }
}

// MARK: - Chat List Controller

final class ChatListExampleController: ViewController {
    private let listView = CrystalListView()
    private let filterBar = ChatFilterBarContent()

    // Bottom search bar (no-tab-bar mode)
    private var bottomSearchBar: GlassBackgroundView?
    private var bottomSearchIcon: UIImageView?
    private var bottomSearchLabel: UILabel?

    private let chatItems: [ChatListItem] = [
        ChatListItem(title: "Sister", subtitle: "online", emoji: "🙋‍♀️", color: .systemRed),
        ChatListItem(title: "Pool Duck", subtitle: "online", emoji: "💧", color: .systemGreen),
        ChatListItem(title: "Cool Duck", subtitle: "online", emoji: "😎", color: .systemYellow),
        ChatListItem(title: "Dad Duck", subtitle: "last seen 3 minutes ago", emoji: "👨", color: .systemOrange),
        ChatListItem(title: "Calm Duck", subtitle: "last seen 4 minutes ago", emoji: "🌙", color: .systemPurple),
        ChatListItem(title: "Smile Duck", subtitle: "last seen 12 minutes ago", emoji: "🙂", color: .systemTeal),
        ChatListItem(title: "Grandma", subtitle: "last seen 15 minutes ago", emoji: "👵", color: .systemYellow),
        ChatListItem(title: "Morning Quack", subtitle: "last seen 37 minutes ago", emoji: "🌅", color: .systemOrange),
        ChatListItem(title: "Clean Duck", subtitle: "last seen 47 minutes ago", emoji: "✨", color: .systemBlue),
        ChatListItem(title: "Sleepy Duck", subtitle: "last seen 57 minutes ago", emoji: "🛏", color: .systemPink),
        ChatListItem(title: "Customer", subtitle: "last seen 1 hour ago", emoji: "💼", color: .systemBrown),
        ChatListItem(title: "Angry Duck", subtitle: "last seen 2 hours ago", emoji: "😠", color: .systemRed, badge: 3),
        ChatListItem(title: "Party Duck", subtitle: "sent a sticker", emoji: "🎉", color: .systemPink, badge: 12),
        ChatListItem(title: "Work Channel", subtitle: "See you tomorrow!", emoji: "💼", color: .systemIndigo, badge: 2),
        ChatListItem(title: "Photo Club", subtitle: "Photo", emoji: "📸", color: .systemOrange),
        ChatListItem(title: "Friends", subtitle: "Alex is typing...", emoji: "👥", color: .systemBlue, badge: 1),
        ChatListItem(title: "Music Lovers", subtitle: "New track shared", emoji: "🎧", color: .systemPurple),
        ChatListItem(title: "Design Feed", subtitle: "Check out this mockup", emoji: "🎨", color: .systemPink),
        ChatListItem(title: "Cat Memes", subtitle: "purr purr", emoji: "🐱", color: .systemGray, badge: 42),
        ChatListItem(title: "Book Club", subtitle: "Chapter 12 discussion", emoji: "📚", color: .systemBrown),
        ChatListItem(title: "Running Squad", subtitle: "5K tomorrow at 7am", emoji: "🏃", color: .systemGreen),
        ChatListItem(title: "Gaming Guild", subtitle: "raid starting in 10", emoji: "🎮", color: .systemBlue, badge: 7),
        ChatListItem(title: "Food Photos", subtitle: "Pizza night", emoji: "🍽", color: .systemOrange),
        ChatListItem(title: "Travel Tips", subtitle: "Best time to visit Kyoto", emoji: "✈️", color: .systemCyan, badge: 1),
        ChatListItem(title: "Morning News", subtitle: "Top stories today", emoji: "📰", color: .systemGray),
        ChatListItem(title: "Tech Updates", subtitle: "Apple event tomorrow", emoji: "🛠", color: .systemBlue),
        ChatListItem(title: "Movie Buffs", subtitle: "What did you think?", emoji: "🎬", color: .systemRed),
        ChatListItem(title: "DIY Projects", subtitle: "new tutorial up", emoji: "🔨", color: .systemYellow),
        ChatListItem(title: "Space Enthusiasts", subtitle: "launch in 3...", emoji: "🌌", color: .systemIndigo, badge: 5),
        ChatListItem(title: "Plant Parents", subtitle: "My monstera grew!", emoji: "🪴", color: .systemGreen),
        ChatListItem(title: "Old Friend", subtitle: "long time no see", emoji: "🤗", color: .systemOrange),
        ChatListItem(title: "Weekly Standup", subtitle: "notes attached", emoji: "🗓", color: .systemPurple),
        ChatListItem(title: "Late Night Talks", subtitle: "can't sleep", emoji: "🌃", color: .systemTeal),
    ]

    // MARK: - Init

    init() {
        super.init(navigationBarPresentationData: nil)
        navigationItem.title = "Чаты"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Изм.", style: .plain, target: self, action: #selector(editTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
            style: .plain, target: self, action: #selector(addTapped)
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // CrystalListView fills the view
        listView.frame = view.bounds
        listView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(listView)

        // Tap handler: push chat detail
        listView.itemTapped = { [weak self] index in
            guard let self, index < self.chatItems.count else { return }
            let detail = ChatDetailExampleController(title: self.chatItems[index].title)
            self.push(detail)
        }

        // Populate list via transaction
        listView.transaction(
            insertIndicesAndItems: chatItems.enumerated().map { i, item in
                CrystalListInsertItem(index: i, item: item)
            }
        )

        // Defer search setup until we know if there's a tab controller
        DispatchQueue.main.async { [weak self] in
            self?.setupSearchMode()
        }
    }

    // MARK: - Search Mode Setup

    private var hasTabBar: Bool {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if next is CrystalTabBarController { return true }
            responder = next
        }
        return false
    }

    private func setupSearchMode() {
        if hasTabBar {
            let search = CrystalSearchController()
            search.placeholder = "Поиск"
            search.delegate = self
            crystalSearchController = search
            navigationBarContent = filterBar
        } else {
            navigationBarContent = filterBar
            buildBottomSearchBar()
        }
    }

    // MARK: - Bottom Search Bar (no tab bar)

    private static let bottomBarHeight: CGFloat = 42.0
    private var bottomEdgeEffect: EdgeEffectView?
    private var isBottomSearchActive = false
    private var bottomSearchTextField: UITextField?
    private var bottomSearchCloseButton: GlassBarButtonView?

    private func buildBottomSearchBar() {
        let edge = EdgeEffectView()
        edge.isUserInteractionEnabled = false
        view.addSubview(edge)
        bottomEdgeEffect = edge

        let bg = GlassBackgroundView(style: .regular)
        bg.isUserInteractionEnabled = true
        view.addSubview(bg)
        bottomSearchBar = bg

        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))?.withRenderingMode(.alwaysTemplate))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .center
        bg.contentView.addSubview(icon)
        bottomSearchIcon = icon

        let label = UILabel()
        label.text = "Поиск"
        label.font = .systemFont(ofSize: 17)
        label.textColor = .secondaryLabel
        bg.contentView.addSubview(label)
        bottomSearchLabel = label

        bg.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(bottomSearchTapped)))
        layoutBottomBar()
    }

    private var bottomBarY: CGFloat {
        view.bounds.height - max(25.0, view.safeAreaInsets.bottom + 8.0) - Self.bottomBarHeight
    }

    private func layoutBottomBar() {
        let h = Self.bottomBarHeight
        let side: CGFloat = 16.0
        let y = bottomBarY
        let isDark = traitCollection.userInterfaceStyle == .dark

        if let edge = bottomEdgeEffect {
            let edgeH: CGFloat = 48.0
            let edgeFrame = CGRect(x: 0, y: y - edgeH, width: view.bounds.width, height: edgeH + h + (view.bounds.height - y - h))
            edge.frame = edgeFrame
            edge.update(content: .systemBackground, blur: true, alpha: 0.65,
                        rect: CGRect(origin: .zero, size: edgeFrame.size),
                        edge: .bottom, edgeSize: edgeH, blurRadiusAtEdge: 3.0, blurRadiusAtFade: 3.0, transition: .immediate)
        }

        guard let bg = bottomSearchBar, !isBottomSearchActive else { return }
        let frame = CGRect(x: side, y: y, width: view.bounds.width - side * 2, height: h)
        bg.frame = frame
        bg.update(size: frame.size, cornerRadius: h / 2, isDark: isDark,
                  tintColor: .init(kind: .panel), isInteractive: false, isVisible: true, transition: .immediate)
        bottomSearchIcon?.frame = CGRect(x: 14, y: (h - 18) / 2, width: 18, height: 18)
        bottomSearchLabel?.frame = CGRect(x: 38, y: 0, width: frame.width - 48, height: h)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !hasTabBar {
            layoutBottomBar()
            if isBottomSearchActive { layoutBottomSearchActive() }
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        if isBottomSearchActive {
            layoutBottomSearchActive(keyboardHeight: layout.inputHeight ?? 0)
        }
    }

    @objc private func bottomSearchTapped() { activateBottomSearch() }

    private func activateBottomSearch() {
        guard !isBottomSearchActive else { return }
        isBottomSearchActive = true
        let h = Self.bottomBarHeight

        bottomSearchIcon?.isHidden = true
        bottomSearchLabel?.isHidden = true

        let tf = UITextField()
        tf.placeholder = "Поиск"
        tf.font = .systemFont(ofSize: 17)
        tf.textColor = .label
        tf.tintColor = .systemBlue
        tf.returnKeyType = .search
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.clearButtonMode = .whileEditing
        let leftIcon = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)))
        leftIcon.tintColor = .secondaryLabel
        leftIcon.frame = CGRect(x: 0, y: 0, width: 28, height: 20)
        leftIcon.contentMode = .center
        tf.leftView = leftIcon
        tf.leftViewMode = .always
        bottomSearchBar?.contentView.addSubview(tf)
        bottomSearchTextField = tf

        let close = GlassBarButtonView(icon: UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)), state: .glass)
        close.contentTintColor = .label
        close.action = { [weak self] _ in self?.deactivateBottomSearch() }
        close.alpha = 0
        close.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        view.addSubview(close)
        bottomSearchCloseButton = close

        let pillFrame = bottomSearchBar?.frame ?? .zero
        tf.frame = CGRect(x: 8, y: 0, width: pillFrame.width - 16, height: h)
        close.frame = CGRect(x: pillFrame.maxX, y: pillFrame.minY, width: h, height: h)
        tf.becomeFirstResponder()

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.2, options: [.beginFromCurrentState]) {
            self.layoutBottomSearchActive()
            close.alpha = 1
            close.transform = .identity
        }
    }

    private func deactivateBottomSearch() {
        guard isBottomSearchActive else { return }
        isBottomSearchActive = false
        bottomSearchTextField?.resignFirstResponder()

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.bottomSearchCloseButton?.alpha = 0
            self.bottomSearchCloseButton?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            self.layoutBottomBar()
        } completion: { _ in
            self.bottomSearchTextField?.removeFromSuperview()
            self.bottomSearchCloseButton?.removeFromSuperview()
            self.bottomSearchTextField = nil
            self.bottomSearchCloseButton = nil
            self.bottomSearchIcon?.isHidden = false
            self.bottomSearchLabel?.isHidden = false
        }
    }

    private func layoutBottomSearchActive(keyboardHeight: CGFloat? = nil) {
        let h = Self.bottomBarHeight
        let side: CGFloat = 16.0
        let isDark = traitCollection.userInterfaceStyle == .dark
        let kbH = keyboardHeight ?? currentlyAppliedLayout?.inputHeight ?? 0
        let baseY = kbH > 0 ? view.bounds.height - kbH - h - 8 : bottomBarY
        let closeX = view.bounds.width - side - h
        let pillWidth = closeX - side - 8

        bottomSearchCloseButton?.frame = CGRect(x: closeX, y: baseY, width: h, height: h)
        let pillFrame = CGRect(x: side, y: baseY, width: pillWidth, height: h)
        bottomSearchBar?.frame = pillFrame
        bottomSearchBar?.update(size: pillFrame.size, cornerRadius: h / 2, isDark: isDark,
                                tintColor: .init(kind: .panel), isInteractive: false, isVisible: true, transition: .immediate)
        bottomSearchTextField?.frame = CGRect(x: 8, y: 0, width: pillWidth - 16, height: h)

        if let edge = bottomEdgeEffect {
            let edgeH: CGFloat = 48.0
            let edgeFrame = CGRect(x: 0, y: baseY - edgeH, width: view.bounds.width, height: view.bounds.height - baseY + edgeH)
            edge.frame = edgeFrame
            edge.update(content: .systemBackground, blur: true, alpha: 0.65,
                        rect: CGRect(origin: .zero, size: edgeFrame.size),
                        edge: .bottom, edgeSize: edgeH, blurRadiusAtEdge: 3.0, blurRadiusAtFade: 3.0, transition: .immediate)
        }
    }

    // MARK: - Tab Bar Search

    override func tabBarActivateSearch() { crystalSearchController?.activate() }
    override func tabBarDeactivateSearch() { crystalSearchController?.deactivate() }

    // MARK: - Actions

    @objc private func editTapped() {}

    @objc private func addTapped() {
        let modal = StickerPackModalController(
            navigationBarPresentationData: NavigationBarPresentationData(theme: .liquidGlass())
        )
        presentModal(modal, animated: true)
    }
}

// MARK: - CrystalSearchControllerDelegate

extension ChatListExampleController: CrystalSearchControllerDelegate {
    func searchController(_ controller: CrystalSearchController, didChangeText text: String) {
        // TODO: filter chatItems and re-transact
    }

    func searchController(_ controller: CrystalSearchController, didSubmitText text: String) {
        // TODO: perform search
    }
}

// MARK: - Filter Bar

private final class ChatFilterBarContent: NavigationBarContentView {
    private let glassBackground = GlassBackgroundView(style: .regular)
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private let filters: [(String, Int?)] = [
        ("Все", nil), ("Личное", 96), ("Melodoius", nil), ("Работа", nil), ("Друзья", nil),
    ]

    override var mode: NavigationBarContentMode { .expansion }
    override var height: CGFloat { 52.0 }
    override var nominalHeight: CGFloat { 52.0 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(glassBackground)
        scrollView.showsHorizontalScrollIndicator = false
        glassBackground.contentView.addSubview(scrollView)
        stack.axis = .horizontal
        stack.spacing = 0
        stack.alignment = .center
        scrollView.addSubview(stack)

        for (index, (title, badge)) in filters.enumerated() {
            stack.addArrangedSubview(FilterChip(title: title, badge: badge, isSelected: index == 1))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGSize {
        let hM: CGFloat = 16.0, vM: CGFloat = 4.0
        let gf = CGRect(x: hM + leftInset, y: vM, width: size.width - (hM + leftInset + hM + rightInset), height: size.height - vM * 2)
        glassBackground.frame = gf
        glassBackground.update(size: gf.size, cornerRadius: gf.height * 0.5, isDark: traitCollection.userInterfaceStyle == .dark,
                               tintColor: .init(kind: .panel), isInteractive: true, isVisible: true, transition: transition)
        scrollView.frame = CGRect(origin: .zero, size: gf.size)
        let cs = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        stack.frame = CGRect(x: 4, y: 0, width: cs.width, height: gf.height)
        scrollView.contentSize = CGSize(width: stack.frame.maxX + 4, height: gf.height)
        return size
    }
}

private final class FilterChip: UIView {
    init(title: String, badge: Int?, isSelected: Bool) {
        super.init(frame: .zero)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        backgroundColor = isSelected ? .secondarySystemBackground : .clear

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = isSelected ? .label : .secondaryLabel
        addSubview(label)

        var constraints = [
            heightAnchor.constraint(equalToConstant: 36),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]

        if let badge {
            let bv = UIView()
            bv.translatesAutoresizingMaskIntoConstraints = false
            bv.backgroundColor = .systemBlue
            bv.layer.cornerRadius = 11
            bv.layer.cornerCurve = .continuous
            let bl = UILabel()
            bl.translatesAutoresizingMaskIntoConstraints = false
            bl.text = "\(badge)"
            bl.textColor = .white
            bl.font = .systemFont(ofSize: 13, weight: .semibold)
            bv.addSubview(bl)
            addSubview(bv)
            constraints += [
                bl.leadingAnchor.constraint(equalTo: bv.leadingAnchor, constant: 6),
                bl.trailingAnchor.constraint(equalTo: bv.trailingAnchor, constant: -6),
                bl.centerYAnchor.constraint(equalTo: bv.centerYAnchor),
                bv.heightAnchor.constraint(equalToConstant: 22),
                bv.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
                bv.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
                bv.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                bv.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
        } else {
            constraints.append(label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14))
        }
        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) { fatalError() }
}
