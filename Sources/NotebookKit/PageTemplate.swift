import Foundation

/// Wraps rendered cells in a self-contained HTML document.
enum PageTemplate {
    /// Static pages may load nothing: no scripts, no network, no frames.
    /// Everything they need (images, fonts) is inlined as `data:` URIs.
    static let staticCSP = "default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'"

    /// With scripts allowed, outputs typically pull libraries (Plotly, Bokeh…) from CDNs.
    static let scriptsCSP = "default-src 'none'; img-src data: https:; font-src data: https:; style-src 'unsafe-inline' https:; script-src 'unsafe-inline' 'unsafe-eval' https:; connect-src https:"

    static func document(title: String, body: String, allowScripts: Bool) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(allowScripts ? scriptsCSP : staticCSP)">
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

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
