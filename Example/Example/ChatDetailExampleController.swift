import UIKit
import CrystalUI

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
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .none
        tableView.dataSource = self
        tableView.register(MessageCell.self, forCellReuseIdentifier: "Message")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.contentInsetAdjustmentBehavior = .automatic
        if #available(iOS 15.0, *) { tableView.sectionHeaderTopPadding = 0 }
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
        let kbH = layout.inputHeight ?? 0
        inputBarBottomConstraint.constant = kbH > 0 ? -kbH : 0
        inputBar.updateBottomPadding(kbH > 0 ? 0 : view.safeAreaInsets.bottom)
        transition.animateView { self.view.layoutIfNeeded() }
    }

    private func scrollToBottom(animated: Bool) {
        guard !messages.isEmpty else { return }
        tableView.scrollToRow(at: IndexPath(row: messages.count - 1, section: 0), at: .bottom, animated: animated)
    }
}

extension ChatDetailExampleController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { messages.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Message", for: indexPath) as! MessageCell
        let m = messages[indexPath.row]
        cell.configure(with: m.text, isOutgoing: m.isOutgoing)
        return cell
    }
}

// MARK: - Chat Input Bar

private final class ChatInputBar: UIView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let separator = UIView()
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
            blurView.topAnchor.constraint(equalTo: topAnchor), blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor), blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor), separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor), separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textField.heightAnchor.constraint(equalToConstant: 36), bottomPaddingConstraint,
            sendButton.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
            sendButton.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 32), sendButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateBottomPadding(_ padding: CGFloat) {
        let c = -(8 + padding)
        if bottomPaddingConstraint.constant != c { bottomPaddingConstraint.constant = c }
    }
}

// MARK: - Message Cell

private final class MessageCell: UITableViewCell {
    private let bubbleView = UIView()
    private let messageLabel = UILabel()
    private var leadingC: NSLayoutConstraint!
    private var trailingC: NSLayoutConstraint!

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
        leadingC = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12)
        trailingC = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12)
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
            bubbleView.backgroundColor = .systemBlue; messageLabel.textColor = .white
            leadingC.isActive = false; trailingC.isActive = true
        } else {
            bubbleView.backgroundColor = .secondarySystemBackground; messageLabel.textColor = .label
            trailingC.isActive = false; leadingC.isActive = true
        }
    }
}
