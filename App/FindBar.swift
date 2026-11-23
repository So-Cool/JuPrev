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

    /// After a re-render (live reload, settings) the selection is gone: recount, and
    /// continue the next search from the top of what's on screen, not from the top of the page.
    func contentDidChange() {
        guard !isHidden else { return }
        setFindingClass(true)
        guard !query.isEmpty else { return }
        placeCaretAtTopOfView { [weak self] in self?.refreshState() }
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
        // A new search starts from the top.
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges()") { [weak self] _, _ in
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
        // WebKit's find continues from the page's selection (the last match, or the caret
        // contentDidChange left at the top of the view).
        webView.find(query, configuration: configuration) { [weak self] _ in
            self?.refreshState()
        }
    }

    /// Puts an empty selection at the top of what's on screen, so the next search
    /// continues from where the reader is.
    private func placeCaretAtTopOfView(then completion: @escaping () -> Void) {
        let script = """
            const r = document.caretRangeFromPoint(Math.min(innerWidth / 2, 200), 40);
            const s = getSelection();
            s.removeAllRanges();
            if (r) s.addRange(r);
            """
        webView?.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { _ in completion() }
    }

    /// Updates "N of M" from the page: matches in the visible text (hidden code or outputs
    /// excluded, as WebKit's find skips them) and which one is selected. Host-evaluated
    /// script, so it runs even though the page's own JavaScript is disabled.
    private func refreshState() {
        let script = """
            const n = needle.toLowerCase();
            const count = (t) => t.toLowerCase().split(n).length - 1;
            const sel = getSelection();
            const at = sel.rangeCount ? sel.getRangeAt(0) : null;
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
                acceptNode: (t) => t.parentElement && t.parentElement.offsetParent !== null
                    ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT,
            });
            let text = "", before = null;
            for (let t; (t = walker.nextNode());) {
                if (at && before === null) {
                    if (t === at.startContainer) before = text + t.data.slice(0, at.startOffset);
                    else if (at.comparePoint(t, 0) > 0) before = text;
                }
                text += t.data;
            }
            const selected = at !== null && sel.toString().toLowerCase() === n;
            return { total: count(text), index: before === null ? 0 : count(before) + (selected ? 1 : 0) };
            """
        webView?.callAsyncJavaScript(script, arguments: ["needle": query], in: nil, in: .page) { [weak self] result in
            guard let self, case .success(let value) = result, let state = value as? [String: Any] else { return }
            self.matches = state["total"] as? Int ?? 0
            self.current = min(state["index"] as? Int ?? 0, self.matches)
            self.updateCount()
        }
    }

    private func updateCount() {
        count.stringValue = query.isEmpty ? ""
            : matches == 0 ? "Not found"
            : current == 0 ? (matches == 1 ? "1 match" : "\(matches) matches")
            : "\(current) of \(matches)"
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
