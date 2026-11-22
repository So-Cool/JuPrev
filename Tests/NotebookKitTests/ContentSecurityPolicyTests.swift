import Foundation
import Testing
import WebKit
@testable import NotebookKit

/// Loads Fixtures/csp-probe.ipynb in a real WKWebView. Every probe in it inserts a
/// "SCRIPT RAN: …" banner if it executes. Two independent layers must each stop them all:
/// the page's CSP (for browsers, e.g. exported HTML) and `NotebookWebView`'s JavaScript-off
/// configuration (for Quick Look, whose data-based previews ignore CSP).
@MainActor
@Suite(.serialized)
struct ContentSecurityPolicyTests {
    final class LoadWaiter: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Error>?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    /// Loads the page and returns its visible text once handlers had a moment to fire.
    func visibleText(of html: String, configuration: WKWebViewConfiguration = WKWebViewConfiguration()) async throws -> String {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let waiter = LoadWaiter()
        webView.navigationDelegate = waiter
        try await withCheckedThrowingContinuation { continuation in
            waiter.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
        try await Task.sleep(for: .milliseconds(300)) // onload/ontoggle fire after didFinish
        // Scripts injected by the host aren't subject to the page's CSP.
        return try await webView.evaluateJavaScript("document.body.innerText") as? String ?? ""
    }

    func probePage() throws -> String {
        try NotebookRenderer().render(fileURL: fixtures.appendingPathComponent("csp-probe.ipynb")).html
    }

    @Test func staticPageBlocksEveryProbe() async throws {
        let text = try await visibleText(of: probePage())
        #expect(text.contains("CSP probe"), "page loaded")
        #expect(!text.contains("SCRIPT RAN:"), "a probe executed:\n\(text)")
    }

    func pageWithoutCSP() throws -> String {
        try probePage()
            .split(separator: "\n")
            .filter { !$0.contains("Content-Security-Policy") }
            .joined(separator: "\n")
    }

    @Test func staticWebViewBlocksEveryProbeEvenWithoutCSP() async throws {
        let text = try await visibleText(of: pageWithoutCSP(), configuration: NotebookWebView.makeConfiguration(.static(remoteImages: false)))
        #expect(text.contains("CSP probe"), "page loaded")
        #expect(!text.contains("SCRIPT RAN:"), "a probe executed:\n\(text)")
    }

    @Test(arguments: [false, true])
    func networkRulesCompile(remoteImages: Bool) async throws {
        _ = try await NotebookWebView.contentRules(remoteImages: remoteImages)
    }

    @Test func remoteImagesModeStillBlocksScripts() async throws {
        let text = try await visibleText(of: pageWithoutCSP(), configuration: NotebookWebView.makeConfiguration(.static(remoteImages: true)))
        #expect(!text.contains("SCRIPT RAN:"), "a probe executed:\n\(text)")
    }

    /// Positive control: with neither layer the same probes do run, so the tests above are meaningful.
    @Test func probesRunWithoutThePolicy() async throws {
        let text = try await visibleText(of: pageWithoutCSP())
        #expect(text.contains("SCRIPT RAN: markdown script"))
        #expect(text.contains("SCRIPT RAN: svg onload"))
    }
}
