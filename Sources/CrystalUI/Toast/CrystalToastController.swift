import UIKit

public struct CrystalToastAction: Equatable {
    public let title: String
    public let handler: () -> Void

    public init(title: String, handler: @escaping () -> Void) {
        self.title = title
        self.handler = handler
    }

    public static func == (lhs: CrystalToastAction, rhs: CrystalToastAction) -> Bool {
        return lhs.title == rhs.title
    }
}

public enum CrystalToastContent {
    /// Plain text, no icon, no action.
    case text(String)
    /// Leading icon + text.
    case iconAndText(UIImage, String)
    /// Text + trailing action button (e.g. "Undo").
    case textAndAction(String, CrystalToastAction)
    /// Icon + text + trailing action button.
    case iconTextAndAction(UIImage, String, CrystalToastAction)

    fileprivate var plainText: String {
        switch self {
        case let .text(t), let .iconAndText(_, t), let .textAndAction(t, _), let .iconTextAndAction(_, t, _):
            return t
        }
    }

    fileprivate var image: UIImage? {
        switch self {
        case let .iconAndText(img, _), let .iconTextAndAction(img, _, _): return img
        case .text, .textAndAction: return nil
        }
    }

    fileprivate var action: CrystalToastAction? {
        switch self {
        case let .textAndAction(_, a), let .iconTextAndAction(_, _, a): return a
        case .text, .iconAndText: return nil
        }
    }
}

public struct CrystalToastTheme: Equatable {
    public let backgroundColor: UIColor
    public let textColor: UIColor
    public let actionColor: UIColor
    public let iconTintColor: UIColor?
    public let cornerRadius: CGFloat
    public let textFont: UIFont
    public let actionFont: UIFont

    public init(
        backgroundColor: UIColor,
        textColor: UIColor,
        actionColor: UIColor,
        iconTintColor: UIColor? = nil,
        cornerRadius: CGFloat = 14.0,
        textFont: UIFont = .systemFont(ofSize: 14.0),
        actionFont: UIFont = .systemFont(ofSize: 14.0, weight: .semibold)
    ) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.actionColor = actionColor
        self.iconTintColor = iconTintColor
        self.cornerRadius = cornerRadius
        self.textFont = textFont
        self.actionFont = actionFont
    }

    public static let dark = CrystalToastTheme(
        backgroundColor: UIColor(white: 0.1, alpha: 0.94),
        textColor: .white,
        actionColor: UIColor(red: 0.3, green: 0.68, blue: 1.0, alpha: 1.0),
        iconTintColor: .white
    )

    public static let light = CrystalToastTheme(
        backgroundColor: UIColor.white.withAlphaComponent(0.95),
        textColor: .black,
        actionColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0),
        iconTintColor: .black
    )
}

/// Snackbar-style transient banner — mounted at the bottom of the window.
/// Analog of Telegram-iOS UndoOverlayController. Slide up from below,
/// auto-dismiss after `timeout`. Tap-to-dismiss always on; action button
/// fires its handler then dismisses.
public final class CrystalToastController {
    public var theme: CrystalToastTheme
    public let content: CrystalToastContent
    public var timeout: TimeInterval = 3.0
    public var dismissed: (() -> Void)?

    private weak var hostView: UIView?
    private var rootView: CrystalToastRootView?
    private var dismissWorkItem: DispatchWorkItem?

    /// Self-pin set. Callers typically do
    /// `CrystalToastController(content:).present()` without capturing the
    /// returned controller, so we'd otherwise deallocate (and tear down
    /// the root view) right after the initializer returns. Inserting
    /// `self` here keeps us alive until `dismiss` clears the entry.
    private static var liveToasts: [CrystalToastController] = []

    public init(
        content: CrystalToastContent,
        theme: CrystalToastTheme = .dark,
        timeout: TimeInterval = 3.0
    ) {
        self.content = content
        self.theme = theme
        self.timeout = timeout
    }

    /// Present. If `parent` is nil, mounts into the app's active key
    /// window so the snackbar floats above every nav bar / tab bar / modal.
    public func present(in parent: UIView? = nil) {
        let target: UIView? = parent ?? Self.findActiveWindow()
        guard let target else { return }

        dismiss(animated: false)
        hostView = target

        // Keep self alive while on-screen — see `liveToasts` doc above.
        if !Self.liveToasts.contains(where: { $0 === self }) {
            Self.liveToasts.append(self)
        }

        let root = CrystalToastRootView(content: content, theme: theme)
        root.onTap = { [weak self] in self?.dismiss(animated: true) }
        root.onAction = { [weak self] handler in
            handler()
            self?.dismiss(animated: true)
        }
        root.frame = target.bounds
        root.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        target.addSubview(root)
        root.setNeedsLayout()
        root.layoutIfNeeded()
        root.animateIn()
        rootView = root

        let work = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    public func dismiss(animated: Bool) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        let root = rootView
        rootView = nil

        let unpin: () -> Void = { [weak self] in
            guard let self else { return }
            Self.liveToasts.removeAll(where: { $0 === self })
        }

        guard let root else { unpin(); dismissed?(); return }
        if animated {
            root.animateOut { [weak self] in
                root.removeFromSuperview()
                unpin()
                self?.dismissed?()
            }
        } else {
            root.removeFromSuperview()
            unpin()
            dismissed?()
        }
    }

    /// Walk the connected-scenes graph to the top-most visible view
    /// controller (respecting modals). Returns nil when called before any
    /// window is attached — caller should guard.
    /// Return the app's active key window. Used to mount overlays that need
    /// to float above every controller (tabs, modals, sheets). Walks
    /// `connectedScenes` so it picks the right window in multi-scene apps.
    static func findActiveWindow() -> UIWindow? {
        // Prefer a foreground-active scene; fall back to any scene if the
        // app is launched but not yet foregrounded (e.g. during startup).
        let scenes = UIApplication.shared.connectedScenes
        let candidates = scenes.filter { $0.activationState == .foregroundActive } + scenes.filter { $0.activationState != .foregroundActive }
        for scene in candidates {
            guard let ws = scene as? UIWindowScene else { continue }
            if #available(iOS 15.0, *) {
                if let kw = ws.keyWindow { return kw }
            }
            if let kw = ws.windows.first(where: { $0.isKeyWindow }) { return kw }
            if let first = ws.windows.first { return first }
        }
        return nil
    }

    /// Back-compat entry point used by other CrystalUI components — still
    /// walks down through tab bars / nav controllers to find the top-most
    /// presented VC. Prefer `findActiveWindow` for overlay mounting.
    static func topViewController() -> UIViewController? {
        guard var vc: UIViewController = findActiveWindow()?.rootViewController else { return nil }
        var guardCounter = 0
        while guardCounter < 20 {
            guardCounter += 1
            if let presented = vc.presentedViewController {
                vc = presented
                continue
            }
            if let tab = vc as? CrystalTabBarController, let current = tab.currentController {
                vc = current
                continue
            }
            if let tab = vc as? UITabBarController, let sel = tab.selectedViewController {
                vc = sel
                continue
            }
            if let nav = vc as? UINavigationController, let top = nav.topViewController {
                vc = top
                continue
            }
            break
        }
        return vc
    }

    deinit {
        dismissWorkItem?.cancel()
        rootView?.removeFromSuperview()
    }
}

// MARK: - Root view

final class CrystalToastRootView: UIView {
    var onTap: () -> Void = {}
    var onAction: (@escaping () -> Void) -> Void = { _ in }
    var cardFrame: CGRect { card.frame }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        // Insets propagate from window → root asynchronously after attach.
        // Re-layout once they're real so the card doesn't sit hidden under
        // the home indicator on the first frame.
        setNeedsLayout()
    }

    private let content: CrystalToastContent
    private let theme: CrystalToastTheme

    private let card = UIView()
    private let textLabel = UILabel()
    private let iconView = UIImageView()
    private let actionButton = UIButton(type: .system)
    /// Vertical separator between text area and action button (only shown
    /// when there's an action).
    private let actionSeparator = UIView()

    private static let horizontalInset: CGFloat = 16.0
    private static let verticalInset: CGFloat = 10.0
    private static let iconSize: CGFloat = 24.0
    private static let iconTextSpacing: CGFloat = 10.0
    private static let actionSpacing: CGFloat = 12.0
    private static let screenMargin: CGFloat = 10.0
    private static let bottomMargin: CGFloat = 10.0
    private static let minCardHeight: CGFloat = 48.0

    init(content: CrystalToastContent, theme: CrystalToastTheme) {
        self.content = content
        self.theme = theme
        super.init(frame: .zero)

        card.backgroundColor = theme.backgroundColor
        card.layer.cornerRadius = theme.cornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.18
        card.layer.shadowRadius = 12.0
        card.layer.shadowOffset = CGSize(width: 0, height: 4)
        addSubview(card)

        textLabel.textColor = theme.textColor
        textLabel.font = theme.textFont
        textLabel.numberOfLines = 0
        textLabel.isUserInteractionEnabled = false
        card.addSubview(textLabel)

        if let image = content.image {
            iconView.image = theme.iconTintColor != nil ? image.withRenderingMode(.alwaysTemplate) : image
            iconView.tintColor = theme.iconTintColor
            iconView.contentMode = .scaleAspectFit
            iconView.isUserInteractionEnabled = false
            card.addSubview(iconView)
        }

        switch content {
        case .text(let t), .iconAndText(_, let t):
            textLabel.text = t
        case .textAndAction(let t, let action), .iconTextAndAction(_, let t, let action):
            textLabel.text = t
            actionButton.titleLabel?.font = theme.actionFont
            actionButton.setTitle(action.title, for: .normal)
            actionButton.setTitleColor(theme.actionColor, for: .normal)
            actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
            card.addSubview(actionButton)

            actionSeparator.backgroundColor = theme.textColor.withAlphaComponent(0.15)
            card.addSubview(actionSeparator)
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(cardTapped))
        card.addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let size = bounds.size
        let sideInset = Self.screenMargin + safeAreaInsets.left
        let rightInset = Self.screenMargin + safeAreaInsets.right
        let maxCardWidth = min(560.0, size.width - sideInset - rightInset)

        let hasIcon = iconView.image != nil
        let hasAction = content.action != nil

        let iconSlot: CGFloat = hasIcon ? (Self.iconSize + Self.iconTextSpacing) : 0
        let actionTitleSize: CGSize
        if hasAction {
            actionButton.sizeToFit()
            actionTitleSize = actionButton.bounds.size
        } else {
            actionTitleSize = .zero
        }
        let actionSlot: CGFloat = hasAction ? (Self.actionSpacing + actionTitleSize.width + Self.horizontalInset) : 0

        let textBox = CGSize(
            width: maxCardWidth - Self.horizontalInset * 2 - iconSlot - actionSlot,
            height: .greatestFiniteMagnitude
        )
        let textFits = textLabel.sizeThatFits(textBox)

        let contentHeight = max(Self.iconSize, textFits.height)
        let cardHeight = max(Self.minCardHeight, contentHeight + Self.verticalInset * 2)
        let cardWidth = min(
            maxCardWidth,
            Self.horizontalInset * 2 + iconSlot + textFits.width + actionSlot
        )

        let cardX = floor((size.width - cardWidth) / 2)
        let cardY = size.height - safeAreaInsets.bottom - Self.bottomMargin - cardHeight
        card.frame = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)

        var x = Self.horizontalInset
        if hasIcon {
            iconView.frame = CGRect(
                x: x,
                y: (cardHeight - Self.iconSize) / 2,
                width: Self.iconSize,
                height: Self.iconSize
            )
            x += Self.iconSize + Self.iconTextSpacing
        }

        let textWidth = cardWidth - x - (hasAction ? actionSlot : Self.horizontalInset)
        textLabel.frame = CGRect(
            x: x,
            y: (cardHeight - textFits.height) / 2,
            width: textWidth,
            height: textFits.height
        )

        if hasAction {
            let sepX = cardWidth - Self.horizontalInset - actionTitleSize.width - Self.actionSpacing
            actionSeparator.frame = CGRect(
                x: sepX,
                y: 10,
                width: 1.0 / UIScreen.main.scale,
                height: cardHeight - 20
            )
            actionButton.frame = CGRect(
                x: sepX + Self.actionSpacing,
                y: 0,
                width: actionTitleSize.width + Self.horizontalInset,
                height: cardHeight
            )
        }
    }

    func animateIn() {
        layoutIfNeeded()
        let travel = bounds.height - card.frame.minY
        card.transform = CGAffineTransform(translationX: 0, y: travel)
        card.alpha = 0.0
        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.2,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.card.alpha = 1.0
            self.card.transform = .identity
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        // Travel distance is computed from card.bounds (non-transformed —
        // reflects the laid-out size only), NOT from card.frame (which is
        // transform-aware and would return mid-flight values while
        // animateIn is still running). Plus a safety margin so the card
        // clears any home-indicator / safe-area overshoot.
        //
        // `.beginFromCurrentState` means the animation smoothly continues
        // from wherever animateIn had the card in-flight — no "jump back
        // to rest position then slide down" glitch.
        let travel = card.bounds.height + safeAreaInsets.bottom + Self.bottomMargin + 8.0
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.card.alpha = 0.0
            self.card.transform = CGAffineTransform(translationX: 0, y: travel)
        } completion: { _ in completion() }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if card.frame.contains(point) {
            return super.hitTest(point, with: event)
        }
        return nil
    }

    @objc private func cardTapped() {
        onTap()
    }

    @objc private func actionTapped() {
        guard let action = content.action else { return }
        onAction(action.handler)
    }
}
