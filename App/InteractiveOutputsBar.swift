import AppKit

/// The strip above a notebook that has interactive outputs (widgets, Plotly, Bokeh…):
/// explains why they're static and lets the user allow scripts for this window.
final class InteractiveOutputsBar: NSView {
    var onToggleScripts: (() -> Void)?

    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        icon.imageScaling = .scaleProportionallyDown
        icon.setContentHuggingPriority(.required, for: .horizontal)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.target = self
        button.action = #selector(buttonClicked)
        button.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [icon, label, button])
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

    func update(interactiveOutputs: Int, scriptsAllowed: Bool) {
        isHidden = interactiveOutputs == 0 && !scriptsAllowed
        if scriptsAllowed {
            icon.image = NSImage(systemSymbolName: "exclamationmark.shield", accessibilityDescription: "Scripts allowed")
            icon.contentTintColor = .systemOrange
            label.stringValue = "Scripts are allowed in this window. Interactive outputs can run code and load content from the internet."
            button.title = "Block Scripts"
        } else {
            let outputs = interactiveOutputs == 1 ? "1 interactive output" : "\(interactiveOutputs) interactive outputs"
            icon.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Scripts blocked")
            icon.contentTintColor = .secondaryLabelColor
            label.stringValue = "This notebook has \(outputs). Scripts are blocked, so static versions are shown where the notebook saved one."
            button.title = "Allow Scripts"
        }
    }

    @objc private func buttonClicked() { onToggleScripts?() }
}
