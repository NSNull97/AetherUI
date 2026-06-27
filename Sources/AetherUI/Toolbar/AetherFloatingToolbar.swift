import UIKit
import SnapKit

/// Floating "Liquid Glass" toolbar in the Safari / Mail / Messages style —
/// a horizontal strip of glass segments that can merge visually on iOS 26
/// via `UIGlassContainerEffect` while keeping independent touch targets.
///
/// Layout is segment-based: each segment is either a standalone glass
/// circle (one button), a pill holding multiple evenly-spaced icon
/// buttons (browser-style nav), or a search pill (optionally flanked by
/// leading/trailing standalone buttons). Adjacent segments render with
/// `segmentSpacing` between them so iOS 26's native glass container can
/// do its soft-merge when they're close enough.
///
/// Intended to be placed at the bottom of a view controller's content
/// with a ~16 pt side inset; see `defaultHeight` for the natural content
/// height including breathing room above the pill.
public final class AetherFloatingToolbarView: UIView {
    // MARK: - Public types

    /// One icon/title button. Renders as a glass circle when used as a
    /// `.standalone` segment, or as a bare icon tile when used inside a
    /// `.pill` segment (pill provides the shared glass background).
    public struct Button {
        public let icon: UIImage?
        public let title: String?
        public let isEnabled: Bool
        public let action: () -> Void

        public init(
            icon: UIImage? = nil,
            title: String? = nil,
            isEnabled: Bool = true,
            action: @escaping () -> Void = {}
        ) {
            self.icon = icon
            self.title = title
            self.isEnabled = isEnabled
            self.action = action
        }
    }

    /// Config for a `.search` segment.
    public struct SearchConfig {
        public var text: String
        public var placeholder: String
        /// Leading icon rendered to the left of the text field. Defaults
        /// to a system magnifying glass. Pass `nil` to hide.
        public var icon: UIImage?
        /// When `true`, a separate round glass X button sits to the
        /// right of the search pill. Tapping it fires `onClose`.
        public var showsCloseButton: Bool
        public var onTextChanged: ((String) -> Void)?
        public var onClose: (() -> Void)?

        public init(
            text: String = "",
            placeholder: String = "Search",
            icon: UIImage? = UIImage(systemName: "magnifyingglass"),
            showsCloseButton: Bool = false,
            onTextChanged: ((String) -> Void)? = nil,
            onClose: (() -> Void)? = nil
        ) {
            self.text = text
            self.placeholder = placeholder
            self.icon = icon
            self.showsCloseButton = showsCloseButton
            self.onTextChanged = onTextChanged
            self.onClose = onClose
        }
    }

    /// One segment of the toolbar. Layout works left-to-right in the
    /// declared order, fixed-width segments consume their natural size,
    /// `.search` takes the remaining horizontal space.
    public enum Segment {
        /// Several buttons in a single merged glass pill — evenly spaced
        /// across the pill's width. Used for browser nav strips.
        case pill([Button])
        /// A single glass circle holding one button.
        case standalone(Button)
        /// A glass search field (flex-width).
        case search(SearchConfig)
        /// Flexible empty space between fixed toolbar segments.
        case spacer
    }

    /// Visual theme — icon/text colors + dark-mode override.
    public struct Theme {
        public var iconColor: UIColor
        public var disabledIconColor: UIColor
        public var textColor: UIColor
        public var placeholderColor: UIColor
        /// `true`/`false` forces the glass background into dark / light
        /// regardless of trait collection; `nil` follows traits.
        public var isDarkOverride: Bool?

        public init(
            iconColor: UIColor,
            disabledIconColor: UIColor,
            textColor: UIColor,
            placeholderColor: UIColor,
            isDarkOverride: Bool? = nil
        ) {
            self.iconColor = iconColor
            self.disabledIconColor = disabledIconColor
            self.textColor = textColor
            self.placeholderColor = placeholderColor
            self.isDarkOverride = isDarkOverride
        }

        public static let light = Theme(
            iconColor: .label,
            disabledIconColor: UIColor.label.withAlphaComponent(0.28),
            textColor: .label,
            placeholderColor: .secondaryLabel,
            isDarkOverride: false
        )

        public static let dark = Theme(
            iconColor: .white,
            disabledIconColor: UIColor.white.withAlphaComponent(0.28),
            textColor: .white,
            placeholderColor: UIColor.white.withAlphaComponent(0.6),
            isDarkOverride: true
        )
    }

    // MARK: - Config

    /// Segment list. Assigning rebuilds the subview tree.
    public var segments: [Segment] = [] {
        didSet { rebuild() }
    }

    /// Visual theme (tint + dark-mode override).
    public var theme: Theme = .light {
        didSet { applyTheme() }
    }

    // MARK: - Sizing

    /// Vertical height of each glass segment (pills + circles).
    public var pillHeight: CGFloat = 49.0 {
        didSet { relayoutAfterSizingChange() }
    }

    /// Gap between adjacent segments.
    public var segmentSpacing: CGFloat = 8.0 {
        didSet { stackView.spacing = segmentSpacing }
    }

    /// Side inset at the view's left/right edges.
    public var sideInset: CGFloat = 12.0 {
        didSet { updateSideInsetConstraints() }
    }

    /// Per-button width inside a `.pill` segment. Defaults to `pillHeight`
    /// so buttons are square-ish (tap target = height) — `GlassControlGroup`
    /// sizes its items at `max(minWidth, availableHeight)`, so anything
    /// narrower than `pillHeight` gets clamped up to it anyway.
    public var pillButtonWidth: CGFloat = 49.0 {
        didSet { relayoutAfterSizingChange() }
    }

    /// Recommended parent-view height. Matches `pillHeight` exactly —
    /// the pill fills the view edge-to-edge (no centered-in-68pt layout
    /// that would leave ~9pt of empty space below the pill, which used
    /// to push the pill visually away from the chrome we sit above).
    public static let defaultHeight: CGFloat = 49.0

    // MARK: - Private state

    /// Horizontal stack — one arranged subview per segment. Distribution
    /// is `.fill` so segments keep their intrinsic / constraint-provided
    /// widths; `.search` segments are marked flex via a low content-hugging
    /// priority so they absorb remaining space.
    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.alignment = .center
        sv.distribution = .fill
        sv.spacing = 8.0
        return sv
    }()

    /// When no flex segment exists we want the strip to center horizontally
    /// inside the toolbar view (otherwise a narrow row of fixed-width
    /// segments sticks to the leading edge and reads as "stuck to the
    /// left"). This is done via leading/trailing >= sideInset + centerX.
    /// We flip between centering + edge-pinning by adjusting constraint
    /// priorities.
    private var leadingConstraint: Constraint?
    private var trailingConstraint: Constraint?
    private var centerXConstraint: Constraint?

    private var segmentViews: [UIView & ToolbarSegmentView] = []

    private var isEffectivelyDark: Bool {
        if let override = theme.isDarkOverride {
            return override
        }
        return traitCollection.userInterfaceStyle == .dark
    }

    // MARK: - Init

    public init(segments: [Segment] = [], theme: Theme = .light) {
        self.segments = segments
        self.theme = theme
        super.init(frame: .zero)
        backgroundColor = .clear
        setupStack()
        rebuild()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupStack() {
        addSubview(stackView)
        stackView.spacing = segmentSpacing
        stackView.snp.makeConstraints { make in
            // Vertically center the pill strip and clamp height to
            // `pillHeight` — the view itself can be taller (leaves room
            // above the pill for breathing space when the host frame is
            // padded), but the pill content stays a fixed height.
            make.centerY.equalToSuperview()
            make.height.equalTo(pillHeight)
            leadingConstraint = make.leading.greaterThanOrEqualToSuperview().offset(sideInset).constraint
            trailingConstraint = make.trailing.lessThanOrEqualToSuperview().offset(-sideInset).constraint
            centerXConstraint = make.centerX.equalToSuperview().constraint
        }
    }

    private func updateSideInsetConstraints() {
        leadingConstraint?.update(offset: sideInset)
        trailingConstraint?.update(offset: -sideInset)
    }

    private func relayoutAfterSizingChange() {
        stackView.snp.updateConstraints { make in
            make.height.equalTo(pillHeight)
        }
        for view in segmentViews {
            view.updateFixedSizing(pillHeight: pillHeight, pillButtonWidth: pillButtonWidth)
        }
    }

    // MARK: - Rebuild + theme

    private func rebuild() {
        segmentViews.forEach { $0.removeFromSuperview() }
        stackView.arrangedSubviews.forEach { stackView.removeArrangedSubview($0); $0.removeFromSuperview() }
        segmentViews.removeAll()

        var hasFlex = false
        for segment in segments {
            let view = makeSegmentView(for: segment)
            view.updateFixedSizing(pillHeight: pillHeight, pillButtonWidth: pillButtonWidth)
            stackView.addArrangedSubview(view)
            segmentViews.append(view)
            if case .search = segment { hasFlex = true }
            if case .spacer = segment { hasFlex = true }
        }

        // Centering on/off: when there's a flex segment (search), pin to
        // both edges so the flex grows; otherwise prefer centerX and let
        // the >= leading / <= trailing act as caps.
        if hasFlex {
            centerXConstraint?.deactivate()
            leadingConstraint?.activate()
            trailingConstraint?.activate()
            // Promote the inequality constraints to equalities by pinning
            // both edges — UIKit will still respect them as `>=` / `<=`,
            // but with centerX off the stack stretches between them.
            stackView.snp.remakeConstraints { make in
                make.centerY.equalToSuperview()
                make.height.equalTo(pillHeight)
                leadingConstraint = make.leading.equalToSuperview().offset(sideInset).constraint
                trailingConstraint = make.trailing.equalToSuperview().offset(-sideInset).constraint
            }
        } else {
            stackView.snp.remakeConstraints { make in
                make.centerY.equalToSuperview()
                make.height.equalTo(pillHeight)
                leadingConstraint = make.leading.greaterThanOrEqualToSuperview().offset(sideInset).constraint
                trailingConstraint = make.trailing.lessThanOrEqualToSuperview().offset(-sideInset).constraint
                centerXConstraint = make.centerX.equalToSuperview().constraint
            }
        }

        applyTheme()
        setNeedsLayout()
    }

    private func applyTheme() {
        for view in segmentViews {
            view.applyTheme(theme, isDark: isEffectivelyDark)
        }
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if theme.isDarkOverride == nil {
            applyTheme()
            setNeedsLayout()
        }
    }

    // MARK: - Factory

    private func makeSegmentView(for segment: Segment) -> UIView & ToolbarSegmentView {
        switch segment {
        case .pill(let buttons):
            return PillSegmentView(buttons: buttons)
        case .standalone(let button):
            return StandaloneSegmentView(button: button)
        case .search(let config):
            return SearchSegmentView(config: config)
        case .spacer:
            return SpacerSegmentView()
        }
    }
}

// MARK: - Segment view protocol

private protocol ToolbarSegmentView: UIView {
    func applyTheme(_ theme: AetherFloatingToolbarView.Theme, isDark: Bool)
    func updateFixedSizing(pillHeight: CGFloat, pillButtonWidth: CGFloat)
}

private final class SpacerSegmentView: UIView, ToolbarSegmentView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme(_ theme: AetherFloatingToolbarView.Theme, isDark: Bool) {
    }

    func updateFixedSizing(pillHeight: CGFloat, pillButtonWidth: CGFloat) {
    }
}

// MARK: - Standalone

private final class StandaloneSegmentView: UIView, ToolbarSegmentView {
    private let button: GlassBarButtonView
    private let item: AetherFloatingToolbarView.Button
    private var heightConstraint: Constraint?
    private var widthConstraint: Constraint?

    init(button: AetherFloatingToolbarView.Button) {
        self.item = button
        self.button = GlassBarButtonView(icon: button.icon, title: button.title, state: .glass)
        super.init(frame: .zero)
        addSubview(self.button)
        self.button.action = { _ in button.action() }
        self.button.isUserInteractionEnabled = button.isEnabled

        self.button.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        snp.makeConstraints { make in
            heightConstraint = make.height.equalTo(AetherFloatingToolbarView.defaultHeight).constraint
            widthConstraint = make.width.equalTo(AetherFloatingToolbarView.defaultHeight).constraint
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ theme: AetherFloatingToolbarView.Theme, isDark: Bool) {
        button.contentTintColor = item.isEnabled ? theme.iconColor : theme.disabledIconColor
        button.isDarkAppearance = theme.isDarkOverride
    }

    func updateFixedSizing(pillHeight: CGFloat, pillButtonWidth _: CGFloat) {
        heightConstraint?.update(offset: pillHeight)
        widthConstraint?.update(offset: pillHeight)
    }
}

// MARK: - Pill (multi-button)

/// Built on `GlassControlGroup` — a single shared glass capsule with
/// multiple `HighlightTrackingButton`s inside. That gives us one
/// continuous pill background (not five overlapping bubbles like an
/// `(GlassBackgroundContainerView + .generic)` stack produces) AND
/// per-button press tracking via `isInteractive` on the shared glass.
private final class PillSegmentView: UIView, ToolbarSegmentView {
    private let group: GlassControlGroup
    private let items: [AetherFloatingToolbarView.Button]
    private var currentTheme: AetherFloatingToolbarView.Theme = .light
    private var currentIsDark: Bool = false
    private var heightConstraint: Constraint?
    private var widthConstraint: Constraint?
    private var pillHeight: CGFloat = AetherFloatingToolbarView.defaultHeight
    private var pillButtonWidth: CGFloat = AetherFloatingToolbarView.defaultHeight

    init(buttons: [AetherFloatingToolbarView.Button]) {
        self.group = GlassControlGroup(style: .regular)
        self.items = buttons
        super.init(frame: .zero)
        addSubview(group)
        group.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        snp.makeConstraints { make in
            heightConstraint = make.height.equalTo(pillHeight).constraint
            widthConstraint = make.width.equalTo(naturalWidth()).constraint
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildGroup()
    }

    func applyTheme(_ theme: AetherFloatingToolbarView.Theme, isDark: Bool) {
        currentTheme = theme
        currentIsDark = isDark
        group.foregroundColor = theme.iconColor
        if let override = theme.isDarkOverride {
            group.isDarkAppearance = override
        }
        rebuildGroup()
    }

    func updateFixedSizing(pillHeight: CGFloat, pillButtonWidth: CGFloat) {
        self.pillHeight = pillHeight
        self.pillButtonWidth = pillButtonWidth
        heightConstraint?.update(offset: pillHeight)
        widthConstraint?.update(offset: naturalWidth())
    }

    private func naturalWidth() -> CGFloat {
        // Match `GlassControlGroup`'s internal item sizing — it clamps
        // each item to `max(minWidth, availableHeight)`, so any
        // `pillButtonWidth` smaller than `pillHeight` would leave empty
        // tail space inside the capsule.
        let perButton = max(pillHeight, pillButtonWidth)
        return max(pillHeight, CGFloat(items.count) * perButton)
    }

    private func rebuildGroup() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let theme = currentTheme
        let groupItems = items.enumerated().map { index, button -> GlassControlGroup.Item in
            let content: GlassControlGroup.Item.Content
            if let icon = button.icon {
                content = .icon(icon)
            } else if let title = button.title {
                content = .text(title)
            } else {
                content = .icon(UIImage())
            }
            return GlassControlGroup.Item(
                id: index,
                content: content,
                action: button.isEnabled ? button.action : nil
            )
        }
        _ = group.update(
            items: groupItems,
            background: .panel,
            preferClearGlass: false,
            foregroundColor: theme.iconColor,
            isDark: currentIsDark,
            availableHeight: bounds.height,
            minWidth: bounds.height,
            transition: .immediate
        )
        // GlassControlGroup sizes itself to its content — we want it to
        // FILL our bounds (the outer stack already allocated the right
        // width). Override the returned frame.
        group.frame = bounds
    }
}

// MARK: - Search

private final class SearchSegmentView: UIView, ToolbarSegmentView, UITextFieldDelegate {
    private let pill: GlassBackgroundView
    private let iconView: UIImageView
    private let textField: UITextField
    private let closeButton: GlassBarButtonView?
    private let config: AetherFloatingToolbarView.SearchConfig
    private var heightConstraint: Constraint?
    private var pillHeight: CGFloat = AetherFloatingToolbarView.defaultHeight

    init(config: AetherFloatingToolbarView.SearchConfig) {
        self.config = config
        self.pill = GlassBackgroundView(style: .regular)
        self.iconView = UIImageView(image: config.icon?.withRenderingMode(.alwaysTemplate))
        self.iconView.contentMode = .scaleAspectFit

        let tf = UITextField()
        tf.font = .systemFont(ofSize: 17)
        tf.placeholder = config.placeholder
        tf.text = config.text
        tf.tintColor = .systemBlue
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.clearButtonMode = .whileEditing
        tf.returnKeyType = .search
        self.textField = tf

        if config.showsCloseButton {
            let close = GlassBarButtonView(
                icon: UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)),
                title: nil,
                state: .glass
            )
            self.closeButton = close
        } else {
            self.closeButton = nil
        }

        super.init(frame: .zero)

        addSubview(pill)
        pill.addSubview(iconView)
        pill.addSubview(textField)
        if let close = closeButton {
            addSubview(close)
            close.action = { [weak self] _ in self?.config.onClose?() }
        }
        textField.delegate = self
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)

        setupConstraints()

        // Flex-width behavior: low content hugging + compression resistance
        // on horizontal axis lets the outer stack stretch us to fill the
        // remaining space. Vertical keeps default priorities so we don't
        // grow/shrink vertically.
        setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupConstraints() {
        let horizontalInset: CGFloat = 14
        let iconSize: CGFloat = 18
        let iconGap: CGFloat = 8

        let hasIcon = iconView.image != nil

        snp.makeConstraints { make in
            heightConstraint = make.height.equalTo(pillHeight).constraint
            // Minimum width so the search pill can't collapse to 0.
            make.width.greaterThanOrEqualTo(120.0)
        }

        if let close = closeButton {
            // close button is a trailing square sibling of the pill.
            close.snp.makeConstraints { make in
                make.top.bottom.trailing.equalToSuperview()
                make.width.equalTo(close.snp.height)
            }
            pill.snp.makeConstraints { make in
                make.top.leading.bottom.equalToSuperview()
                make.trailing.equalTo(close.snp.leading).offset(-8)
            }
        } else {
            pill.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        }

        iconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(horizontalInset)
            make.centerY.equalToSuperview()
            make.height.equalTo(iconSize)
            make.width.equalTo(hasIcon ? iconSize : 0)
        }
        iconView.isHidden = !hasIcon

        textField.snp.makeConstraints { make in
            if hasIcon {
                make.leading.equalTo(iconView.snp.trailing).offset(iconGap)
            } else {
                make.leading.equalToSuperview().offset(horizontalInset)
            }
            make.trailing.equalToSuperview().offset(-horizontalInset)
            make.top.bottom.equalToSuperview()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The pill's corner radius + glass tint depend on its current
        // bounds, which we only know after Auto Layout has run. Update
        // the glass background here (idempotent — `.immediate` transition
        // so no churn).
        pill.update(
            size: pill.bounds.size,
            cornerRadius: pill.bounds.height / 2,
            isDark: traitCollection.userInterfaceStyle == .dark,
            tintColor: .init(kind: .panel),
            isInteractive: true,
            isVisible: true,
            transition: .immediate
        )
    }

    @objc private func textDidChange() {
        config.onTextChanged?(textField.text ?? "")
    }

    func applyTheme(_ theme: AetherFloatingToolbarView.Theme, isDark _: Bool) {
        iconView.tintColor = theme.placeholderColor
        textField.textColor = theme.textColor
        textField.attributedPlaceholder = NSAttributedString(
            string: config.placeholder,
            attributes: [.foregroundColor: theme.placeholderColor]
        )
        closeButton?.contentTintColor = theme.iconColor
        closeButton?.isDarkAppearance = theme.isDarkOverride
    }

    func updateFixedSizing(pillHeight: CGFloat, pillButtonWidth _: CGFloat) {
        self.pillHeight = pillHeight
        heightConstraint?.update(offset: pillHeight)
    }
}
