import AppKit
import NotebookKit
import os
import UniformTypeIdentifiers
import WebKit

private let logger = Logger(subsystem: "me.kcpr.juprev", category: "viewer")

/// Shows one rendered notebook, with the interactive-outputs bar above it.
final class NotebookViewController: NSViewController {
    private weak var document: NotebookDocument?
    private let outline: OutlineModel
    private var sectionTimer: Timer?
    /// A heading the user picked, kept highlighted until they scroll away from where
    /// the jump landed (near the end, a jump can't bring the heading to the top).
    private var pickedHeading: (id: String, scrollY: Double?)?
    private let bar = InteractiveOutputsBar()
    private let findBar = FindBar()
    private let webContainer = NSView()
    private var webView: WKWebView?
    private var webViewMode: NotebookWebView.Mode?

    /// Per window and never remembered, like Jupyter's per-session trust.
    private var scriptsAllowed = false
    /// Set once the user toggles View ▸ Show Code / Show Outputs in this window;
    /// until then the window follows the global setting.
    private var showCodeOverride: Bool?
    private var showOutputsOverride: Bool?
    private var showStderrOverride: Bool?

    var showCode: Bool { showCodeOverride ?? JuPrevSettings.load().showCode }
    var showOutputs: Bool { showOutputsOverride ?? JuPrevSettings.load().showOutputs }
    var showStderr: Bool { showStderrOverride ?? JuPrevSettings.load().showStderr }
    private var pageZoom: CGFloat = 1
    private var renderTask: Task<Void, Never>?
    private var pendingScrollY: Double?

    init(document: NotebookDocument, outline: OutlineModel) {
        self.document = document
        self.outline = outline
        super.init(nibName: nil, bundle: nil)
        outline.onSelect = { [weak self] id in self?.scrollToHeading(id) }
    }

    /// Track the current section only while the outline is on screen.
    var outlineVisible = false {
        didSet { updateSectionTracking() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .width
        stack.addArrangedSubview(bar)
        stack.addArrangedSubview(findBar)
        stack.addArrangedSubview(webContainer)
        webContainer.setContentHuggingPriority(.defaultLow, for: .vertical)
        bar.isHidden = true
        bar.onToggleScripts = { [weak self] in self?.toggleScripts() }
        findBar.isHidden = true
        findBar.onClose = { [weak self] in
            guard let self, let webView = self.webView else { return }
            self.view.window?.makeFirstResponder(webView)
        }
        view = stack
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 1000)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        sectionTimer?.invalidate()
        sectionTimer = nil
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateSectionTracking()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(forName: .juprevSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.reload(preservingScroll: true)
        }
        NotificationCenter.default.addObserver(forName: NotebookDocument.contentsDidChange, object: document, queue: .main) { [weak self] _ in
            self?.reload(preservingScroll: true)
        }
        reload(preservingScroll: false)
    }

    // MARK: Rendering

    func reload(preservingScroll: Bool) {
        renderTask?.cancel()
        renderTask = Task { @MainActor [weak self] in
            await self?.render(preservingScroll: preservingScroll)
        }
    }

    private func render(preservingScroll: Bool) async {
        guard let document else { return }
        let scrollY = preservingScroll ? await currentScrollY() : nil
        let options = RenderOptions(
            settings: JuPrevSettings.load(),
            allowScripts: scriptsAllowed,
            showCode: showCodeOverride,
            showOutputs: showOutputsOverride,
            showStderr: showStderrOverride
        )

        let html: String
        let interactiveOutputs: Int
        let headings: [NotebookHeading]
        switch await RenderService.shared.render(document.contents, fileURL: document.fileURL, options: options) {
        case .success(let rendered):
            html = rendered.html
            interactiveOutputs = rendered.interactiveOutputs
            headings = rendered.headings
        case .failure(let error):
            html = NotebookRenderer.errorPage(title: document.displayName, message: error.localizedDescription, themeCSS: options.themeCSS)
            interactiveOutputs = 0
            headings = []
        }
        guard !Task.isCancelled else { return }

        let mode: NotebookWebView.Mode = scriptsAllowed ? .scriptsAllowed : .static(remoteImages: options.remoteImages)
        guard let webView = await webView(for: mode) else { return }
        guard !Task.isCancelled else { return }

        logger.notice("rendered \(document.displayName, privacy: .public): \(html.utf8.count / 1024) KB")
        bar.update(interactiveOutputs: interactiveOutputs, scriptsAllowed: scriptsAllowed)
        if outline.headings != headings { outline.headings = headings }
        pendingScrollY = scrollY
        webView.loadHTMLString(html, baseURL: nil)
    }

    /// Reuses the web view unless the mode changed: WebKit settings and content rules are
    /// fixed when a web view is created.
    private func webView(for mode: NotebookWebView.Mode) async -> WKWebView? {
        if let webView, webViewMode == mode { return webView }
        let configuration: WKWebViewConfiguration
        do {
            configuration = try await NotebookWebView.makeConfiguration(mode)
        } catch {
            // Fail closed: never show notebook content without the network-blocking rules.
            logger.error("web view configuration failed: \(error.localizedDescription, privacy: .public)")
            presentError(error)
            return nil
        }
        self.webView?.removeFromSuperview()
        let webView = WKWebView(frame: webContainer.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.pageZoom = pageZoom
        webView.setValue(false, forKey: "drawsBackground") // no white flash in dark mode
        webContainer.addSubview(webView)
        findBar.webView = webView
        self.webView = webView
        webViewMode = mode
        return webView
    }

    private func currentScrollY() async -> Double? {
        // Host-evaluated JavaScript runs even when the page's own scripts are disabled.
        try? await webView?.evaluateJavaScript("window.scrollY") as? Double
    }

    private func toggleScripts() {
        scriptsAllowed.toggle()
        reload(preservingScroll: true)
    }

    // MARK: Find

    /// Edit ▸ Find items carry NSTextFinder.Action values as tags.
    func runFindAction(_ sender: Any?) {
        guard let tag = (sender as? NSValidatedUserInterfaceItem)?.tag,
              let action = NSTextFinder.Action(rawValue: tag) else { return }
        switch action {
        case .showFindInterface: findBar.show()
        case .nextMatch: findBar.findNext()
        case .previousMatch: findBar.findPrevious()
        case .setSearchString: findBar.useSelection()
        default: break
        }
    }

    var canFind: Bool { webView != nil }

    // MARK: Outline

    private func scrollToHeading(_ id: String) {
        pickedHeading = (id, nil)
        webView?.callAsyncJavaScript(
            "document.getElementById(id)?.scrollIntoView({ block: 'start' })",
            arguments: ["id": id], in: nil, in: .page
        )
    }

    private func updateSectionTracking() {
        sectionTimer?.invalidate()
        sectionTimer = nil
        guard outlineVisible else { return }
        sectionTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.updateCurrentSection()
        }
    }

    /// The last outline heading scrolled past a line near the top of the window.
    /// (Polled: the page's own scripts are off, so it can't report scrolling itself.)
    private func updateCurrentSection() {
        guard let webView, view.window?.isVisible == true, !outline.headings.isEmpty else { return }
        let script = """
            // A heading becomes current once it scrolls above `line`. Over the last screenful
            // the line slides down the window, so headings too close to the end to reach the
            // top still take their turn, in order.
            const height = window.innerHeight;
            const remaining = document.documentElement.scrollHeight - (window.scrollY + height);
            const progress = Math.max(0, Math.min(1, 1 - remaining / height));
            const line = 80 + (height - 120) * progress;
            let current = null;
            for (const h of document.querySelectorAll('.cell.markdown :is(h1, h2, h3, h4, h5, h6)[id]')) {
                if (h.getBoundingClientRect().top > line) break;
                current = h.id;
            }
            return { current, scrollY: window.scrollY };
            """
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self, case .success(let value) = result,
                  let state = value as? [String: Any], let scrollY = state["scrollY"] as? Double else { return }
            if let picked = self.pickedHeading {
                if picked.scrollY == nil || picked.scrollY == scrollY {
                    self.pickedHeading = (picked.id, scrollY)
                    return
                }
                self.pickedHeading = nil
            }
            let id = state["current"] as? String ?? self.outline.headings.first?.id
            if self.outline.current != id { self.outline.current = id }
        }
    }

    // MARK: Export and print

    private var exportName: String {
        document?.fileURL?.deletingPathExtension().lastPathComponent ?? document?.displayName ?? "Notebook"
    }

    /// The static page as shown (code/outputs choices, images), never with scripts.
    func exportHTML() {
        guard let window = view.window, let document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = exportName + ".html"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let options = RenderOptions(
                    settings: JuPrevSettings.load(),
                    showCode: self.showCode, showOutputs: self.showOutputs, showStderr: self.showStderr
                )
                do {
                    let rendered = try await RenderService.shared.render(document.contents, fileURL: document.fileURL, options: options).get()
                    try Data(rendered.html.utf8).write(to: url, options: .atomic)
                } catch {
                    self.presentError(error)
                }
            }
        }
    }

    func exportPDF() {
        guard let window = view.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = exportName + ".pdf"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let info = self.printInfo()
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            self.runPrintOperation(info, showPanels: false)
        }
    }

    func printNotebook() {
        runPrintOperation(printInfo(), showPanels: true)
    }

    private func printInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        for edge in [\NSPrintInfo.topMargin, \.bottomMargin, \.leftMargin, \.rightMargin] {
            info[keyPath: edge] = 42 // ~15 mm
        }
        return info
    }

    /// WKWebView's print operation must be run modally for a window (not with `run()`)
    /// and needs its view sized, or it produces blank pages.
    private func runPrintOperation(_ info: NSPrintInfo, showPanels: Bool) {
        guard let webView, let window = view.window else { return }
        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds
        operation.jobTitle = exportName
        operation.showsPrintPanel = showPanels
        operation.showsProgressPanel = true
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: Show code / outputs

    func toggleCode() {
        showCodeOverride = !showCode
        setPageClass("hide-code", !showCode)
    }

    func toggleOutputs() {
        showOutputsOverride = !showOutputs
        setPageClass("hide-outputs", !showOutputs)
    }

    func toggleStderr() {
        showStderrOverride = !showStderr
        setPageClass("hide-stderr", !showStderr)
    }

    /// Instant: flips a class on the page instead of re-rendering.
    private func setPageClass(_ name: String, _ on: Bool) {
        webView?.evaluateJavaScript("document.documentElement.classList.toggle('\(name)', \(on))")
    }

    // MARK: Zoom

    func zoom(to zoom: CGFloat) {
        pageZoom = min(max(zoom, 0.5), 3)
        webView?.pageZoom = pageZoom
    }

    func zoom(by factor: CGFloat) { zoom(to: pageZoom * factor) }
}

extension NotebookViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        switch NotebookWebView.decision(for: action) {
        case .allow: decisionHandler(.allow)
        case .cancel: decisionHandler(.cancel)
        case .openExternally(let url):
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        findBar.contentDidChange()
        guard let y = pendingScrollY else { return }
        pendingScrollY = nil
        webView.evaluateJavaScript("window.scrollTo(0, \(y))")
    }
}

extension Notification.Name {
    static let juprevSettingsDidChange = Notification.Name("JuPrevSettingsDidChange")
}
