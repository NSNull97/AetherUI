import UIKit
import CrystalUI

/// Sticker-pack modal content. Presented wrapped in `CrystalModalController`
/// via standard UIKit `present(_:animated:)`.
final class StickerPackModalController: UIViewController {
    let collectionView: UICollectionView
    private let actionButton = UIButton(type: .system)

    private let headerContainer = UIView()
    private let closeButton = GlassButton(image: UIImage(systemName: "xmark"))
    private let moreButton = GlassButton(image: UIImage(systemName: "ellipsis"))
    private let titleCapsule = GlassBackgroundView(style: .regular)
    private let titleLabel = UILabel()

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

    init() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 64, height: 64)
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(EmojiCell.self, forCellWithReuseIdentifier: "Emoji")
        view.addSubview(collectionView)

        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerContainer)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.action = { [weak self] _ in self?.closeTapped() }
        headerContainer.addSubview(closeButton)

        moreButton.translatesAutoresizingMaskIntoConstraints = false
        moreButton.action = { [weak self] _ in self?.moreTapped() }
        headerContainer.addSubview(moreButton)

        titleCapsule.translatesAutoresizingMaskIntoConstraints = false
        headerContainer.addSubview(titleCapsule)

        titleLabel.text = "@smilemyllove"
        titleLabel.font = .systemFont(ofSize: 17.0, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleCapsule.contentView.addSubview(titleLabel)

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

        NSLayoutConstraint.activate([
            headerContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            headerContainer.heightAnchor.constraint(equalToConstant: 44),

            closeButton.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            moreButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            moreButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44),

            titleCapsule.centerXAnchor.constraint(equalTo: headerContainer.centerXAnchor),
            titleCapsule.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            titleCapsule.heightAnchor.constraint(equalToConstant: 36),
            titleCapsule.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),

            titleLabel.topAnchor.constraint(equalTo: titleCapsule.contentView.topAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: titleCapsule.contentView.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: titleCapsule.contentView.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: titleCapsule.contentView.trailingAnchor, constant: -18),

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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let topOverlap = headerContainer.frame.maxY + 8
        let bottomOverlap: CGFloat = 50 + 24
        let insets = UIEdgeInsets(top: topOverlap, left: 0, bottom: bottomOverlap, right: 0)
        if collectionView.contentInset != insets {
            collectionView.contentInset = insets
            collectionView.verticalScrollIndicatorInsets = insets
        }
        titleCapsule.update(size: titleCapsule.bounds.size, cornerRadius: 18, transition: .immediate)
    }

    private func closeTapped() {
        dismiss(animated: true)
    }

    private func moreTapped() {}

    @objc private func addTapped() {
        dismiss(animated: true)
    }
}

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
