import AppKit
import NotebookKit
import os
import QuickLookUI
import WebKit

private let logger = Logger(subsystem: "me.kcpr.juprev.quicklook", category: "preview")

/// View-based Quick Look preview hosting its own WKWebView.
///
/// Data-based HTML previews ignore the page's Content-Security-Policy, so notebook HTML
/// could run scripts inside Finder previews. Owning the web view lets us switch JavaScript
/// off entirely and block every network load (see `NotebookWebView`).
final class PreviewViewController: NSViewController, QLPreviewingController {
    private var webView: WKWebView?
    private var loadWaiter: LoadWaiter?

    // Creating a renderer loads the JS bundle (~25 ms), so keep one per extension process.
    // NotebookRenderer isn't thread-safe and previews may be requested concurrently.
    private static let lock = NSLock()
    private static var sharedRenderer: NotebookRenderer?

    private static func render(_ url: URL) -> (html: String, summary: String) {
        lock.lock()
        defer { lock.unlock() }
        // Read on every preview so changes made in the app apply without restarting Quick Look.
        // Quick Look never loads remote content, whatever the app's setting says.
        let options = RenderOptions(settings: JuPrevSettings.load(), remoteImages: false)
        do {
            if sharedRenderer == nil { sharedRenderer = try NotebookRenderer() }
            let result = try sharedRenderer!.render(fileURL: url, options: options)
            return (result.html, "\(result.cellCount) cells, \(result.html.utf8.count / 1024) KB, images: \(options.localImages.rawValue)")
        } catch {
            logger.error("failed \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return (NotebookRenderer.errorPage(title: url.lastPathComponent, message: error.localizedDescription, themeCSS: options.themeCSS), "error page")
        }
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 1100))
        preferredContentSize = view.frame.size
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let start = Date()
        let rendered = await Task.detached(priority: .userInitiated) { Self.render(url) }.value
        let renderedAt = Date()

        // Quick Look may reuse this controller for the next file (arrowing through files in
        // the preview panel): replace the previous page rather than stacking web views.
        self.webView?.removeFromSuperview()
        self.webView = nil
        loadWaiter?.finish(CancellationError()) // an overlapping call for the previous file

        // Fails closed: without the network-blocking rules there is no preview.
        let webView = WKWebView(frame: view.bounds, configuration: try await NotebookWebView.makeConfiguration(.static(remoteImages: false)))
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground") // no white flash in dark mode before the page paints
        view.addSubview(webView)
        self.webView = webView

        // Return once WebKit commits the page and starts painting: Quick Look never shows a
        // blank view, and large notebooks appear progressively instead of after a full load.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadWaiter = LoadWaiter(continuation)
            webView.loadHTMLString(rendered.html, baseURL: nil)
        }
        let ms = { (a: Date, b: Date) in Int(b.timeIntervalSince(a) * 1000) }
        logger.notice("""
            previewed \(url.lastPathComponent, privacy: .public) (\(rendered.summary, privacy: .public)): \
            render \(ms(start, renderedAt)) ms, shown after \(ms(start, Date())) ms
            """)
    }
}

extension PreviewViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        switch NotebookWebView.decision(for: action) {
        case .allow: decisionHandler(.allow)
        case .cancel: decisionHandler(.cancel)
        case .openExternally(let url):
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        loadWaiter?.finish(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadWaiter?.finish(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadWaiter?.finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadWaiter?.finish(error)
    }
}

/// Resumes the preparePreviewOfFile continuation exactly once.
private final class LoadWaiter {
    private var continuation: CheckedContinuation<Void, Error>?
    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
    func finish(_ error: Error?) {
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
        continuation = nil
    }
}
