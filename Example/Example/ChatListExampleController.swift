import UIKit
import CrystalUI

struct ChatPreview {
    let title: String
    let subtitle: String
    let time: String
    let emoji: String
    let color: UIColor
    let badge: Int?
}

final class ChatListExampleController: ViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let filterBar = ChatFilterBarContent()
    private var navSearchBar: CrystalSearchBarContent?
    private var stackedContent: CrystalStackedBarContent?
    private var bottomSearchBar: GlassBackgroundView?
    private var bottomSearchIcon: UIImageView?
    private var bottomSearchLabel: UILabel?

    private let chats: [ChatPreview] = [
        ChatPreview(title: "Sister", subtitle: "online", time: "", emoji: "🙋‍♀️", color: .systemRed, badge: nil),
        ChatPreview(title: "Pool Duck", subtitle: "online", time: "", emoji: "💧", color: .systemGreen, badge: nil),
        ChatPreview(title: "Cool Duck", subtitle: "online", time: "", emoji: "😎", color: .systemYellow, badge: nil),
        ChatPreview(title: "Dad Duck", subtitle: "last seen 3 minutes ago", time: "", emoji: "👨", color: .systemOrange, badge: nil),
        ChatPreview(title: "Calm Duck", subtitle: "last seen 4 minutes ago", time: "", emoji: "🌙", color: .systemPurple, badge: nil),
        ChatPreview(title: "Smile Duck", subtitle: "last seen 12 minutes ago", time: "", emoji: "🙂", color: .systemTeal, badge: nil),
        ChatPreview(title: "Grandma", subtitle: "last seen 15 minutes ago", time: "", emoji: "👵", color: .systemYellow, badge: nil),
        ChatPreview(title: "Morning Quack", subtitle: "last seen 37 minutes ago", time: "", emoji: "🌅", color: .systemOrange, badge: nil),
        ChatPreview(title: "Clean Duck", subtitle: "last seen 47 minutes ago", time: "", emoji: "✨", color: .systemBlue, badge: nil),
        ChatPreview(title: "Sleepy Duck", subtitle: "last seen 57 minutes ago", time: "", emoji: "🛏", color: .systemPink, badge: nil),
        ChatPreview(title: "Customer", subtitle: "last seen 1 hour ago", time: "", emoji: "💼", color: .systemBrown, badge: nil),
        ChatPreview(title: "Angry Duck", subtitle: "last seen 2 hours ago", time: "", emoji: "😠", color: .systemRed, badge: 3),
        ChatPreview(title: "Party Duck", subtitle: "sent a sticker", time: "", emoji: "🎉", color: .systemPink, badge: 12),
        ChatPreview(title: "Work Channel", subtitle: "See you tomorrow!", time: "", emoji: "💼", color: .systemIndigo, badge: 2),
        ChatPreview(title: "Photo Club", subtitle: "📷 Photo", time: "", emoji: "📸", color: .systemOrange, badge: nil),
        ChatPreview(title: "Friends", subtitle: "Alex is typing…", time: "", emoji: "👥", color: .systemBlue, badge: 1),
        ChatPreview(title: "Music Lovers", subtitle: "🎵 New track shared", time: "", emoji: "🎧", color: .systemPurple, badge: nil),
        ChatPreview(title: "Design Feed", subtitle: "Check out this mockup", time: "", emoji: "🎨", color: .systemPink, badge: nil),
        ChatPreview(title: "Cat Memes", subtitle: "😹 purr purr", time: "", emoji: "🐱", color: .systemGray, badge: 42),
        ChatPreview(title: "Book Club", subtitle: "Chapter 12 discussion", time: "", emoji: "📚", color: .systemBrown, badge: nil),
        ChatPreview(title: "Running Squad", subtitle: "5K tomorrow at 7am", time: "", emoji: "🏃", color: .systemGreen, badge: nil),
        ChatPreview(title: "Gaming Guild", subtitle: "raid starting in 10", time: "", emoji: "🎮", color: .systemBlue, badge: 7),
        ChatPreview(title: "Food Photos", subtitle: "🍕 Pizza night", time: "", emoji: "🍽", color: .systemOrange, badge: nil),
        ChatPreview(title: "Travel Tips", subtitle: "Best time to visit Kyoto", time: "", emoji: "✈️", color: .systemCyan, badge: 1),
        ChatPreview(title: "Morning News", subtitle: "Top stories today", time: "", emoji: "📰", color: .systemGray, badge: nil),
        ChatPreview(title: "Tech Updates", subtitle: "Apple event tomorrow", time: "", emoji: "🛠", color: .systemBlue, badge: nil),
        ChatPreview(title: "Movie Buffs", subtitle: "What did you think?", time: "", emoji: "🎬", color: .systemRed, badge: nil),
        ChatPreview(title: "DIY Projects", subtitle: "new tutorial up", time: "", emoji: "🔨", color: .systemYellow, badge: nil),
        ChatPreview(title: "Space Enthusiasts", subtitle: "🚀 launch in 3…", time: "", emoji: "🌌", color: .systemIndigo, badge: 5),
        ChatPreview(title: "Plant Parents", subtitle: "My monstera grew!", time: "", emoji: "🪴", color: .systemGreen, badge: nil),
        ChatPreview(title: "Old Friend", subtitle: "long time no see", time: "", emoji: "🤗", color: .systemOrange, badge: nil),
        ChatPreview(title: "Weekly Standup", subtitle: "notes attached", time: "", emoji: "🗓", color: .systemPurple, badge: nil),
        ChatPreview(title: "Late Night Talks", subtitle: "can't sleep 😅", time: "", emoji: "🌃", color: .systemTeal, badge: nil),
    ]

    init() {
        // No per-controller bar: the enclosing CrystalNavigationController
        // owns the single shared nav bar.
        super.init(navigationBarPresentationData: nil)

        // Title: "Чаты" with a paper-plane icon after the text (Figma reference).
        navigationItem.title = "Чаты"

        let editButton = UIBarButtonItem(title: "Изм.", style: .plain, target: self, action: #selector(editTapped))
        navigationItem.leftBarButtonItem = editButton

        let shieldButton = UIBarButtonItem(
            image: UIImage(systemName: "shield", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
            style: .plain,
            target: self,
            action: #selector(shieldTapped)
        )
        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "plus.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
            style: .plain,
            target: self,
            action: #selector(addTapped)
        )
        let composeButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
            style: .plain,
            target: self,
            action: #selector(composeTapped)
        )
//        navigationItem.rightBarButtonItems = [composeButton, addButton, shieldButton].reversed()
        navigationItem.rightBarButtonItem = addButton
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 72, bottom: 0, right: 0)
        tableView.rowHeight = 72
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(ChatCell.self, forCellReuseIdentifier: "Chat")
        tableView.contentInsetAdjustmentBehavior = .automatic
        // iOS 15+ adds 35pt of section-header top padding by default in .plain
        // style tables; we want the first row to sit right under the nav bar.
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0.0
        }
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Defer content setup until we know if we have a tab controller
        DispatchQueue.main.async { [weak self] in
            self?.setupSearchMode()
        }

        // Demo helper: auto-scroll so the top scroll-edge fade is visible
        // without manual gesture input.
        if ProcessInfo.processInfo.environment["TG_NAV_DEMO_SCROLL"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.tableView.setContentOffset(CGPoint(x: 0, y: 120), animated: true)
            }
        }

        if ProcessInfo.processInfo.environment["TG_NAV_DEMO_PUSHPOP"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                let detail = ChatDetailExampleController(title: "Sister")
                self.push(detail)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak detail] in
                    detail?.pop()
                }
            }
        }
    }

    // MARK: - Search Mode Setup

    private var hasTabBar: Bool {
        // Walk the responder chain to find a CrystalTabBarController ancestor.
        // Can't use `parent` because CrystalNavigationController doesn't use
        // UIKit child-VC containment for its stack controllers.
        var responder: UIResponder? = self
        while let next = responder?.next {
            if next is CrystalTabBarController { return true }
            responder = next
        }
        return false
    }

    private func setupSearchMode() {
        if hasTabBar {
            // With tab controller: search pill + filters in nav bar
            let navSearch = CrystalSearchBarContent()
            navSearch.placeholder = "Поиск"
            navSearch.isDark = traitCollection.userInterfaceStyle == .dark
            navSearch.onTap = { [weak self] in self?.activateNavBarSearch() }
            self.navSearchBar = navSearch
            let stacked = CrystalStackedBarContent(views: [navSearch, filterBar])
            self.stackedContent = stacked
            self.navigationBarContent = stacked
        } else {
            // Without tab controller: only filters in nav bar, search is at the bottom
            self.navigationBarContent = filterBar
            buildBottomSearchBar()
        }
    }

    // MARK: - Bottom Search Bar (no tab bar)

    private static let bottomBarHeight: CGFloat = 42.0
    private var bottomEdgeEffect: EdgeEffectView?
    private var isBottomSearchActive = false

    // Active-mode subviews (text field goes inside the existing pill)
    private var bottomSearchTextField: UITextField?
    private var bottomSearchCloseButton: GlassBarButtonView?

    private func buildBottomSearchBar() {
        // Edge effect
        let edge = EdgeEffectView()
        edge.isUserInteractionEnabled = false
        view.addSubview(edge)
        bottomEdgeEffect = edge

        // Glass pill
        let bg = GlassBackgroundView(style: .regular)
        bg.isUserInteractionEnabled = true
        view.addSubview(bg)
        bottomSearchBar = bg

        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: config)?.withRenderingMode(.alwaysTemplate))
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

        let tap = UITapGestureRecognizer(target: self, action: #selector(bottomSearchTapped))
        bg.addGestureRecognizer(tap)

        layoutBottomBar()
    }

    private var bottomBarY: CGFloat {
        let safeBottom = view.safeAreaInsets.bottom
        return view.bounds.height - max(25.0, safeBottom + 8.0) - Self.bottomBarHeight
    }

    private func layoutBottomBar() {
        let h = Self.bottomBarHeight
        let side: CGFloat = 16.0
        let y = bottomBarY
        let isDark = traitCollection.userInterfaceStyle == .dark

        // Edge effect
        if let edge = bottomEdgeEffect {
            let edgeH: CGFloat = 48.0
            let edgeFrame = CGRect(x: 0, y: y - edgeH, width: view.bounds.width, height: edgeH + h + (view.bounds.height - y - h))
            edge.frame = edgeFrame
            edge.update(content: .systemBackground, blur: true, alpha: 0.65,
                        rect: CGRect(origin: .zero, size: edgeFrame.size),
                        edge: .bottom, edgeSize: edgeH, blurRadiusAtEdge: 3.0, blurRadiusAtFade: 3.0,
                        transition: .immediate)
        }

        guard let bg = bottomSearchBar else { return }
        if isBottomSearchActive { return } // active mode manages its own frames

        let frame = CGRect(x: side, y: y, width: view.bounds.width - side * 2, height: h)
        bg.frame = frame
        bg.update(size: frame.size, cornerRadius: h / 2, isDark: isDark,
                  tintColor: .init(kind: .panel), isInteractive: false, isVisible: true, transition: .immediate)

        let iconSize: CGFloat = 18
        bottomSearchIcon?.frame = CGRect(x: 14, y: (h - iconSize) / 2, width: iconSize, height: iconSize)
        bottomSearchLabel?.frame = CGRect(x: 14 + iconSize + 6, y: 0, width: frame.width - 48, height: h)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !hasTabBar {
            layoutBottomBar()
            if isBottomSearchActive {
                layoutBottomSearchActive()
            }
        }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        if isBottomSearchActive, let inputH = layout.inputHeight, inputH > 0 {
            layoutBottomSearchActive(keyboardHeight: inputH)
        } else if isBottomSearchActive {
            layoutBottomSearchActive(keyboardHeight: 0)
        }
    }

    @objc private func bottomSearchTapped() {
        activateBottomSearch()
    }

    private func activateBottomSearch() {
        guard !isBottomSearchActive else { return }
        isBottomSearchActive = true

        let h = Self.bottomBarHeight

        // Replace label placeholder with real text field inside the same pill
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

        // Close button appears to the right
        let closeIcon = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        let close = GlassBarButtonView(icon: closeIcon, state: .glass)
        close.contentTintColor = .label
        close.action = { [weak self] _ in self?.deactivateBottomSearch() }
        close.alpha = 0
        close.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        view.addSubview(close)
        bottomSearchCloseButton = close

        // Position text field at full width initially, close button at right edge
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

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            // Close button fades + shrinks
            self.bottomSearchCloseButton?.alpha = 0
            self.bottomSearchCloseButton?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            // Pill expands back to full width
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
        let spacing: CGFloat = 8.0

        let kbH = keyboardHeight ?? currentlyAppliedLayout?.inputHeight ?? 0
        let baseY: CGFloat
        if kbH > 0 {
            baseY = view.bounds.height - kbH - h - 8
        } else {
            baseY = bottomBarY
        }

        // Close button at right
        let closeX = view.bounds.width - side - h
        bottomSearchCloseButton?.frame = CGRect(x: closeX, y: baseY, width: h, height: h)

        // Pill shrinks to make room for close button
        let pillWidth = closeX - side - spacing
        let pillFrame = CGRect(x: side, y: baseY, width: pillWidth, height: h)
        bottomSearchBar?.frame = pillFrame
        bottomSearchBar?.update(size: pillFrame.size, cornerRadius: h / 2, isDark: isDark,
                                tintColor: .init(kind: .panel), isInteractive: false, isVisible: true, transition: .immediate)

        // Text field fills the pill
        bottomSearchTextField?.frame = CGRect(x: 8, y: 0, width: pillWidth - 16, height: h)

        // Edge effect follows
        if let edge = bottomEdgeEffect {
            let edgeH: CGFloat = 48.0
            let edgeFrame = CGRect(x: 0, y: baseY - edgeH, width: view.bounds.width, height: view.bounds.height - baseY + edgeH)
            edge.frame = edgeFrame
            edge.update(content: .systemBackground, blur: true, alpha: 0.65,
                        rect: CGRect(origin: .zero, size: edgeFrame.size),
                        edge: .bottom, edgeSize: edgeH, blurRadiusAtEdge: 3.0, blurRadiusAtFade: 3.0,
                        transition: .immediate)
        }
    }

    // MARK: - Nav Bar Search

    private var isNavSearchActive = false
    private var navSearchTextField: UITextField?
    private var navSearchCloseButton: GlassBarButtonView?

    override func tabBarActivateSearch() {
        activateNavBarSearch()
    }

    override func tabBarDeactivateSearch() {
        deactivateNavBarSearch()
    }

    private func activateNavBarSearch() {
        guard hasTabBar, !isNavSearchActive, let searchPill = navSearchBar else { return }
        isNavSearchActive = true

        // Hide placeholder content, add real text field inside the pill
        searchPill.subviews.forEach { $0.isHidden = true }

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
        searchPill.addSubview(tf)
        tf.frame = CGRect(x: 8, y: 0, width: searchPill.bounds.width - 16, height: searchPill.bounds.height)
        tf.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navSearchTextField = tf

        // Swap to search-only content (pill moves up to title area, filters hidden)
        let searchOnlyContent = CrystalStackedBarContent(views: [searchPill])
        navigationBarContent = searchOnlyContent

        // Create close button in the nav bar's right area
        let closeIcon = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        let close = GlassBarButtonView(icon: closeIcon, state: .glass)
        close.contentTintColor = .label
        close.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        close.alpha = 0
        close.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        let closeBarItem = UIBarButtonItem(customView: close)
        close.action = { [weak self] _ in self?.deactivateNavBarSearch() }
        navSearchCloseButton = close
        navigationItem.rightBarButtonItem = closeBarItem

        tf.becomeFirstResponder()

        requestLayout(transition: .animated(duration: 0.35, curve: .spring))

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.2, options: [.beginFromCurrentState]) {
            close.alpha = 1
            close.transform = .identity
        }
    }

    private func deactivateNavBarSearch() {
        guard isNavSearchActive, let searchPill = navSearchBar else { return }
        isNavSearchActive = false
        navSearchTextField?.resignFirstResponder()

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            self.navSearchCloseButton?.alpha = 0
            self.navSearchCloseButton?.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        } completion: { _ in
            // Remove text field, restore pill subviews
            self.navSearchTextField?.removeFromSuperview()
            self.navSearchTextField = nil
            self.navSearchCloseButton = nil
            searchPill.subviews.forEach { $0.isHidden = false }

            // Restore original right bar button
            let addButton = UIBarButtonItem(
                image: UIImage(systemName: "plus.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)),
                style: .plain,
                target: self,
                action: #selector(self.addTapped)
            )
            self.navigationItem.rightBarButtonItem = addButton

            // Restore stacked content (search + filters)
            self.navigationBarContent = self.stackedContent
            self.requestLayout(transition: .animated(duration: 0.35, curve: .spring))
        }
    }

    @objc private func editTapped() {}
    @objc private func shieldTapped() {}

    @objc private func addTapped() {
        // Figma-style modal demo — opens a sticker-pack sheet that slides up
        // from the bottom with glass X/⋯ nav bar and a blue action pill.
        let modal = StickerPackModalController(
            navigationBarPresentationData: NavigationBarPresentationData(theme: .liquidGlass())
        )
        presentModal(modal, animated: true)
    }

    @objc private func composeTapped() {}
}

extension ChatListExampleController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chats.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Chat", for: indexPath) as! ChatCell
        cell.configure(with: chats[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let detail = ChatDetailExampleController(title: chats[indexPath.row].title)
        push(detail)
    }
}

private final class ChatCell: UITableViewCell {
    private let avatarView = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.textAlignment = .center
        avatarView.layer.cornerRadius = 24
        avatarView.clipsToBounds = true
        avatarView.font = .systemFont(ofSize: 22)
        contentView.addSubview(avatarView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .systemBlue
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 48),
            avatarView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with preview: ChatPreview) {
        avatarView.backgroundColor = preview.color.withAlphaComponent(0.85)
        avatarView.text = preview.emoji
        titleLabel.text = preview.title
        subtitleLabel.text = preview.subtitle
        if preview.subtitle.hasPrefix("online") {
            subtitleLabel.textColor = .systemBlue
        } else {
            subtitleLabel.textColor = .secondaryLabel
        }
    }
}

private final class ChatFilterBarContent: NavigationBarContentView {
    private let glassBackground = GlassBackgroundView(style: .regular)
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private let filters: [(String, Int?)] = [
        ("Все", nil),
        ("Личное", 96),
        ("Melodoius", nil),
        ("Работа", nil),
        ("Друзья", nil),
    ]

    override var mode: NavigationBarContentMode { .expansion }
    override var height: CGFloat { 52.0 }
    override var nominalHeight: CGFloat { 52.0 }

    override init(frame: CGRect) {
        super.init(frame: frame)

        // The entire filter row sits inside one glass capsule (matches the
        // Figma reference where "All / Channels / Bots" live inside a single
        // pill, and only the *selected* chip has a subtle inner highlight).
//        glassBackground.isUserInteractionEnabled = false
        addSubview(glassBackground)

        scrollView.showsHorizontalScrollIndicator = false
        glassBackground.contentView.addSubview(scrollView)

        stack.axis = .horizontal
        stack.spacing = 0
        stack.alignment = .center
        scrollView.addSubview(stack)

        for (index, (title, badge)) in filters.enumerated() {
            let chip = FilterChip(title: title, badge: badge, isSelected: index == 1)
            stack.addArrangedSubview(chip)
        }
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGSize {
        let hMargin: CGFloat = 16.0
        let vMargin: CGFloat = 4.0
        let glassFrame = CGRect(
            x: hMargin + leftInset,
            y: vMargin,
            width: size.width - (hMargin + leftInset + hMargin + rightInset),
            height: size.height - vMargin * 2
        )
        glassBackground.frame = glassFrame
        glassBackground.update(
            size: glassFrame.size,
            cornerRadius: glassFrame.height * 0.5,
            isDark: traitCollection.userInterfaceStyle == .dark,
            tintColor: .init(kind: .panel),
            isInteractive: true,
            isVisible: true,
            transition: transition
        )

        scrollView.frame = CGRect(origin: .zero, size: glassFrame.size)
        let contentSize = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        stack.frame = CGRect(x: 4.0, y: 0.0, width: contentSize.width, height: glassFrame.height)
        scrollView.contentSize = CGSize(width: stack.frame.maxX + 4.0, height: glassFrame.height)
        return size
    }
}

private final class FilterChip: UIView {
    init(title: String, badge: Int?, isSelected: Bool) {
        super.init(frame: .zero)

        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        backgroundColor = isSelected ? UIColor.secondarySystemBackground : .clear

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = isSelected ? .label : .secondaryLabel
        addSubview(label)

        let badgeView: UIView?
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
            NSLayoutConstraint.activate([
                bl.leadingAnchor.constraint(equalTo: bv.leadingAnchor, constant: 6),
                bl.trailingAnchor.constraint(equalTo: bv.trailingAnchor, constant: -6),
                bl.centerYAnchor.constraint(equalTo: bv.centerYAnchor),
                bv.heightAnchor.constraint(equalToConstant: 22),
                bv.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            ])
            addSubview(bv)
            badgeView = bv
        } else {
            badgeView = nil
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 36),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        if let badgeView {
            NSLayoutConstraint.activate([
                badgeView.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
                badgeView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                badgeView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            ])
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class ChatListTitleView: UIView {
    private let label = UILabel()
    private let iconView = UIImageView()

    init(text: String) {
        super.init(frame: .zero)

        label.text = text
        label.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        label.textColor = .label
        addSubview(label)

        iconView.image = UIImage(systemName: "paperplane.fill")
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.setMonochromaticEffect(tintColor: .systemBlue)
        addSubview(iconView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        let textSize = label.intrinsicContentSize
        let iconSize: CGFloat = 18.0
        let spacing: CGFloat = 6.0
        return CGSize(width: textSize.width + spacing + iconSize, height: max(22.0, textSize.height))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    override func layoutSubviews() {
        super.layoutSubviews()
        let textSize = label.sizeThatFits(bounds.size)
        let iconSize: CGFloat = 18.0
        let spacing: CGFloat = 6.0
        label.frame = CGRect(x: 0.0, y: floor((bounds.height - textSize.height) / 2.0), width: textSize.width, height: textSize.height)
        iconView.frame = CGRect(x: label.frame.maxX + spacing, y: floor((bounds.height - iconSize) / 2.0), width: iconSize, height: iconSize)
    }
}

final class ChatDetailExampleController: ViewController {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputBar = ChatInputBar()
    private var inputBarBottomConstraint: NSLayoutConstraint!

    private struct Message {
        let text: String
        let isOutgoing: Bool
    }

    private let messages: [Message] = [
        Message(text: "Hey! How's it going?", isOutgoing: false),
        Message(text: "All good! Just testing CrystalWindow", isOutgoing: true),
        Message(text: "Nice! Does the keyboard track properly?", isOutgoing: false),
        Message(text: "Let me check the interactive dismissal...", isOutgoing: true),
        Message(text: "Try swiping down from above the keyboard!", isOutgoing: false),
        Message(text: "That's the pan gesture we ported from Telegram", isOutgoing: true),
        Message(text: "Cool, it should follow your finger and dismiss if you swipe fast enough", isOutgoing: false),
        Message(text: "Or snap back if you don't drag far enough", isOutgoing: true),
        Message(text: "Also check that the layout updates smoothly when the keyboard appears and disappears", isOutgoing: false),
        Message(text: "The inputHeight from ContainerViewLayout should propagate all the way here", isOutgoing: true),
        Message(text: "From CrystalWindow -> TabBarController -> NavigationController -> this ViewController", isOutgoing: false),
        Message(text: "Exactly! The whole chain is keyboard-aware now", isOutgoing: true),
    ]

    init(title: String) {
        super.init(navigationBarPresentationData: nil)
        navigationItem.title = title
        // TODO: CrystalTabBarController doesn't honor hidesBottomBarWhenPushed yet
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        // Keyboard dismiss is handled by CrystalWindow's pan gesture;
        // don't use UIKit's .interactive mode as it conflicts.
        tableView.keyboardDismissMode = .none
        tableView.dataSource = self
        tableView.register(MessageCell.self, forCellReuseIdentifier: "Message")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.contentInsetAdjustmentBehavior = .automatic
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        view.addSubview(tableView)

        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBar)

        inputBarBottomConstraint = inputBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBarBottomConstraint,
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToBottom(animated: false)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let keyboardHeight = layout.inputHeight ?? 0
        let bottomInset: CGFloat
        if keyboardHeight > 0 {
            // Keyboard visible: position input bar above the keyboard
            bottomInset = -keyboardHeight
        } else {
            // No keyboard: input bar sits at the bottom (safe area handled by the bar itself)
            bottomInset = 0
        }

        inputBarBottomConstraint.constant = bottomInset
        inputBar.updateBottomPadding(keyboardHeight > 0 ? 0 : view.safeAreaInsets.bottom)
        transition.animateView { self.view.layoutIfNeeded() }
    }

    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty else { return }
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }
}

extension ChatDetailExampleController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Message", for: indexPath) as! MessageCell
        cell.configure(with: messages[indexPath.row].text, isOutgoing: messages[indexPath.row].isOutgoing)
        return cell
    }
}

// MARK: - Chat Input Bar

private final class ChatInputBar: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let separator = UIView()
    private var bottomPadding: CGFloat = 0
    private var bottomPaddingConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        addSubview(separator)

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = "Сообщение"
        textField.borderStyle = .none
        textField.backgroundColor = .secondarySystemBackground
        textField.layer.cornerRadius = 18
        textField.layer.cornerCurve = .continuous
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        textField.rightViewMode = .always
        textField.font = .systemFont(ofSize: 16)
        addSubview(textField)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)), for: .normal)
        sendButton.tintColor = .systemBlue
        addSubview(sendButton)

        bottomPaddingConstraint = textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            textField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textField.heightAnchor.constraint(equalToConstant: 36),
            bottomPaddingConstraint,

            sendButton.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
            sendButton.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
            sendButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateBottomPadding(_ padding: CGFloat) {
        let constant = -(8 + padding)
        if bottomPaddingConstraint.constant != constant {
            bottomPaddingConstraint.constant = constant
        }
    }
}

// MARK: - Message Cell

private final class MessageCell: UITableViewCell {
    private let bubbleView = UIView()
    private let messageLabel = UILabel()
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.layer.cornerRadius = 16
        bubbleView.layer.cornerCurve = .continuous
        contentView.addSubview(bubbleView)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.numberOfLines = 0
        messageLabel.font = .systemFont(ofSize: 16)
        bubbleView.addSubview(messageLabel)

        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.75),

            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with text: String, isOutgoing: Bool) {
        messageLabel.text = text
        if isOutgoing {
            bubbleView.backgroundColor = UIColor.systemBlue
            messageLabel.textColor = .white
            leadingConstraint.isActive = false
            trailingConstraint.isActive = true
        } else {
            bubbleView.backgroundColor = UIColor.secondarySystemBackground
            messageLabel.textColor = .label
            trailingConstraint.isActive = false
            leadingConstraint.isActive = true
        }
    }
}
