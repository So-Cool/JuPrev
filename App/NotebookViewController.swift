import AppKit
import NotebookKit
import os
import WebKit

private let logger = Logger(subsystem: "me.kcpr.juprev", category: "viewer")

/// Shows one rendered notebook, with the interactive-outputs bar above it.
final class NotebookViewController: NSViewController {
    private weak var document: NotebookDocument?
    private let bar = InteractiveOutputsBar()
    private let findBar = FindBar()
    private let webContainer = NSView()
    private var webView: WKWebView?
    private var webViewMode: NotebookWebView.Mode?

    /// Per window and never remembered, like Jupyter's per-session trust.
    private var scriptsAllowed = false
    private var pageZoom: CGFloat = 1
    private var renderTask: Task<Void, Never>?
    private var pendingScrollY: Double?

    init(document: NotebookDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
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
        let options = RenderOptions(settings: JuPrevSettings.load(), allowScripts: scriptsAllowed)

        let html: String
        let interactiveOutputs: Int
        switch await RenderService.shared.render(document.contents, fileURL: document.fileURL, options: options) {
        case .success(let rendered):
            html = rendered.html
            interactiveOutputs = rendered.interactiveOutputs
        case .failure(let error):
            html = NotebookRenderer.errorPage(title: document.displayName, message: error.localizedDescription)
            interactiveOutputs = 0
        }
        guard !Task.isCancelled else { return }

        let mode: NotebookWebView.Mode = scriptsAllowed ? .scriptsAllowed : .static(remoteImages: options.remoteImages)
        guard let webView = await webView(for: mode) else { return }
        guard !Task.isCancelled else { return }

        logger.notice("rendered \(document.displayName, privacy: .public): \(html.utf8.count / 1024) KB")
        bar.update(interactiveOutputs: interactiveOutputs, scriptsAllowed: scriptsAllowed)
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
