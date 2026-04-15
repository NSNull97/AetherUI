import UIKit
import TelegramNavigationKit

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
        let barTheme = NavigationBarTheme.liquidGlass()
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: barTheme))

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

        // Install the filter chip bar as a NavigationBarContentView in
        // `.expansion` mode. The TabBar controller forwards it to the shared
        // nav bar; `additionalSafeAreaInsets.top` is recomputed to include it.
        self.navigationBarContent = filterBar

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
    init(title: String) {
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: .liquidGlass()))
        navigationItem.title = title
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Chat detail: \(navigationItem.title ?? "")"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .label
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
