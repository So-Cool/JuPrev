import AppKit
import WebKit

/// Find in page, on WKWebView's find API (which selects each match and scrolls to it).
/// NSTextFinder can drive a WKWebView, but outside WebKit's own container it lost track
/// of the scroll position and of repeated searches.
final class FindBar: NSView, NSSearchFieldDelegate {
    weak var webView: WKWebView?
    var onClose: (() -> Void)?

    private let field = NSSearchField()
    private let count = NSTextField(labelWithString: "")
    private let navigation = NSSegmentedControl()
    private var query = ""
    private var matches = 0
    private var current = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        field.placeholderString = "Find in notebook"
        field.sendsSearchStringImmediately = true
        field.delegate = self
        field.target = self
        field.action = #selector(searchChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)

        count.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        count.setContentHuggingPriority(.required, for: .horizontal)

        navigation.segmentCount = 2
        navigation.trackingMode = .momentary
        navigation.setImage(NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous"), forSegment: 0)
        navigation.setImage(NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next"), forSegment: 1)
        navigation.target = self
        navigation.action = #selector(navigate(_:))

        let done = NSButton(title: "Done", target: self, action: #selector(close))
        done.bezelStyle = .rounded
        done.controlSize = .small

        let stack = NSStackView(views: [field, count, navigation, done])
        stack.orientation = .horizontal
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
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }

    // MARK: Actions

    func show() {
        isHidden = false
        setFindingClass(true)
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    @objc func close() {
        isHidden = true
        setFindingClass(false)
        onClose?()
    }

    /// Lets the page style found text (see `html.finding` in notebook.css).
    private func setFindingClass(_ on: Bool) {
        webView?.evaluateJavaScript("document.documentElement.classList.toggle('finding', \(on))")
    }

    func findNext() { step(backwards: false) }
    func findPrevious() { step(backwards: true) }

    /// ⌘E: search for the page's current selection.
    func useSelection() {
        webView?.evaluateJavaScript("window.getSelection().toString()") { [weak self] result, _ in
            guard let self, let text = result as? String, !text.isEmpty else { return }
            self.field.stringValue = text
            self.searchChanged()
        }
    }

    /// After a re-render the old matches are gone; search again from the top.
    func contentDidChange() {
        guard !isHidden else { return }
        setFindingClass(true)
        guard !query.isEmpty else { return }
        query = ""
        searchChanged()
    }

    @objc private func searchChanged() {
        let text = field.stringValue
        guard text != query else { return }
        query = text
        current = 0
        guard !text.isEmpty else {
            matches = 0
            updateCount()
            webView?.evaluateJavaScript("window.getSelection().removeAllRanges()")
            return
        }
        countMatches(of: text) { [weak self] n in
            self?.matches = n
            self?.step(backwards: false)
        }
    }

    @objc private func navigate(_ sender: NSSegmentedControl) {
        step(backwards: sender.selectedSegment == 0)
    }

    private func step(backwards: Bool) {
        if query.isEmpty, !field.stringValue.isEmpty { searchChanged(); return }
        guard let webView, !query.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(query, configuration: configuration) { [weak self] result in
            guard let self else { return }
            if result.matchFound, self.matches > 0 {
                self.current = backwards
                    ? (self.current <= 1 ? self.matches : self.current - 1)
                    : (self.current >= self.matches ? 1 : self.current + 1)
            }
            self.updateCount()
        }
    }

    /// Counts case-insensitive occurrences in the page text. Host-evaluated script, so it
    /// runs even though the page's own JavaScript is disabled.
    private func countMatches(of text: String, completion: @escaping (Int) -> Void) {
        let script = "(document.body.innerText.toLowerCase().split(needle.toLowerCase()).length - 1)"
        webView?.callAsyncJavaScript("return \(script)", arguments: ["needle": text], in: nil, in: .page) { result in
            completion((try? result.get()) as? Int ?? 0)
        }
    }

    private func updateCount() {
        count.stringValue = query.isEmpty ? "" : matches == 0 ? "Not found" : "\(current) of \(matches)"
        count.textColor = !query.isEmpty && matches == 0 ? .systemRed : .secondaryLabelColor
    }

    // MARK: Keys in the search field

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            if query != field.stringValue { searchChanged() } else { step(backwards: shift) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }
}
