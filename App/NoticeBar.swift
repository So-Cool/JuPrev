import AppKit

/// A strip above the notebook: an icon, a short explanation and buttons. Used for
/// interactive outputs ("Allow Scripts") and for images the settings left out ("Load Once").
final class NoticeBar: NSView {
    struct Action {
        let title: String
        let perform: () -> Void
    }

    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let buttons = NSStackView()
    private var actions: [Action] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isHidden = true

        icon.imageScaling = .scaleProportionallyDown
        icon.setContentHuggingPriority(.required, for: .horizontal)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttons.orientation = .horizontal
        buttons.spacing = 6
        buttons.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [icon, label, buttons])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: separator.topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    func show(symbol: String, tint: NSColor, message: String, actions: [Action]) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = tint
        label.stringValue = message
        self.actions = actions
        buttons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, action) in actions.enumerated() {
            let button = NSButton(title: action.title, target: self, action: #selector(buttonClicked(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.tag = index
            buttons.addArrangedSubview(button)
        }
        isHidden = false
    }

    func hide() { isHidden = true }

    @objc private func buttonClicked(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag].perform()
    }
}
