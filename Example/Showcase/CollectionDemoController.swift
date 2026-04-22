import UIKit
import CrystalUI

struct CollectionDemoItem {
    let emoji: String
    let title: String
    let subtitle: String
    let color: UIColor
}

/// Grid-style collection used to exercise the Liquid-Glass tab bar's
/// edge effect under a real scrolling surface. Each card is a pastel
/// rounded-rect with an emoji + title + subtitle so the scroll looks
/// alive rather than blank rows.
final class CollectionDemoController: ViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private var collectionView: UICollectionView!

    private let items: [CollectionDemoItem] = {
        let palette: [UIColor] = [
            UIColor(red: 1.00, green: 0.84, blue: 0.72, alpha: 1), // peach
            UIColor(red: 0.78, green: 0.90, blue: 1.00, alpha: 1), // sky
            UIColor(red: 0.84, green: 0.92, blue: 0.76, alpha: 1), // lime
            UIColor(red: 1.00, green: 0.76, blue: 0.78, alpha: 1), // pink
            UIColor(red: 0.87, green: 0.80, blue: 1.00, alpha: 1), // lavender
            UIColor(red: 0.96, green: 0.96, blue: 0.76, alpha: 1), // butter
            UIColor(red: 0.76, green: 0.96, blue: 0.92, alpha: 1), // mint
            UIColor(red: 1.00, green: 0.88, blue: 0.62, alpha: 1)  // amber
        ]
        let emojis = ["🌸", "☁️", "🌿", "🍇", "🫧", "🪄", "🌙", "🐚", "🍑", "🌴", "🦄", "🔮",
                      "🎈", "🎨", "🧸", "🪷", "🦋", "🪴", "⭐️", "💎", "🧊", "🌊", "🍀", "🍒"]
        var list: [CollectionDemoItem] = []
        for i in 0 ..< 80 {
            list.append(CollectionDemoItem(
                emoji: emojis[i % emojis.count],
                title: "Элемент \(i + 1)",
                subtitle: ["Категория A", "Категория B", "Категория C", "Категория D"][i % 4],
                color: palette[i % palette.count]
            ))
        }
        return list
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Collection"
        view.backgroundColor = .systemGroupedBackground

        let layout = UICollectionViewCompositionalLayout { _, _ in
            // 2-column grid, estimated height so cell size can grow with text.
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(0.5),
                heightDimension: .fractionalHeight(1.0)
            ))
            item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)

            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .absolute(148)
                ),
                subitems: [item]
            )

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
            return section
        }

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CollectionDemoCell.self, forCellWithReuseIdentifier: "card")
        view.addSubview(collectionView)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        var insets = layout.safeInsets
        insets.top = navigationBarView?.frame.maxY ?? insets.top
        // Pad bottom so content scrolls fully past the tab bar.
        insets.bottom = max(insets.bottom, 100)
        collectionView.contentInset = insets
        collectionView.verticalScrollIndicatorInsets = insets
    }

    // MARK: Data

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "card", for: indexPath) as! CollectionDemoCell
        cell.configure(with: items[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let item = items[indexPath.item]
        CrystalToastController(
            content: .iconAndText(
                UIImage(systemName: "hand.tap.fill") ?? UIImage(),
                "\(item.emoji) \(item.title)"
            )
        ).present()
    }
}

// MARK: - Cell

private final class CollectionDemoCell: UICollectionViewCell {
    private let emojiLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = 18
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true

        emojiLabel.font = .systemFont(ofSize: 34)
        emojiLabel.textAlignment = .left

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = UIColor(white: 0.12, alpha: 1.0)

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = UIColor(white: 0.3, alpha: 1.0)

        [emojiLabel, titleLabel, subtitleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            emojiLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            emojiLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            titleLabel.bottomAnchor.constraint(equalTo: subtitleLabel.topAnchor, constant: -2),

            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.contentView.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.97, y: 0.97)
                    : .identity
            }
        }
    }

    func configure(with item: CollectionDemoItem) {
        emojiLabel.text = item.emoji
        titleLabel.text = item.title
        subtitleLabel.text = item.subtitle
        contentView.backgroundColor = item.color
    }
}
