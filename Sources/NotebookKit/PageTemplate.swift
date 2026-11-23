import Foundation

/// Wraps rendered cells in a self-contained HTML document.
enum PageTemplate {
    /// Static pages may load nothing: no scripts, no network, no frames.
    /// Everything they need (images, fonts) is inlined as `data:` URIs.
    static let staticCSP = "default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'"
    static let staticRemoteImagesCSP = "default-src 'none'; img-src data: https:; font-src data:; style-src 'unsafe-inline'"

    /// With scripts allowed, outputs typically pull libraries (Plotly, Bokeh…) from CDNs.
    static let scriptsCSP = "default-src 'none'; img-src data: https:; font-src data: https:; style-src 'unsafe-inline' https:; script-src 'unsafe-inline' 'unsafe-eval' https:; connect-src https:"

    static func csp(for options: RenderOptions) -> String {
        options.allowScripts ? scriptsCSP : options.remoteImages ? staticRemoteImagesCSP : staticCSP
    }

    /// Classes on <html> that hide parts of the notebook (see notebook.css).
    static func htmlClasses(showCode: Bool, showOutputs: Bool) -> String {
        [showCode ? nil : "hide-code", showOutputs ? nil : "hide-outputs"].compactMap { $0 }.joined(separator: " ")
    }

    static func document(title: String, body: String, options: RenderOptions) -> String {
        """
        <!doctype html>
        <html class="\(htmlClasses(showCode: options.showCode, showOutputs: options.showOutputs))">
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp(for: options))">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(escape(title))</title>
        <style>\(NotebookRenderer.stylesheet)</style>
        </head>
        <body>
        <main class="notebook">
        \(body)
        </main>
        </body>
        </html>
        """
    }

    static func errorDocument(title: String, message: String) -> String {
        document(
            title: title,
            body: """
            <div class="render-error">
            <h1>\(escape(title))</h1>
            <p>\(escape(message))</p>
            </div>
            """,
            options: RenderOptions()
        )
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
