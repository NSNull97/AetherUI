import UIKit
import TelegramNavigationKit

/// Telegram-style sticker-pack modal sheet. Demonstrates `presentModal` on
/// `TelegramNavigationController` plus the Figma reference modal layout:
/// glass "X" close capsule (left), title capsule (centre), more-actions
/// capsule (right), scrollable grid content, bottom action pill.
final class StickerPackModalController: ViewController {
    private let collectionView: UICollectionView
    private let actionButton = UIButton(type: .system)

    private static let emojis: [String] = [
        "🔥", "🫶", "🎀", "👟", "⌚️", "🐆", "🕶", "👜",
        "🌸", "🌷", "💐", "🎀", "🎁", "💗", "📎", "🍃",
        "🚗", "🚙", "🏎", "🏍", "🛴", "🛵", "🚲", "🛼",
        "🍪", "🥐", "🥯", "🍔", "🍕", "🍣", "🍰", "🍩",
        "💄", "🧴", "🧼", "🕯", "💍", "👒", "🎩", "👛",
        "💋", "🌙", "🌞", "⭐️", "✨", "💫", "🪷", "🌺",
        "🐱", "🐶", "🐰", "🐻", "🐼", "🦊", "🐯", "🦁",
        "📷", "📱", "💻", "🎧", "📸", "🎨", "📚", "✏️",
    ]

    override init(navigationBarPresentationData: NavigationBarPresentationData?) {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 64, height: 64)
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(navigationBarPresentationData: navigationBarPresentationData)

        navigationPresentation = .modal
        navigationItem.titleView = StickerPackTitleView(username: "@smilemyllove")

        // Left: X close in a glass circle
        let closeButton = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.leftBarButtonItem = closeButton

        // Right: more-actions (⋯)
        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            style: .plain,
            target: self,
            action: #selector(moreTapped)
        )
        navigationItem.rightBarButtonItem = moreButton
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Modal content sits on top of the sheet's glass background, so the
        // root view is transparent — the chat behind shines through the
        // translucent glass frost (Apple medium-sheet appearance).
        view.backgroundColor = .clear

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.contentInsetAdjustmentBehavior = .automatic
        collectionView.register(EmojiCell.self, forCellWithReuseIdentifier: "Emoji")
        view.addSubview(collectionView)

        // Bottom action pill — Figma's big blue "Добавить N эмодзи" button.
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.setTitle("Добавить \(Self.emojis.count) эмодзи", for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        actionButton.backgroundColor = .systemBlue
        actionButton.tintColor = .white
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.layer.cornerRadius = 25
        actionButton.layer.cornerCurve = .continuous
        actionButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        view.addSubview(actionButton)
        
        //hidesBottomBarWhenPushed
        
        view.setEdgeEffect(.init(
            edge: .bottom,
            thickness: 80,
            blurRadius: 3,
            blurRadiusAtEdge: 3,
            blurRadiusAtFade: 3
        ))

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            actionButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            actionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            actionButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        // Reserve space at the bottom for the action pill.
        let actionAreaHeight: CGFloat = 50 + 24
        collectionView.contentInset = UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: actionAreaHeight,
            right: 0
        )
        collectionView.verticalScrollIndicatorInsets = collectionView.contentInset
    }

    @objc private func closeTapped() {
        dismiss()
    }

    @objc private func moreTapped() {}

    @objc private func addTapped() {
        dismiss()
    }

    private func dismiss() {
        guard let nav = self.navigationController as? TelegramNavigationController else { return }
        nav.dismissModal(animated: true)
    }
}

// MARK: - Title view

private final class StickerPackTitleView: UIView {
    private let label = UILabel()

    init(username: String) {
        super.init(frame: .zero)

        label.text = username
        label.font = .systemFont(ofSize: 17.0, weight: .semibold)
        label.textColor = .label
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        return label.intrinsicContentSize
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { label.sizeThatFits(size) }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }
}

// MARK: - Cells

private final class EmojiCell: UICollectionViewCell {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 40)
        label.textAlignment = .center
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(emoji: String) {
        label.text = emoji
    }
}

// MARK: - Data source

extension StickerPackModalController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        Self.emojis.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Emoji", for: indexPath) as! EmojiCell
        cell.configure(emoji: Self.emojis[indexPath.item])
        return cell
    }
}
